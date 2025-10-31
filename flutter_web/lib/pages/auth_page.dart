import 'package:flutter/material.dart';
import 'dart:html' as html;
import '../api/client.dart';
import '../l10n/app_localizations.dart';

class AuthPage extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onLoggedIn;
  const AuthPage({super.key, required this.api, required this.onLoggedIn});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool isLogin = true;

  final _email = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  final _company = TextEditingController();
  final _contact = TextEditingController();
  final _street = TextEditingController();
  final _zip = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController(text: 'Germany');
  final _phone = TextEditingController();

  bool _privacy = false;
  String? _err;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    _pw2.dispose();
    _company.dispose();
    _contact.dispose();
    _street.dispose();
    _zip.dispose();
    _city.dispose();
    _country.dispose();
    _phone.dispose();
    super.dispose();
  }

  // -------- Sprache aus aktueller UI ableiten (nur zulässige Codes) --------
  String _langCode(BuildContext ctx) {
    final lc = Localizations.localeOf(ctx).languageCode.toLowerCase();
    switch (lc) {
      case 'de':
      case 'en':
      case 'fr':
      case 'it':
      case 'es':
        return lc;
      default:
        return 'de';
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
              onPressed: (i) => setState(() => isLogin = i == 0),
              children: [
                Padding(padding: const EdgeInsets.all(8), child: Text(t.auth_login)),
                Padding(padding: const EdgeInsets.all(8), child: Text(t.auth_register)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              decoration: InputDecoration(
                labelText: t.email,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pw,
              obscureText: true,
              decoration: InputDecoration(
                labelText: t.password,
                border: const OutlineInputBorder(),
              ),
            ),
            if (!isLogin) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _pw2,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: t.password_repeat,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _company,
                decoration: InputDecoration(
                  labelText: t.company,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _contact,
                decoration: InputDecoration(
                  labelText: t.contact,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _street,
                decoration: InputDecoration(
                  labelText: t.street,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _zip,
                      decoration: InputDecoration(
                        labelText: t.zip,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _city,
                      decoration: InputDecoration(
                        labelText: t.city,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _country,
                decoration: InputDecoration(
                  labelText: t.country,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _phone,
                decoration: InputDecoration(
                  labelText: t.phone,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: _privacy,
                    onChanged: (v) => setState(() => _privacy = v ?? false),
                  ),
                  Expanded(child: Text(t.privacy_agree)),
                  TextButton(
                    onPressed: () => html.window.open(
                      'https://www.dfs-diamon.de/datenschutz',
                      '_blank',
                    ),
                    child: Text(t.privacy_link),
                  ),
                ],
              ),
            ],
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _err!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _busy ? null : () async => _handlePress(context),
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isLogin ? t.auth_login : t.auth_register),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePress(BuildContext context) async {
    final t = AppLocalizations.of(context)!;

    setState(() {
      _busy = true;
      _err = null;
    });

    try {
      if (isLogin) {
        final ok = await widget.api.login(_email.text, _pw.text);
        if (!mounted) return;
        if (ok) {
          widget.onLoggedIn();
        } else {
          setState(() => _err = t.login_failed);
        }
        return;
      }

      // Registrierung
      if (!_privacy) {
        if (!mounted) return;
        setState(() => _err = t.privacy_required);
        return;
      }

      final r = await widget.api.register({
        'email': _email.text,
        'password': _pw.text,
        'password2': _pw2.text,
        'company': _company.text,
        'contact': _contact.text,
        'street': _street.text,
        'zip': _zip.text,
        'city': _city.text,
        'country': _country.text,
        'phone': _phone.text,
        'privacy': true,
        'lang': _langCode(context), // Sprache mitgeben
      });

      if (!mounted) return;

      if (r.statusCode == 200) {
        setState(() {
          isLogin = true;
          _err = t.registration_received;
        });
      } else if (r.statusCode == 409) {
        final body = r.body?.toString() ?? '';
        if (body.contains('user_exists')) {
          setState(() => _err = 'E-Mail ist bereits registriert.');
        } else if (body.contains('pending') || body.contains('resent')) {
          setState(() => _err = 'Registrierung liegt bereits vor. Bestätigungs-E-Mail wurde erneut gesendet.');
        } else {
          setState(() => _err = t.register_failed(body));
        }
      } else {
        setState(() => _err = t.register_failed(r.body));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = 'Network/CORS error: $e');
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }
}
