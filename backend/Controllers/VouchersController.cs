using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.Models;
using SoopiFoodBE.Services;

namespace SoopiFoodBE.Controllers;

[ApiController, Authorize, Route("api/merchant/restaurants/{restaurantId:guid}/vouchers")]
public sealed class MerchantVouchersController(SoopiDbContext db, RestaurantManagement management) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(Guid restaurantId, CancellationToken ct)
    {
        await management.Owned(restaurantId, ct);
        var rows = await db.Coupons.AsNoTracking().Where(c => c.RestaurantId == restaurantId).OrderBy(c => c.Code).ToListAsync(ct);
        return Ok(rows.Select(VoucherService.View));
    }

    [HttpGet("{voucherId:guid}")]
    public async Task<IActionResult> Detail(Guid restaurantId, Guid voucherId, CancellationToken ct) =>
        Ok(VoucherService.View(await Find(restaurantId, voucherId, ct)));

    [HttpPost]
    public async Task<IActionResult> Create(Guid restaurantId, VoucherInput input, CancellationToken ct)
    {
        var restaurant = await management.Owned(restaurantId, ct);
        if (input.MenuItemId.HasValue && !restaurant.Categories.SelectMany(c => c.Items).Any(m => m.Id == input.MenuItemId))
            throw new ManagementException(400, "Món phải thuộc quán đang chọn.");
        if (input.DiscountType is not ("Percent" or "Fixed") || input.DiscountValue <= 0
            || input.DiscountValue > 9999999999.99m
            || (input.DiscountType == "Percent" && input.DiscountValue > 100)
            || input.MinOrderAmount < 0 || input.MinOrderAmount > 9999999999.99m
            || input.MaxDiscount <= 0 || input.MaxDiscount > 9999999999.99m || input.UsageLimit <= 0
            || decimal.Round(input.DiscountValue, 2) != input.DiscountValue
            || decimal.Round(input.MinOrderAmount, 2) != input.MinOrderAmount
            || (input.MaxDiscount.HasValue && decimal.Round(input.MaxDiscount.Value, 2) != input.MaxDiscount.Value)
            || (input.StartsAt.HasValue && input.EndsAt.HasValue && input.EndsAt <= input.StartsAt))
            throw new ManagementException(400, "Giá trị giảm, điều kiện hoặc thời gian voucher không hợp lệ.");
        var code = VoucherService.Normalize(input.Code);
        if (await db.Coupons.AnyAsync(c => c.Code.ToUpper() == code, ct))
            throw new ManagementException(409, "Mã voucher đã tồn tại.");
        var coupon = new Coupon { Id = Guid.NewGuid(), RestaurantId = restaurantId, MenuItemId = input.MenuItemId,
            Code = code, DiscountType = input.DiscountType, DiscountValue = input.DiscountValue,
            MinOrderAmount = input.MinOrderAmount, MaxDiscount = input.MaxDiscount,
            StartsAt = input.StartsAt?.UtcDateTime, EndsAt = input.EndsAt?.UtcDateTime,
            UsageLimit = input.UsageLimit, IsActive = input.IsActive };
        db.Coupons.Add(coupon);
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateException e) when (e.InnerException is PostgresException { SqlState: "23505" })
        { throw new ManagementException(409, "Mã voucher đã tồn tại."); }
        return CreatedAtAction(nameof(Detail), new { restaurantId, voucherId = coupon.Id }, VoucherService.View(coupon));
    }

    [HttpPatch("{voucherId:guid}/status")]
    public async Task<IActionResult> Status(Guid restaurantId, Guid voucherId, VoucherStatusInput input, CancellationToken ct)
    {
        var coupon = await Find(restaurantId, voucherId, ct);
        coupon.IsActive = input.IsActive;
        await db.SaveChangesAsync(ct);
        return Ok(VoucherService.View(coupon));
    }

    private async Task<Coupon> Find(Guid restaurantId, Guid voucherId, CancellationToken ct)
    {
        await management.Owned(restaurantId, ct);
        return await db.Coupons.SingleOrDefaultAsync(c => c.Id == voucherId && c.RestaurantId == restaurantId, ct)
            ?? throw new ManagementException(404, "Voucher không tồn tại.");
    }
}

[ApiController, Route("api")]
public sealed class VouchersController(SoopiDbContext db, VoucherService vouchers, CurrentAccount accounts) : ControllerBase
{
    [HttpGet("restaurants/{restaurantId:guid}/vouchers")]
    public async Task<IActionResult> Available(Guid restaurantId, CancellationToken ct)
    {
        if (!await db.Restaurants.AnyAsync(r => r.Id == restaurantId && r.IsActive && !r.IsLocked
            && r.ApprovalStatus == "Approved", ct)) return NotFound();
        var rows = await db.Coupons.AsNoTracking().Where(c => c.RestaurantId == restaurantId && c.IsActive
            && (c.UsageLimit == null || c.UsedCount < c.UsageLimit)
            && (c.MenuItemId == null || db.MenuItems.Any(m => m.Id == c.MenuItemId && m.Category!.RestaurantId == restaurantId)))
            .OrderBy(c => c.Code).ToListAsync(ct);
        var now = DateTime.UtcNow;
        var valid = rows.Where(c =>
            (!c.StartsAt.HasValue || VoucherService.ToUtc(c.StartsAt.Value) <= now.AddMinutes(5)) &&
            (!c.EndsAt.HasValue || VoucherService.ToUtc(c.EndsAt.Value) >= now)).ToList();
        return Ok(valid.Select(VoucherService.View));
    }

    [HttpPost("restaurants/{restaurantId:guid}/vouchers/preview-direct")]
    public async Task<IActionResult> PreviewDirect(
        Guid restaurantId, DirectVoucherPreviewInput input, CancellationToken ct)
    {
        if (input.Items.Count == 0) return BadRequest(new { error = "Giỏ hàng trống." });
        var itemIds = input.Items.Select(item => item.MenuItemId).Distinct().ToList();
        var menuItems = await db.MenuItems
            .Where(item => itemIds.Contains(item.Id) && item.Category!.RestaurantId == restaurantId && item.IsAvailable)
            .ToDictionaryAsync(item => item.Id, ct);
        if (menuItems.Count != itemIds.Count)
            return BadRequest(new { error = "Có món không còn khả dụng tại quán này." });

        try
        {
            var lines = input.Items.Select(item =>
                new VoucherLine(item.MenuItemId, menuItems[item.MenuItemId].Price, item.Quantity)).ToList();
            var result = await vouchers.Evaluate(input.CouponCode, restaurantId, lines, ct);
            return Ok(new
            {
                couponCode = result.Coupon.Code,
                subtotal = lines.Sum(line => line.UnitPrice * line.Quantity),
                eligibleAmount = result.Eligible,
                discountAmount = result.Discount
            });
        }
        catch (InvalidOperationException exception)
        {
            return BadRequest(new { error = exception.Message });
        }
    }

    [Authorize, HttpPost("users/{userId:guid}/cart/vouchers/preview")]
    public async Task<IActionResult> Preview(Guid userId, VoucherPreviewInput input, CancellationToken ct)
    {
        var user = await accounts.Get(ct: ct);
        if (user.Id != userId) return Forbid();
        var cart = await db.Carts.AsNoTracking().Include(c => c.Items).ThenInclude(i => i.MenuItem)
            .SingleOrDefaultAsync(c => c.UserId == userId, ct);
        if (cart?.RestaurantId is null || cart.Items.Count == 0) return BadRequest(new { error = "Giỏ hàng trống." });
        try
        {
            var lines = cart.Items.Select(i => new VoucherLine(i.MenuItemId, i.MenuItem!.Price, i.Quantity)).ToList();
            var result = await vouchers.Evaluate(input.CouponCode, cart.RestaurantId.Value, lines, ct);
            var subtotal = lines.Sum(l => l.UnitPrice * l.Quantity);
            return Ok(new VoucherPreview(result.Coupon.Code, subtotal, result.Eligible, result.Discount, 15000,
                subtotal - result.Discount + 15000));
        }
        catch (InvalidOperationException e) { return BadRequest(new { error = e.Message }); }
    }
}
