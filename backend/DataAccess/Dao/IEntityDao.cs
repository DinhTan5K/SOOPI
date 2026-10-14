using SoopiFoodBE.Models;

namespace SoopiFoodBE.DataAccess.Dao;

public interface IEntityDao<T> where T : class, IEntity
{
    Task<T?> GetAsync(Guid id, CancellationToken ct = default);
    Task<List<T>> ListAsync(CancellationToken ct = default);
    Task<T> AddAsync(T entity, CancellationToken ct = default);
    Task DeleteAsync(T entity, CancellationToken ct = default);
    Task SaveAsync(CancellationToken ct = default);
}
