import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/admin_api_service.dart';

class AdminVouchersTab extends StatefulWidget {
  const AdminVouchersTab({super.key, required this.api});
  final AdminApiService api;

  @override
  State<AdminVouchersTab> createState() => _AdminVouchersTabState();
}

class _AdminVouchersTabState extends State<AdminVouchersTab> {
  final _currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
  bool _loading = true;
  String? _error;
  List<dynamic> _vouchers = [];
  final Set<String> _updatingIds = {};

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await widget.api.getGlobalVouchers();
      if (!mounted) return;
      setState(() {
        _vouchers = list;
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

  Future<void> _toggleStatus(String id, bool currentStatus) async {
    if (_updatingIds.contains(id)) return;
    setState(() => _updatingIds.add(id));

    try {
      await widget.api.toggleGlobalVoucherStatus(id, !currentStatus);
      await _fetch();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi cập nhật: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _updatingIds.remove(id));
    }
  }

  Future<void> _showCreateDialog() async {
    final codeCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    final minOrderCtrl = TextEditingController(text: '0');
    final maxDiscountCtrl = TextEditingController();
    final usageLimitCtrl = TextEditingController(text: '100');
    String discountType = 'Percent'; // 'Percent' or 'Fixed'

    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Tạo Voucher Toàn Sàn Mới'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Mã Voucher (VD: SOOPI50K)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Loại giảm giá: '),
                    DropdownButton<String>(
                      value: discountType,
                      items: const [
                        DropdownMenuItem(value: 'Percent', child: Text('Phần trăm (%)')),
                        DropdownMenuItem(value: 'Fixed', child: Text('Số tiền cố định (đ)')),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => discountType = val);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: valueCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: discountType == 'Percent' ? 'Mức giảm (%)' : 'Số tiền giảm (đ)',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: minOrderCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Đơn hàng tối thiểu (đ)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (discountType == 'Percent') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: maxDiscountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Giảm tối đa (đ) (tùy chọn)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: usageLimitCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Giới hạn số lượt dùng',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: () {
                if (codeCtrl.text.trim().isEmpty || valueCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Vui lòng điền đầy đủ mã và mức giảm giá')),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
              child: const Text('Tạo ngay'),
            ),
          ],
        ),
      ),
    );

      if (result != true) return;

      try {
        final val = double.tryParse(valueCtrl.text.trim()) ?? 0;
        final minOrder = double.tryParse(minOrderCtrl.text.trim()) ?? 0;
        final maxDisc = maxDiscountCtrl.text.trim().isNotEmpty ? double.tryParse(maxDiscountCtrl.text.trim()) : null;
        final limit = usageLimitCtrl.text.trim().isNotEmpty ? int.tryParse(usageLimitCtrl.text.trim()) : null;

        final data = <String, dynamic>{
          'code': codeCtrl.text.trim().toUpperCase(),
          'discountType': discountType,
          'discountValue': val,
          'minOrderAmount': minOrder,
          'isActive': true,
        };
        if (maxDisc != null) data['maxDiscount'] = maxDisc;
        if (limit != null) data['usageLimit'] = limit;

        await widget.api.createGlobalVoucher(data);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tạo voucher toàn sàn thành công!'), backgroundColor: Colors.green),
        );
        _fetch();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tạo voucher: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      codeCtrl.dispose();
      valueCtrl.dispose();
      minOrderCtrl.dispose();
      maxDiscountCtrl.dispose();
      usageLimitCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        backgroundColor: Colors.deepOrange,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Tạo Voucher Mới', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.deepOrange))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Lỗi: $_error', style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 8),
                      ElevatedButton(onPressed: _fetch, child: const Text('Thử lại')),
                    ],
                  ),
                )
              : _vouchers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.discount_outlined, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text('Chưa có voucher toàn sàn nào', style: TextStyle(color: Colors.grey, fontSize: 16)),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _showCreateDialog,
                            icon: const Icon(Icons.add),
                            label: const Text('Tạo voucher đầu tiên'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetch,
                      color: Colors.deepOrange,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                        itemCount: _vouchers.length,
                        itemBuilder: (ctx, index) {
                          final v = _vouchers[index];
                          final id = v['id'].toString();
                          final code = v['code'] ?? '';
                          final type = v['discountType'] ?? 'Percent';
                          final val = (v['discountValue'] as num?)?.toDouble() ?? 0.0;
                          final minOrder = (v['minOrderAmount'] as num?)?.toDouble() ?? 0.0;
                          final maxDisc = (v['maxDiscount'] as num?)?.toDouble();
                          final used = (v['usedCount'] as num?)?.toInt() ?? 0;
                          final limit = (v['usageLimit'] as num?)?.toInt();
                          final isActive = v['isActive'] == true;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0.5,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isActive ? Colors.orange.shade50 : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.confirmation_number_outlined,
                                      color: isActive ? Colors.deepOrange : Colors.grey,
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(code, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isActive ? Colors.green.shade50 : Colors.red.shade50,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                isActive ? 'ĐANG BẬT' : 'ĐÃ TẮT',
                                                style: TextStyle(
                                                  color: isActive ? Colors.green : Colors.red,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          type == 'Percent'
                                              ? 'Giảm ${val.toInt()}%${maxDisc != null ? ' (Tối đa ${_currencyFormat.format(maxDisc)})' : ''}'
                                              : 'Giảm ${_currencyFormat.format(val)}',
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.deepOrange),
                                        ),
                                        Text(
                                          'Đơn tối thiểu: ${_currencyFormat.format(minOrder)} • Đã dùng: $used/${limit ?? '∞'}',
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: isActive,
                                    activeThumbColor: Colors.deepOrange,
                                    onChanged: (val) => _toggleStatus(id, isActive),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
