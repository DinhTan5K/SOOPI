namespace SoopiFoodBE.Contracts;

public sealed record MenuItemResponse(
    Guid Id,
    Guid CategoryId,
    string Name,
    string Description,
    decimal Price,
    string? ImageUrl,
    bool IsAvailable);
