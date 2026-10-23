import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'order_data.dart';
import '../services/order_socket_service.dart';
import 'order_review_screen.dart';
import 'shipper_chat_screen.dart';
import '../services/geocoding_service.dart';
import '../services/profile_api_service.dart';

class OrderTrackingScreen extends StatefulWidget {
  final String orderId;

  const OrderTrackingScreen({super.key, required this.orderId});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen>
    with SingleTickerProviderStateMixin {
  final OrderData _orderData = OrderData();
  final MapController _mapController = MapController();

  late AnimationController _animController;
  late Animation<double> _shipperProgress;
  StreamSubscription? _socketStatusSub;

  LatLng? _savedUserPos;
  String? _savedUserAddress;

  @override
  void initState() {
    super.initState();
    _loadSavedUserLocation();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _shipperProgress = Tween<double>(begin: 0.15, end: 0.85).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _orderData.syncTrack(widget.orderId);

    // Lắng nghe cập nhật đơn hàng thời gian thực qua SignalR
    final initialOrder = _orderData.findById(widget.orderId);
    final trackRoomId = initialOrder?.backendId ?? widget.orderId;
    OrderSocketService().joinOrder(trackRoomId);
    if (trackRoomId != widget.orderId) {
      OrderSocketService().joinOrder(widget.orderId);
    }
    _socketStatusSub = OrderSocketService().onOrderStatus.listen((data) {
      if (!mounted) return;
      final incomingId = (data['orderId'] ?? data['OrderId'])?.toString().toLowerCase();
      final order = _orderData.findById(widget.orderId);
      final myId = widget.orderId.toLowerCase();
      final myBackendId = order?.backendId?.toLowerCase();
      if (incomingId == null || incomingId == myId || (myBackendId != null && incomingId == myBackendId)) {
        final newStatusStr = (data['newStatus'] ?? data['status'] ?? data['Status'])?.toString().toLowerCase();
        if (order != null && newStatusStr != null) {
          if (newStatusStr == 'delivered' || newStatusStr == 'completed') {
            order.status = OrderStatus.completed;
            order.estimatedDeliveryMinutes = 0;
          } else if (newStatusStr == 'delivering' || newStatusStr == 'pickedup') {
            order.status = OrderStatus.delivering;
            order.estimatedDeliveryMinutes = 15;
          } else if (newStatusStr == 'preparing' || newStatusStr == 'readyforpickup') {
            order.status = OrderStatus.preparing;
            order.estimatedDeliveryMinutes = 20;
          } else if (newStatusStr == 'cancelled') {
            order.status = OrderStatus.cancelled;
          }
          setState(() {});
        }
        _orderData.syncTrack(widget.orderId);
      }
    });
  }

  Future<void> _loadSavedUserLocation() async {
    try {
      final order = _orderData.findById(widget.orderId);

      // 1. Nếu đơn hàng đã lưu sẵn tọa độ người dùng cụ thể
      if (order != null && order.userLat != null && order.userLng != null && order.userLat != 0) {
        if (mounted) {
          setState(() {
            _savedUserPos = LatLng(order.userLat!, order.userLng!);
            _savedUserAddress = order.deliveryAddress;
          });
          _recenterMap();
        }
        return;
      }

      // 2. Nếu đơn hàng có chuỗi địa chỉ giao hàng cụ thể, geocode ngay thành tọa độ
      if (order != null &&
          order.deliveryAddress.trim().isNotEmpty &&
          !order.deliveryAddress.startsWith('Địa chỉ')) {
        final query = order.deliveryAddress.trim();
        _savedUserAddress = query;
        final coords = await GeocodingService.getCoordinatesFromAddress(query);
        if (coords != null && mounted) {
          setState(() {
            _savedUserPos = coords;
          });
          _recenterMap();
          return;
        }
      }

      // 3. Đọc địa chỉ đã lưu trong SharedPreferences (quét tất cả các key soopi.delivery_address)
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
      String? raw = prefs.getString('soopi.delivery_address.$uid');

      if (raw == null) {
        for (final key in prefs.getKeys()) {
          if (key.startsWith('soopi.delivery_address.')) {
            final val = prefs.getString(key);
            if (val != null && val.isNotEmpty) {
              raw = val;
              break;
            }
          }
        }
      }

      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final lat = (map['latitude'] as num?)?.toDouble();
        final lng = (map['longitude'] as num?)?.toDouble();
        final addr = map['address']?.toString();

        if (lat != null && lng != null && lat != 0 && lng != 0 && mounted) {
          setState(() {
            _savedUserPos = LatLng(lat, lng);
            _savedUserAddress = addr;
          });
          _recenterMap();
          return;
        } else if (addr != null && addr.isNotEmpty) {
          final coords = await GeocodingService.getCoordinatesFromAddress(addr);
          if (coords != null && mounted) {
            setState(() {
              _savedUserPos = coords;
              _savedUserAddress = addr;
            });
            _recenterMap();
            return;
          }
        }
      }

      // 4. Kiểm tra địa chỉ mặc định từ hồ sơ tài khoản (Backend database)
      try {
        final profileAddresses = await ProfileApiService().getAddresses();
        if (profileAddresses.isNotEmpty) {
          final def = profileAddresses.firstWhere((a) => a.isDefault, orElse: () => profileAddresses.first);
          if (def.fullAddress.trim().isNotEmpty) {
            final coords = await GeocodingService.getCoordinatesFromAddress(def.fullAddress.trim());
            if (coords != null && mounted) {
              setState(() {
                _savedUserPos = coords;
                _savedUserAddress = def.fullAddress;
              });
              _recenterMap();
              return;
            }
          }
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('Error loading saved delivery address: $e');
    }
  }

  void _recenterMap() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _savedUserPos != null) {
        final order = _orderData.findById(widget.orderId);
        if (order != null) {
          final uPos = _savedUserPos!;
          final rPos = _getRestaurantCoordinates(order, uPos);
          final cPos = LatLng(
            (rPos.latitude + uPos.latitude) / 2,
            (rPos.longitude + uPos.longitude) / 2,
          );
          try {
            _mapController.move(cPos, 14.5);
          } catch (_) {}
        }
      }
    });
  }

  @override
  void dispose() {
    _socketStatusSub?.cancel();
    OrderSocketService().leaveOrder(widget.orderId);
    _animController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _callShipper(String phone) async {
    final rawPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$rawPhone');
    try {
      final launched = await launchUrl(uri);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📞 Không thể mở cuộc gọi cho số $rawPhone'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi gọi điện: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  void _messageShipper(OrderModel order, ShipperInfo shipper) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShipperChatScreen(order: order, shipper: shipper),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _orderData,
      builder: (context, _) {
        final order = _orderData.findById(widget.orderId);
        if (order == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Theo dõi đơn hàng')),
            body: const Center(child: Text('Không tìm thấy thông tin đơn hàng')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Theo dõi đơn hàng',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Mã đơn: #${order.id}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRealMap(order),

                const SizedBox(height: 16),

                if (order.shipper != null) ...[
                  _buildShipperCard(order, order.shipper!),
                  const SizedBox(height: 16),
                ],

                _buildStepper(order.status),

                const SizedBox(height: 16),

                if (order.status == OrderStatus.completed) ...[
                  _buildReviewPrompt(order),
                  const SizedBox(height: 16),
                ],

                _buildOrderDetailsCard(order),

                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  LatLng _getUserCoordinates(OrderModel order) {
    if (order.userLat != null && order.userLng != null && order.userLat != 0) {
      return LatLng(order.userLat!, order.userLng!);
    }
    if (_savedUserPos != null) {
      return _savedUserPos!;
    }
    return const LatLng(10.77689, 106.70089);
  }

  LatLng _getRestaurantCoordinates(OrderModel order, LatLng userPos) {
    if (order.restaurantLat != null && order.restaurantLng != null && order.restaurantLat != 0) {
      return LatLng(order.restaurantLat!, order.restaurantLng!);
    }

    // Nếu điểm nhận hàng của người dùng ở ngoài TP.HCM (> 50 km, ví dụ: Bàu Tràm 2 - Đà Nẵng, Hà Nội...)
    // Tự động đặt quán mẫu gần vị trí đã lưu của user (~1.5 km) để tạo lộ trình giao hàng hợp lý trong cùng khu vực
    final isFarFromHcm = (userPos.latitude - 10.78).abs() > 0.5 || (userPos.longitude - 106.69).abs() > 0.5;
    if (isFarFromHcm) {
      return LatLng(userPos.latitude + 0.010, userPos.longitude + 0.008);
    }

    final name = order.restaurantName.toLowerCase();
    if (name.contains('burger')) return const LatLng(10.76985, 106.69650);
    if (name.contains('pizza')) return const LatLng(10.78342, 106.69532);
    if (name.contains('sushi')) return const LatLng(10.77258, 106.69345);
    if (name.contains('phúc long') || name.contains('phuclong')) return const LatLng(10.77312, 106.70425);
    if (name.contains('cơm') || name.contains('ba ghiền')) return const LatLng(10.79150, 106.67420);
    if (name.contains('poke') || name.contains('healthy')) return const LatLng(10.77740, 106.70010);
    return const LatLng(10.78342, 106.69532);
  }

  List<LatLng> _getRoutePoints(LatLng start, LatLng end) {
    final midLat = (start.latitude + end.latitude) / 2;
    final midLng = (start.longitude + end.longitude) / 2;
    final corner1 = LatLng(start.latitude, midLng);
    final corner2 = LatLng(midLat, end.longitude);
    return [start, corner1, corner2, end];
  }

  LatLng _getInterpolatedShipperPos(List<LatLng> route, double progress) {
    if (route.isEmpty) return const LatLng(10.78342, 106.69532);
    if (route.length == 1) return route.first;
    final totalSegments = route.length - 1;
    final segIndex = (progress * totalSegments).floor().clamp(0, totalSegments - 1);
    final segProgress = (progress * totalSegments) - segIndex;
    final p1 = route[segIndex];
    final p2 = route[segIndex + 1];
    return LatLng(
      p1.latitude + (p2.latitude - p1.latitude) * segProgress,
      p1.longitude + (p2.longitude - p1.longitude) * segProgress,
    );
  }

  Widget _buildMapControlBtn({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 3,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: 18, color: Colors.black87),
        ),
      ),
    );
  }

  Widget _buildRealMap(OrderModel order) {
    final userPos = _getUserCoordinates(order);
    final restaurantPos = _getRestaurantCoordinates(order, userPos);
    final routePoints = _getRoutePoints(restaurantPos, userPos);

    final centerLat = (restaurantPos.latitude + userPos.latitude) / 2;
    final centerLng = (restaurantPos.longitude + userPos.longitude) / 2;
    final centerPos = LatLng(centerLat, centerLng);

    return Container(
      height: 250,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _shipperProgress,
            builder: (context, _) {
              final progress = order.status == OrderStatus.delivering
                  ? _shipperProgress.value
                  : (order.status == OrderStatus.completed ? 1.0 : 0.0);
              final shipperPos = _getInterpolatedShipperPos(routePoints, progress);

              return FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: centerPos,
                  initialZoom: 14.5,
                  minZoom: 10,
                  maxZoom: 18,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.soopi',
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: routePoints,
                        color: Colors.orange.shade700,
                        strokeWidth: 4.5,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      // Điểm lấy món (Nhà hàng)
                      Marker(
                        point: restaurantPos,
                        width: 140,
                        height: 75,
                        alignment: Alignment.topCenter,
                        child: _buildLocationPin(
                          icon: Icons.storefront_rounded,
                          label: order.restaurantName,
                          color: Colors.deepOrange,
                          sublabel: 'Điểm lấy món',
                        ),
                      ),
                      // Điểm nhận hàng (Khách hàng)
                      Marker(
                        point: userPos,
                        width: 150,
                        height: 75,
                        alignment: Alignment.topCenter,
                        child: _buildLocationPin(
                          icon: Icons.location_on_rounded,
                          label: 'Vị trí của bạn',
                          color: Colors.green.shade700,
                          sublabel: _savedUserAddress != null && _savedUserAddress!.isNotEmpty
                              ? _savedUserAddress!
                              : (order.deliveryAddress.isNotEmpty && order.deliveryAddress != 'Địa chỉ nhận hàng của bạn'
                                  ? order.deliveryAddress
                                  : 'Điểm nhận hàng'),
                        ),
                      ),
                      // Xe Shipper di chuyển
                      Marker(
                        point: shipperPos,
                        width: 90,
                        height: 70,
                        alignment: Alignment.center,
                        child: _buildShipperBadge(
                          isWaiting: order.status == OrderStatus.preparing,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          // Badge trạng thái góc trên bên phải
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.two_wheeler, color: Colors.orange, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    order.status == OrderStatus.completed
                        ? 'Đã giao tới nơi'
                        : order.status == OrderStatus.delivering
                            ? 'Dự kiến ~10-15 phút'
                            : 'Đang làm món ~20 phút',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Nút điều khiển Map (Recenter, Zoom +, Zoom -) góc dưới bên phải
          Positioned(
            right: 12,
            bottom: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMapControlBtn(
                  icon: Icons.my_location,
                  onTap: () => _mapController.move(centerPos, 14.5),
                ),
                const SizedBox(height: 6),
                _buildMapControlBtn(
                  icon: Icons.add,
                  onTap: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  ),
                ),
                const SizedBox(height: 6),
                _buildMapControlBtn(
                  icon: Icons.remove,
                  onTap: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationPin({
    required IconData icon,
    required String label,
    required Color color,
    required String sublabel,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 4,
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(sublabel, style: const TextStyle(fontSize: 9, color: Colors.grey)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(child: Icon(icon, color: Colors.white, size: 18)),
        ),
      ],
    );
  }

  Widget _buildShipperBadge({bool isWaiting = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.orange.shade700,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            isWaiting ? 'Chờ lấy món' : 'Đang giao hàng',
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.orange,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withValues(alpha: 0.4),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.delivery_dining, color: Colors.white, size: 28),
          ),
        ),
      ],
    );
  }

  Widget _buildShipperCard(OrderModel order, ShipperInfo shipper) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundImage: NetworkImage(shipper.avatarUrl),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      shipper.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.star, color: Colors.amber, size: 16),
                    Text(
                      '${shipper.rating}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${shipper.bikeType} • ${shipper.bikePlate}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Gọi điện',
            onPressed: () => _callShipper(shipper.phone),
            icon: const Icon(Icons.phone, color: Colors.green),
            style: IconButton.styleFrom(backgroundColor: Colors.green.shade50),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            tooltip: 'Nhắn tin',
            onPressed: () => _messageShipper(order, shipper),
            icon: const Icon(Icons.chat_bubble_outline, color: Colors.orange),
            style: IconButton.styleFrom(backgroundColor: Colors.orange.shade50),
          ),
        ],
      ),
    );
  }

  Widget _buildStepper(OrderStatus status) {
    final currentStep = status.stepIndex;
    final steps = [
      {'title': 'Đã đặt đơn', 'desc': 'Đơn hàng đã được gửi', 'icon': Icons.assignment_turned_in},
      {'title': 'Quán chuẩn bị', 'desc': 'Đang nấu & đóng gói', 'icon': Icons.soup_kitchen},
      {'title': 'Đang giao hàng', 'desc': 'Shipper đang trên đường', 'icon': Icons.delivery_dining},
      {'title': 'Đã hoàn thành', 'desc': 'Đã giao tới bạn', 'icon': Icons.check_circle},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tiến trình đơn hàng',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < steps.length; i++) ...[
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: i < currentStep
                              ? Colors.orange
                              : (i == currentStep ? Colors.orange.shade100 : Colors.grey.shade100),
                          shape: BoxShape.circle,
                          border: i == currentStep ? Border.all(color: Colors.orange, width: 2) : null,
                        ),
                        child: Icon(
                          i < currentStep ? Icons.check : (steps[i]['icon'] as IconData),
                          size: 20,
                          color: i < currentStep
                              ? Colors.white
                              : (i == currentStep ? Colors.orange : Colors.grey.shade400),
                        ),
                      ),
                      if (i != steps.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: i < currentStep ? Colors.orange : Colors.grey.shade300,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            steps[i]['title'] as String,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: i <= currentStep ? FontWeight.bold : FontWeight.w500,
                              color: i == currentStep
                                  ? Colors.orange.shade800
                                  : (i < currentStep ? Colors.black87 : Colors.grey),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            steps[i]['desc'] as String,
                            style: TextStyle(
                              fontSize: 12,
                              color: i == currentStep ? Colors.black54 : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (i == currentStep)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: const Text(
                        'Hiện tại',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReviewPrompt(OrderModel order) {
    if (order.isReviewed) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified, color: Colors.green),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Bạn đã đánh giá ${order.review!.restaurantRating}⭐ cho đơn hàng này.',
                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade500, Colors.amber.shade600],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Đơn hàng đã giao thành công!',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Hãy chia sẻ trải nghiệm về món ăn và tài xế để giúp chúng tôi hoàn thiện dịch vụ.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OrderReviewScreen(order: order),
                ),
              );
            },
            icon: const Icon(Icons.star, color: Colors.orange),
            label: const Text(
              'Đánh giá & Bình luận ngay',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderDetailsCard(OrderModel order) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Chi tiết đơn hàng', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.store, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  order.restaurantName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 2),
            child: Text(order.restaurantAddress, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          const Divider(height: 24),
          Row(
            children: [
              const Icon(Icons.location_on, color: Colors.redAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  order.deliveryAddress,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          const Text('Món đã đặt:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          ...order.items.map((item) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text(item.emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${item.quantity}x ${item.name}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      if (item.note.isNotEmpty)
                        Text('Ghi chú: ${item.note}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
                Text(money(item.price * item.quantity), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ],
            ),
          )),
          const Divider(height: 24),
          _summaryRow('Tạm tính', money(order.subtotal)),
          _summaryRow('Phí giao hàng', money(order.deliveryFee)),
          if (order.discount > 0)
            _summaryRow('Giảm giá', '-${money(order.discount)}', isDiscount: true),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Tổng thanh toán', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              Text(
                money(order.totalPrice),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Hình thức: ${order.paymentMethod}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool isDiscount = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDiscount ? Colors.green : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

