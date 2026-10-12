using Microsoft.EntityFrameworkCore;
using SoopiFoodBE.Models;

namespace SoopiFoodBE.DataAccess;

public sealed class SoopiDbContext(
    DbContextOptions<SoopiDbContext> options) : DbContext(options)
{
    public DbSet<AppUser> Users => Set<AppUser>();
    public DbSet<UserAddress> Addresses => Set<UserAddress>();
    public DbSet<Restaurant> Restaurants => Set<Restaurant>();
    public DbSet<OpeningHour> OpeningHours => Set<OpeningHour>();
    public DbSet<MenuCategory> MenuCategories => Set<MenuCategory>();
    public DbSet<MenuItem> MenuItems => Set<MenuItem>();
    public DbSet<ShoppingCart> Carts => Set<ShoppingCart>();
    public DbSet<CartItem> CartItems => Set<CartItem>();
    public DbSet<Coupon> Coupons => Set<Coupon>();
    public DbSet<FoodOrder> Orders => Set<FoodOrder>();
    public DbSet<OrderItem> OrderItems => Set<OrderItem>();
    public DbSet<OrderStatusHistory> OrderStatusHistory => Set<OrderStatusHistory>();
    public DbSet<Review> Reviews => Set<Review>();
    public DbSet<Favorite> Favorites => Set<Favorite>();
    public DbSet<Payment> Payments => Set<Payment>();
    public DbSet<DeliveryLocation> DeliveryLocations => Set<DeliveryLocation>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        ConfigureUsers(modelBuilder);
        ConfigureRestaurants(modelBuilder);
        ConfigureCartAndMenu(modelBuilder);
        ConfigureOrders(modelBuilder);
        ConfigureReviewsAndPayments(modelBuilder);
    }

    private static void ConfigureUsers(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<UserAddress>().ToTable("UserAddresses");

        modelBuilder.Entity<AppUser>()
            .HasIndex(user => user.Email)
            .IsUnique();
        modelBuilder.Entity<AppUser>()
            .HasIndex(user => user.FirebaseUid)
            .IsUnique()
            .HasFilter("[FirebaseUid] IS NOT NULL");
        modelBuilder.Entity<AppUser>().Property(user => user.Email).HasMaxLength(255);
        modelBuilder.Entity<AppUser>().Property(user => user.Role).HasMaxLength(20);

        modelBuilder.Entity<UserAddress>().Property(address => address.Latitude)
            .HasPrecision(10, 7);
        modelBuilder.Entity<UserAddress>().Property(address => address.Longitude)
            .HasPrecision(10, 7);
    }

    private static void ConfigureRestaurants(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Restaurant>().Property(restaurant => restaurant.AverageRating)
            .HasPrecision(3, 2);
        modelBuilder.Entity<Restaurant>().Property(restaurant => restaurant.Latitude)
            .HasPrecision(10, 7);
        modelBuilder.Entity<Restaurant>().Property(restaurant => restaurant.Longitude)
            .HasPrecision(10, 7);
        modelBuilder.Entity<OpeningHour>()
            .HasIndex(hour => new { hour.RestaurantId, hour.DayOfWeek })
            .IsUnique();
        modelBuilder.Entity<Restaurant>()
            .HasOne(restaurant => restaurant.Owner)
            .WithMany()
            .HasForeignKey(restaurant => restaurant.OwnerId)
            .OnDelete(DeleteBehavior.SetNull);
    }

    private static void ConfigureCartAndMenu(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<MenuItem>().Property(item => item.Price).HasPrecision(12, 2);
        modelBuilder.Entity<ShoppingCart>().HasIndex(cart => cart.UserId).IsUnique();
        modelBuilder.Entity<CartItem>()
            .HasIndex(item => new { item.CartId, item.MenuItemId })
            .IsUnique();

        modelBuilder.Entity<Coupon>().HasIndex(coupon => coupon.Code).IsUnique();
        modelBuilder.Entity<Coupon>().Property(coupon => coupon.DiscountValue)
            .HasPrecision(12, 2);
        modelBuilder.Entity<Coupon>().Property(coupon => coupon.MinOrderAmount)
            .HasPrecision(12, 2);
        modelBuilder.Entity<Coupon>().Property(coupon => coupon.MaxDiscount)
            .HasPrecision(12, 2);
    }

    private static void ConfigureOrders(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<FoodOrder>().HasIndex(order => order.OrderCode).IsUnique();
        modelBuilder.Entity<FoodOrder>()
            .HasIndex(order => new { order.CustomerId, order.CreatedAt });
        modelBuilder.Entity<FoodOrder>().Property(order => order.Subtotal)
            .HasPrecision(12, 2);
        modelBuilder.Entity<FoodOrder>().Property(order => order.DiscountAmount)
            .HasPrecision(12, 2);
        modelBuilder.Entity<FoodOrder>().Property(order => order.DeliveryFee)
            .HasPrecision(12, 2);
        modelBuilder.Entity<FoodOrder>().Property(order => order.TotalAmount)
            .HasPrecision(12, 2);
        modelBuilder.Entity<FoodOrder>()
            .HasOne(order => order.Customer)
            .WithMany()
            .HasForeignKey(order => order.CustomerId)
            .OnDelete(DeleteBehavior.Restrict);
        modelBuilder.Entity<FoodOrder>()
            .HasOne(order => order.Shipper)
            .WithMany()
            .HasForeignKey(order => order.ShipperId)
            .OnDelete(DeleteBehavior.Restrict);
        modelBuilder.Entity<FoodOrder>()
            .HasOne(order => order.Address)
            .WithMany()
            .HasForeignKey(order => order.AddressId)
            .OnDelete(DeleteBehavior.SetNull);

        modelBuilder.Entity<OrderItem>().Property(item => item.UnitPrice)
            .HasPrecision(12, 2);
        modelBuilder.Entity<DeliveryLocation>().HasKey(location => location.Id);
        modelBuilder.Entity<DeliveryLocation>()
            .HasIndex(location => new { location.OrderId, location.RecordedAt });
        modelBuilder.Entity<DeliveryLocation>().Property(location => location.Latitude)
            .HasPrecision(10, 7);
        modelBuilder.Entity<DeliveryLocation>().Property(location => location.Longitude)
            .HasPrecision(10, 7);
    }

    private static void ConfigureReviewsAndPayments(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Review>().HasIndex(review => review.OrderId).IsUnique();
        modelBuilder.Entity<Review>()
            .HasOne(review => review.Customer)
            .WithMany()
            .HasForeignKey(review => review.CustomerId)
            .OnDelete(DeleteBehavior.Restrict);
        modelBuilder.Entity<Review>()
            .HasOne(review => review.Shipper)
            .WithMany()
            .HasForeignKey(review => review.ShipperId)
            .OnDelete(DeleteBehavior.Restrict);
        modelBuilder.Entity<Review>()
            .HasOne(review => review.Restaurant)
            .WithMany()
            .HasForeignKey(review => review.RestaurantId)
            .OnDelete(DeleteBehavior.Restrict);

        modelBuilder.Entity<Favorite>()
            .HasIndex(favorite => new { favorite.UserId, favorite.RestaurantId })
            .IsUnique();
        modelBuilder.Entity<Payment>().Property(payment => payment.Amount)
            .HasPrecision(12, 2);
        modelBuilder.Entity<Payment>().HasIndex(payment => payment.ProviderReference);
    }
}
