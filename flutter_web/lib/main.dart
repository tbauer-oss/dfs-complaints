// lib/main.dart
import 'dart:html' as html; // nur Web: Sprache & Theme persistieren
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api/client.dart';
import 'l10n/app_localizations.dart';

// ⚠️ Präfixierte Imports zur Kollisionsvermeidung:
import 'pages/login_page.dart' as lp;
import 'pages/register_page.dart';
import 'pages/admin_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/rep_login_page.dart' as rp;
import 'pages/rep_dashboard_page.dart';
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

  // Globaler ThemeMode (persistiert)
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();

    // Sprache laden
    final savedLang = html.window.localStorage['dfs_lang'];
    if (savedLang != null && savedLang.isNotEmpty) {
      _locale = Locale(savedLang);
    }

    // ThemeMode laden
    final savedTheme = (html.window.localStorage['dfs_theme'] ?? '').toLowerCase();
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

  void _setThemeMode(ThemeMode m) {
    setState(() => _themeMode = m);
    html.window.localStorage['dfs_theme'] = switch (m) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }

  // Kompaktes Theme-Menü mit Icons
  Widget _themeMenu() {
    IconData icon;
    switch (_themeMode) {
      case ThemeMode.dark:
        icon = Icons.dark_mode;
        break;
      case ThemeMode.light:
        icon = Icons.light_mode;
        break;
      default:
        icon = Icons.brightness_auto;
    }

    return PopupMenuButton<ThemeMode>(
      tooltip: 'Theme',
      icon: Icon(icon),
      onSelected: _setThemeMode,
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: ThemeMode.system,
          child: Row(
            children: [
              const Icon(Icons.brightness_auto),
              const SizedBox(width: 10),
              const Text('System'),
              if (_themeMode == ThemeMode.system) const Spacer(),
              if (_themeMode == ThemeMode.system)
                const Icon(Icons.check, color: Colors.green),
            ],
          ),
        ),
        PopupMenuItem(
          value: ThemeMode.light,
          child: Row(
            children: [
              const Icon(Icons.light_mode),
              const SizedBox(width: 10),
              const Text('Light'),
              if (_themeMode == ThemeMode.light) const Spacer(),
              if (_themeMode == ThemeMode.light)
                const Icon(Icons.check, color: Colors.green),
            ],
          ),
        ),
        PopupMenuItem(
          value: ThemeMode.dark,
          child: Row(
            children: [
              const Icon(Icons.dark_mode),
              const SizedBox(width: 10),
              const Text('Dark'),
              if (_themeMode == ThemeMode.dark) const Spacer(),
              if (_themeMode == ThemeMode.dark)
                const Icon(Icons.check, color: Colors.green),
            ],
          ),
        ),
      ],
    );
  }

  // Admin-Secret Dialog + Navigation
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.required_fields)),
      );
      return;
    }

    final ok = await api.validateAdminSecret(secret);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.errorGeneric('Admin-Secret'))),
      );
      return;
    }

    api.setAdminSecret(secret);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminPage(api: api)));
  }

  void _openRegister(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => RegisterPage(api: api)));
  }

  void _openRepArea() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => rp.RepLoginPage(
          api: api,
          onLoggedIn: () {
            if (!mounted) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => RepDashboardPage(api: api)),
            );
          },
        ),
      ),
    );
  }

  void _onLoggedIn() => setState(() => _loggedIn = true);
  void _onLoggedOut() => setState(() => _loggedIn = false);

  @override
  Widget build(BuildContext context) {
    if (!_bootDone) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: const [
        Locale('de'),
        Locale('en'),
        Locale('fr'),
        Locale('it'),
        Locale('es'),
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

      // GLOBAL THEME (Material 3)
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1F4C8F), // DFS-Blau
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1F4C8F),
        brightness: Brightness.dark,
      ),

      // NAVIGATION / START
      home: _loggedIn
          ? Builder(
              builder: (ctx) {
                final t = AppLocalizations.of(ctx)!;
                return Scaffold(
                  appBar: AppBar(
                    title: Text(t.appTitle),
                    actions: [
                      // Sprache
                      LangAction(onLocaleChanged: _setLocale),
                      // Theme-Menü (global)
                      _themeMenu(),
                    ],
                    // Logout unten in der AppBar
                    bottom: PreferredSize(
                      preferredSize: const Size.fromHeight(50),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: FilledButton.icon(
                            icon: const Icon(Icons.logout),
                            label: Text(t.logout),
                            onPressed: () async {
                              await api.logout();
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text(t.loggedOut)),
                                );
                              }
                              _onLoggedOut();
                            },
                          ),
                        ),
                      ),
                    ),
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
                      _themeMenu(), // auch auf Login-Seite
                    ],
                  ),
                  body: lp.LoginPage(
                    api: api,
                    // ⤵️ Korrekte, kontextgebundene Closures statt fehlender Methoden
                    onLoggedIn: _onLoggedIn, // setzt _loggedIn = true
                    onOpenRegister: () => _openRegister(ctx),
                    onOpenAdmin: () => _openAdmin(ctx),
                    onOpenRep: _openRepArea,
                  ),
                );
              },
            ),
    );
  }
}