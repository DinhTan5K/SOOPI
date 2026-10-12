namespace SoopiFoodBE.Models;

public interface IEntity
{
    Guid Id { get; set; }
}

public sealed class AppUser : IEntity
{
    public Guid Id { get; set; }
    public string FirebaseUid { get; set; } = "";
    public string Email { get; set; } = "";
    public string FullName { get; set; } = "";
    public string? AvatarUrl { get; set; }
    public string? Phone { get; set; }
    public string Gender { get; set; } = "Nam";
    public DateTimeOffset? DateOfBirth { get; set; }
    public string Role { get; set; } = "Customer";
    public bool IsLocked { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? UpdatedAt { get; set; }
    public ICollection<UserAddress> Addresses { get; set; } = [];
}

public sealed class UserAddress : IEntity
{
    public Guid Id { get; set; }
    public Guid? UserId { get; set; }
    public AppUser? User { get; set; }
    public string FirebaseUid { get; set; } = "";
    public string Label { get; set; } = "Nhà riêng";
    public string RecipientName { get; set; } = "";
    public string Phone { get; set; } = "";
    public string FullAddress { get; set; } = "";
    public string? Note { get; set; }
    public bool IsDefault { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? UpdatedAt { get; set; }
}

public sealed class Restaurant : IEntity
{
    public Guid Id { get; set; }
    public Guid? OwnerId { get; set; }
    public AppUser? Owner { get; set; }
    public string Name { get; set; } = "";
    public string Description { get; set; } = "";
    public string Phone { get; set; } = "";
    public string Address { get; set; } = "";
    public string City { get; set; } = "";
    public string? ImageUrl { get; set; }
    public decimal? Latitude { get; set; }
    public decimal? Longitude { get; set; }
    public decimal AverageRating { get; set; }
    public bool IsActive { get; set; } = true;
    public bool IsAcceptingOrders { get; set; } = true;
    public ICollection<MenuCategory> Categories { get; set; } = [];
    public ICollection<OpeningHour> OpeningHours { get; set; } = [];
}

public sealed class OpeningHour : IEntity
{
    public Guid Id { get; set; }
    public Guid RestaurantId { get; set; }
    public Restaurant? Restaurant { get; set; }
    public byte DayOfWeek { get; set; }
    public TimeOnly OpensAt { get; set; }
    public TimeOnly ClosesAt { get; set; }
    public bool IsClosed { get; set; }
}

public sealed class MenuCategory : IEntity
{
    public Guid Id { get; set; }
    public Guid RestaurantId { get; set; }
    public Restaurant? Restaurant { get; set; }
    public string Name { get; set; } = "";
    public int SortOrder { get; set; }
    public ICollection<MenuItem> Items { get; set; } = [];
}

public sealed class MenuItem : IEntity
{
    public Guid Id { get; set; }
    public Guid CategoryId { get; set; }
    public MenuCategory? Category { get; set; }
    public string Name { get; set; } = "";
    public string Description { get; set; } = "";
    public decimal Price { get; set; }
    public string? ImageUrl { get; set; }
    public bool IsAvailable { get; set; } = true;
}

public sealed class ShoppingCart : IEntity
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public AppUser? User { get; set; }
    public Guid? RestaurantId { get; set; }
    public Restaurant? Restaurant { get; set; }
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    public ICollection<CartItem> Items { get; set; } = [];
}

public sealed class CartItem : IEntity
{
    public Guid Id { get; set; }
    public Guid CartId { get; set; }
    public ShoppingCart? Cart { get; set; }
    public Guid MenuItemId { get; set; }
    public MenuItem? MenuItem { get; set; }
    public int Quantity { get; set; }
    public string Note { get; set; } = "";
}

public sealed class Coupon : IEntity
{
    public Guid Id { get; set; }
    public string Code { get; set; } = "";
    public string DiscountType { get; set; } = "Percent";
    public decimal DiscountValue { get; set; }
    public decimal MinOrderAmount { get; set; }
    public decimal? MaxDiscount { get; set; }
    public DateTime? StartsAt { get; set; }
    public DateTime? EndsAt { get; set; }
    public int? UsageLimit { get; set; }
    public int UsedCount { get; set; }
    public bool IsActive { get; set; } = true;
}

public sealed class FoodOrder : IEntity
{
    public Guid Id { get; set; }
    public string OrderCode { get; set; } = Guid.NewGuid().ToString("N");
    public Guid CustomerId { get; set; }
    public AppUser? Customer { get; set; }
    public Guid RestaurantId { get; set; }
    public Restaurant? Restaurant { get; set; }
    public Guid? ShipperId { get; set; }
    public AppUser? Shipper { get; set; }
    public Guid? AddressId { get; set; }
    public UserAddress? Address { get; set; }
    public string DeliveryAddress { get; set; } = "";
    public decimal Subtotal { get; set; }
    public decimal DiscountAmount { get; set; }
    public decimal DeliveryFee { get; set; }
    public decimal TotalAmount { get; set; }
    public string Status { get; set; } = "Pending";
    public string PaymentMethod { get; set; } = "Cash";
    public string PaymentStatus { get; set; } = "Unpaid";
    public string? CouponCode { get; set; }
    public string Note { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    public ICollection<OrderItem> Items { get; set; } = [];
    public ICollection<OrderStatusHistory> StatusHistory { get; set; } = [];
    public ICollection<DeliveryLocation> DeliveryLocations { get; set; } = [];
}

public sealed class OrderItem : IEntity
{
    public Guid Id { get; set; }
    public Guid OrderId { get; set; }
    public FoodOrder? Order { get; set; }
    public Guid? MenuItemId { get; set; }
    public string ItemName { get; set; } = "";
    public decimal UnitPrice { get; set; }
    public int Quantity { get; set; }
    public string Note { get; set; } = "";
}

public sealed class OrderStatusHistory : IEntity
{
    public Guid Id { get; set; }
    public Guid OrderId { get; set; }
    public FoodOrder? Order { get; set; }
    public string Status { get; set; } = "";
    public DateTime ChangedAt { get; set; } = DateTime.UtcNow;
    public string? Note { get; set; }
}

public sealed class Review : IEntity
{
    public Guid Id { get; set; }
    public Guid OrderId { get; set; }
    public FoodOrder? Order { get; set; }
    public Guid CustomerId { get; set; }
    public AppUser? Customer { get; set; }
    public Guid RestaurantId { get; set; }
    public Restaurant? Restaurant { get; set; }
    public Guid? ShipperId { get; set; }
    public AppUser? Shipper { get; set; }
    public byte RestaurantRating { get; set; }
    public byte? ShipperRating { get; set; }
    public string Comment { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public sealed class Favorite : IEntity
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public AppUser? User { get; set; }
    public Guid RestaurantId { get; set; }
    public Restaurant? Restaurant { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public sealed class Payment : IEntity
{
    public Guid Id { get; set; }
    public Guid OrderId { get; set; }
    public FoodOrder? Order { get; set; }
    public string Method { get; set; } = "Cash";
    public decimal Amount { get; set; }
    public string Status { get; set; } = "Pending";
    public string? ProviderReference { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public sealed class DeliveryLocation
{
    public Guid Id { get; set; }
    public Guid OrderId { get; set; }
    public FoodOrder? Order { get; set; }
    public Guid ShipperId { get; set; }
    public decimal Latitude { get; set; }
    public decimal Longitude { get; set; }
    public DateTime RecordedAt { get; set; } = DateTime.UtcNow;
}
