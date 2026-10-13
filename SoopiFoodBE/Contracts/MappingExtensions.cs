using SoopiFoodBE.Models;

namespace SoopiFoodBE.Contracts;

public static class MappingExtensions
{
    public static MenuItemResponse ToResponse(this MenuItem item) =>
        new(
            item.Id,
            item.CategoryId,
            item.Name,
            item.Description,
            item.Price,
            item.OriginalPrice,
            item.DiscountPercent,
            item.SoldCount,
            item.LikesCount,
            item.ImageUrl,
            item.IsAvailable);

    public static MenuCategoryResponse ToResponse(this MenuCategory cat) =>
        new(
            cat.Id,
            cat.RestaurantId,
            cat.Name,
            cat.SortOrder,
            cat.Items?.Select(i => i.ToResponse()).ToList() ?? []);

    public static OpeningHourResponse ToResponse(this OpeningHour hour) =>
        new(
            hour.Id,
            hour.RestaurantId,
            hour.DayOfWeek,
            hour.OpensAt,
            hour.ClosesAt,
            hour.IsClosed);

    public static RestaurantResponse ToResponse(this Restaurant r) =>
        new(
            r.Id,
            r.OwnerId,
            r.Name,
            r.Description,
            r.Phone,
            r.Address,
            r.City,
            r.ImageUrl,
            r.Latitude,
            r.Longitude,
            r.AverageRating,
            r.ReviewCount,
            r.TotalOrders,
            r.IsActive,
            r.IsAcceptingOrders,
            r.Categories?.Select(c => c.ToResponse()).ToList() ?? [],
            r.OpeningHours?.Select(h => h.ToResponse()).ToList() ?? []);
}
