using Microsoft.EntityFrameworkCore;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.DataAccess.Repositories;
using SoopiFoodBE.Models;

namespace SoopiFoodBE.Services;

public interface IRestaurantService
{
    Task<List<Restaurant>> Search(
        string? query,
        string? category,
        decimal? rating,
        double? latitude,
        double? longitude,
        double? radiusKm,
        CancellationToken ct);

    Task<Restaurant?> Get(int id, CancellationToken ct);
    Task<List<MenuItem>> Menu(int id, CancellationToken ct);
    Task<bool> Update(int id, int ownerId, RestaurantUpdate input, CancellationToken ct);
    Task<bool> SaveHours(
        int restaurantId,
        int ownerId,
        byte day,
        OpeningHourRequest input,
        CancellationToken ct);

    Task<MenuItem> SaveMenu(
        int ownerId,
        int? id,
        MenuItemRequest input,
        CancellationToken ct);

    Task<bool> DeleteMenu(int ownerId, int id, CancellationToken ct);
}

public sealed class RestaurantService(
    SoopiDbContext db,
    IRestaurantRepository repository) : IRestaurantService
{
    public Task<List<Restaurant>> Search(
        string? query,
        string? category,
        decimal? rating,
        double? latitude,
        double? longitude,
        double? radiusKm,
        CancellationToken ct) => repository.SearchAsync(
            query,
            category,
            rating,
            latitude,
            longitude,
            radiusKm,
            ct);

    public Task<Restaurant?> Get(int id, CancellationToken ct) =>
        repository.GetAsync(id, ct);

    public Task<List<MenuItem>> Menu(int id, CancellationToken ct) =>
        repository.MenuAsync(id, ct);

    public async Task<bool> Update(
        int id,
        int ownerId,
        RestaurantUpdate input,
        CancellationToken ct)
    {
        var restaurant = await db.Restaurants.FirstOrDefaultAsync(
            item => item.Id == id && item.OwnerId == ownerId,
            ct);

        if (restaurant is null)
            return false;

        restaurant.Name = input.Name;
        restaurant.Description = input.Description;
        restaurant.Phone = input.Phone;
        restaurant.Address = input.Address;
        restaurant.City = input.City;
        restaurant.IsActive = input.IsActive;
        restaurant.IsAcceptingOrders = input.IsAcceptingOrders;

        await db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<bool> SaveHours(
        int restaurantId,
        int ownerId,
        byte day,
        OpeningHourRequest input,
        CancellationToken ct)
    {
        if (day > 6)
            throw new ArgumentException("DayOfWeek must be 0–6");

        var restaurantExists = await db.Restaurants.AnyAsync(
            item => item.Id == restaurantId && item.OwnerId == ownerId,
            ct);

        if (!restaurantExists)
            return false;

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

    public async Task<MenuItem> SaveMenu(
        int ownerId,
        int? id,
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
        return menuItem;
    }

    public async Task<bool> DeleteMenu(int ownerId, int id, CancellationToken ct)
    {
        var menuItem = await db.MenuItems.FirstOrDefaultAsync(
            item => item.Id == id && item.Category!.Restaurant!.OwnerId == ownerId,
            ct);

        if (menuItem is null)
            return false;

        db.MenuItems.Remove(menuItem);
        await db.SaveChangesAsync(ct);
        return true;
    }
}
