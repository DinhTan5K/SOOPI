namespace SoopiFoodBE.Contracts;

public sealed record CheckoutRequest(
    Guid AddressId,
    string PaymentMethod,
    string? CouponCode,
    string Note);

public sealed record DirectOrderRequest(
    Guid RestaurantId,
    List<CartLineRequest> Items,
    string? DeliveryAddress,
    Guid? AddressId,
    string PaymentMethod,
    string? CouponCode,
    string? Note);

