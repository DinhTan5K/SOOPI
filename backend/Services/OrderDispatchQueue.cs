using System.Threading.Channels;
using SoopiFoodBE.Contracts;

namespace SoopiFoodBE.Services;

public interface IOrderDispatchQueue
{
    ValueTask EnqueueAsync(OrderDispatchTask task, CancellationToken ct = default);
    IAsyncEnumerable<OrderDispatchTask> ReadAllAsync(CancellationToken ct = default);
}

public sealed class OrderDispatchQueue : IOrderDispatchQueue
{
    private readonly Channel<OrderDispatchTask> _channel;

    public OrderDispatchQueue()
    {
        // Unbounded channel with SingleReader = true for efficient processing
        var options = new UnboundedChannelOptions
        {
            SingleReader = false,
            SingleWriter = false
        };
        _channel = Channel.CreateUnbounded<OrderDispatchTask>(options);
    }

    public ValueTask EnqueueAsync(OrderDispatchTask task, CancellationToken ct = default)
    {
        return _channel.Writer.WriteAsync(task, ct);
    }

    public IAsyncEnumerable<OrderDispatchTask> ReadAllAsync(CancellationToken ct = default)
    {
        return _channel.Reader.ReadAllAsync(ct);
    }
}
