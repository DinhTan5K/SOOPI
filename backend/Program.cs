using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.DataAccess.Dao;
using SoopiFoodBE.DataAccess.Repositories;
using SoopiFoodBE.Services;
using Soopi.Backend.Services;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.Hubs;
using Microsoft.AspNetCore.SignalR;

// Enable legacy timestamp behavior in Npgsql to allow timestamps with offsets
AppContext.SetSwitch("Npgsql.EnableLegacyTimestampBehavior", true);
System.Globalization.CultureInfo.DefaultThreadCurrentCulture = System.Globalization.CultureInfo.InvariantCulture;
System.Globalization.CultureInfo.DefaultThreadCurrentUICulture = System.Globalization.CultureInfo.InvariantCulture;

var builder = WebApplication.CreateBuilder(args);
builder.Configuration.AddJsonFile("appsettings.Local.json", optional: true, reloadOnChange: true)
    .AddEnvironmentVariables().AddCommandLine(args);
builder.Services.AddHttpContextAccessor();
builder.Services.AddAuthorization();
builder.Services.AddScoped<CurrentAccount>();
builder.Services.AddScoped<RestaurantManagement>();
builder.Services.AddScoped<VoucherService>();
builder.Services.AddProblemDetails();

// Controllers & JSON configuration (tránh lỗi circular reference)
builder.Services.AddSignalR();
builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.ReferenceHandler = System.Text.Json.Serialization.ReferenceHandler.IgnoreCycles;
    });

// Memory Cache (lưu OTP và Rate Limiting chống spam)
builder.Services.AddMemoryCache();

// Database (PostgreSQL - SoopiDbContext)
var connectionString = builder.Configuration.GetConnectionString("SoopiFood")
    ?? builder.Configuration.GetConnectionString("DefaultConnection")
    ?? "Host=localhost;Port=5432;Database=soopi;Username=postgres;Password=12345";

builder.Services.AddDbContext<SoopiDbContext>(options =>
    options.UseNpgsql(connectionString));

// Dependency Injection (DataAccess DAO, Repositories & Services)
builder.Services.AddScoped(typeof(IEntityDao<>), typeof(EfEntityDao<>));
builder.Services.AddScoped<IUserRepository, UserRepository>();
builder.Services.AddScoped<IRestaurantRepository, RestaurantRepository>();
builder.Services.AddScoped<IOrderRepository, OrderRepository>();
builder.Services.AddScoped<IUserService, UserService>();
builder.Services.AddScoped<IUserProfileService, UserProfileService>();
builder.Services.AddScoped<IRestaurantService, RestaurantService>();
builder.Services.AddScoped<IOrderService, OrderService>();
builder.Services.AddScoped<IReviewService, ReviewService>();
builder.Services.AddScoped<IImageUploadService, ImageUploadService>();
builder.Services.AddScoped<IEmailService, EmailService>();
builder.Services.AddScoped<IOtpService, OtpService>();

// Driver Location, Matching Engine & Dispatch Background Worker
builder.Services.AddSingleton<IDriverLocationService, InMemoryDriverLocationService>();
builder.Services.AddSingleton<IDriverOfferManager, DriverOfferManager>();
builder.Services.AddSingleton<IOrderDispatchQueue, OrderDispatchQueue>();
builder.Services.AddHostedService<OrderDispatchWorker>();

// Firebase Authentication (JWT Bearer)
var firebaseProjectId = builder.Configuration["Firebase:ProjectId"] ?? "soopi-food";
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = $"https://securetoken.google.com/{firebaseProjectId}";
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = $"https://securetoken.google.com/{firebaseProjectId}",
            ValidateAudience = true,
            ValidAudience = firebaseProjectId,
            ValidateLifetime = true
        };
    });

// CORS (Cho phép kết nối từ Flutter Emulator, Web, LAN thiết bị thật)
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", policy =>
    {
        policy.SetIsOriginAllowed(origin => true)
              .AllowCredentials()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

// Swagger & OpenAPI with Bearer Auth definition
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.OperationFilter<ManagementExamples>();
    c.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "SOOPI FOOD API",
        Version = "v1",
        Description = "Backend API cho ứng dụng SOOPI FOOD (.NET 8 + PostgreSQL + Firebase Auth + Cloudinary)"
    });

    c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Description = "Nhập Firebase JWT Token: Bearer {token}",
        Name = "Authorization",
        In = ParameterLocation.Header,
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT"
    });

    c.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference
                {
                    Type = ReferenceType.SecurityScheme,
                    Id = "Bearer"
                }
            },
            Array.Empty<string>()
        }
    });
});

var app = builder.Build();
app.UseExceptionHandler(errors => errors.Run(async context =>
{
    var exception = context.Features.Get<Microsoft.AspNetCore.Diagnostics.IExceptionHandlerFeature>()?.Error;
    var status = exception switch
    {
        ManagementException e => e.Status,
        DbUpdateConcurrencyException => 409,
        ArgumentException => 400,
        KeyNotFoundException => 404,
        _ => 500
    };
    if (status == 500) app.Logger.LogError(exception, "Unhandled API exception");
    await Results.Problem(statusCode: status, title: status == 500 ? "Internal server error."
        : status == 409 && exception is DbUpdateConcurrencyException ? "Resource changed; reload and retry." : exception?.Message).ExecuteAsync(context);
}));

// Khởi tạo Database nếu chưa có
if (!app.Environment.IsEnvironment("Testing"))
using (var scope = app.Services.CreateScope())
{
    var dbContext = scope.ServiceProvider.GetRequiredService<SoopiDbContext>();
    try
    {
        dbContext.Database.EnsureCreated();
        app.Logger.LogInformation("Database PostgreSQL đã sẵn sàng.");

        // Migration: Đảm bảo bảng Coupons có đầy đủ cột RestaurantId và MenuItemId
        try
        {
            var voucherSql = """
                ALTER TABLE "Coupons" ADD COLUMN IF NOT EXISTS "RestaurantId" uuid REFERENCES "Restaurants"("Id") ON DELETE RESTRICT;
                ALTER TABLE "Coupons" ADD COLUMN IF NOT EXISTS "MenuItemId" uuid REFERENCES "MenuItems"("Id") ON DELETE RESTRICT;
                CREATE INDEX IF NOT EXISTS "IX_Coupons_RestaurantId" ON "Coupons"("RestaurantId");
                CREATE INDEX IF NOT EXISTS "IX_Coupons_MenuItemId" ON "Coupons"("MenuItemId");
                DO $$ BEGIN
                    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'CK_Coupons_Scope' AND conrelid = '"Coupons"'::regclass) THEN
                        ALTER TABLE "Coupons" ADD CONSTRAINT "CK_Coupons_Scope" CHECK ("MenuItemId" IS NULL OR "RestaurantId" IS NOT NULL);
                    END IF;
                END $$;
            """;
            dbContext.Database.ExecuteSqlRaw(voucherSql);
            app.Logger.LogInformation("Đã nâng cấp cấu trúc bảng Coupons.");
        }
        catch (Exception exMigration)
        {
            app.Logger.LogWarning("Lỗi chạy migration Coupons: {Message}", exMigration.Message);
        }

        // Tự động kiểm tra và đồng bộ Admin từ appsettings.json
        try
        {
            var adminEmails = builder.Configuration.GetSection("AdminSettings:AdminEmails").Get<string[]>() ?? [];
            foreach (var email in adminEmails)
            {
                var adminUser = dbContext.Users.FirstOrDefault(u => u.Email.ToLower() == email.ToLower());
                if (adminUser != null && adminUser.Role != "Admin")
                {
                    adminUser.Role = "Admin";
                    adminUser.UpdatedAt = DateTimeOffset.UtcNow;
                    app.Logger.LogInformation("Đã tự động gán vai trò Admin cho: {Email}", email);
                }
            }
            dbContext.SaveChanges();
        }
        catch (Exception exAdmin)
        {
            app.Logger.LogWarning("Lỗi kiểm tra quyền Admin: {Message}", exAdmin.Message);
        }
    }
    catch (Exception ex)
    {
        app.Logger.LogWarning("Chưa kết nối được PostgreSQL khi khởi động: {Message}", ex.Message);
    }
}

// HTTP request pipeline
if (app.Environment.IsDevelopment() || app.Environment.IsEnvironment("Testing"))
{
    app.UseSwagger();
    app.UseSwaggerUI(c =>
    {
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "SOOPI FOOD API v1");
    });
}

app.UseCors("AllowAll");
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.MapHub<OrderHub>("/orderHub");

app.Run();

public partial class Program { }
