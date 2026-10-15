namespace SoopiFoodBE.Models;

public sealed class Restaurant : IEntity
{
    public string ApprovalStatus { get; set; } = "Pending";
    public bool IsLocked { get; set; }
    public string? ReviewReason { get; set; }
    public Guid? ReviewedBy { get; set; }
    public DateTimeOffset? ReviewedAt { get; set; }
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
    public bool IsAcceptingOrders { get; set; }
    public ICollection<MenuCategory> Categories { get; set; } = [];
    public ICollection<OpeningHour> OpeningHours { get; set; } = [];
}
