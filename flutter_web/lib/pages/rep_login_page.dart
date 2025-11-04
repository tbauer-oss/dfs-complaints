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
  // --- Controller ---
  final _secret = TextEditingController();
  final _email  = TextEditingController();
  final _pw     = TextEditingController();
  final _new1   = TextEditingController();
  final _new2   = TextEditingController();

  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _secret.dispose();
    _email.dispose();
    _pw.dispose();
    _new1.dispose();
    _new2.dispose();
    super.dispose();
  }

  // ==========================
  // Secret-Login (REP_JWT_SECRET)
  // ==========================
  Future<void> _loginWithSecret() async {
    final secret = _secret.text.trim();
    if (secret.isEmpty) {
      setState(() => _err = 'Bitte Secret eingeben.');
      return;
    }

    setState(() { _busy = true; _err = null; });
    try {
      final ok = await widget.api.repLoginWithSecret(secret);
      if (!mounted) return;
      if (!ok) {
        setState(() => _err = 'Secret ungültig oder nicht akzeptiert.');
        return;
      }
      // Erfolg → Dashboard
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RepDashboardPage(api: widget.api)),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _err = 'Netzwerk-/Serverfehler: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ==========================
  // E-Mail/Passwort-Login
  // ==========================
  Future<void> _loginWithCredentials() async {
    final email = _email.text.trim();
    final pw    = _pw.text;
    if (email.isEmpty || pw.isEmpty) {
      setState(() => _err = 'Bitte E-Mail und Passwort eingeben.');
      return;
    }

    setState(() { _busy = true; _err = null; });
    try {
      final res = await widget.api.repLogin(email, pw);
      if (!mounted) return;

      if (!res.ok) {
        setState(() => _err = 'Login fehlgeschlagen. Bitte Zugangsdaten prüfen.');
        return;
      }

      if (res.mustChange) {
        // Passwortwechsel erzwingen
        await _showChangePasswordDialog();
        if (!mounted) return;
      }

      // Erfolg → Dashboard
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RepDashboardPage(api: widget.api)),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _err = 'Netzwerk-/Serverfehler: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ==========================
  // Dialog: Neues Passwort setzen (für Credentials-Flow)
  // ==========================
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
          final a = _new1.text;
          final b = _new2.text;
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
                enabled: !saving,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _new2,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Neues Passwort (Wiederholung)'),
                enabled: !saving,
              ),
              if (localErr != null) ...[
                const SizedBox(height: 12),
                Text(localErr!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Später'),
            ),
            FilledButton(
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

  // ==========================
  // UI
  // ==========================
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, // Secret | E-Mail & Passwort
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Vertreter-Login'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.key), text: 'Secret'),
              Tab(icon: Icon(Icons.person), text: 'E-Mail & Passwort'),
            ],
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (_err != null) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.08),
                        border: Border.all(color: Colors.red),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_err!, style: const TextStyle(color: Colors.red)),
                    ),
                  ],
                  Expanded(
                    child: TabBarView(
                      children: [
                        // --- TAB 1: Secret ---
                        _buildSecretTab(),
                        // --- TAB 2: Credentials ---
                        _buildCredentialsTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecretTab() {
    final canLogin = !_busy && _secret.text.trim().isNotEmpty;
    return AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _secret,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(
              labelText: 'REP Secret',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => canLogin ? _loginWithSecret() : null,
            enabled: !_busy,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.login),
              label: const Text('Anmelden (Secret)'),
              onPressed: canLogin ? _loginWithSecret : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCredentialsTab() {
    final canLogin = !_busy && _email.text.trim().isNotEmpty && _pw.text.isNotEmpty;
    return AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _email,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'E-Mail',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            enabled: !_busy,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pw,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(
              labelText: 'Passwort',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => canLogin ? _loginWithCredentials() : null,
            enabled: !_busy,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.login),
              label: const Text('Anmelden (E-Mail & Passwort)'),
              onPressed: canLogin ? _loginWithCredentials : null,
            ),
          ),
        ],
      ),
    );
  }
}