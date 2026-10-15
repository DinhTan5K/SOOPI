using Microsoft.EntityFrameworkCore;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.Models;

namespace SoopiFoodBE.Services;

public sealed class RestaurantManagement(SoopiDbContext db, CurrentAccount accounts)
{
    public async Task<Restaurant> Owned(Guid id, CancellationToken ct)
    {
        var actor = await accounts.Get(ct: ct);
        var restaurant = await db.Restaurants.Include(r => r.Categories).ThenInclude(c => c.Items)
            .Include(r => r.OpeningHours).SingleOrDefaultAsync(r => r.Id == id && r.OwnerId == actor.Id, ct)
            ?? throw new ManagementException(404, "Restaurant not found.");
        if (restaurant.IsLocked) throw new ManagementException(403, "Restaurant is locked by an administrator.");
        return restaurant;
    }

    public static object View(Restaurant r) => new {
        r.Id, r.OwnerId, r.Name, r.Description, r.Phone, r.Address, r.City, r.ImageUrl,
        r.Latitude, r.Longitude, r.ApprovalStatus, r.ReviewReason, r.ReviewedBy, r.ReviewedAt,
        r.IsLocked, r.IsActive, r.IsAcceptingOrders,
        Categories = r.Categories.OrderBy(c => c.SortOrder).Select(CategoryView),
        OpeningHours = r.OpeningHours.OrderBy(h => h.DayOfWeek).Select(h => new { h.DayOfWeek, h.OpensAt, h.ClosesAt, h.IsClosed })
    };
    public static object CategoryView(MenuCategory c) => new { c.Id, c.RestaurantId, c.Name, c.SortOrder,
        Items = c.Items.Where(m => !m.IsDeleted).Select(m => m.ToResponse()) };

    public static void Apply(Restaurant r, RestaurantInput input)
    {
        if (input.Latitude.HasValue != input.Longitude.HasValue)
            throw new ManagementException(400, "Latitude and longitude must be supplied together.");
        r.Name = input.Name.Trim(); r.Description = input.Description; r.Phone = input.Phone.Trim();
        r.Address = input.Address.Trim(); r.City = input.City.Trim(); r.ImageUrl = input.ImageUrl;
        r.Latitude = input.Latitude; r.Longitude = input.Longitude;
    }

    public static bool Changed(Restaurant r, RestaurantInput i) =>
        r.Name != i.Name.Trim() || r.Description != i.Description || r.Phone != i.Phone.Trim()
        || r.Address != i.Address.Trim() || r.City != i.City.Trim() || r.ImageUrl != i.ImageUrl
        || r.Latitude != i.Latitude || r.Longitude != i.Longitude;

    public void Audit(Guid actor, Guid target, string action, string? reason = null, string type = "Restaurant") =>
        db.ManagementAudits.Add(new ManagementAudit { ActorId = actor, TargetId = target,
            Action = action, Reason = reason, TargetType = type });

    public static void Pagination(int page, int pageSize)
    {
        if (page < 1 || page > 1000000 || pageSize < 1 || pageSize > 100)
            throw new ManagementException(400, "Page must be 1–1000000 and pageSize 1–100.");
    }

    public static void Status(string? status)
    {
        if (status is not null && status is not ("Pending" or "Approved" or "Rejected"))
            throw new ManagementException(400, "Invalid approval status.");
    }

    public async Task<object> Create(RestaurantInput input, CancellationToken ct)
    {
        var user = await accounts.Get(create: true, ct: ct);
        var restaurant = new Restaurant { Id = Guid.NewGuid(), OwnerId = user.Id, IsAcceptingOrders = false };
        Apply(restaurant, input);
        restaurant.Categories = new[] { "Món chính", "Ăn nhẹ", "Đồ uống" }.Select((name, index) =>
            new MenuCategory { Id = Guid.NewGuid(), RestaurantId = restaurant.Id, Name = name, SortOrder = index }).ToList();
        db.Restaurants.Add(restaurant);
        Audit(user.Id, restaurant.Id, "Created");
        await db.SaveChangesAsync(ct);
        return View(restaurant);
    }
}
