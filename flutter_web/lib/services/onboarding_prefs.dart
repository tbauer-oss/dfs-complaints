import 'dart:convert';
import 'dart:html' as html;

class OnboardingPrefs {
  static const _completedKey = 'admin_onboarding_completed_v1';
  static const _lastSeenVersionKey = 'admin_onboarding_last_seen_version';
  static const _currentVersion = 'v1';

  static String _normalizeUser(String userId) {
    final normalized = userId.trim();
    return normalized.isEmpty ? 'local' : normalized;
  }

  static Map<String, bool> _loadCompletionMap() {
    try {
      final raw = html.window.localStorage[_completedKey];
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value.toString() == 'true'),
        );
      }
    } catch (_) {}
    return {};
  }

  static void _saveCompletionMap(Map<String, bool> map) {
    try {
      html.window.localStorage[_completedKey] = jsonEncode(map);
    } catch (_) {}
  }

  static bool isSeen(String userId) {
    try {
      final lastSeen = html.window.localStorage[_lastSeenVersionKey];
      if (lastSeen != _currentVersion) return false;
      final completed = _loadCompletionMap();
      return completed[_normalizeUser(userId)] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markSeen(String userId) async {
    try {
      final completed = _loadCompletionMap();
      completed[_normalizeUser(userId)] = true;
      _saveCompletionMap(completed);
      html.window.localStorage[_lastSeenVersionKey] = _currentVersion;
    } catch (_) {}
  }

  static Future<void> reset(String userId) async {
    try {
      final completed = _loadCompletionMap();
      completed.remove(_normalizeUser(userId));
      _saveCompletionMap(completed);
      html.window.localStorage.remove(_lastSeenVersionKey);
    } catch (_) {}
  }
}
