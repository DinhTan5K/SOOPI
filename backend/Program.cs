using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.DataAccess.Dao;
using SoopiFoodBE.DataAccess.Repositories;
using SoopiFoodBE.Services;
using Soopi.Backend.Services;

var builder = WebApplication.CreateBuilder(args);

// Controllers & JSON configuration (tránh lỗi circular reference)
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
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

// Swagger & OpenAPI with Bearer Auth definition
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "SOOPI FOOD API",
        Version = "v1",
        Description = "Backend API cho ứng dụng SOOPI FOOD (.NET 9 + PostgreSQL + Firebase Auth + Cloudinary)"
    });

    c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Description = "Nhập Firebase JWT Token: Bearer {token}",
        Name = "Authorization",
        In = ParameterLocation.Header,
        Type = SecuritySchemeType.ApiKey,
        Scheme = "Bearer"
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

// Khởi tạo Database nếu chưa có
using (var scope = app.Services.CreateScope())
{
    var dbContext = scope.ServiceProvider.GetRequiredService<SoopiDbContext>();
    try
    {
        dbContext.Database.EnsureCreated();
        app.Logger.LogInformation("Database PostgreSQL đã sẵn sàng.");
    }
    catch (Exception ex)
    {
        app.Logger.LogWarning("Chưa kết nối được PostgreSQL khi khởi động: {Message}", ex.Message);
    }
}

// HTTP request pipeline
if (app.Environment.IsDevelopment())
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

app.Run();
