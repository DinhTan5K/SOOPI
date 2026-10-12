namespace SoopiFoodBE.Models;

public sealed class MenuCategory : IEntity
{
    public Guid Id { get; set; }
    public Guid RestaurantId { get; set; }
    public Restaurant? Restaurant { get; set; }
    public string Name { get; set; } = "";
    public int SortOrder { get; set; }
    public ICollection<MenuItem> Items { get; set; } = [];
}
