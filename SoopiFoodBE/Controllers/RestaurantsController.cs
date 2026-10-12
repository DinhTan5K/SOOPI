using Microsoft.AspNetCore.Mvc;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.Services;

namespace SoopiFoodBE.Controllers;

[ApiController]
[Route("api/restaurants")]
public sealed class RestaurantsController(
    IRestaurantService service,
    IReviewService reviews) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Search(
        [FromQuery] string? q,
        [FromQuery] string? category,
        [FromQuery] decimal? minRating,
        [FromQuery] double? lat,
        [FromQuery] double? lng,
        [FromQuery] double? radiusKm,
        CancellationToken ct) =>
        Ok(await service.Search(q, category, minRating, lat, lng, radiusKm, ct));

    [HttpGet("{id:int}")]
    public async Task<IActionResult> Get(int id, CancellationToken ct)
    {
        var restaurant = await service.Get(id, ct);
        return restaurant is null ? NotFound() : Ok(restaurant);
    }

    [HttpGet("{id:int}/menu")]
    public async Task<IActionResult> Menu(int id, CancellationToken ct) =>
        Ok(await service.Menu(id, ct));

    [HttpPut("{id:int}/owner/{ownerId:int}")]
    public async Task<IActionResult> Update(
        int id,
        int ownerId,
        RestaurantUpdate input,
        CancellationToken ct)
    {
        return await service.Update(id, ownerId, input, ct)
            ? NoContent()
            : NotFound();
    }

    [HttpPut("{id:int}/owner/{ownerId:int}/hours/{day:int}")]
    public async Task<IActionResult> Hours(
        int id,
        int ownerId,
        byte day,
        OpeningHourRequest input,
        CancellationToken ct)
    {
        try
        {
            return await service.SaveHours(id, ownerId, day, input, ct)
                ? NoContent()
                : NotFound();
        }
        catch (ArgumentException exception)
        {
            return BadRequest(new { error = exception.Message });
        }
    }

    [HttpPost("owner/{ownerId:int}/menu")]
    public async Task<IActionResult> AddMenu(
        int ownerId,
        MenuItemRequest input,
        CancellationToken ct)
    {
        try
        {
            return Ok(await service.SaveMenu(ownerId, null, input, ct));
        }
        catch (KeyNotFoundException)
        {
            return NotFound();
        }
    }

    [HttpPut("owner/{ownerId:int}/menu/{itemId:int}")]
    public async Task<IActionResult> UpdateMenu(
        int ownerId,
        int itemId,
        MenuItemRequest input,
        CancellationToken ct)
    {
        try
        {
            return Ok(await service.SaveMenu(ownerId, itemId, input, ct));
        }
        catch (KeyNotFoundException)
        {
            return NotFound();
        }
    }

    [HttpDelete("owner/{ownerId:int}/menu/{itemId:int}")]
    public async Task<IActionResult> DeleteMenu(
        int ownerId,
        int itemId,
        CancellationToken ct)
    {
        return await service.DeleteMenu(ownerId, itemId, ct)
            ? NoContent()
            : NotFound();
    }

    [HttpGet("favorites/{userId:int}")]
    public async Task<IActionResult> Favorites(int userId, CancellationToken ct) =>
        Ok(await reviews.Favorites(userId, ct));

    [HttpPut("favorites/{userId:int}/{restaurantId:int}")]
    public async Task<IActionResult> Favorite(
        int userId,
        int restaurantId,
        [FromQuery] bool saved,
        CancellationToken ct)
    {
        return await reviews.Favorite(userId, restaurantId, saved, ct)
            ? NoContent()
            : NotFound();
    }
}
