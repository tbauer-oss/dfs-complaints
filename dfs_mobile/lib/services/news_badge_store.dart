// lib/services/news_badge_store.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NewsBadgeStore {
  static const String lastSeenKey = 'customer_last_seen_news_ts';

  Future<DateTime?> loadLastSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(lastSeenKey);
      return raw == null ? null : DateTime.tryParse(raw);
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('[news] load last seen failed: $e');
        debugPrint(stack.toString());
      }
      return null;
    }
  }

  Future<void> saveLastSeen(DateTime timestamp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastSeenKey, timestamp.toIso8601String());
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('[news] save last seen failed: $e');
        debugPrint(stack.toString());
      }
    }
  }
}
