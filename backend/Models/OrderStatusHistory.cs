namespace SoopiFoodBE.Models;

public sealed class OrderStatusHistory : IEntity
{
    public Guid Id { get; set; }
    public Guid OrderId { get; set; }
    public FoodOrder? Order { get; set; }
    public string Status { get; set; } = "";
    public DateTime ChangedAt { get; set; } = DateTime.UtcNow;
    public string? Note { get; set; }
}
