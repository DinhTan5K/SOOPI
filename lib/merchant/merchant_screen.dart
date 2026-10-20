import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/profile_api_service.dart';

import 'merchant_data.dart';
import 'menu_editor.dart';
import 'merchant_orders.dart';
import 'menu_photo.dart';
import 'restaurant_editor.dart';

class MerchantScreen extends StatefulWidget {
  const MerchantScreen({super.key, this.data});
  final MerchantData? data;
  @override
  State<MerchantScreen> createState() => _MerchantScreenState();
}

class _MerchantScreenState extends State<MerchantScreen> {
  late final _data = widget.data ?? MerchantData(remote: true);
  String? _loadError;
  List<Map<String, dynamic>>? _restaurantChoices;
  final _search = TextEditingController();
  List<OpeningDay> _draft = [];
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  bool _loadFailed = false;
  int _tab = 0;
  String _category = 'Tất cả';
  String _stock = 'Tất cả';
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _restaurantChoices = null;
    });
    try {
      await _data.load();
    } on RestaurantSelectionRequired catch (selection) {
      _restaurantChoices = selection.restaurants;
    } catch (error) {
      _loadFailed = true;
      _loadError = error.toString();
    }
    if (!mounted) return;
    setState(() {
      _draft = _data.hours.map((d) => d.copy()).toList();
      _loading = false;
    });
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _restaurant({bool create = false}) async {
    if (_saving || !await _confirmLeave() || !mounted) return;
    try {
      final initial = create
          ? null
          : Map<String, dynamic>.from(
              await _data.api.request(
                'GET',
                'restaurants/${_data.restaurantId}',
              ),
            );
      if (!mounted) return;
      final input = await editRestaurant(context, initial: initial);
      if (input == null || !mounted) return;
      setState(() => _saving = true);
      final result = await _data.api.request(
        create ? 'POST' : 'PUT',
        create ? 'restaurants' : 'restaurants/${_data.restaurantId}',
        input,
      );
      _data.restaurantId = result['id'];
      _dirty = false;
      await _load();
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _selectRestaurant() async {
    if (_saving || !await _confirmLeave() || !mounted) return;
    try {
      final rows = await _data.listRestaurants();
      if (!mounted) return;
      final id = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Chọn quán'),
          children: [
            for (final row in rows)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, row['id'] as String),
                child: Text('${row['name']} • ${row['approvalStatus']}'),
              ),
          ],
        ),
      );
      if (id == null || !mounted) return;
      _data.restaurantId = id;
      _dirty = false;
      _category = 'Tất cả';
      _stock = 'Tất cả';
      _search.clear();
      await _load();
    } catch (error) {
      if (mounted) _message(error.toString());
    }
  }

  Future<bool> _save({
    bool? accepting,
    List<OpeningDay>? schedule,
    List<MenuItem>? menu,
  }) async {
    if (_saving || _loadFailed) return false;
    setState(() => _saving = true);
    try {
      await _data.save(accepting: accepting, schedule: schedule, menu: menu);
      if (!mounted) return false;
      setState(() {});
      _message('Đã lưu thay đổi.');
      return true;
    } catch (_) {
      if (mounted) _message('Không thể lưu dữ liệu. Vui lòng thử lại.');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Lịch chưa được lưu'),
            content: const Text('Rời màn hình sẽ bỏ các thay đổi giờ mở cửa.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Tiếp tục chỉnh'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Bỏ thay đổi'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _edit([MenuItem? item]) async {
    if (_data.categories.isEmpty) {
      _message('Thêm danh mục trước khi thêm món.');
      return;
    }
    final result = await showModalBottomSheet<MenuItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => MenuEditor(item: item, categories: _data.categories),
    );
    if (result == null || !mounted) return;
    final items = [..._data.items];
    final index = items.indexWhere((m) => m.id == result.id);
    if (index < 0) {
      items.add(result);
    } else {
      items[index] = result;
    }
    await _save(menu: items);
  }

  Future<void> _categoryEditor([String? existing]) async {
    final controller = TextEditingController(text: existing ?? '');
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Thêm danh mục' : 'Sửa danh mục'),
        content: TextField(
          controller: controller,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Tên danh mục'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          if (existing != null)
            TextButton(
              onPressed: () => Navigator.pop(context, 'DELETE'),
              child: const Text('Xóa'),
            ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, existing == null ? 'POST' : 'PUT');
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    final name = controller.text.trim();
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    if (action == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final path = 'restaurants/${_data.restaurantId}/categories';
      await _data.api.request(
        action,
        existing == null ? path : '$path/${_data.categoryIds[existing]}',
        action == 'DELETE'
            ? null
            : {
                'name': name,
                'sortOrder': existing == null
                    ? _data.categories.length
                    : _data.categories.indexOf(existing),
              },
      );
      _category = 'Tất cả';
      await _data.load();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(MenuItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa món?'),
        content: Text('Xóa “${item.name}” khỏi thực đơn?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _save(menu: _data.items.where((m) => m.id != item.id).toList());
    }
  }

  Future<void> _pickTime(int index, bool opening) async {
    final day = _draft[index];
    final minutes = opening ? day.open : day.close;
    final value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (value == null || !mounted) return;
    setState(() {
      if (opening) {
        day.open = value.hour * 60 + value.minute;
      } else {
        day.close = value.hour * 60 + value.minute;
      }
      _dirty = true;
    });
  }

  Future<void> _saveHours() async {
    if (_draft.any((d) => d.enabled && d.open == d.close)) {
      _message('Giờ mở và đóng phải khác nhau. Tắt ngày nếu quán nghỉ.');
      return;
    }
    if (await _save(schedule: _draft.map((d) => d.copy()).toList()) &&
        mounted) {
      setState(() => _dirty = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty && !_saving,
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop || _saving) return;
      if (await _confirmLeave() && mounted) {
        setState(() => _dirty = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    },
    child: Scaffold(
      backgroundColor: const Color(0xFFF8F7F4),
      appBar: AppBar(
        title: const Text('SOOPI • Chủ quán'),
        actions: [
          if (_data.remote) ...[
            IconButton(
              tooltip: 'Chọn quán',
              onPressed: _loading || _saving ? null : _selectRestaurant,
              icon: const Icon(Icons.storefront),
            ),
            IconButton(
              tooltip: 'Đăng ký quán',
              onPressed: _loading || _saving
                  ? null
                  : () => _restaurant(create: true),
              icon: const Icon(Icons.add_business),
            ),
          ],
          IconButton(
            tooltip: 'Đăng xuất',
            onPressed: _saving
                ? null
                : () async {
                    if (await _confirmLeave() && mounted) {
                      if (_data.remote) {
                        try {
                          await FirebaseAuth.instance.signOut();
                          ProfileApiService().clearCache();
                        } catch (error) {
                          if (mounted) _message(error.toString());
                          return;
                        }
                        if (!mounted) return;
                      }
                      setState(() => _dirty = false);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) Navigator.pop(context);
                      });
                    }
                  },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _restaurantChoices != null
          ? _restaurantPicker()
          : _loadFailed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _loadError?.contains('Khách hàng') == true
                          ? Icons.block_rounded
                          : Icons.error_outline,
                      size: 52,
                      color: Colors.red.shade400,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _loadError ?? 'Không thể đọc dữ liệu quán.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    if (_loadError?.contains('Khách hàng') == true)
                      FilledButton.icon(
                        onPressed: () async {
                          final nav = Navigator.of(context);
                          await FirebaseAuth.instance.signOut();
                          ProfileApiService().clearCache();
                          if (mounted) nav.pop();
                        },
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Đăng xuất & Quay lại'),
                      )
                    else ...[
                      FilledButton(onPressed: _load, child: const Text('Thử lại')),
                      if (_data.remote && _data.restaurantId == null)
                        OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _restaurant(create: true),
                          icon: const Icon(Icons.add_business),
                          label: const Text('Đăng ký quán ăn'),
                        ),
                    ],
                  ],
                ),
              ),
            )
          : AbsorbPointer(
              absorbing: _saving,
              child: Column(
                children: [
                  if (_saving) const LinearProgressIndicator(),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: IndexedStack(
                          index: _tab,
                          children: [
                            _shop(),
                            _menu(),
                            MerchantOrders(
                              acceptingOrders: _data.acceptingOrders,
                              restaurantId: _data.restaurantId,
                              api: _data.api,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected:
            _saving || _loading || _loadFailed || _restaurantChoices != null
            ? null
            : (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Quán của tôi',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_menu),
            label: 'Thực đơn',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Đơn hàng',
          ),
        ],
      ),
    ),
  );
  Widget _restaurantPicker() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Chọn quán để quản lý',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('Tài khoản của bạn sở hữu nhiều quán.'),
          const SizedBox(height: 16),
          for (final restaurant in _restaurantChoices!)
            Card(
              child: ListTile(
                leading: const Icon(Icons.storefront),
                title: Text(restaurant['name'] as String),
                subtitle: Text(
                  '${restaurant['address'] ?? ''} • ${restaurant['approvalStatus'] ?? ''}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  _data.restaurantId = restaurant['id'] as String;
                  _tab = 0;
                  _load();
                },
              ),
            ),
        ],
      ),
    ),
  );
  Widget _shop() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Quán của tôi',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      Text(
        '${_data.restaurantName} • ${_data.approvalStatus}',
        style: TextStyle(color: Colors.black54),
      ),
      const SizedBox(height: 20),
      if (_data.remote) ...[
        OutlinedButton(
          onPressed: _restaurant,
          child: const Text('Sửa thông tin quán'),
        ),
        if (_data.approvalStatus == 'Rejected')
          OutlinedButton(
            onPressed: () async {
              setState(() => _saving = true);
              try {
                await _data.api.request(
                  'POST',
                  'restaurants/${_data.restaurantId}/resubmit',
                );
                await _load();
              } catch (error) {
                if (mounted) _message(error.toString());
              } finally {
                if (mounted) setState(() => _saving = false);
              }
            },
            child: const Text('Gửi duyệt lại'),
          ),
      ],
      Card(
        color: _data.acceptingOrders
            ? const Color(0xFFEAF5EC)
            : const Color(0xFFFFEEDC),
        child: SwitchListTile(
          value: _data.acceptingOrders,
          onChanged: (v) => _save(accepting: v),
          secondary: Icon(
            _data.acceptingOrders ? Icons.store : Icons.pause_circle_outline,
          ),
          title: Text(
            _data.acceptingOrders ? 'Đang nhận đơn' : 'Tạm ngưng nhận đơn',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: const Text(
            'Trạng thái thủ công; lịch mở cửa được quản lý riêng.',
          ),
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        'Giờ mở cửa',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      const Text(
        'Chọn giờ cho từng ngày. Giờ đóng sớm hơn giờ mở là ca qua đêm.',
        style: TextStyle(color: Colors.black54),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() {
            _draft = List.generate(7, (_) => _draft.first.copy());
            _dirty = true;
          }),
          icon: const Icon(Icons.copy_all),
          label: const Text('Áp dụng thứ Hai cho cả tuần'),
        ),
      ),
      for (var i = 0; i < 7; i++)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        weekDays[i],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(_draft[i].enabled ? 'Mở cửa' : 'Nghỉ'),
                    Switch(
                      value: _draft[i].enabled,
                      onChanged: (v) => setState(() {
                        _draft[i].enabled = v;
                        _dirty = true;
                      }),
                    ),
                  ],
                ),
                if (_draft[i].enabled)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pickTime(i, true),
                          child: Text('Mở ${clockLabel(_draft[i].open)}'),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.arrow_forward, size: 16),
                      ),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pickTime(i, false),
                          child: Text('Đóng ${clockLabel(_draft[i].close)}'),
                        ),
                      ),
                    ],
                  ),
                if (_draft[i].enabled && _draft[i].close < _draft[i].open)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Đóng vào ngày hôm sau',
                      style: TextStyle(color: Colors.deepOrange),
                    ),
                  ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _dirty ? _saveHours : null,
        icon: const Icon(Icons.save_outlined),
        label: const Text('Lưu giờ mở cửa'),
      ),
      if (_dirty)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Có thay đổi chưa lưu.', textAlign: TextAlign.center),
        ),
      const SizedBox(height: 16),
    ],
  );
  Widget _menu() {
    final query = _search.text.trim().toLowerCase();
    final items = _data.items
        .where(
          (m) =>
              m.name.toLowerCase().contains(query) &&
              (_category == 'Tất cả' || m.category == _category) &&
              (_stock == 'Tất cả' || m.available == (_stock == 'Còn hàng')),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Thực đơn',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Thêm món'),
            ),
          ],
        ),
        Text(
          '${_data.items.length} món • ${_data.items.where((m) => m.available).length} còn hàng',
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Tìm tên món...',
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Xóa tìm kiếm',
                    onPressed: () => setState(() => _search.clear()),
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: ['Tất cả', ..._data.categories]
              .map(
                (c) => ChoiceChip(
                  label: Text(c),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
              )
              .toList(),
        ),
        if (_data.remote)
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => _categoryEditor(),
                icon: const Icon(Icons.add),
                label: const Text('Thêm danh mục'),
              ),
              if (_category != 'Tất cả')
                TextButton(
                  onPressed: () => _categoryEditor(_category),
                  child: const Text('Sửa / xóa danh mục'),
                ),
            ],
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: ['Tất cả', 'Còn hàng', 'Hết hàng']
              .map(
                (s) => ChoiceChip(
                  label: Text(s == 'Tất cả' ? 'Mọi trạng thái' : s),
                  selected: _stock == s,
                  onSelected: (_) => setState(() => _stock = s),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                const Icon(
                  Icons.restaurant_menu,
                  size: 48,
                  color: Colors.black38,
                ),
                const SizedBox(height: 12),
                Text(
                  _data.items.isEmpty
                      ? 'Chưa có món. Thêm món đầu tiên nhé!'
                      : 'Không tìm thấy món phù hợp.',
                ),
              ],
            ),
          ),
        for (final item in items)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.imageBase64 != null)
                        MenuPhoto(imageBase64: item.imageBase64, size: 52)
                      else
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEAD4),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            item.category == 'Đồ uống'
                                ? Icons.local_cafe_outlined
                                : Icons.lunch_dining,
                            color: Colors.deepOrange,
                          ),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              item.category,
                              style: const TextStyle(color: Colors.black54),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              money(item.price),
                              style: const TextStyle(
                                color: Colors.deepOrange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Thao tác món',
                        onSelected: (v) =>
                            v == 'edit' ? _edit(item) : _delete(item),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Sửa món')),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Xóa món'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (item.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        item.description,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.available ? 'Còn hàng' : 'Hết hàng',
                          style: TextStyle(
                            color: item.available
                                ? Colors.green.shade800
                                : Colors.red.shade700,
                          ),
                        ),
                      ),
                      Switch(
                        value: item.available,
                        onChanged: (v) => _save(
                          menu: _data.items
                              .map(
                                (m) =>
                                    m.id == item.id ? m.withAvailability(v) : m,
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
