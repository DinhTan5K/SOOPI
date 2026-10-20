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
  final Set<String> _joinedOrderRooms = {};

  // Broadcast streams
  final _newOrderController = StreamController<Map<String, dynamic>>.broadcast();
  final _orderStatusController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onNewOrder => _newOrderController.stream;
  Stream<Map<String, dynamic>> get onOrderStatus => _orderStatusController.stream;

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

      // Lắng nghe sự kiện Đơn hàng mới (Dành cho Chủ quán)
      _hubConnection!.on('NewOrderReceived', (arguments) {
        if (arguments != null && arguments.isNotEmpty) {
          final data = arguments.first;
          if (data is Map) {
            final map = Map<String, dynamic>.from(data);
            debugPrint('[OrderSocketService] 🔔 Nhận đơn hàng mới: ${map['orderCode'] ?? map['orderId']}');
            // Báo rung và chuông âm thanh hệ thống
            try {
              SystemSound.play(SystemSoundType.alert);
              HapticFeedback.heavyImpact();
            } catch (_) {}
            _newOrderController.add(map);
          }
        }
      });

      // Lắng nghe sự kiện Cập nhật trạng thái đơn (Dành cho Khách hàng & Quán)
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

      await _hubConnection!.start();
      debugPrint('[OrderSocketService] ✅ Kết nối SignalR thành công!');
      _rejoinRooms();
    } catch (e) {
      debugPrint('[OrderSocketService] ❌ Lỗi kết nối SignalR: $e');
    } finally {
      _isConnecting = false;
    }
  }

  /// Tham gia phòng của Quán ăn để nhận đơn
  Future<void> joinRestaurant(String restaurantId) async {
    _joinedRestaurantId = restaurantId;
    if (!isConnected) {
      await connect();
    }
    if (isConnected) {
      try {
        await _hubConnection!.invoke('JoinRestaurantRoom', args: [restaurantId]);
        debugPrint('[OrderSocketService] Đã vào phòng quán: restaurant_$restaurantId');
      } catch (e) {
        debugPrint('[OrderSocketService] Lỗi tham gia phòng quán: $e');
      }
    }
  }

  /// Rời phòng quán
  Future<void> leaveRestaurant(String restaurantId) async {
    if (_joinedRestaurantId == restaurantId) _joinedRestaurantId = null;
    if (isConnected) {
      try {
        await _hubConnection!.invoke('LeaveRestaurantRoom', args: [restaurantId]);
      } catch (_) {}
    }
  }

  /// Tham gia phòng theo dõi 1 Đơn hàng cụ thể (Khách hàng)
  Future<void> joinOrder(String orderId) async {
    _joinedOrderRooms.add(orderId);
    if (!isConnected) {
      await connect();
    }
    if (isConnected) {
      try {
        await _hubConnection!.invoke('JoinOrderRoom', args: [orderId]);
        debugPrint('[OrderSocketService] Đã vào phòng đơn: order_$orderId');
      } catch (e) {
        debugPrint('[OrderSocketService] Lỗi tham gia phòng đơn: $e');
      }
    }
  }

  /// Rời phòng đơn hàng
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
