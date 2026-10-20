import 'dart:math';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'order/order_list_screen.dart';

import 'profile/profile_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'services/api_service.dart';
import 'services/geocoding_service.dart';
import 'services/profile_api_service.dart';
import 'models/user_address.dart';
import 'services/api_config.dart';
import 'restaurant_detail_screen.dart';

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

class _AddressSuggestion {
  final String displayName;
  final String street;
  final String district;
  final String city;
  final double latitude;
  final double longitude;

  const _AddressSuggestion({
    required this.displayName,
    required this.street,
    required this.district,
    required this.city,
    required this.latitude,
    required this.longitude,
  });

  factory _AddressSuggestion.fromJson(Map<String, dynamic> json) {
    final properties = json['properties'] as Map<String, dynamic>? ?? {};
    final coordinates =
        (json['geometry'] as Map<String, dynamic>?)?['coordinates']
            as List<dynamic>? ??
        [];
    final houseNumber = properties['housenumber']?.toString() ?? '';
    final road = properties['street']?.toString() ?? '';
    final street = [
      houseNumber,
      road,
    ].where((part) => part.isNotEmpty).join(' ');
    final district = properties['district'] ?? properties['county'] ?? '';
    final city = properties['city'] ?? properties['state'] ?? '';
    final addressParts = <String>[
      properties['name']?.toString() ?? '',
      street,
      district.toString(),
      city.toString(),
      properties['country']?.toString() ?? '',
    ].where((part) => part.isNotEmpty).toSet().toList();
    return _AddressSuggestion(
      displayName: addressParts.join(', '),
      street: street,
      district: district.toString(),
      city: city.toString(),
      latitude: coordinates.length > 1 ? (coordinates[1] as num).toDouble() : 0,
      longitude: coordinates.isNotEmpty
          ? (coordinates[0] as num).toDouble()
          : 0,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final TextEditingController _searchController = TextEditingController();

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

  @override
  void initState() {
    super.initState();
    _restoreSavedAddress();
    _fetchData();
  }

  String get _savedAddressKey =>
      'soopi.delivery_address.${FirebaseAuth.instance.currentUser?.uid ?? 'guest'}';

  Future<void> _restoreSavedAddress() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final encoded = preferences.getString(_savedAddressKey);
      if (encoded == null) return;
      final saved = jsonDecode(encoded) as Map<String, dynamic>;
      final address = saved['address']?.toString() ?? '';
      final type = saved['type']?.toString() ?? '';
      final latitude = (saved['latitude'] as num?)?.toDouble();
      final longitude = (saved['longitude'] as num?)?.toDouble();
      if (address.isEmpty ||
          type.isEmpty ||
          latitude == null ||
          longitude == null ||
          !mounted) {
        return;
      }
      setState(() {
        _selectedAddressName = address;
        _selectedAddressType = type;
        _selectedLat = latitude;
        _selectedLng = longitude;
      });
      _fetchData();
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
      final locationLabel =
          'Vị trí GPS (${position.latitude.toStringAsFixed(3)}, ${position.longitude.toStringAsFixed(3)})';

      if (mounted) {
        setState(() {
          _currentGpsLat = position.latitude;
          _currentGpsLng = position.longitude;
          _hasCurrentGps = true;
          _selectedLat = position.latitude;
          _selectedLng = position.longitude;
          _selectedAddressName = locationLabel;
          _selectedAddressType = 'Vị trí hiện tại';
        });
        _fetchData();
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã cập nhật vị trí GPS: $locationLabel'),
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

    // Chỉ lấy quán trong bán kính 20km quanh vị trí hiện tại
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

    // Nếu địa chỉ giao hàng được chọn cách vị trí hiện tại > 15 km -> Hiện POPUP CẢNH BÁO / XÁC NHẬN
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

      if (confirm != true) return; // Người dùng hủy chọn
    }

    // Cập nhật vị trí giao hàng và gọi lại API để tối ưu nhà hàng gần nhất
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
  ) async {
    final uri = Uri.https('photon.komoot.io', '/api/', {
      'q': query,
      'limit': '6',
      'countrycode': 'VN',
    });
    final response = await http
        .get(
          uri,
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'SoopiFood/1.0 (delivery address search)',
          },
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Dịch vụ tìm địa chỉ trả về mã ${response.statusCode}.');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final features = payload['features'] as List<dynamic>? ?? [];
    return features
        .map(
          (item) => _AddressSuggestion.fromJson(item as Map<String, dynamic>),
        )
        .where(
          (item) =>
              item.displayName.isNotEmpty &&
              item.latitude != 0 &&
              item.longitude != 0,
        )
        .toList();
  }

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
      final coords = await GeocodingService.getCoordinatesFromAddress(result.fullAddress);
      if (coords != null && mounted) {
        _changeDeliveryAddress(DeliveryLocationOption(
          label: result.label,
          address: result.fullAddress,
          latitude: coords.latitude,
          longitude: coords.longitude,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          SafeArea(
            child: RefreshIndicator(
              onRefresh: () => _fetchData(),
              color: Colors.orange,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTopHeader(),
                    _buildBanner(),
                    _buildCategories(),
                    _buildRestaurantSection(),
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: OrderListScreen(
              onBackToHome: () => setState(() => _selectedIndex = 0),
            ),
          ),
          _buildSimplePlaceholder('Món ăn yêu thích', Icons.favorite),
          ProfileScreen(
            onBackToHome: () => setState(() => _selectedIndex = 0),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: Colors.orange,
        shape: const CircleBorder(),
        child: const Icon(Icons.shopping_cart, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildTopHeader() {
    final currentUser = FirebaseAuth.instance.currentUser;
    final photoUrl = currentUser?.photoURL;
    final displayName = currentUser?.displayName ?? 'Khách';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFF7A00), Color(0xFFFF9800)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Color(0x33FF7A00),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Delivery Location & Quick Icons
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _showAddressSelectionSheet,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        const Text(
                          'Giao đến: ',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        Expanded(
                          child: Text(
                            _selectedAddressName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // GPS Button
              InkWell(
                onTap: _getRealDeviceGpsPosition,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: _isLocatingGps
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.my_location, color: Colors.white, size: 16),
                ),
              ),
              const SizedBox(width: 6),

              // Server config icon
              InkWell(
                onTap: () => ApiConfig.showConfigDialog(context, onConnected: _fetchData),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.wifi_tethering, color: Colors.white, size: 16),
                ),
              ),
              const SizedBox(width: 6),

              // User avatar
              InkWell(
                onTap: () => setState(() => _selectedIndex = 3),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 14,
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

          // Row 2: Search Bar integrated inside header
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                const Icon(Icons.search, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: _onSearchSubmitted,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Tìm món ngon, trà sữa, burger...',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                      isDense: true,
                    ),
                    onChanged: (val) => setState(() {}),
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                    onPressed: () {
                      _searchController.clear();
                      _fetchData(query: '');
                    },
                  ),
                InkWell(
                  onTap: () => _fetchData(),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.tune_rounded, size: 16, color: Colors.orange),
                  ),
                ),
                const SizedBox(width: 4),
              ],
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

  Widget _buildBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF5722), Color(0xFFFF9800)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF5722).withValues(alpha: 0.25),
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '🎉 ƯU ĐÃI ĐỘC QUYỀN',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Giảm 50% đơn đầu tiên',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'SOOPIVIP',
                          style: TextStyle(
                            color: Color(0xFFFF5722),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Tối đa 50k • Toàn menu',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_offer_rounded,
                size: 32,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategories() {
    final categories = [
      {'name': 'Tất cả', 'icon': Icons.lunch_dining_rounded},
      {'name': 'Cơm', 'icon': Icons.rice_bowl_rounded},
      {'name': 'Bún & Phở', 'icon': Icons.ramen_dining_rounded},
      {'name': 'Burger', 'icon': Icons.lunch_dining_outlined},
      {'name': 'Pizza', 'icon': Icons.local_pizza_rounded},
      {'name': 'Trà sữa', 'icon': Icons.local_cafe_rounded},
      {'name': 'Đồ uống', 'icon': Icons.local_drink_rounded},
      {'name': 'Healthy', 'icon': Icons.eco_rounded},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Danh mục món ăn',
                style: TextStyle(
                  fontSize: 15,
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
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 78,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final cat = categories[index];
              final catName = cat['name'] as String;
              final isSelected = _selectedCategory == catName;

              return GestureDetector(
                onTap: () => _onCategorySelected(catName),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFFF7A00) : const Color(0xFFF6F6F6),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? const Color(0xFFFF7A00) : const Color(0xFFE8E8E8),
                          width: isSelected ? 1.5 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                const BoxShadow(
                                  color: Color(0x40FF7A00),
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Icon(
                          cat['icon'] as IconData,
                          size: 23,
                          color: isSelected ? Colors.white : const Color(0xFF555555),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      catName,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? const Color(0xFFFF7A00) : const Color(0xFF424242),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF3E0) : const Color(0xFFF7F7F8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF9800) : const Color(0xFFE5E5E5),
            width: isSelected ? 1.2 : 1,
          ),
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

  Widget _buildRestaurantSection() {
    final displayedRestaurants = _onlyOpen
        ? _restaurants.where((r) => r.isAcceptingOrders).toList()
        : _restaurants;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                        ? 'Quán ngon quanh đây'
                        : 'Món $_selectedCategory',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF212121),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${displayedRestaurants.length}',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              if (_searchController.text.isNotEmpty)
                Text(
                  'Kết quả: "${_searchController.text}"',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Quick Filter Chips (Always visible!)
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
                  label: 'Gần tôi 🛵',
                  isSelected: _restaurantSort == 'distance',
                  onTap: () => _selectRestaurantSort('distance'),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'Đánh giá cao ⭐',
                  isSelected: _restaurantSort == 'rating',
                  onTap: () => _selectRestaurantSort('rating'),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'Đang mở 🟢',
                  isSelected: _onlyOpen,
                  onTap: () => setState(() => _onlyOpen = !_onlyOpen),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Loading, Error, Empty or List
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(color: Colors.orange),
              ),
            )
          else if (_errorMessage != null)
            _buildErrorCard()
          else if (displayedRestaurants.isEmpty)
            _buildEmptyCard()
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayedRestaurants.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                return _buildRestaurantCard(displayedRestaurants[index]);
              },
            ),
        ],
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
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => ApiConfig.showConfigDialog(context, onConnected: _fetchData),
                icon: const Icon(Icons.dns, color: Colors.orange, size: 18),
                label: const Text('Đổi IP máy chủ', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.orange),
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
              style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRestaurantCard(ApiRestaurant restaurant) {
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
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RestaurantDetailScreen(
                restaurant: restaurant,
                userLat: _selectedLat != 0 ? _selectedLat : null,
                userLng: _selectedLng != 0 ? _selectedLng : null,
                userAddress: _selectedAddressName != 'Chưa chọn địa chỉ giao hàng' ? _selectedAddressName : null,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
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
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 88,
                      height: 88,
                      color: Colors.orange.shade50,
                      child: restaurant.imageUrl != null && restaurant.imageUrl!.isNotEmpty
                          ? Image.network(
                              restaurant.imageUrl!,
                              width: 88,
                              height: 88,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Icon(
                                Icons.storefront_rounded,
                                size: 36,
                                color: Colors.orange.shade300,
                              ),
                            )
                          : Icon(
                              Icons.storefront_rounded,
                              size: 36,
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
                        color: isOpen ? const Color(0xDD00A86B) : const Color(0xDD757575),
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
                        Icon(Icons.directions_bike_rounded, size: 13, color: Colors.grey.shade600),
                        const SizedBox(width: 3),
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
                        fontSize: 12,
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
                              '${item.name} • ${item.price.toInt()}k',
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
            _buildNavItem(Icons.home, 'Trang chủ', 0),
            _buildNavItem(Icons.receipt_long, 'Đơn hàng', 1),
            const SizedBox(width: 48), // Space for FAB
            _buildNavItem(Icons.favorite_border, 'Yêu thích', 2),
            _buildNavItem(Icons.person_outline, 'Tài khoản', 3),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    bool isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.orange : Colors.grey,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.orange : Colors.grey,
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
