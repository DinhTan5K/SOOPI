namespace SoopiFoodBE.Contracts;

public sealed record CreateDirectOrderRequest(
    Guid? RestaurantId,
    string RestaurantName,
    string? RestaurantAddress,
    string DeliveryAddress,
    string PaymentMethod,
    decimal DeliveryFee,
    string? Note,
    double? UserLat,
    double? UserLng,
    double? RestaurantLat,
    double? RestaurantLng,
    List<DirectOrderItemDto> Items
);

public sealed record DirectOrderItemDto(
    Guid? MenuItemId,
    string Name,
    decimal Price,
    int Quantity,
    string? Note
);
