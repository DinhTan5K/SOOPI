namespace SoopiFoodBE.Contracts;

public sealed record MenuItemRequest(
    Guid CategoryId,
    string Name,
    string Description,
    decimal Price,
    string? ImageUrl,
    bool IsAvailable);
