import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'merchant_data.dart';

enum OrderStatus {
  pending('Chờ xác nhận', Colors.deepOrange),
  preparing('Đang chuẩn bị', Colors.blue),
  ready('Sẵn sàng', Colors.teal),
  completed('Hoàn tất', Colors.green),
  rejected('Đã từ chối', Colors.grey);

  const OrderStatus(this.label, this.color);
  final String label;
  final MaterialColor color;
}

class _OrderItem {
  const _OrderItem(this.name, this.quantity, this.price);
  final String name;
  final int quantity;
  final int price;
}

class _Order {
  _Order(
    this.id,
    this.customer,
    this.time,
    this.address,
    this.items, {
    this.note = '',
    this.paid = false,
    this.status = OrderStatus.pending,
  });
  final String id;
  final String customer;
  final String time;
  final String address;
  final List<_OrderItem> items;
  final String note;
  final bool paid;
  OrderStatus status;
  int get total =>
      items.fold(0, (sum, item) => sum + item.quantity * item.price);
}

class MerchantOrders extends StatefulWidget {
  const MerchantOrders({super.key, required this.acceptingOrders});
  final bool acceptingOrders;

  @override
  State<MerchantOrders> createState() => _MerchantOrdersState();
}

class _MerchantOrdersState extends State<MerchantOrders> {
  static const _sound = MethodChannel('soopi/order_alert');
  bool _soundEnabled = true;
  bool _alertOpen = false;
  int _nextId = 1025;
  OrderStatus? _filter;
  final _orders = [
    _Order(
      'SP1024',
      'Nguyễn Minh Anh',
      '11:42',
      '12 Nguyễn Văn Bảo, Gò Vấp',
      [
        const _OrderItem('Double Cheese Burger', 2, 65000),
        const _OrderItem('Khoai tây chiên', 1, 30000),
      ],
      note: 'Burger không hành, cho thêm tương cà.',
      paid: true,
    ),
    _Order('SP1023', 'Trần Quốc Huy', '11:38', '45 Lê Văn Việt, Thủ Đức', [
      const _OrderItem('Pepperoni Pizza', 1, 120000),
      const _OrderItem('Trà đào cam sả', 2, 35000),
    ], note: 'Ít đá cho cả hai ly.'),
    _Order(
      'SP1022',
      'Lê Thảo Vy',
      '11:30',
      '88 Quang Trung, Gò Vấp',
      [
        const _OrderItem('Double Cheese Burger', 1, 65000),
        const _OrderItem('Khoai tây chiên', 2, 30000),
      ],
      paid: true,
      status: OrderStatus.preparing,
    ),
    _Order(
      'SP1021',
      'Phạm Tuấn Khang',
      '11:20',
      '20 Phan Văn Trị, Bình Thạnh',
      [const _OrderItem('Pepperoni Pizza', 2, 120000)],
      status: OrderStatus.ready,
    ),
    _Order(
      'SP1020',
      'Đỗ Ngọc Hà',
      '10:55',
      '60 Nguyễn Kiệm, Phú Nhuận',
      [const _OrderItem('Double Cheese Burger', 1, 65000)],
      paid: true,
      status: OrderStatus.completed,
    ),
  ];

  Future<void> _playAlert() async {
    if (!_soundEnabled) return;
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _sound.invokeMethod<void>('play');
      } else {
        await SystemSound.play(SystemSoundType.alert);
      }
    } on PlatformException {
      // The order remains visible even if the device cannot play audio.
    } on MissingPluginException {
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  Future<void> _newMockOrder() async {
    if (_alertOpen || !widget.acceptingOrders) return;
    final now = DateTime.now();
    final order = _Order(
      'SP${_nextId++}',
      'Nguyễn Hoàng Nam',
      clockLabel(now.hour * 60 + now.minute),
      '25 Nguyễn Văn Bảo, Gò Vấp',
      [
        const _OrderItem('Double Cheese Burger', 2, 65000),
        const _OrderItem('Khoai tây chiên', 1, 30000),
      ],
      note: 'Không hành, thêm tương cà.',
      paid: true,
    );
    setState(() {
      _orders.insert(0, order);
      _filter = OrderStatus.pending;
      _alertOpen = true;
    });
    // Show the order immediately; audio must not delay the dialog.
    _playAlert();
    final action = await showDialog<OrderStatus>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.notifications_active,
          color: Colors.deepOrange,
          size: 48,
        ),
        title: const Text('Bạn có đơn hàng mới!'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${order.id} • ${order.time}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(order.customer),
                Text('Giao đến: ${order.address}'),
                const Divider(height: 24),
                for (final item in order.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('${item.quantity} × ${item.name}'),
                  ),
                Text('Ghi chú: ${order.note}'),
                const Divider(height: 24),
                Text(
                  'Tổng tiền: ${money(order.total)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepOrange,
                  ),
                ),
                const Text('Đã thanh toán'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Xem sau'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext, OrderStatus.rejected),
            child: const Text('Từ chối'),
          ),
          FilledButton.icon(
            onPressed: widget.acceptingOrders
                ? () => Navigator.pop(dialogContext, OrderStatus.preparing)
                : null,
            icon: const Icon(Icons.check),
            label: const Text('Nhận đơn'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _alertOpen = false);
    if (action != null) _update(order, action);
  }

  void _update(_Order order, OrderStatus status) {
    setState(() => order.status = status);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đơn #${order.id}: ${status.label.toLowerCase()}.'),
      ),
    );
  }

  Future<void> _reject(_Order order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Từ chối đơn #${order.id}?'),
        content: const Text(
          'Đơn sẽ chuyển sang trạng thái đã từ chối trong bản demo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Quay lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Từ chối đơn'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) _update(order, OrderStatus.rejected);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _orders
        .where((order) => _filter == null || order.status == _filter)
        .toList();
    final pending = _orders
        .where((order) => order.status == OrderStatus.pending)
        .length;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Đơn hàng',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          '$pending đơn đang chờ xác nhận',
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: widget.acceptingOrders && !_alertOpen
                  ? _newMockOrder
                  : null,
              icon: const Icon(Icons.add_alert_outlined),
              label: const Text('Tạo đơn mới (demo)'),
            ),
            FilterChip(
              avatar: Icon(
                _soundEnabled ? Icons.volume_up : Icons.volume_off,
                size: 18,
              ),
              label: const Text('Âm thanh thông báo'),
              selected: _soundEnabled,
              onSelected: (value) => setState(() => _soundEnabled = value),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFEAD4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.deepOrange),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Dữ liệu mẫu • Thao tác chỉ lưu trong phiên demo, không gửi đơn thực tế.',
                ),
              ),
            ],
          ),
        ),
        if (!widget.acceptingOrders)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Quán đang tạm ngưng nhận đơn. Bật nhận đơn ở tab Quán của tôi để xác nhận đơn mới.',
              style: TextStyle(color: Colors.deepOrange),
            ),
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ChoiceChip(
              label: Text('Tất cả (${_orders.length})'),
              selected: _filter == null,
              onSelected: (_) => setState(() => _filter = null),
            ),
            for (final status in OrderStatus.values)
              ChoiceChip(
                label: Text(
                  '${status.label} (${_orders.where((order) => order.status == status).length})',
                ),
                selected: _filter == status,
                onSelected: (_) => setState(() => _filter = status),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 48,
                  color: Colors.black38,
                ),
                SizedBox(height: 12),
                Text('Chưa có đơn ở trạng thái này.'),
              ],
            ),
          ),
        for (final order in visible) _card(order),
      ],
    );
  }

  Widget _card(_Order order) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '#${order.id}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(order.time, style: const TextStyle(color: Colors.black54)),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: order.status.color.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  order.status.label,
                  style: TextStyle(
                    color: order.status.color.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            order.customer,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Giao đến: ${order.address}',
            style: const TextStyle(color: Colors.black54),
          ),
          const Divider(height: 24),
          for (final item in order.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text('${item.quantity} × ${item.name}')),
                  const SizedBox(width: 12),
                  Text(money(item.quantity * item.price)),
                ],
              ),
            ),
          if (order.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Ghi chú: ${order.note}',
                style: TextStyle(color: Colors.deepOrange.shade800),
              ),
            ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  order.paid ? 'Đã thanh toán' : 'Thanh toán khi nhận',
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                money(order.total),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepOrange,
                ),
              ),
            ],
          ),
          if (order.status == OrderStatus.pending) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _reject(order),
                    child: const Text('Từ chối'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: widget.acceptingOrders
                        ? () => _update(order, OrderStatus.preparing)
                        : null,
                    icon: const Icon(Icons.check),
                    label: const Text('Nhận đơn'),
                  ),
                ),
              ],
            ),
          ],
          if (order.status == OrderStatus.preparing ||
              order.status == OrderStatus.ready) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _update(
                  order,
                  order.status == OrderStatus.preparing
                      ? OrderStatus.ready
                      : OrderStatus.completed,
                ),
                icon: Icon(
                  order.status == OrderStatus.preparing
                      ? Icons.restaurant
                      : Icons.done_all,
                ),
                label: Text(
                  order.status == OrderStatus.preparing
                      ? 'Món đã sẵn sàng'
                      : 'Hoàn tất đơn',
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
