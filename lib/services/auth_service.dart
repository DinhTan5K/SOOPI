import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static bool _googleSignInInitialized = false;

  static const String _webClientId =
      '100961861308-9rkfunlqflen9jnuaatthb437fcl6o39.apps.googleusercontent.com';

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signUpWithEmailPassword(String email, String password) async {
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<UserCredential> signInWithEmailPassword(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Đăng nhập bằng tài khoản Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        return await _auth.signInWithPopup(googleProvider);
      }

      if (!_googleSignInInitialized) {
        await GoogleSignIn.instance.initialize(
          serverClientId: _webClientId,
        );
        _googleSignInInitialized = true;
      }

      final GoogleSignInAccount account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;

      String? accessToken;
      try {
        final authz = await account.authorizationClient.authorizationForScopes(['email', 'profile']);
        accessToken = authz?.accessToken;
      } catch (_) {}

      final AuthCredential credential = GoogleAuthProvider.credential(
        idToken: idToken,
        accessToken: accessToken,
      );

      return await _auth.signInWithCredential(credential);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await _auth.signOut();
  }
}
