import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/admin_api_service.dart';

class AdminOrdersTab extends StatefulWidget {
  const AdminOrdersTab({super.key, required this.api});
  final AdminApiService api;

  @override
  State<AdminOrdersTab> createState() => _AdminOrdersTabState();
}

class _AdminOrdersTabState extends State<AdminOrdersTab> {
  final _currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
  final _searchController = TextEditingController();

  String _selectedStatus = 'Tất cả'; // 'Tất cả', 'Pending', 'Delivering', 'Completed', 'Cancelled'
  bool _loading = true;
  String? _error;
  List<dynamic> _orders = [];
  int _page = 1;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      String? status;
      if (_selectedStatus != 'Tất cả') status = _selectedStatus;

      final res = await widget.api.getOrders(
        query: _searchController.text.trim(),
        status: status,
        page: _page,
        pageSize: _pageSize,
      );

      if (!mounted) return;
      setState(() {
        _orders = res['items'] as List<dynamic>? ?? [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onStatusChanged(String status) {
    if (_selectedStatus == status) return;
    setState(() {
      _selectedStatus = status;
      _page = 1;
    });
    _fetch();
  }

  Future<void> _showDetail(String id) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: Colors.deepOrange)),
    );

    try {
      final detail = await widget.api.getOrderDetail(id);
      if (!mounted) return;
      Navigator.pop(context);

      final customer = detail['customer'] as Map<String, dynamic>? ?? {};
      final restaurant = detail['restaurant'] as Map<String, dynamic>? ?? {};
      final shipper = detail['shipper'] as Map<String, dynamic>? ?? {};
      final items = detail['items'] as List<dynamic>? ?? [];
      final history = detail['statusHistory'] as List<dynamic>? ?? [];
      final totalAmount = (detail['totalAmount'] as num?)?.toDouble() ?? 0.0;
      final subtotal = (detail['subtotal'] as num?)?.toDouble() ?? 0.0;
      final deliveryFee = (detail['deliveryFee'] as num?)?.toDouble() ?? 0.0;
      final discount = (detail['discountAmount'] as num?)?.toDouble() ?? 0.0;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mã đơn: #${detail['orderCode'] ?? id.substring(0, 8)}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('Thời gian: ${detail['createdAt'] ?? ''}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  _buildStatusBadge(detail['status'] ?? 'Pending'),
                ],
              ),
              const Divider(height: 30),

              const Text('Thông tin các bên liên quan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              _buildPartyRow(Icons.person_outline, 'Khách hàng', customer['fullName'] ?? 'N/A', customer['phone'] ?? ''),
              const SizedBox(height: 8),
              _buildPartyRow(Icons.storefront_outlined, 'Quán ăn', restaurant['name'] ?? 'N/A', restaurant['phone'] ?? ''),
              const SizedBox(height: 8),
              _buildPartyRow(Icons.delivery_dining_outlined, 'Tài xế giao hàng', shipper['fullName'] ?? 'Chưa nhận đơn', shipper['phone'] ?? ''),

              const SizedBox(height: 16),
              const Text('Địa chỉ giao hàng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              Text(detail['deliveryAddress'] ?? 'N/A', style: TextStyle(color: Colors.grey.shade800)),

              if (detail['note'] != null && (detail['note'] as String).isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Ghi chú của khách: "${detail['note']}"', style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.deepOrange)),
              ],

              const Divider(height: 30),
              Text('Món ăn đã đặt (${items.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              ...items.map((it) {
                final price = (it['unitPrice'] as num?)?.toDouble() ?? 0.0;
                final qty = (it['quantity'] as num?)?.toInt() ?? 1;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Text('${qty}x ', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                      Expanded(child: Text(it['itemName'] ?? '')),
                      Text(_currencyFormat.format(price * qty), style: const TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                );
              }),

              const Divider(height: 24),
              _buildPriceRow('Tạm tính món', _currencyFormat.format(subtotal)),
              _buildPriceRow('Phí giao hàng', _currencyFormat.format(deliveryFee)),
              if (discount > 0)
                _buildPriceRow('Giảm giá', '-${_currencyFormat.format(discount)}', color: Colors.green),
              const Divider(height: 16),
              _buildPriceRow('Tổng thanh toán', _currencyFormat.format(totalAmount), isTotal: true),
              const SizedBox(height: 6),
              Text('Phương thức: ${detail['paymentMethod'] ?? 'COD'} (${detail['paymentStatus'] ?? 'Chưa thanh toán'})',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),

              if (history.isNotEmpty) ...[
                const Divider(height: 30),
                const Text('Lịch sử trạng thái', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                ...history.map((h) => Text('• ${h['status']}: ${h['changedAt'] ?? ''} ${h['note'] ?? ''}',
                    style: const TextStyle(fontSize: 12))),
              ],
              const SizedBox(height: 30),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red));
    }
  }

  Widget _buildPartyRow(IconData icon, String role, String name, String phone) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.deepOrange),
        const SizedBox(width: 8),
        Text('$role: ', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        Expanded(child: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
        if (phone.isNotEmpty) Text(phone, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildPriceRow(String label, String value, {bool isTotal = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: isTotal ? 16 : 13, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: isTotal ? 16 : 13, fontWeight: FontWeight.bold, color: color ?? (isTotal ? Colors.deepOrange : Colors.black87))),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String text;
    switch (status) {
      case 'Delivered':
      case 'Completed':
        color = Colors.green;
        text = 'Hoàn thành';
        break;
      case 'Delivering':
      case 'PickedUp':
      case 'OnDelivery':
        color = Colors.blue;
        text = 'Đang giao';
        break;
      case 'Cancelled':
        color = Colors.red;
        text = 'Đã hủy';
        break;
      case 'Pending':
      default:
        color = Colors.orange;
        text = 'Chờ xử lý';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          color: Colors.white,
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Tìm theo mã đơn, tên quán, tên khách...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _fetch();
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                ),
                onSubmitted: (_) => _fetch(),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('Tất cả'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Pending', label: 'Chờ xử lý'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Delivering', label: 'Đang giao'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Delivered', label: 'Hoàn thành'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Cancelled', label: 'Đã hủy'),
                  ],
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Colors.deepOrange))
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Lỗi tải đơn hàng: $_error', style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 8),
                          ElevatedButton(onPressed: _fetch, child: const Text('Thử lại')),
                        ],
                      ),
                    )
                  : _orders.isEmpty
                      ? const Center(child: Text('Không có đơn hàng nào.', style: TextStyle(color: Colors.grey)))
                      : RefreshIndicator(
                          onRefresh: _fetch,
                          color: Colors.deepOrange,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _orders.length,
                            itemBuilder: (ctx, index) {
                              final o = _orders[index];
                              final id = o['id'].toString();
                              final code = o['orderCode'] ?? id.substring(0, 8);
                              final status = o['status'] ?? 'Pending';
                              final total = (o['totalAmount'] as num?)?.toDouble() ?? 0.0;
                              final customer = o['customer'] as Map<String, dynamic>? ?? {};
                              final restaurant = o['restaurant'] as Map<String, dynamic>? ?? {};
                              final shipper = o['shipper'] as Map<String, dynamic>? ?? {};

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 0.5,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => _showDetail(id),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text('#$code', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                            const Spacer(),
                                            _buildStatusBadge(status),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            const Icon(Icons.storefront, size: 16, color: Colors.grey),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                restaurant['name'] ?? 'Quán ăn',
                                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(Icons.person, size: 16, color: Colors.grey),
                                            const SizedBox(width: 6),
                                            Text('Khách: ${customer['fullName'] ?? 'N/A'}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                                            if (shipper['fullName'] != null) ...[
                                              const SizedBox(width: 12),
                                              const Icon(Icons.delivery_dining, size: 16, color: Colors.teal),
                                              const SizedBox(width: 4),
                                              Text('TX: ${shipper['fullName']}', style: const TextStyle(fontSize: 12, color: Colors.teal)),
                                            ],
                                          ],
                                        ),
                                        const Divider(height: 18),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(o['createdAt'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                            Text(
                                              _currencyFormat.format(total),
                                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String value, {String? label}) {
    final isSelected = _selectedStatus == value;
    return ChoiceChip(
      label: Text(label ?? value),
      selected: isSelected,
      onSelected: (_) => _onStatusChanged(value),
      selectedColor: Colors.deepOrange,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}
