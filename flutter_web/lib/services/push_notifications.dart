// lib/services/push_notifications.dart (web stub)
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../api/client.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(dynamic message) async {
  debugPrint('[push:web] background handler invoked (ignored).');
}

class PushNotifications {
  PushNotifications._();
  static final PushNotifications instance = PushNotifications._();

  Future<void> setup(ApiClient api, {String? languageCode}) async {
    debugPrint('[push:web] setup skipped.');
  }

  Future<void> deactivate(ApiClient api) async {
    debugPrint('[push:web] deactivate skipped.');
  }
}
