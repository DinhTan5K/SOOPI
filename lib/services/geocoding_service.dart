import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/user_address.dart';

class ReverseGeocodeResult {
  final String displayName;
  final String street;
  final String ward;
  final String district;
  final String city;
  final double latitude;
  final double longitude;

  const ReverseGeocodeResult({
    required this.displayName,
    this.street = '',
    this.ward = '',
    this.district = '',
    this.city = '',
    required this.latitude,
    required this.longitude,
  });
}

class NearestSavedAddressMatch {
  final UserAddress address;
  final double latitude;
  final double longitude;
  final double distanceMeters;

  const NearestSavedAddressMatch({
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
  });
}

class GeocodingService {
  static final Map<String, LatLng> _forwardCache = {};
  static final Map<String, ReverseGeocodeResult> _reverseCache = {};

  /// Kiểm tra xem chuỗi địa chỉ có phải là chuỗi tọa độ GPS thô hoặc placeholder chưa rõ ràng không.
  static bool isRawCoordinateAddress(String? address) {
    if (address == null) return true;
    final trimmed = address.trim();
    if (trimmed.isEmpty) return true;
    final lower = trimmed.toLowerCase();
    if (lower == 'chưa chọn địa chỉ giao hàng' ||
        lower == 'địa chỉ nhận hàng của bạn' ||
        lower == 'địa chỉ nhận hàng mặc định' ||
        lower == 'điểm nhận hàng' ||
        lower.startsWith('vị trí gps') ||
        lower.startsWith('tọa độ')) {
      return true;
    }
    // Kiểm tra dạng "(10.776, 106.701)" hoặc "10.776, 106.701"
    final coordPattern = RegExp(r'^\(?-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?\)?$');
    if (coordPattern.hasMatch(trimmed)) return true;
    return false;
  }

  /// Trích xuất tọa độ từ chuỗi dạng "Vị trí GPS (10.776, 106.701)" nếu có.
  static LatLng? extractCoordinatesFromRawAddress(String? address) {
    if (address == null || address.trim().isEmpty) return null;
    final match = RegExp(r'(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)').firstMatch(address);
    if (match != null) {
      final lat = double.tryParse(match.group(1)!);
      final lng = double.tryParse(match.group(2)!);
      if (lat != null && lng != null && lat != 0 && lng != 0) {
        return LatLng(lat, lng);
      }
    }
    return null;
  }

  /// Tính khoảng cách Haversine (km) giữa 2 tọa độ.
  static double calculateDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const p = 0.017453292519943295; // pi / 180
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  /// Tìm địa chỉ đã lưu trong sổ địa chỉ gần với vị trí GPS nhất (mặc định trong bán kính 150m).
  static Future<NearestSavedAddressMatch?> findNearestSavedAddress(
    double lat,
    double lng,
    List<UserAddress> savedAddresses, {
    double maxDistanceMeters = 150,
  }) async {
    if (savedAddresses.isEmpty) return null;

    NearestSavedAddressMatch? bestMatch;

    for (final addr in savedAddresses) {
      final fullAddr = addr.fullAddress.trim();
      if (fullAddr.isEmpty || isRawCoordinateAddress(fullAddr)) continue;

      final coords = await getCoordinatesFromAddress(fullAddr);

      if (coords == null) continue;

      final distKm = calculateDistanceKm(lat, lng, coords.latitude, coords.longitude);
      final distMeters = distKm * 1000;

      if (distMeters <= maxDistanceMeters) {
        if (bestMatch == null || distMeters < bestMatch.distanceMeters) {
          bestMatch = NearestSavedAddressMatch(
            address: addr,
            latitude: coords.latitude,
            longitude: coords.longitude,
            distanceMeters: distMeters,
          );
        }
      }
    }

    return bestMatch;
  }

  /// Chuyển đổi tọa độ GPS (lat, lng) thành địa chỉ cụ thể (Reverse Geocoding).
  /// Kết hợp:
  /// 1. OpenStreetMap Nominatim (ưu tiên tiếng Việt chi tiết số nhà, đường, phường, quận, TP)
  /// 2. Photon Komoot API (tốc độ cao, dữ liệu POI/đường phố)
  /// 3. Tính toán địa chỉ khu vực gần nhất nếu ngoại tuyến hoặc khu vực chưa có tên đường
  static Future<ReverseGeocodeResult> reverseGeocodeResult(
    double lat,
    double lng,
  ) async {
    final cacheKey = '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';
    if (_reverseCache.containsKey(cacheKey)) {
      return _reverseCache[cacheKey]!;
    }

    ReverseGeocodeResult? photonResult;
    ReverseGeocodeResult? nominatimResult;

    // 1. Thử Nominatim OpenStreetMap với ngôn ngữ tiếng Việt để lấy số nhà, đường, phường, quận chuẩn xác
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': lat.toString(),
        'lon': lng.toString(),
        'zoom': '18',
        'addressdetails': '1',
        'accept-language': 'vi',
      });

      final response = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'SoopiFood/1.0 (reverse-geocoding-vi)',
            },
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        nominatimResult = _parseNominatimReverse(payload, lat, lng);
      }
    } catch (e) {
      debugPrint('Nominatim reverse geocode error: $e');
    }

    if (nominatimResult != null &&
        nominatimResult.displayName.isNotEmpty &&
        nominatimResult.street.isNotEmpty) {
      _reverseCache[cacheKey] = nominatimResult;
      _forwardCache[nominatimResult.displayName.toLowerCase()] = LatLng(lat, lng);
      return nominatimResult;
    }

    // 2. Thử Photon Komoot Reverse API
    try {
      final uri = Uri.https('photon.komoot.io', '/reverse', {
        'lat': lat.toString(),
        'lon': lng.toString(),
      });

      final response = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'SoopiFood/1.0 (photon-reverse-geocoding)',
            },
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        final features = payload['features'] as List<dynamic>? ?? [];
        if (features.isNotEmpty) {
          photonResult = _parsePhotonFeature(
            features.first as Map<String, dynamic>,
            lat,
            lng,
          );
        }
      }
    } catch (e) {
      debugPrint('Photon reverse geocode error: $e');
    }

    // Chọn kết quả chi tiết hơn giữa Nominatim và Photon
    if (photonResult != null && photonResult.displayName.isNotEmpty) {
      if (nominatimResult != null &&
          nominatimResult.displayName.length > photonResult.displayName.length) {
        _reverseCache[cacheKey] = nominatimResult;
        return nominatimResult;
      }
      _reverseCache[cacheKey] = photonResult;
      _forwardCache[photonResult.displayName.toLowerCase()] = LatLng(lat, lng);
      return photonResult;
    }

    if (nominatimResult != null && nominatimResult.displayName.isNotEmpty) {
      _reverseCache[cacheKey] = nominatimResult;
      return nominatimResult;
    }

    // 3. Fallback: Tìm địa điểm/tuyến đường thực tế gần nhất trong bán kính 2km trên OpenStreetMap (Photon)
    try {
      final uri = Uri.https('photon.komoot.io', '/reverse', {
        'lat': lat.toString(),
        'lon': lng.toString(),
        'radius': '2',
        'limit': '1',
      });
      final response = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'SoopiFood/1.0 (photon-nearby-reverse)',
            },
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        final features = payload['features'] as List<dynamic>? ?? [];
        if (features.isNotEmpty) {
          final nearbyResult = _parsePhotonFeature(
            features.first as Map<String, dynamic>,
            lat,
            lng,
          );
          if (nearbyResult != null && nearbyResult.displayName.isNotEmpty) {
            _reverseCache[cacheKey] = nearbyResult;
            return nearbyResult;
          }
        }
      }
    } catch (_) {}

    return ReverseGeocodeResult(
      displayName: '',
      latitude: lat,
      longitude: lng,
    );
  }

  /// Trả về chuỗi địa chỉ cụ thể từ tọa độ (lat, lng).
  static Future<String> reverseGeocode(double lat, double lng) async {
    final res = await reverseGeocodeResult(lat, lng);
    return res.displayName;
  }

  static ReverseGeocodeResult? _parseNominatimReverse(
    Map<String, dynamic> payload,
    double lat,
    double lng,
  ) {
    final addr = payload['address'] as Map<String, dynamic>? ?? {};
    final poiName = payload['name']?.toString().trim() ?? '';
    final houseNumber = addr['house_number']?.toString().trim() ?? '';
    final road = (addr['road'] ??
            addr['pedestrian'] ??
            addr['street'] ??
            addr['residential'] ??
            '')
        .toString()
        .trim();

    final ward = (addr['suburb'] ??
            addr['quarter'] ??
            addr['neighbourhood'] ??
            addr['village'] ??
            addr['town'] ??
            '')
        .toString()
        .trim();

    final district = (addr['city_district'] ??
            addr['district'] ??
            addr['county'] ??
            addr['municipality'] ??
            '')
        .toString()
        .trim();

    final city = (addr['city'] ?? addr['state'] ?? addr['province'] ?? '')
        .toString()
        .trim();

    final streetPart = [houseNumber, road]
        .where((s) => s.isNotEmpty)
        .join(' ')
        .trim();

    final parts = <String>[];
    if (poiName.isNotEmpty &&
        poiName.toLowerCase() != road.toLowerCase() &&
        poiName.toLowerCase() != ward.toLowerCase()) {
      parts.add(poiName);
    }
    if (streetPart.isNotEmpty) {
      parts.add(streetPart);
    }
    if (ward.isNotEmpty && !parts.any((p) => p.toLowerCase() == ward.toLowerCase())) {
      parts.add(ward);
    }
    if (district.isNotEmpty &&
        !parts.any((p) => p.toLowerCase() == district.toLowerCase())) {
      parts.add(district);
    }
    if (city.isNotEmpty && !parts.any((p) => p.toLowerCase() == city.toLowerCase())) {
      parts.add(city);
    }

    var displayName = parts.join(', ');
    if (displayName.isEmpty) {
      final rawDisplay = payload['display_name']?.toString().trim() ?? '';
      if (rawDisplay.isNotEmpty) {
        // Loại bỏ mã bưu chính và tên quốc gia ở cuối để gọn đẹp hơn
        final segments = rawDisplay
            .split(',')
            .map((s) => s.trim())
            .where((s) =>
                s.isNotEmpty &&
                !RegExp(r'^\d{5,6}$').hasMatch(s) &&
                s.toLowerCase() != 'việt nam' &&
                s.toLowerCase() != 'vietnam')
            .toList();
        displayName = segments.join(', ');
      }
    }

    if (displayName.isEmpty) return null;

    return ReverseGeocodeResult(
      displayName: displayName,
      street: streetPart.isNotEmpty ? streetPart : poiName,
      ward: ward,
      district: district,
      city: city,
      latitude: lat,
      longitude: lng,
    );
  }

  static ReverseGeocodeResult? _parsePhotonFeature(
    Map<String, dynamic> feature,
    double fallbackLat,
    double fallbackLng,
  ) {
    final properties = feature['properties'] as Map<String, dynamic>? ?? {};
    final name = properties['name']?.toString().trim() ?? '';
    final houseNumber = properties['housenumber']?.toString().trim() ?? '';
    final road = properties['street']?.toString().trim() ?? '';
    final street = [houseNumber, road].where((s) => s.isNotEmpty).join(' ').trim();
    final ward = (properties['locality'] ?? properties['suburb'] ?? '')
        .toString()
        .trim();
    final district = (properties['district'] ?? properties['county'] ?? '')
        .toString()
        .trim();
    final city = (properties['city'] ?? properties['state'] ?? '')
        .toString()
        .trim();

    final parts = <String>[];
    if (name.isNotEmpty && name.toLowerCase() != road.toLowerCase()) {
      parts.add(name);
    }
    if (street.isNotEmpty) {
      parts.add(street);
    }
    if (ward.isNotEmpty && !parts.any((p) => p.toLowerCase() == ward.toLowerCase())) {
      parts.add(ward);
    }
    if (district.isNotEmpty &&
        !parts.any((p) => p.toLowerCase() == district.toLowerCase())) {
      parts.add(district);
    }
    if (city.isNotEmpty && !parts.any((p) => p.toLowerCase() == city.toLowerCase())) {
      parts.add(city);
    }

    final displayName = parts.join(', ');
    if (displayName.isEmpty) return null;

    return ReverseGeocodeResult(
      displayName: displayName,
      street: street.isNotEmpty ? street : name,
      ward: ward,
      district: district,
      city: city,
      latitude: fallbackLat,
      longitude: fallbackLng,
    );
  }

  /// Chuyển đổi chuỗi địa chỉ bất kỳ thành tọa độ GPS (LatLng).
  /// Sử dụng API photon.komoot.io và Nominatim (OpenStreetMap) với timeout và cache bộ nhớ.
  static Future<LatLng?> getCoordinatesFromAddress(String address) async {
    final cleanQuery = address.trim();
    if (cleanQuery.isEmpty) return null;

    // Nếu chuỗi truyền vào chứa sẵn tọa độ (vd: "Vị trí GPS (10.77, 106.70)"), bóc tách ngay
    final extracted = extractCoordinatesFromRawAddress(cleanQuery);
    if (extracted != null) return extracted;

    final normalizedQuery = cleanQuery
        .replaceFirst(RegExp(r'^Khu vực gần\s+', caseSensitive: false), '')
        .trim();

    if (_forwardCache.containsKey(normalizedQuery.toLowerCase())) {
      return _forwardCache[normalizedQuery.toLowerCase()];
    }

    try {
      final uri = Uri.https('photon.komoot.io', '/api/', {
        'q': normalizedQuery,
        'limit': '1',
        'countrycode': 'VN',
      });

      final response = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'SoopiFood/1.0 (geocoding-service)',
            },
          )
          .timeout(const Duration(seconds: 6));

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
            _forwardCache[normalizedQuery.toLowerCase()] = result;
            return result;
          }
        }
      }
    } catch (e) {
      debugPrint('Geocoding error for "$normalizedQuery": $e');
    }

    // Fallback 1: Thử tìm với Nominatim OpenStreetMap
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': normalizedQuery,
        'format': 'jsonv2',
        'limit': '1',
        'countrycodes': 'vn',
      });
      final response = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'SoopiFood/1.0 (nominatim-forward-geocoding)',
            },
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List<dynamic>;
        if (list.isNotEmpty) {
          final first = list.first as Map<String, dynamic>;
          final lat = double.tryParse(first['lat']?.toString() ?? '');
          final lon = double.tryParse(first['lon']?.toString() ?? '');
          if (lat != null && lon != null) {
            final result = LatLng(lat, lon);
            _forwardCache[normalizedQuery.toLowerCase()] = result;
            return result;
          }
        }
      }
    } catch (_) {}

    // Fallback 2: Nếu chuỗi quá dài, thử tìm với phần đầu + phần cuối địa chỉ
    try {
      final parts = normalizedQuery.split(',');
      if (parts.length > 1) {
        final shortenedQuery = '${parts.first.trim()}, ${parts.last.trim()}';
        final uri = Uri.https('photon.komoot.io', '/api/', {
          'q': shortenedQuery,
          'limit': '1',
          'countrycode': 'VN',
        });
        final response = await http
            .get(
              uri,
              headers: {
                'Accept': 'application/json',
                'User-Agent': 'SoopiFood/1.0 (geocoding-service-shortened)',
              },
            )
            .timeout(const Duration(seconds: 5));

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
              _forwardCache[normalizedQuery.toLowerCase()] = result;
              return result;
            }
          }
        }
      }
    } catch (_) {}

    return null;
  }
}
