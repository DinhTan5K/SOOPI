import 'dart:async';
import 'package:flutter/material.dart';
import '../services/merchant_api_service.dart';
import '../services/order_socket_service.dart';

class MerchantOrders extends StatefulWidget {
  const MerchantOrders({
    super.key,
    required this.acceptingOrders,
    this.restaurantId,
    this.api,
  });

  final bool acceptingOrders;
  final String? restaurantId;
  final MerchantApiService? api;

  @override
  State<MerchantOrders> createState() => _MerchantOrdersState();
}

class _MerchantOrdersState extends State<MerchantOrders>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = false;
  String? _error;

  StreamSubscription? _newOrderSub;
  StreamSubscription? _statusSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initSocketAndFetch();
  }

  void _initSocketAndFetch() {
    _fetchOrders();
    final restId = widget.restaurantId;
    if (restId != null && restId.isNotEmpty) {
      final socket = OrderSocketService();
      socket.joinRestaurant(restId);

      _newOrderSub?.cancel();
      _newOrderSub = socket.onNewOrder.listen((orderData) {
        if (!mounted) return;
        _onNewOrderReceived(orderData);
      });

      _statusSub?.cancel();
      _statusSub = socket.onOrderStatus.listen((data) {
        if (!mounted) return;
        _fetchOrders(silent: true);
      });
    }
  }

  @override
  void didUpdateWidget(covariant MerchantOrders oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.restaurantId != widget.restaurantId &&
        widget.restaurantId != null) {
      _initSocketAndFetch();
    }
  }

  @override
  void dispose() {
    _newOrderSub?.cancel();
    _statusSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchOrders({bool silent = false}) async {
    final restId = widget.restaurantId;
    final api = widget.api;
    if (restId == null || api == null) return;

    if (!silent) setState(() => _isLoading = true);
    try {
      final result = await api.request(
        'GET',
        'restaurants/$restId/orders?pageSize=100',
      );
      if (mounted) {
        final list = (result['items'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        setState(() {
          _orders = list;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Không thể tải đơn hàng: $e';
        });
      }
    }
  }

  void _onNewOrderReceived(Map<String, dynamic> order) {
    // Tải lại danh sách đơn
    _fetchOrders(silent: true);

    // Chuyển sang tab "Đơn mới"
    if (_tabController.index != 0) {
      _tabController.animateTo(0);
    }

    // Hiển thị Popup Modal thông báo đơn mới tức thì
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.notifications_active, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('🔔 Có đơn hàng mới!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Khách hàng: ${order['customerName'] ?? 'Khách'}', style: const TextStyle(fontWeight: FontWeight.bold)),
            if (order['customerPhone'] != null && order['customerPhone'].toString().isNotEmpty)
              Text('SĐT: ${order['customerPhone']}'),
            const SizedBox(height: 4),
            Text('Địa chỉ: ${order['deliveryAddress'] ?? 'Địa chỉ mặc định'}', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
            const Divider(height: 16),
            Text('Tổng tiền: ${_formatMoney((order['totalAmount'] as num?)?.toInt() ?? 0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 16)),
            if (order['note'] != null && order['note'].toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Ghi chú: "${order['note']}"', style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.black87)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Để sau'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              final orderId = order['orderId']?.toString();
              if (orderId != null) {
                _updateStatus(orderId, 'Preparing');
              }
            },
            icon: const Icon(Icons.check),
            label: const Text('Nhận đơn ngay'),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
          ),
        ],
      ),
    );
  }

  Future<void> _updateStatus(String orderId, String newStatus, {String? note}) async {
    final restId = widget.restaurantId;
    final api = widget.api;
    if (restId == null || api == null) return;

    try {
      await api.request(
        'PATCH',
        'restaurants/$restId/orders/$orderId/status',
        {'status': newStatus, 'note': note},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã cập nhật trạng thái sang: ${_statusLabel(newStatus)}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        _fetchOrders(silent: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi cập nhật: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatMoney(int amount) =>
      '${amount.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')}đ';

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Chờ xác nhận';
      case 'preparing':
        return 'Đang làm món';
      case 'delivering':
        return 'Đang giao hàng';
      case 'delivered':
        return 'Đã hoàn thành';
      case 'cancelled':
        return 'Đã hủy';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'preparing':
        return Colors.blue;
      case 'delivering':
        return Colors.purple;
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  List<Map<String, dynamic>> _filterOrders(int tabIndex) {
    switch (tabIndex) {
      case 0: // Đơn mới
        return _orders.where((o) => (o['status']?.toString().toLowerCase() == 'pending')).toList();
      case 1: // Đang làm
        return _orders.where((o) => (o['status']?.toString().toLowerCase() == 'preparing')).toList();
      case 2: // Đang giao
        return _orders.where((o) => (o['status']?.toString().toLowerCase() == 'delivering')).toList();
      case 3: // Lịch sử (Completed / Cancelled)
        return _orders.where((o) {
          final s = o['status']?.toString().toLowerCase();
          return s == 'delivered' || s == 'cancelled';
        }).toList();
      default:
        return _orders;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _orders.where((o) => (o['status']?.toString().toLowerCase() == 'pending')).length;

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Quản lý Đơn hàng',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.orange),
                    tooltip: 'Làm mới',
                    onPressed: () => _fetchOrders(),
                  ),
                ],
              ),
            ],
          ),
        ),

        if (!widget.acceptingOrders)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Row(
              children: const [
                Icon(Icons.pause_circle_outline, color: Colors.amber, size: 20),
                SizedBox(width: 8),
                Text(
                  'Quán đang tạm ngưng nhận đơn.',
                  style: TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

        // Tabs
        TabBar(
          controller: _tabController,
          labelColor: Colors.orange,
          unselectedLabelColor: Colors.black54,
          indicatorColor: Colors.orange,
          indicatorWeight: 3,
          isScrollable: true,
          tabs: [
            Tab(
              child: Row(
                children: [
                  const Text('Đơn mới'),
                  if (pendingCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$pendingCount',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Đang nấu 🍳'),
            const Tab(text: 'Đang giao 🛵'),
            const Tab(text: 'Lịch sử 📋'),
          ],
        ),

        // Tab views
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.orange))
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 40),
                          const SizedBox(height: 8),
                          Text(_error!, style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () => _fetchOrders(),
                            child: const Text('Thử lại'),
                          ),
                        ],
                      ),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildOrderList(0),
                        _buildOrderList(1),
                        _buildOrderList(2),
                        _buildOrderList(3),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _buildOrderList(int tabIndex) {
    final list = _filterOrders(tabIndex);

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              tabIndex == 0
                  ? 'Hiện chưa có đơn hàng mới nào.'
                  : 'Không có đơn hàng trong mục này.',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _fetchOrders(),
      color: Colors.orange,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _buildOrderCard(list[index]),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final orderId = order['id']?.toString() ?? '';
    final orderCode = order['orderCode']?.toString() ?? orderId.substring(0, 8);
    final status = order['status']?.toString() ?? 'Pending';
    final customerName = order['customerName']?.toString() ?? 'Khách hàng';
    final customerPhone = order['customerPhone']?.toString() ?? '';
    final address = order['deliveryAddress']?.toString() ?? '';
    final total = (order['totalAmount'] as num?)?.toInt() ?? 0;
    final note = order['note']?.toString() ?? '';
    final items = (order['items'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final statusLow = status.toLowerCase();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order Code & Status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '#$orderCode',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _statusColor(status).withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: TextStyle(
                      color: _statusColor(status),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Customer info
            Row(
              children: [
                const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text(customerName, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (customerPhone.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text('• $customerPhone', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ],
              ],
            ),

            if (address.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      address,
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            const Divider(height: 20),

            // Items list
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Text(
                      '${item['quantity']}x',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item['itemName']?.toString() ?? '',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      _formatMoney(((item['unitPrice'] as num?)?.toInt() ?? 0) * ((item['quantity'] as num?)?.toInt() ?? 1)),
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                    ),
                  ],
                ),
              ),

            if (note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Ghi chú: "$note"',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.amber.shade900),
                ),
              ),
            ],

            const Divider(height: 20),

            // Total and Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tổng thu quán', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    Text(
                      _formatMoney(total),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.orange),
                    ),
                  ],
                ),

                // Dynamic buttons based on status
                Row(
                  children: [
                    if (statusLow == 'pending') ...[
                      OutlinedButton(
                        onPressed: () => _updateStatus(orderId, 'Cancelled', note: 'Quán bận/hết món'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                        child: const Text('Từ chối'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => _updateStatus(orderId, 'Preparing'),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Nhận đơn'),
                        style: FilledButton.styleFrom(backgroundColor: Colors.green),
                      ),
                    ] else if (statusLow == 'preparing') ...[
                      FilledButton.icon(
                        onPressed: () => _updateStatus(orderId, 'Delivering'),
                        icon: const Icon(Icons.delivery_dining, size: 18),
                        label: const Text('Xong - Giao shipper'),
                        style: FilledButton.styleFrom(backgroundColor: Colors.blue),
                      ),
                    ] else if (statusLow == 'delivering') ...[
                      FilledButton.icon(
                        onPressed: () => _updateStatus(orderId, 'Delivered'),
                        icon: const Icon(Icons.done_all, size: 18),
                        label: const Text('Đã hoàn thành'),
                        style: FilledButton.styleFrom(backgroundColor: Colors.green),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
