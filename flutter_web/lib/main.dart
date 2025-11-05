// lib/main.dart
import 'dart:html' as html; // nur Web: Sprache & Theme persistieren
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api/client.dart';
import 'l10n/app_localizations.dart';

// Seiten
import 'pages/register_page.dart';
import 'pages/admin_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/rep_login_page.dart';
import 'pages/rep_dashboard_page.dart';

// Widgets
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
  // ---- Core ----
  final api = ApiClient();
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  Locale? _locale;
  ThemeMode _themeMode = ThemeMode.system;

  bool _bootDone = false;
  bool _loggedIn = false; // Kundenlogin (token) steuert den Kunden-Flow

  // ---- Helpers ----
  bool get _customerLoggedIn => (api.token != null && api.token!.isNotEmpty);
  bool get _repLoggedIn => (api.repToken != null && api.repToken!.isNotEmpty);

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
      _loggedIn = _customerLoggedIn; // Kunden-Flow bleibt unabhängig vom Vertreter-Flow
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

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: _navKey,

      // ---- i18n ----
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

      // ---- Theme ----
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

      // ---- Routing ----
      initialRoute: '/',
      routes: {
        // Root / Startseite: Kunden-Flow
        '/': (_) => Builder(
              builder: (ctx) {
                final t = AppLocalizations.of(ctx)!;
                return _loggedIn
                    ? Scaffold(
                        appBar: AppBar(
                          title: Text(t.appTitle),
                          actions: [
                            LangAction(onLocaleChanged: _setLocale),
                            _themeMenu(),
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
                                    await api.logout(); // Kunden-Logout
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
                      )
                    : Scaffold(
                        appBar: AppBar(
                          title: Text(t.login),
                          actions: [
                            LangAction(onLocaleChanged: _setLocale),
                            _themeMenu(),
                          ],
                        ),
                        body: _LoginScreen(
                          api: api,
                          onLoggedIn: _onLoggedIn,
                          onOpenRegister: () => _openRegister(ctx),
                          onOpenAdmin: () => _openAdmin(ctx),
                          onOpenRep: () => _openRepArea(ctx), // -> /repLogin
                        ),
                      );
              },
            ),

        // Vertreter-Login (immer erreichbar; kein Token nötig)
        '/repLogin': (_) => RepLoginPage(api: api),

        // Vertreter-Dashboard (nur gültig, wenn repToken vorhanden)
        '/rep': (_) => RepDashboardPage(api: api),
      },

      // Guard-Logik zentral
      onGenerateRoute: (settings) {
        final name = settings.name ?? '/';

        // Versucht, direkt ins Rep-Dashboard zu gehen -> nur erlaubt mit repToken
        if (name == '/rep' && !_repLoggedIn) {
          return MaterialPageRoute(
            builder: (_) => RepLoginPage(api: api),
            settings: const RouteSettings(name: '/repLogin'),
          );
        }

        // Ist bereits als Vertreter eingeloggt und ruft /repLogin auf -> auf /rep umbiegen
        if (name == '/repLogin' && _repLoggedIn) {
          return MaterialPageRoute(
            builder: (_) => RepDashboardPage(api: api),
            settings: const RouteSettings(name: '/rep'),
          );
        }

        return null; // standard routing nutzt oben definierte "routes"
      },
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
}
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
  final cs = Theme.of(context).colorScheme;
  const dfsBlue = Color(0xFF1F4C8F);

  final canLogin = !_busy && _email.text.trim().isNotEmpty && _pw.text.isNotEmpty;

  return Stack(
    children: [
      // ---- Hintergrund: dezenter Farbverlauf ----
      Positioned.fill(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                dfsBlue.withOpacity(0.08),
                cs.surfaceVariant.withOpacity(0.1),
              ],
            ),
          ),
        ),
      ),

      // ---- zentrierter Login-Container ----
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            elevation: 6,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---------- Logo & Titel ----------
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: dfsBlue,
                        child: const Text(
                          'DFS',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          t.appTitle,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 22),

                  // ---------- Abschnitt: Kundenlogin ----------
                  const Text(
                    'Kundenlogin',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // E-Mail-Feld
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    decoration: InputDecoration(
                      labelText: t.email,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.mail_outline),
                    ),
                    enabled: !_busy,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),

                  // Passwort-Feld
                  TextField(
                    controller: _pw,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: t.password,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                    onSubmitted: (_) => canLogin ? _doLogin() : null,
                    enabled: !_busy,
                    onChanged: (_) => setState(() {}),
                  ),

                  const SizedBox(height: 16),

                  // Fehlermeldung
                  if (_err != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _err!,
                        style: TextStyle(color: cs.error),
                      ),
                    ),

                  // Login-Button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: canLogin ? _doLogin : null,
                      style: ButtonStyle(
                        padding: WidgetStateProperty.all(
                          const EdgeInsets.symmetric(vertical: 14),
                        ),
                        backgroundColor: WidgetStateProperty.all(dfsBlue),
                      ),
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Anmelden',
                              style: TextStyle(color: Colors.white),
                            ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Registrierung-Button direkt unter Login
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : widget.onOpenRegister,
                      icon: const Icon(Icons.person_add_alt),
                      label: Text(t.register),
                    ),
                  ),

                  const SizedBox(height: 14),
                  const Divider(height: 24),

                  // ---------- Footer: Admin + Vertreter ----------
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: _busy ? null : widget.onOpenAdmin,
                        style: ButtonStyle(
                          foregroundColor: WidgetStateProperty.all(
                            cs.onSurface.withOpacity(0.72),
                          ),
                        ),
                        icon: const Icon(Icons.admin_panel_settings, size: 18),
                        label: Text(t.admin_area),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Öffne Vertreterbereich…')),
                                );
                                widget.onOpenRep();
                              },
                        style: ButtonStyle(
                          foregroundColor: WidgetStateProperty.all(
                            cs.onSurface.withOpacity(0.72),
                          ),
                        ),
                        icon: const Icon(Icons.handshake, size: 18),
                        label: Text(t.rep_area ?? 'Vertreterbereich'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
