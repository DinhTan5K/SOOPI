import 'package:flutter/material.dart';
import '../services/admin_api_service.dart';

class AdminUsersTab extends StatefulWidget {
  const AdminUsersTab({super.key, required this.api});
  final AdminApiService api;

  @override
  State<AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends State<AdminUsersTab> {
  final _searchController = TextEditingController();
  String _selectedRole = 'Tất cả'; // 'Tất cả', 'Customer', 'Owner', 'Shipper', 'Admin', 'Locked'
  bool _loading = true;
  String? _error;
  List<dynamic> _users = [];
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
      String? role;
      bool? locked;
      if (_selectedRole == 'Customer') role = 'Customer';
      if (_selectedRole == 'Owner') role = 'Owner';
      if (_selectedRole == 'Shipper') role = 'Shipper';
      if (_selectedRole == 'Admin') role = 'Admin';
      if (_selectedRole == 'Locked') locked = true;

      final res = await widget.api.getUsers(
        query: _searchController.text.trim(),
        role: role,
        locked: locked,
        page: _page,
        pageSize: _pageSize,
      );

      if (!mounted) return;
      setState(() {
        _users = res['items'] as List<dynamic>? ?? [];
        _total = (res['total'] as num?)?.toInt() ?? _users.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final errorMsg = e is AdminException ? e.message : e.toString();
      setState(() {
        _error = errorMsg;
        _loading = false;
      });
    }
  }

  void _onRoleChanged(String role) {
    if (_selectedRole == role) return;
    setState(() {
      _selectedRole = role;
      _page = 1;
    });
    _fetch();
  }

  Future<void> _changeRole(String id, String email, String currentRole) async {
    String? selected = currentRole;
    final roles = ['Customer', 'Owner', 'Shipper', 'Admin'];

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Phân quyền tài khoản'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tài khoản: $email', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 16),
              const Text('Chọn vai trò mới:'),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: selected,
                onChanged: (val) {
                  setDialogState(() => selected = val);
                },
                child: Column(
                  children: roles
                      .map(
                        (r) => RadioListTile<String>(
                          title: Text(_roleLabel(r)),
                          value: r,
                          dense: true,
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, selected),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
              child: const Text('Cập nhật'),
            ),
          ],
        ),
      ),
    );

    if (result == null || result == currentRole) return;

    try {
      await widget.api.updateUserRole(id, result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã cập nhật vai trò thành ${_roleLabel(result)}'), backgroundColor: Colors.green),
      );
      _fetch();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi cập nhật: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _toggleLock(String id, String email, bool currentlyLocked) async {
    final willLock = !currentlyLocked;
    final reasonController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(willLock ? 'Khóa tài khoản' : 'Mở khóa tài khoản'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              willLock
                  ? 'Tài khoản $email sẽ không thể đăng nhập hoặc đặt hàng.'
                  : 'Mở khóa cho tài khoản $email hoạt động lại bình thường.',
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
            child: Text(willLock ? 'Khóa ngay' : 'Mở khóa'),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      await widget.api.lockUser(id, willLock, willLock ? reasonController.text.trim() : null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(willLock ? 'Đã khóa tài khoản $email' : 'Đã mở khóa $email'),
          backgroundColor: willLock ? Colors.red : Colors.green,
        ),
      );
      _fetch();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
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
      final detail = await widget.api.getUserDetail(id);
      if (dialogCtx != null && dialogCtx!.mounted) {
        Navigator.pop(dialogCtx!);
      }
      if (!mounted) return;

      final user = detail['user'] as Map<String, dynamic>? ?? {};
      final restaurants = detail['restaurants'] as List<dynamic>? ?? [];
      final history = detail['history'] as List<dynamic>? ?? [];

      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.deepOrange.shade100,
                    backgroundImage: user['avatarUrl'] != null ? NetworkImage(user['avatarUrl']) : null,
                    child: user['avatarUrl'] == null
                        ? Text((user['fullName'] ?? 'U')[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20))
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user['fullName'] ?? 'Chưa đặt tên', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        Text(user['email'] ?? '', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _buildRoleChip(user['role'] ?? 'Customer'),
                  const SizedBox(width: 8),
                  if (user['isLocked'] == true)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(20)),
                      child: const Text('BỊ KHÓA', style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const Divider(height: 30),
              Text('Số điện thoại: ${user['phone'] ?? 'Chưa cập nhật'}'),
              Text('Ngày tham gia: ${user['createdAt'] ?? 'N/A'}'),
              const Divider(height: 30),

              Text('Quán ăn sở hữu (${restaurants.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              if (restaurants.isEmpty)
                const Text('Người dùng này không sở hữu quán ăn nào.', style: TextStyle(color: Colors.grey))
              else
                ...restaurants.map((r) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.storefront, color: Colors.deepOrange),
                  title: Text(r['name'] ?? ''),
                  subtitle: Text('Trạng thái: ${r['approvalStatus']}'),
                )),

              if (history.isNotEmpty) ...[
                const Divider(height: 30),
                const Text('Lịch sử kiểm duyệt / khóa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                ...history.map((h) => Text('• [${h['action']}] ${h['reason'] ?? ''} (${h['createdAt']})', style: const TextStyle(fontSize: 12))),
              ],
            ],
          ),
        ),
      );
    } catch (e) {
      if (dialogCtx != null && dialogCtx!.mounted) {
        Navigator.pop(dialogCtx!);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red));
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'Owner':
        return 'Chủ quán (Owner)';
      case 'Shipper':
        return 'Tài xế (Shipper)';
      case 'Admin':
        return 'Quản trị viên (Admin)';
      case 'Customer':
      default:
        return 'Khách hàng (Customer)';
    }
  }

  Widget _buildRoleChip(String role) {
    Color color;
    switch (role) {
      case 'Admin':
        color = Colors.purple;
        break;
      case 'Owner':
      case 'RestaurantOwner':
        color = Colors.deepOrange;
        break;
      case 'Shipper':
        color = Colors.teal;
        break;
      case 'Customer':
      default:
        color = Colors.blue;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(role, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          color: Colors.white,
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Tìm theo Email, Tên, Số điện thoại...',
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
                    _buildFilterChip('Customer', label: 'Khách hàng'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Owner', label: 'Chủ quán'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Shipper', label: 'Tài xế'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Admin', label: 'Quản trị viên'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Locked', label: 'Bị khóa'),
                  ],
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Colors.deepOrange))
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Lỗi tải người dùng: $_error', style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 8),
                          ElevatedButton(onPressed: _fetch, child: const Text('Thử lại')),
                        ],
                      ),
                    )
                  : _users.isEmpty
                      ? const Center(child: Text('Không tìm thấy tài khoản nào.', style: TextStyle(color: Colors.grey)))
                      : RefreshIndicator(
                          onRefresh: _fetch,
                          color: Colors.deepOrange,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _users.length,
                            itemBuilder: (ctx, index) {
                              final u = _users[index];
                              final id = u['id'].toString();
                              final email = u['email'] ?? '';
                              final fullName = u['fullName'] ?? '';
                              final phone = u['phone'] ?? '';
                              final role = u['role'] ?? 'Customer';
                              final isLocked = u['isLocked'] == true;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 0.5,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => _showDetail(id),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: Colors.grey.shade200,
                                          child: Text(
                                            fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U',
                                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                fullName.isNotEmpty ? fullName : email,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                              ),
                                              Text(email, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                              if (phone.isNotEmpty)
                                                Text('SĐT: $phone', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                              const SizedBox(height: 6),
                                              Row(
                                                children: [
                                                  _buildRoleChip(role),
                                                  if (isLocked) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                                                      child: const Text('BỊ KHÓA', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          children: [
                                            PopupMenuButton<String>(
                                              icon: const Icon(Icons.more_vert),
                                              onSelected: (action) {
                                                if (action == 'detail') _showDetail(id);
                                                if (action == 'role') _changeRole(id, email, role);
                                                if (action == 'lock') _toggleLock(id, email, isLocked);
                                              },
                                              itemBuilder: (ctx) => [
                                                const PopupMenuItem(value: 'detail', child: Text('Xem chi tiết')),
                                                const PopupMenuItem(value: 'role', child: Text('Phân quyền Role')),
                                                PopupMenuItem(
                                                  value: 'lock',
                                                  child: Text(
                                                    isLocked ? 'Mở khóa tài khoản' : 'Khóa tài khoản',
                                                    style: TextStyle(color: isLocked ? Colors.green : Colors.red),
                                                  ),
                                                ),
                                              ],
                                            ),
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
                Text('Tổng: $_total người dùng', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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
    final isSelected = _selectedRole == value;
    return ChoiceChip(
      label: Text(label ?? value),
      selected: isSelected,
      onSelected: (_) => _onRoleChanged(value),
      selectedColor: Colors.deepOrange,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}
