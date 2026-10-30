import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models/user_address.dart';
import 'order/order_data.dart';
import 'order/order_list_screen.dart';
import 'order/order_tracking_screen.dart';
import 'profile/profile_screen.dart';
import 'restaurant_detail_screen.dart';
import 'services/address_suggestion_service.dart';
import 'services/api_config.dart';
import 'services/api_service.dart';
import 'services/geocoding_service.dart';
import 'services/profile_api_service.dart';

class DeliveryLocationOption {
  final String label;
  final String address;
  final double latitude;
  final double longitude;

  DeliveryLocationOption({
    required this.label,
    required this.address,
    required this.latitude,
    required this.longitude,
  });
}

enum _AddressSheetAction { gps, customInput }

typedef _AddressSuggestion = AddressSuggestion;

class _DishDealItem {
  final ApiMenuItem item;
  final ApiRestaurant restaurant;

  _DishDealItem({required this.item, required this.restaurant});
}

class _PromoBannerItem {
  final String title;
  final String subtitle;
  final String code;
  final String badge;
  final List<Color> gradientColors;

  const _PromoBannerItem({
    required this.title,
    required this.subtitle,
    required this.code,
    required this.badge,
    required this.gradientColors,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final TextEditingController _searchController = TextEditingController();
  late final PageController _bannerController;
  int _currentBannerIndex = 0;
  Timer? _bannerTimer;

  List<ApiRestaurant> _restaurants = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedCategory = 'Tất cả';
  String _restaurantSort = 'relevance';
  bool _onlyOpen = false;

  // --- VỊ TRÍ GPS THỰC TẾ CỦA THIẾT BỊ ---
  double _currentGpsLat = 0;
  double _currentGpsLng = 0;
  bool _hasCurrentGps = false;
  bool _isLocatingGps = false;

  // --- ĐỊA CHỈ GIAO HÀNG ĐƯỢC CHỌN ĐỂ ĐẶT HÀNG ---
  String _selectedAddressName = 'Chưa chọn địa chỉ giao hàng';
  String _selectedAddressType = '';
  double _selectedLat = 0;
  double _selectedLng = 0;

  final List<_PromoBannerItem> _banners = const [
    _PromoBannerItem(
      title: 'Giảm 50% đơn đầu tiên',
      subtitle: 'Tối đa 50k • Toàn bộ menu quán',
      code: 'SOOPI50',
      badge: 'ƯU ĐÃI ĐỘC QUYỀN',
      gradientColors: [Color(0xFFFF5722), Color(0xFFFF9800)],
    ),
    _PromoBannerItem(
      title: 'Freeship mọi đơn từ 50K',
      subtitle: 'Giao nhanh 20 phút • Tiết kiệm tối đa',
      code: 'FREESHIP',
      badge: 'MIỄN PHÍ VẬN CHUYỂN',
      gradientColors: [Color(0xFF00897B), Color(0xFF26A69A)],
    ),
    _PromoBannerItem(
      title: 'Flash Sale giờ vàng trưa',
      subtitle: 'Đồng giá từ 25k • Áp dụng 11h - 13h30',
      code: 'GIOTRUA',
      badge: 'GIỜ VÀNG GIẢM SÂU',
      gradientColors: [Color(0xFF6A1B9A), Color(0xFFAB47BC)],
    ),
  ];

  final List<String> _trendingSearches = const [
    'Trà sữa',
    'Cơm tấm',
    'Burger',
    'Pizza',
    'Gà rán',
    'Healthy',
  ];

  @override
  void initState() {
    super.initState();
    _bannerController = PageController();
    _startBannerTimer();
    _restoreSavedAddress();
    _fetchData();
  }

  void _startBannerTimer() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_bannerController.hasClients) {
        final next = (_currentBannerIndex + 1) % _banners.length;
        _bannerController.animateToPage(
          next,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  String get _savedAddressKey =>
      'soopi.delivery_address.${FirebaseAuth.instance.currentUser?.uid ?? 'guest'}';

  static bool _isRawCoordinateAddress(String? address) {
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
    final coordPattern = RegExp(r'^\(?-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?\)?$');
    return coordPattern.hasMatch(trimmed);
  }

  Future<String> _reverseGeocode(double lat, double lng) async {
    // 1. Ưu tiên Nominatim OpenStreetMap tiếng Việt
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
              'User-Agent': 'SoopiFood/1.0 (home-reverse-geocoding)',
            },
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
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
        if (streetPart.isNotEmpty) parts.add(streetPart);
        if (ward.isNotEmpty &&
            !parts.any((p) => p.toLowerCase() == ward.toLowerCase())) {
          parts.add(ward);
        }
        if (district.isNotEmpty &&
            !parts.any((p) => p.toLowerCase() == district.toLowerCase())) {
          parts.add(district);
        }
        if (city.isNotEmpty &&
            !parts.any((p) => p.toLowerCase() == city.toLowerCase())) {
          parts.add(city);
        }
        final formatted = parts.join(', ');
        if (formatted.isNotEmpty) return formatted;
      }
    } catch (_) {}

    // 2. Fallback sang Photon Komoot Reverse API
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
              'User-Agent': 'SoopiFood/1.0 (photon-home-reverse)',
            },
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        final features = payload['features'] as List<dynamic>? ?? [];
        if (features.isNotEmpty) {
          final suggestion = _AddressSuggestion.fromJson(
            features.first as Map<String, dynamic>,
          );
          if (suggestion.displayName.isNotEmpty) {
            return suggestion.displayName;
          }
        }
      }
    } catch (_) {}

    return '';
  }

  Future<UserAddress?> _findNearestSavedAddress(
    double lat,
    double lng,
    List<UserAddress> savedAddresses, {
    double maxDistanceMeters = 120,
  }) async {
    UserAddress? best;
    double bestDistMeters = double.infinity;

    for (final addr in savedAddresses) {
      final fullAddr = addr.fullAddress.trim();
      if (fullAddr.isEmpty || _isRawCoordinateAddress(fullAddr)) continue;
      final coords = await GeocodingService.getCoordinatesFromAddress(fullAddr);
      if (coords == null) continue;
      final distMeters =
          _calculateDistance(lat, lng, coords.latitude, coords.longitude) * 1000;
      if (distMeters <= maxDistanceMeters && distMeters < bestDistMeters) {
        bestDistMeters = distMeters;
        best = addr;
      }
    }
    return best;
  }

  Future<void> _restoreSavedAddress() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final encoded = preferences.getString(_savedAddressKey);
      if (encoded != null) {
        final saved = jsonDecode(encoded) as Map<String, dynamic>;
        var address = saved['address']?.toString() ?? '';
        var type = saved['type']?.toString() ?? '';
        final latitude = (saved['latitude'] as num?)?.toDouble();
        final longitude = (saved['longitude'] as num?)?.toDouble();

        if (latitude != null &&
            longitude != null &&
            latitude != 0 &&
            longitude != 0) {
          // Nếu địa chỉ đang lưu là chuỗi tọa độ GPS thô, tự động phân giải sang địa chỉ thật
          if (_isRawCoordinateAddress(address)) {
            final resolved = await _reverseGeocode(latitude, longitude);
            if (resolved.isNotEmpty) {
              address = resolved;
              if (type.isEmpty) type = 'Vị trí hiện tại';
              await _persistAddress(
                DeliveryLocationOption(
                  label: type,
                  address: address,
                  latitude: latitude,
                  longitude: longitude,
                ),
              );
            }
          }

          if (address.isNotEmpty && mounted) {
            setState(() {
              _selectedAddressName = address;
              _selectedAddressType = type.isNotEmpty ? type : 'Địa chỉ giao hàng';
              _selectedLat = latitude;
              _selectedLng = longitude;
            });
            _fetchData();
            return;
          }
        }
      }

      // Fallback: Nếu chưa có trong SharedPreferences, tự động lấy địa chỉ mặc định từ hồ sơ
      final profileAddresses = await ProfileApiService().getAddresses();
      if (profileAddresses.isNotEmpty && mounted) {
        final def = profileAddresses.firstWhere(
          (a) => a.isDefault,
          orElse: () => profileAddresses.first,
        );
        if (def.fullAddress.trim().isNotEmpty) {
          final coords = await GeocodingService.getCoordinatesFromAddress(
            def.fullAddress,
          );
          final lat = coords?.latitude ?? 10.77689;
          final lng = coords?.longitude ?? 106.70089;
          final option = DeliveryLocationOption(
            label: def.label,
            address: def.fullAddress.trim(),
            latitude: lat,
            longitude: lng,
          );
          await _persistAddress(option);
          if (mounted) {
            setState(() {
              _selectedAddressName = option.address;
              _selectedAddressType = option.label;
              _selectedLat = option.latitude;
              _selectedLng = option.longitude;
            });
            _fetchData();
          }
        }
      }
    } catch (error) {
      debugPrint('Could not restore saved delivery address: $error');
    }
  }

  Future<void> _persistAddress(DeliveryLocationOption option) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _savedAddressKey,
      jsonEncode({
        'address': option.address,
        'type': option.label,
        'latitude': option.latitude,
        'longitude': option.longitude,
      }),
    );
    if (!saved) throw Exception('Không lưu được địa chỉ giao hàng');
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Thuật toán tính khoảng cách Haversine (km) giữa 2 tọa độ
  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const p = 0.017453292519943295; // Math.PI / 180
    final a =
        0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // Đường kính Trái đất = 12742 km
  }

  /// ĐỊNH VỊ VỊ TRÍ TỪ CHIP GPS THIẾT BỊ HOẶC MỞ BẢNG CHỌN ĐỊA CHỈ GIAO HÀNG
  Future<void> _getRealDeviceGpsPosition({bool silent = false}) async {
    if (_isLocatingGps) return;
    setState(() => _isLocatingGps = true);

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception(
          'Hãy bật dịch vụ Vị trí/GPS trên điện thoại rồi thử lại.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Quyền vị trí đang bị chặn. Hãy bật quyền Vị trí trong Cài đặt ứng dụng.',
              ),
            ),
          );
        }
        await Geolocator.openAppSettings();
        return;
      }
      if (permission == LocationPermission.denied) {
        throw Exception('Ứng dụng chưa được cấp quyền truy cập vị trí.');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );

      String resolvedAddress = '';
      String resolvedType = 'Vị trí hiện tại';
      double finalLat = position.latitude;
      double finalLng = position.longitude;

      // 1. Kiểm tra xem người dùng có đang đứng gần địa chỉ đã lưu trong Sổ địa chỉ (<= 120m) không
      try {
        final savedAddresses = await ProfileApiService().getAddresses();
        final nearMatch = await _findNearestSavedAddress(
          position.latitude,
          position.longitude,
          savedAddresses,
          maxDistanceMeters: 120,
        );
        if (nearMatch != null) {
          resolvedAddress = nearMatch.fullAddress.trim();
          resolvedType = nearMatch.label;
        }
      } catch (_) {}

      // 2. Nếu không trùng địa chỉ đã lưu, gọi Reverse Geocoding để lấy địa chỉ đường phố cụ thể
      if (resolvedAddress.isEmpty) {
        resolvedAddress = await _reverseGeocode(
          position.latitude,
          position.longitude,
        );
      }

      if (resolvedAddress.isEmpty) {
        throw Exception(
          'Không tìm thấy địa chỉ cụ thể từ GPS. Vui lòng kiểm tra mạng hoặc nhập địa chỉ.',
        );
      }

      final option = DeliveryLocationOption(
        label: resolvedType,
        address: resolvedAddress,
        latitude: finalLat,
        longitude: finalLng,
      );

      try {
        await _persistAddress(option);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _currentGpsLat = position.latitude;
          _currentGpsLng = position.longitude;
          _hasCurrentGps = true;
          _selectedLat = finalLat;
          _selectedLng = finalLng;
          _selectedAddressName = resolvedAddress;
          _selectedAddressType = resolvedType;
        });
        _fetchData();
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã xác định địa chỉ: $resolvedAddress'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (error) {
      debugPrint('GPS location failed: $error');
      if (!silent && mounted) {
        final message = error.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không lấy được vị trí: $message')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocatingGps = false);
    }
  }

  Future<void> _fetchData({String? query, String? category}) async {
    final searchQuery = query ?? _searchController.text;
    if (searchQuery.trim().isNotEmpty && (_selectedLat == 0 || _selectedLng == 0)) {
      setState(() {
        _restaurants = [];
        _isLoading = false;
        _errorMessage = 'Vui lòng chọn địa chỉ giao hàng để tìm quán trong bán kính 20 km.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await ApiService.searchRestaurants(
        query: searchQuery,
        category: category ?? _selectedCategory,
        lat: _selectedLat == 0 ? null : _selectedLat,
        lng: _selectedLng == 0 ? null : _selectedLng,
        radiusKm: 20,
      );
      if (mounted) {
        setState(() {
          _restaurants = _sortRestaurants(results, searchQuery);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Lỗi tải danh sách nhà hàng: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Không thể kết nối đến máy chủ BE. Vui lòng kiểm tra lại kết nối.';
        });
      }
    }
  }

  List<ApiRestaurant> _sortRestaurants(
    List<ApiRestaurant> restaurants,
    String query,
  ) {
    final normalizedQuery = query.trim().toLowerCase();
    double distance(ApiRestaurant restaurant) {
      if (restaurant.latitude == null || restaurant.longitude == null) {
        return double.infinity;
      }
      return _calculateDistance(
        _selectedLat,
        _selectedLng,
        restaurant.latitude!,
        restaurant.longitude!,
      );
    }

    int relevance(ApiRestaurant restaurant) {
      if (normalizedQuery.isEmpty) return 0;
      final matchingItems = restaurant.categories
          .expand((category) => category.items)
          .where((item) => item.name.toLowerCase().contains(normalizedQuery))
          .length;
      final nameMatch = restaurant.name.toLowerCase().contains(normalizedQuery);
      final categoryMatch = restaurant.categories.any(
        (category) => category.name.toLowerCase().contains(normalizedQuery),
      );
      return matchingItems * 100 + (nameMatch ? 10 : 0) + (categoryMatch ? 1 : 0);
    }

    final nearby = (_selectedLat != 0 && _selectedLng != 0)
        ? restaurants.where((r) => distance(r) <= 20.0).toList()
        : restaurants;
    final sorted = [...nearby];
    switch (_restaurantSort) {
      case 'distance':
        sorted.sort((a, b) {
          final byDistance = distance(a).compareTo(distance(b));
          return byDistance != 0
              ? byDistance
              : b.averageRating.compareTo(a.averageRating);
        });
        break;
      case 'rating':
        sorted.sort((a, b) {
          final byRating = b.averageRating.compareTo(a.averageRating);
          return byRating != 0
              ? byRating
              : distance(a).compareTo(distance(b));
        });
        break;
      default:
        sorted.sort((a, b) {
          final byRelevance = relevance(b).compareTo(relevance(a));
          return byRelevance != 0
              ? byRelevance
              : b.averageRating.compareTo(a.averageRating);
        });
        break;
    }
    return sorted;
  }

  void _selectRestaurantSort(String value) {
    setState(() {
      _restaurantSort = value;
      _restaurants = _sortRestaurants(_restaurants, _searchController.text);
    });
  }

  void _onSearchSubmitted(String query) {
    _restaurantSort = 'relevance';
    _fetchData(query: query);
  }

  void _onCategorySelected(String categoryName) {
    setState(() {
      _selectedCategory = _selectedCategory == categoryName
          ? 'Tất cả'
          : categoryName;
    });
    _fetchData(category: _selectedCategory);
  }

  String _formatPrice(double amount) {
    if (amount >= 1000) {
      final k = amount / 1000;
      return k == k.roundToDouble() ? '${k.toInt()}k' : '${k.toStringAsFixed(1)}k';
    }
    return '${amount.toInt()}đ';
  }

  List<_DishDealItem> _getHotDeals() {
    final List<_DishDealItem> deals = [];
    for (final r in _restaurants) {
      for (final cat in r.categories) {
        for (final item in cat.items) {
          if ((item.discountPercent != null && item.discountPercent! > 0) ||
              (item.originalPrice != null && item.originalPrice! > item.price)) {
            deals.add(_DishDealItem(item: item, restaurant: r));
          }
        }
      }
    }
    if (deals.length < 4) {
      for (final r in _restaurants) {
        for (final cat in r.categories) {
          for (final item in cat.items) {
            if (!deals.any((d) => d.item.id == item.id) && item.soldCount > 20) {
              deals.add(_DishDealItem(item: item, restaurant: r));
            }
          }
        }
      }
    }
    deals.sort((a, b) {
      final discA = a.item.discountPercent ?? 0;
      final discB = b.item.discountPercent ?? 0;
      if (discA != discB) return discB.compareTo(discA);
      return b.item.soldCount.compareTo(a.item.soldCount);
    });
    return deals.take(8).toList();
  }

  /// Trích xuất danh sách quán gần nhất (bán kính <= 3.5km hoặc top gần nhất)
  List<ApiRestaurant> _getNearbyRestaurants() {
    if (_selectedLat == 0 || _selectedLng == 0) {
      return _restaurants.take(5).toList();
    }
    final withDist = _restaurants.where((r) => r.latitude != null && r.longitude != null).toList();
    withDist.sort((a, b) {
      final da = _calculateDistance(_selectedLat, _selectedLng, a.latitude!, a.longitude!);
      final db = _calculateDistance(_selectedLat, _selectedLng, b.latitude!, b.longitude!);
      return da.compareTo(db);
    });
    return withDist.take(6).toList();
  }

  /// CHỌN ĐỊA CHỈ & KIỂM TRA KHOẢNG CÁCH VỚI VỊ TRÍ GPS THỰC TẾ
  Future<void> _changeDeliveryAddress(DeliveryLocationOption option) async {
    final distance = _hasCurrentGps
        ? _calculateDistance(
            _currentGpsLat,
            _currentGpsLng,
            option.latitude,
            option.longitude,
          )
        : 0.0;

    if (distance > 15.0) {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Xác nhận địa chỉ giao',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 14,
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(text: 'Địa chỉ bạn chọn: '),
                    TextSpan(
                      text: '"${option.address}"',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    TextSpan(text: ' cách vị trí hiện tại của bạn khoảng '),
                    TextSpan(
                      text: '${distance.toStringAsFixed(1)} km',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const TextSpan(
                      text: '.\n\nBạn có chắc chắn muốn đặt đồ ăn giao đến địa chỉ này không?',
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'Chọn địa chỉ khác',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Xác nhận giao tới đây'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    try {
      await _persistAddress(option);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không lưu được địa chỉ. Vui lòng thử lại.'),
          ),
        );
      }
      debugPrint('Could not persist delivery address: $error');
      return;
    }

    setState(() {
      _selectedAddressName = option.address;
      _selectedAddressType = option.label;
      _selectedLat = option.latitude;
      _selectedLng = option.longitude;
    });

    _fetchData();
  }

  static Future<List<_AddressSuggestion>> _searchAddressSuggestions(
    String query,
  ) => AddressSuggestionService.search(query);

  Future<void> _showCustomAddressInputDialog() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final option = await showDialog<DeliveryLocationOption>(
      context: context,
      builder: (_) => const _AddressInputDialog(),
    );

    if (option != null && mounted) {
      _changeDeliveryAddress(option);
    }
  }

  Future<void> _showAddressSelectionSheet() async {
    List<UserAddress> profileAddresses = [];
    try {
      profileAddresses = await ProfileApiService().getAddresses();
    } catch (_) {}

    if (!mounted) return;

    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Chọn địa chỉ giao hàng',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  tooltip: 'Tự động định vị GPS',
                  onPressed: _isLocatingGps
                      ? null
                      : () {
                          Navigator.pop(ctx, _AddressSheetAction.gps);
                        },
                  icon: _isLocatingGps
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location, color: Colors.orange),
                ),
              ],
            ),
            const Text(
              'Gợi ý nhà hàng sẽ tối ưu theo địa chỉ giao hàng bạn chọn',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),

            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                side: const BorderSide(color: Colors.orange),
              ),
              onPressed: () {
                Navigator.pop(ctx, _AddressSheetAction.customInput);
              },
              icon: const Icon(Icons.search, color: Colors.orange),
              label: const Text(
                'Tìm kiếm & Nhập bất kì địa chỉ nào',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            if (profileAddresses.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Địa chỉ đã lưu trong hồ sơ',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: profileAddresses.length,
                  separatorBuilder: (_, _) => const Divider(height: 8),
                  itemBuilder: (_, idx) {
                    final addr = profileAddresses[idx];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        addr.label == 'Văn phòng'
                            ? Icons.business
                            : (addr.label == 'Nhà riêng' ? Icons.home : Icons.place),
                        color: Colors.orange,
                      ),
                      title: Text(addr.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(addr.fullAddress, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                      onTap: () => Navigator.pop(ctx, addr),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 16),
            if (_selectedAddressName != 'Chưa chọn địa chỉ giao hàng')
              ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: Text('Đang chọn: $_selectedAddressType', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  _selectedAddressName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (!mounted || result == null) return;
    if (result == _AddressSheetAction.gps) {
      _getRealDeviceGpsPosition();
    } else if (result == _AddressSheetAction.customInput) {
      _showCustomAddressInputDialog();
    } else if (result is UserAddress) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đang định vị địa chỉ đã lưu...'),
          duration: Duration(seconds: 1),
        ),
      );
      final coords = await GeocodingService.getCoordinatesFromAddress(
        result.fullAddress,
      );
      final lat = coords?.latitude ?? (_selectedLat != 0 ? _selectedLat : 10.77689);
      final lng = coords?.longitude ?? (_selectedLng != 0 ? _selectedLng : 106.70089);
      if (mounted) {
        _changeDeliveryAddress(DeliveryLocationOption(
          label: result.label,
          address: result.fullAddress,
          latitude: lat,
          longitude: lng,
        ));
      }
    }
  }

  Future<void> _navigateToRestaurant(ApiRestaurant restaurant) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RestaurantDetailScreen(
          restaurant: restaurant,
          userLat: _selectedLat != 0 ? _selectedLat : null,
          userLng: _selectedLng != 0 ? _selectedLng : null,
          userAddress: !_isRawCoordinateAddress(_selectedAddressName)
              ? _selectedAddressName
              : null,
        ),
      ),
    );
    if (mounted) {
      _restoreSavedAddress();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9FA),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          SafeArea(
            child: RefreshIndicator(
              onRefresh: () => _fetchData(),
              color: const Color(0xFFFF7A00),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildModernTopHeader(),
                    _buildActiveOrderBanner(),
                    _buildPromoCarousel(),
                    _buildCategoriesSection(),
                    _buildFlashSaleSection(),
                    _buildNearbySection(),
                    _buildRestaurantFeedSection(),
                    const SizedBox(height: 70),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: OrderListScreen(
              isVisible: _selectedIndex == 1,
              onBackToHome: () => setState(() => _selectedIndex = 0),
            ),
          ),
          _buildSimplePlaceholder('Món ăn yêu thích', Icons.favorite),
          ProfileScreen(
            isVisible: _selectedIndex == 3,
            onBackToHome: () => setState(() => _selectedIndex = 0),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() => _selectedIndex = 1);
        },
        backgroundColor: const Color(0xFFFF7A00),
        shape: const CircleBorder(),
        elevation: 4,
        child: const Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 26),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  // ==========================================
  // 1. TOP HEADER HIỆN ĐẠI & TINH GỌN
  // ==========================================
  Widget _buildModernTopHeader() {
    final currentUser = FirebaseAuth.instance.currentUser;
    final photoUrl = currentUser?.photoURL;
    final displayName = currentUser?.displayName ?? 'Khách';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Address Selector & Action Icons
          Row(
            children: [
              // Address selector pill
              Expanded(
                child: InkWell(
                  onTap: _showAddressSelectionSheet,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4EB),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFFE0CC), width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on, color: Color(0xFFFF7A00), size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    _selectedAddressType.isNotEmpty ? _selectedAddressType : 'Giao đến',
                                    style: const TextStyle(
                                      color: Color(0xFFE65100),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  const Icon(Icons.keyboard_arrow_down, color: Color(0xFFE65100), size: 14),
                                ],
                              ),
                              Text(
                                _selectedAddressName,
                                style: const TextStyle(
                                  color: Color(0xFF212121),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // GPS Button
              InkWell(
                onTap: _getRealDeviceGpsPosition,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F7F8),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                  ),
                  child: Center(
                    child: _isLocatingGps
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF7A00)),
                          )
                        : const Icon(Icons.my_location_rounded, color: Color(0xFFFF7A00), size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Server config icon
              InkWell(
                onTap: () => ApiConfig.showConfigDialog(context, onConnected: _fetchData),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F7F8),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                  ),
                  child: const Center(
                    child: Icon(Icons.wifi_tethering_rounded, color: Color(0xFF555555), size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // User avatar
              InkWell(
                onTap: () => setState(() => _selectedIndex = 3),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFFF7A00), width: 1.5),
                  ),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.orange.shade100,
                    backgroundImage: NetworkImage(
                      photoUrl != null && photoUrl.isNotEmpty
                          ? photoUrl
                          : 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(displayName)}&background=FFA500&color=fff',
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Search Box with Clean Modern Style
          Container(
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFF6F6F7),
              borderRadius: BorderRadius.circular(23),
              border: Border.all(color: const Color(0xFFECECEC)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                const Icon(Icons.search_rounded, color: Color(0xFFFF7A00), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: _onSearchSubmitted,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Bạn đang thèm món gì hôm nay?',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13.5),
                      isDense: true,
                    ),
                    onChanged: (val) => setState(() {}),
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.cancel_rounded, size: 18, color: Colors.grey),
                    onPressed: () {
                      _searchController.clear();
                      _fetchData(query: '');
                    },
                  ),
                InkWell(
                  onTap: () => _fetchData(),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF7A00),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.tune_rounded, size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Trending Search Tags
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _trendingSearches.map((keyword) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () {
                      _searchController.text = keyword;
                      _onSearchSubmitted(keyword);
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F7F8),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE8E8E8)),
                      ),
                      child: Text(
                        keyword,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF424242),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 2. LIVE ACTIVE ORDER TRACKING BANNER
  // ==========================================
  Widget _buildActiveOrderBanner() {
    return AnimatedBuilder(
      animation: OrderData(),
      builder: (context, _) {
        final activeOrders = OrderData().activeOrders;
        if (activeOrders.isEmpty) return const SizedBox.shrink();
        final order = activeOrders.first;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OrderTrackingScreen(orderId: order.id),
                ),
              );
            },
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF9F2), Color(0xFFFFF0E0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFFFCC99), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF7A00).withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF7A00),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'ĐANG GIAO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF00A86B),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                order.restaurantName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFF212121),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${order.status.label} • Dự kiến ~${order.estimatedDeliveryMinutes} phút',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.orange.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF7A00),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Theo dõi',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(Icons.chevron_right_rounded, color: Colors.white, size: 14),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // 3. DYNAMIC PROMO BANNER CAROUSEL
  // ==========================================
  Widget _buildPromoCarousel() {
    return Column(
      children: [
        SizedBox(
          height: 128,
          child: PageView.builder(
            controller: _bannerController,
            onPageChanged: (idx) => setState(() => _currentBannerIndex = idx),
            itemCount: _banners.length,
            itemBuilder: (context, index) {
              final banner = _banners[index];
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: banner.gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: banner.gradientColors.first.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.24),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                banner.badge,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              banner.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    banner.code,
                                    style: TextStyle(
                                      color: banner.gradientColors.first,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    banner.subtitle,
                                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        // Dots indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_banners.length, (idx) {
            final isSelected = _currentBannerIndex == idx;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isSelected ? 16 : 6,
              height: 5,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFFF7A00) : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }

  // ==========================================
  // 4. DANH MỤC MÓN ĂN (PILL TABS KHÔNG ICON)
  // ==========================================
  Widget _buildCategoriesSection() {
    final categories = [
      'Tất cả',
      'Cơm',
      'Trà sữa',
      'Bún & Phở',
      'Burger',
      'Pizza',
      'Đồ uống',
      'Healthy',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Danh mục món ngon',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF212121),
                ),
              ),
              if (_selectedCategory != 'Tất cả')
                GestureDetector(
                  onTap: () {
                    setState(() => _selectedCategory = 'Tất cả');
                    _fetchData(category: 'Tất cả');
                  },
                  child: const Text(
                    'Xem tất cả',
                    style: TextStyle(
                      color: Color(0xFFFF7A00),
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final catName = categories[index];
              final isSelected = _selectedCategory == catName;

              return InkWell(
                onTap: () => _onCategorySelected(catName),
                borderRadius: BorderRadius.circular(20),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFFF7A00) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? const Color(0xFFFF7A00) : const Color(0xFFE0E0E0),
                      width: 1.2,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(0xFFFF7A00).withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      catName,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected ? Colors.white : const Color(0xFF424242),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==========================================
  // 5. FLASH SALE - MÓN NGON GIẢM SÂU (DATA THẬT)
  // ==========================================
  Widget _buildFlashSaleSection() {
    final deals = _getHotDeals();
    if (deals.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3D00),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'FLASH SALE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Món Ngon Giảm Sâu',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF212121),
                    ),
                  ),
                ],
              ),
              const Text(
                'Chỉ hôm nay',
                style: TextStyle(color: Colors.grey, fontSize: 11.5),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: deals.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final deal = deals[index];
              final item = deal.item;
              final restaurant = deal.restaurant;
              final discount = item.discountPercent ??
                  (item.originalPrice != null && item.originalPrice! > item.price
                      ? (((item.originalPrice! - item.price) / item.originalPrice!) * 100).round()
                      : 0);

              return InkWell(
                onTap: () => _navigateToRestaurant(restaurant),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 145,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Dish Image with Discount Badge
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                            child: Container(
                              height: 100,
                              width: double.infinity,
                              color: Colors.orange.shade50,
                              child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                                  ? Image.network(
                                      item.imageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.fastfood_rounded,
                                        size: 40,
                                        color: Colors.orange,
                                      ),
                                    )
                                  : const Icon(Icons.fastfood_rounded, size: 40, color: Colors.orange),
                            ),
                          ),
                          if (discount > 0)
                            Positioned(
                              top: 6,
                              left: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF3D00),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '-$discount%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF212121),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              restaurant.name,
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  _formatPrice(item.price),
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFFF3D00),
                                  ),
                                ),
                                if (item.originalPrice != null && item.originalPrice! > item.price) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatPrice(item.originalPrice!),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==========================================
  // 6. GẦN BẠN GIAO NHANH (CAROUSEL NGANG QUÁN)
  // ==========================================
  Widget _buildNearbySection() {
    final nearby = _getNearbyRestaurants();
    if (nearby.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'Gần Bạn Giao Nhanh',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF212121),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '< 20p',
                      style: TextStyle(
                        color: Color(0xFF2E7D32),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const Text(
                'Freeship 0đ',
                style: TextStyle(color: Color(0xFFFF7A00), fontWeight: FontWeight.bold, fontSize: 11.5),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 165,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: nearby.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final r = nearby[index];
              double? dist;
              if (_selectedLat != 0 && r.latitude != null && r.longitude != null) {
                dist = _calculateDistance(_selectedLat, _selectedLng, r.latitude!, r.longitude!);
              }

              return InkWell(
                onTap: () => _navigateToRestaurant(r),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 210,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                            child: Container(
                              height: 95,
                              width: double.infinity,
                              color: Colors.orange.shade50,
                              child: r.imageUrl != null && r.imageUrl!.isNotEmpty
                                  ? Image.network(
                                      r.imageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.storefront_rounded,
                                        size: 36,
                                        color: Colors.orange,
                                      ),
                                    )
                                  : const Icon(Icons.storefront_rounded, size: 36, color: Colors.orange),
                            ),
                          ),
                          Positioned(
                            bottom: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star_rounded, color: Color(0xFFFFD600), size: 13),
                                  const SizedBox(width: 2),
                                  Text(
                                    r.averageRating > 0 ? r.averageRating.toStringAsFixed(1) : 'Mới',
                                    style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF212121),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Text(
                                  dist != null ? '${dist.toStringAsFixed(1)} km' : 'Gần bạn',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(width: 6),
                                Text('•', style: TextStyle(color: Colors.grey.shade400, fontSize: 10)),
                                const SizedBox(width: 6),
                                Text(
                                  dist != null ? '${(12 + (dist * 3.5).toInt()).clamp(12, 40)}p' : '15p',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==========================================
  // 7. MAIN RESTAURANT FEED SECTION
  // ==========================================
  Widget _buildRestaurantFeedSection() {
    final displayedRestaurants = _onlyOpen
        ? _restaurants.where((r) => r.isAcceptingOrders).toList()
        : _restaurants;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title & Counter
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    _selectedCategory == 'Tất cả'
                        ? 'Khám phá quán ngon'
                        : 'Món $_selectedCategory',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF212121),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0E0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${displayedRestaurants.length}',
                      style: const TextStyle(
                        color: Color(0xFFE65100),
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
              if (_searchController.text.isNotEmpty)
                Text(
                  'Từ khóa: "${_searchController.text}"',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Quick Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  label: 'Gợi ý',
                  isSelected: _restaurantSort == 'relevance',
                  onTap: () => _selectRestaurantSort('relevance'),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'Gần tôi',
                  isSelected: _restaurantSort == 'distance',
                  onTap: () => _selectRestaurantSort('distance'),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'Đánh giá cao',
                  isSelected: _restaurantSort == 'rating',
                  onTap: () => _selectRestaurantSort('rating'),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'Đang mở',
                  isSelected: _onlyOpen,
                  onTap: () => setState(() => _onlyOpen = !_onlyOpen),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Loading, Error, Empty or List
          if (_isLoading)
            _buildShimmerPlaceholder()
          else if (_errorMessage != null)
            _buildErrorCard()
          else if (displayedRestaurants.isEmpty)
            _buildEmptyCard()
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayedRestaurants.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _buildModernRestaurantCard(displayedRestaurants[index]);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF3E0) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF7A00) : const Color(0xFFE5E5E5),
            width: isSelected ? 1.4 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF7A00).withValues(alpha: 0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFFE65100) : const Color(0xFF555555),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 8. SKELETON SHIMMER LOADING
  // ==========================================
  Widget _buildShimmerPlaceholder() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: List.generate(3, (index) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 120,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: 180,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildModernRestaurantCard(ApiRestaurant restaurant) {
    double? distFromDelivery;
    if (_selectedLat != 0 &&
        restaurant.latitude != null &&
        restaurant.longitude != null) {
      distFromDelivery = _calculateDistance(
        _selectedLat,
        _selectedLng,
        restaurant.latitude!,
        restaurant.longitude!,
      );
    }

    final sampleItems = restaurant.categories
        .expand((c) => c.items)
        .take(2)
        .toList();

    final isOpen = restaurant.isAcceptingOrders;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _navigateToRestaurant(restaurant),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFEEEEEE), width: 1.1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail with Status Badge
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 96,
                      height: 96,
                      color: Colors.orange.shade50,
                      child: restaurant.imageUrl != null && restaurant.imageUrl!.isNotEmpty
                          ? Image.network(
                              restaurant.imageUrl!,
                              width: 96,
                              height: 96,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Icon(
                                Icons.storefront_rounded,
                                size: 40,
                                color: Colors.orange.shade300,
                              ),
                            )
                          : Icon(
                              Icons.storefront_rounded,
                              size: 40,
                              color: Colors.orange.shade300,
                            ),
                    ),
                  ),
                  Positioned(
                    bottom: 4,
                    left: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: isOpen ? const Color(0xEE00A86B) : const Color(0xEE757575),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isOpen ? 'Đang mở' : 'Tạm đóng',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),

              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurant.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF212121),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Rating, Reviews & Distance
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, color: Color(0xFFFFB300), size: 16),
                        const SizedBox(width: 2),
                        Text(
                          restaurant.averageRating > 0
                              ? restaurant.averageRating.toStringAsFixed(1)
                              : 'Mới',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF212121),
                          ),
                        ),
                        if (restaurant.reviewCount > 0) ...[
                          Text(
                            ' (${restaurant.reviewCount})',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                        ],
                        const SizedBox(width: 6),
                        Text('•', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                        const SizedBox(width: 6),
                        Text(
                          distFromDelivery != null
                              ? '${distFromDelivery.toStringAsFixed(1)} km'
                              : 'Gần bạn',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                        ),
                        if (distFromDelivery != null) ...[
                          const SizedBox(width: 6),
                          Text('•', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                          const SizedBox(width: 6),
                          Text(
                            '${(15 + (distFromDelivery * 3.5).toInt()).clamp(15, 50)}p',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Address
                    Text(
                      restaurant.address,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),

                    // Featured items / Promo chips
                    if (sampleItems.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: sampleItems.map((item) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF4EB),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFFFDEC5), width: 0.8),
                            ),
                            child: Text(
                              '${item.name} • ${_formatPrice(item.price)}',
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFFE65100),
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Freeship đơn từ 50k',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 36),
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Đang kết nối: ${ApiConfig().baseUrl}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () => _fetchData(),
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF7A00),
                  foregroundColor: Colors.white,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => ApiConfig.showConfigDialog(context, onConnected: _fetchData),
                icon: const Icon(Icons.dns, color: Color(0xFFFF7A00), size: 18),
                label: const Text('Đổi IP máy chủ', style: TextStyle(color: Color(0xFFFF7A00), fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFFF7A00)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(Icons.search_off_rounded, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text(
            'Không tìm thấy quán phù hợp gần địa chỉ này.',
            style: TextStyle(color: Colors.grey, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _selectedCategory = 'Tất cả';
                _onlyOpen = false;
                _restaurantSort = 'relevance';
              });
              _fetchData();
            },
            child: const Text(
              'Đặt lại bộ lọc',
              style: TextStyle(color: Color(0xFFFF7A00), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimplePlaceholder(String title, IconData icon) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.orange.shade300),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Tính năng đang được phát triển', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8.0,
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildNavItem(Icons.home_rounded, 'Trang chủ', 0),
            _buildNavItem(Icons.receipt_long_rounded, 'Đơn hàng', 1),
            const SizedBox(width: 48), // Space for Floating Action Button
            _buildNavItem(Icons.favorite_rounded, 'Yêu thích', 2),
            _buildNavItem(Icons.person_rounded, 'Tài khoản', 3),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    bool isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () {
        final isSame = _selectedIndex == index;
        setState(() {
          _selectedIndex = index;
        });
        if (index == 0) {
          _restoreSavedAddress();
          if (isSame) _fetchData();
        } else if (index == 1) {
          OrderData().refreshFromApi();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFFFF7A00) : Colors.grey.shade400,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFFFF7A00) : Colors.grey.shade500,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 9. DIALOG TÌM KIẾM & NHẬP ĐỊA CHỈ TÙY CHỌN
// ==========================================
class _AddressInputDialog extends StatefulWidget {
  const _AddressInputDialog();

  @override
  State<_AddressInputDialog> createState() => _AddressInputDialogState();
}

class _AddressInputDialogState extends State<_AddressInputDialog> {
  final TextEditingController _addressController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _selectedType = 'Nhà riêng';
  _AddressSuggestion? _selectedSuggestion;
  List<_AddressSuggestion> _suggestions = [];
  bool _searching = false;
  String? _searchError;
  int _searchVersion = 0;

  @override
  void dispose() {
    _addressController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _onAddressChanged(String value) async {
    final version = ++_searchVersion;
    if (value.trim().length < 3) {
      if (mounted) {
        setState(() {
          _suggestions = [];
          _searchError = null;
          _searching = false;
        });
      }
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });

    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (version != _searchVersion || !mounted) return;

    try {
      final result = await _HomeScreenState._searchAddressSuggestions(
        value.trim(),
      );
      if (version == _searchVersion && mounted) {
        setState(() {
          _suggestions = result;
          _searching = false;
        });
      }
    } catch (error) {
      if (version == _searchVersion && mounted) {
        setState(() {
          _suggestions = [];
          _searching = false;
          _searchError = 'Không thể kết nối dịch vụ gợi ý: $error';
        });
      }
    }
  }

  void _selectSuggestion(_AddressSuggestion suggestion) {
    _focusNode.unfocus();
    setState(() {
      _selectedSuggestion = suggestion;
      _addressController.text = suggestion.displayName;
      _suggestions = [];
      _searchVersion++;
    });
  }

  Future<void> _submit() async {
    _focusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();

    if (_selectedSuggestion != null) {
      final option = DeliveryLocationOption(
        label: _selectedType,
        address: _selectedSuggestion!.displayName,
        latitude: _selectedSuggestion!.latitude,
        longitude: _selectedSuggestion!.longitude,
      );
      Navigator.pop(context, option);
      return;
    }

    if (_suggestions.isNotEmpty) {
      final first = _suggestions.first;
      final option = DeliveryLocationOption(
        label: _selectedType,
        address: first.displayName,
        latitude: first.latitude,
        longitude: first.longitude,
      );
      Navigator.pop(context, option);
      return;
    }

    final query = _addressController.text.trim();
    if (query.isNotEmpty) {
      setState(() => _searching = true);
      try {
        final coords = await GeocodingService.getCoordinatesFromAddress(query);
        if (coords != null && mounted) {
          final option = DeliveryLocationOption(
            label: _selectedType,
            address: query,
            latitude: coords.latitude,
            longitude: coords.longitude,
          );
          Navigator.pop(context, option);
          return;
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _searching = false;
          _searchError = 'Không tìm thấy tọa độ cho địa chỉ này trên bản đồ.';
        });
      }
    }
  }

  void _cancel() {
    _focusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: const Text(
        'Địa chỉ giao hàng',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Nhập tên đường, quận/huyện hoặc thành phố để tìm và chọn địa chỉ đầy đủ.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const Text(
                'Gợi ý bản đồ © OpenStreetMap',
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addressController,
                focusNode: _focusNode,
                autofocus: true,
                onChanged: _onAddressChanged,
                decoration: InputDecoration(
                  hintText: 'Ví dụ: 12 Nguyễn Trãi, Thanh Xuân, Hà Nội',
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Colors.orange,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (_searching) const LinearProgressIndicator(minHeight: 2),
              if (_searchError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _searchError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 190),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final suggestion = _suggestions[index];
                      return ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.place_outlined,
                          color: Colors.orange,
                        ),
                        title: Text(
                          suggestion.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                        onTap: () => _selectSuggestion(suggestion),
                      );
                    },
                  ),
                ),
              ],
              if (_selectedSuggestion != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Đường: ${_selectedSuggestion!.street.isEmpty ? '—' : _selectedSuggestion!.street}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'Quận/Huyện: ${_selectedSuggestion!.district.isEmpty ? '—' : _selectedSuggestion!.district}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'Thành phố: ${_selectedSuggestion!.city.isEmpty ? '—' : _selectedSuggestion!.city}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                decoration: InputDecoration(
                  labelText: 'Loại địa điểm',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Nhà riêng',
                    child: Row(
                      children: [
                        Icon(Icons.home_outlined, size: 20, color: Colors.orange),
                        SizedBox(width: 8),
                        Text('Nhà riêng'),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Công ty',
                    child: Row(
                      children: [
                        Icon(Icons.business_outlined, size: 20, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('Công ty'),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Căn hộ',
                    child: Row(
                      children: [
                        Icon(Icons.apartment_outlined, size: 20, color: Colors.purple),
                        SizedBox(width: 8),
                        Text('Căn hộ'),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Khác',
                    child: Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 20, color: Colors.grey),
                        SizedBox(width: 8),
                        Text('Khác'),
                      ],
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedType = value;
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _cancel,
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
          onPressed: _selectedSuggestion == null ? null : _submit,
          child: const Text('Dùng địa chỉ này'),
        ),
      ],
    );
  }
}
