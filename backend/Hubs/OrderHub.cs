using Microsoft.AspNetCore.SignalR;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.Services;

namespace SoopiFoodBE.Hubs;

public sealed class OrderHub(
    IDriverLocationService driverLocationService,
    IDriverOfferManager driverOfferManager,
    IOrderService orderService) : Hub
{
    public async Task JoinRestaurantRoom(string restaurantId)
    {
        if (!string.IsNullOrWhiteSpace(restaurantId))
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, $"restaurant_{restaurantId.Trim()}");
        }
    }

    public async Task LeaveRestaurantRoom(string restaurantId)
    {
        if (!string.IsNullOrWhiteSpace(restaurantId))
        {
            await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"restaurant_{restaurantId.Trim()}");
        }
    }

    public async Task JoinOrderRoom(string orderId)
    {
        if (!string.IsNullOrWhiteSpace(orderId))
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, $"order_{orderId.Trim()}");
        }
    }

    public async Task LeaveOrderRoom(string orderId)
    {
        if (!string.IsNullOrWhiteSpace(orderId))
        {
            await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"order_{orderId.Trim()}");
        }
    }

    public async Task JoinUserRoom(string userId)
    {
        if (!string.IsNullOrWhiteSpace(userId))
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, $"user_{userId.Trim()}");
        }
    }

    public async Task LeaveUserRoom(string userId)
    {
        if (!string.IsNullOrWhiteSpace(userId))
        {
            await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"user_{userId.Trim()}");
        }
    }

    // ==========================================
    // TÀI XẾ (DRIVER / SHIPPER) REAL-TIME HUB
    // ==========================================

    public async Task JoinDriverRoom(string driverId)
    {
        if (!string.IsNullOrWhiteSpace(driverId))
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, $"driver_{driverId.Trim()}");
            var id = await orderService.ResolveDriverIdAsync(driverId, Context.ConnectionAborted);
            if (id != Guid.Empty)
            {
                var existing = driverLocationService.GetDriver(id);
                if (existing is null)
                {
                    driverLocationService.UpdateLocation(id, 16.0442, 108.2213, "Tài xế SOOPI", "");
                }
                var hasActive = await orderService.HasActiveOrderForDriverAsync(id, Context.ConnectionAborted);
                driverLocationService.SetAvailability(id, !hasActive);
            }
        }
    }

    public async Task LeaveDriverRoom(string driverId)
    {
        if (!string.IsNullOrWhiteSpace(driverId))
        {
            await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"driver_{driverId.Trim()}");
            var id = await orderService.ResolveDriverIdAsync(driverId, Context.ConnectionAborted);
            if (id != Guid.Empty)
            {
                driverLocationService.SetAvailability(id, false);
            }
        }
    }

    public async Task DriverPingLocation(string driverId, double latitude, double longitude, string name = "", string phone = "")
    {
        var id = await orderService.ResolveDriverIdAsync(driverId, Context.ConnectionAborted);
        if (id != Guid.Empty)
        {
            driverLocationService.UpdateLocation(id, latitude, longitude, name, phone);
            var hasActive = await orderService.HasActiveOrderForDriverAsync(id, Context.ConnectionAborted);
            driverLocationService.SetAvailability(id, !hasActive);
        }
    }

    public async Task<bool> DriverAcceptOffer(string orderId, string driverId)
    {
        if (!Guid.TryParse(orderId, out var oId))
        {
            return false;
        }

        var dId = await orderService.ResolveDriverIdAsync(driverId, Context.ConnectionAborted);
        if (dId == Guid.Empty)
        {
            return false;
        }

        var acceptedViaQueue = driverOfferManager.TryAcceptOffer(oId, dId);
        if (acceptedViaQueue)
        {
            driverLocationService.SetAvailability(dId, false);
            return true;
        }

        // Fallback: Nếu tài xế bấm nhận sau khi hết 15s hoặc nhận từ danh sách đơn đang chờ
        var assignedDirectly = await orderService.AssignShipperAsync(oId, dId, Context.ConnectionAborted);
        if (assignedDirectly)
        {
            driverLocationService.SetAvailability(dId, false);
        }
        return assignedDirectly;
    }

    public async Task<bool> DriverRejectOffer(string orderId, string driverId)
    {
        if (Guid.TryParse(orderId, out var oId))
        {
            var dId = await orderService.ResolveDriverIdAsync(driverId, Context.ConnectionAborted);
            if (dId != Guid.Empty)
            {
                var rejected = driverOfferManager.TryRejectOffer(oId, dId);
                return rejected;
            }
        }
        return false;
    }

    public async Task<List<DriverOfferPayload>> GetAvailableOrdersForDriver(double latitude, double longitude)
    {
        return await orderService.GetAvailableOrdersForShipperAsync(latitude, longitude, Context.ConnectionAborted);
    }

    public async Task<bool> DriverUpdateOrderStatus(string orderId, string driverId, string status)
    {
        if (Guid.TryParse(orderId, out var oId))
        {
            Guid.TryParse(driverId, out var dId);
            var ok = await orderService.DriverUpdateOrderStatusAsync(oId, dId, status, Context.ConnectionAborted);
            if (ok && status == "Delivered" && dId != Guid.Empty)
            {
                driverLocationService.SetAvailability(dId, true);
            }
            return ok;
        }
        return false;
    }
}
