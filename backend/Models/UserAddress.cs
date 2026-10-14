namespace SoopiFoodBE.Models;

public sealed class UserAddress : IEntity
{
    public Guid Id { get; set; }
    public Guid? UserId { get; set; }
    public AppUser? User { get; set; }
    public string FirebaseUid { get; set; } = "";
    public string Label { get; set; } = "Nhà riêng";
    public string RecipientName { get; set; } = "";
    public string Phone { get; set; } = "";
    public string FullAddress { get; set; } = "";
    public string? Note { get; set; }
    public bool IsDefault { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? UpdatedAt { get; set; }
}
