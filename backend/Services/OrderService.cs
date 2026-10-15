using Microsoft.EntityFrameworkCore;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.DataAccess.Repositories;
using SoopiFoodBE.Models;

namespace SoopiFoodBE.Services;

public interface IOrderService
{
    Task<ShoppingCart> Cart(Guid userId, CancellationToken ct);
    Task<ShoppingCart> AddCartLine(Guid userId, CartLineRequest input, CancellationToken ct);
    Task<FoodOrder> Checkout(Guid userId, CheckoutRequest input, CancellationToken ct);
    Task<List<FoodOrder>> History(Guid userId, CancellationToken ct);
    Task<FoodOrder?> Track(Guid userId, Guid orderId, CancellationToken ct);
    Task<bool> UpdateDelivery(Guid actorId, Guid orderId, DeliveryUpdate input, CancellationToken ct);
}

public sealed class OrderService(SoopiDbContext db, IOrderRepository orders) : IOrderService
{
    public async Task<ShoppingCart> Cart(Guid userId, CancellationToken ct)
    {
        return await db.Carts
            .Include(cart => cart.Items)
            .ThenInclude(item => item.MenuItem)
            .FirstOrDefaultAsync(cart => cart.UserId == userId, ct)
            ?? new ShoppingCart { UserId = userId };
    }

    public async Task<ShoppingCart> AddCartLine(
        Guid userId,
        CartLineRequest input,
        CancellationToken ct)
    {
        if (input.Quantity < 0)
            throw new ArgumentException("Quantity cannot be negative");

        var menuItem = await db.MenuItems
            .Include(item => item.Category)
            .FirstOrDefaultAsync(
                item => item.Id == input.MenuItemId
                    && item.IsAvailable
                    && item.Category!.Restaurant!.IsAcceptingOrders,
                ct)
            ?? throw new KeyNotFoundException("Available menu item not found");

        var cart = await db.Carts
            .Include(item => item.Items)
            .FirstOrDefaultAsync(item => item.UserId == userId, ct);

        if (cart is null)
        {
            cart = new ShoppingCart
            {
                UserId = userId,
                RestaurantId = menuItem.Category!.RestaurantId
            };
            db.Carts.Add(cart);
        }

        if (cart.RestaurantId != menuItem.Category!.RestaurantId)
        {
            throw new InvalidOperationException(
                "A cart can contain items from one restaurant");
        }

        var cartLine = cart.Items.FirstOrDefault(
            item => item.MenuItemId == input.MenuItemId);

        if (input.Quantity == 0)
        {
            if (cartLine is not null)
                db.CartItems.Remove(cartLine);
        }
        else if (cartLine is null)
        {
            cart.Items.Add(new CartItem
            {
                MenuItemId = input.MenuItemId,
                Quantity = input.Quantity,
                Note = input.Note
            });
        }
        else
        {
            cartLine.Quantity = input.Quantity;
            cartLine.Note = input.Note;
        }

        cart.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        return await Cart(userId, ct);
    }

    public async Task<FoodOrder> Checkout(
        Guid userId,
        CheckoutRequest input,
        CancellationToken ct)
    {
        var cart = await db.Carts
            .Include(item => item.Items)
            .ThenInclude(item => item.MenuItem)
            .FirstOrDefaultAsync(item => item.UserId == userId, ct)
            ?? throw new InvalidOperationException("Cart is empty");

        if (cart.Items.Count == 0)
            throw new InvalidOperationException("Cart is empty");

        var address = await db.Addresses.FirstOrDefaultAsync(
            item => item.Id == input.AddressId && item.UserId == userId,
            ct)
            ?? throw new KeyNotFoundException("Address not found");

        var subtotal = cart.Items.Sum(item =>
            item.MenuItem!.Price * item.Quantity);
        var discount = 0m;
        Coupon? coupon = null;

        if (!string.IsNullOrWhiteSpace(input.CouponCode))
        {
            coupon = await db.Coupons.FirstOrDefaultAsync(
                item => item.Code == input.CouponCode
                    && item.IsActive
                    && (item.StartsAt == null || item.StartsAt <= DateTime.UtcNow)
                    && (item.EndsAt == null || item.EndsAt >= DateTime.UtcNow)
                    && (item.UsageLimit == null || item.UsedCount < item.UsageLimit),
                ct);

            if (coupon is null || subtotal < coupon.MinOrderAmount)
            {
                throw new InvalidOperationException(
                    "Coupon is invalid or order total is too low");
            }

            discount = coupon.DiscountType == "Percent"
                ? subtotal * coupon.DiscountValue / 100
                : coupon.DiscountValue;

            if (coupon.MaxDiscount.HasValue)
                discount = Math.Min(discount, coupon.MaxDiscount.Value);

            discount = Math.Min(discount, subtotal);
            coupon.UsedCount++;
        }

        var restaurant = await db.Restaurants.FindAsync([cart.RestaurantId], ct)
            ?? throw new KeyNotFoundException("Restaurant not found");

        var order = new FoodOrder
        {
            CustomerId = userId,
            RestaurantId = restaurant.Id,
            AddressId = address.Id,
            DeliveryAddress = address.FullAddress,
            Subtotal = subtotal,
            DiscountAmount = discount,
            DeliveryFee = 15000,
            TotalAmount = subtotal - discount + 15000,
            CouponCode = coupon?.Code,
            PaymentMethod = input.PaymentMethod,
            PaymentStatus = input.PaymentMethod == "Cash" ? "Unpaid" : "Pending",
            Note = input.Note,
            Items = cart.Items.Select(item => new OrderItem
            {
                MenuItemId = item.MenuItemId,
                ItemName = item.MenuItem!.Name,
                UnitPrice = item.MenuItem.Price,
                Quantity = item.Quantity,
                Note = item.Note
            }).ToList()
        };

        order.StatusHistory.Add(new OrderStatusHistory { Status = "Pending" });
        db.Orders.Add(order);
        db.Payments.Add(new Payment
        {
            Order = order,
            Method = input.PaymentMethod,
            Amount = order.TotalAmount,
            Status = order.PaymentStatus
        });

        db.CartItems.RemoveRange(cart.Items);
        cart.RestaurantId = null;
        await db.SaveChangesAsync(ct);
        return order;
    }

    public Task<List<FoodOrder>> History(Guid userId, CancellationToken ct) =>
        orders.HistoryAsync(userId, ct);

    public Task<FoodOrder?> Track(Guid userId, Guid orderId, CancellationToken ct) =>
        orders.GetForCustomerAsync(orderId, userId, ct);

    public async Task<bool> UpdateDelivery(
        Guid actorId,
        Guid orderId,
        DeliveryUpdate input,
        CancellationToken ct)
    {
        var order = await db.Orders
            .Include(item => item.Restaurant)
            .FirstOrDefaultAsync(item => item.Id == orderId, ct);

        if (order is null)
            return false;

        var isOwner = order.Restaurant!.OwnerId == actorId;
        var isShipper = order.ShipperId == actorId;

        if (!isOwner && !isShipper)
        {
            throw new UnauthorizedAccessException(
                "Only assigned shipper or restaurant owner can update this order");
        }

        var allowedStatuses = new[]
        {
            "Accepted", "Preparing", "ReadyForPickup", "PickedUp",
            "Delivering", "Delivered", "Cancelled"
        };

        if (!allowedStatuses.Contains(input.Status))
            throw new ArgumentException("Invalid order status");

        var shipperStatuses = new[] { "PickedUp", "Delivering", "Delivered" };
        if (isShipper && !shipperStatuses.Contains(input.Status))
            throw new UnauthorizedAccessException("Shipper cannot set this status");

        if (isOwner && shipperStatuses.Contains(input.Status))
        {
            throw new UnauthorizedAccessException(
                "Restaurant cannot set delivery status");
        }

        order.Status = input.Status;
        order.UpdatedAt = DateTime.UtcNow;
        order.StatusHistory.Add(new OrderStatusHistory
        {
            Status = input.Status,
            Note = input.Note
        });

        if (input.Latitude.HasValue && input.Longitude.HasValue)
        {
            if (!isShipper)
                throw new UnauthorizedAccessException("Only shipper can send location");

            db.DeliveryLocations.Add(new DeliveryLocation
            {
                OrderId = order.Id,
                ShipperId = actorId,
                Latitude = input.Latitude.Value,
                Longitude = input.Longitude.Value
            });
        }

        await db.SaveChangesAsync(ct);
        return true;
    }
}
