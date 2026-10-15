namespace SoopiFoodBE.Models;

public sealed class ManagementAudit
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ActorId { get; set; }
    public Guid TargetId { get; set; }
    public string TargetType { get; set; } = "Restaurant";
    public string Action { get; set; } = "";
    public string? Reason { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}
