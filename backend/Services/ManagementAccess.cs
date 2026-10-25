using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.Models;

namespace SoopiFoodBE.Services;

public sealed class ManagementException(int status, string message) : Exception(message)
{
    public int Status { get; } = status;
}

public sealed class CurrentAccount(SoopiDbContext db, IHttpContextAccessor accessor, IConfiguration? config = null)
{
    public async Task<AppUser> Get(bool create = false, CancellationToken ct = default)
    {
        var principal = accessor.HttpContext?.User;
        if (principal?.Identity?.IsAuthenticated != true)
            throw new ManagementException(401, "A valid Firebase bearer token is required.");
        var uid = principal.FindFirstValue("user_id") ?? principal.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? principal.FindFirstValue("sub");
        if (string.IsNullOrWhiteSpace(uid)) throw new ManagementException(401, "Firebase UID is missing.");
        var account = await db.Users.SingleOrDefaultAsync(u => u.FirebaseUid == uid, ct);
        var adminEmails = config?.GetSection("AdminSettings:AdminEmails").Get<string[]>() ?? [];

        if (account is not null)
        {
            if (adminEmails.Any(e => string.Equals(e, account.Email, StringComparison.OrdinalIgnoreCase)) && account.Role != "Admin")
            {
                account.Role = "Admin";
                account.UpdatedAt = DateTimeOffset.UtcNow;
                await db.SaveChangesAsync(ct);
            }
        }

        if (account is null && create)
        {
            var email = principal.FindFirstValue(ClaimTypes.Email) ?? principal.FindFirstValue("email");
            if (string.IsNullOrWhiteSpace(email)) throw new ManagementException(400, "An email identity is required.");
            var isAdmin = adminEmails.Any(e => string.Equals(e, email, StringComparison.OrdinalIgnoreCase));
            account = new AppUser { Id = Guid.NewGuid(), FirebaseUid = uid, Email = email,
                FullName = principal.FindFirstValue("name") ?? email.Split('@')[0],
                Role = isAdmin ? "Admin" : "Customer" };
            db.Users.Add(account);
            try { await db.SaveChangesAsync(ct); }
            catch (DbUpdateException)
            {
                db.Entry(account).State = EntityState.Detached;
                account = await db.Users.SingleOrDefaultAsync(u => u.FirebaseUid == uid, ct);
                if (account is null) throw;
            }
        }
        if (account is null) throw new ManagementException(403, "Account profile does not exist.");
        if (account.IsLocked) throw new ManagementException(403, "Account is locked.");
        return account;
    }

    public async Task<AppUser> Admin(CancellationToken ct = default)
    {
        var user = await Get(ct: ct);
        var adminEmails = config?.GetSection("AdminSettings:AdminEmails").Get<string[]>() ?? [];
        if (adminEmails.Any(e => string.Equals(e, user.Email, StringComparison.OrdinalIgnoreCase)) && user.Role != "Admin")
        {
            user.Role = "Admin";
            user.UpdatedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync(ct);
        }
        if (user.Role != "Admin") throw new ManagementException(403, "Administrator access is required.");
        return user;
    }

    public async Task<AppUser> Owner(bool create = false, CancellationToken ct = default)
    {
        var user = await Get(create: create, ct: ct);
        if (user.Role != "Owner" && user.Role != "RestaurantOwner" && user.Role != "Admin")
        {
            var hasRestaurants = await db.Restaurants.AnyAsync(r => r.OwnerId == user.Id, ct);
            if (!hasRestaurants)
            {
                throw new ManagementException(403, "Tài khoản của bạn là Khách hàng (Customer), không có quyền truy cập Cổng Quản lý Chủ quán.");
            }
            user.Role = "Owner";
            await db.SaveChangesAsync(ct);
        }
        return user;
    }
}

// Protect legacy URLs as well as the new routes; never trust an ID in the URL.
[AttributeUsage(AttributeTargets.Method | AttributeTargets.Class)]
public sealed class ManagementAccessAttribute(bool admin = false, bool create = false) : Attribute, IAsyncActionFilter
{
    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        var accounts = context.HttpContext.RequestServices.GetRequiredService<CurrentAccount>();
        var actor = admin ? await accounts.Admin(context.HttpContext.RequestAborted)
            : await accounts.Get(create: create, ct: context.HttpContext.RequestAborted);
        if (!admin && context.ActionArguments.TryGetValue("ownerId", out var value)
            && value is Guid ownerId && ownerId != actor.Id)
            throw new ManagementException(403, "Owner ID does not match the signed-in account.");
        await next();
    }
}
