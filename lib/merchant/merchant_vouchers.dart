import 'package:flutter/material.dart';

import 'merchant_style.dart';

import 'package:flutter/services.dart';

import '../services/merchant_api_service.dart';
import 'merchant_data.dart';

class MerchantVouchers extends StatefulWidget {
  const MerchantVouchers({
    super.key,
    required this.restaurantId,
    required this.api,
    required this.items,
  });
  final String? restaurantId;
  final MerchantApiService api;
  final List<MenuItem> items;

  @override
  State<MerchantVouchers> createState() => _MerchantVouchersState();
}

class _MerchantVouchersState extends State<MerchantVouchers> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String get _path => 'restaurants/${widget.restaurantId}/vouchers';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.restaurantId == null) {
      setState(() {
        _loading = false;
        _error = 'Vui lòng chọn quán đã đồng bộ để quản lý voucher.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.api.request('GET', _path) as List;
      if (mounted) {
        setState(
          () => _rows = rows
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(Object message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$message')));

  Future<void> _create() async {
    final input = await showMerchantDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _VoucherForm(items: widget.items),
    );
    if (input == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.api.request('POST', _path, input);
      if (mounted) {
        _message('Đã tạo voucher.');
        await _load();
      }
    } catch (e) {
      if (mounted) _message(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggle(Map<String, dynamic> row) async {
    setState(() => _saving = true);
    try {
      await widget.api.request('PATCH', '$_path/${row['id']}/status', {
        'isActive': row['isActive'] != true,
      });
      if (mounted) await _load();
    } catch (e) {
      if (mounted) _message(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _scope(Map<String, dynamic> row) {
    if (row['menuItemId'] == null) return 'Toàn quán';
    for (final item in widget.items) {
      if (item.id == row['menuItemId']) return 'Món: ${item.name}';
    }
    return 'Món đã ngừng bán';
  }

  String _date(dynamic value) => value == null
      ? 'Không giới hạn'
      : DateTime.parse(value as String).toLocal().toString().substring(0, 16);
  String _amount(dynamic value) => money((value as num).round());

  Future<void> _detail(Map<String, dynamic> row) async {
    try {
      final result = Map<String, dynamic>.from(
        await widget.api.request('GET', '$_path/${row['id']}') as Map,
      );
      if (!mounted) return;
      await showMerchantDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(result['code'] as String),
          content: SingleChildScrollView(
            child: Text(
              [
                _scope(result),
                result['discountType'] == 'Percent'
                    ? 'Giảm ${result['discountValue']}%'
                    : 'Giảm ${_amount(result['discountValue'])}',
                'Đơn tối thiểu: ${_amount(result['minOrderAmount'])}',
                'Giảm tối đa: ${result['maxDiscount'] == null ? 'Không giới hạn' : _amount(result['maxDiscount'])}',
                'Bắt đầu: ${_date(result['startsAt'])}',
                'Kết thúc: ${_date(result['endsAt'])}',
                'Đã dùng: ${result['usedCount']}/${result['usageLimit'] ?? 'Không giới hạn'}',
                'Trạng thái: ${_status(result)}',
              ].join('\n\n'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) _message(e);
    }
  }

  String _status(Map<String, dynamic> row) => switch (row['status']) {
    'Inactive' => 'Đã tắt',
    'Expired' => 'Hết hạn',
    'Exhausted' => 'Hết lượt',
    'Scheduled' => 'Chưa bắt đầu',
    _ => 'Đang hoạt động',
  };

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MerchantSectionHeader(
              title: 'Ưu đãi của quán',
              subtitle: 'Tạo ưu đãi hấp dẫn để khách quay lại nhiều hơn.',
              icon: Icons.local_offer_rounded,
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                const Text(
                  'Voucher của quán',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      onPressed: _loading || _saving ? null : _load,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Tải lại',
                    ),
                    FilledButton.icon(
                      onPressed:
                          _loading || _saving || widget.restaurantId == null
                          ? null
                          : _create,
                      icon: const Icon(Icons.add),
                      label: const Text('Tạo voucher'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      if (_saving) const LinearProgressIndicator(),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
              )
            : _rows.isEmpty
            ? const MerchantEmptyState(
                icon: Icons.local_offer_outlined,
                message: 'Chưa có voucher. Tạo voucher đầu tiên cho quán.',
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _rows.length,
                  itemBuilder: (context, index) {
                    final row = _rows[index];
                    return Card(
                      child: ListTile(
                        onTap: _saving ? null : () => _detail(row),
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFFFF0E0),
                          child: Icon(
                            Icons.local_offer_outlined,
                            color: MerchantStyle.primary,
                          ),
                        ),
                        title: Text(row['code'] as String),
                        subtitle: Text(
                          '${_scope(row)}\n${_status(row)} • Đã dùng ${row['usedCount']}/${row['usageLimit'] ?? '∞'}',
                        ),
                        isThreeLine: true,
                        trailing: Switch(
                          value: row['isActive'] == true,
                          onChanged: _saving ? null : (_) => _toggle(row),
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    ],
  );
}

class _VoucherForm extends StatefulWidget {
  const _VoucherForm({required this.items});
  final List<MenuItem> items;
  @override
  State<_VoucherForm> createState() => _VoucherFormState();
}

class _VoucherFormState extends State<_VoucherForm> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _value = TextEditingController();
  final _minimum = TextEditingController(text: '0');
  final _maximum = TextEditingController();
  final _limit = TextEditingController();
  String _type = 'Percent';
  String? _itemId;
  bool _itemScope = false;
  bool _active = true;
  DateTime? _start;
  DateTime? _end;
  String? _dateError;

  @override
  void dispose() {
    for (final controller in [_code, _value, _minimum, _maximum, _limit]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: (start ? _start : _end) ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime((start ? _start : _end) ?? now),
    );
    if (time == null || !mounted) return;
    setState(() {
      final value = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (start) {
        _start = value;
      } else {
        _end = value;
      }
      _dateError = null;
    });
  }

  Widget _number(
    String label,
    TextEditingController controller, {
    bool optional = false,
    bool zero = false,
    bool integer = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(integer ? r'[0-9]' : r'[0-9.]'),
        ),
      ],
      validator: (text) {
        if (optional && (text ?? '').isEmpty) return null;
        final value = num.tryParse(text ?? '');
        if (value == null ||
            !value.isFinite ||
            (zero ? value < 0 : value <= 0) ||
            value > (integer ? 2147483647 : 9999999999.99) ||
            (integer && value != value.roundToDouble())) {
          return 'Nhập giá trị hợp lệ';
        }
        if (controller == _value && _type == 'Percent' && value > 100) {
          return 'Phần trăm không vượt quá 100';
        }
        if (!integer && !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text!)) {
          return 'Tối đa 2 chữ số thập phân';
        }
        return null;
      },
    ),
  );

  void _submit() {
    if (!_form.currentState!.validate()) return;
    if (_start != null && _end != null && !_end!.isAfter(_start!)) {
      setState(() => _dateError = 'Thời gian kết thúc phải sau bắt đầu.');
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'code': _code.text.trim().toUpperCase(),
      'menuItemId': _itemScope ? _itemId : null,
      'discountType': _type,
      'discountValue': num.parse(_value.text),
      'minOrderAmount': num.parse(_minimum.text),
      'maxDiscount': _maximum.text.isEmpty ? null : num.parse(_maximum.text),
      'usageLimit': _limit.text.isEmpty ? null : int.parse(_limit.text),
      'startsAt': _start?.toUtc().toIso8601String(),
      'endsAt': _end?.toUtc().toIso8601String(),
      'isActive': _active,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Tạo voucher'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _code,
                decoration: const InputDecoration(labelText: 'Mã voucher'),
                textCapitalization: TextCapitalization.characters,
                validator: (s) =>
                    RegExp(r'^[A-Za-z0-9_-]{1,50}$').hasMatch((s ?? '').trim())
                    ? null
                    : 'Nhập 1–50 chữ, số, dấu _ hoặc -',
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Áp dụng cho một món'),
                value: _itemScope,
                onChanged: (v) => setState(() => _itemScope = v),
              ),
              if (_itemScope)
                DropdownButtonFormField<String>(
                  initialValue: _itemId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Chọn món'),
                  items: widget.items
                      .map(
                        (m) =>
                            DropdownMenuItem(value: m.id, child: Text(m.name)),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _itemId = v),
                  validator: (v) => v == null ? 'Vui lòng chọn món' : null,
                ),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Loại giảm'),
                items: const [
                  DropdownMenuItem(
                    value: 'Percent',
                    child: Text('Phần trăm (%)'),
                  ),
                  DropdownMenuItem(value: 'Fixed', child: Text('Số tiền (đ)')),
                ],
                onChanged: (v) => setState(() => _type = v!),
              ),
              const SizedBox(height: 16),
              _number(
                _type == 'Percent' ? 'Giá trị giảm (%)' : 'Số tiền giảm (đ)',
                _value,
              ),
              _number('Đơn tối thiểu (đ)', _minimum, zero: true),
              _number(
                'Giảm tối đa (đ, không bắt buộc)',
                _maximum,
                optional: true,
              ),
              _number(
                'Giới hạn lượt dùng (không bắt buộc)',
                _limit,
                optional: true,
                integer: true,
              ),
              const Text(
                'Thời gian theo giờ thiết bị; bỏ trống để không giới hạn.',
              ),
              for (final start in [true, false])
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => _pick(start),
                        child: Text(
                          '${start ? 'Bắt đầu' : 'Kết thúc'}: ${(start ? _start : _end)?.toString().substring(0, 16) ?? 'Chưa chọn'}',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Xóa thời gian',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() {
                        if (start) {
                          _start = null;
                        } else {
                          _end = null;
                        }
                      }),
                    ),
                  ],
                ),
              if (_dateError != null)
                Text(
                  _dateError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Kích hoạt voucher'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Tạo voucher')),
    ],
  );
}
