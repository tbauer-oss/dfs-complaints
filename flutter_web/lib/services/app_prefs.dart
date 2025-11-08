import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppPrefs extends ChangeNotifier {
  // ------------------------------
  // Keys in localStorage
  // ------------------------------
  static const _kTheme = 'dfs_theme'; // 'system' | 'light' | 'dark'
  static const _kLang  = 'dfs_lang';  // 'de' | 'en' | 'es' | 'fr' | 'it' | ...
  static const _kVer   = 'dfs_version'; // App-Version
  static const _kBuild = 'dfs_build';   // Build-Nummer

  ThemeMode _themeMode = ThemeMode.system;
  Locale? _locale; // null -> System/Default (z. B. Deutsch)
  String _version = '1.0.0';
  String _build   = '001';

  // ------------------------------
  // Getter
  // ------------------------------
  ThemeMode get themeMode => _themeMode;
  Locale? get locale => _locale;
  String get version => _version;
  String get build => _build;

  // ------------------------------
  // Laden (z. B. beim App-Start)
  // ------------------------------
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

      // Version & Build laden
      _version = (html.window.localStorage[_kVer] ?? '1.0.0').trim();
      _build   = (html.window.localStorage[_kBuild] ?? '001').trim();
    } catch (_) {}
    notifyListeners();
  }

  // ------------------------------
  // Theme ändern
  // ------------------------------
  Future<void> setTheme(String mode) async {
    try { html.window.localStorage[_kTheme] = mode; } catch (_) {}
    _themeMode = switch (mode) {
      'light' => ThemeMode.light,
      'dark'  => ThemeMode.dark,
      _       => ThemeMode.system,
    };
    notifyListeners(); // kein Reload nötig
  }

  // ------------------------------
  // Sprache ändern
  // ------------------------------
  Future<void> setLang(String langCode) async {
    try { html.window.localStorage[_kLang] = langCode; } catch (_) {}
    _locale = langCode.trim().isEmpty ? null : Locale(langCode);
    notifyListeners();
  }

  // ------------------------------
  // Version/Build ändern (Admin)
  // ------------------------------
  Future<void> setVersion(String version, String build) async {
    try {
      html.window.localStorage[_kVer] = version;
      html.window.localStorage[_kBuild] = build;
    } catch (_) {}
    _version = version.trim().isEmpty ? '1.0.0' : version.trim();
    _build   = build.trim().isEmpty   ? '001'   : build.trim();
    notifyListeners();
  }
}
