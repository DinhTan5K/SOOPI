using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.DataAccess;
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

    private static void ValidateLock(LockInput input)
    {
        if (input.Locked && string.IsNullOrWhiteSpace(input.Reason)) throw new ManagementException(400, "A lock reason is required.");
    }
}
