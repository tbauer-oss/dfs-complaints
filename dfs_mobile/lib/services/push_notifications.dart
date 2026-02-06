// lib/services/push_notifications.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/client.dart';
import 'notification_permission_service.dart';

const String _kApiKey = String.fromEnvironment('FIREBASE_API_KEY', defaultValue: '');
const String _kAppId = String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '');
const String _kProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: '');
const String _kSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID', defaultValue: '');
const String _kStorageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET', defaultValue: '');
const String _kIosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID', defaultValue: 'de.dfs_diamon.dfs_complaints');
const String _kMeasurementId = String.fromEnvironment('FIREBASE_MEASUREMENT_ID', defaultValue: '');
const String _kPrefsTokenKey = 'dfs_push_last_token';
const String _kPrefsTokenAtKey = 'dfs_push_last_token_at';
const String _kPrefsUploadStatusKey = 'dfs_push_last_upload_status';
const String _kPrefsUploadStatusCodeKey = 'dfs_push_last_upload_status_code';
const String _kPrefsUploadErrorKey = 'dfs_push_last_upload_error';
const String _kPrefsUploadAtKey = 'dfs_push_last_upload_at';
const String _kPrefsLastMessageIdKey = 'dfs_push_last_message_id';
const String _kPrefsLastMessageAtKey = 'dfs_push_last_message_at';

FirebaseOptions? _optionsCache;
FirebaseOptions? _firebaseOptions() {
  if (_optionsCache != null) return _optionsCache;

  // WEB: braucht explizite Optionen aus --dart-define
  if (kIsWeb) {
    if (_kApiKey.isEmpty || _kAppId.isEmpty || _kProjectId.isEmpty || _kSenderId.isEmpty) {
      debugPrint('[push] Firebase options incomplete (web) – skipping setup');
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

  // MOBILE (Android/iOS): nutzt native Konfiguration (google-services.json, Info.plist)
  return null;
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kIsWeb) return;
  final options = _firebaseOptions();
  try {
    if (Firebase.apps.isEmpty) {
      if (options != null) {
        await Firebase.initializeApp(options: options);
      } else {
        await Firebase.initializeApp();
      }
    }
  } catch (_) {}
  await _recordBackgroundMessage(message);
  if (message.notification != null) return;
  await _showBackgroundNotification(message);
}

class PushMessagingService {
  PushMessagingService._();
  static final PushMessagingService instance = PushMessagingService._();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  StreamSubscription<String>? _tokenSub;
  bool _initialized = false;
  String? _lastToken;
  String? _lastLang;
  String? _appVersion;
  String? _appBuild;

  Future<void> setup(
    ApiClient api, {
    String? languageCode,
    bool forcePermissionPrompt = false,
  }) async {
    if (kIsWeb) return;
    final options = _firebaseOptions();
    await _ensureFirebase(options);
    await _ensureAppInfo();

    final messaging = FirebaseMessaging.instance;
    debugPrint('[push][init] setup start');
    await messaging.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

    final forceFirstLaunch = await NotificationPermissionService.instance.consumeFirstLaunchPromptFlag();
    final notificationSnapshot = await NotificationPermissionService.instance.ensureRequested(
      trigger: 'push_setup',
      force: forcePermissionPrompt || forceFirstLaunch,
    );
    debugPrint('[push][perm] status: ${notificationSnapshot.toLogString()}');
    await _requestLocalPermissions(notificationSnapshot);

    if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: true,
        provisional: false,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[push] iOS permission denied');
        return;
      }
    } else if (notificationSnapshot.isRuntimeRequired && !notificationSnapshot.isGranted) {
      debugPrint('[push][perm] Android notification permission not granted');
    }

    final token = await messaging.getToken();
    if (token != null && token.isNotEmpty) {
      await _recordTokenReceived(token);
      debugPrint('[push][token] got FCM token from FirebaseMessaging: $token');
      await _registerToken(api, token, languageCode);
    }

    await _logLastMessageSnapshot();

    _tokenSub ??= messaging.onTokenRefresh.listen((value) {
      debugPrint('[push][token] token refreshed');
      _recordTokenReceived(value);
      _registerToken(api, value, languageCode);
    });
  }

  Future<void> replayLatestToken(ApiClient api, {String? languageCode}) async {
    if (kIsWeb) return;
    final options = _firebaseOptions();
    final lang = (languageCode ?? '').trim();
    try {
      await _ensureFirebase(options);
      await _ensureAppInfo();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _recordTokenReceived(token);
        await _registerToken(api, token, languageCode);
      } else {
        final cached = (api.pushDeviceToken ?? '').trim();
        if (cached.isEmpty) return;
        await api.registerPushToken(
          cached,
          platform: _platformLabel(),
          lang: lang.isEmpty ? null : lang,
          locale: lang,
          appVersion: _appVersion,
          appBuild: _appBuild,
        );
      }
    } catch (e) {
      debugPrint('[push] replayLatestToken failed: $e');
    }
  }

  Future<void> init() async {
    if (kIsWeb) return;
    final options = _firebaseOptions();
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

  Future<void> _ensureFirebase([FirebaseOptions? options]) async {
    if (!_initialized) {
      debugPrint('[push][init] ensuring Firebase');
      try {
        if (Firebase.apps.isEmpty) {
          if (options != null) {
            await Firebase.initializeApp(options: options);
          } else {
            // Mobile: default Konfiguration aus native Files
            await Firebase.initializeApp();
          }
        }
      } catch (e) {
        if (Firebase.apps.isEmpty) rethrow;
      }

      await _configureLocalNotifications();
      FirebaseMessaging.onMessage.listen((message) {
        _recordMessageReceived(message);
        _showNotification(message);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _recordMessageReceived(message);
        debugPrint('[push][msg] notification opened: ${message.messageId ?? '-'}');
      });
      FirebaseMessaging.instance.getInitialMessage().then((message) {
        if (message != null) {
          _recordMessageReceived(message);
          debugPrint('[push][msg] initial notification: ${message.messageId ?? '-'}');
        }
      });
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      _initialized = true;
      debugPrint('[push][init] Firebase messaging ready');
    }
  }

  Future<void> _requestLocalPermissions(NotificationPermissionSnapshot snapshot) async {
    if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
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
      return;
    }

    if (snapshot.isRuntimeRequired) {
      return;
    }

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
  }

  Future<void> _configureLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidInit, iOS: iosInit);
    final dynamic notifications = _localNotifications;
    try {
      await Function.apply(
        notifications.initialize,
        const [],
        {#initializationSettings: settings},
      );
    } on NoSuchMethodError {
      await Function.apply(notifications.initialize, [settings]);
    }

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

  Future<void> _recordTokenReceived(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsTokenKey, token);
    await prefs.setString(_kPrefsTokenAtKey, DateTime.now().toIso8601String());
  }

  Future<void> _recordUploadResult({
    required bool success,
    required int statusCode,
    String? error,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsUploadStatusKey, success ? 'success' : 'failure');
    await prefs.setInt(_kPrefsUploadStatusCodeKey, statusCode);
    if (error != null && error.trim().isNotEmpty) {
      await prefs.setString(_kPrefsUploadErrorKey, error.trim());
    } else {
      await prefs.remove(_kPrefsUploadErrorKey);
    }
    await prefs.setString(_kPrefsUploadAtKey, DateTime.now().toIso8601String());
  }

  Future<void> _recordMessageReceived(RemoteMessage message) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messageId = message.messageId ?? message.data['messageId']?.toString() ?? '';
      if (messageId.isNotEmpty) {
        await prefs.setString(_kPrefsLastMessageIdKey, messageId);
      }
      await prefs.setString(_kPrefsLastMessageAtKey, DateTime.now().toIso8601String());
      debugPrint('[push][msg] received ${message.messageId ?? '-'}');
    } catch (e) {
      debugPrint('[push][msg] record failed: $e');
    }
  }

  Future<PushDiagnosticsSnapshot> collectDiagnostics() async {
    final permission = await NotificationPermissionService.instance.snapshot();
    final prefs = await SharedPreferences.getInstance();
    final storedToken = prefs.getString(_kPrefsTokenKey);
    final storedTokenAt = prefs.getString(_kPrefsTokenAtKey);
    final uploadStatus = prefs.getString(_kPrefsUploadStatusKey);
    final uploadStatusCode = prefs.getInt(_kPrefsUploadStatusCodeKey);
    final uploadError = prefs.getString(_kPrefsUploadErrorKey);
    final uploadAt = prefs.getString(_kPrefsUploadAtKey);
    final lastMessageId = prefs.getString(_kPrefsLastMessageIdKey);
    final lastMessageAt = prefs.getString(_kPrefsLastMessageAtKey);

    String? currentToken;
    if (!kIsWeb) {
      try {
        await _ensureFirebase(_firebaseOptions());
        currentToken = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        debugPrint('[push][diag] token check failed: $e');
      }
    }

    final channelInfo = await _loadChannelInfo();

    return PushDiagnosticsSnapshot(
      permission: permission,
      androidSdk: permission.sdkInt,
      compileSdk: permission.compileSdk,
      targetSdk: permission.targetSdk,
      currentToken: currentToken,
      storedToken: storedToken,
      storedTokenAt: storedTokenAt,
      lastUploadStatus: uploadStatus,
      lastUploadStatusCode: uploadStatusCode,
      lastUploadError: uploadError,
      lastUploadAt: uploadAt,
      lastMessageId: lastMessageId,
      lastMessageAt: lastMessageAt,
      channelInfo: channelInfo,
    );
  }

  Future<PushChannelInfo?> _loadChannelInfo() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    try {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin == null) return null;
      final dynamic androidDynamic = androidPlugin;
      final dynamic channels = await androidDynamic.getNotificationChannels();
      if (channels is List) {
        for (final channel in channels) {
          if (channel is AndroidNotificationChannel) {
            if (channel.id == 'complaint-status') {
              return PushChannelInfo(
                id: channel.id,
                name: channel.name,
                importance: channel.importance.name,
              );
            }
          } else {
            try {
              if (channel.id == 'complaint-status') {
                return PushChannelInfo(
                  id: channel.id?.toString(),
                  name: channel.name?.toString(),
                  importance: channel.importance?.toString(),
                );
              }
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[push][diag] channel check failed: $e');
    }
    return null;
  }

  Future<void> _registerToken(ApiClient api, String token, String? languageCode) async {
    final lang = (languageCode ?? '').trim();
    final hasAuth = api.hasPushAuth;
    if (hasAuth && token == _lastToken && lang == _lastLang && api.pushDeviceToken == token) return;

    final platform = _platformLabel();

    debugPrint('[push][token] FCM token: $token (platform=$platform, lang=${lang.isEmpty ? '-': lang})');
    if (!hasAuth) {
      debugPrint('[push][token] no auth session yet; caching token for later upload');
    }

    await _registerTokenWithRetry(api, token, platform, lang, hasAuth);
  }

  void _showNotification(RemoteMessage message) {
    final notification = message.notification;
    final dataTitle = message.data['title']?.toString();
    final dataBody = message.data['body']?.toString();
    final title = notification?.title ?? dataTitle;
    final body = notification?.body ?? dataBody;
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      debugPrint('[push][msg] skipped empty notification payload');
      return;
    }
    debugPrint('[push][msg] foreground message ${message.messageId ?? '-'} title=$title');
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
      id: message.hashCode,
      title: title,
      body: body,
      notificationDetails: details,
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

  Future<void> _ensureAppInfo() async {
    if (_appVersion != null || _appBuild != null) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = info.version;
      _appBuild = info.buildNumber;
    } catch (e) {
      debugPrint('[push] package info unavailable: $e');
    }
  }

  Future<void> _logLastMessageSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastMessageId = prefs.getString(_kPrefsLastMessageIdKey) ?? '';
      final lastMessageAt = prefs.getString(_kPrefsLastMessageAtKey) ?? '';
      if (lastMessageId.isEmpty && lastMessageAt.isEmpty) {
        debugPrint('[push][msg] last receipt: none');
        return;
      }
      debugPrint('[push][msg] last receipt id=${lastMessageId.isEmpty ? '-' : lastMessageId} at=${lastMessageAt.isEmpty ? '-' : lastMessageAt}');
    } catch (e) {
      debugPrint('[push][msg] last receipt log failed: $e');
    }
  }

  bool _shouldRetry(ApiError? error) {
    if (error == null) return true;
    if (error.status == 0) return true;
    if (error.status == 408 || error.status == 429) return true;
    if (error.status >= 500 && error.status < 600) return true;
    return false;
  }

  Future<void> _registerTokenWithRetry(
    ApiClient api,
    String token,
    String platform,
    String lang,
    bool hasAuth,
  ) async {
    final delays = <Duration>[
      const Duration(seconds: 1),
      const Duration(seconds: 2),
      const Duration(seconds: 5),
    ];
    ApiError? lastApiError;
    Object? lastError;

    for (var attempt = 0; attempt <= delays.length; attempt += 1) {
      try {
        await _ensureAppInfo();
        await api.registerPushToken(
          token,
          platform: platform,
          locale: lang,
          lang: lang.isEmpty ? null : lang,
          appVersion: _appVersion,
          appBuild: _appBuild,
        );

        api.pushDeviceToken = token;
        await _recordUploadResult(success: true, statusCode: 200);
        debugPrint('[push][upload] token registered (attempt ${attempt + 1})');

        if (hasAuth) {
          _lastToken = token;
          _lastLang = lang;
        }
        return;
      } catch (e) {
        lastError = e;
        lastApiError = e is ApiError ? e : null;
        final statusCode = lastApiError?.status ?? 0;
        debugPrint('[push][upload] register failed (attempt ${attempt + 1}): $e');

        if (!_shouldRetry(lastApiError) || attempt == delays.length) {
          await _recordUploadResult(success: false, statusCode: statusCode, error: e.toString());
          return;
        }

        await Future.delayed(delays[attempt]);
      }
    }

    if (lastError != null) {
      final statusCode = lastApiError?.status ?? 0;
      await _recordUploadResult(success: false, statusCode: statusCode, error: lastError.toString());
    }
  }
}

class PushDiagnosticsSnapshot {
  PushDiagnosticsSnapshot({
    required this.permission,
    required this.androidSdk,
    required this.compileSdk,
    required this.targetSdk,
    required this.currentToken,
    required this.storedToken,
    required this.storedTokenAt,
    required this.lastUploadStatus,
    required this.lastUploadStatusCode,
    required this.lastUploadError,
    required this.lastUploadAt,
    required this.lastMessageId,
    required this.lastMessageAt,
    required this.channelInfo,
  });

  final NotificationPermissionSnapshot permission;
  final int? androidSdk;
  final int? compileSdk;
  final int? targetSdk;
  final String? currentToken;
  final String? storedToken;
  final String? storedTokenAt;
  final String? lastUploadStatus;
  final int? lastUploadStatusCode;
  final String? lastUploadError;
  final String? lastUploadAt;
  final String? lastMessageId;
  final String? lastMessageAt;
  final PushChannelInfo? channelInfo;

  String? maskedToken() {
    final token = currentToken ?? storedToken;
    if (token == null || token.isEmpty) return null;
    if (token.length <= 12) return token;
    return '${token.substring(0, 6)}…${token.substring(token.length - 6)}';
  }
}

class PushChannelInfo {
  PushChannelInfo({
    required this.id,
    required this.name,
    required this.importance,
  });

  final String? id;
  final String? name;
  final String? importance;
}

Future<void> _showBackgroundNotification(RemoteMessage message) async {
  if (kIsWeb) return;
  final dataTitle = message.data['title']?.toString();
  final dataBody = message.data['body']?.toString();
  if ((dataTitle == null || dataTitle.isEmpty) && (dataBody == null || dataBody.isEmpty)) {
    return;
  }
  debugPrint('[push][msg] background data-only ${message.messageId ?? '-'}');

  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  const settings = InitializationSettings(android: androidInit, iOS: iosInit);
  final dynamic notifications = plugin;
  try {
    await Function.apply(
      notifications.initialize,
      const [],
      {#initializationSettings: settings},
    );
  } on NoSuchMethodError {
    await Function.apply(notifications.initialize, [settings]);
  }

  const channel = AndroidNotificationChannel(
    'complaint-status',
    'Complaint status updates',
    description: 'Updates whenever a complaint status changes.',
    importance: Importance.high,
  );
  final androidPlugin =
      plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(channel);

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
  final payload = message.data.isEmpty ? null : jsonEncode(message.data);
  try {
    await Function.apply(
      notifications.show,
      const [],
      {
        #id: message.hashCode,
        #title: dataTitle,
        #body: dataBody,
        #notificationDetails: details,
        #payload: payload,
      },
    );
  } on NoSuchMethodError {
    await notifications.show(
      message.hashCode,
      dataTitle,
      dataBody,
      details,
      payload: payload,
    );
  }
}

Future<void> _recordBackgroundMessage(RemoteMessage message) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final messageId = message.messageId ?? message.data['messageId']?.toString() ?? '';
    if (messageId.isNotEmpty) {
      await prefs.setString(_kPrefsLastMessageIdKey, messageId);
    }
    await prefs.setString(_kPrefsLastMessageAtKey, DateTime.now().toIso8601String());
  } catch (e) {
    debugPrint('[push][msg] background record failed: $e');
  }
}
