namespace SoopiFoodBE.Models;

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
