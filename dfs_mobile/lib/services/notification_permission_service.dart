import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationPermissionSnapshot {
  NotificationPermissionSnapshot({
    required this.isAndroid,
    required this.sdkInt,
    required this.compileSdk,
    required this.targetSdk,
    required this.status,
    required this.attempted,
    required this.requestCount,
    required this.lastRequestedAt,
  });

  final bool isAndroid;
  final int? sdkInt;
  final int? compileSdk;
  final int? targetSdk;
  final PermissionStatus status;
  final bool attempted;
  final int requestCount;
  final String? lastRequestedAt;

  bool get isRuntimeRequired {
    if (!isAndroid) return false;
    final runtime = sdkInt ?? targetSdk ?? compileSdk ?? 0;
    return runtime >= 33;
  }
  bool get isGranted => status == PermissionStatus.granted;
  bool get isPermanentlyDenied => status.isPermanentlyDenied;

  String toLogString() {
    return 'sdk=${sdkInt ?? '-'} targetSdk=${targetSdk ?? '-'} '
        'compileSdk=${compileSdk ?? '-'} status=${status.name} attempted=$attempted '
        'requests=$requestCount lastAt=${lastRequestedAt ?? '-'}';
  }
}

class NotificationPermissionService {
  NotificationPermissionService._();
  static final NotificationPermissionService instance = NotificationPermissionService._();

  static const MethodChannel _channel = MethodChannel('dfs/notification_permissions');
  static const String _kAttemptedKey = 'dfs_notifications_attempted';
  static const String _kRequestCountKey = 'dfs_notifications_request_count';
  static const String _kLastStatusKey = 'dfs_notifications_last_status';
  static const String _kLastRequestAtKey = 'dfs_notifications_last_request_at';

  Future<NotificationPermissionSnapshot> ensureRequested({
    bool force = false,
    String trigger = 'startup',
  }) async {
    final before = await snapshot();
    debugPrint('[push] notification permission snapshot ($trigger): ${before.toLogString()}');

    if (!before.isAndroid || !before.isRuntimeRequired) {
      return before;
    }

    if (before.isGranted) {
      return before;
    }

    if (!force && before.attempted) {
      debugPrint('[push] notification permission already requested; skipping prompt');
      return before;
    }

    await _recordAttempt(status: before.status, increment: true);
    final status = await Permission.notification.request();
    await _recordAttempt(status: status, increment: false);

    final after = await snapshot();
    debugPrint('[push] notification permission result ($trigger): ${after.toLogString()}');
    return after;
  }

  Future<void> resetPromptState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAttemptedKey);
    await prefs.remove(_kRequestCountKey);
    await prefs.remove(_kLastStatusKey);
    await prefs.remove(_kLastRequestAtKey);
    debugPrint('[push] notification permission prompt state reset');
  }

  Future<void> openSettingsIfNeeded(NotificationPermissionSnapshot snapshot) async {
    if (snapshot.isPermanentlyDenied) {
      await openAppSettings();
    }
  }

  Future<NotificationPermissionSnapshot> snapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final attempted = prefs.getBool(_kAttemptedKey) ?? false;
    final requestCount = prefs.getInt(_kRequestCountKey) ?? 0;
    final lastRequestedAt = prefs.getString(_kLastRequestAtKey);
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    PermissionStatus status = PermissionStatus.denied;

    if (!kIsWeb) {
      try {
        status = await Permission.notification.status;
      } catch (e) {
        debugPrint('[push] notification status check failed: $e');
      }
    }

    final info = await _loadAndroidInfo();
    return NotificationPermissionSnapshot(
      isAndroid: isAndroid,
      sdkInt: info.sdkInt,
      compileSdk: info.compileSdk,
      targetSdk: info.targetSdk,
      status: status,
      attempted: attempted,
      requestCount: requestCount,
      lastRequestedAt: lastRequestedAt,
    );
  }

  Future<void> _recordAttempt({required PermissionStatus status, required bool increment}) async {
    final prefs = await SharedPreferences.getInstance();
    if (increment) {
      await prefs.setBool(_kAttemptedKey, true);
      final current = prefs.getInt(_kRequestCountKey) ?? 0;
      await prefs.setInt(_kRequestCountKey, current + 1);
    }
    await prefs.setString(_kLastStatusKey, status.name);
    await prefs.setString(_kLastRequestAtKey, DateTime.now().toIso8601String());
  }

  Future<_AndroidInfo> _loadAndroidInfo() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const _AndroidInfo();
    }
    try {
      final result = await _channel.invokeMethod<Map>('getAndroidSdkInfo');
      if (result == null) return const _AndroidInfo();
      return _AndroidInfo(
        sdkInt: result['sdkInt'] as int?,
        compileSdk: result['compileSdk'] as int?,
        targetSdk: result['targetSdk'] as int?,
      );
    } catch (e) {
      debugPrint('[push] android sdk info unavailable: $e');
      return const _AndroidInfo();
    }
  }
}

class _AndroidInfo {
  const _AndroidInfo({this.sdkInt, this.compileSdk, this.targetSdk});
  final int? sdkInt;
  final int? compileSdk;
  final int? targetSdk;
}
