// lib/main.dart
import 'dart:html' as html; // für Sprache + Theme persistieren
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api/client.dart';
import 'l10n/app_localizations.dart';
import 'pages/login_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/register_page.dart';
import 'pages/admin_page.dart';
import 'widgets/lang_action.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final api = ApiClient();

  Locale? _locale;
  bool _bootDone = false;
  bool _loggedIn = false;

  // ---- NEU: globaler ThemeMode (system | light | dark)
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();

    // gespeicherte Sprache laden
    final savedLang = html.window.localStorage['dfs_lang'];
    if (savedLang != null && savedLang.isNotEmpty) {
      _locale = Locale(savedLang);
    }

    // gespeicherten ThemeMode laden
    final savedTheme = (html.window.localStorage['dfs_theme'] ?? 'system').toLowerCase();
    switch (savedTheme) {
      case 'light':
        _themeMode = ThemeMode.light;
        break;
      case 'dark':
        _themeMode = ThemeMode.dark;
        break;
      default:
        _themeMode = ThemeMode.system;
    }

    _boot();
  }

  Future<void> _boot() async {
    await api.restoreSession();
    setState(() {
      _loggedIn = (api.token != null && api.token!.isNotEmpty);
      _bootDone = true;
    });
  }

  void _setLocale(Locale l) {
    setState(() => _locale = l);
    html.window.localStorage['dfs_lang'] = l.languageCode;
  }

  // ---- NEU: ThemeMode setzen + persistieren
  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    final v = switch (mode) { ThemeMode.light => 'light', ThemeMode.dark => 'dark', _ => 'system' };
    html.window.localStorage['dfs_theme'] = v;
  }

  // Kleines Icon je aktuellem Modus
  IconData _themeIconFor(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
      case ThemeMode.system:
      default:
        return Icons.brightness_auto;
    }
  }

  // --- Admin-Secret Dialog + Navigation ---
  Future<void> _openAdmin(BuildContext context) async {
    final t = AppLocalizations.of(context)!;
    final ctrl = TextEditingController(text: api.adminSecret ?? '');
    final wantOpen = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t.admin_area),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'X-Admin-Secret',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.open)),
        ],
      ),
    );

    if (wantOpen != true) return;

    final secret = ctrl.text.trim();
    if (secret.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.required_fields)));
      return;
    }

    final ok = await api.validateAdminSecret(secret);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.errorGeneric('Admin-Secret'))));
      return;
    }

    api.setAdminSecret(secret);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminPage(api: api)));
  }

  void _openRegister(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => RegisterPage(api: api)));
  }

  void _onLoggedIn() => setState(() => _loggedIn = true);
  void _onLoggedOut() => setState(() => _loggedIn = false);

  @override
  Widget build(BuildContext context) {
    if (!_bootDone) {
      return const MaterialApp(home: Scaffold(body: Center(child: CircularProgressIndicator())));
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,

      // ---- Global: Locale + L10n
      locale: _locale,
      supportedLocales: const [
        Locale('de'), Locale('en'), Locale('fr'), Locale('it'), Locale('es'),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeListResolutionCallback: (locales, supported) {
        if (_locale != null) return _locale!;
        if (locales != null) {
          for (final loc in locales) {
            for (final s in supported) {
              if (s.languageCode.toLowerCase() == loc.languageCode.toLowerCase()) {
                return s;
              }
            }
          }
        }
        return const Locale('de'); // Default
      },

      // ---- Global: Theme/Darkmode
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3453A8), brightness: Brightness.light),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3453A8), brightness: Brightness.dark),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),

      // ---- UI
      home: _loggedIn
          ? Builder(
              builder: (ctx) {
                final t = AppLocalizations.of(ctx)!;
                return Scaffold(
                  appBar: AppBar(
                    title: Text(t.appTitle),
                    actions: [
                      // Sprachwahl
                      LangAction(onLocaleChanged: _setLocale),

                      // ---- NEU: globaler Theme-Umschalter (System/Light/Dark)
                      PopupMenuButton<ThemeMode>(
                        tooltip: 'Theme',
                        position: PopupMenuPosition.under,
                        icon: Icon(_themeIconFor(_themeMode)),
                        onSelected: _setThemeMode,
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: ThemeMode.system,
                            child: Row(
                              children: [
                                Icon(Icons.brightness_auto, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 10),
                                const Text('System'),
                                const Spacer(),
                                if (_themeMode == ThemeMode.system) const Icon(Icons.check),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: ThemeMode.light,
                            child: Row(
                              children: [
                                Icon(Icons.light_mode, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 10),
                                const Text('Hell'),
                                const Spacer(),
                                if (_themeMode == ThemeMode.light) const Icon(Icons.check),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: ThemeMode.dark,
                            child: Row(
                              children: [
                                Icon(Icons.dark_mode, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 10),
                                const Text('Dunkel'),
                                const Spacer(),
                                if (_themeMode == ThemeMode.dark) const Icon(Icons.check),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 6),
                    ],
                  ),
                  body: DashboardPage(api: api, onLoggedOut: _onLoggedOut),
                );
              },
            )
          : Builder(
              builder: (ctx) {
                final t = AppLocalizations.of(ctx)!;
                return Scaffold(
                  appBar: AppBar(
                    title: Text(t.login),
                    actions: [
                      LangAction(onLocaleChanged: _setLocale),
                      PopupMenuButton<ThemeMode>(
                        tooltip: 'Theme',
                        position: PopupMenuPosition.under,
                        icon: Icon(_themeIconFor(_themeMode)),
                        onSelected: _setThemeMode,
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: ThemeMode.system,
                            child: Row(
                              children: [
                                Icon(Icons.brightness_auto, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 10),
                                const Text('System'),
                                const Spacer(),
                                if (_themeMode == ThemeMode.system) const Icon(Icons.check),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: ThemeMode.light,
                            child: Row(
                              children: [
                                Icon(Icons.light_mode, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 10),
                                const Text('Hell'),
                                const Spacer(),
                                if (_themeMode == ThemeMode.light) const Icon(Icons.check),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: ThemeMode.dark,
                            child: Row(
                              children: [
                                Icon(Icons.dark_mode, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 10),
                                const Text('Dunkel'),
                                const Spacer(),
                                if (_themeMode == ThemeMode.dark) const Icon(Icons.check),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 6),
                    ],
                  ),
                  body: LoginPage(
                    api: api,
                    onLoggedIn: _onLoggedIn,
                    onOpenAdmin: () => _openAdmin(ctx),
                    onOpenRegister: () => _openRegister(ctx),
                  ),
                );
              },
            ),
    );
  }
}