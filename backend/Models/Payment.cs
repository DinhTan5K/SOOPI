namespace SoopiFoodBE.Models;

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
