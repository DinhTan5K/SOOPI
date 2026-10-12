using Microsoft.AspNetCore.Mvc;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.Services;

namespace SoopiFoodBE.Controllers;

[ApiController]
[Route("api/users/{userId:int}")]
public sealed class OrdersController(
    IOrderService orders,
    IReviewService reviews) : ControllerBase
{
    [HttpGet("cart")]
    public async Task<IActionResult> Cart(int userId, CancellationToken ct) =>
        Ok(await orders.Cart(userId, ct));

    [HttpPut("cart/items")]
    public async Task<IActionResult> CartItem(
        int userId,
        CartLineRequest input,
        CancellationToken ct)
    {
        try
        {
            return Ok(await orders.AddCartLine(userId, input, ct));
        }
        catch (KeyNotFoundException)
        {
            return NotFound();
        }
        catch (InvalidOperationException exception)
        {
            return BadRequest(new { error = exception.Message });
        }
    }

    [HttpPost("orders")]
    public async Task<IActionResult> Checkout(
        int userId,
        CheckoutRequest input,
        CancellationToken ct)
    {
        try
        {
            return Ok(await orders.Checkout(userId, input, ct));
        }
        catch (KeyNotFoundException exception)
        {
            return NotFound(new { error = exception.Message });
        }
        catch (InvalidOperationException exception)
        {
            return BadRequest(new { error = exception.Message });
        }
    }

    [HttpGet("orders")]
    public async Task<IActionResult> History(int userId, CancellationToken ct) =>
        Ok(await orders.History(userId, ct));

    [HttpGet("orders/{orderId:int}")]
    public async Task<IActionResult> Track(
        int userId,
        int orderId,
        CancellationToken ct)
    {
        var order = await orders.Track(userId, orderId, ct);
        return order is null ? NotFound() : Ok(order);
    }

    [HttpPost("orders/{orderId:int}/review")]
    public async Task<IActionResult> Review(
        int userId,
        int orderId,
        ReviewRequest input,
        CancellationToken ct)
    {
        try
        {
            return Ok(await reviews.Create(userId, orderId, input, ct));
        }
        catch (KeyNotFoundException)
        {
            return NotFound();
        }
        catch (InvalidOperationException exception)
        {
            return BadRequest(new { error = exception.Message });
        }
        catch (ArgumentException exception)
        {
            return BadRequest(new { error = exception.Message });
        }
    }

    [HttpPut("orders/{orderId:int}/delivery")]
    public async Task<IActionResult> Delivery(
        int userId,
        int orderId,
        DeliveryUpdate input,
        CancellationToken ct)
    {
        try
        {
            return await orders.UpdateDelivery(userId, orderId, input, ct)
                ? NoContent()
                : NotFound();
        }
        catch (UnauthorizedAccessException exception)
        {
            return StatusCode(403, new { error = exception.Message });
        }
        catch (ArgumentException exception)
        {
            return BadRequest(new { error = exception.Message });
        }
    }
}
