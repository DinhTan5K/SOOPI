namespace SoopiFoodBE.Services;

public static class ManagementImages
{
    public static async Task Validate(IFormFile file, CancellationToken ct)
    {
        if (file is null || file.Length is <= 0 or > 5 * 1024 * 1024)
            throw new ManagementException(400, "Image must be between 1 byte and 5 MB.");
        var header = new byte[12];
        await using var stream = file.OpenReadStream();
        var read = await stream.ReadAtLeastAsync(header, 12, throwOnEndOfStream: false, cancellationToken: ct);
        var jpeg = read >= 3 && header[0] == 0xff && header[1] == 0xd8 && header[2] == 0xff;
        var png = read >= 8 && header.AsSpan(0, 8).SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 });
        var webp = read == 12 && header.AsSpan(0, 4).SequenceEqual("RIFF"u8) && header.AsSpan(8, 4).SequenceEqual("WEBP"u8);
        if (!((jpeg && file.ContentType == "image/jpeg") || (png && file.ContentType == "image/png") || (webp && file.ContentType == "image/webp")))
            throw new ManagementException(400, "Only JPEG, PNG and WebP images with matching signatures are accepted.");
    }
}
