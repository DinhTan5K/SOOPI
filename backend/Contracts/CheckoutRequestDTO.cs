namespace SoopiFoodBE.Contracts;

public sealed record CheckoutRequest(
    Guid AddressId,
    string PaymentMethod,
    string? CouponCode,
    string Note,
    double? UserLat = null,
    double? UserLng = null);

public sealed record DirectOrderRequest(
    Guid RestaurantId,
    List<CartLineRequest> Items,
    string? DeliveryAddress,
    Guid? AddressId,
    string PaymentMethod,
    string? CouponCode,
    string? Note,
    double? UserLat = null,
    double? UserLng = null);

