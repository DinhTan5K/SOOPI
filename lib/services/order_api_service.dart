import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../order/order_data.dart';
import 'profile_api_service.dart';
import 'api_config.dart';

class OrderApiService {
  static final OrderApiService _instance = OrderApiService._internal();
  factory OrderApiService() => _instance;
  OrderApiService._internal();

  final ProfileApiService _profileService = ProfileApiService();

  String get _baseUrl => _profileService.baseUrl;

  Future<Map<String, String>> _getHeaders() async {
    final profile = await _profileService.getProfile().catchError((_) => _profileService.getInitialProfile());
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (profile.firebaseUid.isNotEmpty) {
      headers['X-Firebase-Uid'] = profile.firebaseUid;
      headers['X-Firebase-Email'] = profile.email;
      headers['X-Firebase-Name'] = Uri.encodeComponent(profile.fullName);
    }
    return headers;
  }

  bool _isValidGuid(String? val) {
    if (val == null || val.length != 36) return false;
    return RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(val);
  }

  Future<String?> _getUserId() async {
    try {
      final profile = await _profileService.getProfile();
      if (_isValidGuid(profile.id)) return profile.id;
    } catch (_) {}
    final initial = _profileService.getInitialProfile();
    if (_isValidGuid(initial.id)) return initial.id;
    return null;
  }

  Future<http.Response> _safeGet(String path, Map<String, String> headers, {Duration timeout = const Duration(seconds: 4)}) async {
    try {
      final uri = Uri.parse('$_baseUrl$path');
      return await http.get(uri, headers: headers).timeout(timeout);
    } catch (_) {
      final detected = await ApiConfig().autoDetect();
      if (detected) {
        final uri = Uri.parse('$_baseUrl$path');
        return await http.get(uri, headers: headers).timeout(timeout);
      }
      rethrow;
    }
  }

  Future<http.Response> _safePost(String path, Map<String, String> headers, String body, {Duration timeout = const Duration(seconds: 8)}) async {
    try {
      final uri = Uri.parse('$_baseUrl$path');
      return await http.post(uri, headers: headers, body: body).timeout(timeout);
    } catch (_) {
      final detected = await ApiConfig().autoDetect();
      if (detected) {
        final uri = Uri.parse('$_baseUrl$path');
        return await http.post(uri, headers: headers, body: body).timeout(timeout);
      }
      rethrow;
    }
  }

  /// Đặt đơn hàng mới trực tiếp vào Backend Database
  Future<OrderModel> createOrder({
    required String restaurantId,
    required String restaurantName,
    required String restaurantAddress,
    required List<OrderItem> items,
    required String deliveryAddress,
    String paymentMethod = 'Tiền mặt khi nhận hàng (COD)',
    int deliveryFee = 16000,
  }) async {
    final userId = await _getUserId();
    if (userId == null || userId.isEmpty) {
      throw Exception('Chưa xác thực được người dùng.');
    }

    final headers = await _getHeaders();
    final body = jsonEncode({
      'restaurantId': restaurantId,
      'items': items.map((it) => {
        'menuItemId': it.id,
        'quantity': it.quantity,
        'note': it.note,
      }).toList(),
      'deliveryAddress': deliveryAddress,
      'paymentMethod': paymentMethod,
      'couponCode': null,
      'note': '',
    });

    final response = await _safePost('/users/$userId/orders/direct', headers, body);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return _mapJsonToOrder(data);
    } else {
      throw Exception('Lỗi đặt hàng (${response.statusCode}): ${response.body}');
    }
  }

  /// UC07: Lấy danh sách lịch sử đơn hàng từ Backend (GET /api/users/{userId}/orders)
  Future<List<OrderModel>> fetchOrders() async {
    final userId = await _getUserId();
    if (userId == null || userId.isEmpty) {
      throw Exception('Chưa xác thực được người dùng.');
    }

    final headers = await _getHeaders();
    final response = await _safeGet('/users/$userId/orders', headers);

    if (response.statusCode == 200) {
      final List<dynamic> list = jsonDecode(utf8.decode(response.bodyBytes));
      return list.map((json) => _mapJsonToOrder(json as Map<String, dynamic>)).toList();
    } else {
      throw Exception('Lỗi máy chủ: ${response.statusCode}');
    }
  }

  /// UC06: Theo dõi chi tiết đơn hàng theo thời gian thực (GET /api/users/{userId}/orders/{orderId})
  Future<OrderModel?> trackOrder(String orderId) async {
    final userId = await _getUserId();
    if (userId == null || userId.isEmpty) return null;

    final headers = await _getHeaders();

    try {
      final response = await _safeGet('/users/$userId/orders/$orderId', headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return _mapJsonToOrder(data as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('OrderApiService.trackOrder error: $e');
    }
    return null;
  }

  /// UC08: Gửi đánh giá đơn hàng lên Backend (POST /api/users/{userId}/orders/{orderId}/review)
  Future<bool> submitReview({
    required String orderId,
    required int restaurantRating,
    int? shipperRating,
    required String comment,
  }) async {
    final userId = await _getUserId();
    if (userId == null || userId.isEmpty) return false;

    final headers = await _getHeaders();
    final body = jsonEncode({
      'restaurantRating': restaurantRating,
      'shipperRating': shipperRating ?? restaurantRating,
      'comment': comment,
    });

    try {
      final response = await _safePost('/users/$userId/orders/$orderId/review', headers, body, timeout: const Duration(seconds: 5));
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('OrderApiService.submitReview error: $e');
      return false;
    }
  }

  /// Helper map dữ liệu JSON trả về từ Backend .NET sang OrderModel của Flutter
  OrderModel _mapJsonToOrder(Map<String, dynamic> json) {
    final orderId = json['id']?.toString() ?? json['orderCode']?.toString() ?? 'SP-0000';
    final restaurant = json['restaurant'] as Map<String, dynamic>?;
    final restaurantName = restaurant?['name']?.toString() ?? 'Nhà hàng SOOPI';
    final restaurantAddress = restaurant?['address']?.toString() ?? 'Hà Nội';

    final rawStatus = (json['status']?.toString() ?? 'pending').toLowerCase();
    OrderStatus status;
    switch (rawStatus) {
      case 'preparing':
        status = OrderStatus.preparing;
        break;
      case 'delivering':
        status = OrderStatus.delivering;
        break;
      case 'delivered':
      case 'completed':
        status = OrderStatus.completed;
        break;
      case 'cancelled':
        status = OrderStatus.cancelled;
        break;
      default:
        status = OrderStatus.pending;
    }

    final rawItems = json['items'] as List<dynamic>? ?? [];
    final items = rawItems.map((item) {
      final itemMap = item as Map<String, dynamic>;
      final price = (itemMap['unitPrice'] as num?)?.toInt() ?? (itemMap['price'] as num?)?.toInt() ?? 0;
      final quantity = (itemMap['quantity'] as num?)?.toInt() ?? 1;
      return OrderItem(
        id: itemMap['id']?.toString() ?? itemMap['menuItemId']?.toString() ?? '',
        name: itemMap['itemName']?.toString() ?? itemMap['name']?.toString() ?? 'Món ăn',
        price: price,
        quantity: quantity,
        emoji: '',
        note: itemMap['note']?.toString() ?? '',
      );
    }).toList();

    ShipperInfo? shipper;
    if (json['shipper'] != null) {
      final s = json['shipper'] as Map<String, dynamic>;
      shipper = ShipperInfo(
        name: s['fullName']?.toString() ?? s['name']?.toString() ?? 'Tài xế SOOPI',
        phone: s['phoneNumber']?.toString() ?? s['phone']?.toString() ?? '0901.234.567',
        rating: (s['rating'] as num?)?.toDouble() ?? 4.9,
        bikePlate: s['bikePlate']?.toString() ?? '29-X1 999.99',
        bikeType: s['bikeType']?.toString() ?? 'Honda Wave Alpha',
        avatarUrl: s['avatarUrl']?.toString() ??
            'https://ui-avatars.com/api/?name=Shipper&background=FF8A00&color=fff',
      );
    }

    final createdAtStr = json['createdAt']?.toString();
    final createdAt = createdAtStr != null ? DateTime.tryParse(createdAtStr) ?? DateTime.now() : DateTime.now();

    return OrderModel(
      id: orderId,
      restaurantName: restaurantName,
      restaurantAddress: restaurantAddress,
      restaurantEmoji: '',
      items: items.isNotEmpty ? items : [
        OrderItem(id: 'default', name: 'Combo món ăn tổng hợp', price: (json['subtotal'] as num?)?.toInt() ?? 50000, quantity: 1)
      ],
      deliveryFee: (json['deliveryFee'] as num?)?.toInt() ?? 15000,
      discount: (json['discountAmount'] as num?)?.toInt() ?? 0,
      paymentMethod: json['paymentMethod']?.toString() ?? 'Tiền mặt khi nhận hàng (COD)',
      deliveryAddress: json['deliveryAddress']?.toString() ?? 'Địa chỉ mặc định',
      status: status,
      createdAt: createdAt,
      estimatedDeliveryMinutes: status == OrderStatus.delivering ? 15 : (status == OrderStatus.preparing ? 25 : 0),
      shipper: shipper,
    );
  }
}
