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

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Get(Guid id, CancellationToken ct)
    {
        var restaurant = await service.Get(id, ct);
        return restaurant is null ? NotFound() : Ok(restaurant);
    }

    [HttpGet("{id:guid}/menu")]
    public async Task<IActionResult> Menu(Guid id, CancellationToken ct) =>
        Ok(await service.Menu(id, ct));

    [HttpPut("{id:guid}/owner/{ownerId:guid}")]
    public async Task<IActionResult> Update(
        Guid id,
        Guid ownerId,
        RestaurantUpdate input,
        CancellationToken ct)
    {
        return await service.Update(id, ownerId, input, ct)
            ? NoContent()
            : NotFound();
    }

    [HttpPut("{id:guid}/owner/{ownerId:guid}/hours/{day:int}")]
    public async Task<IActionResult> Hours(
        Guid id,
        Guid ownerId,
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

    [HttpPost("owner/{ownerId:guid}/menu")]
    public async Task<IActionResult> AddMenu(
        Guid ownerId,
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

    [HttpPut("owner/{ownerId:guid}/menu/{itemId:guid}")]
    public async Task<IActionResult> UpdateMenu(
        Guid ownerId,
        Guid itemId,
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

    [HttpDelete("owner/{ownerId:guid}/menu/{itemId:guid}")]
    public async Task<IActionResult> DeleteMenu(
        Guid ownerId,
        Guid itemId,
        CancellationToken ct)
    {
        return await service.DeleteMenu(ownerId, itemId, ct)
            ? NoContent()
            : NotFound();
    }

    [HttpGet("favorites/{userId:guid}")]
    public async Task<IActionResult> Favorites(Guid userId, CancellationToken ct) =>
        Ok(await reviews.Favorites(userId, ct));

    [HttpPut("favorites/{userId:guid}/{restaurantId:guid}")]
    public async Task<IActionResult> Favorite(
        Guid userId,
        Guid restaurantId,
        [FromQuery] bool saved,
        CancellationToken ct)
    {
        return await reviews.Favorite(userId, restaurantId, saved, ct)
            ? NoContent()
            : NotFound();
    }
}
