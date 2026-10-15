using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.Services;

namespace SoopiFoodBE.Controllers;

[ApiController]
[Route("api/users")]
public sealed class UsersController(IUserService service) : ControllerBase
{
    [HttpGet("{userId:guid}")]
    public async Task<IActionResult> Profile(Guid userId, CancellationToken ct)
    {
        var user = await service.Profile(userId, ct);
        return user is null ? NotFound() : Ok(user);
    }

    [HttpPut("{userId:guid}/profile")]
    public async Task<IActionResult> Update(
        Guid userId,
        ProfileUpdate input,
        CancellationToken ct)
    {
        return await service.Update(userId, input, ct)
            ? NoContent()
            : NotFound();
    }

    [HttpGet("{userId:guid}/addresses")]
    public async Task<IActionResult> Addresses(Guid userId, CancellationToken ct) =>
        Ok(await service.Addresses(userId, ct));

    [HttpPost("{userId:guid}/addresses")]
    public async Task<IActionResult> AddAddress(
        Guid userId,
        AddressRequest input,
        CancellationToken ct)
    {
        var address = await service.SaveAddress(userId, null, input, ct);
        return Created($"api/users/{userId}/addresses/{address.Id}", address);
    }

    [HttpPut("{userId:guid}/addresses/{addressId:guid}")]
    public async Task<IActionResult> UpdateAddress(
        Guid userId,
        Guid addressId,
        AddressRequest input,
        CancellationToken ct)
    {
        try
        {
            return Ok(await service.SaveAddress(userId, addressId, input, ct));
        }
        catch (KeyNotFoundException)
        {
            return NotFound();
        }
    }

    [HttpDelete("{userId:guid}/addresses/{addressId:guid}")]
    public async Task<IActionResult> DeleteAddress(
        Guid userId,
        Guid addressId,
        CancellationToken ct)
    {
        return await service.DeleteAddress(userId, addressId, ct)
            ? NoContent()
            : NotFound();
    }

    [HttpPut("{userId:guid}/lock")]
    [Authorize, ManagementAccess(admin: true)]
    public async Task<IActionResult> Lock(
        Guid userId,
        [FromQuery] bool locked,
        CancellationToken ct)
    {
        return await service.SetLock(userId, locked, ct)
            ? NoContent()
            : NotFound();
    }
}
