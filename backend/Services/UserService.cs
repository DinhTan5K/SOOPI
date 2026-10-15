using Microsoft.EntityFrameworkCore;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.DataAccess.Repositories;
using SoopiFoodBE.Models;

namespace SoopiFoodBE.Services;

public interface IUserService
{
    Task<AppUser?> Profile(Guid id, CancellationToken ct);
    Task<bool> Update(Guid id, ProfileUpdate input, CancellationToken ct);
    Task<List<UserAddress>> Addresses(Guid id, CancellationToken ct);
    Task<UserAddress> SaveAddress(Guid id, Guid? addressId, AddressRequest input, CancellationToken ct);
    Task<bool> DeleteAddress(Guid id, Guid addressId, CancellationToken ct);
    Task<bool> SetLock(Guid id, bool locked, CancellationToken ct);
}

public sealed class UserService(SoopiDbContext db, IUserRepository users, CurrentAccount accounts) : IUserService
{
    public Task<AppUser?> Profile(Guid id, CancellationToken ct) => users.FindAsync(id, ct);

    public async Task<bool> Update(Guid id, ProfileUpdate input, CancellationToken ct)
    {
        var user = await db.Users.FindAsync([id], ct);
        if (user is null)
            return false;

        user.FullName = input.FullName;
        user.Phone = input.Phone;
        user.AvatarUrl = input.AvatarUrl;
        await db.SaveChangesAsync(ct);
        return true;
    }

    public Task<List<UserAddress>> Addresses(Guid id, CancellationToken ct) =>
        users.AddressesAsync(id, ct);

    public async Task<UserAddress> SaveAddress(
        Guid id,
        Guid? addressId,
        AddressRequest input,
        CancellationToken ct)
    {
        var user = await db.Users.FindAsync([id], ct)
            ?? throw new KeyNotFoundException("User not found");

        var address = addressId.HasValue
            ? await db.Addresses.FirstOrDefaultAsync(
                item => item.Id == addressId && item.UserId == id,
                ct)
            : new UserAddress
            {
                UserId = id,
                FirebaseUid = user.FirebaseUid
            };

        if (address is null)
            throw new KeyNotFoundException("Address not found");

        address.Label = input.Label;
        address.RecipientName = input.RecipientName;
        address.Phone = input.Phone;
        address.FullAddress = input.FullAddress;
        address.Note = input.Note;
        address.IsDefault = input.IsDefault;
        address.UpdatedAt = DateTimeOffset.UtcNow;

        if (input.IsDefault)
        {
            var otherAddresses = await db.Addresses
                .Where(item => item.UserId == id && item.Id != address.Id)
                .ToListAsync(ct);

            foreach (var otherAddress in otherAddresses)
                otherAddress.IsDefault = false;
        }

        if (!addressId.HasValue)
            db.Addresses.Add(address);

        await db.SaveChangesAsync(ct);
        return address;
    }

    public async Task<bool> DeleteAddress(Guid id, Guid addressId, CancellationToken ct)
    {
        var address = await db.Addresses.FirstOrDefaultAsync(
            item => item.Id == addressId && item.UserId == id,
            ct);

        if (address is null)
            return false;

        db.Addresses.Remove(address);
        await db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<bool> SetLock(Guid id, bool locked, CancellationToken ct)
    {
        var actor = await accounts.Admin(ct);
        var user = await db.Users.FindAsync([id], ct);
        if (user is null)
            return false;

        if (user.Id == actor.Id || user.Role == "Admin") throw new ManagementException(403, "Administrator accounts cannot be locked here.");
        if (locked) throw new ManagementException(400, "Use PATCH /api/admin/users/{id}/lock with a reason to lock an account.");
        user.IsLocked = false;
        db.ManagementAudits.Add(new SoopiFoodBE.Models.ManagementAudit { ActorId = actor.Id, TargetId = id, TargetType = "User", Action = "Unlocked" });
        await db.SaveChangesAsync(ct);
        return true;
    }
}
