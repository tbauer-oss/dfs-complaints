import 'dart:html' as html;

class OnboardingPrefs {
  static String _normalizeUser(String userId) {
    final normalized = userId.trim().toLowerCase();
    return normalized.isEmpty ? 'local' : normalized;
  }

  static String _tourSeenKey(String userId) => 'tourSeen:${_normalizeUser(userId)}';

  static bool isSeen(String userId) {
    try {
      return html.window.localStorage[_tourSeenKey(userId)] == 'true';
    } catch (_) {
      return false;
    }
  }

  static Future<void> markSeen(String userId) async {
    try {
      html.window.localStorage[_tourSeenKey(userId)] = 'true';
    } catch (_) {}
  }

  static Future<void> reset(String userId) async {
    try {
      html.window.localStorage.remove(_tourSeenKey(userId));
    } catch (_) {}
  }
}
