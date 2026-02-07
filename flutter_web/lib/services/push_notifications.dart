// lib/services/push_notifications.dart
import 'package:flutter/foundation.dart';
import '../api/client.dart';

class PushMessagingService {
  PushMessagingService._();
  static final PushMessagingService instance = PushMessagingService._();

  Future<void> setup(
    ApiClient api, {
    String? languageCode,
    bool forcePermissionPrompt = false,
  }) async {
    if (kDebugMode) {
      debugPrint('[push][web] setup noop');
    }
  }

  Future<void> replayLatestToken(
    ApiClient api, {
    String? languageCode,
  }) async {
    if (kDebugMode) {
      debugPrint('[push][web] replayLatestToken noop');
    }
  }

  Future<void> deactivate(ApiClient api) async {
    if (kDebugMode) {
      debugPrint('[push][web] deactivate noop');
    }
  }
}

class PushNotifications {
  PushNotifications._();
  static final PushMessagingService instance = PushMessagingService.instance;
}
