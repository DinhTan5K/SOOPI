import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:signalr_netcore/signalr_client.dart';
import 'api_config.dart';

class OrderSocketService {
  static final OrderSocketService _instance = OrderSocketService._internal();
  factory OrderSocketService() => _instance;
  OrderSocketService._internal();

  HubConnection? _hubConnection;
  bool _isConnecting = false;
  String? _joinedRestaurantId;
  String? _joinedDriverId;
  double _lastDriverLat = 16.0442;
  double _lastDriverLng = 108.2213;
  String _lastDriverName = '';
  String _lastDriverPhone = '';
  final Set<String> _joinedOrderRooms = {};

  // Broadcast streams
  final _newOrderController = StreamController<Map<String, dynamic>>.broadcast();
  final _orderStatusController = StreamController<Map<String, dynamic>>.broadcast();
  final _deliveryOfferController = StreamController<Map<String, dynamic>>.broadcast();
  final _deliveryOfferExpiredController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onNewOrder => _newOrderController.stream;
  Stream<Map<String, dynamic>> get onOrderStatus => _orderStatusController.stream;
  Stream<Map<String, dynamic>> get onDeliveryOffer => _deliveryOfferController.stream;
  Stream<Map<String, dynamic>> get onDeliveryOfferExpired => _deliveryOfferExpiredController.stream;

  bool get isConnected => _hubConnection?.state == HubConnectionState.Connected;

  /// Lấy URL của Hub SignalR dựa trên ApiConfig hiện tại
  String _getHubUrl() {
    final base = ApiConfig().baseUrl.trim();
    // Bỏ /api ở cuối nếu có để kết nối tới /orderHub
    final root = base.endsWith('/api')
        ? base.substring(0, base.length - 4)
        : base.endsWith('/api/')
            ? base.substring(0, base.length - 5)
            : base;
    return '$root/orderHub';
  }

  /// Khởi tạo và kết nối tới SignalR Hub
  Future<void> connect() async {
    if (isConnected || _isConnecting) return;
    _isConnecting = true;

    try {
      final hubUrl = _getHubUrl();
      debugPrint('[OrderSocketService] Đang kết nối tới $hubUrl ...');

      _hubConnection = HubConnectionBuilder()
          .withUrl(hubUrl)
          .withAutomaticReconnect(retryDelays: [2000, 5000, 10000, 20000])
          .build();

      _hubConnection!.onreconnecting(({error}) {
        debugPrint('[OrderSocketService] Đang kết nối lại: $error');
      });

      _hubConnection!.onreconnected(({connectionId}) {
        debugPrint('[OrderSocketService] Đã kết nối lại thành công ($connectionId).');
        _rejoinRooms();
      });

      _hubConnection!.onclose(({error}) {
        debugPrint('[OrderSocketService] Mất kết nối: $error');
      });

      // 1. Lắng nghe sự kiện Đơn hàng mới (Dành cho Chủ quán)
      _hubConnection!.on('NewOrderReceived', (arguments) {
        if (arguments != null && arguments.isNotEmpty) {
          final data = arguments.first;
          if (data is Map) {
            final map = Map<String, dynamic>.from(data);
            debugPrint('[OrderSocketService] 🔔 Nhận đơn hàng mới: ${map['orderCode'] ?? map['orderId']}');
            try {
              SystemSound.play(SystemSoundType.alert);
              HapticFeedback.heavyImpact();
            } catch (_) {}
            _newOrderController.add(map);
          }
        }
      });

      // 2. Lắng nghe sự kiện Cập nhật trạng thái đơn (Khách hàng & Quán)
      _hubConnection!.on('OrderStatusUpdated', (arguments) {
        if (arguments != null && arguments.isNotEmpty) {
          final data = arguments.first;
          if (data is Map) {
            final map = Map<String, dynamic>.from(data);
            debugPrint('[OrderSocketService] ⚡ Trạng thái đơn cập nhật: ${map['newStatus']}');
            try {
              HapticFeedback.lightImpact();
            } catch (_) {}
            _orderStatusController.add(map);
          }
        }
      });

      // 3. Lắng nghe sự kiện Nổ đơn mới (Dành riêng cho Tài xế)
      _hubConnection!.on('NewDeliveryOffer', (arguments) {
        if (arguments != null && arguments.isNotEmpty) {
          final data = arguments.first;
          if (data is Map) {
            final map = Map<String, dynamic>.from(data);
            debugPrint('[OrderSocketService] 🛵 Nổ đơn mới: ${map['orderCode']} (Khoảng cách: ${map['distanceToRestaurantKm']}km)');
            try {
              SystemSound.play(SystemSoundType.alert);
              HapticFeedback.heavyImpact();
            } catch (_) {}
            _deliveryOfferController.add(map);
          }
        }
      });

      // 4. Lắng nghe sự kiện Hết hạn nhận đơn (Tài xế)
      _hubConnection!.on('DeliveryOfferExpired', (arguments) {
        if (arguments != null && arguments.isNotEmpty) {
          final data = arguments.first;
          if (data is Map) {
            final map = Map<String, dynamic>.from(data);
            _deliveryOfferExpiredController.add(map);
          }
        }
      });

      await _hubConnection!.start();
      debugPrint('[OrderSocketService] ✅ Kết nối SignalR thành công!');
      _rejoinRooms();
    } catch (e) {
      debugPrint('[OrderSocketService] ❌ Lỗi kết nối SignalR: $e');
    } finally {
      _isConnecting = false;
    }
  }

  // =========================================================================
  // PHÒNG QUÁN ĂN (RESTAURANT ROOMS)
  // =========================================================================

  Future<void> joinRestaurant(String restaurantId) async {
    _joinedRestaurantId = restaurantId;
    if (!isConnected) await connect();
    if (isConnected) {
      try {
        await _hubConnection!.invoke('JoinRestaurantRoom', args: [restaurantId]);
        debugPrint('[OrderSocketService] Đã vào phòng quán: restaurant_$restaurantId');
      } catch (e) {
        debugPrint('[OrderSocketService] Lỗi tham gia phòng quán: $e');
      }
    }
  }

  Future<void> leaveRestaurant(String restaurantId) async {
    if (_joinedRestaurantId == restaurantId) _joinedRestaurantId = null;
    if (isConnected) {
      try {
        await _hubConnection!.invoke('LeaveRestaurantRoom', args: [restaurantId]);
      } catch (_) {}
    }
  }

  // =========================================================================
  // PHÒNG TÀI XẾ (DRIVER ROOMS & LOCATION TRACKING)
  // =========================================================================

  Future<void> joinDriver(String driverId) async {
    _joinedDriverId = driverId;
    if (!isConnected) await connect();
    if (isConnected) {
      try {
        await _hubConnection!.invoke('JoinDriverRoom', args: [driverId]);
        debugPrint('[OrderSocketService] Tài xế đã vào phòng nhận đơn: driver_$driverId');
      } catch (e) {
        debugPrint('[OrderSocketService] Lỗi tham gia phòng tài xế: $e');
      }
    }
  }

  Future<void> leaveDriver(String driverId) async {
    if (_joinedDriverId == driverId) _joinedDriverId = null;
    if (isConnected) {
      try {
        await _hubConnection!.invoke('LeaveDriverRoom', args: [driverId]);
        debugPrint('[OrderSocketService] Tài xế đã rời phòng nhận đơn: driver_$driverId');
      } catch (_) {}
    }
  }

  Future<void> driverPingLocation(
    String driverId,
    double latitude,
    double longitude, {
    String name = '',
    String phone = '',
  }) async {
    _joinedDriverId = driverId;
    _lastDriverLat = latitude;
    _lastDriverLng = longitude;
    if (name.isNotEmpty) _lastDriverName = name;
    if (phone.isNotEmpty) _lastDriverPhone = phone;

    if (!isConnected) await connect();
    if (isConnected) {
      try {
        await _hubConnection!.invoke(
          'DriverPingLocation',
          args: [driverId, latitude, longitude, name, phone],
        );
      } catch (e) {
        debugPrint('[OrderSocketService] Lỗi ping tọa độ tài xế: $e');
      }
    }
  }

  Future<List<Map<String, dynamic>>> getAvailableOrdersForDriver(
    double latitude,
    double longitude,
  ) async {
    if (!isConnected) await connect();
    if (isConnected) {
      try {
        final result = await _hubConnection!.invoke(
          'GetAvailableOrdersForDriver',
          args: [latitude, longitude],
        );
        if (result is List) {
          return result
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (e) {
        debugPrint('[OrderSocketService] Lỗi lấy danh sách đơn chờ: $e');
      }
    }
    return [];
  }

  Future<bool> driverAcceptOffer(String orderId, String driverId) async {
    if (!isConnected) await connect();
    if (isConnected) {
      try {
        final result = await _hubConnection!.invoke(
          'DriverAcceptOffer',
          args: [orderId, driverId],
        );
        return result == true;
      } catch (e) {
        debugPrint('[OrderSocketService] Lỗi chấp nhận đơn: $e');
      }
    }
    return false;
  }

  Future<bool> driverUpdateOrderStatus(
    String orderId,
    String driverId,
    String status,
  ) async {
    if (!isConnected) await connect();
    if (isConnected) {
      try {
        final result = await _hubConnection!.invoke(
          'DriverUpdateOrderStatus',
          args: [orderId, driverId, status],
        );
        return result == true;
      } catch (e) {
        debugPrint('[OrderSocketService] Lỗi cập nhật trạng thái đơn: $e');
      }
    }
    return false;
  }

  Future<bool> driverRejectOffer(String orderId, String driverId) async {
    if (!isConnected) await connect();
    if (isConnected) {
      try {
        final result = await _hubConnection!.invoke(
          'DriverRejectOffer',
          args: [orderId, driverId],
        );
        return result == true;
      } catch (e) {
        debugPrint('[OrderSocketService] Lỗi từ chối đơn: $e');
      }
    }
    return false;
  }

  // =========================================================================
  // PHÒNG THEO DÕI ĐƠN HÀNG (ORDER ROOMS)
  // =========================================================================

  Future<void> joinOrder(String orderId) async {
    _joinedOrderRooms.add(orderId);
    if (!isConnected) await connect();
    if (isConnected) {
      try {
        await _hubConnection!.invoke('JoinOrderRoom', args: [orderId]);
        debugPrint('[OrderSocketService] Đã vào phòng đơn: order_$orderId');
      } catch (e) {
        debugPrint('[OrderSocketService] Lỗi tham gia phòng đơn: $e');
      }
    }
  }

  Future<void> leaveOrder(String orderId) async {
    _joinedOrderRooms.remove(orderId);
    if (isConnected) {
      try {
        await _hubConnection!.invoke('LeaveOrderRoom', args: [orderId]);
      } catch (_) {}
    }
  }

  void _rejoinRooms() {
    if (_joinedRestaurantId != null) {
      joinRestaurant(_joinedRestaurantId!);
    }
    if (_joinedDriverId != null) {
      joinDriver(_joinedDriverId!);
      driverPingLocation(
        _joinedDriverId!,
        _lastDriverLat,
        _lastDriverLng,
        name: _lastDriverName,
        phone: _lastDriverPhone,
      );
    }
    for (final orderId in _joinedOrderRooms) {
      joinOrder(orderId);
    }
  }

  Future<void> disconnect() async {
    try {
      await _hubConnection?.stop();
    } catch (_) {}
  }
}
