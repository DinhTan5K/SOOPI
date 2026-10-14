namespace SoopiFoodBE.Models;

public sealed class AppUser : IEntity
{
    public Guid Id { get; set; }
    public string FirebaseUid { get; set; } = "";
    public string Email { get; set; } = "";
    public string FullName { get; set; } = "";
    public string? AvatarUrl { get; set; }
    public string? Phone { get; set; }
    public string Gender { get; set; } = "Nam";
    public DateTimeOffset? DateOfBirth { get; set; }
    public string Role { get; set; } = "Customer";
    public bool IsLocked { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? UpdatedAt { get; set; }
    public ICollection<UserAddress> Addresses { get; set; } = [];
}
