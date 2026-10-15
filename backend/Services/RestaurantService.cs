using Microsoft.EntityFrameworkCore;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.DataAccess.Repositories;
using SoopiFoodBE.Models;

namespace SoopiFoodBE.Services;

public interface IRestaurantService
{
    Task<List<RestaurantResponse>> Search(
        string? query,
        string? category,
        decimal? rating,
        double? latitude,
        double? longitude,
        double? radiusKm,
        CancellationToken ct);

    Task<RestaurantResponse?> Get(Guid id, CancellationToken ct);
    Task<List<MenuItemResponse>> Menu(Guid id, CancellationToken ct);
    Task<bool> Update(Guid id, Guid ownerId, RestaurantUpdate input, CancellationToken ct);
    Task<bool> SaveHours(
        Guid restaurantId,
        Guid ownerId,
        byte day,
        OpeningHourRequest input,
        CancellationToken ct);

    Task<MenuItemResponse> SaveMenu(
        Guid ownerId,
        Guid? id,
        MenuItemRequest input,
        CancellationToken ct);

    Task<bool> DeleteMenu(Guid ownerId, Guid id, CancellationToken ct);
}

public sealed class RestaurantService(
    SoopiDbContext db,
    IRestaurantRepository repository) : IRestaurantService
{
    public async Task<List<RestaurantResponse>> Search(
        string? query,
        string? category,
        decimal? rating,
        double? latitude,
        double? longitude,
        double? radiusKm,
        CancellationToken ct)
    {
        var list = await repository.SearchAsync(
            query,
            category,
            rating,
            latitude,
            longitude,
            radiusKm,
            ct);
        return list.Select(r => r.ToResponse()).ToList();
    }

    public async Task<RestaurantResponse?> Get(Guid id, CancellationToken ct)
    {
        var restaurant = await repository.GetAsync(id, ct);
        return restaurant?.ToResponse();
    }

    public async Task<List<MenuItemResponse>> Menu(Guid id, CancellationToken ct)
    {
        var items = await repository.MenuAsync(id, ct);
        return items.Select(i => i.ToResponse()).ToList();
    }

    public async Task<bool> Update(
        Guid id,
        Guid ownerId,
        RestaurantUpdate input,
        CancellationToken ct)
    {
        var restaurant = await db.Restaurants.FirstOrDefaultAsync(
            item => item.Id == id && item.OwnerId == ownerId,
            ct);

        if (restaurant is null)
            return false;

        await EnsureOwnerCanManage(restaurant, ct);
        if (input.IsAcceptingOrders && (restaurant.ApprovalStatus != "Approved" || !input.IsActive))
            throw new ManagementException(409, "Only approved, active restaurants can accept orders.");
        if (restaurant.ApprovalStatus == "Approved" && (restaurant.Name != input.Name || restaurant.Description != input.Description
            || restaurant.Phone != input.Phone || restaurant.Address != input.Address || restaurant.City != input.City))
        {
            restaurant.ApprovalStatus = "Pending";
            db.ManagementAudits.Add(new ManagementAudit { ActorId = ownerId, TargetId = id, Action = "Resubmitted" });
        }

        restaurant.Name = input.Name;
        restaurant.Description = input.Description;
        restaurant.Phone = input.Phone;
        restaurant.Address = input.Address;
        restaurant.City = input.City;
        restaurant.IsActive = input.IsActive;
        restaurant.IsAcceptingOrders = input.IsAcceptingOrders && restaurant.ApprovalStatus == "Approved";

        await db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<bool> SaveHours(
        Guid restaurantId,
        Guid ownerId,
        byte day,
        OpeningHourRequest input,
        CancellationToken ct)
    {
        if (day > 6)
            throw new ArgumentException("DayOfWeek must be 0–6");
        if (!input.IsClosed && input.OpensAt >= input.ClosesAt)
            throw new ArgumentException("Opening time must precede closing time.");

        var restaurantExists = await db.Restaurants.AnyAsync(
            item => item.Id == restaurantId && item.OwnerId == ownerId,
            ct);

        if (!restaurantExists)
            return false;
        await EnsureOwnerCanManage(await db.Restaurants.SingleAsync(r => r.Id == restaurantId, ct), ct);

        var openingHour = await db.OpeningHours.FirstOrDefaultAsync(
            item => item.RestaurantId == restaurantId && item.DayOfWeek == day,
            ct);

        if (openingHour is null)
        {
            openingHour = new OpeningHour
            {
                RestaurantId = restaurantId,
                DayOfWeek = day
            };
            db.OpeningHours.Add(openingHour);
        }

        openingHour.OpensAt = input.OpensAt;
        openingHour.ClosesAt = input.ClosesAt;
        openingHour.IsClosed = input.IsClosed;

        await db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<MenuItemResponse> SaveMenu(
        Guid ownerId,
        Guid? id,
        MenuItemRequest input,
        CancellationToken ct)
    {
        var category = await db.MenuCategories
            .Include(item => item.Restaurant)
            .FirstOrDefaultAsync(
                item => item.Id == input.CategoryId
                    && item.Restaurant!.OwnerId == ownerId,
                ct)
            ?? throw new KeyNotFoundException("Menu category not found");
        await EnsureOwnerCanManage(category.Restaurant!, ct);

        var menuItem = id.HasValue
            ? await db.MenuItems.FirstOrDefaultAsync(
                item => item.Id == id
                    && item.Category!.RestaurantId == category.RestaurantId,
                ct)
            : new MenuItem();

        if (menuItem is null)
            throw new KeyNotFoundException("Menu item not found");

        menuItem.CategoryId = input.CategoryId;
        menuItem.Name = input.Name;
        menuItem.Description = input.Description;
        menuItem.Price = input.Price;
        menuItem.ImageUrl = input.ImageUrl;
        menuItem.IsAvailable = input.IsAvailable;

        if (!id.HasValue)
            db.MenuItems.Add(menuItem);

        await db.SaveChangesAsync(ct);
        return menuItem.ToResponse();
    }

    public async Task<bool> DeleteMenu(Guid ownerId, Guid id, CancellationToken ct)
    {
        var menuItem = await db.MenuItems.Include(m => m.Category).FirstOrDefaultAsync(
            item => item.Id == id && item.Category!.Restaurant!.OwnerId == ownerId,
            ct);

        if (menuItem is null)
            return false;
        await EnsureOwnerCanManage(await db.Restaurants.SingleAsync(r => r.Id == menuItem.Category!.RestaurantId, ct), ct);
        menuItem.IsDeleted = true;
        menuItem.IsAvailable = false;
        await db.SaveChangesAsync(ct);
        return true;
    }

    private async Task EnsureOwnerCanManage(Restaurant restaurant, CancellationToken ct)
    {
        if (restaurant.IsLocked || !await db.Users.AnyAsync(u => u.Id == restaurant.OwnerId && !u.IsLocked, ct))
            throw new ManagementException(403, "Restaurant or owner is locked.");
    }
}
