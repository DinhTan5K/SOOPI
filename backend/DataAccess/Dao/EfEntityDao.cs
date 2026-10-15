using Microsoft.EntityFrameworkCore;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.Models;

namespace SoopiFoodBE.DataAccess.Dao;

public sealed class EfEntityDao<T>(SoopiDbContext db) : IEntityDao<T>
    where T : class, IEntity
{
    private readonly DbSet<T> _set = db.Set<T>();

    public Task<T?> GetAsync(Guid id, CancellationToken ct = default) =>
        _set.FindAsync([id], ct).AsTask();

    public Task<List<T>> ListAsync(CancellationToken ct = default) =>
        _set.AsNoTracking().ToListAsync(ct);

    public async Task<T> AddAsync(T entity, CancellationToken ct = default)
    {
        await _set.AddAsync(entity, ct);
        await db.SaveChangesAsync(ct);
        return entity;
    }

    public async Task DeleteAsync(T entity, CancellationToken ct = default)
    {
        _set.Remove(entity);
        await db.SaveChangesAsync(ct);
    }

    public Task SaveAsync(CancellationToken ct = default) =>
        db.SaveChangesAsync(ct);
}
