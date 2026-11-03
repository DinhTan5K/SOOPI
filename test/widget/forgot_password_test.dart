import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soopi/widgets/forgot_password_dialog.dart';

void main() {
  testWidgets('ForgotPasswordDialog validates email correctly and renders UI', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ForgotPasswordDialog(initialEmail: 'test@example.com'),
        ),
      ),
    );

    // Kiểm tra các thành phần UI xuất hiện
    expect(find.text('Quên mật khẩu?'), findsOneWidget);
    expect(find.text('Gửi liên kết khôi phục'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);

    // Kiểm tra email được điền sẵn
    expect(find.text('test@example.com'), findsOneWidget);

    // Xóa email và nhấn Gửi để test validation
    await tester.enterText(find.byType(TextFormField), '');
    await tester.tap(find.text('Gửi liên kết khôi phục'));
    await tester.pump();

    expect(find.text('Vui lòng nhập địa chỉ email'), findsOneWidget);

    // Nhập sai định dạng email
    await tester.enterText(find.byType(TextFormField), 'invalid-email');
    await tester.tap(find.text('Gửi liên kết khôi phục'));
    await tester.pump();

    expect(find.text('Địa chỉ email không đúng định dạng'), findsOneWidget);
  });
}
