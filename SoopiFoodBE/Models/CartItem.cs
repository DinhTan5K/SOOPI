namespace SoopiFoodBE.Models;

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
