namespace SoopiFoodBE.Contracts;

public sealed record ProfileUpdate(
    string FullName,
    string Phone,
    string? AvatarUrl);

public sealed record AddressRequest(
    string Label,
    string RecipientName,
    string Phone,
    string Line,
    string Ward,
    string District,
    string City,
    decimal? Latitude,
    decimal? Longitude,
    bool IsDefault);

public sealed record MenuItemRequest(
    int CategoryId,
    string Name,
    string Description,
    decimal Price,
    string? ImageUrl,
    bool IsAvailable);

public sealed record CartLineRequest(int MenuItemId, int Quantity, string Note);

public sealed record CheckoutRequest(
    int AddressId,
    string PaymentMethod,
    string? CouponCode,
    string Note);

public sealed record ReviewRequest(
    byte RestaurantRating,
    byte? ShipperRating,
    string Comment);

public sealed record RestaurantUpdate(
    string Name,
    string Description,
    string Phone,
    string Address,
    string City,
    bool IsActive,
    bool IsAcceptingOrders);

public sealed record OpeningHourRequest(
    TimeOnly OpensAt,
    TimeOnly ClosesAt,
    bool IsClosed);

public sealed record DeliveryUpdate(
    string Status,
    decimal? Latitude,
    decimal? Longitude,
    string? Note);
