import 'dart:math';
import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'order/order_data.dart' as order_data;
import 'order/order_tracking_screen.dart';

class RestaurantDetailScreen extends StatefulWidget {
  final ApiRestaurant restaurant;
  final double? userLat;
  final double? userLng;

  const RestaurantDetailScreen({
    super.key,
    required this.restaurant,
    this.userLat,
    this.userLng,
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

  final ScrollController _menuScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _menuScrollController.dispose();
    super.dispose();
  }

  // Thuật toán Haversine tính khoảng cách (km)
  double? get _calculatedDistance {
    if (widget.userLat == null ||
        widget.userLng == null ||
        widget.restaurant.latitude == null ||
        widget.restaurant.longitude == null) {
      return null;
    }
    const p = 0.017453292519943295;
    final a = 0.5 -
        cos((widget.restaurant.latitude! - widget.userLat!) * p) / 2 +
        cos(widget.userLat! * p) *
            cos(widget.restaurant.latitude! * p) *
            (1 - cos((widget.restaurant.longitude! - widget.userLng!) * p)) /
            2;
    return 12742 * asin(sqrt(a));
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
    final vouchers = [
      'Giảm 15.000đ (Đơn từ 0đ)',
      'Giảm 25.000đ (Đơn từ 99k)',
      'Giảm 50.000đ (Đơn từ 150k)',
      'Freeship 15k',
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
      child: SizedBox(
        height: 32,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: vouchers.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
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
                    vouchers[index],
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
            onPressed: () => _showCheckoutSheet(context, totalPrice, categories),
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

  void _showCheckoutSheet(BuildContext context, double subtotal, List<ApiMenuCategory> categories) {
    final selectedOrderItems = <order_data.OrderItem>[];
    for (final cat in categories) {
      for (final item in cat.items) {
        final qty = _cartItems[item.id] ?? 0;
        if (qty > 0) {
          selectedOrderItems.add(
            order_data.OrderItem(
              id: item.id,
              name: item.name,
              price: item.price.toInt(),
              quantity: qty,
              emoji: '',
            ),
          );
        }
      }
    }

    if (selectedOrderItems.isEmpty) return;

    const deliveryFee = 16000;
    final total = subtotal.toInt() + deliveryFee;
    const paymentMethod = 'Tiền mặt khi nhận hàng (COD)';

    var isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 20,
          ),
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
              const Text('Món đã chọn:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: selectedOrderItems.length,
                  itemBuilder: (_, i) {
                    final it = selectedOrderItems[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Text('${it.quantity}x ', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                          Expanded(child: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                          Text(order_data.money(it.price * it.quantity), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Tiền món:', style: TextStyle(color: Colors.grey)),
                  Text(order_data.money(subtotal.toInt())),
                ],
              ),
              const SizedBox(height: 4),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Phí giao hàng:', style: TextStyle(color: Colors.grey)),
                  Text('16.000 đ'),
                ],
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
                        setSheetState(() => isSubmitting = true);
                        try {
                          final newOrder = await order_data.OrderData().createOrder(
                            restaurantId: widget.restaurant.id,
                            restaurantName: widget.restaurant.name,
                            restaurantAddress: widget.restaurant.address,
                            items: selectedOrderItems,
                            deliveryAddress: 'Địa chỉ nhận hàng của bạn',
                            paymentMethod: paymentMethod,
                            deliveryFee: deliveryFee,
                          );

                          setState(() {
                            _cartItems.clear();
                          });

                          if (ctx.mounted) Navigator.pop(ctx);

                          if (context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrderTrackingScreen(orderId: newOrder.id),
                              ),
                            );

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Đặt đơn #${newOrder.id} thành công! Quán đang nhận đơn.'),
                                backgroundColor: Colors.green,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }
                        } catch (e) {
                          setSheetState(() => isSubmitting = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
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
      ),
    );
  }
}
