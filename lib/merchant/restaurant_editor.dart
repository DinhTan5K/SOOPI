import 'package:flutter/material.dart';

Future<Map<String, dynamic>?> editRestaurant(
  BuildContext context, {
  Map<String, dynamic>? initial,
}) async {
  final form = GlobalKey<FormState>();
  final fields = {
    'name': 'Tên quán',
    'phone': 'Số điện thoại',
    'address': 'Địa chỉ',
    'city': 'Thành phố',
    'description': 'Mô tả',
  };
  final controllers = {
    for (final key in fields.keys)
      key: TextEditingController(text: initial?[key] as String? ?? ''),
  };
  try {
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(initial == null ? 'Đăng ký quán ăn' : 'Thông tin quán'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final field in fields.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: controllers[field.key],
                        maxLength: field.key == 'name'
                            ? 150
                            : field.key == 'phone'
                            ? 20
                            : field.key == 'city'
                            ? 100
                            : field.key == 'description'
                            ? 1000
                            : 500,
                        decoration: InputDecoration(labelText: field.value),
                        validator: (value) =>
                            field.key != 'description' &&
                                (value == null || value.trim().isEmpty)
                            ? 'Vui lòng nhập ${field.value.toLowerCase()}.'
                            : null,
                      ),
                    ),
                  const Text(
                    'Quán cần được duyệt trước khi nhận đơn. Thay đổi thông tin quán đã duyệt sẽ gửi duyệt lại.',
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
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, <String, dynamic>{
                  ...?initial,
                  for (final field in controllers.entries)
                    field.key: field.value.text.trim(),
                });
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  } finally {
    // Dialog route may still animate while its fields are mounted.
    Future<void>.delayed(const Duration(seconds: 1), () {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    });
  }
}
