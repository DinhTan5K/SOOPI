using System.ComponentModel.DataAnnotations;
namespace SoopiFoodBE.Contracts;

public sealed record MenuItemRequest(
    Guid CategoryId,
    [Required, StringLength(150)] string Name,
    [StringLength(1000)] string Description,
    [Range(typeof(decimal), "0", "9999999999.99")] decimal Price,
    [Url, StringLength(500)] string? ImageUrl,
    bool IsAvailable);
