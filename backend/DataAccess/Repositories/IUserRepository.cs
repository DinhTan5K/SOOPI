using Soopi.Backend.Models.Entities;

namespace Soopi.Backend.DataAccess.Repositories
{
    public interface IUserRepository
    {
        Task<User?> GetByFirebaseUidAsync(string firebaseUid);
        Task<User?> GetByEmailAsync(string email);
        Task<User> CreateAsync(User user);
        Task<User> UpdateAsync(User user);
    }
}
