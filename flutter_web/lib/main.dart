// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api/client.dart';
import 'l10n/app_localizations.dart';

import 'pages/login_page.dart';
import 'pages/register_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/admin_page.dart';

import 'widgets/lang_action.dart';
import 'widgets/logout_action.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DFSApp());
}

class DFSApp extends StatefulWidget {
  const DFSApp({super.key});
  @override
  State<DFSApp> createState() => _DFSAppState();
}

class _DFSAppState extends State<DFSApp> {
  final api = ApiClient();

  bool _booting = true;
  bool _loggedIn = false;
  Locale? _forcedLocale; // für LangAction (globale Umschaltung)

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // 1) Session aus localStorage lesen
    await api.restoreSession();

    // 2) Token (falls vorhanden) serverseitig validieren
    var ok = false;
    if (api.token != null && api.token!.isNotEmpty) {
      try {
        await api.accountGet(); // 200 = ok
        ok = true;
      } catch (_) {
        api.logout();
        ok = false;
      }
    }

    setState(() {
      _loggedIn = ok;
      _booting = false;
    });
  }

  void _onLoggedIn() {
    setState(() => _loggedIn = true);
  }

  void _onLoggedOut() {
    api.logout();
    setState(() => _loggedIn = false);
  }

  // LangAction ruft diesen Setter auf
  void _setLocale(Locale? loc) {
    setState(() => _forcedLocale = loc);
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // Globale Lokalisierung
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('de'),
        Locale('en'),
        Locale('fr'),
        Locale('it'),
        Locale('es'),
      ],
      locale: _forcedLocale, // von LangAction gesetzt
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5A63FF)),
        useMaterial3: true,
      ),

      // === HOME entscheidet: Login oder Dashboard ===
      home: _loggedIn
          ? _DashboardShell(
              api: api,
              onLoggedOut: _onLoggedOut,
              onLocaleChanged: _setLocale,
            )
          : _LoginShell(
              api: api,
              onLoggedIn: _onLoggedIn,
              onLocaleChanged: _setLocale,
            ),

      // Routen, die wir zusätzlich brauchen
      routes: {
        '/admin': (_) => AdminPage(api: api), // optional
      },
    );
  }
}

/// Wrapper mit AppBar für die Login-Ansicht (Startseite)
class _LoginShell extends StatelessWidget {
  final ApiClient api;
  final VoidCallback onLoggedIn;
  final void Function(Locale? locale) onLocaleChanged;

  const _LoginShell({
    required this.api,
    required this.onLoggedIn,
    required this.onLocaleChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.login), // „Login“
        actions: [
          LangAction(onLocaleChanged: onLocaleChanged),
          const SizedBox(width: 8),
          // Button zum Adminbereich (öffnet /admin-Route)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AdminPage(api: api)),
              ),
              icon: const Icon(Icons.admin_panel_settings),
              label: Text(t.admin_area), // bitte Key in l10n hinzufügen
            ),
          ),
        ],
      ),
      body: LoginPage(
        api: api,
        onLoggedIn: onLoggedIn,
        onOpenRegister: () {
          // Gate-Abfrage machst du in der RegisterPage selbst weiter
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => RegisterPage(api: api)),
          );
        },
      ),
    );
  }
}

/// Wrapper mit AppBar für den Kundenbereich (nur nach Login)
class _DashboardShell extends StatelessWidget {
  final ApiClient api;
  final VoidCallback onLoggedOut;
  final void Function(Locale? locale) onLocaleChanged;

  const _DashboardShell({
    required this.api,
    required this.onLoggedOut,
    required this.onLocaleChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.customer_area), // z. B. „Kundenbereich“
        actions: [
          LangAction(onLocaleChanged: onLocaleChanged),
          const SizedBox(width: 8),
          LogoutAction(api: api, onLoggedOut: onLoggedOut),
          const SizedBox(width: 8),
        ],
      ),
      // Wichtig: Der eigentliche Inhalt ist dein bisheriger Dashboard-Bildschirm
      body: DashboardPage(api: api),
    );
  }
}
