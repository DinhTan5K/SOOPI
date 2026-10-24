import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'auth_screen.dart';
import 'home.dart';
import 'merchant/merchant_screen.dart';
import 'shipper/shipper_main_screen.dart';
import 'services/api_config.dart';
import 'services/profile_api_service.dart';

void main() async {
  // Bắt buộc phải có khi khởi tạo Firebase
  WidgetsFlutterBinding.ensureInitialized();

  // Khởi tạo Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Khởi tạo và tự động kết nối Backend API theo IP thiết bị
  await ApiConfig().init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SOOPI FOOD',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      routes: {
        '/login': (context) => const AuthScreen(),
        '/home': (context) => const HomeScreen(),
        '/merchant': (context) => const MerchantScreen(),
        '/shipper': (context) => const ShipperMainScreen(),
      },
      home: const AuthGate(),
    );
  }
}

/// Tự động giữ phiên đăng nhập khi F5 (Refresh) trên Web hoặc mở lại App
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Colors.deepOrange),
            ),
          );
        }

        // Nếu đã có phiên đăng nhập Firebase (kể cả khi F5 Refresh trình duyệt)
        if (snapshot.hasData && snapshot.data != null) {
          return RoleBasedHome(key: ValueKey(snapshot.data!.uid));
        }

        // Chỉ khi chưa đăng nhập hoặc đã bấm Đăng xuất mới hiện trang Login
        return const AuthScreen();
      },
    );
  }
}

/// Điều hướng đúng giao diện theo Role (Owner -> MerchantScreen, Shipper -> ShipperMainScreen, Customer -> HomeScreen)
class RoleBasedHome extends StatefulWidget {
  const RoleBasedHome({super.key});

  @override
  State<RoleBasedHome> createState() => _RoleBasedHomeState();
}

class _RoleBasedHomeState extends State<RoleBasedHome> {
  String? _role;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final cached = await ProfileApiService().getCachedUserRole();
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() {
        _role = cached;
        _loading = false;
      });
    }
    final resolved = await ProfileApiService().resolveUserRole();
    if (mounted) {
      setState(() {
        _role = resolved;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Colors.deepOrange),
        ),
      );
    }

    final r = (_role ?? 'Customer').trim().toLowerCase();
    if (r == 'owner' || r == 'restaurantowner') {
      return const MerchantScreen();
    }
    if (r == 'shipper') {
      return const ShipperMainScreen();
    }
    return const HomeScreen();
  }
}
