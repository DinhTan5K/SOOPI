using Microsoft.AspNetCore.SignalR;

namespace SoopiFoodBE.Hubs;

public sealed class OrderHub : Hub
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
}
