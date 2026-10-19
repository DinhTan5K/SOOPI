import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class GeocodingService {
  static final Map<String, LatLng> _cache = {};

  /// Chuyển đổi chuỗi địa chỉ bất kỳ thành tọa độ GPS (LatLng).
  /// Sử dụng API photon.komoot.io (OpenStreetMap) với timeout và cache bộ nhớ.
  static Future<LatLng?> getCoordinatesFromAddress(String address) async {
    final cleanQuery = address.trim();
    if (cleanQuery.isEmpty) return null;

    if (_cache.containsKey(cleanQuery.toLowerCase())) {
      return _cache[cleanQuery.toLowerCase()];
    }

    try {
      final uri = Uri.https('photon.komoot.io', '/api/', {
        'q': cleanQuery,
        'limit': '1',
        'countrycode': 'VN',
      });

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'SoopiFood/1.0 (geocoding-service)',
        },
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        final features = payload['features'] as List<dynamic>? ?? [];
        if (features.isNotEmpty) {
          final first = features.first as Map<String, dynamic>;
          final geom = first['geometry'] as Map<String, dynamic>?;
          final coords = geom?['coordinates'] as List<dynamic>?;
          if (coords != null && coords.length >= 2) {
            final lng = (coords[0] as num).toDouble();
            final lat = (coords[1] as num).toDouble();
            final result = LatLng(lat, lng);
            _cache[cleanQuery.toLowerCase()] = result;
            return result;
          }
        }
      }
    } catch (e) {
      debugPrint('Geocoding error for "$cleanQuery": $e');
    }

    // Fallback: nếu photon không tìm thấy với chuỗi quá dài, thử tìm với phần đầu địa chỉ (ví dụ: tên đường + quận/thành phố)
    try {
      final parts = cleanQuery.split(',');
      if (parts.length > 1) {
        final shortenedQuery = '${parts.first.trim()}, ${parts.last.trim()}';
        final uri = Uri.https('photon.komoot.io', '/api/', {
          'q': shortenedQuery,
          'limit': '1',
          'countrycode': 'VN',
        });
        final response = await http.get(
          uri,
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'SoopiFood/1.0 (geocoding-service-shortened)',
          },
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final payload = jsonDecode(response.body) as Map<String, dynamic>;
          final features = payload['features'] as List<dynamic>? ?? [];
          if (features.isNotEmpty) {
            final first = features.first as Map<String, dynamic>;
            final geom = first['geometry'] as Map<String, dynamic>?;
            final coords = geom?['coordinates'] as List<dynamic>?;
            if (coords != null && coords.length >= 2) {
              final lng = (coords[0] as num).toDouble();
              final lat = (coords[1] as num).toDouble();
              final result = LatLng(lat, lng);
              _cache[cleanQuery.toLowerCase()] = result;
              return result;
            }
          }
        }
      }
    } catch (_) {}

    return null;
  }
}
