// lib/main.dart
import 'package:flutter/material.dart';

// API-Client für Session/JWT
import 'api/client.dart';

// Seiten
import 'pages/login_page.dart';

// Lokalisierung
import 'l10n/app_localizations.dart';

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
  Locale? _locale; // optional: manuelles Umschalten, falls du es später brauchst

  @override
  void initState() {
    super.initState();
    // Einmalig Session (JWT + Gate) aus dem Browser-Speicher laden
    api.restoreSession().whenComplete(() {
      if (mounted) setState(() => _restored = true);
    });
  }

  // Falls du irgendwo eine Sprachumschaltung brauchst:
  void setLocale(Locale? loc) {
    setState(() => _locale = loc);
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

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DFS Customer Complaint',
      // Lokalisierung aktivieren
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: _locale, // bleibt null => Systemsprache

      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D47A1)), // DFS-Blau nahekommend
      ),

      // Startseite = Login
      home: LoginPage(
        api: api,
        onLoggedIn: () {
          // Optionaler Hook nach Login – die LoginPage pusht ohnehin ins Dashboard.
          // Hier könntest du z.B. Analytics o.ä. ergänzen.
        },
      ),
    );
  }
}
