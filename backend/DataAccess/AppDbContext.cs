using Microsoft.EntityFrameworkCore;
using Soopi.Backend.Models.Entities;

namespace Soopi.Backend.DataAccess
{
    public class AppDbContext : DbContext
    {
        public AppDbContext(DbContextOptions<AppDbContext> options) : base(options)
        {
        }

        public DbSet<User> Users { get; set; } = null!;
        public DbSet<UserAddress> UserAddresses { get; set; } = null!;

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            // User configuration
            modelBuilder.Entity<User>(entity =>
            {
                entity.HasIndex(u => u.FirebaseUid).IsUnique();
                entity.HasIndex(u => u.Email);
            });

            // UserAddress configuration
            modelBuilder.Entity<UserAddress>(entity =>
            {
                entity.HasIndex(a => a.FirebaseUid);

                entity.HasOne(a => a.User)
                      .WithMany(u => u.Addresses)
                      .HasForeignKey(a => a.UserId)
                      .OnDelete(DeleteBehavior.Cascade);
            });
        }
    }
}
