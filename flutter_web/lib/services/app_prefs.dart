import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppPrefs extends ChangeNotifier {
  // Keys in localStorage
  static const _kTheme = 'dfs_theme'; // 'system' | 'light' | 'dark'
  static const _kLang  = 'dfs_lang';  // 'de' | 'en' | 'es' | 'fr' | 'it' | ...

  ThemeMode _themeMode = ThemeMode.system;
  Locale? _locale; // null -> System/Default (z. B. Deutsch)

  ThemeMode get themeMode => _themeMode;
  Locale? get locale => _locale;

  Future<void> load() async {
    try {
      final t = (html.window.localStorage[_kTheme] ?? 'system').toLowerCase();
      _themeMode = switch (t) {
        'light' => ThemeMode.light,
        'dark'  => ThemeMode.dark,
        _       => ThemeMode.system,
      };

      final lang = (html.window.localStorage[_kLang] ?? '').trim();
      _locale = lang.isEmpty ? null : Locale(lang);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setTheme(String mode) async {
    try { html.window.localStorage[_kTheme] = mode; } catch (_) {}
    _themeMode = switch (mode) {
      'light' => ThemeMode.light,
      'dark'  => ThemeMode.dark,
      _       => ThemeMode.system,
    };
    notifyListeners(); // << kein Reload!
  }

  Future<void> setLang(String langCode) async {
    try { html.window.localStorage[_kLang] = langCode; } catch (_) {}
    _locale = langCode.trim().isEmpty ? null : Locale(langCode);
    notifyListeners(); // << kein Reload!
  }
}
