import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/admin_api_service.dart';
import 'admin_dashboard_tab.dart';
import 'admin_restaurants_tab.dart';
import 'admin_users_tab.dart';
import 'admin_orders_tab.dart';
import 'admin_vouchers_tab.dart';
import 'admin_audits_tab.dart';

class AdminMainScreen extends StatefulWidget {
  const AdminMainScreen({super.key});

  @override
  State<AdminMainScreen> createState() => _AdminMainScreenState();
}

class _AdminMainScreenState extends State<AdminMainScreen> {
  final _api = AdminApiService();
  int _currentIndex = 0;

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất'),
        content: const Text('Bạn có chắc chắn muốn đăng xuất khỏi cổng Quản trị?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  void _switchToUserMode() {
    Navigator.pushNamed(context, '/home');
  }

  void _switchToMerchantMode() {
    Navigator.pushNamed(context, '/merchant');
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    final tabs = [
      AdminDashboardTab(api: _api, onNavigateToRestaurants: () => _onTabTapped(1)),
      AdminRestaurantsTab(api: _api),
      AdminUsersTab(api: _api),
      AdminOrdersTab(api: _api),
      AdminVouchersTab(api: _api),
      AdminAuditsTab(api: _api),
    ];

    final titles = [
      'Tổng quan hệ thống',
      'Quản lý Nhà hàng',
      'Quản lý Người dùng',
      'Quản lý Đơn hàng',
      'Voucher toàn sàn',
      'Nhật ký kiểm duyệt',
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.deepOrange,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'ADMIN',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              titles[_currentIndex],
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.swap_horiz, color: Colors.white),
            tooltip: 'Chuyển chế độ xem',
            onSelected: (val) {
              if (val == 'home') _switchToUserMode();
              if (val == 'merchant') _switchToMerchantMode();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'home',
                child: Row(
                  children: [
                    Icon(Icons.shopping_bag_outlined, color: Colors.deepOrange, size: 20),
                    SizedBox(width: 8),
                    Text('Chuyển sang Khách hàng'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'merchant',
                child: Row(
                  children: [
                    Icon(Icons.storefront_outlined, color: Colors.deepOrange, size: 20),
                    SizedBox(width: 8),
                    Text('Chuyển sang Chủ quán'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70),
            tooltip: 'Đăng xuất',
            onPressed: _logout,
          ),
        ],
      ),
      body: isDesktop
          ? Row(
              children: [
                NavigationRail(
                  backgroundColor: const Color(0xFF1E293B),
                  selectedIndex: _currentIndex,
                  onDestinationSelected: _onTabTapped,
                  labelType: NavigationRailLabelType.all,
                  selectedLabelTextStyle: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 12),
                  unselectedLabelTextStyle: const TextStyle(color: Colors.white60, fontSize: 11),
                  selectedIconTheme: const IconThemeData(color: Colors.deepOrange),
                  unselectedIconTheme: const IconThemeData(color: Colors.white60),
                  destinations: const [
                    NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: Text('Tổng quan')),
                    NavigationRailDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: Text('Nhà hàng')),
                    NavigationRailDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: Text('Người dùng')),
                    NavigationRailDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: Text('Đơn hàng')),
                    NavigationRailDestination(icon: Icon(Icons.confirmation_number_outlined), selectedIcon: Icon(Icons.confirmation_number), label: Text('Vouchers')),
                    NavigationRailDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history), label: Text('Nhật ký')),
                  ],
                ),
                const VerticalDivider(width: 1, thickness: 1, color: Color(0xFF334155)),
                Expanded(child: tabs[_currentIndex]),
              ],
            )
          : tabs[_currentIndex],
      bottomNavigationBar: isDesktop
          ? null
          : BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: _onTabTapped,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: Colors.deepOrange,
              unselectedItemColor: Colors.grey.shade600,
              selectedFontSize: 11,
              unselectedFontSize: 10,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Tổng quan'),
                BottomNavigationBarItem(icon: Icon(Icons.storefront_outlined), activeIcon: Icon(Icons.storefront), label: 'Nhà hàng'),
                BottomNavigationBarItem(icon: Icon(Icons.people_outline), activeIcon: Icon(Icons.people), label: 'Tài khoản'),
                BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), activeIcon: Icon(Icons.receipt_long), label: 'Đơn hàng'),
                BottomNavigationBarItem(icon: Icon(Icons.confirmation_number_outlined), activeIcon: Icon(Icons.confirmation_number), label: 'Vouchers'),
                BottomNavigationBarItem(icon: Icon(Icons.history_outlined), activeIcon: Icon(Icons.history), label: 'Nhật ký'),
              ],
            ),
    );
  }
}
