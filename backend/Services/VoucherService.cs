using Microsoft.EntityFrameworkCore;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.Models;

namespace SoopiFoodBE.Services;

public sealed record VoucherLine(Guid MenuItemId, decimal UnitPrice, int Quantity);

public sealed class VoucherService(SoopiDbContext db)
{
    public static string Normalize(string code) => code.Trim().ToUpperInvariant();

    public static DateTime ToUtc(DateTime dt)
    {
        if (dt.Kind == DateTimeKind.Utc) return dt;
        if (dt.Kind == DateTimeKind.Local) return dt.ToUniversalTime();
        return DateTime.SpecifyKind(dt, DateTimeKind.Local).ToUniversalTime();
    }

    public async Task<(Coupon Coupon, decimal Eligible, decimal Discount)> Evaluate(
        string code, Guid restaurantId, IReadOnlyCollection<VoucherLine> lines, CancellationToken ct)
    {
        var normalized = Normalize(code);
        var coupon = await db.Coupons.SingleOrDefaultAsync(c => c.Code.ToUpper() == normalized, ct)
            ?? throw new InvalidOperationException("Mã voucher không tồn tại.");
        var now = DateTime.UtcNow;
        if (!coupon.IsActive)
            throw new InvalidOperationException("Voucher này đang tạm ngưng hoạt động.");
        if (coupon.RestaurantId.HasValue && coupon.RestaurantId != restaurantId)
            throw new InvalidOperationException("Voucher này không thuộc về quán ăn đang chọn.");
        if (coupon.StartsAt.HasValue && ToUtc(coupon.StartsAt.Value) > now.AddMinutes(5))
            throw new InvalidOperationException("Voucher chưa đến thời hạn hiệu lực.");
        if (coupon.EndsAt.HasValue && ToUtc(coupon.EndsAt.Value) < now)
            throw new InvalidOperationException("Voucher này đã hết hạn sử dụng.");
        if (coupon.UsageLimit.HasValue && coupon.UsedCount >= coupon.UsageLimit)
            throw new InvalidOperationException("Voucher này đã hết lượt sử dụng.");
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
        var now = DateTime.UtcNow;
        if (coupon.EndsAt.HasValue && ToUtc(coupon.EndsAt.Value) < now) return "Expired";
        if (coupon.UsageLimit.HasValue && coupon.UsedCount >= coupon.UsageLimit) return "Exhausted";
        return (coupon.StartsAt.HasValue && ToUtc(coupon.StartsAt.Value) > now.AddMinutes(5)) ? "Scheduled" : "Active";
    }

    public static object View(Coupon c) => new {
        c.Id, c.Code, c.RestaurantId, c.MenuItemId, Scope = c.MenuItemId.HasValue ? "MenuItem" : "Restaurant",
        c.DiscountType, c.DiscountValue, c.MinOrderAmount, c.MaxDiscount, c.StartsAt, c.EndsAt,
        c.UsageLimit, c.UsedCount, c.IsActive, Status = Status(c)
    };
}
