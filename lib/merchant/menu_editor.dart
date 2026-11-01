import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'merchant_style.dart';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'merchant_data.dart';
import 'menu_photo.dart';

class MenuEditor extends StatefulWidget {
  const MenuEditor({super.key, this.item, this.categories = foodCategories});
  final List<String> categories;
  final MenuItem? item;
  @override
  State<MenuEditor> createState() => _MenuEditorState();
}

class _MenuEditorState extends State<MenuEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _description;
  late String _category;
  late bool _available;
  String? _imageBase64;
  bool _picking = false;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item?.name ?? '');
    _price = TextEditingController(text: widget.item?.price.toString() ?? '');
    _description = TextEditingController(text: widget.item?.description ?? '');
    _category = widget.item?.category ?? widget.categories.first;
    _available = widget.item?.available ?? true;
    _imageBase64 = widget.item?.imageBase64;
  }

  Future<void> _pickPhoto() async {
    if (_picking) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _picking = true);
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
        requestFullMetadata: false,
      );
      if (photo == null) return;
      if (await photo.length() > 2 * 1024 * 1024) {
        throw const FormatException('Chọn ảnh có dung lượng tối đa 2 MB.');
      }
      final bytes = await photo.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      codec.dispose();
      if (mounted) setState(() => _imageBase64 = base64Encode(bytes));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException
                  ? error.message
                  : error is MissingPluginException
                  ? 'Thư viện ảnh chưa được tích hợp vào bản app này. Hãy dừng app và chạy lại bản build Android mới.'
                  : error is PlatformException
                  ? 'Không thể mở thư viện ảnh (${error.code}). ${error.message ?? 'Vui lòng thử lại.'}'
                  : 'Không thể chọn ảnh. Vui lòng thử ảnh JPG hoặc PNG khác.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      MenuItem(
        id: widget.item?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: _name.text.trim(),
        price: int.parse(_price.text),
        category: _category,
        description: _description.text.trim(),
        available: _available,
        imageBase64: _imageBase64,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MerchantAppearance(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.item == null ? 'Thêm món mới' : 'Sửa món',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Center(child: MenuPhoto(imageBase64: _imageBase64, size: 150)),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _picking ? null : _pickPhoto,
                    icon: _picking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(
                      _picking
                          ? 'Đang tải ảnh...'
                          : _imageBase64 == null
                          ? 'Chọn ảnh món'
                          : 'Đổi ảnh',
                    ),
                  ),
                  if (_imageBase64 != null)
                    TextButton.icon(
                      onPressed: _picking
                          ? null
                          : () => setState(() => _imageBase64 = null),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Xóa ảnh'),
                    ),
                ],
              ),
              const Text(
                'Ảnh món (tùy chọn) • Tối đa 2 MB',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _name,
                maxLength: 80,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Tên món'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Nhập tên món.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(9),
                ],
                decoration: const InputDecoration(
                  labelText: 'Giá bán',
                  suffixText: 'VND',
                  hintText: 'Ví dụ: 65000',
                ),
                validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0
                    ? 'Nhập giá lớn hơn 0 bằng số nguyên VND.'
                    : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Danh mục'),
                items: widget.categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _category = v!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                maxLines: 3,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Mô tả (tùy chọn)',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Còn hàng'),
                subtitle: const Text('Tắt khi món đã hết.'),
                value: _available,
                onChanged: (v) => setState(() => _available = v),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _picking ? null : _submit,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Lưu món'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
