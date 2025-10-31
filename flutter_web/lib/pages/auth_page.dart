// lib/pages/auth_page.dart
import 'package:flutter/material.dart';
import 'dart:html' as html;

// Falls du eine eigene ApiClient-Datei hast, Pfad so lassen:
import '../api/client.dart';

// WICHTIG: hier je nach Projektstruktur den korrekten L10N-Import verwenden.
// Wenn du "flutter gen-l10n" nutzt, ist es meist:
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
// Falls du stattdessen eine eigene Datei nutzt, dann DIESE hier aktivieren
// und die Zeile oben auskommentieren:
// import '../l10n/app_localizations.dart';

class AuthPage extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onLoggedIn;

  const AuthPage({super.key, required this.api, required this.onLoggedIn});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool isLogin = true;

  final _email = TextEditingController(), _pw = TextEditingController();
  final _pw2 = TextEditingController(), _company = TextEditingController();
  final _contact = TextEditingController(), _street = TextEditingController();
  final _zip = TextEditingController(), _city = TextEditingController();
  final _country = TextEditingController(text: 'Germany');
  final _phone = TextEditingController();

  bool _privacy = false;
  String? _err;
  bool _busy = false;

  Future<void> _doLogin(BuildContext context) async {
    final t = AppLocalizations.of(context)!;
    setState(() { _busy = true; _err = null; });
    try {
      final ok = await widget.api.login(_email.text.trim(), _pw.text);
      if (!mounted) return;
      if (ok) {
        widget.onLoggedIn();
      } else {
        setState(() => _err = t.login_failed);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = 'Network/CORS error: $e');
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _doRegister(BuildContext context) async {
    final t = AppLocalizations.of(context)!;

    // leichte Client-Validierungen
    final email = _email.text.trim();
    final pw    = _pw.text;
    final pw2   = _pw2.text;

    String? vErr;
    if (email.isEmpty || !email.contains('@')) vErr = t.email_invalid;
    else if (pw.length < 8) vErr = t.password_policy;          // mind. 8 Zeichen
    else if (pw != pw2) vErr = t.password_mismatch;
    else if (!_privacy) vErr = t.privacy_required;

    if (vErr != null) {
      setState(() { _err = vErr; _busy = false; });
      return;
    }

    setState(() { _busy = true; _err = null; });
    try {
      final r = await widget.api.register({
        'email': email,
        'password': pw,
        'password2': pw2,
        'company': _company.text.trim(),
        'contact': _contact.text.trim(),
        'street': _street.text.trim(),
        'zip': _zip.text.trim(),
        'city': _city.text.trim(),
        'country': _country.text.trim(),
        'phone': _phone.text.trim(),
        'privacy': true,
      });

      if (!mounted) return;

      if (r.statusCode == 200) {
        setState(() {
          isLogin = true;
          _err = t.registration_received; // Erfolgsmeldung
        });
      } else {
        setState(() {
          _err = t.register_failed(r.body);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = 'Network/CORS error: $e');
    } finally {
      if (!mounted) return;
      setState(() => _busy = false); // immer entsperren
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Center(
      child: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ToggleButtons(
              isSelected: [isLogin, !isLogin],
              onPressed: (i) { setState(() => isLogin = i == 0); },
              children: [
                Padding(padding: const EdgeInsets.all(8), child: Text(t.auth_login)),
                Padding(padding: const EdgeInsets.all(8), child: Text(t.auth_register)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              decoration: InputDecoration(labelText: t.email, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pw,
              obscureText: true,
              decoration: InputDecoration(labelText: t.password, border: const OutlineInputBorder()),
            ),
            if (!isLogin) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _pw2,
                obscureText: true,
                decoration: InputDecoration(labelText: t.password_repeat, border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(controller: _company, decoration: InputDecoration(labelText: t.company, border: const OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: _contact, decoration: InputDecoration(labelText: t.contact, border: const OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: _street, decoration: InputDecoration(labelText: t.street, border: const OutlineInputBorder())),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: _zip,  decoration: InputDecoration(labelText: t.zip,  border: const OutlineInputBorder()))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _city, decoration: InputDecoration(labelText: t.city, border: const OutlineInputBorder()))),
              ]),
              const SizedBox(height: 8),
              TextField(controller: _country, decoration: InputDecoration(labelText: t.country, border: const OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: _phone, decoration: InputDecoration(labelText: t.phone, border: const OutlineInputBorder())),
              const SizedBox(height: 8),
              Row(children: [
                Checkbox(value: _privacy, onChanged: (v) => setState(() => _privacy = v ?? false)),
                Expanded(child: Text(t.privacy_agree)),
                TextButton(
                  onPressed: () { html.window.open('https://www.dfs-diamon.de/datenschutz', '_blank'); },
                  child: Text(t.privacy_link),
                ),
              ]),
            ],
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_err!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _busy
                  ? null
                  : () {
                      if (isLogin) {
                        _doLogin(context);
                      } else {
                        _doRegister(context);
                      }
                    },
              child: _busy
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(isLogin ? t.auth_login : t.auth_register),
            ),
          ],
        ),
      ),
    );
  }
}
