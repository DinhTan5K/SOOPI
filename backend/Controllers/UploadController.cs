using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using SoopiFoodBE.Services;

namespace SoopiFoodBE.Controllers;

[ApiController]
[Route("api/upload")]
public sealed class UploadController(IImageUploadService uploadService) : ControllerBase
{
    [HttpPost("image")]
    [Authorize, ManagementAccess, Consumes("multipart/form-data"), RequestSizeLimit(6 * 1024 * 1024)]
    public async Task<IActionResult> UploadImage(IFormFile file, [FromQuery] string? folder, CancellationToken ct)
    {
        if (file is null || file.Length == 0)
            return BadRequest(new { message = "Vui lòng chọn file ảnh để tải lên." });

        await ManagementImages.Validate(file, ct);
        var folderName = "soopifood";
        var imageUrl = await uploadService.UploadImageAsync(file, folderName, ct);

        if (string.IsNullOrEmpty(imageUrl))
            return BadRequest(new { message = "Upload ảnh lên Cloudinary thất bại. Hãy kiểm tra lại cấu hình Cloudinary trong appsettings.json." });

        return Ok(new { imageUrl });
    }
}
