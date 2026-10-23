using System.Collections.Concurrent;
using SoopiFoodBE.Contracts;

namespace SoopiFoodBE.Services;

public interface IDriverLocationService
{
    void UpdateLocation(Guid driverId, double latitude, double longitude, string name = "", string phone = "");
    void SetAvailability(Guid driverId, bool isAvailable);
    void RemoveDriver(Guid driverId);
    DriverLocationInfo? GetDriver(Guid driverId);
    List<(DriverLocationInfo Driver, double DistanceKm)> GetNearbyAvailableDrivers(
        double shopLat,
        double shopLng,
        double radiusKm,
        IEnumerable<Guid>? excludedDriverIds = null);
    List<(DriverLocationInfo Driver, double DistanceKm)> GetAllActiveDrivers(
        double shopLat,
        double shopLng,
        IEnumerable<Guid>? excludedDriverIds = null);
}

public sealed class InMemoryDriverLocationService : IDriverLocationService
{
    // Lưu trữ vị trí các tài xế trong RAM an toàn đa luồng
    private readonly ConcurrentDictionary<Guid, DriverLocationInfo> _drivers = new();
    
    // Giữ trạng thái trực tuyến 30 phút để chống trình duyệt ẩn tab ngắt timer khi test đa cửa sổ
    private static readonly TimeSpan MaxInactivePing = TimeSpan.FromMinutes(30);

    public void UpdateLocation(Guid driverId, double latitude, double longitude, string name = "", string phone = "")
    {
        _drivers.AddOrUpdate(
            driverId,
            id => new DriverLocationInfo
            {
                DriverId = id,
                DriverName = name,
                DriverPhone = phone,
                Latitude = latitude,
                Longitude = longitude,
                IsAvailable = true,
                LastPingUtc = DateTime.UtcNow
            },
            (id, existing) =>
            {
                existing.Latitude = latitude;
                existing.Longitude = longitude;
                existing.LastPingUtc = DateTime.UtcNow;
                if (!string.IsNullOrWhiteSpace(name)) existing.DriverName = name;
                if (!string.IsNullOrWhiteSpace(phone)) existing.DriverPhone = phone;
                return existing;
            });
    }

    public void SetAvailability(Guid driverId, bool isAvailable)
    {
        if (_drivers.TryGetValue(driverId, out var info))
        {
            info.IsAvailable = isAvailable;
        }
    }

    public void RemoveDriver(Guid driverId)
    {
        _drivers.TryRemove(driverId, out _);
    }

    public DriverLocationInfo? GetDriver(Guid driverId)
    {
        return _drivers.TryGetValue(driverId, out var info) ? info : null;
    }

    public List<(DriverLocationInfo Driver, double DistanceKm)> GetNearbyAvailableDrivers(
        double shopLat,
        double shopLng,
        double radiusKm,
        IEnumerable<Guid>? excludedDriverIds = null)
    {
        var excludedSet = excludedDriverIds != null ? new HashSet<Guid>(excludedDriverIds) : [];
        var result = new List<(DriverLocationInfo Driver, double DistanceKm)>();

        foreach (var driver in _drivers.Values)
        {
            if (!driver.IsActive(MaxInactivePing))
                continue;

            if (excludedSet.Contains(driver.DriverId))
                continue;

            var distance = CalculateDistanceKm(shopLat, shopLng, driver.Latitude, driver.Longitude);
            if (distance <= radiusKm)
            {
                result.Add((driver, distance));
            }
        }

        // Ưu tiên tài xế ở gần quán nhất
        return result.OrderBy(x => x.DistanceKm).ToList();
    }

    public List<(DriverLocationInfo Driver, double DistanceKm)> GetAllActiveDrivers(
        double shopLat,
        double shopLng,
        IEnumerable<Guid>? excludedDriverIds = null)
    {
        var excludedSet = excludedDriverIds != null ? new HashSet<Guid>(excludedDriverIds) : [];
        var result = new List<(DriverLocationInfo Driver, double DistanceKm)>();

        foreach (var driver in _drivers.Values)
        {
            if (!driver.IsActive(MaxInactivePing))
                continue;

            if (excludedSet.Contains(driver.DriverId))
                continue;

            var distance = CalculateDistanceKm(shopLat, shopLng, driver.Latitude, driver.Longitude);
            result.Add((driver, distance));
        }

        return result.OrderBy(x => x.DistanceKm).ToList();
    }

    /// <summary>
    /// Công thức Haversine tính khoảng cách đường chim bay giữa 2 tọa độ (km)
    /// </summary>
    public static double CalculateDistanceKm(double lat1, double lon1, double lat2, double lon2)
    {
        const double EarthRadiusKm = 6371.0;
        var dLat = (lat2 - lat1) * Math.PI / 180.0;
        var dLon = (lon2 - lon1) * Math.PI / 180.0;

        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(lat1 * Math.PI / 180.0) * Math.Cos(lat2 * Math.PI / 180.0) *
                Math.Sin(dLon / 2) * Math.Sin(dLon / 2);

        var c = 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
        return EarthRadiusKm * c;
    }
}
