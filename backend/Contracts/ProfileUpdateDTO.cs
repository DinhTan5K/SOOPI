namespace SoopiFoodBE.Contracts;

public sealed record ProfileUpdate(
    string FullName,
    string Phone,
    string? AvatarUrl);
