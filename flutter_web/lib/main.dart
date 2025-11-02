// lib/main.dart
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

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await api.restoreSession();
    setState(() {
      _loggedIn = (api.token != null && api.token!.isNotEmpty);
      _bootDone = true;
    });
  }

  void _setLocale(Locale l) => setState(() => _locale = l);

  // --- Admin-Secret Dialog + Navigation ---
  Future<void> _openAdmin(BuildContext context) async {
    final ctrl = TextEditingController(text: api.adminSecret ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Admin-Secret'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'X-Admin-Secret',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Öffnen')),
        ],
      ),
    );
    if (ok == true) {
      api.setAdminSecret(ctrl.text.trim());
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminPage()));
    }
  }

  // --- Registrierung öffnen ---
  void _openRegister(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => RegisterPage(api: api)));
  }

  // --- Nach Login zum Dashboard ---
  void _onLoggedIn() => setState(() => _loggedIn = true);

  // --- Nach Logout zurück zum Login ---
  void _onLoggedOut() => setState(() => _loggedIn = false);

  @override
  Widget build(BuildContext context) {
    if (!_bootDone) {
      return const MaterialApp(home: Scaffold(body: Center(child: CircularProgressIndicator())));
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
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: _loggedIn
          ? Scaffold(
              
              body: DashboardPage(api: api, onLoggedOut: _onLoggedOut),
            )
          : Scaffold(
            // ... Login bleibt unverändert
              appBar: AppBar(
                title: const Text('Login'),
                actions: [
                  LangAction(onLocaleChanged: _setLocale),
                ],
              ),
              body: Builder(
                builder: (ctx) => LoginPage(
                  api: api,
                  onLoggedIn: _onLoggedIn,
                  onOpenAdmin: () => _openAdmin(ctx),
                  onOpenRegister: () => _openRegister(ctx),
                ),
              ),
            ),
    );
  }
}
