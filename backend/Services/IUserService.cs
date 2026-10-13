using Soopi.Backend.Models.DTOs;

namespace Soopi.Backend.Services
{
    public interface IUserService
    {
        Task<UserProfileDto> GetOrCreateUserProfileAsync(string firebaseUid, string email, string? displayName = null, string? photoUrl = null);
        Task<UserProfileDto> UpdateUserProfileAsync(string firebaseUid, UpdateProfileDto dto);

        Task<List<UserAddressDto>> GetUserAddressesAsync(string firebaseUid);
        Task<UserAddressDto?> GetUserAddressByIdAsync(Guid id, string firebaseUid);
        Task<UserAddressDto> CreateUserAddressAsync(string firebaseUid, CreateOrUpdateAddressDto dto);
        Task<UserAddressDto?> UpdateUserAddressAsync(Guid id, string firebaseUid, CreateOrUpdateAddressDto dto);
        Task<bool> DeleteUserAddressAsync(Guid id, string firebaseUid);
        Task<bool> SetDefaultAddressAsync(Guid id, string firebaseUid);
    }
}
