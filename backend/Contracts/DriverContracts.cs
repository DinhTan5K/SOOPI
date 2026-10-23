namespace SoopiFoodBE.Contracts;

public sealed class DriverLocationInfo
{
    public Guid DriverId { get; set; }
    public string DriverName { get; set; } = string.Empty;
    public string DriverPhone { get; set; } = string.Empty;
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public bool IsAvailable { get; set; } = true;
    public DateTime LastPingUtc { get; set; } = DateTime.UtcNow;

    public bool IsActive(TimeSpan maxInactiveTime) =>
        IsAvailable && (DateTime.UtcNow - LastPingUtc) <= maxInactiveTime;
}

public sealed class OrderDispatchTask
{
    public Guid OrderId { get; set; }
    public string OrderCode { get; set; } = string.Empty;
    public Guid RestaurantId { get; set; }
    public string RestaurantName { get; set; } = string.Empty;
    public double RestaurantLatitude { get; set; }
    public double RestaurantLongitude { get; set; }
    public string DeliveryAddress { get; set; } = string.Empty;
    public decimal DeliveryFee { get; set; }
    public decimal TotalAmount { get; set; }
    public HashSet<Guid> ExcludedDriverIds { get; set; } = [];
    public int CurrentRadiusIndex { get; set; } = 0;
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}

public sealed record DriverLocationPingRequest(
    double Latitude,
    double Longitude);

public sealed record DriverOfferPayload(
    Guid OrderId,
    string OrderCode,
    string RestaurantName,
    string DeliveryAddress,
    decimal DeliveryFee,
    decimal TotalAmount,
    double DistanceToRestaurantKm,
    int TimeoutSeconds);
