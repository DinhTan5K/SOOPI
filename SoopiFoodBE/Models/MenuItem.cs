namespace SoopiFoodBE.Models;

public sealed class MenuItem : IEntity
{
    public Guid Id { get; set; }
    public Guid CategoryId { get; set; }
    public MenuCategory? Category { get; set; }
    public string Name { get; set; } = "";
    public string Description { get; set; } = "";
    public decimal Price { get; set; }
    public decimal? OriginalPrice { get; set; }
    public int? DiscountPercent { get; set; }
    public int SoldCount { get; set; }
    public int LikesCount { get; set; }
    public string? ImageUrl { get; set; }
    public bool IsAvailable { get; set; } = true;
}
