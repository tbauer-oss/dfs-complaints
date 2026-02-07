import 'package:shared_preferences/shared_preferences.dart';

class PushPrefs {
  static const _kPushEnabled = 'dfs_push_enabled';
  static const _kLastLogin = 'dfs_last_login';

  Future<bool> getPushEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kPushEnabled) ?? false;
  }

  Future<void> setPushEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPushEnabled, value);
  }

  Future<DateTime?> getLastLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastLogin);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> setLastLogin(DateTime value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastLogin, value.toIso8601String());
  }
}
