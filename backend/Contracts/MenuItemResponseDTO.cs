namespace SoopiFoodBE.Contracts;

public sealed record MenuItemResponse(
    Guid Id,
    Guid CategoryId,
    string Name,
    string Description,
    decimal Price,
    decimal? OriginalPrice,
    int? DiscountPercent,
    int SoldCount,
    int LikesCount,
    string? ImageUrl,
    bool IsAvailable);
