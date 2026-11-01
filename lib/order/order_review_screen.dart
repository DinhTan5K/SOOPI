import 'package:flutter/material.dart';
import 'order_data.dart';
import '../services/shipper_earnings_service.dart';
import '../services/restaurant_review_service.dart';
import '../services/profile_api_service.dart';

class OrderReviewScreen extends StatefulWidget {
  final OrderModel order;

  const OrderReviewScreen({super.key, required this.order});

  @override
  State<OrderReviewScreen> createState() => _OrderReviewScreenState();
}

class _OrderReviewScreenState extends State<OrderReviewScreen> {
  int _restaurantRating = 5;
  final Set<String> _selectedRestaurantTags = {};
  final TextEditingController _restaurantCommentController = TextEditingController();

  int _shipperRating = 5;
  final Set<String> _selectedShipperTags = {};
  final TextEditingController _shipperCommentController = TextEditingController();
  int _tipAmount = 0;

  final List<String> _restaurantQuickTags = [
    'Món nóng hổi',
    'Đóng gói cẩn thận',
    'Hương vị tuyệt hảo',
    'Đúng số lượng món',
    'Giá cả hợp lý',
    'Nguyên liệu tươi ngon',
  ];

  final List<String> _shipperQuickTags = [
    'Giao hàng nhanh nhẹn',
    'Thân thiện, lịch sự',
    'Bảo quản đồ cẩn thận',
    'Nhiệt tình hỗ trợ',
    'Đúng hẹn',
  ];

  final List<int> _tipOptions = [0, 10000, 20000, 50000];

  @override
  void dispose() {
    _restaurantCommentController.dispose();
    _shipperCommentController.dispose();
    super.dispose();
  }

  bool _isSubmitting = false;

  Future<void> _submitReview() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    final review = ReviewModel(
      restaurantRating: _restaurantRating,
      restaurantTags: _selectedRestaurantTags.toList(),
      restaurantComment: _restaurantCommentController.text.trim(),
      shipperRating: _shipperRating,
      shipperTags: _selectedShipperTags.toList(),
      shipperComment: _shipperCommentController.text.trim(),
      tipAmount: _tipAmount,
      createdAt: DateTime.now(),
    );

    OrderData().submitReview(widget.order.id, review);

    final dishes = widget.order.items.map((i) => i.name).toList();
    final profile = ProfileApiService().cachedProfile;
    final customerName = (profile != null && profile.fullName.isNotEmpty) ? profile.fullName : 'Khách hàng SOOPI';
    final customerAvatar = profile?.avatarUrl ?? '';

    // Ghi nhận ngay đánh giá của khách hàng vào trang Quán ăn để hiển thị bình luận
    await RestaurantReviewService().addReview(
      orderId: widget.order.backendId ?? widget.order.id,
      restaurantId: widget.order.restaurantId ?? '',
      restaurantName: widget.order.restaurantName,
      customerName: customerName,
      customerAvatar: customerAvatar,
      rating: _restaurantRating,
      tags: _selectedRestaurantTags.toList(),
      comment: _restaurantCommentController.text.trim(),
      dishNames: dishes,
    );

    // Ghi nhận ngay đánh giá của khách hàng vào tài khoản tài xế
    final shipperComment = _shipperCommentController.text.trim().isNotEmpty
        ? _shipperCommentController.text.trim()
        : _restaurantCommentController.text.trim();
    final shipperTags = _selectedShipperTags.isNotEmpty
        ? _selectedShipperTags.toList()
        : _selectedRestaurantTags.toList();

    await ShipperEarningsService().recordCustomerReview(
      orderId: widget.order.backendId ?? widget.order.id,
      orderCode: widget.order.orderCode ?? widget.order.id,
      restaurantName: widget.order.restaurantName,
      rating: _shipperRating,
      comment: shipperComment,
      tipAmount: _tipAmount,
      tags: shipperTags,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cảm ơn bạn đã đánh giá đơn hàng!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Đánh giá & Bình luận',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildRestaurantSection(),

            const SizedBox(height: 20),

            _buildShipperSection(),
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _isSubmitting ? null : _submitReview,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'Gửi đánh giá',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildRestaurantSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(widget.order.restaurantEmoji, style: const TextStyle(fontSize: 24)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Đánh giá Nhà hàng / Món ăn', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                      widget.order.restaurantName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (index) {
                final star = index + 1;
                return IconButton(
                  onPressed: () => setState(() => _restaurantRating = star),
                  icon: Icon(
                    star <= _restaurantRating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 36,
                  ),
                );
              }),
            ),
          ),
          Center(
            child: Text(
              _ratingLabel(_restaurantRating),
              style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Bạn cảm thấy thế nào về món ăn?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _restaurantQuickTags.map((tag) {
              final isSelected = _selectedRestaurantTags.contains(tag);
              return FilterChip(
                label: Text(tag),
                selected: isSelected,
                selectedColor: Colors.orange.shade100,
                checkmarkColor: Colors.orange,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.orange.shade900 : Colors.black87,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                backgroundColor: Colors.grey.shade100,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: isSelected ? Colors.orange : Colors.grey.shade300),
                ),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedRestaurantTags.add(tag);
                    } else {
                      _selectedRestaurantTags.remove(tag);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _restaurantCommentController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Chia sẻ thêm trải nghiệm về chất lượng món ăn...',
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShipperSection() {
    final shipper = widget.order.shipper;
    final shipperName = (shipper != null && shipper.name.isNotEmpty) ? shipper.name : 'Tài xế giao hàng SOOPI';
    final shipperAvatar = (shipper != null && shipper.avatarUrl.isNotEmpty)
        ? shipper.avatarUrl
        : 'https://ui-avatars.com/api/?name=Shipper&background=FF8A00&color=fff';
    final shipperInfoText = (shipper != null && shipper.bikePlate.isNotEmpty)
        ? '${shipper.bikeType} • ${shipper.bikePlate}'
        : 'Đối tác giao nhận đơn #${widget.order.orderCode ?? widget.order.id}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 22, backgroundImage: NetworkImage(shipperAvatar)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Đánh giá Tài xế (Shipper)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(shipperName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(shipperInfoText, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (index) {
                final star = index + 1;
                return IconButton(
                  onPressed: () => setState(() => _shipperRating = star),
                  icon: Icon(
                    star <= _shipperRating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 36,
                  ),
                );
              }),
            ),
          ),
          Center(
            child: Text(
              _ratingLabel(_shipperRating),
              style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Dịch vụ của tài xế như thế nào?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _shipperQuickTags.map((tag) {
              final isSelected = _selectedShipperTags.contains(tag);
              return FilterChip(
                label: Text(tag),
                selected: isSelected,
                selectedColor: Colors.orange.shade100,
                checkmarkColor: Colors.orange,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.orange.shade900 : Colors.black87,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                backgroundColor: Colors.grey.shade100,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: isSelected ? Colors.orange : Colors.grey.shade300),
                ),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedShipperTags.add(tag);
                    } else {
                      _selectedShipperTags.remove(tag);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          const Text('Gửi thêm tiền Tip động viên tài xế:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: _tipOptions.map((tip) {
              final isSelected = _tipAmount == tip;
              final label = tip == 0 ? 'Không tip' : '+${tip ~/ 1000}k';
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: isSelected,
                    selectedColor: Colors.orange,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    backgroundColor: Colors.grey.shade100,
                    onSelected: (selected) => setState(() => _tipAmount = tip),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _shipperCommentController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Nhận xét thêm về thái độ phục vụ của tài xế...',
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
            ),
          ),
        ],
      ),
    );
  }

  String _ratingLabel(int star) {
    switch (star) {
      case 5:
        return 'Tuyệt vời ⭐⭐⭐⭐⭐';
      case 4:
        return 'Hài lòng ⭐⭐⭐⭐';
      case 3:
        return 'Bình thường ⭐⭐⭐';
      case 2:
        return 'Không hài lòng ⭐⭐';
      case 1:
        return 'Rất tệ ⭐';
      default:
        return '';
    }
  }
}
