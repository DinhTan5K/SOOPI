using Microsoft.EntityFrameworkCore;
using Npgsql;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.Models;
using Xunit;

namespace SoopiFoodBE.Tests;

public sealed class PostgresFactAttribute : FactAttribute
{
    public PostgresFactAttribute()
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("SOOPI_TEST_CONNECTION")))
            Skip = "Set SOOPI_TEST_CONNECTION to a PostgreSQL connection with CREATE DATABASE permission.";
    }
}

public sealed class VoucherPostgresTests
{
    [PostgresFact]
    public async Task UpgradeIsRepeatableAndConcurrentConsumptionRollsBackLosingOrder()
    {
        var source = Environment.GetEnvironmentVariable("SOOPI_TEST_CONNECTION")!;
        var databaseName = "soopi_voucher_test_" + Guid.NewGuid().ToString("N");
        await using var admin = new NpgsqlConnection(source);
        await admin.OpenAsync();
        await using (var create = new NpgsqlCommand($"CREATE DATABASE \"{databaseName}\"", admin))
            await create.ExecuteNonQueryAsync();
        try
        {
            var builder = new NpgsqlConnectionStringBuilder(source) { Database = databaseName, Pooling = false };
            await using var sql = new NpgsqlConnection(builder.ConnectionString);
            await sql.OpenAsync();
            var schema = await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "sql", "soopifood.sql"));
            // Recreate the pre-upgrade coupon shape while keeping all other current tables.
            schema = schema.Replace("    \"RestaurantId\" uuid REFERENCES \"Restaurants\"(\"Id\") ON DELETE RESTRICT,", "")
                .Replace("    \"MenuItemId\" uuid REFERENCES \"MenuItems\"(\"Id\") ON DELETE RESTRICT,", "")
                .Replace("    CONSTRAINT \"CK_Coupons_Scope\" CHECK (\"MenuItemId\" IS NULL OR \"RestaurantId\" IS NOT NULL),", "");
            await using (var init = new NpgsqlCommand(schema, sql)) await init.ExecuteNonQueryAsync();
            await using (var seed = new NpgsqlCommand("INSERT INTO \"Coupons\" (\"Code\",\"DiscountType\",\"DiscountValue\",\"UsedCount\") VALUES ('LEGACY','Fixed',1000,2)", sql))
                await seed.ExecuteNonQueryAsync();
            var upgrade = await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "sql", "voucher_management_upgrade.sql"));
            for (var i = 0; i < 2; i++)
            {
                await using var migration = new NpgsqlCommand(upgrade, sql);
                await migration.ExecuteNonQueryAsync();
            }
            var options = new DbContextOptionsBuilder<SoopiDbContext>().UseNpgsql(builder.ConnectionString).Options;
            await using var setup = new SoopiDbContext(options);
            Assert.Equal(2, (await setup.Coupons.SingleAsync()).UsedCount);
            var customer = new AppUser { Id = Guid.NewGuid(), FirebaseUid = "customer", Email = "customer@test.local" };
            var restaurant = new Restaurant { Id = Guid.NewGuid(), Name = "Test", Address = "Test", City = "Test" };
            var coupon = new Coupon { Id = Guid.NewGuid(), Code = "LAST", RestaurantId = restaurant.Id,
                DiscountType = "Fixed", DiscountValue = 1000, UsageLimit = 1 };
            setup.AddRange(customer, restaurant, coupon);
            await setup.SaveChangesAsync();

            await using var first = new SoopiDbContext(options);
            await using var second = new SoopiDbContext(options);
            var firstCoupon = await first.Coupons.SingleAsync(c => c.Code == "LAST");
            var secondCoupon = await second.Coupons.SingleAsync(c => c.Code == "LAST");
            firstCoupon.UsedCount++; secondCoupon.UsedCount++;
            FoodOrder NewOrder() => new() { Id = Guid.NewGuid(), CustomerId = customer.Id, RestaurantId = restaurant.Id,
                Subtotal = 50000, DiscountAmount = 1000, DeliveryFee = 15000, TotalAmount = 64000, CouponCode = "LAST" };
            var winningOrder = NewOrder(); var losingOrder = NewOrder();
            first.Orders.Add(winningOrder); second.Orders.Add(losingOrder);
            await first.SaveChangesAsync();
            await Assert.ThrowsAsync<DbUpdateConcurrencyException>(() => second.SaveChangesAsync());
            await using var verify = new SoopiDbContext(options);
            Assert.Equal(1, (await verify.Coupons.SingleAsync(c => c.Code == "LAST")).UsedCount);
            Assert.True(await verify.Orders.AnyAsync(o => o.Id == winningOrder.Id));
            Assert.False(await verify.Orders.AnyAsync(o => o.Id == losingOrder.Id));
        }
        finally
        {
            // The identifier is generated above and only ever names this test's isolated database.
            await using var drop = new NpgsqlCommand($"DROP DATABASE \"{databaseName}\" WITH (FORCE)", admin);
            await drop.ExecuteNonQueryAsync();
        }
    }
}
