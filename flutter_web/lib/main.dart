// lib/main.dart
import 'dart:html' as html; // für Sprache persistieren
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
    // gespeicherte Sprache laden
    final saved = html.window.localStorage['dfs_lang'];
    if (saved != null && saved.isNotEmpty) {
      _locale = Locale(saved);
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

  // --- Admin-Secret Dialog + Navigation ---
  Future<void> _openAdmin(BuildContext context) async {
    final t = AppLocalizations.of(context)!;
    final ctrl = TextEditingController(text: api.adminSecret ?? '');
    final wantOpen = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t.adminArea), // oder t.adminTitle
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: t.adminSecret,
            border: const OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.open),
          ),
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
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AdminPage(api: api)),
    );
  }

  void _openRegister(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => RegisterPage(api: api)));
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
        Locale('de'), Locale('en'), Locale('fr'), Locale('it'), Locale('es'),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Fallback, wenn Browser-Sprache nicht unterstützt wird
      localeResolutionCallback: (deviceLocales, supported) {
        if (_locale != null) return _locale;
        if (deviceLocales != null && deviceLocales.isNotEmpty) {
          final lang = deviceLocales.first.languageCode.toLowerCase();
          for (final s in supported) {
            if (s.languageCode.toLowerCase() == lang) return s;
          }
        }
        return const Locale('de');
      },
      home: _loggedIn
          ? Builder(
              builder: (ctx) {
                final t = AppLocalizations.of(ctx)!;
                return Scaffold(
                  appBar: AppBar(
                    title: Text(t.appTitle),
                    actions: [LangAction(onLocaleChanged: _setLocale)],
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
                    // WICHTIG: kein const + lokalisiert
                    title: Text(t.login),
                    actions: [LangAction(onLocaleChanged: _setLocale)],
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
