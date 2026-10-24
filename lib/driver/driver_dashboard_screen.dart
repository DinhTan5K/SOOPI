import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/driver_location_tracker.dart';
import '../services/order_socket_service.dart';
import '../services/profile_api_service.dart';
import 'driver_offer_dialog.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  final _tracker = DriverLocationTracker();
  final _socketService = OrderSocketService();

  bool _isOnline = false;
  bool _isLoading = false;
  String _driverId = '';
  String _driverName = 'Tài xế SOOPI';
  String _driverPhone = '';
  Position? _currentPosition;
  Timer? _uiRefreshTimer;
  StreamSubscription? _offerSubscription;

  @override
  void initState() {
    super.initState();
    _loadDriverInfo();

    // Lắng nghe sự kiện nổ đơn từ SignalR
    _offerSubscription = _socketService.onDeliveryOffer.listen((offer) {
      if (!mounted || !_isOnline) return;
      _showIncomingOfferDialog(offer);
    });

    // Cập nhật tọa độ hiển thị trên UI mỗi 2 giây
    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && _tracker.isTracking) {
        setState(() {
          _currentPosition = _tracker.lastKnownPosition;
        });
      }
    });
  }

  @override
  void dispose() {
    _offerSubscription?.cancel();
    _uiRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDriverInfo() async {
    try {
      final profile = await ProfileApiService().getProfile();
      if (profile.id.isNotEmpty) {
        setState(() {
          _driverId = profile.id;
          _driverName = profile.fullName.isNotEmpty ? profile.fullName : 'Tài xế SOOPI';
          _driverPhone = profile.phoneNumber;
        });
      } else {
        // Fallback test ID nếu chưa đăng nhập backend
        setState(() {
          _driverId = '11111111-1111-1111-1111-111111111111';
        });
      }
    } catch (_) {
      setState(() {
        _driverId = '11111111-1111-1111-1111-111111111111';
      });
    }
  }

  Future<void> _toggleOnlineStatus(bool value) async {
    if (_driverId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa xác định được tài khoản tài xế')),
      );
      return;
    }

    setState(() => _isLoading = true);

    if (value) {
      // Bật trực tuyến
      final success = await _tracker.startTracking(
        driverId: _driverId,
        driverName: _driverName,
        driverPhone: _driverPhone,
      );

      if (success) {
        setState(() {
          _isOnline = true;
          _currentPosition = _tracker.lastKnownPosition;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.green,
              content: Text('Đã bật chế độ Sẵn sàng nhận đơn!'),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.red,
              content: Text('Vui lòng cấp quyền định vị GPS để nhận đơn'),
            ),
          );
        }
      }
    } else {
      // Tắt trực tuyến
      await _tracker.stopTracking(_driverId);
      setState(() {
        _isOnline = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.grey,
            content: Text('Đã tắt nhận đơn (Nghỉ ngơi).'),
          ),
        );
      }
    }

    setState(() => _isLoading = false);
  }

  void _showIncomingOfferDialog(Map<String, dynamic> offer) async {
    final accepted = await DriverOfferDialog.show(
      context,
      offer: offer,
      driverId: _driverId,
    );

    if (accepted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade800,
          content: Text(
            '🎉 Nhận đơn #${offer['orderCode']} thành công! Hãy di chuyển đến quán để lấy món.',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text(
          'Tài xế SOOPI',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _isOnline ? Colors.green.shade50 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isOnline ? Colors.green : Colors.grey.shade400,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 4,
                  backgroundColor: _isOnline ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 6),
                Text(
                  _isOnline ? 'Trực tuyến' : 'Nghỉ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _isOnline ? Colors.green.shade800 : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thẻ trạng thái Nhận đơn chính
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isOnline ? 'Đang sẵn sàng nhận đơn' : 'Đang tạm dừng nhận đơn',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _isOnline ? Colors.green.shade800 : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isOnline
                                  ? 'GPS đang ping mỗi 5 giây...'
                                  : 'Gạt công tắc để bắt đầu tìm cuốc',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Switch(
                                value: _isOnline,
                                activeTrackColor: Colors.deepOrange.shade300,
                                activeThumbColor: Colors.deepOrange,
                                onChanged: _toggleOnlineStatus,
                              ),
                      ],
                    ),
                    if (_isOnline) ...[
                      const Divider(height: 24),
                      Row(
                        children: [
                          const Icon(Icons.gps_fixed, color: Colors.green, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _currentPosition != null
                                  ? 'Vị trí: ${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)}'
                                  : 'Đang định vị GPS...',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Thông tin tài xế
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Thông tin tài xế',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: Colors.deepOrange.shade100,
                        child: const Icon(Icons.person, color: Colors.deepOrange),
                      ),
                      title: Text(
                        _driverName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(_driverPhone.isNotEmpty ? _driverPhone : 'Chưa cập nhật SĐT'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Hướng dẫn hoạt động
            Card(
              elevation: 0.5,
              color: Colors.amber.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.amber.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: Colors.amber, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Quy tắc nhận đơn tự động:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '• Khi có khách đặt quanh bán kính 1km - 5km, màn hình sẽ nổ chuông và hiển thị thông báo.\n'
                            '• Bạn có 15 giây để bấm "Nhận đơn".\n'
                            '• Tọa độ GPS của bạn được đồng bộ tự động mỗi 5 giây.',
                            style: TextStyle(fontSize: 12, height: 1.4, color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
