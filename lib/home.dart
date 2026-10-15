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
        radiusKm: searchQuery.trim().isNotEmpty ? 20 : null,
      );
      if (mounted) {
        setState(() {
          _restaurants = _sortRestaurants(results, searchQuery);
          _isLoading = false;
        });
      }
    } catch (e) {
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

    final sorted = [...restaurants];
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
    final action = await showModalBottomSheet<_AddressSheetAction>(
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
              icon: const Icon(Icons.edit_note, color: Colors.orange),
              label: const Text(
                'Tìm và nhập địa chỉ giao hàng',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_selectedAddressName != 'Chưa chọn địa chỉ giao hàng')
              ListTile(
                leading: const Icon(Icons.place, color: Colors.orange),
                title: Text(_selectedAddressType),
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

    if (!mounted || action == null) return;
    if (action == _AddressSheetAction.gps) {
      _getRealDeviceGpsPosition();
    } else if (action == _AddressSheetAction.customInput) {
      _showCustomAddressInputDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  _buildTitle(),
                  _buildSearchBar(),
                  _buildBanner(),
                  _buildCategories(),
                  _buildRestaurantSection(),
                  const SizedBox(height: 40), // Space for bottom nav padding
                ],
              ),
            ),
          ),
          const SafeArea(child: OrderListScreen()),
          _buildSimplePlaceholder('Món ăn yêu thích', Icons.favorite),
          const ProfileScreen(),
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

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _showAddressSelectionSheet,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Text(
                        'Giao đến',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.grey,
                        size: 18,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _selectedAddressName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Lấy vị trí thực tế',
            onPressed: _getRealDeviceGpsPosition,
            icon: _isLocatingGps
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.orange,
                    ),
                  )
                : const Icon(Icons.my_location, color: Colors.orange),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => setState(() => _selectedIndex = 3),
            borderRadius: BorderRadius.circular(22),
            child: CircleAvatar(
              backgroundColor: Colors.orange.shade200,
              radius: 22,
              child: const CircleAvatar(
                radius: 20,
                backgroundImage: NetworkImage('https://ui-avatars.com/api/?name=User&background=random'),
              ),
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

  Widget _buildTitle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: const TextSpan(
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Colors.black,
                letterSpacing: -1,
              ),
              children: [
                TextSpan(text: 'SOOPI '),
                TextSpan(
                  text: 'FOOD',
                  style: TextStyle(color: Colors.orange),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Hôm nay bạn muốn ăn gì?',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              height: 50,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.grey),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onSubmitted: _onSearchSubmitted,
                      textInputAction: TextInputAction.search,
                      autocorrect: false,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Tìm kiếm món ăn, nhà hàng...',
                        hintStyle: const TextStyle(color: Colors.grey),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  _searchController.clear();
                                  _fetchData(query: '');
                                },
                              )
                            : null,
                      ),
                      onChanged: (val) {
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: () => _fetchData(),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 50,
              width: 50,
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.tune, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Colors.orange, Colors.amber],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Khuyến mãi',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Giảm giá 50%\ncho đơn đầu tiên',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.orange,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      minimumSize: Size.zero,
                    ),
                    child: const Text(
                      'Đặt ngay',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const Text('🍔', style: TextStyle(fontSize: 60)),
          ],
        ),
      ),
    );
  }

  Widget _buildCategories() {
    final categories = [
      {'icon': '🍔', 'name': 'Burger'},
      {'icon': '🍕', 'name': 'Pizza'},
      {'icon': '🍣', 'name': 'Sushi'},
      {'icon': '🥤', 'name': 'Đồ uống'},
      {'icon': '🥗', 'name': 'Healthy'},
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Danh mục',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedCategory = 'Tất cả';
                  });
                  _fetchData(category: 'Tất cả');
                },
                child: const Text(
                  'Xem tất cả',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              final catName = cat['name'] as String;
              final isSelected = _selectedCategory == catName;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: GestureDetector(
                  onTap: () => _onCategorySelected(catName),
                  child: Column(
                    children: [
                      Container(
                        width: 65,
                        height: 65,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.orange.shade100
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? Colors.orange
                                : Colors.grey.shade300,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            cat['icon'] as String,
                            style: const TextStyle(fontSize: 30),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        catName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isSelected
                              ? Colors.orange
                              : Colors.grey.shade700,
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

  Widget _buildRestaurantSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _selectedCategory == 'Tất cả'
                    ? 'Nhà hàng gần bạn'
                    : 'Danh mục: $_selectedCategory',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_searchController.text.isNotEmpty)
                Text(
                  'Kết quả cho "${_searchController.text}"',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_searchController.text.trim().isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: const Text('Liên quan nhất'),
                  selected: _restaurantSort == 'relevance',
                  onSelected: (_) => _selectRestaurantSort('relevance'),
                ),
                ChoiceChip(
                  label: const Text('Gần tôi nhất'),
                  selected: _restaurantSort == 'distance',
                  onSelected: (_) => _selectRestaurantSort('distance'),
                ),
                ChoiceChip(
                  label: const Text('Đánh giá cao nhất'),
                  selected: _restaurantSort == 'rating',
                  onSelected: (_) => _selectRestaurantSort('rating'),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(color: Colors.orange),
              ),
            )
          else if (_errorMessage != null)
            Container(
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
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _fetchData(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            )
          else if (_restaurants.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const Text('🔍', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  const Text(
                    'Không tìm thấy nhà hàng hoặc món ăn phù hợp gần địa chỉ này.',
                    style: TextStyle(color: Colors.grey, fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      _searchController.clear();
                      _selectedCategory = 'Tất cả';
                      _fetchData();
                    },
                    child: const Text(
                      'Đặt lại bộ lọc',
                      style: TextStyle(color: Colors.orange),
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _restaurants.length,
              separatorBuilder: (_, _) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                return _buildRestaurantCard(_restaurants[index]);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRestaurantCard(ApiRestaurant restaurant) {
    // Tính khoảng cách từ địa chỉ giao hàng được chọn tới nhà hàng
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

    // Tách danh sách món ăn từ tất cả danh mục của nhà hàng
    final allMenuItems = <ApiMenuItem>[];
    for (var cat in restaurant.categories) {
      allMenuItems.addAll(cat.items);
    }

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RestaurantDetailScreen(
              restaurant: restaurant,
              userLat: _selectedLat != 0 ? _selectedLat : null,
              userLng: _selectedLng != 0 ? _selectedLng : null,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thông tin nhà hàng
            Row(
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child:
                        restaurant.imageUrl != null &&
                            restaurant.imageUrl!.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.network(
                              restaurant.imageUrl!,
                              width: 70,
                              height: 70,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Text(
                                '🏪',
                                style: TextStyle(fontSize: 36),
                              ),
                            ),
                          )
                        : const Text('🏪', style: TextStyle(fontSize: 36)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        restaurant.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        restaurant.address,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            restaurant.averageRating > 0
                                ? restaurant.averageRating.toStringAsFixed(1)
                                : 'Mới',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          if (distFromDelivery != null) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.near_me,
                                    color: Colors.orange,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    '${distFromDelivery.toStringAsFixed(1)} km',
                                    style: const TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(width: 10),
                          Icon(
                            restaurant.isAcceptingOrders
                                ? Icons.circle
                                : Icons.circle_outlined,
                            size: 10,
                            color: restaurant.isAcceptingOrders
                                ? Colors.green
                                : Colors.red,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            restaurant.isAcceptingOrders ? 'Đang mở' : 'Đóng',
                            style: TextStyle(
                              fontSize: 12,
                              color: restaurant.isAcceptingOrders
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Danh sách món ăn nổi bật của nhà hàng (nếu có)
            if (allMenuItems.isNotEmpty) ...[
              const Divider(height: 24),
              const Text(
                'Món ăn nổi bật:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Column(
                children: allMenuItems
                    .take(3)
                    .map((item) => _buildMenuItemRow(item))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItemRow(ApiMenuItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(
                  Icons.restaurant_menu,
                  size: 16,
                  color: Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${item.price.toInt().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')}đ',
            style: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
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

  void _submit() {
    if (_selectedSuggestion == null) return;
    _focusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    final option = DeliveryLocationOption(
      label: _selectedType,
      address: _selectedSuggestion!.displayName,
      latitude: _selectedSuggestion!.latitude,
      longitude: _selectedSuggestion!.longitude,
    );
    Navigator.pop(context, option);
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
                    child: Text('🏠 Nhà riêng'),
                  ),
                  DropdownMenuItem(
                    value: 'Công ty',
                    child: Text('🏢 Công ty'),
                  ),
                  DropdownMenuItem(
                    value: 'Căn hộ',
                    child: Text('🏬 Căn hộ'),
                  ),
                  DropdownMenuItem(value: 'Khác', child: Text('📍 Khác')),
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
