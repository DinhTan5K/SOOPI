using Microsoft.AspNetCore.Mvc;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.Services;

namespace SoopiFoodBE.Controllers;

[ApiController]
[Route("api/users")]
public sealed class UsersController(IUserService service) : ControllerBase
{
    [HttpGet("{userId:int}")]
    public async Task<IActionResult> Profile(int userId, CancellationToken ct)
    {
        var user = await service.Profile(userId, ct);
        return user is null ? NotFound() : Ok(user);
    }

    [HttpPut("{userId:int}/profile")]
    public async Task<IActionResult> Update(
        int userId,
        ProfileUpdate input,
        CancellationToken ct)
    {
        return await service.Update(userId, input, ct)
            ? NoContent()
            : NotFound();
    }

    [HttpGet("{userId:int}/addresses")]
    public async Task<IActionResult> Addresses(int userId, CancellationToken ct) =>
        Ok(await service.Addresses(userId, ct));

    [HttpPost("{userId:int}/addresses")]
    public async Task<IActionResult> AddAddress(
        int userId,
        AddressRequest input,
        CancellationToken ct)
    {
        var address = await service.SaveAddress(userId, null, input, ct);
        return Created($"api/users/{userId}/addresses/{address.Id}", address);
    }

    [HttpPut("{userId:int}/addresses/{addressId:int}")]
    public async Task<IActionResult> UpdateAddress(
        int userId,
        int addressId,
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

    [HttpDelete("{userId:int}/addresses/{addressId:int}")]
    public async Task<IActionResult> DeleteAddress(
        int userId,
        int addressId,
        CancellationToken ct)
    {
        return await service.DeleteAddress(userId, addressId, ct)
            ? NoContent()
            : NotFound();
    }

    [HttpPut("{userId:int}/lock")]
    public async Task<IActionResult> Lock(
        int userId,
        [FromQuery] bool locked,
        CancellationToken ct)
    {
        return await service.SetLock(userId, locked, ct)
            ? NoContent()
            : NotFound();
    }
}
