import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/merchant_api_service.dart';
import 'merchant_style.dart';

class MerchantReviewsScreen extends StatefulWidget {
  const MerchantReviewsScreen({
    super.key,
    required this.restaurantId,
    required this.api,
  });

  final String restaurantId;
  final MerchantApiService api;

  @override
  State<MerchantReviewsScreen> createState() => _MerchantReviewsScreenState();
}

class _MerchantReviewsScreenState extends State<MerchantReviewsScreen> {
  final List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  int _page = 0;
  int _total = 0;
  double _average = 0;
  bool _retryReset = true;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _retryReset = reset;
    });
    final nextPage = reset ? 1 : _page + 1;
    try {
      final result = Map<String, dynamic>.from(
        await widget.api.request(
          'GET',
          'restaurants/${widget.restaurantId}/reviews?page=$nextPage&pageSize=20',
        ) as Map,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _rows.clear();
        _rows.addAll(
          (result['items'] as List).map(
            (row) => Map<String, dynamic>.from(row as Map),
          ),
        );
        _page = nextPage;
        _total = (result['total'] as num).toInt();
        _average = (result['averageRating'] as num).toDouble();
      });
    } catch (error) {
      debugPrint('MerchantReviews.load: $error');
      if (mounted) {
        setState(() => _error = 'Không tải được đánh giá. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => MerchantAppearance(
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Đánh giá của quán'),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: MerchantStyle.gradient),
        ),
        actions: [
          IconButton(
            tooltip: 'Tải lại đánh giá',
            onPressed: _loading ? null : () => _load(reset: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _loading && _rows.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () async {
                      if (!_loading) await _load(reset: true);
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      children: [
                        if (_page > 0)
                          MerchantSectionHeader(
                            title: _total == 0
                                ? 'Chưa có đánh giá'
                                : '${_average.toStringAsFixed(1)} / 5 sao',
                            subtitle: '$_total đánh giá từ khách đã đặt hàng',
                            icon: Icons.star_rounded,
                          ),
                        const SizedBox(height: 20),
                        if (_error != null) ...[
                          Text(_error!, textAlign: TextAlign.center),
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () => _load(reset: _retryReset),
                            child: const Text('Thử lại'),
                          ),
                        ] else if (_rows.isEmpty)
                          const MerchantEmptyState(
                            icon: Icons.rate_review_outlined,
                            message: 'Quán chưa nhận được đánh giá nào.',
                          ),
                        for (final row in _rows) _review(row),
                        if (_loading)
                          const Center(child: CircularProgressIndicator())
                        else if (_rows.length < _total && _error == null)
                          OutlinedButton(
                            onPressed: () => _load(),
                            child: const Text('Xem thêm đánh giá'),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    ),
  );

  Widget _review(Map<String, dynamic> row) {
    final createdAt = DateTime.tryParse(row['createdAt']?.toString() ?? '');
    final name = row['customerName']?.toString().trim() ?? '';
    final comment = row['comment']?.toString().trim() ?? '';
    final code = row['orderCode']?.toString() ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name.isEmpty ? 'Khách hàng' : name,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Row(
              children: List.generate(
                5,
                (index) => Icon(
                  index < (row['restaurantRating'] as num).toInt()
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: Colors.amber.shade700,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(comment.isEmpty ? 'Khách không để lại bình luận.' : comment),
            const SizedBox(height: 12),
            Text(
              [
                if (code.isNotEmpty) 'Đơn #$code',
                if (createdAt != null)
                  DateFormat('dd/MM/yyyy HH:mm').format(createdAt.toLocal()),
              ].join(' • '),
              style: const TextStyle(color: MerchantStyle.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
