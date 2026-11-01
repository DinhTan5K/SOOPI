import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../auth_screen.dart';
import '../services/auth_service.dart';
import '../services/driver_location_tracker.dart';
import '../services/profile_api_service.dart';
import '../services/shipper_earnings_service.dart';
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
  bool _isOnline = false;
  bool _isOnlineLoading = false;
  String _driverId = '';
  String _driverName = 'Tài xế SOOPI';
  String _driverPhone = '';

  @override
  void initState() {
    super.initState();
    _initOnlineState();
  }

  Future<void> _initOnlineState() async {
    final cached = ProfileApiService().cachedProfile;
    if (cached != null && cached.id.isNotEmpty) {
      _driverId = cached.id;
      _driverName = cached.fullName.isNotEmpty ? cached.fullName : 'Tài xế SOOPI';
      _driverPhone = cached.phoneNumber;
    }
    final authUser = FirebaseAuth.instance.currentUser;
    if (_driverId.isEmpty && authUser != null) {
      _driverId = authUser.uid;
      _driverName = authUser.displayName ?? authUser.email ?? 'Tài xế SOOPI';
      _driverPhone = authUser.phoneNumber ?? '';
    }

    try {
      final profile = await ProfileApiService().getProfile();
      if (profile.id.isNotEmpty) {
        _driverId = profile.id;
        _driverName = profile.fullName.isNotEmpty ? profile.fullName : 'Tài xế SOOPI';
        _driverPhone = profile.phoneNumber;
      }
    } catch (_) {}

    // Tự động bật online khi tài xế mở app
    await _toggleOnline(true, silent: true);
  }

  Future<void> _toggleOnline(bool value, {bool silent = false}) async {
    if (_driverId.isEmpty) {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser != null) _driverId = authUser.uid;
    }
    if (_driverId.isEmpty) return;

    setState(() => _isOnlineLoading = true);

    if (value) {
      final ok = await DriverLocationTracker().startTracking(
        driverId: _driverId,
        driverName: _driverName,
        driverPhone: _driverPhone,
      );
      if (ok && mounted) {
        setState(() => _isOnline = true);
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
              content: Text('Đã bật nhận đơn! Tọa độ GPS đang cập nhật.'),
            ),
          );
        }
      }
    } else {
      await DriverLocationTracker().stopTracking(_driverId);
      if (mounted) {
        setState(() => _isOnline = false);
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.grey,
              duration: Duration(seconds: 2),
              content: Text('Đã tắt nhận đơn (Nghỉ ngơi).'),
            ),
          );
        }
      }
    }

    if (mounted) {
      setState(() => _isOnlineLoading = false);
    }
  }

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
    ShipperEarningsService().init();
  }

  void _navigateToActiveTrip() {
    setState(() {
      _currentTab = 1;
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
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          ShipperHomeScreen(
            onTripAccepted: _onTripAccepted,
            hasActiveTrip: _activeTrip != null,
            activeTrip: _activeTrip,
            activeTripCode: _activeTrip?['orderCode']?.toString() ?? _activeTrip?['orderId']?.toString() ?? '',
            onNavigateToActiveTrip: _navigateToActiveTrip,
            isOnline: _isOnline,
            onToggleOnline: _toggleOnline,
          ),
          ShipperActiveTripScreen(
            initialTrip: _activeTrip,
            onTripFinished: _onTripFinished,
          ),
          ShipperEarningsScreen(
            isOnline: _isOnline,
            isLoadingOnline: _isOnlineLoading,
            onToggleOnline: _toggleOnline,
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (index) {
          setState(() => _currentTab = index);
          if (index == 2) {
            ShipperEarningsService().init();
          }
        },
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
