using Microsoft.AspNetCore.Mvc;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.Services;

namespace SoopiFoodBE.Controllers;

[ApiController]
[Route("api/users/{userId:guid}")]
public sealed class OrdersController(
    IOrderService orders,
    IReviewService reviews) : ControllerBase
{
    [HttpGet("cart")]
    public async Task<IActionResult> Cart(Guid userId, CancellationToken ct) =>
        Ok(await orders.Cart(userId, ct));

    [HttpPut("cart/items")]
    public async Task<IActionResult> CartItem(
        Guid userId,
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
        Guid userId,
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

    [HttpPost("orders/direct")]
    public async Task<IActionResult> CreateDirect(
        Guid userId,
        [FromBody] DirectOrderRequest input,
        CancellationToken ct)
    {
        try
        {
            var order = await orders.CreateDirect(userId, input, ct);
            return Ok(order);
        }
        catch (KeyNotFoundException exception)
        {
            return NotFound(new { error = exception.Message });
        }
        catch (InvalidOperationException exception)
        {
            return BadRequest(new { error = exception.Message });
        }
        catch (ArgumentException exception)
        {
            return BadRequest(new { error = exception.Message });
        }
        catch (Exception exception)
        {
            return StatusCode(500, new { error = exception.Message });
        }
    }

    [HttpGet("orders")]
    public async Task<IActionResult> History(Guid userId, CancellationToken ct) =>
        Ok(await orders.History(userId, ct));

    [HttpGet("orders/{orderId:guid}")]
    public async Task<IActionResult> Track(
        Guid userId,
        Guid orderId,
        CancellationToken ct)
    {
        var order = await orders.Track(userId, orderId, ct);
        return order is null ? NotFound() : Ok(order);
    }

    [HttpPost("orders/{orderId:guid}/review")]
    public async Task<IActionResult> Review(
        Guid userId,
        Guid orderId,
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

    [HttpPut("orders/{orderId:guid}/delivery")]
    public async Task<IActionResult> Delivery(
        Guid userId,
        Guid orderId,
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

    [HttpPatch("/api/orders/{orderId:guid}/delivery")]
    [HttpPut("/api/orders/{orderId:guid}/delivery")]
    public async Task<IActionResult> DriverDeliveryUpdate(
        Guid orderId,
        [FromBody] DeliveryUpdate input,
        CancellationToken ct)
    {
        var driverIdHeader = Request.Headers["X-User-Id"].FirstOrDefault();
        Guid.TryParse(driverIdHeader, out var driverId);
        var ok = await orders.DriverUpdateOrderStatusAsync(orderId, driverId, input.Status, ct);
        return ok ? Ok(new { success = true, status = input.Status }) : NotFound();
    }
}
