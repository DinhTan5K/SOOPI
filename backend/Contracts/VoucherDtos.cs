using System.ComponentModel.DataAnnotations;

namespace SoopiFoodBE.Contracts;

public sealed record VoucherInput(
    [Required, RegularExpression(@"^[A-Za-z0-9_-]{1,50}$")] string Code,
    Guid? MenuItemId,
    [Required] string DiscountType,
    decimal DiscountValue,
    decimal MinOrderAmount = 0,
    decimal? MaxDiscount = null,
    DateTimeOffset? StartsAt = null,
    DateTimeOffset? EndsAt = null,
    int? UsageLimit = null,
    bool IsActive = true);

public sealed record VoucherStatusInput(bool IsActive);
public sealed record VoucherPreviewInput([Required] string CouponCode);
public sealed record DirectVoucherPreviewInput([Required] string CouponCode, [Required] List<CartLineRequest> Items);
public sealed record VoucherPreview(string CouponCode, decimal Subtotal, decimal EligibleAmount,
    decimal DiscountAmount, decimal DeliveryFee, decimal TotalAmount);
