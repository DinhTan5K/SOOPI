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
    _tabController = TabController(length: 3, vsync: this);
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
    _fetchOrders(silent: true);
    if (_tabController.index != 0) {
      _tabController.animateTo(0);
    }
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
      case 'accepted':
      case 'preparing':
        return 'Đang làm món';
      case 'readyforpickup':
        return 'Chờ tài xế lấy món';
      case 'pickedup':
      case 'delivering':
        return 'Tài xế đang giao';
      case 'delivered':
      case 'completed':
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
      case 'accepted':
      case 'preparing':
        return Colors.blue;
      case 'readyforpickup':
        return Colors.deepOrange;
      case 'pickedup':
      case 'delivering':
        return Colors.purple;
      case 'delivered':
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  List<Map<String, dynamic>> _filterOrders(int tabIndex) {
    switch (tabIndex) {
      case 0: // Đang nấu (Gồm đơn chờ xác nhận và đang nấu)
        return _orders.where((o) {
          final s = o['status']?.toString().toLowerCase();
          return s == 'pending' || s == 'accepted' || s == 'preparing';
        }).toList();
      case 1: // Đang giao (Gồm đơn chờ shipper lấy và shipper đang đi giao)
        return _orders.where((o) {
          final s = o['status']?.toString().toLowerCase();
          return s == 'readyforpickup' || s == 'pickedup' || s == 'delivering';
        }).toList();
      case 2: // Lịch sử (Đã hoàn thành / Đã hủy)
        return _orders.where((o) {
          final s = o['status']?.toString().toLowerCase();
          return s == 'delivered' || s == 'completed' || s == 'cancelled';
        }).toList();
      default:
        return _orders;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cookingCount = _filterOrders(0).length;
    final deliveringCount = _filterOrders(1).length;

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
              TextButton(
                onPressed: () => _fetchOrders(),
                child: const Text('Làm mới'),
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
            child: const Text(
              'Quán đang tạm ngưng nhận đơn.',
              style: TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w500),
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
                  const Text('Đang nấu'),
                  if (cookingCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$cookingCount',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                children: [
                  const Text('Đang giao'),
                  if (deliveringCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$deliveringCount',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Lịch sử'),
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
        child: Text(
          tabIndex == 0
              ? 'Hiện chưa có đơn hàng mới nào.'
              : 'Không có đơn hàng trong mục này.',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
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
    final shipperId = order['shipperId']?.toString();
    final shipperName = order['shipperName']?.toString();
    final shipperPhone = order['shipperPhone']?.toString();
    final address = order['deliveryAddress']?.toString() ?? '';
    final total = (order['totalAmount'] as num?)?.toInt() ?? 0;
    final note = order['note']?.toString() ?? '';
    final items = (order['items'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final statusLow = status.toLowerCase();
    final hasShipper = shipperId != null && shipperId.isNotEmpty;

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
                Text(customerName, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (customerPhone.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text('• $customerPhone', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ],
              ],
            ),

            if (address.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Địa chỉ: $address',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            if (statusLow == 'readyforpickup' || statusLow == 'delivering' || statusLow == 'pickedup') ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: hasShipper ? Colors.green.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hasShipper
                      ? (statusLow == 'readyforpickup'
                          ? 'Tài xế ${shipperName ?? 'SOOPI'} (${shipperPhone ?? ''}) đang đến quán lấy món'
                          : 'Tài xế ${shipperName ?? 'SOOPI'} (${shipperPhone ?? ''}) đang giao đến khách hàng')
                      : 'Đang tìm tài xế gần quán...',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: hasShipper ? Colors.green.shade800 : Colors.deepOrange.shade800,
                  ),
                ),
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
                        item['itemName']?.toString() ?? 'Món ăn',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      _formatMoney(((item['unitPrice'] as num?)?.toInt() ?? 0) * ((item['quantity'] as num?)?.toInt() ?? 1)),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),

            if (note.isNotEmpty) ...[
              const SizedBox(height: 8),
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
                      FilledButton(
                        onPressed: () => _updateStatus(orderId, 'Preparing'),
                        style: FilledButton.styleFrom(backgroundColor: Colors.green),
                        child: const Text('Nhận đơn'),
                      ),
                    ] else if (statusLow == 'accepted' || statusLow == 'preparing') ...[
                      FilledButton(
                        onPressed: () => _updateStatus(orderId, 'ReadyForPickup'),
                        style: FilledButton.styleFrom(backgroundColor: Colors.blue),
                        child: const Text('Xong - Giao shipper'),
                      ),
                    ] else if (statusLow == 'readyforpickup' && !hasShipper) ...[
                      OutlinedButton(
                        onPressed: () => _updateStatus(orderId, 'ReadyForPickup', note: 'Phát lại tín hiệu gọi Shipper'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue,
                          side: const BorderSide(color: Colors.blue),
                        ),
                        child: const Text('Gọi lại Shipper'),
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
