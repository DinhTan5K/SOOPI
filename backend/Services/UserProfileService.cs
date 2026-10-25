using Microsoft.EntityFrameworkCore;
using Soopi.Backend.Models.DTOs;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.Models;

namespace Soopi.Backend.Services
{
    public class UserProfileService : IUserProfileService
    {
        private readonly SoopiDbContext _db;
        private readonly ILogger<UserProfileService> _logger;
        private readonly IConfiguration? _config;

        public UserProfileService(SoopiDbContext db, ILogger<UserProfileService> logger, IConfiguration? config = null)
        {
            _db = db;
            _logger = logger;
            _config = config;
        }

        public async Task<UserProfileDto> GetOrCreateUserProfileAsync(string firebaseUid, string email, string? displayName = null, string? photoUrl = null)
        {
            var user = await _db.Users
                .Include(u => u.Addresses)
                .FirstOrDefaultAsync(u => u.FirebaseUid == firebaseUid);

            var adminEmails = _config?.GetSection("AdminSettings:AdminEmails").Get<string[]>() ?? [];

            if (user == null)
            {
                var isAdmin = adminEmails.Any(e => string.Equals(e, email, StringComparison.OrdinalIgnoreCase));
                user = new AppUser
                {
                    Id = Guid.NewGuid(),
                    FirebaseUid = firebaseUid,
                    Email = email,
                    FullName = !string.IsNullOrEmpty(displayName) ? displayName : email.Split('@')[0],
                    AvatarUrl = photoUrl,
                    Gender = "Nam",
                    Role = isAdmin ? "Admin" : "Customer",
                    CreatedAt = DateTimeOffset.UtcNow
                };
                await _db.Users.AddAsync(user);
                await _db.SaveChangesAsync();
                _logger.LogInformation("Đã tự động tạo hồ sơ người dùng mới trong DB cho UID: {Uid}", firebaseUid);
            }
            else if (adminEmails.Any(e => string.Equals(e, user.Email, StringComparison.OrdinalIgnoreCase)) && user.Role != "Admin")
            {
                user.Role = "Admin";
                user.UpdatedAt = DateTimeOffset.UtcNow;
                await _db.SaveChangesAsync();
                _logger.LogInformation("Đã tự động đồng bộ vai trò Admin cho: {Email}", user.Email);
            }

            return MapToProfileDto(user);
        }

        public async Task<UserProfileDto> UpdateUserProfileAsync(string firebaseUid, UpdateProfileDto dto)
        {
            var user = await _db.Users.FirstOrDefaultAsync(u => u.FirebaseUid == firebaseUid);

            if (user == null)
            {
                user = new AppUser
                {
                    Id = Guid.NewGuid(),
                    FirebaseUid = firebaseUid,
                    Email = "",
                    FullName = !string.IsNullOrEmpty(dto.FullName) ? dto.FullName : "Khách hàng SOOPI",
                    AvatarUrl = dto.AvatarUrl,
                    Phone = dto.PhoneNumber,
                    Gender = !string.IsNullOrEmpty(dto.Gender) ? dto.Gender : "Nam",
                    Role = "Customer",
                    CreatedAt = DateTimeOffset.UtcNow,
                    UpdatedAt = DateTimeOffset.UtcNow,
                };
                if (dto.DateOfBirth.HasValue)
                {
                    var d = dto.DateOfBirth.Value;
                    user.DateOfBirth = new DateTimeOffset(d.Year, d.Month, d.Day, 0, 0, 0, TimeSpan.Zero);
                }
                await _db.Users.AddAsync(user);
            }
            else
            {
                if (!string.IsNullOrEmpty(dto.FullName)) user.FullName = dto.FullName;
                if (dto.PhoneNumber != null) user.Phone = dto.PhoneNumber;
                if (dto.AvatarUrl != null) user.AvatarUrl = dto.AvatarUrl;
                if (!string.IsNullOrEmpty(dto.Gender)) user.Gender = dto.Gender;
                if (dto.DateOfBirth.HasValue)
                {
                    var d = dto.DateOfBirth.Value;
                    user.DateOfBirth = new DateTimeOffset(d.Year, d.Month, d.Day, 0, 0, 0, TimeSpan.Zero);
                }
                user.UpdatedAt = DateTimeOffset.UtcNow;
            }

            await _db.SaveChangesAsync();
            return MapToProfileDto(user);
        }

        public async Task<List<UserAddressDto>> GetUserAddressesAsync(string firebaseUid)
        {
            var addresses = await _db.Addresses
                .Where(a => a.FirebaseUid == firebaseUid)
                .OrderByDescending(a => a.IsDefault)
                .ThenByDescending(a => a.CreatedAt)
                .ToListAsync();

            return addresses.Select(MapToAddressDto).ToList();
        }

        public async Task<UserAddressDto?> GetUserAddressByIdAsync(Guid id, string firebaseUid)
        {
            var address = await _db.Addresses.FirstOrDefaultAsync(a => a.Id == id && a.FirebaseUid == firebaseUid);
            return address == null ? null : MapToAddressDto(address);
        }

        public async Task<UserAddressDto> CreateUserAddressAsync(string firebaseUid, CreateOrUpdateAddressDto dto)
        {
            var user = await _db.Users.FirstOrDefaultAsync(u => u.FirebaseUid == firebaseUid)
                ?? throw new KeyNotFoundException($"Không tìm thấy user với FirebaseUid: {firebaseUid}");

            if (dto.IsDefault)
            {
                var existingDefaults = await _db.Addresses
                    .Where(a => a.UserId == user.Id && a.IsDefault)
                    .ToListAsync();
                foreach (var addr in existingDefaults)
                {
                    addr.IsDefault = false;
                }
            }

            var address = new UserAddress
            {
                Id = Guid.NewGuid(),
                UserId = user.Id,
                FirebaseUid = firebaseUid,
                Label = dto.Label ?? "Nhà riêng",
                RecipientName = dto.RecipientName,
                Phone = dto.PhoneNumber,
                FullAddress = dto.FullAddress,
                Note = dto.Note,
                IsDefault = dto.IsDefault,
                CreatedAt = DateTimeOffset.UtcNow
            };

            await _db.Addresses.AddAsync(address);
            await _db.SaveChangesAsync();

            return MapToAddressDto(address);
        }

        public async Task<UserAddressDto?> UpdateUserAddressAsync(Guid id, string firebaseUid, CreateOrUpdateAddressDto dto)
        {
            var address = await _db.Addresses.FirstOrDefaultAsync(a => a.Id == id && a.FirebaseUid == firebaseUid);
            if (address == null) return null;

            if (dto.IsDefault)
            {
                var otherAddresses = await _db.Addresses
                    .Where(a => a.UserId == address.UserId && a.Id != id && a.IsDefault)
                    .ToListAsync();
                foreach (var other in otherAddresses)
                {
                    other.IsDefault = false;
                }
            }

            if (!string.IsNullOrEmpty(dto.Label)) address.Label = dto.Label;
            address.RecipientName = dto.RecipientName;
            address.Phone = dto.PhoneNumber;
            address.FullAddress = dto.FullAddress;
            address.Note = dto.Note;
            address.IsDefault = dto.IsDefault;
            address.UpdatedAt = DateTimeOffset.UtcNow;

            await _db.SaveChangesAsync();
            return MapToAddressDto(address);
        }

        public async Task<bool> DeleteUserAddressAsync(Guid id, string firebaseUid)
        {
            var address = await _db.Addresses.FirstOrDefaultAsync(a => a.Id == id && a.FirebaseUid == firebaseUid);
            if (address == null) return false;

            _db.Addresses.Remove(address);
            await _db.SaveChangesAsync();
            return true;
        }

        public async Task<bool> SetDefaultAddressAsync(Guid id, string firebaseUid)
        {
            var target = await _db.Addresses.FirstOrDefaultAsync(a => a.Id == id && a.FirebaseUid == firebaseUid);
            if (target == null) return false;

            var userAddresses = await _db.Addresses.Where(a => a.UserId == target.UserId).ToListAsync();
            foreach (var addr in userAddresses)
            {
                addr.IsDefault = (addr.Id == id);
            }

            await _db.SaveChangesAsync();
            return true;
        }

        private static UserProfileDto MapToProfileDto(AppUser user)
        {
            return new UserProfileDto
            {
                Id = user.Id,
                FirebaseUid = user.FirebaseUid,
                FullName = user.FullName ?? string.Empty,
                Email = user.Email ?? string.Empty,
                PhoneNumber = user.Phone ?? string.Empty,
                AvatarUrl = user.AvatarUrl ?? string.Empty,
                Gender = user.Gender ?? "Nam",
                DateOfBirth = user.DateOfBirth?.DateTime,
                Role = user.Role ?? "Customer",
                CreatedAt = user.CreatedAt.DateTime,
                UpdatedAt = user.UpdatedAt?.DateTime
            };
        }

        private static UserAddressDto MapToAddressDto(UserAddress address)
        {
            return new UserAddressDto
            {
                Id = address.Id,
                FirebaseUid = address.FirebaseUid,
                Label = address.Label,
                RecipientName = address.RecipientName,
                PhoneNumber = address.Phone,
                FullAddress = address.FullAddress,
                Note = address.Note,
                IsDefault = address.IsDefault,
                CreatedAt = address.CreatedAt.DateTime
            };
        }
    }
}
