using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using SoopiFoodBE.Contracts;
using SoopiFoodBE.Hubs;

namespace SoopiFoodBE.Services;

public sealed class OrderDispatchWorker(
    IOrderDispatchQueue queue,
    IDriverLocationService locationService,
    IDriverOfferManager offerManager,
    IHubContext<OrderHub> hubContext,
    IServiceScopeFactory scopeFactory,
    ILogger<OrderDispatchWorker> logger) : BackgroundService
{
    // Bán kính mở rộng: 1km -> 3km -> 5km
    private static readonly double[] RadiusSteps = [1.0, 3.0, 5.0];

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        logger.LogInformation("OrderDispatchWorker background service is running.");

        await foreach (var task in queue.ReadAllAsync(stoppingToken))
        {
            // Bắn một task riêng trên ThreadPool cho từng đơn hàng để không làm nghẽn hàng đợi
            _ = Task.Run(async () =>
            {
                try
                {
                    await ProcessDispatchTaskAsync(task, stoppingToken);
                }
                catch (Exception ex)
                {
                    logger.LogError(ex, "Error processing dispatch for Order {OrderId}", task.OrderId);
                }
            }, stoppingToken);
        }
    }

    private async Task ProcessDispatchTaskAsync(OrderDispatchTask task, CancellationToken stoppingToken)
    {
        logger.LogInformation("Starting driver dispatch for Order {OrderCode} ({OrderId})", task.OrderCode, task.OrderId);

        foreach (var radius in RadiusSteps)
        {
            if (stoppingToken.IsCancellationRequested) return;

            // Tìm các tài xế khả dụng quanh quán trong bán kính hiện tại
            var candidates = locationService.GetNearbyAvailableDrivers(
                task.RestaurantLatitude,
                task.RestaurantLongitude,
                radius,
                task.ExcludedDriverIds);

            logger.LogInformation("Order {OrderId}: Found {Count} candidate driver(s) in radius {Radius}km",
                task.OrderId, candidates.Count, radius);

            if (candidates.Count == 0)
            {
                continue; // Chuyển sang bán kính lớn hơn ngay lập tức
            }

            foreach (var (driver, distance) in candidates)
            {
                if (stoppingToken.IsCancellationRequested) return;

                // Tạo offer và chuẩn bị chờ phản hồi
                var offerTcs = offerManager.CreateOffer(task.OrderId, driver.DriverId);

                // Gửi SignalR nổ đơn đến phòng riêng của tài xế
                var payload = new DriverOfferPayload(
                    task.OrderId,
                    task.OrderCode,
                    task.RestaurantName,
                    task.DeliveryAddress,
                    task.DeliveryFee,
                    task.TotalAmount,
                    Math.Round(distance, 2),
                    15
                );

                await hubContext.Clients.Group($"driver_{driver.DriverId}")
                    .SendAsync("NewDeliveryOffer", payload, cancellationToken: stoppingToken);

                logger.LogInformation("Sent offer for Order {OrderId} to Driver {DriverId} (distance: {Dist}km)",
                    task.OrderId, driver.DriverId, distance);

                // Chờ tài xế phản hồi hoặc timeout 15s
                using var timeoutCts = new CancellationTokenSource(TimeSpan.FromSeconds(15));
                using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken, timeoutCts.Token);

                bool accepted = false;
                try
                {
                    var completedTask = await Task.WhenAny(offerTcs.Task, Task.Delay(Timeout.Infinite, linkedCts.Token));
                    if (completedTask == offerTcs.Task)
                    {
                        accepted = await offerTcs.Task;
                    }
                }
                catch (OperationCanceledException)
                {
                    accepted = false;
                }

                if (accepted)
                {
                    logger.LogInformation("Driver {DriverId} accepted Order {OrderId}. Assigning in DB...",
                        driver.DriverId, task.OrderId);

                    using var scope = scopeFactory.CreateScope();
                    var orderService = scope.ServiceProvider.GetRequiredService<IOrderService>();
                    var assigned = await orderService.AssignShipperAsync(task.OrderId, driver.DriverId, stoppingToken);

                    if (assigned)
                    {
                        // Đánh dấu tài xế đang bận
                        locationService.SetAvailability(driver.DriverId, false);
                        logger.LogInformation("Order {OrderId} successfully assigned to Driver {DriverId}!",
                            task.OrderId, driver.DriverId);
                        return; // Hoàn tất tìm tài xế!
                    }
                }

                // Nếu từ chối hoặc hết 15s hoặc gán DB không thành công
                offerManager.RemoveOffer(task.OrderId);
                task.ExcludedDriverIds.Add(driver.DriverId);

                await hubContext.Clients.Group($"driver_{driver.DriverId}")
                    .SendAsync("DeliveryOfferExpired", new { orderId = task.OrderId }, cancellationToken: stoppingToken);
            }

            // Chờ 5s trước khi mở rộng bán kính ở vòng lặp tiếp theo
            await Task.Delay(5000, stoppingToken);
        }

        // Hết tất cả các bán kính (tối đa 5km quanh quán) mà không có tài xế nào nhận
        logger.LogWarning("Order {OrderId}: No available driver found within 5km radius.", task.OrderId);
        await hubContext.Clients.Group($"order_{task.OrderId}")
            .SendAsync("NoDriverAvailable", new { orderId = task.OrderId }, cancellationToken: stoppingToken);
    }
}
