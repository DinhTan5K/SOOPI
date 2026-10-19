using Microsoft.EntityFrameworkCore;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.Models;

namespace SoopiFoodBE.DataAccess.Repositories;

public interface IUserRepository
{
    Task<AppUser?> FindAsync(Guid id, CancellationToken ct);
    Task<AppUser?> FindByEmailAsync(string email, CancellationToken ct = default);
    Task<AppUser?> FindByFirebaseUidAsync(string firebaseUid, CancellationToken ct = default);
    Task<List<UserAddress>> AddressesAsync(Guid userId, CancellationToken ct = default);
    Task<AppUser> CreateAsync(AppUser user, CancellationToken ct = default);
    Task<AppUser> UpdateAsync(AppUser user, CancellationToken ct = default);
}

public sealed class UserRepository(SoopiDbContext db) : IUserRepository
{
    public Task<AppUser?> FindAsync(Guid id, CancellationToken ct) => db.Users
        .Include(user => user.Addresses)
        .FirstOrDefaultAsync(user => user.Id == id, ct);

    public Task<AppUser?> FindByEmailAsync(string email, CancellationToken ct = default) =>
        db.Users.FirstOrDefaultAsync(user => user.Email.ToLower() == email.ToLower(), ct);

    public Task<AppUser?> FindByFirebaseUidAsync(string firebaseUid, CancellationToken ct = default) =>
        db.Users
            .Include(user => user.Addresses)
            .FirstOrDefaultAsync(user => user.FirebaseUid == firebaseUid, ct);

    public Task<List<UserAddress>> AddressesAsync(Guid userId, CancellationToken ct = default) =>
        db.Addresses
            .Where(address => address.UserId == userId)
            .OrderByDescending(address => address.IsDefault)
            .ToListAsync(ct);

    public async Task<AppUser> CreateAsync(AppUser user, CancellationToken ct = default)
    {
        user.CreatedAt = DateTimeOffset.UtcNow;
        await db.Users.AddAsync(user, ct);
        await db.SaveChangesAsync(ct);
        return user;
    }

    public async Task<AppUser> UpdateAsync(AppUser user, CancellationToken ct = default)
    {
        user.UpdatedAt = DateTimeOffset.UtcNow;
        db.Users.Update(user);
        await db.SaveChangesAsync(ct);
        return user;
    }
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

    Task<Restaurant?> GetAsync(Guid id, CancellationToken ct);
    Task<List<MenuItem>> MenuAsync(Guid restaurantId, CancellationToken ct);
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
            .Include(restaurant => restaurant.Categories)
                .ThenInclude(cat => cat.Items)
            .AsNoTracking()
            .Where(restaurant => restaurant.IsActive && restaurant.IsAcceptingOrders
                && restaurant.ApprovalStatus == "Approved" && !restaurant.IsLocked
                && restaurant.Owner != null && !restaurant.Owner.IsLocked);

        if (!string.IsNullOrWhiteSpace(query))
        {
            var pattern = $"%{query.Trim()}%";
            restaurants = restaurants.Where(restaurant =>
                EF.Functions.ILike(restaurant.Name, pattern) ||
                EF.Functions.ILike(restaurant.Address, pattern) ||
                EF.Functions.ILike(restaurant.Description, pattern) ||
                restaurant.Categories.Any(cat =>
                    EF.Functions.ILike(cat.Name, pattern) ||
                    cat.Items.Any(item => EF.Functions.ILike(item.Name, pattern))));
        }

        if (minRating.HasValue)
            restaurants = restaurants.Where(restaurant =>
                restaurant.AverageRating >= minRating.Value);

        if (!string.IsNullOrWhiteSpace(category) && category != "Tất cả")
        {
            var catPattern = $"%{category.Trim()}%";
            restaurants = restaurants.Where(restaurant =>
                restaurant.Categories.Any(item => EF.Functions.ILike(item.Name, catPattern)));
        }

        var results = await restaurants
            .OrderByDescending(restaurant => restaurant.AverageRating)
            .ToListAsync(ct);

        if (latitude.HasValue && longitude.HasValue)
        {
            if (radiusKm.HasValue && radiusKm > 0)
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

            // Sắp xếp ưu tiên theo khoảng cách gần nhất tới địa chỉ giao hàng
            results = results.OrderBy(restaurant =>
                restaurant.Latitude.HasValue && restaurant.Longitude.HasValue
                    ? Distance(
                        latitude.Value,
                        longitude.Value,
                        (double)restaurant.Latitude.Value,
                        (double)restaurant.Longitude.Value)
                    : double.MaxValue)
                .ThenByDescending(restaurant => restaurant.AverageRating)
                .ToList();
        }

        return results;
    }

    public Task<Restaurant?> GetAsync(Guid id, CancellationToken ct) => db.Restaurants
        .Include(restaurant => restaurant.Categories)
            .ThenInclude(category => category.Items)
        .Include(restaurant => restaurant.OpeningHours)
        .FirstOrDefaultAsync(restaurant => restaurant.Id == id && restaurant.ApprovalStatus == "Approved"
            && !restaurant.IsLocked && restaurant.Owner != null && !restaurant.Owner.IsLocked, ct);

    public Task<List<MenuItem>> MenuAsync(Guid restaurantId, CancellationToken ct) =>
        db.MenuItems
            .Include(item => item.Category)
            .Where(item => item.Category!.RestaurantId == restaurantId
                && item.Category.Restaurant!.ApprovalStatus == "Approved" && !item.Category.Restaurant.IsLocked
                && item.Category.Restaurant.Owner != null && !item.Category.Restaurant.Owner.IsLocked)
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
    Task<FoodOrder?> GetForCustomerAsync(Guid id, Guid userId, CancellationToken ct);
    Task<List<FoodOrder>> HistoryAsync(Guid userId, CancellationToken ct);
}

public sealed class OrderRepository(SoopiDbContext db) : IOrderRepository
{
    public Task<FoodOrder?> GetForCustomerAsync(Guid id, Guid userId, CancellationToken ct) =>
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

    public Task<List<FoodOrder>> HistoryAsync(Guid userId, CancellationToken ct) =>
        db.Orders
            .Where(order => order.CustomerId == userId)
            .Include(order => order.Items)
            .Include(order => order.Restaurant)
            .Include(order => order.Shipper)
            .OrderByDescending(order => order.CreatedAt)
            .AsNoTracking()
            .ToListAsync(ct);
}
