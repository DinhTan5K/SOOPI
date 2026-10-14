namespace SoopiFoodBE.Models;

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
