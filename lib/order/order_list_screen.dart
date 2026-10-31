import 'dart:async';
import '../services/order_socket_service.dart';
import 'package:flutter/material.dart';
import 'order_data.dart';
import 'order_tracking_screen.dart';
import 'order_review_screen.dart';

class OrderListScreen extends StatefulWidget {
  final VoidCallback? onBackToHome;
  final bool isVisible;
  const OrderListScreen({super.key, this.onBackToHome, this.isVisible = false});

  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final OrderData _orderData = OrderData();
  StreamSubscription? _socketStatusSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _refreshAfterBuild();

    _socketStatusSub = OrderSocketService().onOrderStatus.listen((data) {
      if (mounted) {
        final orderId = (data['orderId'] ?? data['OrderId'])?.toString();
        if (orderId != null) {
          _orderData.syncTrack(orderId);
        } else {
          _orderData.refreshFromApi();
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant OrderListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _refreshAfterBuild();
    }
  }

  void _refreshAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _orderData.refreshFromApi();
    });
  }

  @override
  void dispose() {
    _socketStatusSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _onReorder(OrderModel order) {
    final newOrder = _orderData.reorder(order);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã mua lại đơn #${newOrder.id} thành công!'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
    _tabController.animateTo(0);
  }

  String _formatDate(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$hour:$min • $day/$month';
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
      case OrderStatus.preparing:
        return Colors.blue.shade700;
      case OrderStatus.delivering:
        return Colors.orange.shade800;
      case OrderStatus.completed:
        return Colors.green.shade700;
      case OrderStatus.cancelled:
        return Colors.red.shade700;
    }
  }

  Color _getStatusBg(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
      case OrderStatus.preparing:
        return Colors.blue.shade50;
      case OrderStatus.delivering:
        return Colors.orange.shade50;
      case OrderStatus.completed:
        return Colors.green.shade50;
      case OrderStatus.cancelled:
        return Colors.red.shade50;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _orderData,
      builder: (context, _) {
        final activeOrders = _orderData.activeOrders;
        final pastOrders = _orderData.pastOrders;
        final canPop = Navigator.canPop(context);
        final showBackButton = canPop || widget.onBackToHome != null;

        return PopScope(
          canPop: canPop,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && widget.onBackToHome != null) {
              widget.onBackToHome!();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              leading: showBackButton
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                      tooltip: 'Quay lại',
                      onPressed: () {
                        if (canPop) {
                          Navigator.pop(context);
                        } else if (widget.onBackToHome != null) {
                          widget.onBackToHome!();
                        }
                      },
                    )
                  : null,
              title: const Text(
                'Đơn hàng của tôi',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
            actions: [
              IconButton(
                tooltip: 'Làm mới từ máy chủ',
                onPressed: () async {
                  await _orderData.refreshFromApi();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_orderData.isFromBackend
                            ? '✅ Đã tải đơn hàng từ máy chủ BE'
                            : 'ℹ️ Đang dùng dữ liệu offline'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
                icon: _orderData.isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                      )
                    : const Icon(Icons.refresh, color: Colors.orange),
              ),
            ],
            elevation: 0,
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.orange,
              labelColor: Colors.orange,
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              indicatorWeight: 3,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Đang đến'),
                      if (activeOrders.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${activeOrders.length}',
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Tab(child: Text('Lịch sử đơn (${pastOrders.length})')),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildOrdersList(
                orders: activeOrders,
                emptyTitle: 'Chưa có đơn hàng nào đang giao',
                emptySubtitle: 'Hãy chọn món ăn yêu thích và đặt ngay nhé!',
                emptyIcon: Icons.delivery_dining_rounded,
              ),
              _buildOrdersList(
                orders: pastOrders,
                emptyTitle: 'Chưa có lịch sử đơn hàng',
                emptySubtitle: 'Các đơn hàng đã hoàn thành hoặc đã hủy sẽ hiển thị ở đây.',
                emptyIcon: Icons.receipt_long_rounded,
              ),
            ],
          ),
        ),
      );
    },
  );
}

  Widget _buildOrdersList({
    required List<OrderModel> orders,
    required String emptyTitle,
    required String emptySubtitle,
    required IconData emptyIcon,
  }) {
    if (orders.isEmpty) {
      if (_orderData.isLoading) {
        return const Center(child: CircularProgressIndicator(color: Colors.orange));
      }
      return RefreshIndicator(
        onRefresh: _orderData.refreshFromApi,
        color: Colors.orange,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(emptyIcon, size: 64, color: Colors.orange.shade300),
                const SizedBox(height: 16),
                Text(emptyTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(emptySubtitle, style: const TextStyle(color: Colors.grey, fontSize: 13), textAlign: TextAlign.center),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _orderData.refreshFromApi,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Tải lại đơn hàng'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _orderData.refreshFromApi,
      color: Colors.orange,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        itemBuilder: (context, index) => _buildOrderCard(orders[index]),
      ),
    );
  }

  Widget _buildOrderCard(OrderModel order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Icon(Icons.storefront_rounded, color: Colors.orange, size: 24),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.restaurantName,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '#${order.id} • ${_formatDate(order.createdAt)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _getStatusBg(order.status),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    order.status.label,
                    style: TextStyle(
                      color: _getStatusColor(order.status),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.items.map((i) => '${i.quantity}x ${i.name}').join(', '),
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${order.items.fold(0, (sum, i) => sum + i.quantity)} món',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Row(
                      children: [
                        const Text('Tổng tiền: ', style: TextStyle(fontSize: 13, color: Colors.grey)),
                        Text(
                          money(order.totalPrice),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.orange),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _buildCardActions(order),
          ),
        ],
      ),
    );
  }

  Widget _buildCardActions(OrderModel order) {
    if (order.isActive) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: order.id)),
            );
          },
          icon: const Icon(Icons.two_wheeler, size: 20),
          label: const Text('Theo dõi đơn hàng ', style: TextStyle(fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _onReorder(order),
            icon: const Icon(Icons.replay, size: 18),
            label: const Text('Mua lại', style: TextStyle(fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange,
              side: const BorderSide(color: Colors.orange),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),

        if (order.status == OrderStatus.completed) ...[
          const SizedBox(width: 10),
          Expanded(
            child: order.isReviewed
                ? Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Center(
                      child: Text(
                        'Đã đánh giá (${order.review!.restaurantRating}⭐)',
                        style: TextStyle(
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => OrderReviewScreen(order: order)),
                      );
                    },
                    icon: const Icon(Icons.star_border, size: 18),
                    label: const Text('Đánh giá', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
          ),
        ],
      ],
    );
  }
}
