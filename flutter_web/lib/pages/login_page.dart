import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../widgets/lang_action.dart';

class LoginPage extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onLoggedIn;
  final VoidCallback onOpenRegister; // öffnet RegisterPage
  final VoidCallback onOpenAdmin;    // öffnet Adminbereich

  const LoginPage({
    super.key,
    required this.api,
    required this.onLoggedIn,
    required this.onOpenRegister,
    required this.onOpenAdmin,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _doLogin() async {
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
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      // <<< HIER kommt die globale Sprachumschaltung rein
      appBar: AppBar(
        title: const Text('Login'),
        actions: const [LangAction()], // <-- Genau hier platzieren
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // --- Admin-Button ÜBER dem Login-Formular ---
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : widget.onOpenAdmin,
                  icon: const Icon(Icons.admin_panel_settings),
                  label: Text(t.admin_area), // z.B. „Adminbereich“
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
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
                onSubmitted: (_) => _busy ? null : _doLogin(),
              ),
              if (_err != null) ...[
                const SizedBox(height: 8),
                Text(_err!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _busy ? null : _doLogin,
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(t.auth_login),
              ),

              const SizedBox(height: 24),
              // --- Registrieren-Button UNTER dem Login-Formular ---
              Center(
                child: TextButton.icon(
                  onPressed: _busy ? null : widget.onOpenRegister,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: Text(t.auth_register),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
