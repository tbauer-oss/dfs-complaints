import 'package:flutter/material.dart';

// API-Client
import 'api/client.dart';

// Startseite (Login)
import 'pages/login_page.dart';

// Lokalisierung
import 'l10n/app_localizations.dart';

// Globaler Sprach-Controller
import 'i18n/locale_controller.dart';

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
  final ApiClient api = ApiClient();

  bool _restored = false;

  @override
  void initState() {
    super.initState();
    // Session (JWT + Gate) einmalig aus LocalStorage laden
    api.restoreSession().whenComplete(() {
      if (mounted) setState(() => _restored = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_restored) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    // <- WICHTIG: MaterialApp hört auf den globalen LocaleController
    return ValueListenableBuilder<Locale?>(
      valueListenable: LocaleController.I.locale,
      builder: (context, appLocale, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'DFS Customer Complaint',
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: appLocale, // null = System, sonst erzwungene Sprache

          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D47A1)),
          ),

          home: LoginPage(
            api: api,
            onLoggedIn: () {
              // optionaler Hook nach Login
            },
          ),
        );
      },
    );
  }
}
