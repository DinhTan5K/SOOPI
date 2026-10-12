import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiMenuItem {
  final String id;
  final String name;
  final String description;
  final double price;
  final String? imageUrl;
  final bool isAvailable;

  ApiMenuItem({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    this.imageUrl,
    required this.isAvailable,
  });

  factory ApiMenuItem.fromJson(Map<String, dynamic> json) {
    return ApiMenuItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      imageUrl: json['imageUrl']?.toString(),
      isAvailable: json['isAvailable'] as bool? ?? true,
    );
  }
}

class ApiMenuCategory {
  final String id;
  final String name;
  final List<ApiMenuItem> items;

  ApiMenuCategory({
    required this.id,
    required this.name,
    required this.items,
  });

  factory ApiMenuCategory.fromJson(Map<String, dynamic> json) {
    var rawItems = json['items'] as List<dynamic>? ?? [];
    return ApiMenuCategory(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      items: rawItems.map((e) => ApiMenuItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class ApiRestaurant {
  final String id;
  final String name;
  final String description;
  final String phone;
  final String address;
  final String city;
  final String? imageUrl;
  final double? latitude;
  final double? longitude;
  final double averageRating;
  final bool isActive;
  final bool isAcceptingOrders;
  final List<ApiMenuCategory> categories;

  ApiRestaurant({
    required this.id,
    required this.name,
    required this.description,
    required this.phone,
    required this.address,
    required this.city,
    this.imageUrl,
    this.latitude,
    this.longitude,
    required this.averageRating,
    required this.isActive,
    required this.isAcceptingOrders,
    required this.categories,
  });

  factory ApiRestaurant.fromJson(Map<String, dynamic> json) {
    var rawCats = json['categories'] as List<dynamic>? ?? [];
    return ApiRestaurant(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      averageRating: (json['averageRating'] as num?)?.toDouble() ?? 0.0,
      isActive: json['isActive'] as bool? ?? true,
      isAcceptingOrders: json['isAcceptingOrders'] as bool? ?? true,
      categories: rawCats.map((e) => ApiMenuCategory.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class ApiService {
  // Thay đổi IP host ở đây nếu chạy thiết bị thật hoặc port khác
  static String get baseUrl {
    if (kIsWeb) return 'http://localhost:5194/api';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5194/api';
    }
    return 'http://localhost:5194/api';
  }

  /// TÌM KIẾM & DUYỆT NHÀ HÀNG / MÓN ĂN VỚI TỌA ĐỘ VỊ TRÍ GIAO HÀNG (UC03)
  static Future<List<ApiRestaurant>> searchRestaurants({
    String? query,
    String? category,
    double? minRating,
    double? lat,
    double? lng,
    double? radiusKm,
  }) async {
    final queryParams = <String, String>{};
    if (query != null && query.trim().isNotEmpty) {
      queryParams['q'] = query.trim();
    }
    if (category != null && category.trim().isNotEmpty && category != 'Tất cả') {
      queryParams['category'] = category.trim();
    }
    if (minRating != null && minRating > 0) {
      queryParams['minRating'] = minRating.toString();
    }
    if (lat != null && lng != null) {
      queryParams['lat'] = lat.toString();
      queryParams['lng'] = lng.toString();
    }
    if (radiusKm != null && radiusKm > 0) {
      queryParams['radiusKm'] = radiusKm.toString();
    }

    final uri = Uri.parse('$baseUrl/restaurants').replace(queryParameters: queryParams.isEmpty ? null : queryParams);

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final List<dynamic> list = jsonDecode(response.body);
        return list.map((e) => ApiRestaurant.fromJson(e as Map<String, dynamic>)).toList();
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error searchRestaurants: $e');
      rethrow;
    }
  }

  /// LẤY CHI TIẾT NHÀ HÀNG & THỰC ĐƠN
  static Future<ApiRestaurant?> getRestaurant(String id) async {
    final uri = Uri.parse('$baseUrl/restaurants/$id');
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return ApiRestaurant.fromJson(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      debugPrint('Error getRestaurant: $e');
      return null;
    }
  }

  /// LẤY DANH SÁCH MÓN ĂN CỦA NHÀ HÀNG
  static Future<List<ApiMenuItem>> getRestaurantMenu(String restaurantId) async {
    final uri = Uri.parse('$baseUrl/restaurants/$restaurantId/menu');
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final List<dynamic> list = jsonDecode(response.body);
        return list.map((e) => ApiMenuItem.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error getRestaurantMenu: $e');
      return [];
    }
  }

  /// TỰ ĐỘNG ĐỊNH VỊ THÀNH PHỐ VÀ TỌA ĐỘ THEO MẠNG INTERNET/IP CỦA MÁY TÍNH (HTTPS)
  static Future<Map<String, dynamic>?> getIpLocation() async {
    try {
      final response = await http
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error getIpLocation ipapi.co: $e');
    }

    try {
      final response = await http
          .get(Uri.parse('http://ip-api.com/json'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error getIpLocation ip-api.com: $e');
    }
    return null;
  }
}
