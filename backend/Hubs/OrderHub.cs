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
            if (Guid.TryParse(driverId, out var id))
            {
                var existing = driverLocationService.GetDriver(id);
                if (existing is null)
                {
                    driverLocationService.UpdateLocation(id, 16.0442, 108.2213, "Tài xế SOOPI", "");
                }
                driverLocationService.SetAvailability(id, true);
            }
        }
    }

    public async Task LeaveDriverRoom(string driverId)
    {
        if (!string.IsNullOrWhiteSpace(driverId))
        {
            await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"driver_{driverId.Trim()}");
            if (Guid.TryParse(driverId, out var id))
            {
                driverLocationService.SetAvailability(id, false);
            }
        }
    }

    public Task DriverPingLocation(string driverId, double latitude, double longitude, string name = "", string phone = "")
    {
        if (Guid.TryParse(driverId, out var id))
        {
            driverLocationService.UpdateLocation(id, latitude, longitude, name, phone);
            driverLocationService.SetAvailability(id, true);
        }
        return Task.CompletedTask;
    }

    public async Task<bool> DriverAcceptOffer(string orderId, string driverId)
    {
        if (Guid.TryParse(orderId, out var oId) && Guid.TryParse(driverId, out var dId))
        {
            var acceptedViaQueue = driverOfferManager.TryAcceptOffer(oId, dId);
            if (acceptedViaQueue)
            {
                return true;
            }

            // Fallback: Nếu tài xế bấm nhận sau khi hết 15s hoặc nhận từ danh sách đơn đang chờ
            var assignedDirectly = await orderService.AssignShipperAsync(oId, dId, Context.ConnectionAborted);
            return assignedDirectly;
        }
        return false;
    }

    public Task<bool> DriverRejectOffer(string orderId, string driverId)
    {
        if (Guid.TryParse(orderId, out var oId) && Guid.TryParse(driverId, out var dId))
        {
            var rejected = driverOfferManager.TryRejectOffer(oId, dId);
            return Task.FromResult(rejected);
        }
        return Task.FromResult(false);
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
            return await orderService.DriverUpdateOrderStatusAsync(oId, dId, status, Context.ConnectionAborted);
        }
        return false;
    }
}
