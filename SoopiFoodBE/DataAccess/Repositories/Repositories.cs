using Microsoft.EntityFrameworkCore;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.Models;

namespace SoopiFoodBE.DataAccess.Repositories;

public interface IUserRepository
{
    Task<AppUser?> FindAsync(int id, CancellationToken ct);
    Task<AppUser?> FindByEmailAsync(string email, CancellationToken ct);
    Task<List<UserAddress>> AddressesAsync(int userId, CancellationToken ct);
}

public sealed class UserRepository(SoopiDbContext db) : IUserRepository
{
    public Task<AppUser?> FindAsync(int id, CancellationToken ct) => db.Users
        .Include(user => user.Addresses)
        .FirstOrDefaultAsync(user => user.Id == id, ct);

    public Task<AppUser?> FindByEmailAsync(string email, CancellationToken ct) =>
        db.Users.FirstOrDefaultAsync(user => user.Email == email, ct);

    public Task<List<UserAddress>> AddressesAsync(int userId, CancellationToken ct) =>
        db.Addresses
            .Where(address => address.UserId == userId)
            .OrderByDescending(address => address.IsDefault)
            .ToListAsync(ct);
}

public interface IRestaurantRepository
{
    Task<List<Restaurant>> SearchAsync(
        string? query,
        string? category,
        decimal? minRating,
        double? latitude,
        double? longitude,
        double? radiusKm,
        CancellationToken ct);

    Task<Restaurant?> GetAsync(int id, CancellationToken ct);
    Task<List<MenuItem>> MenuAsync(int restaurantId, CancellationToken ct);
}

public sealed class RestaurantRepository(SoopiDbContext db) : IRestaurantRepository
{
    public async Task<List<Restaurant>> SearchAsync(
        string? query,
        string? category,
        decimal? minRating,
        double? latitude,
        double? longitude,
        double? radiusKm,
        CancellationToken ct)
    {
        var restaurants = db.Restaurants
            .AsNoTracking()
            .Where(restaurant => restaurant.IsActive && restaurant.IsAcceptingOrders);

        if (!string.IsNullOrWhiteSpace(query))
        {
            restaurants = restaurants.Where(restaurant =>
                restaurant.Name.Contains(query) || restaurant.Address.Contains(query));
        }

        if (minRating.HasValue)
            restaurants = restaurants.Where(restaurant =>
                restaurant.AverageRating >= minRating.Value);

        if (!string.IsNullOrWhiteSpace(category))
        {
            restaurants = restaurants.Where(restaurant =>
                restaurant.Categories.Any(item => item.Name == category));
        }

        var results = await restaurants
            .OrderByDescending(restaurant => restaurant.AverageRating)
            .ToListAsync(ct);

        if (latitude.HasValue && longitude.HasValue && radiusKm.HasValue)
        {
            results = results.Where(restaurant =>
                    restaurant.Latitude.HasValue && restaurant.Longitude.HasValue
                    && Distance(
                        latitude.Value,
                        longitude.Value,
                        (double)restaurant.Latitude.Value,
                        (double)restaurant.Longitude.Value) <= radiusKm.Value)
                .ToList();
        }

        return results;
    }

    public Task<Restaurant?> GetAsync(int id, CancellationToken ct) => db.Restaurants
        .Include(restaurant => restaurant.Categories)
            .ThenInclude(category => category.Items)
        .Include(restaurant => restaurant.OpeningHours)
        .FirstOrDefaultAsync(restaurant => restaurant.Id == id, ct);

    public Task<List<MenuItem>> MenuAsync(int restaurantId, CancellationToken ct) =>
        db.MenuItems
            .Include(item => item.Category)
            .Where(item => item.Category!.RestaurantId == restaurantId)
            .AsNoTracking()
            .ToListAsync(ct);

    private static double Distance(double lat1, double lon1, double lat2, double lon2)
    {
        const double earthRadiusKm = 6371;
        var latDifference = (lat2 - lat1) * Math.PI / 180;
        var lonDifference = (lon2 - lon1) * Math.PI / 180;
        var haversine = Math.Pow(Math.Sin(latDifference / 2), 2)
            + Math.Cos(lat1 * Math.PI / 180)
            * Math.Cos(lat2 * Math.PI / 180)
            * Math.Pow(Math.Sin(lonDifference / 2), 2);

        return 2 * earthRadiusKm * Math.Asin(Math.Sqrt(haversine));
    }
}

public interface IOrderRepository
{
    Task<FoodOrder?> GetForCustomerAsync(int id, int userId, CancellationToken ct);
    Task<List<FoodOrder>> HistoryAsync(int userId, CancellationToken ct);
}

public sealed class OrderRepository(SoopiDbContext db) : IOrderRepository
{
    public Task<FoodOrder?> GetForCustomerAsync(int id, int userId, CancellationToken ct) =>
        db.Orders
            .Include(order => order.Items)
            .Include(order => order.StatusHistory)
            .Include(order => order.DeliveryLocations
                .OrderByDescending(location => location.RecordedAt)
                .Take(1))
            .Include(order => order.Restaurant)
            .Include(order => order.Shipper)
            .FirstOrDefaultAsync(
                order => order.Id == id && order.CustomerId == userId,
                ct);

    public Task<List<FoodOrder>> HistoryAsync(int userId, CancellationToken ct) =>
        db.Orders
            .Where(order => order.CustomerId == userId)
            .OrderByDescending(order => order.CreatedAt)
            .AsNoTracking()
            .ToListAsync(ct);
}
