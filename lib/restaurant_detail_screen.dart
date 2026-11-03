import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/api_service.dart';
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
  int _selectedCategoryIndex = 0; // 0 = Tất cả, 1, 2... = các danh mục
  bool _isFavorite = false;
  String _menuSearchQuery = '';

  final TextEditingController _menuSearchController = TextEditingController();

  // Giỏ hàng lưu số lượng của từng món ăn: itemId -> quantity
  final Map<String, int> _cartItems = {};
  final Map<String, String> _cartNotes = {};

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

  Future<void> _loadSavedAddressFallback() async {
    if (_deliveryAddress != null && _deliveryLat != null && _deliveryLat != 0) return;
    try {
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
        final addr = map['address']?.toString();
        if (mounted) {
          setState(() {
            _deliveryAddress ??= addr;
            _deliveryLat ??= lat;
            _deliveryLng ??= lng;
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    _menuSearchController.dispose();
    super.dispose();
  }

  // Haversine distance in km
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
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('Đã thêm "${item.name}" vào giỏ hàng')),
          ],
        ),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.orange.shade800,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  List<ApiMenuItem> _filteredMenuItems(List<ApiMenuCategory> categories) {
    List<ApiMenuItem> items = [];
    if (_selectedCategoryIndex == 0) {
      // Tất cả món
      for (final cat in categories) {
        items.addAll(cat.items);
      }
    } else if (_selectedCategoryIndex - 1 < categories.length) {
      items = List.from(categories[_selectedCategoryIndex - 1].items);
    }

    if (_menuSearchQuery.trim().isNotEmpty) {
      final query = _menuSearchQuery.toLowerCase().trim();
      items = items.where((it) =>
        it.name.toLowerCase().contains(query) ||
        it.description.toLowerCase().contains(query)
      ).toList();
    }

    return items;
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
      backgroundColor: const Color(0xFFF8F9FA),
      body: Column(
        children: [
          Expanded(
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  _buildSliverHeader(restaurant),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          _buildRestaurantCard(restaurant),
                          if (_fetchedVouchers.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _buildVoucherRow(),
                          ],
                          const SizedBox(height: 16),
                          _buildTabBarSection(),
                        ],
                      ),
                    ),
                  ),
                ];
              },
              body: TabBarView(
                controller: _tabController,
                children: [
                  _buildMenuTab(categories),
                  _buildReviewsTab(),
                ],
              ),
            ),
          ),
          if (_totalCartCount > 0) _buildCartStickyBottomBar(categories),
        ],
      ),
    );
  }

  // --- SLIVER APP BAR VỚI BANNER VÀ NÚT TÁC VỤ ---
  Widget _buildSliverHeader(ApiRestaurant restaurant) {
    final imgUrl = restaurant.imageUrl;
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.orange,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
        child: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: IconButton(
            icon: Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_border,
              color: _isFavorite ? Colors.red : Colors.black87,
              size: 20,
            ),
            onPressed: () {
              setState(() {
                _isFavorite = !_isFavorite;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_isFavorite
                      ? '❤️ Đã thêm "${restaurant.name}" vào yêu thích'
                      : 'Đã xóa khỏi danh sách yêu thích'),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 8, bottom: 8, right: 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.black87, size: 20),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Đã sao chép liên kết cửa hàng!'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            imgUrl != null && imgUrl.isNotEmpty
                ? Image.network(
                    imgUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _buildFallbackBanner(),
                  )
                : _buildFallbackBanner(),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.5),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.2),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackBanner() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFF7A00), Color(0xFFFF9800)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.storefront_rounded, size: 64, color: Colors.white70),
      ),
    );
  }

  // --- THẺ THÔNG TIN NHÀ HÀNG CHÍNH (ĐỒNG BỘ PHONG CÁCH HOME) ---
  Widget _buildRestaurantCard(ApiRestaurant restaurant) {
    final dist = _calculatedDistance;
    final fee = _deliveryFee;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo / Avatar quán
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orange.shade100),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: restaurant.imageUrl != null && restaurant.imageUrl!.isNotEmpty
                      ? Image.network(
                          restaurant.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.storefront,
                            color: Colors.orange,
                            size: 32,
                          ),
                        )
                      : const Icon(
                          Icons.storefront,
                          color: Colors.orange,
                          size: 32,
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
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange,
                            borderRadius: BorderRadius.circular(6),
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
                        Expanded(
                          child: Text(
                            restaurant.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                        const SizedBox(width: 2),
                        Text(
                          restaurant.averageRating > 0
                              ? restaurant.averageRating.toStringAsFixed(1)
                              : '5.0',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          restaurant.reviewCount > 0
                              ? ' (${restaurant.reviewCount}+)'
                              : ' (Mới)',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                        const SizedBox(width: 8),
                        Text('•', style: TextStyle(color: Colors.grey.shade400)),
                        const SizedBox(width: 8),
                        Icon(Icons.shopping_bag_outlined, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 2),
                        Text(
                          restaurant.totalOrders > 0
                              ? '${restaurant.totalOrders}+ đơn'
                              : 'Đang mở',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          // Địa chỉ & Phí giao hàng
          Row(
            children: [
              Icon(Icons.location_on, color: Colors.orange.shade700, size: 16),
              const SizedBox(width: 4),
              Text(
                dist != null ? '${dist.toStringAsFixed(1)} km' : 'Gần bạn',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  restaurant.address,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.two_wheeler, color: Colors.green.shade700, size: 16),
              const SizedBox(width: 4),
              Text(
                'Phí giao: ${order_data.money(fee)}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.access_time_filled, color: Colors.blue.shade600, size: 15),
              const SizedBox(width: 4),
              Text(
                '20 - 30 phút',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- DÒNG VOUCHER KHUYẾN MÃI CỦA CỬA HÀNG ---
  Widget _buildVoucherRow() {
    return SizedBox(
      height: 34,
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
              ? 'Mã $code: Giảm $discountVal%'
              : 'Mã $code: Giảm ${order_data.money(discountVal)}';

          return Material(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🏷️ Nhớ dùng mã "$code" (Đơn từ ${order_data.money(minAmt)}) khi thanh toán!'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.teal.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.confirmation_num_outlined, size: 14, color: Colors.teal.shade800),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.teal.shade900,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // --- TAB BAR "THỰC ĐƠN" & "ĐÁNH GIÁ" ---
  Widget _buildTabBarSection() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Colors.orange,
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey.shade700,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        tabs: const [
          Tab(text: 'Thực đơn'),
          Tab(text: 'Đánh giá'),
        ],
      ),
    );
  }

  // --- TAB THỰC ĐƠN NGANG PHONG CÁCH HIỆN ĐẠI ---
  Widget _buildMenuTab(List<ApiMenuCategory> categories) {
    final filteredItems = _filteredMenuItems(categories);

    return Column(
      children: [
        // 1. THANH TÌM KIẾM MÓN ĂN & DANH MỤC THU BỎ CỘT DỌC
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              // Thanh tìm kiếm món ăn
              TextField(
                controller: _menuSearchController,
                decoration: InputDecoration(
                  hintText: 'Tìm kiếm món ăn trong quán...',
                  prefixIcon: const Icon(Icons.search, color: Colors.orange),
                  suffixIcon: _menuSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            setState(() {
                              _menuSearchController.clear();
                              _menuSearchQuery = '';
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Colors.orange, width: 1.5),
                  ),
                ),
                onChanged: (val) {
                  setState(() {
                    _menuSearchQuery = val;
                  });
                },
              ),
              const SizedBox(height: 10),
              // Thanh cuộn chọn danh mục dạng Chip
              SizedBox(
                height: 36,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length + 1,
                  itemBuilder: (context, index) {
                    final isAll = index == 0;
                    final title = isAll ? 'Tất cả (${_filteredMenuItemsCount(categories)})' : categories[index - 1].name;
                    final isSelected = index == _selectedCategoryIndex;

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        selected: isSelected,
                        label: Text(
                          title,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                        ),
                        selectedColor: Colors.orange,
                        backgroundColor: Colors.white,
                        checkmarkColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSelected ? Colors.orange : Colors.grey.shade300,
                          ),
                        ),
                        onSelected: (_) {
                          setState(() {
                            _selectedCategoryIndex = index;
                          });
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // 2. DANH SÁCH MÓN ĂN HIỂN THỊ DẠNG DANH SÁCH
        Expanded(
          child: filteredItems.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text(
                          _menuSearchQuery.isNotEmpty
                              ? 'Không tìm thấy món "$_menuSearchQuery"'
                              : 'Chưa có món ăn trong danh mục này.',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: filteredItems.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = filteredItems[index];
                    return _buildFoodCardItem(item);
                  },
                ),
        ),
      ],
    );
  }

  int _filteredMenuItemsCount(List<ApiMenuCategory> categories) {
    int total = 0;
    for (final c in categories) {
      total += c.items.length;
    }
    return total;
  }

  // --- THẺ MÓN ĂN ĐỒNG BỘ DẠNG CARD SANG TRỌNG ---
  Widget _buildFoodCardItem(ApiMenuItem item) {
    final qty = _cartItems[item.id] ?? 0;
    final hasDiscount = item.discountPercent != null && item.discountPercent! > 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Ảnh món ăn
          Stack(
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                      ? Image.network(
                          item.imageUrl!,
                          width: 90,
                          height: 90,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.restaurant_rounded,
                            size: 36,
                            color: Colors.orange,
                          ),
                        )
                      : const Icon(
                          Icons.restaurant_rounded,
                          size: 36,
                          color: Colors.orange,
                        ),
                ),
              ),
              if (hasDiscount)
                Positioned(
                  top: 0,
                  left: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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

          // 2. Chi tiết món ăn
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
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
                Row(
                  children: [
                    Text(
                      item.soldCount > 0 ? '${item.soldCount}+ đã bán' : 'Món mới',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                    ),
                    if (item.likesCount > 0) ...[
                      const SizedBox(width: 6),
                      Text('•', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                      const SizedBox(width: 6),
                      Icon(Icons.favorite_rounded, size: 12, color: Colors.red.shade400),
                      const SizedBox(width: 2),
                      Text('${item.likesCount}', style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Giá tiền
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _formatPrice(item.price),
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (item.originalPrice != null && item.originalPrice! > item.price) ...[
                          const SizedBox(width: 6),
                          Text(
                            _formatPrice(item.originalPrice!),
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 11,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                      ],
                    ),

                    // Nút Thêm món (+ / -)
                    qty == 0
                        ? FilledButton.icon(
                            onPressed: item.isAvailable ? () => _addToCart(item) : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(Icons.add_shopping_cart, size: 14),
                            label: const Text(
                              'Thêm',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.orange.shade300),
                            ),
                            child: Row(
                              children: [
                                InkWell(
                                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                                  onTap: () => _removeFromCart(item),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    child: Icon(Icons.remove, size: 16, color: Colors.orange),
                                  ),
                                ),
                                Text(
                                  '$qty',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.orange,
                                  ),
                                ),
                                InkWell(
                                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
                                  onTap: () => _addToCart(item),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    child: Icon(Icons.add, size: 16, color: Colors.orange),
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
      ),
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
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Column(
                children: [
                  Text(
                    rating > 0 ? rating.toStringAsFixed(1) : '5.0',
                    style: const TextStyle(
                      fontSize: 40,
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
                    reviewCount > 0 ? '$reviewCount+ đánh giá' : 'Chưa có đánh giá',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: [
                    _buildRatingBar('5 ⭐', reviewCount > 0 ? 0.85 : 1.0),
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
        const SizedBox(height: 20),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Nhận xét từ khách hàng',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              '${reviewCount > 0 ? reviewCount : 0} bình luận',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 12),

        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.rate_review_outlined, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Text(
                  reviewCount == 0
                      ? 'Cửa hàng này chưa có đánh giá nào từ khách hàng.'
                      : 'Chưa có bình luận chi tiết nào cho cửa hàng này.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
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
          const SizedBox(width: 14),
          Expanded(
            child: Column(
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
          ),
          FilledButton.icon(
            onPressed: () => _showCheckoutSheet(context, categories),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text(
              'Giao hàng',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.location_on, color: Colors.green),
                    ),
                    title: const Text('Giao đến vị trí của bạn:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green)),
                    subtitle: Text(
                      _deliveryAddress ?? widget.userAddress ?? 'Địa chỉ nhận hàng của bạn',
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
                            final finalAddr = _deliveryAddress ?? widget.userAddress ?? 'Địa chỉ nhận hàng của bạn';
                            setSheetState(() => isSubmitting = true);
                            try {
                              final newOrder = await order_data.OrderData().createOrder(
                                restaurantId: widget.restaurant.id,
                                restaurantName: widget.restaurant.name,
                                restaurantAddress: widget.restaurant.address,
                                items: selectedOrderItems,
                                deliveryAddress: finalAddr,
                                paymentMethod: paymentMethod,
                                deliveryFee: deliveryFee,
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
