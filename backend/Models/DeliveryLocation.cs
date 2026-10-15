namespace SoopiFoodBE.Models;

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
