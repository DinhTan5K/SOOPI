namespace SoopiFoodBE.Contracts;

public sealed record ReviewRequest(
    byte RestaurantRating,
    byte? ShipperRating,
    string Comment,
    string? ShipperComment = null,
    List<string>? RestaurantTags = null,
    List<string>? ShipperTags = null,
    int TipAmount = 0);

public sealed record RestaurantReviewDto(
    Guid Id,
    Guid OrderId,
    Guid RestaurantId,
    string RestaurantName,
    string CustomerName,
    string CustomerAvatar,
    int Rating,
    List<string> Tags,
    string Comment,
    List<string> DishNames,
    DateTime CreatedAt);

public sealed record ShipperReviewDto(
    Guid Id,
    Guid OrderId,
    string OrderCode,
    string RestaurantName,
    string CustomerName,
    int Rating,
    string Comment,
    int TipAmount,
    List<string> Tags,
    DateTime CreatedAt);

public sealed record ShipperCompletedTripDto(
    Guid OrderId,
    string OrderCode,
    string RestaurantName,
    string DeliveryAddress,
    int DeliveryFee,
    DateTime CompletedAt);

public sealed record ShipperDashboardDto(
    double AverageRating,
    int TotalReviewsCount,
    List<ShipperReviewDto> Reviews,
    List<ShipperCompletedTripDto> Trips);
