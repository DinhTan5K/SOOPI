import 'package:flutter/material.dart';
import '../services/admin_api_service.dart';

class AdminRestaurantsTab extends StatefulWidget {
  const AdminRestaurantsTab({super.key, required this.api});
  final AdminApiService api;

  @override
  State<AdminRestaurantsTab> createState() => _AdminRestaurantsTabState();
}

class _AdminRestaurantsTabState extends State<AdminRestaurantsTab> {
  final _searchController = TextEditingController();
  String _selectedStatus = 'Tất cả'; // 'Tất cả', 'Pending', 'Approved', 'Rejected', 'Locked'
  bool _loading = true;
  String? _error;
  List<dynamic> _restaurants = [];
  int _page = 1;
  int _total = 0;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      String? status;
      bool? locked;
      if (_selectedStatus == 'Pending') status = 'Pending';
      if (_selectedStatus == 'Approved') status = 'Approved';
      if (_selectedStatus == 'Rejected') status = 'Rejected';
      if (_selectedStatus == 'Locked') locked = true;

      final res = await widget.api.getRestaurants(
        query: _searchController.text.trim(),
        status: status,
        locked: locked,
        page: _page,
        pageSize: _pageSize,
      );

      if (!mounted) return;
      setState(() {
        _restaurants = res['items'] as List<dynamic>? ?? [];
        _total = (res['total'] as num?)?.toInt() ?? _restaurants.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onStatusChanged(String status) {
    if (_selectedStatus == status) return;
    setState(() {
      _selectedStatus = status;
      _page = 1;
    });
    _fetch();
  }

  Future<void> _approve(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Phê duyệt nhà hàng?'),
        content: Text('Bạn có chắc chắn muốn duyệt quán "$name" vào hoạt động?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('Phê duyệt'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await widget.api.approveRestaurant(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã phê duyệt quán "$name" thành công!'), backgroundColor: Colors.green),
      );
      _fetch();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi duyệt: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _reject(String id, String name) async {
    final reasonController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Từ chối duyệt nhà hàng'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nhập lý do từ chối quán "$name":', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                hintText: 'Ví dụ: Thiếu thông tin liên hệ, menu chưa hoàn chỉnh...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Vui lòng nhập lý do từ chối')),
                );
                return;
              }
              Navigator.pop(ctx, reasonController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Từ chối'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;

    try {
      await widget.api.rejectRestaurant(id, result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã từ chối quán "$name".'), backgroundColor: Colors.orange),
      );
      _fetch();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi từ chối: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _toggleLock(String id, String name, bool currentlyLocked) async {
    final willLock = !currentlyLocked;
    final reasonController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(willLock ? 'Khóa nhà hàng' : 'Mở khóa nhà hàng'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              willLock
                  ? 'Quán "$name" sẽ bị ẩn và không thể nhận đơn hàng.'
                  : 'Mở khóa quán "$name" trở lại.',
              style: const TextStyle(fontSize: 13),
            ),
            if (willLock) ...[
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  hintText: 'Nhập lý do khóa (bắt buộc)...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ]
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () {
              if (willLock && reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Vui lòng nhập lý do khóa')),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: willLock ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(willLock ? 'Khóa quán' : 'Mở khóa'),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      await widget.api.lockRestaurant(id, willLock, willLock ? reasonController.text.trim() : null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(willLock ? 'Đã khóa quán "$name"' : 'Đã mở khóa quán "$name"'),
          backgroundColor: willLock ? Colors.red : Colors.green,
        ),
      );
      _fetch();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi thực hiện: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showDetail(String id) async {
    BuildContext? dialogCtx;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogCtx = ctx;
        return const Center(child: CircularProgressIndicator(color: Colors.deepOrange));
      },
    );

    try {
      final detail = await widget.api.getRestaurantDetail(id);
      if (dialogCtx != null && dialogCtx!.mounted) {
        Navigator.pop(dialogCtx!);
      }
      if (!mounted) return;

      final rest = detail['restaurant'] as Map<String, dynamic>? ?? {};
      final owner = detail['owner'] as Map<String, dynamic>? ?? {};
      final categories = rest['categories'] as List<dynamic>? ?? [];
      final history = detail['history'] as List<dynamic>? ?? [];

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      rest['name'] ?? '',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 10),
              _buildBadge(rest['approvalStatus'], rest['isLocked'] == true),
              const SizedBox(height: 16),
              const Text('Thông tin chung', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Text('Địa chỉ: ${rest['address']}, ${rest['city']}'),
              Text('Số điện thoại: ${rest['phone']}'),
              if (rest['description'] != null && (rest['description'] as String).isNotEmpty)
                Text('Mô tả: ${rest['description']}'),
              if (rest['reviewReason'] != null && (rest['reviewReason'] as String).isNotEmpty)
                Text('Lý do kiểm duyệt: ${rest['reviewReason']}', style: const TextStyle(color: Colors.red)),

              const Divider(height: 30),
              const Text('Chủ sở hữu (Owner)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Text('Họ tên: ${owner['fullName'] ?? 'Chưa rõ'}'),
              Text('Email: ${owner['email'] ?? 'Chưa rõ'}'),
              Text('SĐT: ${owner['phone'] ?? 'Chưa rõ'}'),

              const Divider(height: 30),
              Text('Thực đơn (${categories.length} danh mục)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              if (categories.isEmpty)
                const Text('Chưa có danh mục hay món ăn nào.', style: TextStyle(color: Colors.grey))
              else
                ...categories.map((c) {
                  final items = c['items'] as List<dynamic>? ?? [];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${c['name']} (${items.length} món)', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        ...items.map((it) => Text('• ${it['name']} - ${it['price']} đ', style: const TextStyle(fontSize: 12))),
                      ],
                    ),
                  );
                }),

              if (history.isNotEmpty) ...[
                const Divider(height: 30),
                const Text('Lịch sử kiểm duyệt & khóa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                ...history.map((h) => Text('• [${h['action']}] ${h['reason'] ?? ''} (${h['createdAt']})', style: const TextStyle(fontSize: 12))),
              ],

              const SizedBox(height: 24),
              // Action buttons inside detail
              Row(
                children: [
                  if (rest['approvalStatus'] == 'Pending') ...[
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _approve(id, rest['name'] ?? '');
                        },
                        icon: const Icon(Icons.check),
                        label: const Text('Duyệt'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _reject(id, rest['name'] ?? '');
                        },
                        icon: const Icon(Icons.close),
                        label: const Text('Từ chối'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      ),
                    ),
                  ] else ...[
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _toggleLock(id, rest['name'] ?? '', rest['isLocked'] == true);
                        },
                        icon: Icon(rest['isLocked'] == true ? Icons.lock_open : Icons.lock_outline),
                        label: Text(rest['isLocked'] == true ? 'Mở khóa' : 'Khóa quán'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: rest['isLocked'] == true ? Colors.green : Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      );
    } catch (e) {
      if (dialogCtx != null && dialogCtx!.mounted) {
        Navigator.pop(dialogCtx!);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi lấy chi tiết quán: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildBadge(String? status, bool isLocked) {
    if (isLocked) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(20)),
        child: const Text('ĐÃ BỊ KHÓA', style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
      );
    }

    Color color;
    String text;
    switch (status) {
      case 'Approved':
        color = Colors.green;
        text = 'ĐÃ DUYỆT';
        break;
      case 'Rejected':
        color = Colors.red;
        text = 'BỊ TỪ CHỐI';
        break;
      case 'Pending':
      default:
        color = Colors.orange;
        text = 'CHỜ DUYỆT';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Thanh tìm kiếm & Lọc
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          color: Colors.white,
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Tìm kiếm theo tên quán, địa chỉ...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _fetch();
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                ),
                onSubmitted: (_) => _fetch(),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('Tất cả'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Pending', label: 'Chờ duyệt'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Approved', label: 'Đã duyệt'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Rejected', label: 'Từ chối'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Locked', label: 'Đã khóa'),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Danh sách quán ăn
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Colors.deepOrange))
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Lỗi tải danh sách: $_error', style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 8),
                          ElevatedButton(onPressed: _fetch, child: const Text('Thử lại')),
                        ],
                      ),
                    )
                  : _restaurants.isEmpty
                      ? const Center(child: Text('Không tìm thấy nhà hàng nào.', style: TextStyle(color: Colors.grey)))
                      : RefreshIndicator(
                          onRefresh: _fetch,
                          color: Colors.deepOrange,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _restaurants.length,
                            itemBuilder: (ctx, index) {
                              final r = _restaurants[index];
                              final id = r['id'].toString();
                              final name = r['name'] ?? 'Chưa đặt tên';
                              final address = r['address'] ?? '';
                              final phone = r['phone'] ?? '';
                              final status = r['approvalStatus'] ?? 'Pending';
                              final isLocked = r['isLocked'] == true;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 0.5,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => _showDetail(id),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                name,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                              ),
                                            ),
                                            _buildBadge(status, isLocked),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text('Địa chỉ: $address', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                                        Text('SĐT: $phone', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                        const SizedBox(height: 12),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            OutlinedButton(
                                              onPressed: () => _showDetail(id),
                                              style: OutlinedButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                textStyle: const TextStyle(fontSize: 12),
                                              ),
                                              child: const Text('Xem chi tiết'),
                                            ),
                                            const SizedBox(width: 8),
                                            if (status == 'Pending') ...[
                                              ElevatedButton(
                                                onPressed: () => _approve(id, name),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.green,
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                                ),
                                                child: const Text('Duyệt'),
                                              ),
                                              const SizedBox(width: 8),
                                              ElevatedButton(
                                                onPressed: () => _reject(id, name),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.red,
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                  textStyle: const TextStyle(fontSize: 12),
                                                ),
                                                child: const Text('Từ chối'),
                                              ),
                                            ] else ...[
                                              IconButton(
                                                icon: Icon(
                                                  isLocked ? Icons.lock_open : Icons.lock_outline,
                                                  color: isLocked ? Colors.green : Colors.redAccent,
                                                ),
                                                tooltip: isLocked ? 'Mở khóa quán' : 'Khóa quán',
                                                onPressed: () => _toggleLock(id, name, isLocked),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
        ),
        if (_total > _pageSize)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Tổng: $_total quán ăn', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _page > 1
                          ? () {
                              setState(() => _page--);
                              _fetch();
                            }
                          : null,
                    ),
                    Text('Trang $_page / ${((_total - 1) ~/ _pageSize) + 1}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _page < ((_total - 1) ~/ _pageSize) + 1
                          ? () {
                              setState(() => _page++);
                              _fetch();
                            }
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildFilterChip(String value, {String? label}) {
    final isSelected = _selectedStatus == value;
    return ChoiceChip(
      label: Text(label ?? value),
      selected: isSelected,
      onSelected: (_) => _onStatusChanged(value),
      selectedColor: Colors.deepOrange,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}
