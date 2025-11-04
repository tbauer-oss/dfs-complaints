// lib/pages/rep_login_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import 'rep_dashboard_page.dart';

class RepLoginPage extends StatefulWidget {
  final ApiClient api;
  const RepLoginPage({super.key, required this.api});

  @override
  State<RepLoginPage> createState() => _RepLoginPageState();
}

class _RepLoginPageState extends State<RepLoginPage> {
  final _email = TextEditingController();
  final _pw    = TextEditingController();
  final _new1  = TextEditingController();
  final _new2  = TextEditingController();

  bool _busy = false;
  String? _err;

  Future<void> _login() async {
    setState(() { _busy = true; _err = null; });
    try {
      final ok = await widget.api.repLogin(_email.text.trim(), _pw.text);
      if (!ok) {
        setState(() => _err = 'Login fehlgeschlagen.');
        return;
      }

      // Hinweis: Falls du "mustChangePw" erzwingen willst,
      // kannst du das Backend-Flag später in ApiClient.repLogin zurückgeben
      // und hier abfragen. Aktuell navigieren wir direkt ins Dashboard.
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RepDashboardPage(api: widget.api)),
      );
    } catch (e) {
      setState(() => _err = 'Netzwerk-/Serverfehler: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showChangePasswordDialog() async {
    _new1.clear();
    _new2.clear();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool saving = false;
        String? localErr;

        Future<void> save() async {
          if (saving) return;
          final a = _new1.text.trim();
          final b = _new2.text.trim();
          if (a.isEmpty || b.isEmpty) {
            localErr = 'Bitte neues Passwort in beiden Feldern eingeben.';
            (ctx as Element).markNeedsBuild();
            return;
          }
          if (a != b) {
            localErr = 'Passwörter stimmen nicht überein.';
            (ctx as Element).markNeedsBuild();
            return;
          }
          saving = true;
          (ctx as Element).markNeedsBuild();
          try {
            await widget.api.repChangePassword(a);
            if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Passwort wurde geändert.')),
            );
          } catch (e) {
            localErr = 'Fehler: $e';
            saving = false;
            (ctx as Element).markNeedsBuild();
          }
        }

        return AlertDialog(
          title: const Text('Neues Passwort setzen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _new1,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Neues Passwort'),
              ),
              TextField(
                controller: _new2,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Neues Passwort (Wiederholung)'),
              ),
              if (localErr != null) ...[
                const SizedBox(height: 8),
                Text(localErr!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: saving ? null : save,
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Speichern'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final canLogin = !_busy && _email.text.trim().isNotEmpty && _pw.text.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Vertreter-Login')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _email,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'E-Mail'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pw,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Passwort'),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => canLogin ? _login() : null,
                  ),
                  const SizedBox(height: 16),
                  if (_err != null)
                    Text(_err!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: _busy
                          ? const SizedBox(
                              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.login),
                      label: const Text('Anmelden'),
                      onPressed: canLogin ? _login : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Optional: Passwort ändern (setzt vorhandenes Vertreter-Token voraus – also nach Login sinnvoll)
                  TextButton.icon(
                    onPressed: _busy ? null : _showChangePasswordDialog,
                    icon: const Icon(Icons.lock_reset),
                    child: const Text('Passwort ändern'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
