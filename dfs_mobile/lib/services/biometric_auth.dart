import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

enum BiometricProfile { customer, rep }

class BiometricAuthService {
  BiometricAuthService._();

  static final BiometricAuthService instance = BiometricAuthService._();

  final _auth = LocalAuthentication();
  final _storage = const FlutterSecureStorage();

  static const _customerEmailKey = 'dfs_bio_customer_email';
  static const _customerPasswordKey = 'dfs_bio_customer_password';
  static const _repEmailKey = 'dfs_bio_rep_email';
  static const _repPasswordKey = 'dfs_bio_rep_password';

  Future<bool> _canUseBiometrics() async {
    if (kIsWeb) return false;
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> isAvailable() async => _canUseBiometrics();

  Future<bool> hasCredentials(BiometricProfile profile) async {
    if (!await _canUseBiometrics()) return false;
    final emailKey = profile == BiometricProfile.customer ? _customerEmailKey : _repEmailKey;
    final pwKey = profile == BiometricProfile.customer ? _customerPasswordKey : _repPasswordKey;
    final email = await _storage.read(key: emailKey);
    final pw = await _storage.read(key: pwKey);
    return (email?.isNotEmpty ?? false) && (pw?.isNotEmpty ?? false);
  }

  Future<void> clear(BiometricProfile profile) async {
    final emailKey = profile == BiometricProfile.customer ? _customerEmailKey : _repEmailKey;
    final pwKey = profile == BiometricProfile.customer ? _customerPasswordKey : _repPasswordKey;
    await _storage.delete(key: emailKey);
    await _storage.delete(key: pwKey);
  }

  Future<bool> saveCredentials(
    BiometricProfile profile,
    String email,
    String password,
  ) async {
    if (!await _canUseBiometrics()) return false;
    final emailKey = profile == BiometricProfile.customer ? _customerEmailKey : _repEmailKey;
    final pwKey = profile == BiometricProfile.customer ? _customerPasswordKey : _repPasswordKey;
    await _storage.write(key: emailKey, value: email.trim());
    await _storage.write(key: pwKey, value: password);
    return true;
  }

  Future<(String email, String password)?> readCredentials(BiometricProfile profile) async {
    if (!await _canUseBiometrics()) return null;
    final emailKey = profile == BiometricProfile.customer ? _customerEmailKey : _repEmailKey;
    final pwKey = profile == BiometricProfile.customer ? _customerPasswordKey : _repPasswordKey;
    final email = await _storage.read(key: emailKey);
    final pw = await _storage.read(key: pwKey);
    if (email == null || email.isEmpty || pw == null || pw.isEmpty) return null;
    return (email, pw);
  }

  Future<bool> authenticate(String localizedReason) async {
    if (!await _canUseBiometrics()) return false;
    try {
      return await _auth.authenticate(
        localizedReason: localizedReason,
        biometricOnly: true,
      );
    } on PlatformException {
      return false;
    }
  }
}
