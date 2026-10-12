using Microsoft.EntityFrameworkCore;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.Models;

namespace SoopiFoodBE.Services;

public interface IReviewService
{
    Task<Review> Create(
        int userId,
        int orderId,
        ReviewRequest input,
        CancellationToken ct);

    Task<bool> Favorite(
        int userId,
        int restaurantId,
        bool add,
        CancellationToken ct);

    Task<List<Restaurant>> Favorites(int userId, CancellationToken ct);
}

public sealed class ReviewService(SoopiDbContext db) : IReviewService
{
    public async Task<Review> Create(
        int userId,
        int orderId,
        ReviewRequest input,
        CancellationToken ct)
    {
        if (input.RestaurantRating is < 1 or > 5
            || input.ShipperRating is < 1 or > 5)
        {
            throw new ArgumentException("Rating must be between 1 and 5");
        }

        var order = await db.Orders.FirstOrDefaultAsync(
            item => item.Id == orderId
                && item.CustomerId == userId
                && item.Status == "Delivered",
            ct)
            ?? throw new InvalidOperationException(
                "Only delivered orders can be reviewed");

        if (await db.Reviews.AnyAsync(item => item.OrderId == orderId, ct))
            throw new InvalidOperationException("Order already reviewed");

        var review = new Review
        {
            OrderId = order.Id,
            CustomerId = userId,
            RestaurantId = order.RestaurantId,
            ShipperId = order.ShipperId,
            RestaurantRating = input.RestaurantRating,
            ShipperRating = input.ShipperRating,
            Comment = input.Comment
        };

        db.Reviews.Add(review);

        var restaurant = await db.Restaurants.FindAsync([order.RestaurantId], ct);
        if (restaurant is not null)
        {
            var previousCount = await db.Reviews
                .CountAsync(item => item.RestaurantId == order.RestaurantId, ct);
            var previousAverage = previousCount == 0
                ? 0
                : await db.Reviews
                    .Where(item => item.RestaurantId == order.RestaurantId)
                    .AverageAsync(item => (double)item.RestaurantRating, ct);

            restaurant.AverageRating = (decimal)(
                (previousAverage * previousCount + input.RestaurantRating)
                / (previousCount + 1));
        }

        await db.SaveChangesAsync(ct);
        return review;
    }

    public async Task<bool> Favorite(
        int userId,
        int restaurantId,
        bool add,
        CancellationToken ct)
    {
        var favorite = await db.Favorites.FirstOrDefaultAsync(
            item => item.UserId == userId && item.RestaurantId == restaurantId,
            ct);

        if (add)
        {
            if (favorite is null)
            {
                var restaurantExists = await db.Restaurants.AnyAsync(
                    item => item.Id == restaurantId,
                    ct);

                if (!restaurantExists)
                    return false;

                db.Favorites.Add(new Favorite
                {
                    UserId = userId,
                    RestaurantId = restaurantId
                });
            }
        }
        else if (favorite is not null)
        {
            db.Favorites.Remove(favorite);
        }

        await db.SaveChangesAsync(ct);
        return true;
    }

    public Task<List<Restaurant>> Favorites(int userId, CancellationToken ct) =>
        db.Favorites
            .Where(favorite => favorite.UserId == userId)
            .Select(favorite => favorite.Restaurant!)
            .AsNoTracking()
            .ToListAsync(ct);
}
