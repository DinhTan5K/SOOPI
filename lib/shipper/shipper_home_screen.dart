import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/driver_location_tracker.dart';
import '../services/geocoding_service.dart';
import '../services/order_socket_service.dart';
import '../services/profile_api_service.dart';
import '../driver/driver_offer_dialog.dart';

class ShipperHomeScreen extends StatefulWidget {
  final Function(Map<String, dynamic> offer) onTripAccepted;
  final bool hasActiveTrip;
  final Map<String, dynamic>? activeTrip;
  final String activeTripCode;
  final VoidCallback? onNavigateToActiveTrip;
  final bool isOnline;
  final Function(bool value)? onToggleOnline;

  const ShipperHomeScreen({
    super.key,
    required this.onTripAccepted,
    this.hasActiveTrip = false,
    this.activeTrip,
    this.activeTripCode = '',
    this.onNavigateToActiveTrip,
    this.isOnline = true,
    this.onToggleOnline,
  });

  @override
  State<ShipperHomeScreen> createState() => _ShipperHomeScreenState();
}

class _ShipperHomeScreenState extends State<ShipperHomeScreen> {
  final _tracker = DriverLocationTracker();
  final _socket = OrderSocketService();
  final _mapController = MapController();

  bool _isShowingOfferDialog = false;
  String _driverId = '';
  String _driverName = 'Tài xế SOOPI';
  String _driverPhone = '';

  // Mặc định Đà Nẵng
  LatLng _currentLocation = const LatLng(16.0442, 108.2213);
  List<Map<String, dynamic>> _availableOrders = [];
  LatLng? _geocodedCustomerPos;
  String _lastGeocodedOrderId = '';

  StreamSubscription? _offerSubscription;
  StreamSubscription? _statusSubscription;
  Timer? _locationPollTimer;

  @override
  void initState() {
    super.initState();
    _initShipper();

    _offerSubscription = _socket.onDeliveryOffer.listen((offer) {
      // Khi tài xế đang có đơn giao dở dang hoặc đang offline -> Tuyệt đối không nổ đơn che bản đồ
      if (!mounted || !widget.isOnline || widget.hasActiveTrip) return;
      _fetchAvailableOrders();
      _handleIncomingOffer(offer);
    });

    _statusSubscription = _socket.onOrderStatus.listen((_) {
      if (!mounted || !widget.isOnline || widget.hasActiveTrip) return;
      _fetchAvailableOrders();
    });

    _locationPollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      if (_tracker.isTracking) {
        final newCoord = LatLng(_tracker.currentLatitude, _tracker.currentLongitude);
        if (newCoord != _currentLocation) {
          setState(() {
            _currentLocation = newCoord;
          });
        }
        if (!widget.hasActiveTrip && widget.isOnline) {
          _fetchAvailableOrders();
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant ShipperHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasActiveTrip != oldWidget.hasActiveTrip ||
        widget.activeTrip?['orderId'] != oldWidget.activeTrip?['orderId']) {
      if (widget.hasActiveTrip && widget.activeTrip != null) {
        setState(() {
          _availableOrders = [];
        });
        _syncActiveTripCoordinates(widget.activeTrip!);
      } else {
        setState(() {
          _geocodedCustomerPos = null;
          _lastGeocodedOrderId = '';
        });
        // Tài xế vừa rảnh rỗi (hoàn thành đơn) -> Quét lại đơn đang chờ và nổ đơn nếu có
        _fetchAvailableOrders(autoPromptFirst: true);
      }
    }
    if (widget.isOnline != oldWidget.isOnline) {
      if (widget.isOnline) {
        _fetchAvailableOrders(autoPromptFirst: true);
      } else {
        setState(() {
          _availableOrders = [];
        });
      }
    }
  }

  double? _parseDouble(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString());
  }

  LatLng _getActiveRestaurantPos(Map<String, dynamic> trip) {
    final lat = _parseDouble(trip['restaurantLatitude'] ?? trip['RestaurantLatitude'] ?? trip['latitude']);
    final lng = _parseDouble(trip['restaurantLongitude'] ?? trip['RestaurantLongitude'] ?? trip['longitude']);
    if (lat != null && lng != null && lat != 0 && lng != 0) {
      return LatLng(lat, lng);
    }
    return LatLng(_currentLocation.latitude + 0.0045, _currentLocation.longitude + 0.0038);
  }

  LatLng _getActiveCustomerPos(Map<String, dynamic> trip, LatLng restaurantPos) {
    final orderId = (trip['orderId'] ?? trip['OrderId'] ?? '').toString();
    if (_geocodedCustomerPos != null && _lastGeocodedOrderId == orderId) {
      return _geocodedCustomerPos!;
    }
    final lat = _parseDouble(trip['customerLatitude'] ?? trip['CustomerLatitude']);
    final lng = _parseDouble(trip['customerLongitude'] ?? trip['CustomerLongitude']);
    if (lat != null && lng != null && lat != 0 && lng != 0) {
      return LatLng(lat, lng);
    }
    return LatLng(restaurantPos.latitude + 0.0095, restaurantPos.longitude + 0.0082);
  }

  LatLng _getWaitingOrderPos(Map<String, dynamic> order, int index) {
    final lat = _parseDouble(order['restaurantLatitude'] ?? order['RestaurantLatitude']);
    final lng = _parseDouble(order['restaurantLongitude'] ?? order['RestaurantLongitude']);
    if (lat != null && lng != null && lat != 0 && lng != 0) {
      // Thêm độ lệch cực nhỏ theo index để nếu nhiều đơn cùng 1 quán không đè khít lên nhau
      return LatLng(lat + (index * 0.00025), lng + (index * 0.00025));
    }
    final offsetLat = 0.003 + (index * 0.0018);
    final offsetLng = 0.0025 - (index * 0.0015);
    return LatLng(_currentLocation.latitude + offsetLat, _currentLocation.longitude + offsetLng);
  }

  Future<void> _syncActiveTripCoordinates(Map<String, dynamic> trip) async {
    final orderId = (trip['orderId'] ?? trip['OrderId'] ?? '').toString();
    final restaurantPos = _getActiveRestaurantPos(trip);
    final fallbackCustomerPos = _getActiveCustomerPos(trip, restaurantPos);

    // Đưa camera về trung điểm giữa tài xế, quán và khách để thấy trọn lộ trình
    final midLat = (_currentLocation.latitude + restaurantPos.latitude + fallbackCustomerPos.latitude) / 3.0;
    final midLng = (_currentLocation.longitude + restaurantPos.longitude + fallbackCustomerPos.longitude) / 3.0;
    try {
      _mapController.move(LatLng(midLat, midLng), 14.2);
    } catch (_) {}

    final address = (trip['deliveryAddress'] ?? trip['DeliveryAddress'] ?? '').toString().trim();
    if (address.isEmpty || GeocodingService.isRawCoordinateAddress(address)) return;

    final geocoded = await GeocodingService.getCoordinatesFromAddress(address);
    if (!mounted || geocoded == null) return;

    // Chỉ dùng tọa độ geocode nếu nằm trong phạm vi hợp lý (<= 25km quanh quán)
    final distKm = GeocodingService.calculateDistanceKm(
      restaurantPos.latitude,
      restaurantPos.longitude,
      geocoded.latitude,
      geocoded.longitude,
    );
    if (distKm <= 25.0 && mounted) {
      setState(() {
        _lastGeocodedOrderId = orderId;
        _geocodedCustomerPos = geocoded;
      });
    }
  }

  List<LatLng> _getRoutePoints(LatLng start, LatLng end) {
    final mid1 = LatLng(
      start.latitude + (end.latitude - start.latitude) * 0.35,
      start.longitude + (end.longitude - start.longitude) * 0.2,
    );
    final mid2 = LatLng(
      start.latitude + (end.latitude - start.latitude) * 0.7,
      start.longitude + (end.longitude - start.longitude) * 0.85,
    );
    return [start, mid1, mid2, end];
  }

  Widget _buildLocationPin({
    required IconData icon,
    required Color color,
    required String label,
    required String subLabel,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Text(
                subLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.45),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _offerSubscription?.cancel();
    _statusSubscription?.cancel();
    _locationPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _initShipper() async {
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
    } catch (e) {
      debugPrint('[ShipperHomeScreen] Lỗi tải profile tài xế: $e');
    }

    // Lấy vị trí ban đầu (không chặn nếu timeout)
    try {
      final pos = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              timeLimit: Duration(seconds: 3),
            ),
          );
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(pos.latitude, pos.longitude);
        });
        _mapController.move(_currentLocation, 15.5);
      }
    } catch (_) {}

    // Quét đơn chờ nếu đang online và rảnh rỗi, hoặc đồng bộ lộ trình nếu đang có chuyến đi
    if (mounted) {
      if (widget.hasActiveTrip && widget.activeTrip != null) {
        _syncActiveTripCoordinates(widget.activeTrip!);
      } else if (widget.isOnline) {
        _fetchAvailableOrders(autoPromptFirst: true);
      }
    }
  }

  Future<void> _fetchAvailableOrders({bool autoPromptFirst = false}) async {
    if (!widget.isOnline || widget.hasActiveTrip) {
      if (mounted && _availableOrders.isNotEmpty) {
        setState(() {
          _availableOrders = [];
        });
      }
      return;
    }
    final list = await _socket.getAvailableOrdersForDriver(
      _currentLocation.latitude,
      _currentLocation.longitude,
    );
    if (mounted) {
      setState(() {
        _availableOrders = list;
      });

      // Tự động bung popup nổ đơn ngay khi tài xế rảnh rỗi vừa login / online và có đơn chờ mới
      if (autoPromptFirst && _availableOrders.isNotEmpty && !_isShowingOfferDialog && !widget.hasActiveTrip && widget.isOnline) {
        _handleIncomingOffer(_availableOrders.first);
      }
    }
  }

  Future<void> _handleIncomingOffer(Map<String, dynamic> offer) async {
    // Khi đang có chuyến đi, tuyệt đối không mở dialog nổ đơn che bản đồ
    if (_isShowingOfferDialog || widget.hasActiveTrip) return;
    _isShowingOfferDialog = true;

    try {
      String targetDriverId = _driverId;
      if (targetDriverId.isEmpty) {
        targetDriverId = ProfileApiService().cachedProfile?.id ?? '';
        if (targetDriverId.isEmpty) {
          targetDriverId = FirebaseAuth.instance.currentUser?.uid ?? '';
        }
      }

      final accepted = await DriverOfferDialog.show(
        context,
        offer: offer,
        driverId: targetDriverId,
      );

      if (accepted == true && mounted) {
        widget.onTripAccepted(offer);
      }
    } finally {
      _isShowingOfferDialog = false;
    }
  }

  Future<void> _acceptWaitingOrder(Map<String, dynamic> offer) async {
    if (widget.hasActiveTrip) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('Bạn đang có chuyến đi chưa hoàn tất. Vui lòng giao xong đơn hiện tại!'),
        ),
      );
      return;
    }

    final orderId = offer['orderId']?.toString() ?? '';
    if (orderId.isEmpty) return;

    String targetDriverId = _driverId;
    if (targetDriverId.isEmpty) {
      targetDriverId = ProfileApiService().cachedProfile?.id ?? '';
      if (targetDriverId.isEmpty) {
        targetDriverId = FirebaseAuth.instance.currentUser?.uid ?? '';
      }
    }

    final ok = await _socket.driverAcceptOffer(orderId, targetDriverId);
    if (ok && mounted) {
      widget.onTripAccepted(offer);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Đơn hàng này đã được nhận hoặc không còn khả dụng.'),
        ),
      );
      _fetchAvailableOrders();
    }
  }

  String _formatCurrency(dynamic value) {
    final numVal = (value is num) ? value.toInt() : int.tryParse(value.toString()) ?? 0;
    return '${numVal.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}đ';
  }

  @override
  Widget build(BuildContext context) {
    final activeTrip = widget.hasActiveTrip ? widget.activeTrip : null;
    LatLng? activeRestaurantPos;
    LatLng? activeCustomerPos;
    List<LatLng> activeRoutePoints = [];

    if (activeTrip != null) {
      activeRestaurantPos = _getActiveRestaurantPos(activeTrip);
      activeCustomerPos = _getActiveCustomerPos(activeTrip, activeRestaurantPos);
      final leg1 = _getRoutePoints(_currentLocation, activeRestaurantPos);
      final leg2 = _getRoutePoints(activeRestaurantPos, activeCustomerPos);
      activeRoutePoints = [...leg1, ...leg2.skip(1)];
    }

    return Stack(
      children: [
        // 1. BẢN ĐỒ TOÀN MÀN HÌNH
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentLocation,
            initialZoom: 15.5,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.soopi',
            ),
            if (activeRoutePoints.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: activeRoutePoints,
                    strokeWidth: 4.5,
                    color: Colors.deepOrange,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                // 1a. Khi đang có chuyến đi: Hiện pin Quán ăn và pin Khách hàng
                if (activeTrip != null && activeRestaurantPos != null)
                  Marker(
                    point: activeRestaurantPos,
                    width: 150,
                    height: 78,
                    child: _buildLocationPin(
                      icon: Icons.storefront_rounded,
                      color: Colors.deepOrange,
                      label: (activeTrip['restaurantName'] ?? activeTrip['RestaurantName'] ?? 'Quán ăn SOOPI').toString(),
                      subLabel: 'Điểm lấy món',
                    ),
                  ),
                if (activeTrip != null && activeCustomerPos != null)
                  Marker(
                    point: activeCustomerPos,
                    width: 165,
                    height: 78,
                    child: _buildLocationPin(
                      icon: Icons.location_on_rounded,
                      color: Colors.green.shade700,
                      label: (activeTrip['deliveryAddress'] ?? activeTrip['DeliveryAddress'] ?? 'Điểm giao hàng').toString(),
                      subLabel: 'Điểm giao cho khách',
                    ),
                  ),

                // 1b. Khi đang rảnh rỗi và online: Hiện pin các quán đang có đơn chờ quanh tài xế
                if (activeTrip == null && widget.isOnline && _availableOrders.isNotEmpty)
                  for (int i = 0; i < _availableOrders.length; i++)
                    Marker(
                      point: _getWaitingOrderPos(_availableOrders[i], i),
                      width: 145,
                      height: 78,
                      child: GestureDetector(
                        onTap: () => _handleIncomingOffer(_availableOrders[i]),
                        child: _buildLocationPin(
                          icon: Icons.storefront_rounded,
                          color: Colors.orange.shade800,
                          label: (_availableOrders[i]['restaurantName'] ?? 'Quán SOOPI').toString(),
                          subLabel: 'Ship ${_formatCurrency(_availableOrders[i]['deliveryFee'] ?? 13000)}',
                        ),
                      ),
                    ),

                // 1c. Vị trí hiện tại của Shipper
                Marker(
                  point: _currentLocation,
                  width: 60,
                  height: 60,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (widget.isOnline)
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.green.withValues(alpha: 0.25),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: widget.isOnline ? Colors.green : Colors.grey.shade700,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 6),
                          ],
                        ),
                        child: const Icon(
                          Icons.delivery_dining,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),

        // 2. BANNER ĐANG CÓ CHUYẾN ĐI (CHẠM ĐỂ QUAY LẠI CHUYẾN ĐI)
        if (widget.hasActiveTrip)
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(14),
              color: Colors.deepOrange,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: widget.onNavigateToActiveTrip,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.delivery_dining, color: Colors.white, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.activeTripCode.isNotEmpty
                              ? 'Đang giao đơn #${widget.activeTripCode} • Chạm để quay lại'
                              : 'Đang có chuyến đi chưa hoàn tất • Chạm để quay lại',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // 2b. CHỈ BÁO KHI TẠM NGHỈ (OFFLINE)
        if (!widget.isOnline && !widget.hasActiveTrip)
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(14),
              color: Colors.black87.withValues(alpha: 0.8),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.nightlight_round, color: Colors.amber, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Đang tạm nghỉ • Bật nhận đơn tại tab Thu nhập',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 3. KHAY ĐƠN HÀNG ĐANG CHỜ GIAO QUANH BẠN (CHỈ HIỆN KHI RẢNH RỖI)
        if (widget.isOnline && !widget.hasActiveTrip && _availableOrders.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 240),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.shade50,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Có ${_availableOrders.length} đơn đang cần tài xế gần bạn (trong bán kính 5km)',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.deepOrange,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(12),
                      itemCount: _availableOrders.length,
                      separatorBuilder: (_, _) => const Divider(height: 14),
                      itemBuilder: (context, index) {
                        final order = _availableOrders[index];
                        final code = order['orderCode'] ?? 'SP-Order';
                        final shop = order['restaurantName'] ?? 'Quán ăn SOOPI';
                        final addr = order['deliveryAddress'] ?? 'Địa chỉ khách hàng';
                        final dist = order['distanceToRestaurantKm'] ?? 0.1;
                        final fee = _formatCurrency(order['deliveryFee'] ?? 16000);
                        final total = _formatCurrency(order['totalAmount'] ?? 0);

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade100,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '#$code',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: Colors.deepOrange.shade900,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          shop.toString(),
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        'Cách ${dist}km',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: Colors.blue.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Giao đến: $addr',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Phí ship: $fee • Thu hộ: $total',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton(
                              onPressed: () => _acceptWaitingOrder(order),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green.shade600,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'Nhận đơn',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 4. NÚT VỊ TRÍ CỦA TÔI
        Positioned(
          bottom: (widget.isOnline && !widget.hasActiveTrip && _availableOrders.isNotEmpty) ? 256 : 24,
          right: 16,
          child: FloatingActionButton.small(
            heroTag: 'recenter_gps',
            backgroundColor: Colors.white,
            foregroundColor: Colors.deepOrange,
            onPressed: () {
              _mapController.move(_currentLocation, 16.5);
            },
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }
}
