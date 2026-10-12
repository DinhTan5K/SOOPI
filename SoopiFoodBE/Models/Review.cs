namespace SoopiFoodBE.Models;

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
