using Soopi.Backend.Models.Entities;

namespace Soopi.Backend.DataAccess.Repositories
{
    public interface IUserAddressRepository
    {
        Task<List<UserAddress>> GetByFirebaseUidAsync(string firebaseUid);
        Task<UserAddress?> GetByIdAsync(Guid id, string firebaseUid);
        Task<UserAddress> CreateAsync(UserAddress address);
        Task<UserAddress> UpdateAsync(UserAddress address);
        Task<bool> DeleteAsync(Guid id, string firebaseUid);
        Task SetDefaultAsync(Guid id, string firebaseUid);
    }
}
