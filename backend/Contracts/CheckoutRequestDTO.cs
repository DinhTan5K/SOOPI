namespace SoopiFoodBE.Contracts;

public sealed record CheckoutRequest(
    Guid AddressId,
    string PaymentMethod,
    string? CouponCode,
    string Note);
