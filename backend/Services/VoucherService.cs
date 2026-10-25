using Microsoft.EntityFrameworkCore;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.Models;

namespace SoopiFoodBE.Services;

public sealed record VoucherLine(Guid MenuItemId, decimal UnitPrice, int Quantity);

public sealed class VoucherService(SoopiDbContext db)
{
    public static string Normalize(string code) => code.Trim().ToUpperInvariant();

    public async Task<(Coupon Coupon, decimal Eligible, decimal Discount)> Evaluate(
        string code, Guid restaurantId, IReadOnlyCollection<VoucherLine> lines, CancellationToken ct)
    {
        var normalized = Normalize(code);
        var coupon = await db.Coupons.SingleOrDefaultAsync(c => c.Code.ToUpper() == normalized, ct)
            ?? throw new InvalidOperationException("Voucher không tồn tại.");
        var now = DateTime.UtcNow;
        if (!coupon.IsActive
            || (coupon.StartsAt.HasValue && coupon.StartsAt.Value.ToUniversalTime() > now)
            || (coupon.EndsAt.HasValue && coupon.EndsAt.Value.ToUniversalTime() < now)
            || (coupon.UsageLimit.HasValue && coupon.UsedCount >= coupon.UsageLimit)
            || (coupon.RestaurantId.HasValue && coupon.RestaurantId != restaurantId))
            throw new InvalidOperationException("Voucher không còn hiệu lực hoặc không áp dụng cho quán này.");
        if (coupon.MenuItemId.HasValue && !await db.MenuItems.AnyAsync(m => m.Id == coupon.MenuItemId
            && m.Category!.RestaurantId == restaurantId, ct))
            throw new InvalidOperationException("Món áp dụng voucher không còn tồn tại.");
        var (eligible, discount) = Calculate(coupon, lines);
        return (coupon, eligible, discount);
    }

    public static (decimal Eligible, decimal Discount) Calculate(Coupon coupon, IReadOnlyCollection<VoucherLine> lines)
    {
        if (lines.Count == 0 || lines.Any(l => l.Quantity <= 0 || l.UnitPrice < 0))
            throw new InvalidOperationException("Giỏ hàng không hợp lệ.");
        var subtotal = lines.Sum(l => l.UnitPrice * l.Quantity);
        if (subtotal < coupon.MinOrderAmount)
            throw new InvalidOperationException("Đơn hàng chưa đạt giá trị tối thiểu.");
        var eligible = lines.Where(l => !coupon.MenuItemId.HasValue || l.MenuItemId == coupon.MenuItemId)
            .Sum(l => l.UnitPrice * l.Quantity);
        if (eligible <= 0) throw new InvalidOperationException("Giỏ hàng không có món được áp dụng voucher.");
        var discount = coupon.DiscountType == "Percent" ? eligible * coupon.DiscountValue / 100 : coupon.DiscountValue;
        if (coupon.MaxDiscount.HasValue) discount = Math.Min(discount, coupon.MaxDiscount.Value);
        return (eligible, decimal.Round(Math.Min(discount, eligible), 2, MidpointRounding.AwayFromZero));
    }

    public static string Status(Coupon coupon)
    {
        if (!coupon.IsActive) return "Inactive";
        if (coupon.EndsAt.HasValue && coupon.EndsAt.Value.ToUniversalTime() < DateTime.UtcNow) return "Expired";
        if (coupon.UsageLimit.HasValue && coupon.UsedCount >= coupon.UsageLimit) return "Exhausted";
        return (coupon.StartsAt.HasValue && coupon.StartsAt.Value.ToUniversalTime() > DateTime.UtcNow) ? "Scheduled" : "Active";
    }

    public static object View(Coupon c) => new {
        c.Id, c.Code, c.RestaurantId, c.MenuItemId, Scope = c.MenuItemId.HasValue ? "MenuItem" : "Restaurant",
        c.DiscountType, c.DiscountValue, c.MinOrderAmount, c.MaxDiscount, c.StartsAt, c.EndsAt,
        c.UsageLimit, c.UsedCount, c.IsActive, Status = Status(c)
    };
}
