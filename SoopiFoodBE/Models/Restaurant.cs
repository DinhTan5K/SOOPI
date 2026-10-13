namespace SoopiFoodBE.Models;

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
    public int ReviewCount { get; set; }
    public int TotalOrders { get; set; }
    public bool IsActive { get; set; } = true;
    public bool IsAcceptingOrders { get; set; } = true;
    public ICollection<MenuCategory> Categories { get; set; } = [];
    public ICollection<OpeningHour> OpeningHours { get; set; } = [];
}
