using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.Models;
using SoopiFoodBE.Services;
using Microsoft.AspNetCore.SignalR;
using SoopiFoodBE.Hubs;

namespace SoopiFoodBE.Controllers;

[ApiController, Authorize, Route("api/merchant")]
public sealed class MerchantRestaurantsController(
    SoopiDbContext db, CurrentAccount accounts, RestaurantManagement management,
    IRestaurantService restaurants, IImageUploadService images) : ControllerBase
{
    [HttpPost("register")]
    public async Task<IActionResult> Register(CancellationToken ct)
    {
        var user = await accounts.Get(create: true, ct: ct);
        if (user.Role == "Customer")
        {
            user.Role = "Owner";
            user.UpdatedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync(ct);
        }
        return Ok(new { success = true, role = user.Role });
    }

    [HttpGet("me")]
    public async Task<IActionResult> Me(CancellationToken ct)
    {
        var user = await accounts.Owner(ct: ct);
        return Ok(new { user.Id, user.Email, user.FullName, user.Phone, user.AvatarUrl, user.Role,
            HasRestaurants = await db.Restaurants.AnyAsync(r => r.OwnerId == user.Id, ct) });
    }

    [HttpGet("restaurants")]
    public async Task<IActionResult> List(string? status, int page = 1, int pageSize = 20, CancellationToken ct = default)
    {
        RestaurantManagement.Pagination(page, pageSize); RestaurantManagement.Status(status);
        var user = await accounts.Owner(ct: ct);
        var query = db.Restaurants.AsNoTracking().Where(r => r.OwnerId == user.Id);
        if (status is not null) query = query.Where(r => r.ApprovalStatus == status);
        var total = await query.CountAsync(ct);
        var rows = await query.OrderBy(r => r.Name).ThenBy(r => r.Id).Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        return Ok(new PageResult<object>(rows.Select(RestaurantManagement.View).ToList(), total, page, pageSize));
    }

    [HttpPost("restaurants")]
    public async Task<IActionResult> Create(RestaurantInput input, CancellationToken ct) =>
        StatusCode(201, await management.Create(input, ct));

    [HttpGet("restaurants/{id:guid}")]
    public async Task<IActionResult> Detail(Guid id, CancellationToken ct)
    {
        var user = await accounts.Owner(ct: ct);
        var r = await db.Restaurants.AsNoTracking().Include(r => r.Categories).ThenInclude(c => c.Items)
            .Include(r => r.OpeningHours).SingleOrDefaultAsync(r => r.Id == id && r.OwnerId == user.Id, ct);
        return r is null ? NotFound() : Ok(RestaurantManagement.View(r));
    }

    [HttpPut("restaurants/{id:guid}")]
    public async Task<IActionResult> Update(Guid id, RestaurantInput input, CancellationToken ct)
    {
        var r = await management.Owned(id, ct);
        if (r.ApprovalStatus == "Approved" && RestaurantManagement.Changed(r, input))
        {
            r.ApprovalStatus = "Pending"; r.IsAcceptingOrders = false;
            management.Audit(r.OwnerId!.Value, id, "Resubmitted", "Approved restaurant information changed.");
        }
        RestaurantManagement.Apply(r, input);
        await db.SaveChangesAsync(ct);
        return Ok(RestaurantManagement.View(r));
    }

    [HttpPost("restaurants/{id:guid}/resubmit")]
    public async Task<IActionResult> Resubmit(Guid id, CancellationToken ct)
    {
        var r = await management.Owned(id, ct);
        if (r.ApprovalStatus != "Rejected") throw new ManagementException(409, "Only rejected restaurants can be resubmitted.");
        r.ApprovalStatus = "Pending"; r.IsAcceptingOrders = false;
        management.Audit(r.OwnerId!.Value, id, "Resubmitted");
        await db.SaveChangesAsync(ct);
        return Ok(RestaurantManagement.View(r));
    }

    [HttpPatch("restaurants/{id:guid}/operation")]
    public async Task<IActionResult> Operation(Guid id, OperationInput input, CancellationToken ct)
    {
        var r = await management.Owned(id, ct);
        if (input.IsAcceptingOrders && (r.ApprovalStatus != "Approved" || !input.IsActive))
            throw new ManagementException(409, "Only approved, active restaurants can accept orders.");
        r.IsActive = input.IsActive; r.IsAcceptingOrders = input.IsAcceptingOrders;
        await db.SaveChangesAsync(ct); return NoContent();
    }

    [HttpPut("restaurants/{id:guid}/hours/{day:int}")]
    public async Task<IActionResult> Hours(Guid id, int day, OpeningHourRequest input, CancellationToken ct)
    {
        var r = await management.Owned(id, ct);
        if (day is < 0 or > 6) throw new ManagementException(400, "Day must be 0–6 (Sunday = 0).");
        await restaurants.SaveHours(id, r.OwnerId!.Value, (byte)day, input, ct);
        return NoContent();
    }

    [HttpGet("restaurants/{id:guid}/categories")]
    public async Task<IActionResult> Categories(Guid id, CancellationToken ct) =>
        Ok((await management.Owned(id, ct)).Categories.OrderBy(c => c.SortOrder).Select(RestaurantManagement.CategoryView));

    [HttpPost("restaurants/{id:guid}/categories")]
    public async Task<IActionResult> CreateCategory(Guid id, CategoryInput input, CancellationToken ct)
    {
        await management.Owned(id, ct);
        var category = new MenuCategory { Id = Guid.NewGuid(), RestaurantId = id, Name = input.Name.Trim(), SortOrder = input.SortOrder };
        db.MenuCategories.Add(category); await db.SaveChangesAsync(ct);
        return StatusCode(201, RestaurantManagement.CategoryView(category));
    }

    [HttpPut("restaurants/{id:guid}/categories/{categoryId:guid}")]
    public async Task<IActionResult> UpdateCategory(Guid id, Guid categoryId, CategoryInput input, CancellationToken ct)
    {
        var r = await management.Owned(id, ct);
        var c = r.Categories.SingleOrDefault(c => c.Id == categoryId) ?? throw new ManagementException(404, "Category not found.");
        c.Name = input.Name.Trim(); c.SortOrder = input.SortOrder;
        await db.SaveChangesAsync(ct); return Ok(RestaurantManagement.CategoryView(c));
    }

    [HttpDelete("restaurants/{id:guid}/categories/{categoryId:guid}")]
    public async Task<IActionResult> DeleteCategory(Guid id, Guid categoryId, CancellationToken ct)
    {
        var r = await management.Owned(id, ct);
        var c = r.Categories.SingleOrDefault(c => c.Id == categoryId) ?? throw new ManagementException(404, "Category not found.");
        if (await db.MenuItems.IgnoreQueryFilters().AnyAsync(m => m.CategoryId == categoryId, ct))
            throw new ManagementException(409, "Category contains menu items, including archived items.");
        db.MenuCategories.Remove(c); await db.SaveChangesAsync(ct); return NoContent();
    }

    [HttpGet("restaurants/{id:guid}/menu")]
    public async Task<IActionResult> Menu(Guid id, CancellationToken ct) =>
        Ok((await management.Owned(id, ct)).Categories.SelectMany(c => c.Items).Select(m => m.ToResponse()));

    [HttpGet("restaurants/{id:guid}/menu/{itemId:guid}")]
    public async Task<IActionResult> Item(Guid id, Guid itemId, CancellationToken ct) =>
        Ok((await FindItem(id, itemId, ct)).ToResponse());

    [HttpPost("restaurants/{id:guid}/menu")]
    public async Task<IActionResult> CreateItem(Guid id, MenuItemRequest input, CancellationToken ct)
    {
        var r = await management.Owned(id, ct);
        RequireCategory(r, input.CategoryId);
        return StatusCode(201, await restaurants.SaveMenu(r.OwnerId!.Value, null, input, ct));
    }

    [HttpPut("restaurants/{id:guid}/menu/{itemId:guid}")]
    public async Task<IActionResult> UpdateItem(Guid id, Guid itemId, MenuItemRequest input, CancellationToken ct)
    {
        var r = await management.Owned(id, ct); RequireCategory(r, input.CategoryId);
        if (!r.Categories.SelectMany(c => c.Items).Any(m => m.Id == itemId)) throw new ManagementException(404, "Menu item not found.");
        return Ok(await restaurants.SaveMenu(r.OwnerId!.Value, itemId, input, ct));
    }

    [HttpDelete("restaurants/{id:guid}/menu/{itemId:guid}")]
    public async Task<IActionResult> DeleteItem(Guid id, Guid itemId, CancellationToken ct)
    {
        var item = await FindItem(id, itemId, ct);
        item.IsDeleted = true; item.IsAvailable = false;
        await db.SaveChangesAsync(ct); return NoContent();
    }

    [HttpPatch("restaurants/{id:guid}/menu/{itemId:guid}/availability")]
    public async Task<IActionResult> Availability(Guid id, Guid itemId, AvailabilityInput input, CancellationToken ct)
    {
        var item = await FindItem(id, itemId, ct); item.IsAvailable = input.IsAvailable;
        await db.SaveChangesAsync(ct); return NoContent();
    }

    [HttpPost("restaurants/{id:guid}/images"), Consumes("multipart/form-data"), RequestSizeLimit(6 * 1024 * 1024)]
    public async Task<IActionResult> Image(Guid id, IFormFile file, CancellationToken ct)
    {
        await management.Owned(id, ct);
        await ManagementImages.Validate(file, ct);
        var url = await images.UploadImageAsync(file, $"soopifood/restaurants/{id}", ct);
        if (url is null) throw new ManagementException(503, "Image upload is unavailable.");
        return Ok(new { imageUrl = url });
    }

    private async Task<MenuItem> FindItem(Guid id, Guid itemId, CancellationToken ct) =>
        (await management.Owned(id, ct)).Categories.SelectMany(c => c.Items).SingleOrDefault(m => m.Id == itemId)
        ?? throw new ManagementException(404, "Menu item not found.");
    private static void RequireCategory(Restaurant r, Guid categoryId)
    {
        if (!r.Categories.Any(c => c.Id == categoryId)) throw new ManagementException(404, "Category not found in this restaurant.");
    }

    [HttpGet("restaurants/{id:guid}/orders")]
    public async Task<IActionResult> Orders(
        Guid id,
        [FromQuery] string? status,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        CancellationToken ct = default)
    {
        await management.Owned(id, ct);
        var query = db.Orders
            .AsNoTracking()
            .Include(o => o.Items)
            .Include(o => o.Customer)
            .Include(o => o.Shipper)
            .Where(o => o.RestaurantId == id);

        if (!string.IsNullOrWhiteSpace(status) && !string.Equals(status, "all", StringComparison.OrdinalIgnoreCase))
        {
            query = query.Where(o => o.Status.ToLower() == status.ToLower());
        }

        var total = await query.CountAsync(ct);
        var list = await query
            .OrderByDescending(o => o.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(o => new
            {
                o.Id,
                o.OrderCode,
                o.CustomerId,
                CustomerName = o.Customer != null ? (o.Customer.FullName ?? o.Customer.Email) : "Khách hàng",
                CustomerPhone = o.Customer != null ? (o.Customer.Phone ?? "") : "",
                o.ShipperId,
                ShipperName = o.Shipper != null ? (o.Shipper.FullName ?? o.Shipper.Email) : null,
                ShipperPhone = o.Shipper != null ? (o.Shipper.Phone ?? "") : null,
                o.DeliveryAddress,
                o.Subtotal,
                o.DiscountAmount,
                o.DeliveryFee,
                o.TotalAmount,
                o.Status,
                o.PaymentMethod,
                o.PaymentStatus,
                o.Note,
                o.CreatedAt,
                Items = o.Items.Select(i => new
                {
                    i.Id,
                    i.MenuItemId,
                    i.ItemName,
                    i.UnitPrice,
                    i.Quantity,
                    i.Note
                }).ToList()
            })
            .ToListAsync(ct);

        return Ok(new { items = list, total, page, pageSize });
    }

    [HttpPatch("restaurants/{id:guid}/orders/{orderId:guid}/status")]
    public async Task<IActionResult> UpdateOrderStatus(
        Guid id,
        Guid orderId,
        [FromBody] UpdateOrderStatusInput input,
        [FromServices] IHubContext<OrderHub> hubContext,
        [FromServices] IOrderService orderService,
        CancellationToken ct = default)
    {
        await management.Owned(id, ct);
        var order = await db.Orders
            .Include(o => o.Items)
            .Include(o => o.Customer)
            .FirstOrDefaultAsync(o => o.Id == orderId && o.RestaurantId == id, ct)
            ?? throw new ManagementException(404, "Order not found");

        var oldStatus = order.Status;
        var rawStatus = input.Status.Trim();
        var newStatus = rawStatus.ToLowerInvariant() switch
        {
            "pending" => "Pending",
            "accepted" => "Accepted",
            "preparing" => "Preparing",
            "readyforpickup" => "ReadyForPickup",
            "pickedup" => "PickedUp",
            "delivering" => "Delivering",
            "delivered" => "Delivered",
            "cancelled" or "canceled" => "Cancelled",
            _ => rawStatus
        };

        order.Status = newStatus;
        order.UpdatedAt = DateTime.UtcNow;
        order.StatusHistory.Add(new OrderStatusHistory
        {
            Status = newStatus,
            Note = input.Note ?? $"Chủ quán cập nhật trạng thái sang {newStatus}"
        });

        await db.SaveChangesAsync(ct);

        if (newStatus is "ReadyForPickup" or "Delivering")
        {
            await orderService.TriggerOrderDispatchAsync(order.Id, ct);
        }

        var payload = new
        {
            orderId = order.Id,
            restaurantId = id,
            oldStatus,
            newStatus,
            updatedAt = order.UpdatedAt,
            note = input.Note
        };

        // Bắn sự kiện thời gian thực qua SignalR
        await hubContext.Clients.Group($"order_{order.Id}").SendAsync("OrderStatusUpdated", payload, cancellationToken: ct);
        await hubContext.Clients.Group($"user_{order.CustomerId}").SendAsync("OrderStatusUpdated", payload, cancellationToken: ct);
        await hubContext.Clients.Group($"restaurant_{id}").SendAsync("OrderStatusUpdated", payload, cancellationToken: ct);

        return Ok(new { success = true, status = order.Status });
    }
}