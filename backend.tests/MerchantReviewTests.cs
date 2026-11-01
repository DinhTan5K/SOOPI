using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.Controllers;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.Models;
using SoopiFoodBE.Services;
using Xunit;

public sealed class MerchantReviewTests
{
    private static SoopiDbContext Database() => new(new DbContextOptionsBuilder<SoopiDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);

    private static MerchantReviewsController Controller(SoopiDbContext db, string? uid)
    {
        var http = new DefaultHttpContext();
        if (uid != null) http.User = new ClaimsPrincipal(new ClaimsIdentity(
            [new Claim("user_id", uid)], "test"));
        return new(db, new CurrentAccount(db, new HttpContextAccessor { HttpContext = http }));
    }

    private static AppUser User(string uid, string role = "Owner") => new()
        { Id = Guid.NewGuid(), FirebaseUid = uid, FullName = uid, Role = role };

    [Fact]
    public async Task OnlyReturnsOwnedRestaurantReviewsNewestFirstWithGlobalSummary()
    {
        await using var db = Database();
        var owner = User("owner");
        var other = User("other");
        var customer = User("customer", "Customer");
        var shop = new Restaurant { Id = Guid.NewGuid(), Owner = owner };
        var otherShop = new Restaurant { Id = Guid.NewGuid(), Owner = other };
        db.AddRange(owner, other, customer, shop, otherShop);
        var now = DateTime.UtcNow;
        foreach (var (restaurant, rating, date) in new[] {
            (shop, 2, now.AddDays(-1)), (shop, 4, now), (otherShop, 1, now.AddDays(1)) })
        {
            var order = new FoodOrder { Id = Guid.NewGuid(), Restaurant = restaurant,
                Customer = customer, OrderCode = Guid.NewGuid().ToString(), Status = "Delivered" };
            db.Add(new Review { Id = Guid.NewGuid(), Order = order, Restaurant = restaurant,
                Customer = customer, RestaurantRating = (byte)rating, Comment = "Đánh giá thật", CreatedAt = date });
        }
        await db.SaveChangesAsync();
        var result = Assert.IsType<OkObjectResult>(await Controller(db, owner.FirebaseUid).List(shop.Id, 1, 1));
        var page = Assert.IsType<MerchantReviewPage>(result.Value);
        Assert.Equal(2, page.Total);
        Assert.Equal(3, page.AverageRating);
        Assert.Equal(4, Assert.Single(page.Items).RestaurantRating);
        Assert.Equal("customer", page.Items[0].CustomerName);
        var second = Assert.IsType<MerchantReviewPage>(Assert.IsType<OkObjectResult>(
            await Controller(db, owner.FirebaseUid).List(shop.Id, 2, 1)).Value);
        Assert.Equal(2, Assert.Single(second.Items).RestaurantRating);
        Assert.IsType<NotFoundResult>(await Controller(db, owner.FirebaseUid).List(otherShop.Id));
    }

    [Fact]
    public async Task EmptyAndOutOfRangePagesReturnEmptyRows()
    {
        await using var db = Database();
        var owner = User("owner");
        var shop = new Restaurant { Id = Guid.NewGuid(), Owner = owner };
        db.AddRange(owner, shop);
        await db.SaveChangesAsync();
        var page = Assert.IsType<MerchantReviewPage>(Assert.IsType<OkObjectResult>(
            await Controller(db, owner.FirebaseUid).List(shop.Id, 2)).Value);
        Assert.Empty(page.Items);
        Assert.Equal(0, page.Total);
        Assert.Equal(0, page.AverageRating);
    }

    [Fact]
    public async Task RequiresAuthenticationOwnerAccessAndValidPagination()
    {
        await using var db = Database();
        var customer = User("customer", "Customer");
        db.Add(customer);
        await db.SaveChangesAsync();
        Assert.NotNull(Attribute.GetCustomAttribute(typeof(MerchantReviewsController), typeof(AuthorizeAttribute)));
        var unauthenticated = await Assert.ThrowsAsync<ManagementException>(() => Controller(db, null).List(Guid.NewGuid()));
        Assert.Equal(401, unauthenticated.Status);
        var forbidden = await Assert.ThrowsAsync<ManagementException>(() => Controller(db, customer.FirebaseUid).List(Guid.NewGuid()));
        Assert.Equal(403, forbidden.Status);
        foreach (var (page, size) in new[] { (0, 20), (1, 0), (1, 101) })
        {
            var invalid = await Assert.ThrowsAsync<ManagementException>(() => Controller(db, null).List(Guid.NewGuid(), page, size));
            Assert.Equal(400, invalid.Status);
        }
    }
}
