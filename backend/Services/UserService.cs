using Soopi.Backend.DataAccess.Repositories;
using Soopi.Backend.Models.DTOs;
using Soopi.Backend.Models.Entities;

namespace Soopi.Backend.Services
{
    public class UserService : IUserService
    {
        private readonly IUserRepository _userRepository;
        private readonly IUserAddressRepository _addressRepository;

        public UserService(IUserRepository userRepository, IUserAddressRepository addressRepository)
        {
            _userRepository = userRepository;
            _addressRepository = addressRepository;
        }

        public async Task<UserProfileDto> GetOrCreateUserProfileAsync(string firebaseUid, string email, string? displayName = null, string? photoUrl = null)
        {
            var user = await _userRepository.GetByFirebaseUidAsync(firebaseUid);
            if (user == null)
            {
                user = new User
                {
                    FirebaseUid = firebaseUid,
                    Email = email,
                    FullName = !string.IsNullOrWhiteSpace(displayName) ? displayName : (email.Split('@')[0]),
                    AvatarUrl = photoUrl,
                    Gender = "Nam",
                    CreatedAt = DateTime.UtcNow
                };
                user = await _userRepository.CreateAsync(user);
            }

            return MapToUserProfileDto(user);
        }

        public async Task<UserProfileDto> UpdateUserProfileAsync(string firebaseUid, UpdateProfileDto dto)
        {
            var user = await _userRepository.GetByFirebaseUidAsync(firebaseUid);
            if (user == null)
            {
                user = new User
                {
                    FirebaseUid = firebaseUid,
                    FullName = !string.IsNullOrWhiteSpace(dto.FullName) ? dto.FullName : "Người dùng SOOPI",
                    Email = $"{firebaseUid}@soopi.vn",
                    PhoneNumber = dto.PhoneNumber,
                    AvatarUrl = dto.AvatarUrl,
                    Gender = dto.Gender ?? "Nam",
                    DateOfBirth = dto.DateOfBirth.HasValue ? DateTime.SpecifyKind(dto.DateOfBirth.Value, DateTimeKind.Utc) : null,
                    CreatedAt = DateTime.UtcNow
                };
                user = await _userRepository.CreateAsync(user);
                return MapToUserProfileDto(user);
            }

            if (!string.IsNullOrWhiteSpace(dto.FullName))
                user.FullName = dto.FullName;

            if (dto.PhoneNumber != null)
                user.PhoneNumber = dto.PhoneNumber;

            if (dto.AvatarUrl != null)
                user.AvatarUrl = dto.AvatarUrl;

            if (!string.IsNullOrWhiteSpace(dto.Gender))
                user.Gender = dto.Gender;

            if (dto.DateOfBirth.HasValue)
                user.DateOfBirth = DateTime.SpecifyKind(dto.DateOfBirth.Value, DateTimeKind.Utc);

            var updated = await _userRepository.UpdateAsync(user);
            return MapToUserProfileDto(updated);
        }

        public async Task<List<UserAddressDto>> GetUserAddressesAsync(string firebaseUid)
        {
            var addresses = await _addressRepository.GetByFirebaseUidAsync(firebaseUid);
            return addresses.Select(MapToAddressDto).ToList();
        }

        public async Task<UserAddressDto?> GetUserAddressByIdAsync(Guid id, string firebaseUid)
        {
            var address = await _addressRepository.GetByIdAsync(id, firebaseUid);
            return address != null ? MapToAddressDto(address) : null;
        }

        public async Task<UserAddressDto> CreateUserAddressAsync(string firebaseUid, CreateOrUpdateAddressDto dto)
        {
            var user = await _userRepository.GetByFirebaseUidAsync(firebaseUid);

            var address = new UserAddress
            {
                FirebaseUid = firebaseUid,
                UserId = user?.Id,
                Label = !string.IsNullOrWhiteSpace(dto.Label) ? dto.Label : "Nhà riêng",
                RecipientName = dto.RecipientName,
                PhoneNumber = dto.PhoneNumber,
                FullAddress = dto.FullAddress,
                Note = dto.Note,
                IsDefault = dto.IsDefault,
                CreatedAt = DateTime.UtcNow
            };

            var created = await _addressRepository.CreateAsync(address);
            return MapToAddressDto(created);
        }

        public async Task<UserAddressDto?> UpdateUserAddressAsync(Guid id, string firebaseUid, CreateOrUpdateAddressDto dto)
        {
            var address = await _addressRepository.GetByIdAsync(id, firebaseUid);
            if (address == null) return null;

            address.Label = !string.IsNullOrWhiteSpace(dto.Label) ? dto.Label : address.Label;
            address.RecipientName = dto.RecipientName;
            address.PhoneNumber = dto.PhoneNumber;
            address.FullAddress = dto.FullAddress;
            address.Note = dto.Note;
            address.IsDefault = dto.IsDefault;

            var updated = await _addressRepository.UpdateAsync(address);
            return MapToAddressDto(updated);
        }

        public async Task<bool> DeleteUserAddressAsync(Guid id, string firebaseUid)
        {
            return await _addressRepository.DeleteAsync(id, firebaseUid);
        }

        public async Task<bool> SetDefaultAddressAsync(Guid id, string firebaseUid)
        {
            var address = await _addressRepository.GetByIdAsync(id, firebaseUid);
            if (address == null) return false;

            await _addressRepository.SetDefaultAsync(id, firebaseUid);
            return true;
        }

        private static UserProfileDto MapToUserProfileDto(User user)
        {
            return new UserProfileDto
            {
                Id = user.Id,
                FirebaseUid = user.FirebaseUid,
                FullName = user.FullName,
                Email = user.Email,
                PhoneNumber = user.PhoneNumber ?? string.Empty,
                AvatarUrl = user.AvatarUrl ?? string.Empty,
                Gender = user.Gender ?? "Nam",
                DateOfBirth = user.DateOfBirth,
                CreatedAt = user.CreatedAt,
                UpdatedAt = user.UpdatedAt
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
                PhoneNumber = address.PhoneNumber,
                FullAddress = address.FullAddress,
                Note = address.Note,
                IsDefault = address.IsDefault,
                CreatedAt = address.CreatedAt
            };
        }
    }
}
