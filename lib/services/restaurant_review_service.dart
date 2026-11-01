import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'profile_api_service.dart';
import 'package:http/http.dart' as http;

class RestaurantReviewItem {
  final String id;
  final String orderId;
  final String restaurantId;
  final String restaurantName;
  final String customerName;
  final String customerAvatar;
  final int rating;
  final List<String> tags;
  final String comment;
  final List<String> dishNames;
  final DateTime createdAt;

  RestaurantReviewItem({
    required this.id,
    required this.orderId,
    required this.restaurantId,
    required this.restaurantName,
    required this.customerName,
    this.customerAvatar = '',
    required this.rating,
    this.tags = const [],
    required this.comment,
    this.dishNames = const [],
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'orderId': orderId,
        'restaurantId': restaurantId,
        'restaurantName': restaurantName,
        'customerName': customerName,
        'customerAvatar': customerAvatar,
        'rating': rating,
        'tags': tags,
        'comment': comment,
        'dishNames': dishNames,
        'createdAt': createdAt.toIso8601String(),
      };

  factory RestaurantReviewItem.fromJson(Map<String, dynamic> json) {
    var dishes = (json['dishNames'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    if (dishes.isEmpty) {
      final summary = json['orderItemsSummary']?.toString() ?? json['OrderItemsSummary']?.toString() ?? '';
      if (summary.isNotEmpty) {
        dishes = summary.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      }
    }
    return RestaurantReviewItem(
      id: json['id']?.toString() ?? json['Id']?.toString() ?? '',
      orderId: json['orderId']?.toString() ?? json['OrderId']?.toString() ?? '',
      restaurantId: json['restaurantId']?.toString() ?? json['RestaurantId']?.toString() ?? '',
      restaurantName: json['restaurantName']?.toString() ?? json['RestaurantName']?.toString() ?? 'Nhà hàng',
      customerName: json['customerName']?.toString() ?? json['CustomerName']?.toString() ?? 'Khách hàng SOOPI',
      customerAvatar: json['customerAvatar']?.toString() ?? '',
      rating: (json['rating'] as num?)?.toInt() ??
          (json['Rating'] as num?)?.toInt() ??
          (json['restaurantRating'] as num?)?.toInt() ??
          5,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          (json['Tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          (json['restaurantTags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          [],
      comment: json['comment']?.toString() ??
          json['Comment']?.toString() ??
          json['restaurantComment']?.toString() ??
          '',
      dishNames: dishes,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class RestaurantReviewService {
  static final RestaurantReviewService _instance = RestaurantReviewService._internal();
  factory RestaurantReviewService() => _instance;
  RestaurantReviewService._internal();

  static const String globalReviewsKey = 'soopi.restaurant_reviews.global';

  /// Chuẩn hóa tên quán để so sánh không phân biệt hoa thường và tiền tố quán ăn/nhà hàng
  static String normalizeShopName(String name) {
    var s = name.toLowerCase().trim();
    s = s
        .replaceAll('nhà hàng', '')
        .replaceAll('quán ăn', '')
        .replaceAll('quán', '')
        .replaceAll('tiệm', '')
        .trim();
    return s;
  }

  /// So khớp linh hoạt tên quán ăn (ví dụ "soopi" khớp "Nhà hàng SOOPI", "SOOPI FOOD")
  static bool isNameMatch(String name1, String name2) {
    final n1 = normalizeShopName(name1);
    final n2 = normalizeShopName(name2);
    if (n1.isEmpty || n2.isEmpty) return false;
    if (n1 == n2) return true;
    if (n1.contains(n2) || n2.contains(n1)) return true;
    if (n1.contains('soopi') && n2.contains('soopi')) return true;
    return false;
  }

  String _getKey(String restaurantId, String restaurantName) {
    final cleanId = restaurantId.trim();
    if (cleanId.isNotEmpty) return 'soopi.restaurant_reviews.$cleanId';
    return 'soopi.restaurant_reviews.${restaurantName.trim().toLowerCase()}';
  }

  /// Lấy danh sách đánh giá của quán ăn từ backend và local persistent storage
  Future<List<RestaurantReviewItem>> getReviews({
    required String restaurantId,
    required String restaurantName,
  }) async {
    final reviews = <RestaurantReviewItem>[];

    // 1. Thử lấy từ Backend API
    try {
      final baseUrl = ProfileApiService().baseUrl;
      final uri = Uri.parse('$baseUrl/restaurants/$restaurantId/reviews');
      final res = await http.get(uri, headers: {'bypass-tunnel-reminder': 'true'}).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(utf8.decode(res.bodyBytes));
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            reviews.add(RestaurantReviewItem.fromJson(item));
          }
        }
      }
    } catch (_) {}

    // 2. Lấy từ Persistent Storage đã lưu trên thiết bị
    try {
      final prefs = await SharedPreferences.getInstance();

      // a. Quét kho toàn cục (Global Storage)
      final rawGlobal = prefs.getString(globalReviewsKey);
      if (rawGlobal != null && rawGlobal.isNotEmpty) {
        final List<dynamic> list = jsonDecode(rawGlobal);
        for (final it in list) {
          final rev = RestaurantReviewItem.fromJson(Map<String, dynamic>.from(it as Map));
          final isSameShop = (restaurantId.isNotEmpty && rev.restaurantId == restaurantId) ||
              isNameMatch(rev.restaurantName, restaurantName);
          if (isSameShop) {
            if (!reviews.any((r) => r.id == rev.id || (r.orderId.isNotEmpty && r.orderId == rev.orderId))) {
              reviews.add(rev);
            }
          }
        }
      }

      // b. Quét theo key ID
      final key1 = _getKey(restaurantId, restaurantName);
      final raw1 = prefs.getString(key1);
      if (raw1 != null && raw1.isNotEmpty) {
        final List<dynamic> list = jsonDecode(raw1);
        for (final it in list) {
          final rev = RestaurantReviewItem.fromJson(Map<String, dynamic>.from(it as Map));
          if (!reviews.any((r) => r.id == rev.id || (r.orderId.isNotEmpty && r.orderId == rev.orderId))) {
            reviews.add(rev);
          }
        }
      }

      // c. Quét theo tên quán
      final key2 = 'soopi.restaurant_reviews.${restaurantName.trim().toLowerCase()}';
      if (key2 != key1) {
        final raw2 = prefs.getString(key2);
        if (raw2 != null && raw2.isNotEmpty) {
          final List<dynamic> list2 = jsonDecode(raw2);
          for (final it in list2) {
            final rev = RestaurantReviewItem.fromJson(Map<String, dynamic>.from(it as Map));
            if (!reviews.any((r) => r.id == rev.id || (r.orderId.isNotEmpty && r.orderId == rev.orderId))) {
              reviews.add(rev);
            }
          }
        }
      }

      // d. Quét theo tên quán đã chuẩn hóa
      final normName = normalizeShopName(restaurantName);
      final keyNorm = 'soopi.restaurant_reviews.$normName';
      if (keyNorm != key1 && keyNorm != key2) {
        final rawNorm = prefs.getString(keyNorm);
        if (rawNorm != null && rawNorm.isNotEmpty) {
          final List<dynamic> listNorm = jsonDecode(rawNorm);
          for (final it in listNorm) {
            final rev = RestaurantReviewItem.fromJson(Map<String, dynamic>.from(it as Map));
            if (!reviews.any((r) => r.id == rev.id || (r.orderId.isNotEmpty && r.orderId == rev.orderId))) {
              reviews.add(rev);
            }
          }
        }
      }

      // e. Quét tất cả các key SharedPreferences soopi.order_review.*
      final allKeys = prefs.getKeys();
      for (final k in allKeys) {
        if (k.startsWith('soopi.order_review.')) {
          final rawOrderRev = prefs.getString(k);
          if (rawOrderRev != null && rawOrderRev.isNotEmpty) {
            try {
              final json = jsonDecode(rawOrderRev) as Map<String, dynamic>;
              final rRating = (json['restaurantRating'] as num?)?.toInt() ?? 0;
              final orderId = k.substring('soopi.order_review.'.length);
              if (rRating > 0 && !reviews.any((r) => r.orderId == orderId)) {
                reviews.add(
                  RestaurantReviewItem(
                    id: 'rev_$orderId',
                    orderId: orderId,
                    restaurantId: restaurantId,
                    restaurantName: restaurantName,
                    customerName: 'Khách hàng SOOPI',
                    rating: rRating,
                    tags: (json['restaurantTags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
                    comment: json['restaurantComment']?.toString() ?? '',
                    dishNames: [],
                    createdAt: json['createdAt'] != null
                        ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
                        : DateTime.now(),
                  ),
                );
              }
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[RestaurantReviewService] Lỗi đọc reviews local: $e');
    }

    // Sắp xếp mới nhất lên đầu
    reviews.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return reviews;
  }

  /// Ghi nhận và lưu đánh giá mới của khách hàng vào quán ăn
  Future<void> addReview({
    required String orderId,
    required String restaurantId,
    required String restaurantName,
    required String customerName,
    String customerAvatar = '',
    required int rating,
    List<String> tags = const [],
    required String comment,
    List<String> dishNames = const [],
  }) async {
    final newReview = RestaurantReviewItem(
      id: 'rev_${DateTime.now().millisecondsSinceEpoch}',
      orderId: orderId,
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      customerName: customerName.isNotEmpty ? customerName : 'Khách hàng SOOPI',
      customerAvatar: customerAvatar,
      rating: rating,
      tags: tags,
      comment: comment,
      dishNames: dishNames,
      createdAt: DateTime.now(),
    );

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Lưu vào kho toàn cục (Global Storage)
      final rawGlobal = prefs.getString(globalReviewsKey);
      final List<dynamic> globalList = (rawGlobal != null && rawGlobal.isNotEmpty)
          ? (jsonDecode(rawGlobal) as List)
          : [];
      globalList.removeWhere((item) => item['orderId'] == orderId);
      globalList.insert(0, newReview.toJson());
      await prefs.setString(globalReviewsKey, jsonEncode(globalList));

      // 2. Lưu theo restaurantId nếu có
      if (restaurantId.trim().isNotEmpty) {
        final keyId = 'soopi.restaurant_reviews.${restaurantId.trim()}';
        final raw = prefs.getString(keyId);
        final list = (raw != null && raw.isNotEmpty) ? (jsonDecode(raw) as List) : [];
        list.removeWhere((item) => item['orderId'] == orderId);
        list.insert(0, newReview.toJson());
        await prefs.setString(keyId, jsonEncode(list));
      }

      // 3. Lưu theo tên quán thô
      if (restaurantName.trim().isNotEmpty) {
        final keyName = 'soopi.restaurant_reviews.${restaurantName.trim().toLowerCase()}';
        final raw = prefs.getString(keyName);
        final list = (raw != null && raw.isNotEmpty) ? (jsonDecode(raw) as List) : [];
        list.removeWhere((item) => item['orderId'] == orderId);
        list.insert(0, newReview.toJson());
        await prefs.setString(keyName, jsonEncode(list));

        // 4. Lưu theo tên quán chuẩn hóa
        final norm = normalizeShopName(restaurantName);
        if (norm.isNotEmpty) {
          final keyNorm = 'soopi.restaurant_reviews.$norm';
          final rawN = prefs.getString(keyNorm);
          final listN = (rawN != null && rawN.isNotEmpty) ? (jsonDecode(rawN) as List) : [];
          listN.removeWhere((item) => item['orderId'] == orderId);
          listN.insert(0, newReview.toJson());
          await prefs.setString(keyNorm, jsonEncode(listN));
        }
      }

      debugPrint('[RestaurantReviewService] Đã lưu đánh giá cho quán "$restaurantName": $comment');
    } catch (e) {
      debugPrint('[RestaurantReviewService] Lỗi lưu review quán: $e');
    }
  }
}
