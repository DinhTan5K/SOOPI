using Microsoft.EntityFrameworkCore;
using Soopi.Backend.Models.Entities;

namespace Soopi.Backend.DataAccess.Repositories
{
    public class UserAddressRepository : IUserAddressRepository
    {
        private readonly AppDbContext _context;

        public UserAddressRepository(AppDbContext context)
        {
            _context = context;
        }

        public async Task<List<UserAddress>> GetByFirebaseUidAsync(string firebaseUid)
        {
            return await _context.UserAddresses
                .Where(a => a.FirebaseUid == firebaseUid)
                .OrderByDescending(a => a.IsDefault)
                .ThenByDescending(a => a.CreatedAt)
                .ToListAsync();
        }

        public async Task<UserAddress?> GetByIdAsync(Guid id, string firebaseUid)
        {
            return await _context.UserAddresses
                .FirstOrDefaultAsync(a => a.Id == id && a.FirebaseUid == firebaseUid);
        }

        public async Task<UserAddress> CreateAsync(UserAddress address)
        {
            address.CreatedAt = DateTime.UtcNow;

            // Nếu đây là địa chỉ mặc định, bỏ mặc định ở các địa chỉ khác
            if (address.IsDefault)
            {
                var existingDefaults = await _context.UserAddresses
                    .Where(a => a.FirebaseUid == address.FirebaseUid && a.IsDefault)
                    .ToListAsync();

                foreach (var item in existingDefaults)
                {
                    item.IsDefault = false;
                }
            }
            else
            {
                // Nếu chưa có địa chỉ nào, tự động đặt làm mặc định
                var hasAny = await _context.UserAddresses.AnyAsync(a => a.FirebaseUid == address.FirebaseUid);
                if (!hasAny)
                {
                    address.IsDefault = true;
                }
            }

            await _context.UserAddresses.AddAsync(address);
            await _context.SaveChangesAsync();
            return address;
        }

        public async Task<UserAddress> UpdateAsync(UserAddress address)
        {
            address.UpdatedAt = DateTime.UtcNow;

            if (address.IsDefault)
            {
                var existingDefaults = await _context.UserAddresses
                    .Where(a => a.FirebaseUid == address.FirebaseUid && a.Id != address.Id && a.IsDefault)
                    .ToListAsync();

                foreach (var item in existingDefaults)
                {
                    item.IsDefault = false;
                }
            }

            _context.UserAddresses.Update(address);
            await _context.SaveChangesAsync();
            return address;
        }

        public async Task<bool> DeleteAsync(Guid id, string firebaseUid)
        {
            var address = await GetByIdAsync(id, firebaseUid);
            if (address == null) return false;

            _context.UserAddresses.Remove(address);
            await _context.SaveChangesAsync();

            // Nếu vừa xóa địa chỉ mặc định mà vẫn còn địa chỉ khác, gán cái đầu tiên làm mặc định
            var remaining = await _context.UserAddresses
                .Where(a => a.FirebaseUid == firebaseUid)
                .OrderByDescending(a => a.CreatedAt)
                .FirstOrDefaultAsync();

            if (remaining != null && !await _context.UserAddresses.AnyAsync(a => a.FirebaseUid == firebaseUid && a.IsDefault))
            {
                remaining.IsDefault = true;
                await _context.SaveChangesAsync();
            }

            return true;
        }

        public async Task SetDefaultAsync(Guid id, string firebaseUid)
        {
            var addresses = await _context.UserAddresses
                .Where(a => a.FirebaseUid == firebaseUid)
                .ToListAsync();

            foreach (var item in addresses)
            {
                item.IsDefault = (item.Id == id);
            }

            await _context.SaveChangesAsync();
        }
    }
}
