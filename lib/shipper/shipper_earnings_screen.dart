import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../auth_screen.dart';
import '../services/auth_service.dart';
import '../services/profile_api_service.dart';
import '../services/shipper_earnings_service.dart';

class ShipperEarningsScreen extends StatefulWidget {
  final bool isOnline;
  final bool isLoadingOnline;
  final Future<void> Function(bool value)? onToggleOnline;

  const ShipperEarningsScreen({
    super.key,
    this.isOnline = true,
    this.isLoadingOnline = false,
    this.onToggleOnline,
  });

  @override
  State<ShipperEarningsScreen> createState() => _ShipperEarningsScreenState();
}

class _ShipperEarningsScreenState extends State<ShipperEarningsScreen> {
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
  final _earningsService = ShipperEarningsService();
  String _shipperName = 'Tài xế SOOPI';
  String _shipperPhone = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _earningsService.addListener(_onEarningsChanged);
    _earningsService.init();
  }

  @override
  void dispose() {
    _earningsService.removeListener(_onEarningsChanged);
    super.dispose();
  }

  void _onEarningsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await ProfileApiService().getProfile();
      if (mounted && profile.id.isNotEmpty) {
        setState(() {
          _shipperName = profile.fullName.isNotEmpty ? profile.fullName : 'Tài xế SOOPI';
          _shipperPhone = profile.phoneNumber;
        });
      }
    } catch (_) {}
  }

  Future<void> _refresh() async {
    await Future.wait([
      _loadProfile(),
      _earningsService.init(),
    ]);
  }

  void _showCustomerReviewsDialog() {
    final reviews = _earningsService.reviews;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Đánh giá từ khách hàng (${reviews.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: reviews.isEmpty
                    ? const Center(
                        child: Text(
                          'Chưa có đánh giá nào từ khách hàng.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        itemCount: reviews.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final r = reviews[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Đơn #${r.orderCode}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    Row(
                                      children: List.generate(
                                        5,
                                        (starIdx) => Icon(
                                          starIdx < r.rating ? Icons.star : Icons.star_border,
                                          color: Colors.amber,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  r.restaurantName,
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                if (r.tags.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    children: r.tags
                                        .map((t) => Chip(
                                              label: Text(t, style: const TextStyle(fontSize: 11)),
                                              padding: EdgeInsets.zero,
                                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              backgroundColor: Colors.orange.shade50,
                                              side: BorderSide(color: Colors.orange.shade200),
                                            ))
                                        .toList(),
                                  ),
                                ],
                                if (r.comment.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    '"${r.comment}"',
                                    style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13),
                                  ),
                                ],
                                if (r.tipAmount > 0) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tiền tip thêm: +${currencyFormat.format(r.tipAmount)}',
                                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showOrderHistoryDialog() {
    final trips = _earningsService.trips;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Lịch sử cuốc xe hoàn thành',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: trips.isEmpty
                    ? const Center(
                        child: Text(
                          'Chưa có cuốc xe nào hoàn thành.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        itemCount: trips.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final t = trips[index];
                          return ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Colors.green,
                              child: Icon(Icons.check, color: Colors.white, size: 20),
                            ),
                            title: Text('Đơn #${t.orderCode}'),
                            subtitle: Text('${t.restaurantName} • ${t.deliveryAddress}'),
                            trailing: Text(
                              '+${currencyFormat.format(t.deliveryFee)}',
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final todayEarnings = _earningsService.todayEarnings;
    final totalEarnings = _earningsService.totalEarnings;
    final tripsCount = _earningsService.trips.length;
    final rating = _earningsService.rating;
    final isLoading = _earningsService.isLoading;

    final displayEarnings = todayEarnings > 0 ? todayEarnings : totalEarnings;
    final earningsTitle = todayEarnings > 0
        ? 'Tổng thu nhập hôm nay'
        : (totalEarnings > 0 ? 'Tổng thu nhập các đơn đã giao' : 'Tổng thu nhập hôm nay');

    return RefreshIndicator(
      onRefresh: _refresh,
      color: Colors.deepOrange,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thẻ Bật / Tắt chế độ sẵn sàng nhận cuốc
            Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: widget.isOnline ? Colors.green.shade50 : Colors.grey.shade100,
                      child: Icon(
                        widget.isOnline ? Icons.radar : Icons.power_settings_new,
                        color: widget.isOnline ? Colors.green : Colors.grey,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.isOnline ? 'Đang sẵn sàng nhận cuốc' : 'Đang tạm dừng nhận cuốc',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: widget.isOnline ? Colors.green.shade800 : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.isOnline
                                ? 'GPS đang phát tín hiệu • Sẵn sàng nổ đơn'
                                : 'Gạt công tắc để bắt đầu ca nhận đơn',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    widget.isLoadingOnline
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Switch(
                            value: widget.isOnline,
                            activeTrackColor: Colors.green.shade300,
                            activeThumbColor: Colors.green,
                            onChanged: widget.onToggleOnline != null
                                ? (val) => widget.onToggleOnline!(val)
                                : null,
                          ),
                  ],
                ),
              ),
            ),

            // Thẻ Thông tin Tài xế & Ví
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B00), Color(0xFFFF9500)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 26,
                          backgroundColor: Colors.white,
                          child: Icon(Icons.delivery_dining, color: Colors.deepOrange, size: 32),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _shipperName,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                              Text(
                                _shipperPhone.isNotEmpty ? _shipperPhone : 'Đối tác giao vận SOOPI',
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(earningsTitle, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 4),
                    isLoading
                        ? const SizedBox(
                            height: 32,
                            width: 32,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            currencyFormat.format(displayEarnings),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28),
                          ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Thống kê nhanh: Cuốc hoàn thành, Đánh giá
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _showOrderHistoryDialog,
                    borderRadius: BorderRadius.circular(16),
                    child: Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            const Icon(Icons.check_circle_outline, color: Colors.green, size: 28),
                            const SizedBox(height: 8),
                            Text('$tripsCount cuốc', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            const Text('Đã hoàn thành', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _showCustomerReviewsDialog,
                    borderRadius: BorderRadius.circular(16),
                    child: Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 28),
                            const SizedBox(height: 8),
                            Text(
                              _earningsService.reviews.isNotEmpty ? '${rating.toStringAsFixed(1)} ⭐' : '-- ⭐',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            Text(
                              _earningsService.reviews.isNotEmpty
                                  ? 'Xem (${_earningsService.reviews.length}) đánh giá'
                                  : 'Chưa có đánh giá',
                              style: TextStyle(
                                fontSize: 12,
                                color: _earningsService.reviews.isNotEmpty ? Colors.deepOrange : Colors.grey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Cài đặt & Hỗ trợ
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.history, color: Colors.deepOrange),
                    title: const Text('Lịch sử cuốc xe'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showOrderHistoryDialog,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.star_outline, color: Colors.amber),
                    title: const Text('Đánh giá từ khách hàng'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showCustomerReviewsDialog,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.headset_mic_outlined, color: Colors.blue),
                    title: const Text('Hỗ trợ tài xế'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Tổng đài hỗ trợ đối tác SOOPI: 1900 6868'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Nút đăng xuất tài khoản Tài xế
            ElevatedButton.icon(
              onPressed: () async {
                try {
                  ProfileApiService().clearCache();
                  await AuthService().signOut();
                } catch (_) {}
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const AuthScreen()),
                    (route) => false,
                  );
                }
              },
              icon: const Icon(Icons.logout),
              label: const Text('Đăng xuất tài khoản'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
