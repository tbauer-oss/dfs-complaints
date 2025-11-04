// lib/pages/login_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';

class LoginPage extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onLoggedIn;
  final VoidCallback onOpenRegister;
  final VoidCallback onOpenAdmin;
  final VoidCallback onOpenRep; // ← NEU

  const LoginPage({
    super.key,
    required this.api,
    required this.onLoggedIn,
    required this.onOpenRegister,
    required this.onOpenAdmin,
    required this.onOpenRep, // ← NEU
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _pw    = TextEditingController();
  bool _busy = false;
  String? _err;

  Future<void> _doLogin() async {
    setState(() { _busy = true; _err = null; });
    try {
      final ok = await widget.api.login(_email.text.trim(), _pw.text);
      if (ok) {
        widget.onLoggedIn();
      } else {
        setState(() => _err = AppLocalizations.of(context)?.loginFailed ?? 'Login fehlgeschlagen.');
      }
    } catch (e) {
      setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    String tx(String? s, String fb) => (s == null || s.isEmpty) ? fb : s;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Adminbereich & Vertreter (oben rechts nebeneinander)
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('Adminbereich'),
                    onPressed: _busy ? null : widget.onOpenAdmin,
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.handshake_outlined),
                    label: const Text('Vertreter'),
                    onPressed: _busy ? null : widget.onOpenRep, // ← NEU
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: tx(t?.email, 'E-Mail*'),
                border: const OutlineInputBorder(),
              ),
              enabled: !_busy,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pw,
              obscureText: true,
              decoration: InputDecoration(
                labelText: tx(t?.password, 'Passwort*'),
                border: const OutlineInputBorder(),
              ),
              enabled: !_busy,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy ? null : _doLogin,
                child: _busy
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Login'),
              ),
            ),

            if (_err != null) ...[
              const SizedBox(height: 8),
              Text(_err!, style: const TextStyle(color: Colors.red)),
            ],

            const SizedBox(height: 16),

            TextButton.icon(
              icon: const Icon(Icons.person_add_alt),
              label: Text(tx(t?.register, 'Registrieren')),
              onPressed: _busy ? null : widget.onOpenRegister,
            ),
          ],
        ),
      ),
    );
  }
}
