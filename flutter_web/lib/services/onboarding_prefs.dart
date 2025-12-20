import 'dart:html' as html;

class OnboardingPrefs {
  static const _prefix = 'dfs_admin_onboarding_seen';

  static String _keyForUser(String userId) {
    final normalized = userId.trim().isEmpty ? 'local' : userId.trim();
    return '${_prefix}_$normalized';
  }

  static bool isSeen(String userId) {
    try {
      return html.window.localStorage[_keyForUser(userId)] == 'true';
    } catch (_) {
      return false;
    }
  }

  static Future<void> markSeen(String userId) async {
    try {
      html.window.localStorage[_keyForUser(userId)] = 'true';
    } catch (_) {}
  }

  static Future<void> reset(String userId) async {
    try {
      html.window.localStorage.remove(_keyForUser(userId));
    } catch (_) {}
  }
}
