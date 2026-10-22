using SoopiFoodBE.Models;
using SoopiFoodBE.Services;
using Xunit;

namespace SoopiFoodBE.Tests;

public sealed class VoucherTests
{
    private static readonly Guid Food = Guid.NewGuid();
    private static readonly Guid OtherFood = Guid.NewGuid();
    private static readonly VoucherLine[] Lines = [new(Food, 40000, 2), new(OtherFood, 20000, 1)];

    [Theory]
    [InlineData(false, "Percent", 20, 100000, 20000)]
    [InlineData(true, "Percent", 20, 80000, 16000)]
    [InlineData(true, "Fixed", 30000, 80000, 30000)]
    [InlineData(true, "Fixed", 90000, 80000, 80000)]
    public void AppliesOnlyToEligibleSubtotal(bool itemScope, string type, decimal value, decimal eligible, decimal discount)
    {
        var c = new Coupon { MenuItemId = itemScope ? Food : null, DiscountType = type, DiscountValue = value };
        Assert.Equal((eligible, discount), VoucherService.Calculate(c, Lines));
    }

    [Fact]
    public void MinimumUsesWholeOrderAndMaximumCapsDiscount()
    {
        var c = new Coupon { MenuItemId = Food, DiscountType = "Percent", DiscountValue = 50,
            MinOrderAmount = 100000, MaxDiscount = 15000 };
        Assert.Equal((80000m, 15000m), VoucherService.Calculate(c, Lines));
        c.MinOrderAmount = 100001;
        Assert.Throws<InvalidOperationException>(() => VoucherService.Calculate(c, Lines));
    }

    [Fact]
    public void MissingEligibleItemAndInvalidCartFail()
    {
        var c = new Coupon { MenuItemId = Guid.NewGuid(), DiscountValue = 20 };
        Assert.Throws<InvalidOperationException>(() => VoucherService.Calculate(c, Lines));
        Assert.Throws<InvalidOperationException>(() => VoucherService.Calculate(c, []));
        Assert.Throws<InvalidOperationException>(() => VoucherService.Calculate(c, [new(Food, 100, 0)]));
    }

    [Fact]
    public void CalculationDoesNotConsumeUsageAndRoundsMoney()
    {
        var c = new Coupon { DiscountValue = 33.33m, UsedCount = 3 };
        Assert.Equal((100m, 33.33m), VoucherService.Calculate(c, [new(Food, 100, 1)]));
        Assert.Equal(3, c.UsedCount);
        Assert.Equal("COM20", VoucherService.Normalize(" com20 "));
    }

    [Fact]
    public void StatusReflectsDatesUsageAndActivation()
    {
        var c = new Coupon();
        Assert.Equal("Active", VoucherService.Status(c));
        c.StartsAt = DateTime.UtcNow.AddDays(1);
        Assert.Equal("Scheduled", VoucherService.Status(c));
        c.UsageLimit = 1; c.UsedCount = 1;
        Assert.Equal("Exhausted", VoucherService.Status(c));
        c.EndsAt = DateTime.UtcNow.AddDays(-1);
        Assert.Equal("Expired", VoucherService.Status(c));
        c.IsActive = false;
        Assert.Equal("Inactive", VoucherService.Status(c));
    }
}
