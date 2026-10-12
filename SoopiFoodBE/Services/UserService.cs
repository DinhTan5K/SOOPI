using Microsoft.EntityFrameworkCore;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.DataAccess.Repositories;
using SoopiFoodBE.Models;

namespace SoopiFoodBE.Services;

public interface IUserService
{
    Task<AppUser?> Profile(int id, CancellationToken ct);
    Task<bool> Update(int id, ProfileUpdate input, CancellationToken ct);
    Task<List<UserAddress>> Addresses(int id, CancellationToken ct);
    Task<UserAddress> SaveAddress(int id, int? addressId, AddressRequest input, CancellationToken ct);
    Task<bool> DeleteAddress(int id, int addressId, CancellationToken ct);
    Task<bool> SetLock(int id, bool locked, CancellationToken ct);
}

public sealed class UserService(SoopiDbContext db, IUserRepository users) : IUserService
{
    public Task<AppUser?> Profile(int id, CancellationToken ct) => users.FindAsync(id, ct);

    public async Task<bool> Update(int id, ProfileUpdate input, CancellationToken ct)
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

    public Task<List<UserAddress>> Addresses(int id, CancellationToken ct) =>
        users.AddressesAsync(id, ct);

    public async Task<UserAddress> SaveAddress(
        int id,
        int? addressId,
        AddressRequest input,
        CancellationToken ct)
    {
        var address = addressId.HasValue
            ? await db.Addresses.FirstOrDefaultAsync(
                item => item.Id == addressId && item.UserId == id,
                ct)
            : new UserAddress { UserId = id };

        if (address is null)
            throw new KeyNotFoundException("Address not found");

        address.Label = input.Label;
        address.RecipientName = input.RecipientName;
        address.Phone = input.Phone;
        address.Line = input.Line;
        address.Ward = input.Ward;
        address.District = input.District;
        address.City = input.City;
        address.Latitude = input.Latitude;
        address.Longitude = input.Longitude;
        address.IsDefault = input.IsDefault;

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

    public async Task<bool> DeleteAddress(int id, int addressId, CancellationToken ct)
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

    public async Task<bool> SetLock(int id, bool locked, CancellationToken ct)
    {
        var user = await db.Users.FindAsync([id], ct);
        if (user is null)
            return false;

        user.IsLocked = locked;
        await db.SaveChangesAsync(ct);
        return true;
    }
}
