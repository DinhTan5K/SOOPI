using Microsoft.EntityFrameworkCore;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.DataAccess.Dao;
using SoopiFoodBE.DataAccess.Repositories;
using SoopiFoodBE.Services;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddDbContext<SoopiDbContext>(options =>
    options.UseNpgsql(
        builder.Configuration.GetConnectionString("SoopiFood")
        ?? throw new InvalidOperationException(
            "Missing ConnectionStrings:SoopiFood")));

builder.Services.AddScoped(typeof(IEntityDao<>), typeof(EfEntityDao<>));
builder.Services.AddScoped<IUserRepository, UserRepository>();
builder.Services.AddScoped<IRestaurantRepository, RestaurantRepository>();
builder.Services.AddScoped<IOrderRepository, OrderRepository>();
builder.Services.AddScoped<IUserService, UserService>();
builder.Services.AddScoped<IRestaurantService, RestaurantService>();
builder.Services.AddScoped<IOrderService, OrderService>();
builder.Services.AddScoped<IReviewService, ReviewService>();
var app = builder.Build();
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.MapControllers();
app.Run();
