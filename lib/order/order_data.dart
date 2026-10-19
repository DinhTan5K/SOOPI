import 'package:flutter/foundation.dart';
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
    this.emoji = '🍔',
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
    emoji: json['emoji'] as String? ?? '🍔',
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
}

class OrderModel {
  final String id;
  final String? backendId;
  final String? orderCode;
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
  final ShipperInfo? shipper;
  ReviewModel? review;
  final double? restaurantLat;
  final double? restaurantLng;
  final double? userLat;
  final double? userLng;

  OrderModel({
    required this.id,
    this.backendId,
    this.orderCode,
    required this.restaurantName,
    required this.restaurantAddress,
    this.restaurantEmoji = '🏪',
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

  List<OrderModel> get orders => List.unmodifiable(_orders);
  List<OrderModel> get activeOrders => _orders.where((o) => o.isActive).toList();
  List<OrderModel> get pastOrders => _orders.where((o) => !o.isActive).toList();

  Future<void> refreshFromApi() async {
    isLoading = true;
    notifyListeners();
    try {
      final remoteOrders = await OrderApiService().fetchOrders();
      _orders.clear();
      _orders.addAll(remoteOrders);
      isFromBackend = true;
    } catch (e) {
      debugPrint('OrderData: Chưa kết nối được BE ($e), tiếp tục dùng dữ liệu local');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> syncTrack(String orderId) async {
    try {
      final updated = await OrderApiService().trackOrder(orderId);
      if (updated != null) {
        final idx = _orders.indexWhere((o) => o.id == orderId);
        if (idx != -1) {
          _orders[idx] = updated;
          notifyListeners();
        }
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

  OrderModel createOrder({
    String? restaurantId,
    required String restaurantName,
    required String restaurantAddress,
    required List<OrderItem> items,
    required String deliveryAddress,
    required String paymentMethod,
    required int deliveryFee,
    String restaurantEmoji = '🏪',
    int discount = 0,
    double? restaurantLat,
    double? restaurantLng,
    double? userLat,
    double? userLng,
  }) {
    final tempId = 'SP-${(DateTime.now().millisecondsSinceEpoch % 10000).toString().padLeft(4, '0')}';
    final newOrder = OrderModel(
      id: tempId,
      restaurantName: restaurantName,
      restaurantAddress: restaurantAddress,
      restaurantEmoji: restaurantEmoji,
      items: List.from(items),
      deliveryFee: deliveryFee,
      discount: discount,
      paymentMethod: paymentMethod,
      deliveryAddress: deliveryAddress,
      status: OrderStatus.preparing,
      createdAt: DateTime.now(),
      estimatedDeliveryMinutes: 25,
      restaurantLat: restaurantLat,
      restaurantLng: restaurantLng,
      userLat: userLat,
      userLng: userLng,
      shipper: ShipperInfo(
        name: 'Nguyễn Văn Hùng',
        phone: '0987.654.321',
        rating: 4.9,
        bikePlate: '29-B1 888.66',
        bikeType: 'Honda Wave Alpha',
      ),
    );

    _orders.insert(0, newOrder);
    notifyListeners();

    OrderApiService().createDirectOrder(
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      restaurantAddress: restaurantAddress,
      deliveryAddress: deliveryAddress,
      paymentMethod: paymentMethod,
      deliveryFee: deliveryFee,
      userLat: userLat,
      userLng: userLng,
      restaurantLat: restaurantLat,
      restaurantLng: restaurantLng,
      items: items,
    ).then((savedOrder) {
      if (savedOrder != null) {
        final idx = _orders.indexWhere((o) => o.id == tempId);
        if (idx != -1) {
          // Lưu dữ liệu thật từ DB đồng thời giữ tempId để màn hình theo dõi không bị mất
          _orders[idx] = OrderModel(
            id: tempId,
            backendId: savedOrder.backendId ?? savedOrder.id,
            orderCode: savedOrder.orderCode ?? tempId,
            restaurantName: savedOrder.restaurantName,
            restaurantAddress: savedOrder.restaurantAddress,
            restaurantEmoji: savedOrder.restaurantEmoji,
            items: savedOrder.items,
            deliveryFee: savedOrder.deliveryFee,
            discount: savedOrder.discount,
            paymentMethod: savedOrder.paymentMethod,
            deliveryAddress: savedOrder.deliveryAddress,
            status: savedOrder.status,
            createdAt: savedOrder.createdAt,
            estimatedDeliveryMinutes: savedOrder.estimatedDeliveryMinutes,
            shipper: savedOrder.shipper,
            review: savedOrder.review,
            restaurantLat: savedOrder.restaurantLat,
            restaurantLng: savedOrder.restaurantLng,
            userLat: savedOrder.userLat,
            userLng: savedOrder.userLng,
          );
          notifyListeners();
        }
      }
    }).catchError((e) {
      debugPrint('Lỗi lưu đơn hàng vào DB: $e');
    });

    return newOrder;
  }

  OrderModel reorder(OrderModel oldOrder) {
    final newId = 'SP-${(DateTime.now().millisecondsSinceEpoch % 10000).toString().padLeft(4, '0')}';
    final newOrder = OrderModel(
      id: newId,
      restaurantName: oldOrder.restaurantName,
      restaurantAddress: oldOrder.restaurantAddress,
      restaurantEmoji: oldOrder.restaurantEmoji,
      items: oldOrder.items.map((item) => OrderItem(
        id: item.id,
        name: item.name,
        price: item.price,
        quantity: item.quantity,
        emoji: item.emoji,
        note: item.note,
      )).toList(),
      deliveryFee: oldOrder.deliveryFee,
      discount: 0,
      paymentMethod: oldOrder.paymentMethod,
      deliveryAddress: oldOrder.deliveryAddress,
      status: OrderStatus.preparing,
      createdAt: DateTime.now(),
      estimatedDeliveryMinutes: 25,
      shipper: ShipperInfo(
        name: 'Nguyễn Văn Hùng',
        phone: '0987.654.321',
        rating: 4.9,
        bikePlate: '29-B1 888.66',
        bikeType: 'Honda Wave Alpha',
      ),
    );

    _orders.insert(0, newOrder);
    notifyListeners();
    return newOrder;
  }

  void submitReview(String orderId, ReviewModel review) {
    final order = findById(orderId);
    if (order == null) return;

    order.review = review;
    notifyListeners();

    OrderApiService().submitReview(
      orderId: orderId,
      restaurantRating: review.restaurantRating,
      shipperRating: review.shipperRating,
      comment: review.restaurantComment.isNotEmpty
          ? review.restaurantComment
          : (review.shipperComment.isNotEmpty ? review.shipperComment : 'Đánh giá món ăn'),
    ).then((success) {
      if (success) {
        debugPrint('OrderData: Gửi đánh giá lên Backend thành công ($orderId)');
      }
    });
  }
}
