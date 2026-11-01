import 'package:flutter/foundation.dart';
import 'order_api_service.dart';
import '../order/order_data.dart';

class CompletedTripItem {
  final String orderId;
  final String orderCode;
  final String restaurantName;
  final String deliveryAddress;
  final int deliveryFee;
  final DateTime completedAt;

  CompletedTripItem({
    required this.orderId,
    required this.orderCode,
    required this.restaurantName,
    required this.deliveryAddress,
    required this.deliveryFee,
    required this.completedAt,
  });

  Map<String, dynamic> toJson() => {
        'orderId': orderId,
        'orderCode': orderCode,
        'restaurantName': restaurantName,
        'deliveryAddress': deliveryAddress,
        'deliveryFee': deliveryFee,
        'completedAt': completedAt.toIso8601String(),
      };

  factory CompletedTripItem.fromJson(Map<String, dynamic> json) => CompletedTripItem(
        orderId: json['orderId']?.toString() ?? '',
        orderCode: json['orderCode']?.toString() ?? '',
        restaurantName: json['restaurantName']?.toString() ?? 'Nhà hàng',
        deliveryAddress: json['deliveryAddress']?.toString() ?? 'Địa chỉ khách hàng',
        deliveryFee: (json['deliveryFee'] as num?)?.toInt() ?? 16000,
        completedAt: json['completedAt'] != null
            ? DateTime.tryParse(json['completedAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );
}

class ShipperCustomerReview {
  final String orderId;
  final String orderCode;
  final String restaurantName;
  final int rating;
  final String comment;
  final int tipAmount;
  final List<String> tags;
  final DateTime createdAt;

  ShipperCustomerReview({
    required this.orderId,
    required this.orderCode,
    required this.restaurantName,
    required this.rating,
    this.comment = '',
    this.tipAmount = 0,
    this.tags = const [],
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'orderId': orderId,
        'orderCode': orderCode,
        'restaurantName': restaurantName,
        'rating': rating,
        'comment': comment,
        'tipAmount': tipAmount,
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ShipperCustomerReview.fromJson(Map<String, dynamic> json) => ShipperCustomerReview(
        orderId: json['orderId']?.toString() ?? '',
        orderCode: json['orderCode']?.toString() ?? '',
        restaurantName: json['restaurantName']?.toString() ?? 'Đơn hàng',
        rating: (json['rating'] as num?)?.toInt() ?? (json['shipperRating'] as num?)?.toInt() ?? 5,
        comment: json['comment']?.toString() ?? json['shipperComment']?.toString() ?? '',
        tipAmount: (json['tipAmount'] as num?)?.toInt() ?? 0,
        tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
            (json['shipperTags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
            [],
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );
}

class ShipperEarningsService extends ChangeNotifier {
  static final ShipperEarningsService _instance = ShipperEarningsService._internal();
  factory ShipperEarningsService() => _instance;
  ShipperEarningsService._internal();

  final List<CompletedTripItem> _trips = [];
  final List<ShipperCustomerReview> _reviews = [];
  bool _isLoading = false;
  double _rating = 5.0;

  List<CompletedTripItem> get trips => List.unmodifiable(_trips);
  List<ShipperCustomerReview> get reviews => List.unmodifiable(_reviews);
  bool get isLoading => _isLoading;
  double get rating => _rating;

  int get todayEarnings {
    final now = DateTime.now();
    return _trips.where((t) {
      final local = t.completedAt.toLocal();
      return local.year == now.year &&
          local.month == now.month &&
          local.day == now.day;
    }).fold(0, (sum, t) => sum + t.deliveryFee);
  }

  int get totalEarnings => _trips.fold(0, (sum, t) => sum + t.deliveryFee);

  int get todayTripsCount {
    final now = DateTime.now();
    return _trips.where((t) {
      final local = t.completedAt.toLocal();
      return local.year == now.year &&
          local.month == now.month &&
          local.day == now.day;
    }).length;
  }

  int get totalTripsCount => _trips.length;

  /// Khởi tạo và đồng bộ thu nhập của tài xế TRỰC TIẾP TỪ BẢNG ORDERS TRONG DATABASE
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      _trips.clear();
      _reviews.clear();

      // Tải trực tiếp từ PostgreSQL Database qua Backend API (/api/shipper/dashboard)
      final dashboard = await OrderApiService().fetchShipperDashboard();
      if (dashboard != null) {
        // 1. Lấy danh sách cuốc xe đã hoàn thành từ bảng Orders
        final rawDbTrips = dashboard['trips'] ?? dashboard['Trips'] ?? dashboard['completedTrips'] ?? dashboard['CompletedTrips'];
        if (rawDbTrips is List) {
          for (final item in rawDbTrips) {
            if (item is Map) {
              final map = Map<String, dynamic>.from(item);
              final t = CompletedTripItem(
                orderId: map['orderId']?.toString() ?? map['OrderId']?.toString() ?? '',
                orderCode: map['orderCode']?.toString() ?? map['OrderCode']?.toString() ?? '',
                restaurantName: map['restaurantName']?.toString() ?? map['RestaurantName']?.toString() ?? 'Nhà hàng',
                deliveryAddress: map['deliveryAddress']?.toString() ?? map['DeliveryAddress']?.toString() ?? '',
                deliveryFee: (map['deliveryFee'] as num?)?.toInt() ??
                    (map['DeliveryFee'] as num?)?.toInt() ??
                    (map['shippingFee'] as num?)?.toInt() ??
                    (map['ShippingFee'] as num?)?.toInt() ??
                    16000,
                completedAt: map['completedAt'] != null
                    ? DateTime.tryParse(map['completedAt'].toString()) ?? DateTime.now()
                    : DateTime.now(),
              );
              if (t.orderId.isNotEmpty &&
                  !_trips.any((exist) => exist.orderId == t.orderId || exist.orderCode == t.orderCode)) {
                _trips.add(t);
              }
            }
          }
        }

        // 2. Lấy danh sách đánh giá từ bảng Reviews
        final rawDbReviews = dashboard['reviews'] ?? dashboard['Reviews'];
        if (rawDbReviews is List) {
          for (final item in rawDbReviews) {
            if (item is Map) {
              final map = Map<String, dynamic>.from(item);
              final r = ShipperCustomerReview(
                orderId: map['orderId']?.toString() ?? map['OrderId']?.toString() ?? '',
                orderCode: map['orderCode']?.toString() ?? map['OrderCode']?.toString() ?? '',
                restaurantName: map['restaurantName']?.toString() ?? map['RestaurantName']?.toString() ?? 'Quán ăn',
                rating: (map['rating'] as num?)?.toInt() ??
                    (map['Rating'] as num?)?.toInt() ??
                    (map['shipperRating'] as num?)?.toInt() ??
                    (map['ShipperRating'] as num?)?.toInt() ??
                    5,
                comment: map['comment']?.toString() ??
                    map['Comment']?.toString() ??
                    map['shipperComment']?.toString() ??
                    map['ShipperComment']?.toString() ??
                    '',
                tipAmount: (map['tipAmount'] as num?)?.toInt() ??
                    (map['TipAmount'] as num?)?.toInt() ??
                    0,
                tags: (map['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
                    (map['Tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
                    (map['shipperTags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
                    (map['ShipperTags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
                    [],
                createdAt: map['createdAt'] != null
                    ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
                    : DateTime.now(),
              );
              if (r.orderId.isNotEmpty &&
                  !_reviews.any((exist) => exist.orderId == r.orderId || exist.orderCode == r.orderCode)) {
                _reviews.add(r);
              }
            }
          }
        }

        // 3. Đánh giá trung bình
        if (dashboard['averageRating'] != null || dashboard['AverageRating'] != null) {
          _rating = (dashboard['averageRating'] as num?)?.toDouble() ??
              (dashboard['AverageRating'] as num?)?.toDouble() ??
              5.0;
        } else if (_reviews.isNotEmpty) {
          _rating = _reviews.fold<int>(0, (sum, r) => sum + r.rating) / _reviews.length;
        } else {
          _rating = 0.0;
        }
      }

      // 4. Fallback: Nếu API dashboard chưa nạp được nhưng trong OrderData có đơn Delivered
      if (_trips.isEmpty) {
        final allOrders = OrderData().orders;
        for (final o in allOrders) {
          if (o.status == OrderStatus.completed) {
            final id = o.backendId ?? o.id;
            if (!_trips.any((exist) => exist.orderId == id || exist.orderCode == (o.orderCode ?? o.id))) {
              _trips.add(
                CompletedTripItem(
                  orderId: id,
                  orderCode: o.orderCode ?? o.id,
                  restaurantName: o.restaurantName,
                  deliveryAddress: o.deliveryAddress,
                  deliveryFee: o.deliveryFee > 0 ? o.deliveryFee : 16000,
                  completedAt: o.createdAt,
                ),
              );
            }
          }
        }
      }

      // Sắp xếp cuốc xe và đánh giá mới nhất lên đầu
      _trips.sort((a, b) => b.completedAt.compareTo(a.completedAt));
      _reviews.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      debugPrint('[ShipperEarningsService] Lỗi nạp dữ liệu từ Backend: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Ghi nhận cuốc xe vừa giao thành công vào thu nhập tài xế ngay lập tức
  Future<void> recordCompletedTrip({
    required String orderId,
    required String orderCode,
    required String restaurantName,
    required String deliveryAddress,
    required int deliveryFee,
  }) async {
    final newItem = CompletedTripItem(
      orderId: orderId,
      orderCode: orderCode.isNotEmpty ? orderCode : orderId,
      restaurantName: restaurantName,
      deliveryAddress: deliveryAddress,
      deliveryFee: deliveryFee,
      completedAt: DateTime.now(),
    );

    _trips.removeWhere((t) => t.orderId == orderId || (orderCode.isNotEmpty && t.orderCode == orderCode));
    _trips.insert(0, newItem);
    notifyListeners();

    // Đồng bộ lại dữ liệu thật từ bảng Orders (Status = 'Delivered')
    await init();
  }

  /// Ghi nhận đánh giá mới từ khách hàng cho tài xế
  Future<void> recordCustomerReview({
    required String orderId,
    required String orderCode,
    required String restaurantName,
    required int rating,
    String comment = '',
    int tipAmount = 0,
    List<String> tags = const [],
  }) async {
    final newRev = ShipperCustomerReview(
      orderId: orderId,
      orderCode: orderCode.isNotEmpty ? orderCode : orderId,
      restaurantName: restaurantName,
      rating: rating,
      comment: comment,
      tipAmount: tipAmount,
      tags: tags,
      createdAt: DateTime.now(),
    );

    _reviews.removeWhere((r) => r.orderId == orderId || (orderCode.isNotEmpty && r.orderCode == orderCode));
    _reviews.insert(0, newRev);

    final totalStars = _reviews.fold<int>(0, (sum, r) => sum + r.rating);
    _rating = totalStars / _reviews.length;
    notifyListeners();
  }
}
