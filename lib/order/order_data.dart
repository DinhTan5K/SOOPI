import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/order_api_service.dart';

enum OrderStatus {
  pending,
  preparing,
  delivering,
  completed,
  cancelled,
}

extension OrderStatusExtension on OrderStatus {
  String get label {
    switch (this) {
      case OrderStatus.pending:
        return 'Chờ xác nhận';
      case OrderStatus.preparing:
        return 'Quán đang làm';
      case OrderStatus.delivering:
        return 'Tài xế đang giao';
      case OrderStatus.completed:
        return 'Đã hoàn thành';
      case OrderStatus.cancelled:
        return 'Đã hủy';
    }
  }

  int get stepIndex {
    switch (this) {
      case OrderStatus.pending:
        return 0;
      case OrderStatus.preparing:
        return 1;
      case OrderStatus.delivering:
        return 2;
      case OrderStatus.completed:
        return 3;
      case OrderStatus.cancelled:
        return -1;
    }
  }
}

class OrderItem {
  final String id;
  final String name;
  final int price;
  final int quantity;
  final String emoji;
  final String note;

  OrderItem({
    required this.id,
    required this.name,
    required this.price,
    required this.quantity,
    this.emoji = '',
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'quantity': quantity,
    'emoji': emoji,
    'note': note,
  };

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
    id: json['id'] as String,
    name: json['name'] as String,
    price: json['price'] as int,
    quantity: json['quantity'] as int,
    emoji: json['emoji'] as String? ?? '',
    note: json['note'] as String? ?? '',
  );
}

class ShipperInfo {
  final String name;
  final String phone;
  final double rating;
  final String bikePlate;
  final String bikeType;
  final String avatarUrl;

  ShipperInfo({
    required this.name,
    required this.phone,
    required this.rating,
    required this.bikePlate,
    required this.bikeType,
    this.avatarUrl = 'https://ui-avatars.com/api/?name=Shipper&background=FF8A00&color=fff',
  });
}

class ReviewModel {
  final int restaurantRating;
  final List<String> restaurantTags;
  final String restaurantComment;
  final int shipperRating;
  final List<String> shipperTags;
  final String shipperComment;
  final int tipAmount;
  final DateTime createdAt;

  ReviewModel({
    required this.restaurantRating,
    this.restaurantTags = const [],
    this.restaurantComment = '',
    required this.shipperRating,
    this.shipperTags = const [],
    this.shipperComment = '',
    this.tipAmount = 0,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'restaurantRating': restaurantRating,
        'restaurantTags': restaurantTags,
        'restaurantComment': restaurantComment,
        'shipperRating': shipperRating,
        'shipperTags': shipperTags,
        'shipperComment': shipperComment,
        'tipAmount': tipAmount,
        'createdAt': createdAt.toIso8601String(),
      };

  static List<String> _parseTags(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    return [];
  }

  factory ReviewModel.fromJson(Map<String, dynamic> json) {
    final restComment = json['restaurantComment']?.toString() ??
        json['comment']?.toString() ??
        json['Comment']?.toString() ??
        '';
    final shipComment = json['shipperComment']?.toString() ??
        json['ShipperComment']?.toString() ??
        '';
    return ReviewModel(
      restaurantRating: (json['restaurantRating'] as num?)?.toInt() ??
          (json['RestaurantRating'] as num?)?.toInt() ??
          (json['rating'] as num?)?.toInt() ??
          (json['Rating'] as num?)?.toInt() ??
          5,
      restaurantTags: _parseTags(json['restaurantTags'] ?? json['RestaurantTags'] ?? json['tags']),
      restaurantComment: restComment,
      shipperRating: (json['shipperRating'] as num?)?.toInt() ??
          (json['ShipperRating'] as num?)?.toInt() ??
          (json['driverRating'] as num?)?.toInt() ??
          5,
      shipperTags: _parseTags(json['shipperTags'] ?? json['ShipperTags']),
      shipperComment: shipComment.isNotEmpty ? shipComment : restComment,
      tipAmount: (json['tipAmount'] as num?)?.toInt() ??
          (json['TipAmount'] as num?)?.toInt() ??
          0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class OrderModel {
  final String id;
  final String? backendId;
  final String? orderCode;
  final String? restaurantId;
  final String restaurantName;
  final String restaurantAddress;
  final String restaurantEmoji;
  final List<OrderItem> items;
  final int deliveryFee;
  final int discount;
  final String paymentMethod;
  final String deliveryAddress;
  OrderStatus status;
  final DateTime createdAt;
  int estimatedDeliveryMinutes;
  ShipperInfo? shipper;
  ReviewModel? review;
  double? restaurantLat;
  double? restaurantLng;
  double? userLat;
  double? userLng;

  OrderModel({
    required this.id,
    this.backendId,
    this.orderCode,
    this.restaurantId,
    required this.restaurantName,
    required this.restaurantAddress,
    this.restaurantEmoji = '',
    required this.items,
    this.deliveryFee = 16000,
    this.discount = 0,
    this.paymentMethod = 'Tiền mặt (COD)',
    required this.deliveryAddress,
    required this.status,
    required this.createdAt,
    this.estimatedDeliveryMinutes = 15,
    this.shipper,
    this.review,
    this.restaurantLat,
    this.restaurantLng,
    this.userLat,
    this.userLng,
  });

  int get subtotal => items.fold(0, (sum, item) => sum + (item.price * item.quantity));
  int get totalPrice => subtotal + deliveryFee - discount;
  bool get isReviewed => review != null;
  bool get isActive =>
      status == OrderStatus.pending ||
      status == OrderStatus.preparing ||
      status == OrderStatus.delivering;
}

String money(int value) =>
    '${value.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')} đ';

class OrderData extends ChangeNotifier {
  static final OrderData _instance = OrderData._internal();
  factory OrderData() => _instance;

  OrderData._internal() {
    refreshFromApi();
  }

  final List<OrderModel> _orders = [];
  bool isLoading = false;
  bool isFromBackend = false;
  String? activeCouponCode;

  List<OrderModel> get orders => List.unmodifiable(_orders);
  List<OrderModel> get activeOrders => _orders.where((o) => o.isActive).toList();
  List<OrderModel> get pastOrders => _orders.where((o) => !o.isActive).toList();

  Future<void> refreshFromApi() async {
    isLoading = true;
    notifyListeners();
    try {
      final remoteOrders = await OrderApiService().fetchOrders();

      // Khôi phục đánh giá đã lưu nếu backend chưa trả về trường review
      try {
        final prefs = await SharedPreferences.getInstance();
        for (final o in remoteOrders) {
          if (o.review == null) {
            final saved = prefs.getString('soopi.order_review.${o.id}') ??
                (o.backendId != null ? prefs.getString('soopi.order_review.${o.backendId}') : null) ??
                (o.orderCode != null ? prefs.getString('soopi.order_review.${o.orderCode}') : null);
            if (saved != null && saved.isNotEmpty) {
              try {
                o.review = ReviewModel.fromJson(jsonDecode(saved) as Map<String, dynamic>);
              } catch (_) {}
            }
          }
        }
      } catch (_) {}

      _orders.clear();
      _orders.addAll(remoteOrders);
      isFromBackend = true;
    } catch (e) {
      debugPrint('OrderData: Chưa kết nối được BE ($e)');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> syncTrack(String orderId) async {
    try {
      final existing = findById(orderId);
      final lookupId = existing?.backendId ?? orderId;
      final updated = await OrderApiService().trackOrder(lookupId);
      if (updated != null) {
        final idx = _orders.indexWhere(
          (o) =>
              o.id.toLowerCase() == orderId.toLowerCase() ||
              (o.backendId != null && o.backendId!.toLowerCase() == lookupId.toLowerCase()),
        );
        if (idx != -1) {
          _orders[idx] = updated;
        } else {
          _orders.insert(0, updated);
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('OrderData: Chưa đồng bộ được tracking từ BE ($e)');
    }
  }

  OrderModel? findById(String id) {
    final q = id.trim().toLowerCase();
    try {
      return _orders.firstWhere(
        (o) =>
            o.id.toLowerCase() == q ||
            (o.backendId != null && o.backendId!.toLowerCase() == q) ||
            (o.orderCode != null && o.orderCode!.toLowerCase() == q) ||
            o.id.toLowerCase().contains(q) ||
            (o.backendId != null && o.backendId!.toLowerCase().contains(q)),
      );
    } catch (_) {
      return null;
    }
  }

  /// Đặt đơn hàng mới lưu trực tiếp vào Database thông qua Backend API
  Future<OrderModel> createOrder({
    String? restaurantId,
    required String restaurantName,
    required String restaurantAddress,
    String restaurantEmoji = '',
    required List<OrderItem> items,
    required String deliveryAddress,
    String paymentMethod = 'Tiền mặt khi nhận hàng (COD)',
    int deliveryFee = 16000,
    int discount = 0,
    double? restaurantLat,
    double? restaurantLng,
    double? userLat,
    double? userLng,
    String? couponCode,
  }) async {
    final effectiveCoupon = (couponCode != null && couponCode.trim().isNotEmpty)
        ? couponCode.trim().toUpperCase()
        : (activeCouponCode != null && activeCouponCode!.trim().isNotEmpty
            ? activeCouponCode!.trim().toUpperCase()
            : null);
    try {
      final backendOrder = await OrderApiService().createOrder(
        restaurantId: restaurantId ?? '',
        restaurantName: restaurantName,
        restaurantAddress: restaurantAddress,
        items: items,
        deliveryAddress: deliveryAddress,
        paymentMethod: paymentMethod,
        deliveryFee: deliveryFee,
        couponCode: effectiveCoupon,
        userLat: userLat,
        userLng: userLng,
      );
      activeCouponCode = null;
      backendOrder.restaurantLat = restaurantLat;
      backendOrder.restaurantLng = restaurantLng;
      backendOrder.userLat = userLat;
      backendOrder.userLng = userLng;
      _orders.insert(0, backendOrder);
      isFromBackend = true;
      notifyListeners();
      return backendOrder;
    } catch (e) {
      debugPrint('OrderData.createOrder Backend error: $e');
      rethrow;
    }
  }

  void advanceOrderStatus(String orderId) {
    final order = findById(orderId);
    if (order == null) return;

    if (order.status == OrderStatus.pending) {
      order.status = OrderStatus.preparing;
      order.estimatedDeliveryMinutes = 20;
    } else if (order.status == OrderStatus.preparing) {
      order.status = OrderStatus.delivering;
      order.estimatedDeliveryMinutes = 12;
    } else if (order.status == OrderStatus.delivering) {
      order.status = OrderStatus.completed;
      order.estimatedDeliveryMinutes = 0;
    }
    notifyListeners();
  }

  Future<OrderModel> reorder(OrderModel oldOrder) async {
    return await createOrder(
      restaurantId: oldOrder.backendId,
      restaurantName: oldOrder.restaurantName,
      restaurantAddress: oldOrder.restaurantAddress,
      restaurantEmoji: oldOrder.restaurantEmoji,
      items: oldOrder.items,
      deliveryAddress: oldOrder.deliveryAddress,
      paymentMethod: oldOrder.paymentMethod,
      deliveryFee: oldOrder.deliveryFee,
      restaurantLat: oldOrder.restaurantLat,
      restaurantLng: oldOrder.restaurantLng,
      userLat: oldOrder.userLat,
      userLng: oldOrder.userLng,
    );
  }

  void submitReview(String orderId, ReviewModel review) {
    final order = findById(orderId);
    if (order != null) {
      order.review = review;
      notifyListeners();
    }

    // Luôn lưu ngay review vào SharedPreferences để không bao giờ bị mất
    try {
      SharedPreferences.getInstance().then((prefs) {
        final encoded = jsonEncode(review.toJson());
        prefs.setString('soopi.order_review.$orderId', encoded);
        if (order?.id != null && order!.id != orderId) {
          prefs.setString('soopi.order_review.${order.id}', encoded);
        }
        if (order?.backendId != null && order!.backendId!.isNotEmpty) {
          prefs.setString('soopi.order_review.${order.backendId}', encoded);
        }
        if (order?.orderCode != null && order!.orderCode!.isNotEmpty) {
          prefs.setString('soopi.order_review.${order.orderCode}', encoded);
        }
      });
    } catch (_) {}

    final lookupId = order?.backendId ?? orderId;

    OrderApiService().submitReview(
      orderId: lookupId,
      restaurantRating: review.restaurantRating,
      shipperRating: review.shipperRating,
      comment: review.restaurantComment.isNotEmpty
          ? review.restaurantComment
          : review.shipperComment,
      shipperComment: review.shipperComment.isNotEmpty
          ? review.shipperComment
          : review.restaurantComment,
      restaurantTags: review.restaurantTags,
      shipperTags: review.shipperTags,
      tipAmount: review.tipAmount,
    ).then((success) {
      if (success) {
        debugPrint('OrderData: Gửi đánh giá lên Backend thành công ($lookupId)');
      }
    });
  }
}
