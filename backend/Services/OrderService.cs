using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using SoopiFoodBE.Hubs;
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
    Task<FoodOrder> CreateDirect(Guid userId, DirectOrderRequest input, CancellationToken ct);
    Task<List<FoodOrder>> History(Guid userId, CancellationToken ct);
    Task<FoodOrder?> Track(Guid userId, Guid orderId, CancellationToken ct);
    Task<bool> UpdateDelivery(Guid actorId, Guid orderId, DeliveryUpdate input, CancellationToken ct);
    Task<bool> DriverUpdateOrderStatusAsync(Guid orderId, Guid driverId, string status, CancellationToken ct);
    Task<bool> AssignShipperAsync(Guid orderId, Guid shipperId, CancellationToken ct);
    Task TriggerOrderDispatchAsync(Guid orderId, CancellationToken ct);
    Task<List<DriverOfferPayload>> GetAvailableOrdersForShipperAsync(double driverLat, double driverLng, CancellationToken ct);
}

public sealed class OrderService(
    SoopiDbContext db,
    IOrderRepository orders,
    VoucherService vouchers,
    IHubContext<OrderHub> hubContext,
    IOrderDispatchQueue dispatchQueue,
    IDriverLocationService driverLocationService,
    VoucherService vouchers) : IOrderService
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
            var lines = cart.Items
                .Where(i => i.MenuItem != null)
                .Select(i => new VoucherLine(i.MenuItemId, i.MenuItem!.Price, i.Quantity))
                .ToList();
            var result = await vouchers.Evaluate(input.CouponCode, cart.RestaurantId!.Value, lines, ct);
            coupon = result.Coupon;
            discount = result.Discount;
            coupon.UsedCount++;
            db.Coupons.Update(coupon);
            db.Entry(coupon).Property(c => c.UsedCount).IsModified = true;
        }

        var restaurant = await db.Restaurants.FindAsync([cart.RestaurantId], ct)
            ?? throw new KeyNotFoundException("Restaurant not found");

        var paymentMethod = (input.PaymentMethod ?? "").ToLower() switch
        {
            var p when p.Contains("card") || p.Contains("thẻ") || p.Contains("bank") => "Card",
            var p when p.Contains("wallet") || p.Contains("ví") => "EWallet",
            _ => "Cash"
        };

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
            PaymentMethod = paymentMethod,
            PaymentStatus = paymentMethod == "Cash" ? "Unpaid" : "Paid",
            Note = input.Note,
            ShipperId = null,
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
            Method = paymentMethod,
            Amount = order.TotalAmount,
            Status = order.PaymentStatus
        });

        db.CartItems.RemoveRange(cart.Items);
        cart.RestaurantId = null;

        await db.SaveChangesAsync(ct);
        await BroadcastNewOrderAsync(order, restaurant, ct);
        return order;
    }

    public async Task<FoodOrder> CreateDirect(
        Guid userId,
        DirectOrderRequest input,
        CancellationToken ct)
    {
        var user = await db.Users.FindAsync([userId], ct);
        if (user is null)
        {
            user = new AppUser
            {
                Id = userId,
                FirebaseUid = $"guest_{userId:N}",
                Role = "Customer",
                FullName = "Khách hàng SOOPI",
                Email = $"{userId}@soopi.vn",
                CreatedAt = DateTimeOffset.UtcNow
            };
            db.Users.Add(user);
        }

        if (input.Items == null || input.Items.Count == 0)
            throw new ArgumentException("Items cannot be empty");

        Restaurant? restaurant = null;
        if (input.RestaurantId != Guid.Empty)
        {
            restaurant = await db.Restaurants.FindAsync([input.RestaurantId], ct);
        }
        if (restaurant is null)
        {
            throw new KeyNotFoundException("Restaurant not found");
        }

        var menuItemIds = input.Items.Select(i => i.MenuItemId).Distinct().ToList();
        var menuItems = await db.MenuItems
            .Where(m => menuItemIds.Contains(m.Id) && m.Category!.RestaurantId == restaurant.Id && m.IsAvailable)
            .ToDictionaryAsync(m => m.Id, ct);

        var orderItems = new List<OrderItem>();
        decimal subtotal = 0;

        foreach (var item in input.Items)
        {
            if (item.Quantity <= 0 || !menuItems.ContainsKey(item.MenuItemId))
                throw new ArgumentException("Món hoặc số lượng không hợp lệ cho quán đã chọn.");
            decimal unitPrice = 0;
            string itemName = "Món ăn";
            if (menuItems.TryGetValue(item.MenuItemId, out var mi))
            {
                unitPrice = mi.Price;
                itemName = mi.Name;
            }
            subtotal += unitPrice * item.Quantity;
            orderItems.Add(new OrderItem
            {
                Id = Guid.NewGuid(),
                MenuItemId = item.MenuItemId != Guid.Empty ? item.MenuItemId : null,
                ItemName = itemName,
                UnitPrice = unitPrice,
                Quantity = item.Quantity,
                Note = item.Note ?? ""
            });
        }

        if (orderItems.Count == 0)
            throw new ArgumentException("No valid items found for the order");

        // Address resolution
        UserAddress? address = null;
        if (input.AddressId.HasValue && input.AddressId.Value != Guid.Empty)
        {
            address = await db.Addresses.FirstOrDefaultAsync(
                a => a.Id == input.AddressId.Value && a.UserId == userId, ct);
        }

        if (address == null)
        {
            address = await db.Addresses.FirstOrDefaultAsync(
                a => a.UserId == userId && a.IsDefault, ct)
                ?? await db.Addresses.FirstOrDefaultAsync(
                    a => a.UserId == userId, ct);
        }

        var deliveryAddress = !string.IsNullOrWhiteSpace(input.DeliveryAddress)
            ? input.DeliveryAddress
            : (address?.FullAddress ?? "Địa chỉ nhận hàng mặc định");

        // Discount calculation
        var discount = 0m;
        Coupon? coupon = null;
        if (!string.IsNullOrWhiteSpace(input.CouponCode))
        {
            var lines = orderItems
                .Where(i => i.MenuItemId.HasValue && i.MenuItemId.Value != Guid.Empty)
                .Select(i => new VoucherLine(i.MenuItemId!.Value, i.UnitPrice, i.Quantity))
                .ToList();
            var result = await vouchers.Evaluate(input.CouponCode, restaurant.Id, lines, ct);
            coupon = result.Coupon;
            discount = result.Discount;
            coupon.UsedCount++;
            db.Coupons.Update(coupon);
            db.Entry(coupon).Property(c => c.UsedCount).IsModified = true;
        }

        var paymentMethod = (input.PaymentMethod ?? "").ToLower() switch
        {
            var p when p.Contains("card") || p.Contains("thẻ") || p.Contains("bank") => "Card",
            var p when p.Contains("wallet") || p.Contains("ví") => "EWallet",
            _ => "Cash"
        };

        const decimal deliveryFee = 16000m;
        var order = new FoodOrder
        {
            Id = Guid.NewGuid(),
            OrderCode = "SP-" + Random.Shared.Next(1000, 9999).ToString(),
            CustomerId = userId,
            RestaurantId = restaurant.Id,
            AddressId = address?.Id,
            DeliveryAddress = deliveryAddress,
            Subtotal = subtotal,
            DiscountAmount = discount,
            DeliveryFee = deliveryFee,
            TotalAmount = subtotal - discount + deliveryFee,
            CouponCode = coupon?.Code,
            PaymentMethod = paymentMethod,
            PaymentStatus = paymentMethod == "Cash" ? "Unpaid" : "Paid",
            Note = input.Note ?? "",
            Status = "Pending",
            ShipperId = null, // Không gán cứng shipper lúc tạo đơn để Dispatch Engine bắn popup!
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow,
            Items = orderItems
        };

        order.StatusHistory.Add(new OrderStatusHistory { Id = Guid.NewGuid(), Status = "Pending", Note = "Đã tiếp nhận đơn, chờ quán xác nhận" });

        db.Orders.Add(order);
        db.Payments.Add(new Payment
        {
            Id = Guid.NewGuid(),
            Order = order,
            Method = paymentMethod,
            Amount = order.TotalAmount,
            Status = order.PaymentStatus,
            CreatedAt = DateTime.UtcNow
        });

        await db.SaveChangesAsync(ct);
        await BroadcastNewOrderAsync(order, restaurant, ct);

        // Load navigations for caller
        await db.Entry(order).Reference(o => o.Restaurant).LoadAsync(ct);
        await db.Entry(order).Collection(o => o.Items).LoadAsync(ct);

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

        var statusPayload = new
        {
            orderId = order.Id,
            restaurantId = order.RestaurantId,
            newStatus = order.Status,
            status = order.Status,
            updatedAt = order.UpdatedAt,
            note = input.Note
        };

        try
        {
            await hubContext.Clients.Group($"order_{order.Id}")
                .SendAsync("OrderStatusUpdated", statusPayload, cancellationToken: ct);
            await hubContext.Clients.Group($"user_{order.CustomerId}")
                .SendAsync("OrderStatusUpdated", statusPayload, cancellationToken: ct);
            await hubContext.Clients.Group($"restaurant_{order.RestaurantId}")
                .SendAsync("OrderStatusUpdated", statusPayload, cancellationToken: ct);
        }
        catch { }

        if (input.Status == "ReadyForPickup")
        {
            await TriggerOrderDispatchAsync(order.Id, ct);
        }

        return true;
    }

    public async Task<bool> DriverUpdateOrderStatusAsync(
        Guid orderId,
        Guid driverId,
        string status,
        CancellationToken ct)
    {
        var order = await db.Orders
            .Include(o => o.Restaurant)
            .FirstOrDefaultAsync(o => o.Id == orderId, ct);

        if (order is null)
            return false;

        var oldStatus = order.Status;
        var newStatus = (status ?? "").Trim().ToLowerInvariant() switch
        {
            "pickedup" or "delivering" => "Delivering",
            "delivered" or "completed" => "Delivered",
            "readyforpickup" => "ReadyForPickup",
            _ => (status ?? "Delivering").Trim()
        };

        if (order.ShipperId == null && driverId != Guid.Empty)
        {
            order.ShipperId = driverId;
        }

        order.Status = newStatus;
        order.UpdatedAt = DateTime.UtcNow;

        if (newStatus == "Delivered")
        {
            order.PaymentStatus = "Paid";
            if (driverId != Guid.Empty)
            {
                driverLocationService.SetAvailability(driverId, true);
            }
            else if (order.ShipperId.HasValue)
            {
                driverLocationService.SetAvailability(order.ShipperId.Value, true);
            }
        }

        order.StatusHistory.Add(new OrderStatusHistory
        {
            Status = newStatus,
            Note = newStatus == "Delivering"
                ? "Tài xế đã lấy món và đang giao đến khách hàng"
                : newStatus == "Delivered"
                    ? "Tài xế đã giao hàng thành công"
                    : $"Tài xế cập nhật trạng thái: {newStatus}",
            ChangedAt = DateTime.UtcNow
        });

        await db.SaveChangesAsync(ct);

        var payload = new
        {
            orderId = order.Id,
            orderCode = order.OrderCode,
            restaurantId = order.RestaurantId,
            oldStatus,
            newStatus,
            status = newStatus,
            shipperId = order.ShipperId,
            updatedAt = order.UpdatedAt
        };

        try
        {
            await hubContext.Clients.Group($"order_{order.Id}")
                .SendAsync("OrderStatusUpdated", payload, cancellationToken: ct);
            await hubContext.Clients.Group($"user_{order.CustomerId}")
                .SendAsync("OrderStatusUpdated", payload, cancellationToken: ct);
            await hubContext.Clients.Group($"restaurant_{order.RestaurantId}")
                .SendAsync("OrderStatusUpdated", payload, cancellationToken: ct);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"SignalR broadcast error on DriverUpdateOrderStatus: {ex.Message}");
        }

        return true;
    }

    private async Task BroadcastNewOrderAsync(FoodOrder order, Restaurant restaurant, CancellationToken ct)
    {
        try
        {
            var payload = new
            {
                orderId = order.Id,
                orderCode = order.OrderCode,
                restaurantId = restaurant.Id,
                restaurantName = restaurant.Name,
                customerId = order.CustomerId,
                customerName = order.Address?.RecipientName ?? "Khách hàng",
                customerPhone = order.Address?.Phone ?? "",
                deliveryAddress = order.DeliveryAddress,
                subtotal = order.Subtotal,
                discountAmount = order.DiscountAmount,
                deliveryFee = order.DeliveryFee,
                totalAmount = order.TotalAmount,
                paymentMethod = order.PaymentMethod,
                paymentStatus = order.PaymentStatus,
                note = order.Note,
                status = order.Status,
                createdAt = order.CreatedAt,
                items = order.Items.Select(i => new
                {
                    itemName = i.ItemName,
                    quantity = i.Quantity,
                    unitPrice = i.UnitPrice,
                    note = i.Note
                }).ToList()
            };

            await hubContext.Clients.Group($"restaurant_{restaurant.Id}")
                .SendAsync("NewOrderReceived", payload, cancellationToken: ct);

            await hubContext.Clients.Group($"user_{order.CustomerId}")
                .SendAsync("OrderCreated", payload, cancellationToken: ct);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"SignalR broadcast error: {ex.Message}");
        }
    }

    public async Task TriggerOrderDispatchAsync(Guid orderId, CancellationToken ct)
    {
        var order = await db.Orders
            .Include(o => o.Restaurant)
            .FirstOrDefaultAsync(o => o.Id == orderId, ct);

        if (order is null || order.Restaurant is null)
            return;

        if (order.Status is not ("ReadyForPickup" or "Delivering"))
            return;

        // Nếu đơn trước đó bị gán ShipperId ảo hoặc chủ quán bấm phát lại đơn cho shipper
        if (order.ShipperId.HasValue)
        {
            order.ShipperId = null;
            await db.SaveChangesAsync(ct);
        }

        // Tọa độ quán (nếu chưa có thì dùng mặc định FPT Complex Đà Nẵng)
        var shopLat = (double)(order.Restaurant.Latitude ?? 16.0442m);
        var shopLng = (double)(order.Restaurant.Longitude ?? 108.2213m);

        var task = new OrderDispatchTask
        {
            OrderId = order.Id,
            OrderCode = order.OrderCode,
            RestaurantId = order.RestaurantId,
            RestaurantName = order.Restaurant.Name,
            RestaurantLatitude = shopLat,
            RestaurantLongitude = shopLng,
            DeliveryAddress = order.DeliveryAddress,
            DeliveryFee = order.DeliveryFee,
            TotalAmount = order.TotalAmount
        };

        await dispatchQueue.EnqueueAsync(task, ct);
    }

    public async Task<List<DriverOfferPayload>> GetAvailableOrdersForShipperAsync(
        double driverLat,
        double driverLng,
        CancellationToken ct)
    {
        var waitingOrders = await db.Orders
            .AsNoTracking()
            .Include(o => o.Restaurant)
            .Where(o => (o.Status == "ReadyForPickup" || o.Status == "Delivering") && o.ShipperId == null)
            .OrderByDescending(o => o.CreatedAt)
            .Take(20)
            .ToListAsync(ct);

        var result = new List<DriverOfferPayload>();
        foreach (var o in waitingOrders)
        {
            var shopLat = (double)(o.Restaurant?.Latitude ?? 16.0442m);
            var shopLng = (double)(o.Restaurant?.Longitude ?? 108.2213m);
            var dist = InMemoryDriverLocationService.CalculateDistanceKm(driverLat, driverLng, shopLat, shopLng);

            // Chỉ hiện các đơn loanh quanh tài xế (trong bán kính <= 5km), loại bỏ đơn cách xa 600km
            if (dist <= 5.0)
            {
                result.Add(new DriverOfferPayload(
                    o.Id,
                    o.OrderCode,
                    o.Restaurant?.Name ?? "Quán SOOPI",
                    o.DeliveryAddress,
                    o.DeliveryFee,
                    o.TotalAmount,
                    Math.Round(dist, 2),
                    15
                ));
            }
        }

        return result.OrderBy(r => r.DistanceToRestaurantKm).ToList();
    }

    public async Task<bool> AssignShipperAsync(Guid orderId, Guid shipperId, CancellationToken ct)
    {
        var order = await db.Orders
            .Include(o => o.Restaurant)
            .Include(o => o.Address)
            .FirstOrDefaultAsync(o => o.Id == orderId, ct);

        if (order is null || order.Status is "Cancelled" or "Delivered")
        {
            return false;
        }

        var shipper = await db.Users.FirstOrDefaultAsync(u => u.Id == shipperId, ct);
        shipper ??= new AppUser
        {
            Id = shipperId,
            FullName = "Tài xế SOOPI",
            Phone = "0901234567",
            Role = "Shipper"
        };
        if (!db.Users.Local.Contains(shipper) && await db.Users.FindAsync([shipperId], ct) == null)
        {
            db.Users.Add(shipper);
        }

        order.ShipperId = shipperId;
        order.UpdatedAt = DateTime.UtcNow;
        order.StatusHistory.Add(new OrderStatusHistory
        {
            Status = "ShipperAssigned",
            Note = $"Tài xế {shipper.FullName} ({shipper.Phone}) đã nhận đơn",
            ChangedAt = DateTime.UtcNow
        });

        await db.SaveChangesAsync(ct);

        var payload = new
        {
            orderId = order.Id,
            orderCode = order.OrderCode,
            restaurantId = order.RestaurantId,
            shipperId = shipper.Id,
            shipperName = shipper.FullName,
            shipperPhone = shipper.Phone,
            newStatus = order.Status,
            status = order.Status
        };

        try
        {
            await hubContext.Clients.Group($"restaurant_{order.RestaurantId}")
                .SendAsync("ShipperAssigned", payload, cancellationToken: ct);
            await hubContext.Clients.Group($"user_{order.CustomerId}")
                .SendAsync("ShipperAssigned", payload, cancellationToken: ct);
            await hubContext.Clients.Group($"order_{order.Id}")
                .SendAsync("ShipperAssigned", payload, cancellationToken: ct);

            await hubContext.Clients.Group($"restaurant_{order.RestaurantId}")
                .SendAsync("OrderStatusUpdated", payload, cancellationToken: ct);
            await hubContext.Clients.Group($"user_{order.CustomerId}")
                .SendAsync("OrderStatusUpdated", payload, cancellationToken: ct);
            await hubContext.Clients.Group($"order_{order.Id}")
                .SendAsync("OrderStatusUpdated", payload, cancellationToken: ct);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"SignalR broadcast error on AssignShipper: {ex.Message}");
        }

        return true;
    }
}
