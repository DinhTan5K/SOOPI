using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.Controllers;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.Models;
using SoopiFoodBE.Services;
using Xunit;

namespace SoopiFoodBE.Tests;

public sealed class VoucherApiTests : IDisposable
{
    private readonly SoopiDbContext db = new(new DbContextOptionsBuilder<SoopiDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
    private readonly Guid restaurantId = Guid.NewGuid();
    private readonly Guid itemId = Guid.NewGuid();
    private readonly Guid customerId = Guid.NewGuid();

    public VoucherApiTests()
    {
        var owner = new AppUser { Id = Guid.NewGuid(), FirebaseUid = "owner", Role = "Owner" };
        db.Users.AddRange(owner, new AppUser { Id = customerId, FirebaseUid = "customer" });
        db.Restaurants.Add(new Restaurant { Id = restaurantId, OwnerId = owner.Id, ApprovalStatus = "Approved",
            Categories = [new MenuCategory { Id = Guid.NewGuid(), Items = [new MenuItem { Id = itemId, Price = 40000 }] }] });
        db.Carts.Add(new ShoppingCart { Id = Guid.NewGuid(), UserId = customerId, RestaurantId = restaurantId,
            Items = [new CartItem { Id = Guid.NewGuid(), MenuItemId = itemId, Quantity = 2 }] });
        db.SaveChanges();
    }

    private CurrentAccount Account(string uid) => new(db, new HttpContextAccessor { HttpContext = new DefaultHttpContext {
        User = new ClaimsPrincipal(new ClaimsIdentity([new Claim("user_id", uid)], "Test")) } });
    private MerchantVouchersController Merchant(string uid = "owner") => new(db, new RestaurantManagement(db, Account(uid)));
    private VoucherInput Input(Guid? menuItem = null) => new("TEST20", menuItem, "Percent", 20);

    [Fact]
    public async Task CreateNormalizesAndRejectsDuplicateOrForeignMenu()
    {
        Assert.IsType<CreatedAtActionResult>(await Merchant().Create(restaurantId, Input(itemId), default));
        Assert.Equal(restaurantId, (await db.Coupons.SingleAsync()).RestaurantId);
        var duplicate = await Assert.ThrowsAsync<ManagementException>(() => Merchant().Create(restaurantId, Input() with { Code = "test20" }, default));
        Assert.Equal(409, duplicate.Status);
        var wrongItem = await Assert.ThrowsAsync<ManagementException>(() => Merchant().Create(restaurantId, Input(Guid.NewGuid()), default));
        Assert.Equal(400, wrongItem.Status);
    }

    [Theory]
    [InlineData("Percent", 101)]
    [InlineData("Fixed", 0)]
    [InlineData("Other", 10)]
    [InlineData("Fixed", 1.001)]
    public async Task InvalidDiscountFails(string type, decimal value)
    {
        var e = await Assert.ThrowsAsync<ManagementException>(() => Merchant().Create(restaurantId,
            Input() with { DiscountType = type, DiscountValue = value }, default));
        Assert.Equal(400, e.Status);
    }

    [Fact]
    public async Task InvalidDatesAndLimitsFail()
    {
        var now = DateTimeOffset.UtcNow;
        foreach (var input in new[] { Input() with { StartsAt = now, EndsAt = now.AddMinutes(-1) },
            Input() with { UsageLimit = 0 }, Input() with { MaxDiscount = -1 }, Input() with { MinOrderAmount = -1 } })
            Assert.Equal(400, (await Assert.ThrowsAsync<ManagementException>(() => Merchant().Create(restaurantId, input, default))).Status);
    }

    [Fact]
    public async Task OtherOwnerCannotReadCreateOrToggle()
    {
        var other = new AppUser { Id = Guid.NewGuid(), FirebaseUid = "other", Role = "Owner" };
        db.Users.Add(other); await db.SaveChangesAsync();
        Assert.Equal(404, (await Assert.ThrowsAsync<ManagementException>(() => Merchant("other").List(restaurantId, default))).Status);
        Assert.Equal(404, (await Assert.ThrowsAsync<ManagementException>(() => Merchant("other").Create(restaurantId, Input(), default))).Status);
        Assert.Equal(404, (await Assert.ThrowsAsync<ManagementException>(() => Merchant("other").Status(restaurantId, Guid.NewGuid(), new(false), default))).Status);
    }

    [Fact]
    public async Task PreviewUsesCartPricesWithoutConsumingAndChecksCustomer()
    {
        await Merchant().Create(restaurantId, Input(itemId), default);
        var controller = new VouchersController(db, new VoucherService(db), Account("customer"));
        var response = Assert.IsType<OkObjectResult>(await controller.Preview(customerId, new("test20"), default));
        var preview = Assert.IsType<VoucherPreview>(response.Value);
        Assert.Equal(80000, preview.EligibleAmount);
        Assert.Equal(16000, preview.DiscountAmount);
        Assert.Equal(79000, preview.TotalAmount);
        Assert.Equal(0, (await db.Coupons.SingleAsync()).UsedCount);
        Assert.IsType<ForbidResult>(await controller.Preview(Guid.NewGuid(), new("test20"), default));
    }

    [Fact]
    public async Task InvalidAndWrongRestaurantCodesAreRejected()
    {
        await Merchant().Create(restaurantId, Input(), default);
        var coupon = await db.Coupons.SingleAsync();
        var service = new VoucherService(db);
        VoucherLine[] lines = [new(itemId, 40000, 2)];
        await Assert.ThrowsAsync<InvalidOperationException>(() => service.Evaluate("TEST20", Guid.NewGuid(), lines, default));
        coupon.EndsAt = DateTime.UtcNow.AddDays(-1); await db.SaveChangesAsync();
        await Assert.ThrowsAsync<InvalidOperationException>(() => service.Evaluate("TEST20", restaurantId, lines, default));
        coupon.EndsAt = null; coupon.UsageLimit = 1; coupon.UsedCount = 1; await db.SaveChangesAsync();
        await Assert.ThrowsAsync<InvalidOperationException>(() => service.Evaluate("TEST20", restaurantId, lines, default));
        coupon.UsedCount = 0; coupon.IsActive = false; await db.SaveChangesAsync();
        await Assert.ThrowsAsync<InvalidOperationException>(() => service.Evaluate("TEST20", restaurantId, lines, default));
    }

    public void Dispose() => db.Dispose();
}
