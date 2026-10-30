import 'package:flutter/material.dart';
import '../auth_screen.dart';
import '../services/auth_service.dart';
import '../services/profile_api_service.dart';
import 'shipper_home_screen.dart';
import 'shipper_active_trip_screen.dart';
import 'shipper_earnings_screen.dart';

class ShipperMainScreen extends StatefulWidget {
  const ShipperMainScreen({super.key});

  @override
  State<ShipperMainScreen> createState() => _ShipperMainScreenState();
}

class _ShipperMainScreenState extends State<ShipperMainScreen> {
  int _currentTab = 0;
  Map<String, dynamic>? _activeTrip;

  void _onTripAccepted(Map<String, dynamic> offer) {
    setState(() {
      _activeTrip = offer;
      _currentTab = 1; // Tự động chuyển ngay sang tab "Chuyến đi"
    });
  }

  void _onTripFinished() {
    setState(() {
      _activeTrip = null;
      _currentTab = 0; // Quay lại bản đồ nhận đơn
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentTab == 0
              ? 'Tài xế SOOPI • Bản đồ'
              : _currentTab == 1
                  ? 'Chuyến đi hiện tại'
                  : 'Thu nhập & Tài khoản',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Đăng xuất tài khoản',
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () async {
              ProfileApiService().clearCache();
              await AuthService().signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          ShipperHomeScreen(onTripAccepted: _onTripAccepted),
          ShipperActiveTripScreen(
            initialTrip: _activeTrip,
            onTripFinished: _onTripFinished,
          ),
          const ShipperEarningsScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (index) => setState(() => _currentTab = index),
        selectedItemColor: Colors.deepOrange,
        unselectedItemColor: Colors.grey,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Bản đồ',
          ),
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: _activeTrip != null,
              child: const Icon(Icons.delivery_dining_outlined),
            ),
            activeIcon: Badge(
              isLabelVisible: _activeTrip != null,
              child: const Icon(Icons.delivery_dining),
            ),
            label: 'Chuyến đi',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet),
            label: 'Thu nhập',
          ),
        ],
      ),
    );
  }
}
