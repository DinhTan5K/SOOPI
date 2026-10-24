import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/driver_location_tracker.dart';
import '../services/order_socket_service.dart';
import '../services/profile_api_service.dart';
import '../driver/driver_offer_dialog.dart';

class ShipperHomeScreen extends StatefulWidget {
  final Function(Map<String, dynamic> offer) onTripAccepted;

  const ShipperHomeScreen({super.key, required this.onTripAccepted});

  @override
  State<ShipperHomeScreen> createState() => _ShipperHomeScreenState();
}

class _ShipperHomeScreenState extends State<ShipperHomeScreen> {
  final _tracker = DriverLocationTracker();
  final _socket = OrderSocketService();
  final _mapController = MapController();

  bool _isOnline = false;
  bool _isLoading = false;
  bool _isShowingOfferDialog = false;
  String _driverId = '';
  String _driverName = 'Tài xế SOOPI';
  String _driverPhone = '';

  // Mặc định Đà Nẵng
  LatLng _currentLocation = const LatLng(16.0442, 108.2213);
  List<Map<String, dynamic>> _availableOrders = [];

  StreamSubscription? _offerSubscription;
  StreamSubscription? _statusSubscription;
  Timer? _locationPollTimer;

  @override
  void initState() {
    super.initState();
    _initShipper();

    _offerSubscription = _socket.onDeliveryOffer.listen((offer) {
      if (!mounted || !_isOnline) return;
      _fetchAvailableOrders();
      _handleIncomingOffer(offer);
    });

    _statusSubscription = _socket.onOrderStatus.listen((_) {
      if (!mounted || !_isOnline) return;
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
        _fetchAvailableOrders();
      }
    });
  }

  @override
  void dispose() {
    _offerSubscription?.cancel();
    _statusSubscription?.cancel();
    _locationPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _initShipper() async {
    try {
      final profile = await ProfileApiService().getProfile();
      if (profile.id.isNotEmpty) {
        _driverId = profile.id;
        _driverName = profile.fullName.isNotEmpty ? profile.fullName : 'Tài xế SOOPI';
        _driverPhone = profile.phoneNumber;
      } else {
        _driverId = 'd16e5d6a-903e-40fa-8b01-cf146ecd55ac';
      }
    } catch (_) {
      _driverId = 'd16e5d6a-903e-40fa-8b01-cf146ecd55ac';
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

    // Tự động bật chế độ nhận đơn ngay khi vào màn hình Tài xế
    if (mounted) {
      await _toggleOnline(true, silent: true);
    }
  }

  Future<void> _fetchAvailableOrders() async {
    if (!_isOnline) return;
    final list = await _socket.getAvailableOrdersForDriver(
      _currentLocation.latitude,
      _currentLocation.longitude,
    );
    if (mounted) {
      setState(() {
        _availableOrders = list;
      });
    }
  }

  Future<void> _toggleOnline(bool value, {bool silent = false}) async {
    if (_driverId.isEmpty) return;
    setState(() => _isLoading = true);

    if (value) {
      final ok = await _tracker.startTracking(
        driverId: _driverId,
        driverName: _driverName,
        driverPhone: _driverPhone,
      );
      if (ok && mounted) {
        setState(() => _isOnline = true);
        _currentLocation = LatLng(_tracker.currentLatitude, _tracker.currentLongitude);
        try {
          _mapController.move(_currentLocation, 16);
        } catch (_) {}
        await _fetchAvailableOrders();
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
      await _tracker.stopTracking(_driverId);
      if (mounted) {
        setState(() {
          _isOnline = false;
          _availableOrders = [];
        });
        if (!silent) {
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
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleIncomingOffer(Map<String, dynamic> offer) async {
    if (_isShowingOfferDialog) return;
    _isShowingOfferDialog = true;

    try {
      final accepted = await DriverOfferDialog.show(
        context,
        offer: offer,
        driverId: _driverId,
      );

      if (accepted == true && mounted) {
        widget.onTripAccepted(offer);
      }
    } finally {
      _isShowingOfferDialog = false;
    }
  }

  Future<void> _acceptWaitingOrder(Map<String, dynamic> offer) async {
    final orderId = offer['orderId']?.toString() ?? '';
    if (orderId.isEmpty) return;

    final ok = await _socket.driverAcceptOffer(orderId, _driverId);
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
            MarkerLayer(
              markers: [
                Marker(
                  point: _currentLocation,
                  width: 60,
                  height: 60,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_isOnline)
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
                          color: _isOnline ? Colors.green : Colors.grey.shade700,
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

        // 2. HEADER: THẺ TRẠNG THÁI & CÔNG TẮC BẬT NHẬN ĐƠN
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: _isOnline ? Colors.green.shade100 : Colors.grey.shade200,
                      child: Icon(
                        _isOnline ? Icons.radar : Icons.power_settings_new,
                        color: _isOnline ? Colors.green : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isOnline ? 'Đang sẵn sàng nhận cuốc' : 'Đang tạm dừng nhận cuốc',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: _isOnline ? Colors.green.shade800 : Colors.black87,
                            ),
                          ),
                          Text(
                            _isOnline
                                ? 'GPS: ${_currentLocation.latitude.toStringAsFixed(4)}, ${_currentLocation.longitude.toStringAsFixed(4)}'
                                : 'Bật công tắc để tìm đơn quanh bạn',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Quét lại đơn quanh đây',
                      onPressed: _fetchAvailableOrders,
                      icon: const Icon(Icons.refresh, color: Colors.deepOrange),
                    ),
                    _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Switch(
                            value: _isOnline,
                            activeTrackColor: Colors.green.shade300,
                            activeThumbColor: Colors.green,
                            onChanged: (val) => _toggleOnline(val),
                          ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // 3. KHAY ĐƠN HÀNG ĐANG CHỜ GIAO QUANH BẠN
        if (_isOnline && _availableOrders.isNotEmpty)
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
          bottom: (_isOnline && _availableOrders.isNotEmpty) ? 256 : 24,
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
