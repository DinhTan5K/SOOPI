import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/admin_api_service.dart';

class AdminDashboardTab extends StatefulWidget {
  const AdminDashboardTab({
    super.key,
    required this.api,
    required this.onNavigateToRestaurants,
  });

  final AdminApiService api;
  final VoidCallback onNavigateToRestaurants;

  @override
  State<AdminDashboardTab> createState() => _AdminDashboardTabState();
}

class _AdminDashboardTabState extends State<AdminDashboardTab> {
  final _currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _stats;
  List<dynamic> _pendingRestaurants = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final stats = await widget.api.getDashboardStats();
      final restaurantsRes = await widget.api.getRestaurants(status: 'Pending', pageSize: 5);
      final pendingList = restaurantsRes['items'] as List<dynamic>? ?? [];

      if (!mounted) return;
      setState(() {
        _stats = stats;
        _pendingRestaurants = pendingList;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.deepOrange),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                'Lỗi tải thống kê: $_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black87),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                ),
              )
            ],
          ),
        ),
      );
    }

    final users = _stats?['users'] as Map<String, dynamic>? ?? {};
    final restaurants = _stats?['restaurants'] as Map<String, dynamic>? ?? {};
    final orders = _stats?['orders'] as Map<String, dynamic>? ?? {};
    final revenue = _stats?['revenue'] as Map<String, dynamic>? ?? {};

    final totalRev = (revenue['total'] as num?)?.toDouble() ?? 0.0;
    final todayRev = (revenue['today'] as num?)?.toDouble() ?? 0.0;
    final pendingR = (restaurants['pending'] as num?)?.toInt() ?? 0;

    return RefreshIndicator(
      onRefresh: _loadData,
      color: Colors.deepOrange,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Banner Chào mừng
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.admin_panel_settings,
                    color: Colors.deepOrange,
                    size: 36,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Trung tâm Quản trị SOOPI FOOD',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Theo dõi và kiểm duyệt hoạt động hệ thống real-time',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Cảnh báo nếu có quán chờ duyệt
          if (pendingR > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                border: Border.all(color: const Color(0xFFFDE68A)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Có $pendingR quán ăn đang chờ bạn duyệt!',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF92400E),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Hãy kiểm tra menu và thông tin quán để mở bán.',
                          style: TextStyle(color: Color(0xFFB45309), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onNavigateToRestaurants,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB45309),
                      backgroundColor: const Color(0xFFFEF3C7),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Xem ngay'),
                  ),
                ],
              ),
            ),

          // Grid KPIs
          const Text(
            'Chỉ số tài chính & Đơn hàng',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: 'Doanh thu hoàn tất',
                  value: _currencyFormat.format(totalRev),
                  subtitle: 'Hôm nay: ${_currencyFormat.format(todayRev)}',
                  icon: Icons.payments_outlined,
                  color: const Color(0xFF10B981),
                  bgColor: const Color(0xFFECFDF5),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  title: 'Tổng đơn hàng',
                  value: '${orders['total'] ?? 0}',
                  subtitle: 'Hôm nay: ${orders['todayOrders'] ?? 0} đơn',
                  icon: Icons.shopping_bag_outlined,
                  color: const Color(0xFF3B82F6),
                  bgColor: const Color(0xFFEFF6FF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: 'Đang vận chuyển',
                  value: '${orders['delivering'] ?? 0}',
                  subtitle: 'Chờ xử lý: ${orders['pending'] ?? 0}',
                  icon: Icons.delivery_dining_outlined,
                  color: const Color(0xFFF59E0B),
                  bgColor: const Color(0xFFFFFBEB),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  title: 'Đã hoàn tất',
                  value: '${orders['completed'] ?? 0}',
                  subtitle: 'Đã hủy: ${orders['cancelled'] ?? 0}',
                  icon: Icons.task_alt_outlined,
                  color: const Color(0xFF8B5CF6),
                  bgColor: const Color(0xFFF5F3FF),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          const Text(
            'Hệ sinh thái SOOPI FOOD',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 12),

          // Thống kê Quán & Users
          Row(
            children: [
              Expanded(
                child: _buildStatusCard(
                  title: 'Quán ăn',
                  total: '${restaurants['total'] ?? 0}',
                  icon: Icons.storefront_outlined,
                  color: Colors.deepOrange,
                  items: [
                    'Chờ duyệt: ${restaurants['pending'] ?? 0}',
                    'Đã duyệt: ${restaurants['approved'] ?? 0}',
                    'Đã khóa: ${restaurants['locked'] ?? 0}',
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatusCard(
                  title: 'Tài khoản',
                  total: '${users['total'] ?? 0}',
                  icon: Icons.people_outline,
                  color: Colors.indigo,
                  items: [
                    'Khách hàng: ${users['customers'] ?? 0}',
                    'Chủ quán: ${users['owners'] ?? 0}',
                    'Shipper: ${users['shippers'] ?? 0}',
                    'Bị khóa: ${users['locked'] ?? 0}',
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Danh sách quán chờ duyệt gần nhất
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Quán ăn chờ duyệt gần đây',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              TextButton(
                onPressed: widget.onNavigateToRestaurants,
                child: const Text('Xem tất cả'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_pendingRestaurants.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Center(
                child: Text(
                  'Không có quán nào đang chờ duyệt 🎉',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            )
          else
            ..._pendingRestaurants.map((r) => _buildPendingRestaurantItem(r)),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard({
    required String title,
    required String total,
    required IconData icon,
    required Color color,
    required List<String> items,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              Text(total, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
            ],
          ),
          const Divider(height: 20),
          ...items.map(
            (it) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                it,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingRestaurantItem(dynamic r) {
    final name = r['name'] ?? 'Chưa đặt tên';
    final address = r['address'] ?? '';
    final phone = r['phone'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.storefront, color: Colors.deepOrange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  address,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'SĐT: $phone',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: widget.onNavigateToRestaurants,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Duyệt'),
          ),
        ],
      ),
    );
  }
}
