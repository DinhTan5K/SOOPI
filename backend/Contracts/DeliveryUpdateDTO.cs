namespace SoopiFoodBE.Contracts;

public sealed record DeliveryUpdate(
    string Status,
    decimal? Latitude,
    decimal? Longitude,
    string? Note);
