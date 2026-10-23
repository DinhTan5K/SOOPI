using System.Collections.Concurrent;

namespace SoopiFoodBE.Services;

public interface IDriverOfferManager
{
    TaskCompletionSource<bool> CreateOffer(Guid orderId, Guid driverId);
    bool TryAcceptOffer(Guid orderId, Guid driverId);
    bool TryRejectOffer(Guid orderId, Guid driverId);
    void RemoveOffer(Guid orderId);
}

public sealed class DriverOfferManager : IDriverOfferManager
{
    private sealed record OfferContext(Guid DriverId, TaskCompletionSource<bool> CompletionSource);

    private readonly ConcurrentDictionary<Guid, OfferContext> _activeOffers = new();

    public TaskCompletionSource<bool> CreateOffer(Guid orderId, Guid driverId)
    {
        var tcs = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        _activeOffers[orderId] = new OfferContext(driverId, tcs);
        return tcs;
    }

    public bool TryAcceptOffer(Guid orderId, Guid driverId)
    {
        if (_activeOffers.TryGetValue(orderId, out var offer) && offer.DriverId == driverId)
        {
            var success = offer.CompletionSource.TrySetResult(true);
            _activeOffers.TryRemove(orderId, out _);
            return success;
        }
        return false;
    }

    public bool TryRejectOffer(Guid orderId, Guid driverId)
    {
        if (_activeOffers.TryGetValue(orderId, out var offer) && offer.DriverId == driverId)
        {
            var success = offer.CompletionSource.TrySetResult(false);
            _activeOffers.TryRemove(orderId, out _);
            return success;
        }
        return false;
    }

    public void RemoveOffer(Guid orderId)
    {
        if (_activeOffers.TryRemove(orderId, out var offer))
        {
            offer.CompletionSource.TrySetResult(false);
        }
    }
}
