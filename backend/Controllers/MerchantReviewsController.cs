using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.DataAccess;
using SoopiFoodBE.Services;

namespace SoopiFoodBE.Controllers;

[ApiController, Authorize, Route("api/merchant/restaurants/{restaurantId:guid}/reviews")]
public sealed class MerchantReviewsController(SoopiDbContext db, CurrentAccount accounts) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(Guid restaurantId, int page = 1,
        int pageSize = 20, CancellationToken ct = default)
    {
        RestaurantManagement.Pagination(page, pageSize);
        var actor = await accounts.Owner(ct: ct);
        if (!await db.Restaurants.AnyAsync(r => r.Id == restaurantId && r.OwnerId == actor.Id, ct))
            return NotFound();

        var query = db.Reviews.AsNoTracking().Where(r => r.RestaurantId == restaurantId);
        var summary = await query.GroupBy(r => 1)
            .Select(g => new { Total = g.Count(), Average = g.Average(r => (double)r.RestaurantRating) })
            .SingleOrDefaultAsync(ct);
        var rows = await query.OrderByDescending(r => r.CreatedAt).ThenByDescending(r => r.Id)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(r => new MerchantReviewRow(r.Id, r.OrderId,
                r.Order != null ? r.Order.OrderCode : "",
                r.Customer != null ? r.Customer.FullName : "Khách hàng",
                r.RestaurantRating, r.Comment, r.CreatedAt)).ToListAsync(ct);
        return Ok(new MerchantReviewPage(rows, summary?.Total ?? 0, page, pageSize,
            summary is null ? 0 : Math.Round(summary.Average, 2)));
    }
}
