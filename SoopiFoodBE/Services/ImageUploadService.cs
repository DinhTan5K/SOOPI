using CloudinaryDotNet;
using CloudinaryDotNet.Actions;

namespace SoopiFoodBE.Services;

public interface IImageUploadService
{
    Task<string?> UploadImageAsync(IFormFile file, string folder = "soopifood", CancellationToken ct = default);
}

public sealed class ImageUploadService : IImageUploadService
{
    private readonly Cloudinary? _cloudinary;
    private readonly ILogger<ImageUploadService> _logger;

    public ImageUploadService(IConfiguration config, ILogger<ImageUploadService> logger)
    {
        _logger = logger;
        var cloudName = config["Cloudinary:CloudName"];
        var apiKey = config["Cloudinary:ApiKey"];
        var apiSecret = config["Cloudinary:ApiSecret"];

        if (!string.IsNullOrWhiteSpace(cloudName) &&
            !string.IsNullOrWhiteSpace(apiKey) &&
            !string.IsNullOrWhiteSpace(apiSecret) &&
            cloudName != "YOUR_CLOUD_NAME")
        {
            var acc = new Account(cloudName, apiKey, apiSecret);
            _cloudinary = new Cloudinary(acc);
        }
    }

    public async Task<string?> UploadImageAsync(IFormFile file, string folder = "soopifood", CancellationToken ct = default)
    {
        if (file == null || file.Length == 0) return null;

        if (_cloudinary is null)
        {
            _logger.LogWarning("Cloudinary is not configured in appsettings.json.");
            return null;
        }

        try
        {
            await using var stream = file.OpenReadStream();
            var uploadParams = new ImageUploadParams
            {
                File = new FileDescription(file.FileName, stream),
                Folder = folder,
                Transformation = new Transformation().Quality("auto").FetchFormat("auto")
            };

            var result = await _cloudinary.UploadAsync(uploadParams, ct);
            return result.SecureUrl?.ToString();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error uploading image to Cloudinary");
            return null;
        }
    }
}
