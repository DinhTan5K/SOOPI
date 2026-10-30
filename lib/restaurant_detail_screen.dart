import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'services/profile_api_service.dart';
import 'services/api_service.dart';
import 'services/geocoding_service.dart';
import 'services/address_suggestion_service.dart';
import 'models/user_address.dart';
import 'package:geolocator/geolocator.dart';
import 'order/order_data.dart' as order_data;
import 'order/order_tracking_screen.dart';
import 'services/order_api_service.dart';

class RestaurantDetailScreen extends StatefulWidget {
  final ApiRestaurant restaurant;
  final double? userLat;
  final double? userLng;
  final String? userAddress;

  const RestaurantDetailScreen({
    super.key,
    required this.restaurant,
    this.userLat,
    this.userLng,
    this.userAddress,
  });

  @override
  State<RestaurantDetailScreen> createState() => _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState extends State<RestaurantDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedCategoryIndex = 0;
  bool _isFavorite = false;

  // Giỏ hàng lưu số lượng của từng món ăn: itemId -> quantity
  final Map<String, int> _cartItems = {};
  final Map<String, String> _cartNotes = {};

  final ScrollController _menuScrollController = ScrollController();

  String? _deliveryAddress;
  double? _deliveryLat;
  double? _deliveryLng;
  List<Map<String, dynamic>> _fetchedVouchers = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _deliveryAddress = widget.userAddress;
    _deliveryLat = widget.userLat;
    _deliveryLng = widget.userLng;
    _loadSavedAddressFallback();
    _loadRestaurantVouchers();
  }

  Future<void> _loadRestaurantVouchers() async {
    final list = await OrderApiService().fetchRestaurantVouchers(widget.restaurant.id);
    if (mounted) {
      setState(() {
        _fetchedVouchers = list;
      });
    }
  }

  Future<void> _persistSelectedAddress({
    required String address,
    required String label,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
      await prefs.setString(
        'soopi.delivery_address.$uid',
        jsonEncode({
          'address': address,
          'type': label,
          'latitude': latitude,
          'longitude': longitude,
        }),
      );
    } catch (_) {}
  }

  Future<void> _loadSavedAddressFallback() async {
    try {
      // Nếu địa chỉ truyền vào từ Home là chuỗi GPS thô nhưng có tọa độ, dịch ngược ngay sang địa chỉ thật
      if (GeocodingService.isRawCoordinateAddress(_deliveryAddress) &&
          _deliveryLat != null &&
          _deliveryLng != null &&
          _deliveryLat != 0 &&
          _deliveryLng != 0) {
        final resolved = await GeocodingService.reverseGeocode(
          _deliveryLat!,
          _deliveryLng!,
        );
        if (mounted) {
          setState(() {
            _deliveryAddress = resolved;
          });
        }
        await _persistSelectedAddress(
          address: resolved,
          label: 'Vị trí hiện tại',
          latitude: _deliveryLat!,
          longitude: _deliveryLng!,
        );
        return;
      }

      if (!GeocodingService.isRawCoordinateAddress(_deliveryAddress) &&
          _deliveryLat != null &&
          _deliveryLat != 0) {
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
      String? raw = prefs.getString('soopi.delivery_address.$uid');
      if (raw == null) {
        for (final k in prefs.getKeys()) {
          if (k.startsWith('soopi.delivery_address.')) {
            final val = prefs.getString(k);
            if (val != null && val.isNotEmpty) {
              raw = val;
              break;
            }
          }
        }
      }
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final lat = (map['latitude'] as num?)?.toDouble();
        final lng = (map['longitude'] as num?)?.toDouble();
        var addr = map['address']?.toString();

        if (GeocodingService.isRawCoordinateAddress(addr) &&
            lat != null &&
            lng != null &&
            lat != 0 &&
            lng != 0) {
          addr = await GeocodingService.reverseGeocode(lat, lng);
          await _persistSelectedAddress(
            address: addr,
            label: map['type']?.toString() ?? 'Vị trí hiện tại',
            latitude: lat,
            longitude: lng,
          );
        }

        if (mounted) {
          setState(() {
            if (!GeocodingService.isRawCoordinateAddress(addr)) {
              _deliveryAddress = addr;
            }
            _deliveryLat ??= lat;
            _deliveryLng ??= lng;
          });
        }
      }

      // Nếu vẫn chưa có địa chỉ rõ ràng, lấy địa chỉ mặc định trong Sổ địa chỉ
      if (GeocodingService.isRawCoordinateAddress(_deliveryAddress)) {
        final profileAddresses = await ProfileApiService().getAddresses();
        if (profileAddresses.isNotEmpty) {
          final def = profileAddresses.firstWhere(
            (a) => a.isDefault,
            orElse: () => profileAddresses.first,
          );
          if (def.fullAddress.trim().isNotEmpty) {
            final coords = await GeocodingService.getCoordinatesFromAddress(
              def.fullAddress.trim(),
            );
            final lat = coords?.latitude ?? _deliveryLat ?? 10.77689;
            final lng = coords?.longitude ?? _deliveryLng ?? 106.70089;
            if (mounted) {
              setState(() {
                _deliveryAddress = def.fullAddress.trim();
                _deliveryLat = lat;
                _deliveryLng = lng;
              });
            }
            await _persistSelectedAddress(
              address: def.fullAddress.trim(),
              label: def.label,
              latitude: lat,
              longitude: lng,
            );
          }
        }
      }
    } catch (_) {}
  }

  Future<bool> _showChangeDeliveryAddressSheet(BuildContext parentContext) async {
    List<UserAddress> profileAddresses = [];
    try {
      profileAddresses = await ProfileApiService().getAddresses();
    } catch (_) {}

    if (!mounted) return false;

    final searchController = TextEditingController();
    List<AddressSuggestion> suggestions = [];
    bool isSearching = false;
    bool isLocatingGps = false;
    int searchVersion = 0;

    final selectedResult = await showModalBottomSheet<Map<String, dynamic>>(
      context: parentContext,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setModalState) {
          Future<void> onSearchChanged(String val) async {
            final ver = ++searchVersion;
            if (val.trim().length < 3) {
              setModalState(() {
                suggestions = [];
                isSearching = false;
              });
              return;
            }
            setModalState(() => isSearching = true);
            await Future<void>.delayed(const Duration(milliseconds: 500));
            if (ver != searchVersion || !sheetCtx.mounted) return;
            try {
              final res = await AddressSuggestionService.search(val.trim());
              if (ver == searchVersion && sheetCtx.mounted) {
                setModalState(() {
                  suggestions = res;
                  isSearching = false;
                });
              }
            } catch (_) {
              if (ver == searchVersion && sheetCtx.mounted) {
                setModalState(() {
                  suggestions = [];
                  isSearching = false;
                });
              }
            }
          }

          Future<void> useCurrentGps() async {
            if (isLocatingGps) return;
            setModalState(() => isLocatingGps = true);
            try {
              var perm = await Geolocator.checkPermission();
              if (perm == LocationPermission.denied) {
                perm = await Geolocator.requestPermission();
              }
              if (perm == LocationPermission.denied ||
                  perm == LocationPermission.deniedForever) {
                throw Exception('Chưa cấp quyền truy cập vị trí GPS.');
              }
              final pos = await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.high,
                  timeLimit: Duration(seconds: 15),
                ),
              );

              String resolvedAddr = '';
              String resolvedLabel = 'Vị trí hiện tại';
              final near = await GeocodingService.findNearestSavedAddress(
                pos.latitude,
                pos.longitude,
                profileAddresses,
                maxDistanceMeters: 120,
              );
              if (near != null) {
                resolvedAddr = near.address.fullAddress.trim();
                resolvedLabel = near.address.label;
              } else {
                resolvedAddr = await GeocodingService.reverseGeocode(
                  pos.latitude,
                  pos.longitude,
                );
              }

              if (sheetCtx.mounted) {
                Navigator.pop(sheetCtx, {
                  'address': resolvedAddr,
                  'label': resolvedLabel,
                  'latitude': pos.latitude,
                  'longitude': pos.longitude,
                });
              }
            } catch (e) {
              if (sheetCtx.mounted) {
                setModalState(() => isLocatingGps = false);
                ScaffoldMessenger.of(sheetCtx).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Không lấy được GPS: ${e.toString().replaceFirst('Exception: ', '')}',
                    ),
                  ),
                );
              }
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
              left: 20,
              right: 20,
              top: 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Đổi địa chỉ giao hàng',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 46),
                      side: const BorderSide(color: Colors.orange),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: isLocatingGps ? null : useCurrentGps,
                    icon: isLocatingGps
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location, color: Colors.orange),
                    label: Text(
                      isLocatingGps
                          ? 'Đang xác định địa chỉ cụ thể...'
                          : 'Dùng vị trí hiện tại (Tự động tìm số nhà/tên đường)',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Nhập số nhà, tên đường, phường/quận...',
                      prefixIcon: const Icon(Icons.search, color: Colors.orange),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.check_circle, color: Colors.green),
                        tooltip: 'Dùng địa chỉ vừa nhập',
                        onPressed: () async {
                          final q = searchController.text.trim();
                          if (q.isEmpty) return;
                          final coords =
                              await GeocodingService.getCoordinatesFromAddress(q);
                          if (sheetCtx.mounted) {
                            Navigator.pop(sheetCtx, {
                              'address': q,
                              'label': 'Địa chỉ tùy chỉnh',
                              'latitude':
                                  coords?.latitude ?? _deliveryLat ?? 10.77689,
                              'longitude':
                                  coords?.longitude ?? _deliveryLng ?? 106.70089,
                            });
                          }
                        },
                      ),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  if (isSearching)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: suggestions.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final s = suggestions[i];
                          return ListTile(
                            dense: true,
                            leading: const Icon(
                              Icons.place_outlined,
                              color: Colors.orange,
                            ),
                            title: Text(
                              s.displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                            onTap: () => Navigator.pop(sheetCtx, {
                              'address': s.displayName,
                              'label': 'Địa chỉ giao hàng',
                              'latitude': s.latitude,
                              'longitude': s.longitude,
                            }),
                          );
                        },
                      ),
                    ),
                  ],
                  if (profileAddresses.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Địa chỉ đã lưu trong hồ sơ:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: profileAddresses.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final addr = profileAddresses[i];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              addr.label == 'Văn phòng'
                                  ? Icons.business
                                  : (addr.label == 'Nhà riêng'
                                      ? Icons.home
                                      : Icons.location_on),
                              color: Colors.orange,
                            ),
                            title: Text(
                              addr.label,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              addr.fullAddress,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () async {
                              final coords = await GeocodingService
                                  .getCoordinatesFromAddress(addr.fullAddress);
                              if (sheetCtx.mounted) {
                                Navigator.pop(sheetCtx, {
                                  'address': addr.fullAddress,
                                  'label': addr.label,
                                  'latitude': coords?.latitude ??
                                      _deliveryLat ??
                                      10.77689,
                                  'longitude': coords?.longitude ??
                                      _deliveryLng ??
                                      106.70089,
                                });
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );

    if (selectedResult != null && mounted) {
      final newAddr = selectedResult['address']?.toString() ?? '';
      final newLabel = selectedResult['label']?.toString() ?? 'Địa chỉ giao hàng';
      final newLat = (selectedResult['latitude'] as num?)?.toDouble();
      final newLng = (selectedResult['longitude'] as num?)?.toDouble();
      if (newAddr.isNotEmpty) {
        setState(() {
          _deliveryAddress = newAddr;
          if (newLat != null && newLat != 0) _deliveryLat = newLat;
          if (newLng != null && newLng != 0) _deliveryLng = newLng;
        });
        if (newLat != null && newLng != null) {
          await _persistSelectedAddress(
            address: newAddr,
            label: newLabel,
            latitude: newLat,
            longitude: newLng,
          );
        }
        return true;
      }
    }
    return false;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _menuScrollController.dispose();
    super.dispose();
  }

  // Thuật toán Haversine tính khoảng cách (km)
  double? get _calculatedDistance {
    final userLat = _deliveryLat ?? widget.userLat;
    final userLng = _deliveryLng ?? widget.userLng;
    if (userLat == null ||
        userLng == null ||
        widget.restaurant.latitude == null ||
        widget.restaurant.longitude == null) {
      return null;
    }
    const p = 0.017453292519943295;
    final a = 0.5 -
        cos((widget.restaurant.latitude! - userLat) * p) / 2 +
        cos(userLat * p) *
            cos(widget.restaurant.latitude! * p) *
            (1 - cos((widget.restaurant.longitude! - userLng) * p)) /
            2;
    return 12742 * asin(sqrt(a));
  }

  int get _deliveryFee {
    final distance = _calculatedDistance;
    if (distance == null) return 16000;
    return 5000 + distance.ceil() * 2000;
  }

  void _addToCart(ApiMenuItem item) {
    setState(() {
      _cartItems[item.id] = (_cartItems[item.id] ?? 0) + 1;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã thêm "${item.name}" vào giỏ hàng!'),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.orange.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _removeFromCart(ApiMenuItem item) {
    setState(() {
      final current = _cartItems[item.id] ?? 0;
      if (current <= 1) {
        _cartItems.remove(item.id);
        _cartNotes.remove(item.id);
      } else {
        _cartItems[item.id] = current - 1;
      }
    });
  }

  int get _totalCartCount {
    return _cartItems.values.fold(0, (sum, qty) => sum + qty);
  }

  double _totalCartPrice(List<ApiMenuCategory> categories) {
    double total = 0.0;
    for (final cat in categories) {
      for (final item in cat.items) {
        final qty = _cartItems[item.id] ?? 0;
        if (qty > 0) {
          total += item.price * qty;
        }
      }
    }
    return total;
  }

  String _formatPrice(double amount) {
    return '${amount.toInt().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')}đ';
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = widget.restaurant;
    final categories = restaurant.categories.isNotEmpty
        ? restaurant.categories
        : [
            ApiMenuCategory(
              id: 'default',
              name: 'Món chính',
              items: [],
            ),
          ];

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildStoreImageBanner(),
                          _buildStoreHeaderInfo(),
                          _buildVoucherRow(),
                          _buildTabBar(),
                        ],
                      ),
                    ),
                  ];
                },
                body: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTwoColumnMenu(categories),
                    _buildReviewsTab(),
                  ],
                ),
              ),
            ),
            if (_totalCartCount > 0) _buildCartStickyBottomBar(categories),
          ],
        ),
      ),
    );
  }

  // --- TOP BAR CÓ NÚT BACK, SEARCH, FAVORITE, SHARE ---
  Widget _buildAppBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black87),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_border,
              color: _isFavorite ? Colors.red : Colors.black87,
            ),
            onPressed: () {
              setState(() {
                _isFavorite = !_isFavorite;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_isFavorite
                      ? 'Đã thêm vào danh sách Yêu thích'
                      : 'Đã xóa khỏi danh sách Yêu thích'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.black87),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  // --- BANNER ẢNH CỦA CỬA HÀNG ---
  Widget _buildStoreImageBanner() {
    final imgUrl = widget.restaurant.imageUrl;
    return Container(
      height: 160,
      width: double.infinity,
      color: Colors.orange.shade100,
      child: imgUrl != null && imgUrl.isNotEmpty
          ? Image.network(
              imgUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _buildFallbackBanner(),
            )
          : _buildFallbackBanner(),
    );
  }

  Widget _buildFallbackBanner() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orangeAccent, Colors.deepOrangeAccent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lunch_dining_rounded, size: 44, color: Colors.white70),
            SizedBox(width: 14),
            Icon(Icons.ramen_dining_rounded, size: 50, color: Colors.white),
            SizedBox(width: 14),
            Icon(Icons.local_drink_rounded, size: 44, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  // --- THÔNG TIN CỬA HÀNG (TÊN, ĐÁNH GIÁ, KHOẢNG CÁCH, TỔNG ĐƠN) ---
  Widget _buildStoreHeaderInfo() {
    final res = widget.restaurant;
    final dist = _calculatedDistance;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: res.imageUrl != null && res.imageUrl!.isNotEmpty
                      ? Image.network(
                          res.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.storefront,
                            color: Colors.orange,
                            size: 28,
                          ),
                        )
                      : const Icon(
                          Icons.storefront,
                          color: Colors.orange,
                          size: 28,
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Yêu thích',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.check_circle,
                            color: Colors.orange, size: 16),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            res.name,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 16),
                        const SizedBox(width: 2),
                        Text(
                          res.averageRating > 0
                              ? res.averageRating.toStringAsFixed(1)
                              : 'Mới',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          res.reviewCount > 0
                              ? ' (${res.reviewCount}+ Đánh giá)'
                              : ' (Chưa có đánh giá)',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 13),
                        ),
                        const SizedBox(width: 8),
                        const Text('•', style: TextStyle(color: Colors.grey)),
                        const SizedBox(width: 8),
                        Text(
                          res.totalOrders > 0
                              ? '${res.totalOrders}+ Đơn đã làm'
                              : 'Quán mới',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            color: Colors.orange, size: 14),
                        const SizedBox(width: 2),
                        Text(
                          dist != null
                              ? '${dist.toStringAsFixed(1)} km'
                              : 'Gần bạn',
                          style: const TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            res.address,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12),
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
        ],
      ),
    );
  }

  // --- DÒNG VOUCHER KHUYẾN MÃI CỦA CỬA HÀNG ---
  Widget _buildVoucherRow() {
    if (_fetchedVouchers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
      child: SizedBox(
        height: 32,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _fetchedVouchers.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final v = _fetchedVouchers[index];
            final code = v['code']?.toString() ?? '';
            final discountType = v['discountType']?.toString() ?? 'Percent';
            final discountVal = (v['discountValue'] as num?)?.toInt() ?? 0;
            final minAmt = (v['minOrderAmount'] as num?)?.toInt() ?? 0;
            final label = discountType == 'Percent'
                ? 'Mã $code: Giảm $discountVal% (Đơn ${order_data.money(minAmt)})'
                : 'Mã $code: Giảm ${order_data.money(discountVal)} (Đơn ${order_data.money(minAmt)})';

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                border: Border.all(color: Colors.teal.shade200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.confirmation_num_outlined,
                      size: 14, color: Colors.teal.shade700),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.teal.shade800,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // --- TAB BAR "THỰC ĐƠN" & "ĐÁNH GIÁ" ---
  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        indicatorColor: Colors.orange,
        indicatorWeight: 3,
        labelColor: Colors.orange,
        unselectedLabelColor: Colors.black87,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        tabs: const [
          Tab(text: 'Thực đơn'),
          Tab(text: 'Đánh giá'),
        ],
      ),
    );
  }

  // --- THỰC ĐƠN BỐ CỤC 2 CỘT (CỘT TRÁI: TAG DANH MỤC, CỘT PHẢI: MÓN ĂN) ---
  Widget _buildTwoColumnMenu(List<ApiMenuCategory> categories) {
    if (categories.isEmpty ||
        categories.every((cat) => cat.items.isEmpty)) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Cửa hàng chưa cập nhật thực đơn.',
            style: TextStyle(color: Colors.grey, fontSize: 15),
          ),
        ),
      );
    }

    final selectedCat = categories[_selectedCategoryIndex < categories.length
        ? _selectedCategoryIndex
        : 0];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // CỘT TRÁI: DANH SÁCH TAG DANH MỤC
        Container(
          width: 115,
          color: Colors.grey.shade100,
          child: ListView.builder(
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              final isSelected = index == _selectedCategoryIndex;

              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedCategoryIndex = index;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 14),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white : Colors.grey.shade100,
                    border: Border(
                      left: BorderSide(
                        color: isSelected ? Colors.orange : Colors.transparent,
                        width: 4,
                      ),
                    ),
                  ),
                  child: Text(
                    cat.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.orange : Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            },
          ),
        ),

        // CỘT PHẢI: DANH SÁCH MÓN ĂN THUỘC DANH MỤC ĐƯỢC CHỌN
        Expanded(
          child: Container(
            color: Colors.white,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Row(
                  children: [
                    Text(
                      selectedCat.name.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(${selectedCat.items.length})',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (selectedCat.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        'Chưa có món ăn trong danh mục này.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: selectedCat.items.length,
                    separatorBuilder: (_, _) => const Divider(height: 24),
                    itemBuilder: (context, itemIdx) {
                      final item = selectedCat.items[itemIdx];
                      return _buildFoodItemRow(item);
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- HÀNG TỪNG MÓN ĂN VỚI HÌNH ẢNH, TÊN, GIÁ, ĐÃ BÁN, NÚT MUA ---
  Widget _buildFoodItemRow(ApiMenuItem item) {
    final qty = _cartItems[item.id] ?? 0;
    final hasDiscount = item.discountPercent != null && item.discountPercent! > 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // HÌNH ẢNH MÓN ĂN VỚI BADGE GIẢM GIÁ
        Stack(
          children: [
            Container(
              width: 85,
              height: 85,
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                    ? Image.network(
                        item.imageUrl!,
                        width: 85,
                        height: 85,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(Icons.restaurant_rounded, size: 36, color: Colors.grey),
                        ),
                      )
                    : const Center(
                        child: Icon(Icons.restaurant_rounded, size: 36, color: Colors.grey),
                      ),
              ),
            ),
            if (hasDiscount)
              Positioned(
                top: 0,
                left: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  child: Text(
                    '-${item.discountPercent}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),

        // THÔNG TIN MÓN ĂN (TÊN, ĐÃ BÁN, GIÁ)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.description.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  item.description,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 4),
              Text(
                item.soldCount > 0
                    ? '${item.soldCount}+ đã bán • ${item.likesCount} lượt thích'
                    : 'Món mới',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatPrice(item.price),
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (item.originalPrice != null &&
                          item.originalPrice! > item.price)
                        Text(
                          _formatPrice(item.originalPrice!),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 11,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                    ],
                  ),

                  // NÚT THÊM VÀO GIỎ HÀNG (+ / -)
                  qty == 0
                      ? ElevatedButton(
                          onPressed: item.isAvailable ? () => _addToCart(item) : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Mua ngay',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              InkWell(
                                onTap: () => _removeFromCart(item),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(Icons.remove,
                                      size: 16, color: Colors.orange),
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  '$qty',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => _addToCart(item),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(Icons.add,
                                      size: 16, color: Colors.orange),
                                ),
                              ),
                            ],
                          ),
                        ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- TAB ĐÁNH GIÁ CỦA KHÁCH HÀNG ---
  Widget _buildReviewsTab() {
    final reviewCount = widget.restaurant.reviewCount;
    final rating = widget.restaurant.averageRating;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Column(
                children: [
                  Text(
                    rating > 0 ? rating.toStringAsFixed(1) : '5.0',
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                  const Row(
                    children: [
                      Icon(Icons.star, color: Colors.amber, size: 16),
                      Icon(Icons.star, color: Colors.amber, size: 16),
                      Icon(Icons.star, color: Colors.amber, size: 16),
                      Icon(Icons.star, color: Colors.amber, size: 16),
                      Icon(Icons.star, color: Colors.amber, size: 16),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    reviewCount > 0
                        ? '$reviewCount+ đánh giá'
                        : 'Chưa có đánh giá',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: [
                    _buildRatingBar('5 ⭐', reviewCount > 0 ? 0.85 : 0.0),
                    _buildRatingBar('4 ⭐', reviewCount > 0 ? 0.10 : 0.0),
                    _buildRatingBar('3 ⭐', reviewCount > 0 ? 0.03 : 0.0),
                    _buildRatingBar('2 ⭐', reviewCount > 0 ? 0.01 : 0.0),
                    _buildRatingBar('1 ⭐', reviewCount > 0 ? 0.01 : 0.0),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        const Text(
          'Đánh giá gần đây',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Text(
              reviewCount == 0
                  ? 'Cửa hàng này chưa có đánh giá nào từ khách hàng.'
                  : 'Chưa có bình luận chi tiết nào cho cửa hàng này.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRatingBar(String label, double percent) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(label, style: const TextStyle(fontSize: 11)),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: percent,
              color: Colors.amber,
              backgroundColor: Colors.grey.shade200,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }


  // --- THANH GIỎ HÀNG DÍNH Ở ĐÁY MÀN HÌNH ---
  Widget _buildCartStickyBottomBar(List<ApiMenuCategory> categories) {
    final count = _totalCartCount;
    final totalPrice = _totalCartPrice(categories);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 26),
                  ),
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatPrice(totalPrice),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const Text(
                    'Đã bao gồm thuế & phí',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          ElevatedButton(
            onPressed: () => _showCheckoutSheet(context, categories),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Giao hàng',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  List<order_data.OrderItem> _currentOrderItems(List<ApiMenuCategory> categories) {
    final items = <order_data.OrderItem>[];
    for (final category in categories) {
      for (final item in category.items) {
        final quantity = _cartItems[item.id] ?? 0;
        if (quantity > 0) {
          items.add(order_data.OrderItem(
            id: item.id,
            name: item.name,
            price: item.price.toInt(),
            quantity: quantity,
            note: _cartNotes[item.id] ?? '',
          ));
        }
      }
    }
    return items;
  }

  Future<void> _showCheckoutSheet(BuildContext context, List<ApiMenuCategory> categories) async {
    if (_totalCartCount == 0) return;
    Map<String, dynamic>? selectedVoucher;
    String? voucherMessage;
    var isSubmitting = false;
    var isApplyingVoucher = false;
    const paymentMethod = 'Tiền mặt khi nhận hàng (COD)';
    final voucherCodeController = TextEditingController();

    final createdOrder = await showModalBottomSheet<order_data.OrderModel>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final selectedOrderItems = _currentOrderItems(categories);
          final currentSubtotal = selectedOrderItems.fold<int>(0, (sum, item) => sum + item.price * item.quantity);
          final deliveryFee = _deliveryFee;
          final discount = (selectedVoucher?['discountAmount'] as num?)?.round() ?? 0;
          final total = currentSubtotal + deliveryFee - discount;

          Future<void> applyVoucher(String rawCode) async {
            final code = rawCode.trim().toUpperCase();
            if (code.isEmpty) {
              setSheetState(() => voucherMessage = 'Nhập mã voucher trước.');
              return;
            }
            setSheetState(() {
              isApplyingVoucher = true;
              voucherMessage = null;
            });
            try {
              final preview = await OrderApiService().previewDirectVoucher(
                restaurantId: widget.restaurant.id,
                couponCode: code,
                items: selectedOrderItems,
              );
              if (!ctx.mounted) return;
              setSheetState(() {
                selectedVoucher = {
                  ...preview,
                  'code': preview['couponCode']?.toString() ?? code,
                };
                voucherCodeController.text = selectedVoucher!['code'].toString();
                voucherMessage = 'Đã áp dụng ${selectedVoucher!['code']}.';
                isApplyingVoucher = false;
              });
            } catch (error) {
              if (!ctx.mounted) return;
              setSheetState(() {
                selectedVoucher = null;
                voucherMessage = error.toString().replaceFirst('Exception: ', '');
                isApplyingVoucher = false;
              });
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              left: 20,
              right: 20,
              top: 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Xác nhận đặt đơn hàng',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.storefront, color: Colors.orange),
                ),
                title: Text(widget.restaurant.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(widget.restaurant.address, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: isSubmitting
                    ? null
                    : () async {
                        final changed =
                            await _showChangeDeliveryAddressSheet(ctx);
                        if (changed && ctx.mounted) {
                          setSheetState(() {});
                        }
                      },
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.location_on, color: Colors.green),
                ),
                title: const Text('Giao đến vị trí của bạn:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green)),
                subtitle: Text(
                  !GeocodingService.isRawCoordinateAddress(_deliveryAddress)
                      ? _deliveryAddress!
                      : (!GeocodingService.isRawCoordinateAddress(widget.userAddress)
                          ? widget.userAddress!
                          : 'Nhấn vào đây để chọn địa chỉ nhận hàng cụ thể'),
                  style: TextStyle(
                    fontSize: 12,
                    color: !GeocodingService.isRawCoordinateAddress(
                                _deliveryAddress ?? widget.userAddress)
                        ? Colors.black87
                        : Colors.deepOrange,
                    fontWeight: !GeocodingService.isRawCoordinateAddress(
                                _deliveryAddress ?? widget.userAddress)
                        ? FontWeight.normal
                        : FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: TextButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final changed =
                              await _showChangeDeliveryAddressSheet(ctx);
                          if (changed && ctx.mounted) {
                            setSheetState(() {});
                          }
                        },
                  icon: const Icon(Icons.edit_location_alt, size: 16, color: Colors.orange),
                  label: const Text(
                    'Thay đổi',
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const Divider(),
              const Text('Món đã chọn:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: selectedOrderItems.length,
                  itemBuilder: (_, i) {
                    final it = selectedOrderItems[i];
                    final menuItem = categories.expand((c) => c.items).firstWhere((item) => item.id == it.id);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Column(
                        children: [
                          Row(children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: isSubmitting || isApplyingVoucher ? null : () {
                                _removeFromCart(menuItem);
                                setSheetState(() {
                                  selectedVoucher = null;
                                  voucherMessage = 'Giỏ hàng đã đổi, hãy áp dụng lại voucher.';
                                });
                              },
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.orange),
                            ),
                            Text('${it.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: isSubmitting || isApplyingVoucher ? null : () {
                                _cartItems[menuItem.id] = (_cartItems[menuItem.id] ?? 0) + 1;
                                setSheetState(() {
                                  selectedVoucher = null;
                                  voucherMessage = 'Giỏ hàng đã đổi, hãy áp dụng lại voucher.';
                                });
                              },
                              icon: const Icon(Icons.add_circle_outline, color: Colors.orange),
                            ),
                            Expanded(child: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            Text(order_data.money(it.price * it.quantity), style: const TextStyle(fontWeight: FontWeight.w600)),
                          ]),
                          TextFormField(
                            key: ValueKey('cart-note-${it.id}'),
                            initialValue: _cartNotes[it.id] ?? '',
                            decoration: const InputDecoration(
                              isDense: true,
                              prefixIcon: Icon(Icons.edit_note, size: 19),
                              hintText: 'Ghi chú món này (ít cay, không hành...)',
                            ),
                            onChanged: (value) {
                              _cartNotes[it.id] = value;
                              setSheetState(() {});
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Divider(),
              const Text('Voucher', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              if (_fetchedVouchers.isNotEmpty) ...[
                const Text(
                  'Mã voucher khả dụng (Nhấn để chọn):',
                  style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _fetchedVouchers.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, idx) {
                      final v = _fetchedVouchers[idx];
                      final code = v['code']?.toString() ?? '';
                      final isSelected = selectedVoucher?['code'] == code;
                      final discountType = v['discountType']?.toString() ?? 'Percent';
                      final discountVal = (v['discountValue'] as num?)?.toInt() ?? 0;
                      final minAmt = (v['minOrderAmount'] as num?)?.toInt() ?? 0;
                      final discountText = discountType == 'Percent'
                          ? 'Giảm $discountVal%'
                          : 'Giảm ${order_data.money(discountVal)}';

                      return FilterChip(
                        selected: isSelected,
                        avatar: Icon(Icons.local_offer, size: 14, color: isSelected ? Colors.white : Colors.orange),
                        label: Text(
                          '$code - $discountText (đơn từ ${order_data.money(minAmt)})',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                        ),
                        selectedColor: Colors.orange,
                        backgroundColor: Colors.orange.shade50,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        onSelected: isSubmitting || isApplyingVoucher
                            ? null
                            : (selected) {
                                if (selected) {
                                  voucherCodeController.text = code;
                                  applyVoucher(code);
                                }
                              },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: voucherCodeController,
                      enabled: !isApplyingVoucher,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Hoặc nhập mã voucher thủ công',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setSheetState(() {
                        selectedVoucher = null;
                        voucherMessage = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: isSubmitting || isApplyingVoucher
                        ? null
                        : () => applyVoucher(voucherCodeController.text),
                    child: isApplyingVoucher
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Áp dụng'),
                  ),
                ],
              ),
                if (voucherMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(voucherMessage!, style: TextStyle(
                      color: selectedVoucher == null ? Colors.deepOrange : Colors.green,
                      fontSize: 12,
                    )),
                  ),
                const SizedBox(height: 6),
                if (selectedVoucher != null)
                  Text(
                    'Đã giảm ${order_data.money(discount)}',
                    style: const TextStyle(color: Colors.green, fontSize: 12),
                  ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Tiền món:', style: TextStyle(color: Colors.grey)),
                  Text(order_data.money(currentSubtotal)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Phí giao hàng${_calculatedDistance == null ? '' : ' (${_calculatedDistance!.toStringAsFixed(1)} km)'}:', style: const TextStyle(color: Colors.grey)),
                  Text(order_data.money(deliveryFee)),
                ],
              ),
              if (discount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Voucher:', style: TextStyle(color: Colors.green)),
                    Text('-${order_data.money(discount)}', style: const TextStyle(color: Colors.green)),
                  ]),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Tổng thanh toán:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(
                    order_data.money(total),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.red),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        var finalAddr = _deliveryAddress ?? widget.userAddress ?? '';
                        final targetLat = _deliveryLat ?? widget.userLat;
                        final targetLng = _deliveryLng ?? widget.userLng;

                        setSheetState(() => isSubmitting = true);
                        try {
                          if (GeocodingService.isRawCoordinateAddress(finalAddr)) {
                            if (targetLat != null &&
                                targetLng != null &&
                                targetLat != 0 &&
                                targetLng != 0) {
                              finalAddr = await GeocodingService.reverseGeocode(
                                targetLat,
                                targetLng,
                              );
                              _deliveryAddress = finalAddr;
                            } else {
                              setSheetState(() => isSubmitting = false);
                              final picked =
                                  await _showChangeDeliveryAddressSheet(ctx);
                              if (!picked || !ctx.mounted) return;
                              setSheetState(() => isSubmitting = true);
                              finalAddr = _deliveryAddress ?? '';
                            }
                          }

                          final newOrder = await order_data.OrderData().createOrder(
                            restaurantId: widget.restaurant.id,
                            restaurantName: widget.restaurant.name,
                            restaurantAddress: widget.restaurant.address,
                            items: selectedOrderItems,
                            deliveryAddress: finalAddr,
                            paymentMethod: paymentMethod,
                            deliveryFee: _deliveryFee,
                            discount: discount,
                            couponCode: selectedVoucher?['code']?.toString(),
                            userLat: _deliveryLat ?? widget.userLat,
                            userLng: _deliveryLng ?? widget.userLng,
                            restaurantLat: widget.restaurant.latitude,
                            restaurantLng: widget.restaurant.longitude,
                          );

                          if (ctx.mounted) {
                            Navigator.pop(ctx, newOrder);
                          }
                        } catch (e) {
                          setSheetState(() => isSubmitting = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text('❌ Đặt hàng thất bại: $e'),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          }
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Xác nhận Đặt hàng', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
              ),
            ),
          );
        },
      ),
    );

    if (createdOrder != null && context.mounted) {
      setState(() {
        _cartItems.clear();
        _cartNotes.clear();
      });

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OrderTrackingScreen(orderId: createdOrder.id),
        ),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 Đặt đơn #${createdOrder.id} thành công! Quán đang nhận đơn.'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
    voucherCodeController.dispose();
  }
}
