using Microsoft.EntityFrameworkCore;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.Models;

namespace SoopiFoodBE.Services;

public interface IReviewService
{
    Task<Review> Create(
        Guid userId,
        Guid orderId,
        ReviewRequest input,
        CancellationToken ct);

    Task<List<RestaurantReviewDto>> GetRestaurantReviews(
        Guid restaurantId,
        CancellationToken ct);

    Task<ShipperDashboardDto> GetShipperDashboard(
        Guid shipperId,
        CancellationToken ct);

    Task<bool> Favorite(
        Guid userId,
        Guid restaurantId,
        bool add,
        CancellationToken ct);

    Task<List<Restaurant>> Favorites(Guid userId, CancellationToken ct);
}

public sealed class ReviewService(SoopiDbContext db) : IReviewService
{
    public async Task<Review> Create(
        Guid userId,
        Guid orderId,
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

        var resolvedShipperId = order.ShipperId;
        if (resolvedShipperId is null)
        {
            var lastDeliveryLoc = await db.DeliveryLocations
                .Where(d => d.OrderId == order.Id)
                .OrderByDescending(d => d.RecordedAt)
                .FirstOrDefaultAsync(ct);

            if (lastDeliveryLoc is not null)
            {
                resolvedShipperId = lastDeliveryLoc.ShipperId;
            }
            else
            {
                var anyShipper = await db.Users
                    .Where(u => u.Role == "Shipper")
                    .OrderByDescending(u => u.UpdatedAt)
                    .FirstOrDefaultAsync(ct);
                if (anyShipper is not null)
                {
                    resolvedShipperId = anyShipper.Id;
                }
            }

            if (resolvedShipperId is not null)
            {
                order.ShipperId = resolvedShipperId;
            }
        }

        var restaurantComment = input.Comment?.Trim() ?? string.Empty;
        var shipperComment = !string.IsNullOrWhiteSpace(input.ShipperComment)
            ? input.ShipperComment.Trim()
            : restaurantComment;

        var restaurantTags = input.RestaurantTags is { Count: > 0 }
            ? string.Join("|", input.RestaurantTags.Where(t => !string.IsNullOrWhiteSpace(t)).Select(t => t.Trim()))
            : string.Empty;

        var shipperTags = input.ShipperTags is { Count: > 0 }
            ? string.Join("|", input.ShipperTags.Where(t => !string.IsNullOrWhiteSpace(t)).Select(t => t.Trim()))
            : string.Empty;

        var review = new Review
        {
            OrderId = order.Id,
            CustomerId = userId,
            RestaurantId = order.RestaurantId,
            ShipperId = resolvedShipperId,
            RestaurantRating = input.RestaurantRating,
            ShipperRating = input.ShipperRating ?? input.RestaurantRating,
            Comment = restaurantComment,
            ShipperComment = shipperComment,
            RestaurantTags = restaurantTags,
            ShipperTags = shipperTags,
            TipAmount = Math.Max(0, input.TipAmount)
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
            restaurant.ReviewCount = previousCount + 1;
        }

        await db.SaveChangesAsync(ct);
        return review;
    }

    public async Task<List<RestaurantReviewDto>> GetRestaurantReviews(
        Guid restaurantId,
        CancellationToken ct)
    {
        var list = await db.Reviews
            .Include(r => r.Customer)
            .Include(r => r.Restaurant)
            .Include(r => r.Order)
                .ThenInclude(o => o!.Items)
            .Where(r => r.RestaurantId == restaurantId)
            .OrderByDescending(r => r.CreatedAt)
            .AsNoTracking()
            .ToListAsync(ct);

        return list.Select(r =>
        {
            var tags = string.IsNullOrWhiteSpace(r.RestaurantTags)
                ? new List<string>()
                : r.RestaurantTags.Split('|', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList();

            var orderItems = r.Order?.Items.Select(i => $"{i.Quantity}x {i.ItemName}").ToList() ?? [];
            var comment = !string.IsNullOrWhiteSpace(r.Comment) ? r.Comment : r.ShipperComment;

            return new RestaurantReviewDto(
                r.Id,
                r.OrderId,
                r.RestaurantId,
                r.Restaurant?.Name ?? string.Empty,
                r.Customer?.FullName ?? "Khách hàng",
                string.Empty,
                r.RestaurantRating,
                tags,
                comment,
                orderItems,
                r.CreatedAt);
        }).ToList();
    }

    public async Task<ShipperDashboardDto> GetShipperDashboard(
        Guid shipperId,
        CancellationToken ct)
    {
        // 1. Lấy danh sách đánh giá từ bảng Reviews
        var rawReviews = await db.Reviews
            .Include(r => r.Customer)
            .Include(r => r.Restaurant)
            .Include(r => r.Order)
            .Where(r => shipperId == Guid.Empty || r.ShipperId == shipperId || r.ShipperId == null || (r.Order != null && (r.Order.ShipperId == shipperId || r.Order.ShipperId == null)))
            .OrderByDescending(r => r.CreatedAt)
            .AsNoTracking()
            .ToListAsync(ct);

        var reviewDtos = rawReviews.Select(r =>
        {
            var rating = (int)(r.ShipperRating ?? r.RestaurantRating);
            var comment = !string.IsNullOrWhiteSpace(r.ShipperComment)
                ? r.ShipperComment
                : r.Comment;
            var rawTags = !string.IsNullOrWhiteSpace(r.ShipperTags)
                ? r.ShipperTags
                : r.RestaurantTags;
            var tags = string.IsNullOrWhiteSpace(rawTags)
                ? new List<string>()
                : rawTags.Split('|', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList();

            var orderCode = !string.IsNullOrWhiteSpace(r.Order?.OrderCode)
                ? r.Order.OrderCode
                : $"#SP-{r.OrderId.ToString()[..Math.Min(6, r.OrderId.ToString().Length)].ToUpperInvariant()}";

            return new ShipperReviewDto(
                r.Id,
                r.OrderId,
                orderCode,
                r.Restaurant?.Name ?? "Quán ăn",
                r.Customer?.FullName ?? "Khách hàng",
                rating,
                comment,
                r.TipAmount,
                tags,
                r.CreatedAt);
        }).ToList();

        // 2. Lấy danh sách cuốc xe đã hoàn thành trực tiếp từ bảng Orders
        // Chỉ lấy Status 'Delivered'
        var deliveredOrders = await db.Orders
            .Include(o => o.Restaurant)
            .Where(o => o.Status == "Delivered")
            .OrderByDescending(o => o.UpdatedAt)
            .AsNoTracking()
            .ToListAsync(ct);

        var tripDtos = deliveredOrders.Select(o =>
        {
            var orderCode = !string.IsNullOrWhiteSpace(o.OrderCode)
                ? o.OrderCode
                : $"#SP-{o.Id.ToString()[..Math.Min(6, o.Id.ToString().Length)].ToUpperInvariant()}";
            
            // Phí vận chuyển lấy trực tiếp từ cột DeliveryFee của bảng Orders
            var shippingFee = (int)Math.Round(o.DeliveryFee);
            if (shippingFee <= 0) shippingFee = 16000;

            return new ShipperCompletedTripDto(
                o.Id,
                orderCode,
                o.Restaurant?.Name ?? "Quán ăn",
                o.DeliveryAddress,
                shippingFee,
                o.UpdatedAt);
        }).ToList();

        double avgRating = reviewDtos.Count > 0
            ? reviewDtos.Average(r => r.Rating)
            : 0.0;

        return new ShipperDashboardDto(
            Math.Round(avgRating, 1),
            reviewDtos.Count,
            reviewDtos,
            tripDtos);
    }

    public async Task<bool> Favorite(
        Guid userId,
        Guid restaurantId,
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
                    item => item.Id == restaurantId && item.ApprovalStatus == "Approved"
                        && !item.IsLocked && item.Owner != null && !item.Owner.IsLocked,
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

    public Task<List<Restaurant>> Favorites(Guid userId, CancellationToken ct) =>
        db.Favorites
            .Where(favorite => favorite.UserId == userId)
            .Select(favorite => favorite.Restaurant!)
            .Where(r => r.ApprovalStatus == "Approved" && !r.IsLocked && r.Owner != null && !r.Owner.IsLocked)
            .AsNoTracking()
            .ToListAsync(ct);
}
