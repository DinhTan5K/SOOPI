namespace SoopiFoodBE.Contracts;

public sealed record RestaurantResponse(
    Guid Id,
    Guid? OwnerId,
    string Name,
    string Description,
    string Phone,
    string Address,
    string City,
    string? ImageUrl,
    decimal? Latitude,
    decimal? Longitude,
    decimal AverageRating,
    int ReviewCount,
    int TotalOrders,
    bool IsActive,
    bool IsAcceptingOrders,
    List<MenuCategoryResponse> Categories,
    List<OpeningHourResponse> OpeningHours);
