import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api/client.dart';
import 'l10n/app_localizations.dart';

import 'pages/login_page.dart';
import 'pages/register_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/admin_page.dart';

import 'widgets/lang_action.dart';

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

  bool _ready = false;
  bool _loggedIn = false;
  Locale _locale = const Locale('de');

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await api.restoreSession();
    setState(() {
      _loggedIn = (api.token ?? '').isNotEmpty;
      _ready = true;
    });
  }

  void _setLocale(Locale l) => setState(() => _locale = l);

  void _goLogin() => setState(() => _loggedIn = false);
  void _goDashboard() => setState(() => _loggedIn = true);

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: const [
        Locale('de'), Locale('en'), Locale('fr'), Locale('it'), Locale('es'),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),
      home: _loggedIn ? _buildDashboardShell() : _buildLoginShell(),
    );
  }

  // ---------- LOGIN SHELL ----------
  Widget _buildLoginShell() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
        actions: [
          LangAction(onLocaleChanged: _setLocale),
          const SizedBox(width: 8),
        ],
      ),
      body: LoginPage(
        api: api,
        // öffnet Admin-Bereich (fragt Secret auf der Seite ab)
        onOpenAdmin: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => AdminPage(api: api)),
          );
        },
        // öffnet Registrierung (Gate-Abfrage macht RegisterPage)
        onOpenRegister: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => RegisterPage(api: api)),
          );
        },
        // optional: wenn deine LoginPage nach erfolgreichem Login NICHT selbst navigiert
        onLoggedIn: () => _goDashboard(),
      ),
    );
  }

  // ---------- DASHBOARD SHELL ----------
  Widget _buildDashboardShell() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kundenbereich'),
        actions: [
          LangAction(onLocaleChanged: _setLocale),
          const SizedBox(width: 8),
        ],
      ),
      body: DashboardPage(
        api: api,
        onLoggedOut: () {
          api.logout();
          _goLogin();
        },
      ),
    );
  }
}
