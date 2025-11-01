import 'package:flutter/material.dart';
import '../api/client.dart';
import 'register_page.dart';
import 'admin_page.dart';
import 'dashboard_page.dart';

class LoginPage extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onLoggedIn;
  const LoginPage({super.key, required this.api, required this.onLoggedIn});

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
    setState(() { _busy = true; _err = null; });
    try {
      final ok = await widget.api.login(_email.text.trim(), _pw.text);
      if (!mounted) return;
      if (ok) {
        widget.onLoggedIn();
        // Rein ins Dashboard:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => DashboardPage(api: widget.api)),
        );
      } else {
        setState(() => _err = 'Login fehlgeschlagen. Bitte Zugangsdaten prüfen.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = 'Netzwerk-/CORS-Fehler: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _gotoRegister() async {
    // Vor Eintritt in die Registrierung EINMAL Gate abfragen:
    final pass = await showDialog<String>(
      context: context,
      builder: (_) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Registrierung öffnen'),
          content: TextField(
            controller: ctrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Gate-Passwort',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Weiter'),
            ),
          ],
        );
      },
    );
    if (pass == null || pass.isEmpty) return;

    setState(() { _busy = true; _err = null; });
    try {
      final ok = await widget.api.gateUnlock(pass);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gate-Passwort ungültig.')),
        );
        return;
      }
      // Gate ok → Registrierungsseite
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RegisterPage(api: widget.api)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _gotoAdmin() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdminPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kunden-Login'),
        actions: [
          // Adminbereich oben
          TextButton.icon(
            onPressed: _gotoAdmin,
            icon: const Icon(Icons.admin_panel_settings, size: 18),
            label: const Text('Adminbereich'),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onPrimary),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'E-Mail',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _pw,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Passwort',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_err != null) ...[
                  const SizedBox(height: 8),
                  Text(_err!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _doLogin,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Anmelden'),
                  ),
                ),
                const SizedBox(height: 10),
                // Registrierung unten
                TextButton(
                  onPressed: _busy ? null : _gotoRegister,
                  child: const Text('Jetzt registrieren'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
