import 'package:flutter/foundation.dart' show kIsWeb;
import '../web_compat/html_stub.dart'
    if (dart.library.html) '../web_compat/html_web.dart' as html;

class UiPrefs {
  static final Map<String, bool> _memory = <String, bool>{};

  static bool? getBool(String key) {
    if (kIsWeb) {
      try {
        final raw = html.window.localStorage[key];
        if (raw == null) return null;
        return raw.toLowerCase() == 'true';
      } catch (_) {
        return null;
      }
    }
    return _memory[key];
  }

  static void setBool(String key, bool value) {
    if (kIsWeb) {
      try {
        html.window.localStorage[key] = value.toString();
      } catch (_) {}
      return;
    }
    _memory[key] = value;
  }
}
