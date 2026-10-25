using System.ComponentModel.DataAnnotations;

namespace SoopiFoodBE.Contracts;

public sealed record RestaurantInput(
    [Required, StringLength(150)] string Name,
    [StringLength(1000)] string Description,
    [Required, StringLength(20)] string Phone,
    [Required, StringLength(500)] string Address,
    [Required, StringLength(100)] string City,
    [Url, StringLength(500)] string? ImageUrl,
    [Range(-90, 90)] decimal? Latitude,
    [Range(-180, 180)] decimal? Longitude);
public sealed record CategoryInput([Required, StringLength(100)] string Name, int SortOrder);
public sealed record OperationInput(bool IsActive, bool IsAcceptingOrders);
public sealed record AvailabilityInput(bool IsAvailable);
public sealed record ReasonInput([Required, StringLength(1000)] string Reason);
public sealed record LockInput(bool Locked, [StringLength(1000)] string? Reason);
public sealed record PageResult<T>(IReadOnlyList<T> Items, int Total, int Page, int PageSize);

public sealed record UpdateOrderStatusInput([Required] string Status, string? Note);

public sealed record UpdateUserRoleInput([Required] string Role);

public sealed record GlobalVoucherInput(
    [Required, StringLength(50)] string Code,
    [Required] string DiscountType,
    [Range(0.01, 9999999999.99)] decimal DiscountValue,
    [Range(0, 9999999999.99)] decimal MinOrderAmount,
    [Range(0.01, 9999999999.99)] decimal? MaxDiscount,
    DateTimeOffset? StartsAt,
    DateTimeOffset? EndsAt,
    [Range(1, int.MaxValue)] int? UsageLimit,
    bool IsActive = true);
