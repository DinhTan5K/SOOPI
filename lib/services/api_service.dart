import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'profile_api_service.dart';
import 'api_config.dart';
import 'cloudinary_service.dart';

num? _getNum(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final val = json[key];
    if (val is num) return val;
    if (val != null) {
      final parsed = num.tryParse(val.toString());
      if (parsed != null) return parsed;
    }
  }
  return null;
}

bool? _getBool(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final val = json[key];
    if (val is bool) return val;
    if (val != null) {
      final str = val.toString().toLowerCase();
      if (str == 'true' || str == '1') return true;
      if (str == 'false' || str == '0') return false;
    }
  }
  return null;
}

String _getStr(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final val = json[key];
    if (val != null) return val.toString();
  }
  return '';
}

class ApiMenuItem {
  final String id;
  final String name;
  final String description;
  final double price;
  final double? originalPrice;
  final int? discountPercent;
  final String? imageUrl;
  final bool isAvailable;
  final int soldCount;
  final int likesCount;

  ApiMenuItem({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    this.originalPrice,
    this.discountPercent,
    this.imageUrl,
    required this.isAvailable,
    this.soldCount = 0,
    this.likesCount = 0,
  });

  factory ApiMenuItem.fromJson(Map<String, dynamic> json) {
    final id = _getStr(json, ['id', 'Id']);
    final price = _getNum(json, ['price', 'Price'])?.toDouble() ?? 0.0;
    final origPrice = _getNum(json, ['originalPrice', 'OriginalPrice', 'original_price'])?.toDouble();
    final discount = _getNum(json, ['discountPercent', 'DiscountPercent', 'discount_percent'])?.toInt();
    final imgUrlStr = _getStr(json, ['imageUrl', 'ImageUrl', 'image_url']);

    return ApiMenuItem(
      id: id,
      name: _getStr(json, ['name', 'Name']),
      description: _getStr(json, ['description', 'Description']),
      price: price,
      originalPrice: origPrice ?? (discount != null && discount > 0 ? price / (1 - discount / 100) : null),
      discountPercent: discount,
      imageUrl: imgUrlStr.isNotEmpty ? imgUrlStr : null,
      isAvailable: _getBool(json, ['isAvailable', 'IsAvailable', 'is_available']) ?? true,
      soldCount: _getNum(json, ['soldCount', 'SoldCount', 'sold_count'])?.toInt() ?? 0,
      likesCount: _getNum(json, ['likesCount', 'LikesCount', 'likes_count'])?.toInt() ?? 0,
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
    var rawItems = (json['items'] ?? json['Items']) as List<dynamic>? ?? [];
    return ApiMenuCategory(
      id: _getStr(json, ['id', 'Id']),
      name: _getStr(json, ['name', 'Name']),
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
  final int reviewCount;
  final int totalOrders;
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
    this.reviewCount = 0,
    this.totalOrders = 0,
    required this.isActive,
    required this.isAcceptingOrders,
    required this.categories,
  });

  factory ApiRestaurant.fromJson(Map<String, dynamic> json) {
    var rawCats = (json['categories'] ?? json['Categories']) as List<dynamic>? ?? [];
    final id = _getStr(json, ['id', 'Id']);
    final imgUrlStr = _getStr(json, ['imageUrl', 'ImageUrl', 'image_url']);

    return ApiRestaurant(
      id: id,
      name: _getStr(json, ['name', 'Name']),
      description: _getStr(json, ['description', 'Description']),
      phone: _getStr(json, ['phone', 'Phone']),
      address: _getStr(json, ['address', 'Address']),
      city: _getStr(json, ['city', 'City']),
      imageUrl: imgUrlStr.isNotEmpty ? imgUrlStr : null,
      latitude: _getNum(json, ['latitude', 'Latitude'])?.toDouble(),
      longitude: _getNum(json, ['longitude', 'Longitude'])?.toDouble(),
      averageRating: _getNum(json, ['averageRating', 'AverageRating', 'average_rating'])?.toDouble() ?? 0.0,
      reviewCount: _getNum(json, ['reviewCount', 'ReviewCount', 'review_count'])?.toInt() ?? 0,
      totalOrders: _getNum(json, ['totalOrders', 'TotalOrders', 'total_orders'])?.toInt() ?? 0,
      isActive: _getBool(json, ['isActive', 'IsActive', 'is_active']) ?? true,
      isAcceptingOrders: _getBool(json, ['isAcceptingOrders', 'IsAcceptingOrders', 'is_accepting_orders']) ?? true,
      categories: rawCats.map((e) => ApiMenuCategory.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class ApiService {
  static String get baseUrl => ProfileApiService().baseUrl;
  static set baseUrl(String value) => ProfileApiService().baseUrl = value;

  static List<String> get candidateBaseUrls => ProfileApiService.candidateBaseUrls;

  static Future<http.Response> _getWithFallback(String pathWithQuery, {Duration timeout = const Duration(seconds: 4)}) async {
    const headers = {'bypass-tunnel-reminder': 'true'};
    final primary = baseUrl;
    try {
      final uri = Uri.parse('$primary$pathWithQuery');
      return await http.get(uri, headers: headers).timeout(timeout);
    } catch (_) {
      for (final candidate in candidateBaseUrls) {
        if (candidate == primary) continue;
        try {
          final uri = Uri.parse('$candidate$pathWithQuery');
          final res = await http.get(uri, headers: headers).timeout(const Duration(milliseconds: 1800));
          if (res.statusCode == 200 || res.statusCode == 404) {
            baseUrl = candidate;
            return res;
          }
        } catch (_) {}
      }
      final detected = await ApiConfig().autoDetect();
      if (detected) {
        final uri = Uri.parse('$baseUrl$pathWithQuery');
        return await http.get(uri, headers: headers).timeout(timeout);
      }
      rethrow;
    }
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

    final pathWithQuery = Uri(
      path: '/restaurants',
      queryParameters: queryParams.isEmpty ? null : queryParams,
    ).toString();

    try {
      final response = await _getWithFallback(pathWithQuery, timeout: const Duration(seconds: 4));
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
    try {
      final response = await _getWithFallback('/restaurants/$id', timeout: const Duration(seconds: 4));
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
    try {
      final response = await _getWithFallback('/restaurants/$restaurantId/menu', timeout: const Duration(seconds: 4));
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

  /// UPLOAD ẢNH LÊN CLOUDINARY THÔNG QUA BACKEND HOẶC DIRECT CLOUDINARY
  static Future<String?> uploadImage(dynamic imageFile) async {
    return CloudinaryService().uploadImage(imageFile);
  }
}
