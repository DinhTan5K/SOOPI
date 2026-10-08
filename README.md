# soopi

## Giao diện chủ quán (UC10–UC11)

Chạy `flutter run`, chọn **Dành cho chủ quán** ở màn hình đầu tiên.
Tài khoản demo: `owner@soopi.vn` / `Soopi123!`.

- **Quán của tôi**: bật/tắt nhận đơn, chỉnh giờ từng ngày, nghỉ cả ngày,
  ca qua đêm, áp dụng giờ thứ Hai cho cả tuần, lưu lịch.
- **Thực đơn**: tìm/lọc món, thêm/sửa/xóa, cập nhật giá VND, đánh dấu hết hàng.
- Android lưu quán và món cục bộ bằng SharedPreferences; nền tảng khác chỉ
  giữ dữ liệu trong phiên. Đăng xuất không xóa thực đơn và không lưu mật khẩu.
- Chưa có API xác thực hoặc đồng bộ backend; tài khoản trên chỉ dùng thử UI.

Kế hoạch: [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md).
Kiểm tra: `flutter analyze`, `flutter test`, `flutter build apk --debug`.

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
