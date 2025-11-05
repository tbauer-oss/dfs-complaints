// lib/main.dart
import 'dart:html' as html; // nur Web: Sprache & Theme persistieren
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api/client.dart';
import 'l10n/app_localizations.dart';

// WICHTIG: Keine login_page.dart mehr importieren!
// import 'pages/login_page.dart'  <-- entfernt
import 'pages/register_page.dart';
import 'pages/admin_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/rep_login_page.dart' show RepLoginPage;
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
  bool _loggedIn = false; // -> bleibt für den Kunden-Login (token) zuständig

  ThemeMode _themeMode = ThemeMode.system;

  // Globaler Navigator-Key (für Redirects im builder)
  final _navKey = GlobalKey<NavigatorState>();

  // ---- kleine Helfer für den Gating-Check ----
  bool get _customerLoggedIn => (api.token != null && api.token!.isNotEmpty);
  bool get _repLoggedIn {
    final repTok = (api.repToken != null && api.repToken!.isNotEmpty);
    final mode   = (html.window.localStorage['dfs_mode'] ?? '').toLowerCase();
    final isRepMode = mode == 'rep';
    // Wenn ein Vertreter-Token da ist ODER der Modus explizit gesetzt wurde, zeigen wir den Rep-Bereich:
    return repTok || isRepMode;
  }

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
    await api.ensureRepSession(); // invalides repToken nach Deploys o.ä. wegräumen
    setState(() {
      // _loggedIn steuert weiterhin nur den Kundenbereich;
      // der Vertreterbereich wird via _repLoggedIn im builder geroutet.
      _loggedIn = _customerLoggedIn;
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

  Widget _themeMenu() {
    final icon = switch (_themeMode) {
      ThemeMode.dark => Icons.dark_mode,
      ThemeMode.light => Icons.light_mode,
      _ => Icons.brightness_auto,
    };

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

  // Vertreter-Bereich öffnen: zur Rep-Login-Route
  void _openRepArea(BuildContext ctx) {
    Navigator.of(ctx).pushNamed('/repLogin');
  }

  void _onLoggedIn() => setState(() => _loggedIn = true);   // Kundenlogin
  void _onLoggedOut() => setState(() => _loggedIn = false); // Kundenlogout

  @override
  Widget build(BuildContext context) {
    if (!_bootDone) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    // Eine (!) MaterialApp mit benannten Routen
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: _navKey,
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
        return const Locale('de');
      },

      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1F4C8F),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1F4C8F),
        brightness: Brightness.dark,
      ),

      // Feste Start-Route (Login/Startseite)
      initialRoute: '/login',

      // Benannte Routen
      routes: {
        // Start-/Login-Shell (beinhaltet deinen alten "home:"-Block dynamisch)
        '/login': (_) => _RootLoginShell(
              api: api,
              themeMenu: _themeMenu(),
              onLocaleChanged: _setLocale,
              onLoggedIn: _onLoggedIn,
              onOpenRegister: _openRegister,
              onOpenAdmin: _openAdmin,
              onOpenRep: _openRepArea,
              loggedIn: _loggedIn,
              onLoggedOut: _onLoggedOut,
            ),

        // Vertreter-Login (deine existierende Seite)
        '/repLogin': (_) => RepLoginPage(api: api),

        // Vertreter-Dashboard
        '/rep': (_) => RepDashboardPage(api: api),
      },

      // Zentraler Redirect je nach Rep-Status
      builder: (context, child) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _navKey.currentContext ?? context;
          final route = ModalRoute.of(ctx);
          final name = route?.settings.name;

          if (_repLoggedIn && name != '/rep') {
            _navKey.currentState?.pushNamedAndRemoveUntil('/rep', (r) => false);
          } else if (!_repLoggedIn && name == '/rep') {
            _navKey.currentState?.pushNamedAndRemoveUntil('/login', (r) => false);
          }
        });
        return child!;
      },
    );
  }
}

// =======================
// Root-Shell für Kunden-Start/Login (ersetzt vorheriges home:)
// =======================
class _RootLoginShell extends StatelessWidget {
  final ApiClient api;
  final Widget themeMenu;
  final void Function(Locale) onLocaleChanged;
  final VoidCallback onLoggedIn;
  final void Function(BuildContext) onOpenRegister;
  final void Function(BuildContext) onOpenAdmin;
  final void Function(BuildContext) onOpenRep;
  final bool loggedIn;
  final VoidCallback onLoggedOut;

  const _RootLoginShell({
    required this.api,
    required this.themeMenu,
    required this.onLocaleChanged,
    required this.onLoggedIn,
    required this.onOpenRegister,
    required this.onOpenAdmin,
    required this.onOpenRep,
    required this.loggedIn,
    required this.onLoggedOut,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    if (loggedIn) {
      // Dein alter "home:"-Block für eingeloggte Kunden
      return Scaffold(
        appBar: AppBar(
          title: Text(t.appTitle),
          actions: [
            LangAction(onLocaleChanged: onLocaleChanged),
            themeMenu,
          ],
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
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(t.loggedOut)),
                      );
                    }
                    onLoggedOut();
                  },
                ),
              ),
            ),
          ),
        ),
        body: DashboardPage(api: api, onLoggedOut: onLoggedOut),
      );
    }

    // Nicht eingeloggt -> interner Login-Screen
    return Scaffold(
      appBar: AppBar(
        title: Text(t.login),
        actions: [
          LangAction(onLocaleChanged: onLocaleChanged),
          themeMenu,
        ],
      ),
      body: _LoginScreen(
        api: api,
        onLoggedIn: onLoggedIn,
        onOpenRegister: () => onOpenRegister(context),
        onOpenAdmin: () => onOpenAdmin(context),
        onOpenRep: () => onOpenRep(context),
      ),
    );
  }
}

// =======================
// Interner Login-Screen (Kundenbereich)
// =======================
class _LoginScreen extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onLoggedIn;
  final VoidCallback onOpenRegister;
  final VoidCallback onOpenAdmin;
  final VoidCallback onOpenRep;

  const _LoginScreen({
    required this.api,
    required this.onLoggedIn,
    required this.onOpenRegister,
    required this.onOpenAdmin,
    required this.onOpenRep,
  });

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _email = TextEditingController();
  final _pw    = TextEditingController();
  bool _busy = false;
  String? _err;

  Future<void> _doLogin() async {
    setState(() { _busy = true; _err = null; });
    try {
      final ok = await widget.api.login(_email.text.trim(), _pw.text); // Kunden-Login
      if (!mounted) return;
      if (ok) {
        widget.onLoggedIn();
      } else {
        setState(() => _err = AppLocalizations.of(context)!.invalid);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _email,
                decoration: InputDecoration(
                  labelText: t.email,
                  border: const OutlineInputBorder(),
                ),
                enabled: !_busy,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pw,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: t.password,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _busy ? null : _doLogin(),
                enabled: !_busy,
              ),
              const SizedBox(height: 16),
              if (_err != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_err!, style: const TextStyle(color: Colors.red)),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _doLogin,
                  child: _busy
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(t.login),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.person_add_alt),
                    onPressed: _busy ? null : widget.onOpenRegister,
                    label: Text(t.register),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.admin_panel_settings),
                    onPressed: _busy ? null : widget.onOpenAdmin,
                    label: Text(t.admin_area),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
