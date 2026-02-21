import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

class PersistentSnapshotCache {
  static const _prefix = 'dfs:snapshot:';

  static Map<String, dynamic>? readJson(String key) {
    final sw = Stopwatch()..start();
    try {
      final raw = html.window.localStorage['$_prefix$key'];
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, dynamic>();
      return null;
    } catch (_) {
      return null;
    } finally {
      _debugLog('cache-read', key, sw.elapsedMilliseconds);
    }
  }

  static void writeJson(String key, Map<String, dynamic> payload) {
    final sw = Stopwatch()..start();
    try {
      html.window.localStorage['$_prefix$key'] = jsonEncode(payload);
    } catch (_) {
      // Ignore quota errors silently for web.
    } finally {
      _debugLog('cache-write', key, sw.elapsedMilliseconds);
    }
  }

  static String? readString(String key) => html.window.localStorage['$_prefix$key'];
  static void writeString(String key, String value) => html.window.localStorage['$_prefix$key'] = value;

  static void _debugLog(String phase, String key, int ms) {
    if (!kDebugMode) return;
    debugPrint('[snapshot-cache] $phase $key ${ms}ms');
  }
}
