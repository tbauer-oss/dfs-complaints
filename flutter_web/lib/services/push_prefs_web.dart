import '../web_compat/html_stub.dart'
  if (dart.library.html) '../web_compat/html_web.dart' as html;

class PushPrefs {
  static const _kPushEnabled = 'dfs_push_enabled';
  static const _kLastLogin = 'dfs_last_login';

  Future<bool> getPushEnabled() async {
    final raw = html.window.localStorage[_kPushEnabled];
    return raw?.toLowerCase() == 'true';
  }

  Future<void> setPushEnabled(bool value) async {
    html.window.localStorage[_kPushEnabled] = value.toString();
  }

  Future<DateTime?> getLastLogin() async {
    final raw = html.window.localStorage[_kLastLogin];
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> setLastLogin(DateTime value) async {
    html.window.localStorage[_kLastLogin] = value.toIso8601String();
  }
}
