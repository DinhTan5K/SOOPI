using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.Models;
using SoopiFoodBE.Services;

namespace SoopiFoodBE.Controllers;

[ApiController, Authorize, Route("api/admin")]
public sealed class AdminManagementController(
    SoopiDbContext db, CurrentAccount accounts, RestaurantManagement management) : ControllerBase
{
    [HttpGet("restaurants")]
    public async Task<IActionResult> Restaurants(string? q, string? status, bool? locked,
        int page = 1, int pageSize = 20, CancellationToken ct = default)
    {
        await accounts.Admin(ct); RestaurantManagement.Pagination(page, pageSize); RestaurantManagement.Status(status);
        var query = db.Restaurants.AsNoTracking();
        if (status is not null) query = query.Where(r => r.ApprovalStatus == status);
        if (locked.HasValue) query = query.Where(r => r.IsLocked == locked.Value);
        if (!string.IsNullOrWhiteSpace(q)) query = query.Where(r => r.Name.Contains(q) || r.Address.Contains(q));
        var total = await query.CountAsync(ct);
        var rows = await query.OrderBy(r => r.Name).ThenBy(r => r.Id).Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        return Ok(new PageResult<object>(rows.Select(RestaurantManagement.View).ToList(), total, page, pageSize));
    }

    [HttpGet("restaurants/{id:guid}")]
    public async Task<IActionResult> Restaurant(Guid id, CancellationToken ct)
    {
        await accounts.Admin(ct);
        var r = await db.Restaurants.AsNoTracking().Include(r => r.Owner).Include(r => r.Categories).ThenInclude(c => c.Items)
            .Include(r => r.OpeningHours).SingleOrDefaultAsync(r => r.Id == id, ct)
            ?? throw new ManagementException(404, "Restaurant not found.");
        var history = await db.ManagementAudits.AsNoTracking().Where(a => a.TargetId == id && a.TargetType == "Restaurant")
            .OrderByDescending(a => a.CreatedAt).Select(a => new { a.Action, a.Reason, a.ActorId, a.CreatedAt }).ToListAsync(ct);
        return Ok(new { Restaurant = RestaurantManagement.View(r),
            Owner = r.Owner is null ? null : new { r.Owner.Id, r.Owner.Email, r.Owner.FullName, r.Owner.Phone, r.Owner.IsLocked }, History = history });
    }

    [HttpPost("restaurants/{id:guid}/approve")]
    public async Task<IActionResult> Approve(Guid id, CancellationToken ct) => await Review(id, "Approved", null, ct);

    [HttpPost("restaurants/{id:guid}/reject")]
    public async Task<IActionResult> Reject(Guid id, ReasonInput input, CancellationToken ct) =>
        await Review(id, "Rejected", input.Reason.Trim(), ct);

    private async Task<IActionResult> Review(Guid id, string status, string? reason, CancellationToken ct)
    {
        var actor = await accounts.Admin(ct);
        var r = await db.Restaurants.Include(r => r.Owner).SingleOrDefaultAsync(r => r.Id == id, ct)
            ?? throw new ManagementException(404, "Restaurant not found.");
        if (r.ApprovalStatus != "Pending") throw new ManagementException(409, "Only pending restaurants can be reviewed.");
        if (r.IsLocked || r.Owner is null || r.Owner.IsLocked)
            throw new ManagementException(409, "Restaurant requires an active owner and must not be locked.");
        r.ApprovalStatus = status; r.ReviewReason = reason; r.ReviewedBy = actor.Id; r.ReviewedAt = DateTimeOffset.UtcNow;
        // Approval never enables order acceptance automatically.
        r.IsAcceptingOrders = false;
        management.Audit(actor.Id, id, status, reason);
        await db.SaveChangesAsync(ct); return Ok(RestaurantManagement.View(r));
    }

    [HttpPatch("restaurants/{id:guid}/lock")]
    public async Task<IActionResult> LockRestaurant(Guid id, LockInput input, CancellationToken ct)
    {
        var actor = await accounts.Admin(ct); ValidateLock(input);
        var r = await db.Restaurants.SingleOrDefaultAsync(r => r.Id == id, ct)
            ?? throw new ManagementException(404, "Restaurant not found.");
        r.IsLocked = input.Locked;
        if (input.Locked) r.IsAcceptingOrders = false;
        management.Audit(actor.Id, id, input.Locked ? "Locked" : "Unlocked", input.Reason?.Trim());
        await db.SaveChangesAsync(ct); return NoContent();
    }

    [HttpGet("users")]
    public async Task<IActionResult> Users(string? q, string? role, bool? locked,
        int page = 1, int pageSize = 20, CancellationToken ct = default)
    {
        await accounts.Admin(ct); RestaurantManagement.Pagination(page, pageSize);
        if (role is not null && role is not ("Customer" or "Owner" or "Admin" or "Shipper"))
            throw new ManagementException(400, "Invalid role.");
        var query = db.Users.AsNoTracking();
        if (role is not null) query = query.Where(u => u.Role == role);
        if (locked.HasValue) query = query.Where(u => u.IsLocked == locked.Value);
        if (!string.IsNullOrWhiteSpace(q)) query = query.Where(u => u.Email.Contains(q) || u.FullName.Contains(q));
        var total = await query.CountAsync(ct);
        var rows = await query.OrderBy(u => u.Email).ThenBy(u => u.Id).Skip((page - 1) * pageSize).Take(pageSize)
            .Select(u => new { u.Id, u.Email, u.FullName, u.Phone, u.Role, u.IsLocked }).ToListAsync(ct);
        return Ok(new { Items = rows, Total = total, Page = page, PageSize = pageSize });
    }

    [HttpGet("users/{id:guid}")]
    public async Task<IActionResult> UserDetail(Guid id, CancellationToken ct)
    {
        await accounts.Admin(ct);
        var user = await db.Users.AsNoTracking().Where(u => u.Id == id)
            .Select(u => new { u.Id, u.Email, u.FullName, u.Phone, u.AvatarUrl, u.Role, u.IsLocked, u.CreatedAt }).SingleOrDefaultAsync(ct)
            ?? throw new ManagementException(404, "User not found.");
        var owned = await db.Restaurants.AsNoTracking().Where(r => r.OwnerId == id)
            .Select(r => new { r.Id, r.Name, r.ApprovalStatus, r.IsLocked }).ToListAsync(ct);
        var history = await db.ManagementAudits.AsNoTracking().Where(a => a.TargetType == "User" && a.TargetId == id)
            .OrderByDescending(a => a.CreatedAt).Select(a => new { a.Action, a.Reason, a.ActorId, a.CreatedAt }).ToListAsync(ct);
        return Ok(new { User = user, Restaurants = owned, History = history });
    }

    [HttpPatch("users/{id:guid}/lock")]
    public async Task<IActionResult> LockUser(Guid id, LockInput input, CancellationToken ct)
    {
        var actor = await accounts.Admin(ct); ValidateLock(input);
        var user = await db.Users.SingleOrDefaultAsync(u => u.Id == id, ct)
            ?? throw new ManagementException(404, "User not found.");
        if (user.Id == actor.Id || user.Role == "Admin") throw new ManagementException(403, "Administrator accounts cannot be locked here.");
        user.IsLocked = input.Locked; user.UpdatedAt = DateTimeOffset.UtcNow;
        management.Audit(actor.Id, id, input.Locked ? "Locked" : "Unlocked", input.Reason?.Trim(), "User");
        await db.SaveChangesAsync(ct); return NoContent();
    }

    [HttpPatch("users/{id:guid}/role")]
    public async Task<IActionResult> UpdateUserRole(Guid id, UpdateUserRoleInput input, CancellationToken ct)
    {
        var actor = await accounts.Admin(ct);
        var role = input.Role.Trim();
        if (role is not ("Customer" or "Owner" or "Shipper" or "Admin"))
            throw new ManagementException(400, "Vai trò không hợp lệ (Customer, Owner, Shipper, Admin).");

        var user = await db.Users.SingleOrDefaultAsync(u => u.Id == id, ct)
            ?? throw new ManagementException(404, "User not found.");

        if (user.Id == actor.Id && role != "Admin")
            throw new ManagementException(403, "Không thể tự hạ quyền Admin của chính mình.");

        var oldRole = user.Role;
        user.Role = role;
        user.UpdatedAt = DateTimeOffset.UtcNow;
        management.Audit(actor.Id, id, $"RoleChanged:{oldRole}->{role}", null, "User");
        await db.SaveChangesAsync(ct);
        return Ok(new { user.Id, user.Email, user.FullName, Role = user.Role });
    }

    [HttpGet("dashboard/stats")]
    public async Task<IActionResult> DashboardStats(CancellationToken ct)
    {
        await accounts.Admin(ct);

        // User stats
        var totalUsers = await db.Users.CountAsync(ct);
        var customersCount = await db.Users.CountAsync(u => u.Role == "Customer", ct);
        var ownersCount = await db.Users.CountAsync(u => u.Role == "Owner" || u.Role == "RestaurantOwner", ct);
        var shippersCount = await db.Users.CountAsync(u => u.Role == "Shipper", ct);
        var adminsCount = await db.Users.CountAsync(u => u.Role == "Admin", ct);
        var lockedUsersCount = await db.Users.CountAsync(u => u.IsLocked, ct);

        // Restaurant stats
        var totalRestaurants = await db.Restaurants.CountAsync(ct);
        var pendingRestaurants = await db.Restaurants.CountAsync(r => r.ApprovalStatus == "Pending", ct);
        var approvedRestaurants = await db.Restaurants.CountAsync(r => r.ApprovalStatus == "Approved", ct);
        var rejectedRestaurants = await db.Restaurants.CountAsync(r => r.ApprovalStatus == "Rejected", ct);
        var lockedRestaurants = await db.Restaurants.CountAsync(r => r.IsLocked, ct);

        // Order stats
        var totalOrders = await db.Orders.CountAsync(ct);
        var pendingOrders = await db.Orders.CountAsync(o => o.Status == "Pending" || o.Status == "Placed", ct);
        var deliveringOrders = await db.Orders.CountAsync(o => o.Status == "Delivering" || o.Status == "PickedUp" || o.Status == "OnDelivery", ct);
        var completedOrders = await db.Orders.CountAsync(o => o.Status == "Delivered" || o.Status == "Completed", ct);
        var cancelledOrders = await db.Orders.CountAsync(o => o.Status == "Cancelled", ct);

        // Revenue
        var totalRevenue = await db.Orders
            .Where(o => o.Status == "Delivered" || o.Status == "Completed")
            .SumAsync(o => (decimal?)o.TotalAmount, ct) ?? 0m;

        var todayStart = DateTime.UtcNow.Date;
        var todayOrders = await db.Orders.CountAsync(o => o.CreatedAt >= todayStart, ct);
        var todayRevenue = await db.Orders
            .Where(o => o.CreatedAt >= todayStart && (o.Status == "Delivered" || o.Status == "Completed"))
            .SumAsync(o => (decimal?)o.TotalAmount, ct) ?? 0m;

        return Ok(new
        {
            Users = new
            {
                Total = totalUsers,
                Customers = customersCount,
                Owners = ownersCount,
                Shippers = shippersCount,
                Admins = adminsCount,
                Locked = lockedUsersCount
            },
            Restaurants = new
            {
                Total = totalRestaurants,
                Pending = pendingRestaurants,
                Approved = approvedRestaurants,
                Rejected = rejectedRestaurants,
                Locked = lockedRestaurants
            },
            Orders = new
            {
                Total = totalOrders,
                Pending = pendingOrders,
                Delivering = deliveringOrders,
                Completed = completedOrders,
                Cancelled = cancelledOrders,
                TodayOrders = todayOrders
            },
            Revenue = new
            {
                Total = totalRevenue,
                Today = todayRevenue
            }
        });
    }

    [HttpGet("orders")]
    public async Task<IActionResult> Orders(
        string? q,
        string? status,
        Guid? restaurantId,
        Guid? shipperId,
        int page = 1,
        int pageSize = 20,
        CancellationToken ct = default)
    {
        await accounts.Admin(ct);
        RestaurantManagement.Pagination(page, pageSize);

        var query = db.Orders.AsNoTracking()
            .Include(o => o.Customer)
            .Include(o => o.Restaurant)
            .Include(o => o.Shipper)
            .AsQueryable();

        if (!string.IsNullOrWhiteSpace(status))
        {
            query = query.Where(o => o.Status == status);
        }

        if (restaurantId.HasValue)
        {
            query = query.Where(o => o.RestaurantId == restaurantId.Value);
        }

        if (shipperId.HasValue)
        {
            query = query.Where(o => o.ShipperId == shipperId.Value);
        }

        if (!string.IsNullOrWhiteSpace(q))
        {
            var search = q.Trim();
            query = query.Where(o =>
                o.OrderCode.Contains(search) ||
                (o.Customer != null && (o.Customer.FullName.Contains(search) || o.Customer.Phone!.Contains(search))) ||
                (o.Restaurant != null && o.Restaurant.Name.Contains(search)));
        }

        var total = await query.CountAsync(ct);
        var rows = await query
            .OrderByDescending(o => o.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(o => new
            {
                o.Id,
                o.OrderCode,
                o.Status,
                o.Subtotal,
                o.DiscountAmount,
                o.DeliveryFee,
                o.TotalAmount,
                o.PaymentMethod,
                o.PaymentStatus,
                o.DeliveryAddress,
                o.Note,
                o.CreatedAt,
                Customer = o.Customer == null ? null : new { o.Customer.Id, o.Customer.FullName, o.Customer.Phone, o.Customer.Email },
                Restaurant = o.Restaurant == null ? null : new { o.Restaurant.Id, o.Restaurant.Name, o.Restaurant.Address, o.Restaurant.Phone },
                Shipper = o.Shipper == null ? null : new { o.Shipper.Id, o.Shipper.FullName, o.Shipper.Phone }
            })
            .ToListAsync(ct);

        return Ok(new PageResult<object>(rows, total, page, pageSize));
    }

    [HttpGet("orders/{id:guid}")]
    public async Task<IActionResult> OrderDetail(Guid id, CancellationToken ct)
    {
        await accounts.Admin(ct);

        var order = await db.Orders.AsNoTracking()
            .Include(o => o.Customer)
            .Include(o => o.Restaurant)
            .Include(o => o.Shipper)
            .Include(o => o.Items)
            .Include(o => o.StatusHistory)
            .SingleOrDefaultAsync(o => o.Id == id, ct)
            ?? throw new ManagementException(404, "Đơn hàng không tồn tại.");

        return Ok(new
        {
            order.Id,
            order.OrderCode,
            order.Status,
            order.Subtotal,
            order.DiscountAmount,
            order.DeliveryFee,
            order.TotalAmount,
            order.PaymentMethod,
            order.PaymentStatus,
            order.DeliveryAddress,
            order.Note,
            order.CreatedAt,
            order.UpdatedAt,
            Customer = order.Customer == null ? null : new { order.Customer.Id, order.Customer.FullName, order.Customer.Phone, order.Customer.Email },
            Restaurant = order.Restaurant == null ? null : new { order.Restaurant.Id, order.Restaurant.Name, order.Restaurant.Address, order.Restaurant.Phone },
            Shipper = order.Shipper == null ? null : new { order.Shipper.Id, order.Shipper.FullName, order.Shipper.Phone },
            Items = order.Items.Select(i => new { i.Id, i.MenuItemId, i.ItemName, i.UnitPrice, i.Quantity, i.Note }),
            StatusHistory = order.StatusHistory.OrderBy(h => h.ChangedAt).Select(h => new { h.Status, h.ChangedAt, h.Note })
        });
    }

    [HttpGet("audits")]
    public async Task<IActionResult> Audits(string? targetType, int page = 1, int pageSize = 20, CancellationToken ct = default)
    {
        await accounts.Admin(ct);
        RestaurantManagement.Pagination(page, pageSize);

        var query = db.ManagementAudits.AsNoTracking();
        if (!string.IsNullOrWhiteSpace(targetType))
        {
            query = query.Where(a => a.TargetType == targetType);
        }

        var total = await query.CountAsync(ct);
        var rows = await query
            .OrderByDescending(a => a.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(a => new
            {
                a.Id,
                a.ActorId,
                a.TargetId,
                a.TargetType,
                a.Action,
                a.Reason,
                a.CreatedAt
            })
            .ToListAsync(ct);

        return Ok(new PageResult<object>(rows, total, page, pageSize));
    }

    [HttpGet("vouchers")]
    public async Task<IActionResult> GlobalVouchers(CancellationToken ct)
    {
        await accounts.Admin(ct);
        var rows = await db.Coupons.AsNoTracking()
            .Where(c => c.RestaurantId == null)
            .OrderBy(c => c.Code)
            .ToListAsync(ct);
        return Ok(rows.Select(VoucherService.View));
    }

    [HttpPost("vouchers")]
    public async Task<IActionResult> CreateGlobalVoucher(GlobalVoucherInput input, CancellationToken ct)
    {
        await accounts.Admin(ct);

        if (input.DiscountType is not ("Percent" or "Fixed") || input.DiscountValue <= 0
            || (input.DiscountType == "Percent" && input.DiscountValue > 100)
            || input.MinOrderAmount < 0
            || (input.MaxDiscount.HasValue && input.MaxDiscount <= 0)
            || (input.UsageLimit.HasValue && input.UsageLimit <= 0)
            || (input.StartsAt.HasValue && input.EndsAt.HasValue && input.EndsAt <= input.StartsAt))
        {
            throw new ManagementException(400, "Thông tin voucher không hợp lệ.");
        }

        var code = VoucherService.Normalize(input.Code);
        if (await db.Coupons.AnyAsync(c => c.Code.ToUpper() == code, ct))
        {
            throw new ManagementException(409, "Mã voucher đã tồn tại.");
        }

        var coupon = new Coupon
        {
            Id = Guid.NewGuid(),
            RestaurantId = null,
            MenuItemId = null,
            Code = code,
            DiscountType = input.DiscountType,
            DiscountValue = input.DiscountValue,
            MinOrderAmount = input.MinOrderAmount,
            MaxDiscount = input.MaxDiscount,
            StartsAt = input.StartsAt?.UtcDateTime,
            EndsAt = input.EndsAt?.UtcDateTime,
            UsageLimit = input.UsageLimit,
            IsActive = input.IsActive
        };

        db.Coupons.Add(coupon);
        await db.SaveChangesAsync(ct);

        return Ok(VoucherService.View(coupon));
    }

    [HttpPatch("vouchers/{id:guid}/status")]
    public async Task<IActionResult> GlobalVoucherStatus(Guid id, VoucherStatusInput input, CancellationToken ct)
    {
        await accounts.Admin(ct);
        var coupon = await db.Coupons.SingleOrDefaultAsync(c => c.Id == id && c.RestaurantId == null, ct)
            ?? throw new ManagementException(404, "Voucher không tồn tại.");

        coupon.IsActive = input.IsActive;
        await db.SaveChangesAsync(ct);
        return Ok(VoucherService.View(coupon));
    }

    private static void ValidateLock(LockInput input)
    {
        if (input.Locked && string.IsNullOrWhiteSpace(input.Reason)) throw new ManagementException(400, "A lock reason is required.");
    }
}
