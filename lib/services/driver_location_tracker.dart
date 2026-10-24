import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'order_socket_service.dart';

class DriverLocationTracker {
  static final DriverLocationTracker _instance = DriverLocationTracker._internal();
  factory DriverLocationTracker() => _instance;
  DriverLocationTracker._internal();

  Timer? _pingTimer;
  bool _isTracking = false;
  Position? _lastKnownPosition;
  double _lastLat = 16.0442;
  double _lastLng = 108.2213;

  bool get isTracking => _isTracking;
  Position? get lastKnownPosition => _lastKnownPosition;
  double get currentLatitude => _lastKnownPosition?.latitude ?? _lastLat;
  double get currentLongitude => _lastKnownPosition?.longitude ?? _lastLng;

  /// Bắt đầu gửi tọa độ GPS ngầm mỗi 5 giây
  Future<bool> startTracking({
    required String driverId,
    String driverName = '',
    String driverPhone = '',
  }) async {
    _isTracking = true;

    // 1. Tham gia phòng tài xế trên SignalR ngay lập tức
    await OrderSocketService().joinDriver(driverId);

    // 2. Kiểm tra quyền định vị (không chặn nếu trình duyệt PC từ chối hoặc không có GPS)
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
      }
    } catch (e) {
      debugPrint('[DriverLocationTracker] Cảnh báo kiểm tra quyền GPS (sẽ dùng tọa độ mặc định): $e');
    }

    // 3. Ping ngay lập tức 1 lần đầu tiên
    await _pingCurrentLocation(driverId, driverName, driverPhone);

    // 4. Định kỳ mỗi 5 giây gửi GPS 1 lần
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!_isTracking) {
        timer.cancel();
        return;
      }
      await _pingCurrentLocation(driverId, driverName, driverPhone);
    });

    debugPrint('[DriverLocationTracker] Đã bật chế độ trực tuyến & gửi GPS 5s/lần cho driver $driverId.');
    return true;
  }

  /// Dừng gửi tọa độ và rời khỏi chế độ trực tuyến
  Future<void> stopTracking(String driverId) async {
    _isTracking = false;
    _pingTimer?.cancel();
    _pingTimer = null;

    await OrderSocketService().leaveDriver(driverId);
    debugPrint('[DriverLocationTracker] Đã tắt chế độ nhận đơn (Offline).');
  }

  Future<void> _pingCurrentLocation(
    String driverId,
    String driverName,
    String driverPhone,
  ) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 3),
        ),
      );
      _lastKnownPosition = pos;
      _lastLat = pos.latitude;
      _lastLng = pos.longitude;
    } catch (_) {
      // Nếu trình duyệt PC timeout hoặc tab đang ẩn, dùng tọa độ gần nhất hoặc mặc định Đà Nẵng
    }

    try {
      await OrderSocketService().driverPingLocation(
        driverId,
        _lastLat,
        _lastLng,
        name: driverName,
        phone: driverPhone,
      );
      debugPrint(
        '[DriverLocationTracker] 📍 Đã ping GPS ($driverId): ($_lastLat, $_lastLng)',
      );
    } catch (e) {
      debugPrint('[DriverLocationTracker] Lỗi gửi ping lên Hub: $e');
    }
  }
}
