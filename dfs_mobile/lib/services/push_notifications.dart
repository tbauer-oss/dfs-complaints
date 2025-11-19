// lib/services/push_notifications.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../api/client.dart';

const String _kApiKey = String.fromEnvironment('FIREBASE_API_KEY', defaultValue: '');
const String _kAppId = String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '');
const String _kProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: '');
const String _kSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID', defaultValue: '');
const String _kStorageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET', defaultValue: '');
const String _kIosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID', defaultValue: 'de.dfs_diamon.dfs_complaints');
const String _kMeasurementId = String.fromEnvironment('FIREBASE_MEASUREMENT_ID', defaultValue: '');

FirebaseOptions? _optionsCache;

FirebaseOptions? _firebaseOptions() {
  if (_optionsCache != null) return _optionsCache;
  if (_kApiKey.isEmpty || _kAppId.isEmpty || _kProjectId.isEmpty || _kSenderId.isEmpty) {
    debugPrint('[push] Firebase options incomplete – skipping setup');
    return null;
  }
  _optionsCache = FirebaseOptions(
    apiKey: _kApiKey,
    appId: _kAppId,
    projectId: _kProjectId,
    messagingSenderId: _kSenderId,
    storageBucket: _kStorageBucket.isEmpty ? null : _kStorageBucket,
    iosBundleId: _kIosBundleId.isEmpty ? null : _kIosBundleId,
    measurementId: _kMeasurementId.isEmpty ? null : _kMeasurementId,
  );
  return _optionsCache;
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kIsWeb) return;
  final options = _firebaseOptions();
  if (options == null) return;
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: options);
    }
  } catch (_) {}
}

class PushNotifications {
  PushNotifications._();
  static final PushNotifications instance = PushNotifications._();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  StreamSubscription<String>? _tokenSub;
  bool _initialized = false;
  String? _lastToken;
  String? _lastLang;

  Future<void> setup(ApiClient api, {String? languageCode}) async {
    if (kIsWeb) return;
    final options = _firebaseOptions();
    if (options == null) return;

    await _ensureFirebase(options);

    final messaging = FirebaseMessaging.instance;
    await messaging.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

    await _requestLocalPermissions();

    final settings = await messaging.requestPermission(alert: true, badge: true, sound: true, announcement: true, provisional: false);
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[push] Permission denied');
      return;
    }

    final token = await messaging.getToken();
    if (token != null && token.isNotEmpty) {
      debugPrint('[push] got FCM token from FirebaseMessaging: $token');
      await _registerToken(api, token, languageCode);
    }

    _tokenSub ??= messaging.onTokenRefresh.listen((value) {
      _registerToken(api, value, languageCode);
    });
  }

  Future<void> replayLatestToken(ApiClient api, {String? languageCode}) async {
    if (kIsWeb) return;
    final options = _firebaseOptions();
    if (options == null) return;
    final lang = (languageCode ?? '').trim();
    try {
      await _ensureFirebase(options);
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _registerToken(api, token, languageCode);
      } else {
        final cached = (api.pushDeviceToken ?? '').trim();
        if (cached.isEmpty) return;
        await api.registerPushToken(
          cached,
          platform: _platformLabel(),
          lang: lang.isEmpty ? null : lang,
          locale: lang,
        );
      }
    } catch (e) {
      debugPrint('[push] replayLatestToken failed: $e');
    }
  }

  Future<void> init() async {
    if (kIsWeb) return;
    final options = _firebaseOptions();
    if (options == null) return;

    await _ensureFirebase(options);
  }

  Future<void> deactivate(ApiClient api) async {
    if (kIsWeb) return;
    final options = _firebaseOptions();
    if (options == null) return;

    final messaging = FirebaseMessaging.instance;
    try {
      final current = await messaging.getToken();
      final token = current ?? api.pushDeviceToken;
      if (token != null && token.isNotEmpty) {
        await api.unregisterPushToken(token, silent: true);
      }
    } catch (e) {
      debugPrint('[push] unregister failed: $e');
    }

    try { await messaging.deleteToken(); }
    catch (e) { debugPrint('[push] deleteToken failed: $e'); }

    _lastToken = null;
    _lastLang = null;
    await _tokenSub?.cancel();
    _tokenSub = null;
  }

  Future<void> _ensureFirebase(FirebaseOptions options) async {
    if (!_initialized) {
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(options: options);
        }
      } catch (e) {
        if (Firebase.apps.isEmpty) rethrow;
      }
      await _configureLocalNotifications();
      FirebaseMessaging.onMessage.listen(_showNotification);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      _initialized = true;
    }
  }

  Future<void> _requestLocalPermissions() async {
    try {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final dynamic androidDynamic = androidPlugin;
        try {
          await androidDynamic.requestNotificationsPermission();
        } on NoSuchMethodError {
          try {
            await androidDynamic.requestPermission();
          } on NoSuchMethodError catch (_) {
            debugPrint('[push] Android permission API unavailable');
          }
        }
      }
    } catch (e) {
      debugPrint('[push] Android permission request failed: $e');
    }

    try {
      final iosPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);

      final macPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
      await macPlugin?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('[push] iOS permission request failed: $e');
    }
  }

  Future<void> _configureLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _localNotifications.initialize(settings);

    const channel = AndroidNotificationChannel(
      'complaint-status',
      'Complaint status updates',
      description: 'Updates whenever a complaint status changes.',
      importance: Importance.high,
    );
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(channel);
  }

  Future<void> _registerToken(ApiClient api, String token, String? languageCode) async {
    final lang = (languageCode ?? '').trim();
    final hasAuth = api.hasPushAuth;
    if (hasAuth && token == _lastToken && lang == _lastLang && api.pushDeviceToken == token) return;

    final platform = _platformLabel();

    debugPrint('[push] FCM token: $token (platform=$platform, lang=${lang.isEmpty ? '-': lang})');

    try {
      await api.registerPushToken(
        token,
        platform: platform,
        locale: lang,
        lang: lang.isEmpty ? null : lang,
      );

      api.pushDeviceToken = token;
      
      if (hasAuth) {
        _lastToken = token;
        _lastLang = lang;
      }
    } catch (e) {
      debugPrint('[push] register token failed: $e');
    }
  }

  void _showNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    final androidDetails = AndroidNotificationDetails(
      'complaint-status',
      'Complaint status updates',
      channelDescription: 'Updates whenever a complaint status changes.',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'complaint-status',
    );
    const iosDetails = DarwinNotificationDetails();
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      details,
      payload: message.data.isEmpty ? null : jsonEncode(message.data),
    );
  }

  String _platformLabel() {
    if (kIsWeb) return 'web';
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
      if (defaultTargetPlatform == TargetPlatform.android) return 'android';
    } catch (_) {}
    return 'mobile';
  }
}
