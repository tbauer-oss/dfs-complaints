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
  // --- Login (E-Mail + Passwort) ---
  final _email = TextEditingController();
  final _pw    = TextEditingController();
  bool _busy = false;
  String? _err;

  void _setErr(String? msg) => setState(() => _err = msg);
  void _setBusy(bool b) => setState(() => _busy = b);

  // --- Navigation ins Dashboard (ohne dfs_mode) ---
  void _goRepDashboard() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => RepDashboardPage(api: widget.api)),
      (r) => false,
    );
  }

  // =========
  // LOGIN FLOW (E-Mail + Passwort)
  // =========
  Future<void> _submitPasswordLogin() async {
    _setErr(null);
    final email = _email.text.trim().toLowerCase();
    final pw    = _pw.text;

    if (email.isEmpty || !email.contains('@')) {
      _setErr('Bitte eine gültige E-Mail-Adresse eingeben.');
      return;
    }
    if (pw.isEmpty) {
      _setErr('Bitte ein Passwort eingeben.');
      return;
    }

    _setBusy(true);
    try {
      final res = await widget.api.repLogin(email, pw);
      if (!res.ok) {
        _setErr('Anmeldung fehlgeschlagen. Bitte E-Mail/Passwort prüfen.');
        return;
      }
      if (res.mustChange) {
        // Sofort PW-Änderung erzwingen:
        await _openChangePwDialog();
        return;
      }
      // Erfolgreich -> Dashboard
      _goRepDashboard();
    } catch (e) {
      _setErr('Login fehlgeschlagen: $e');
    } finally {
      _setBusy(false);
    }
  }

  // =========
  // SECRET-REGISTRATION FLOW
  //   1) Dialog: E-Mail + temporäres Passwort (Secret)
  //   2) Direkt im Anschluss Passwort ändern
  //   3) Danach ins Dashboard
  // =========
  Future<void> _openSecretDialog() async {
    final mailCtrl = TextEditingController(text: _email.text.trim());
    final secCtrl  = TextEditingController();
    String? locErr;
    bool saving = false;

    final want = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Registrieren (temporäres Passwort)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: mailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Vertreter-E-Mail',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: secCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Temporäres Passwort (Secret)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (locErr != null) ...[
                const SizedBox(height: 8),
                Text(locErr!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      final email = mailCtrl.text.trim().toLowerCase();
                      final sec   = secCtrl.text.trim();
                      if (email.isEmpty || !email.contains('@')) {
                        setS(() => locErr = 'Bitte eine gültige E-Mail-Adresse eingeben.');
                        return;
                      }
                      if (sec.isEmpty) {
                        setS(() => locErr = 'Bitte das temporäre Passwort eingeben.');
                        return;
                      }
                      setS(() { saving = true; locErr = null; });
                      try {
                        final ok = await widget.api.repLoginWithSecret(email, sec);
                        if (!ok) {
                          setS(() {
                            saving = false;
                            locErr = 'Temporäres Passwort ungültig oder nicht zulässig.';
                          });
                          return;
                        }
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setS(() {
                          saving = false;
                          locErr = 'Fehler: $e';
                        });
                      }
                    },
              icon: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.login),
              label: const Text('Weiter'),
            ),
          ],
        ),
      ),
    );

    if (want == true) {
      // Nach erfolgreichem Secret-Login sofort Passwort-Änderung erzwingen:
      await _openChangePwDialog();
    }

    mailCtrl.dispose();
    secCtrl.dispose();
  }

  // Dialog zum Passwort-Ändern (wird nach Secret-Login oder mustChangePw aufgerufen)
  Future<void> _openChangePwDialog() async {
    final aCtrl = TextEditingController();
    final bCtrl = TextEditingController();
    String? locErr;
    bool saving = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Neues Passwort festlegen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: aCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Neues Passwort (mind. 8 Zeichen)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: bCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Neues Passwort (Wiederholung)',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) async {
                  if (!saving) {
                    await _submitChangePw(ctx, setS, aCtrl, bCtrl, (s) => locErr = s, () => saving = true);
                  }
                },
              ),
              if (locErr != null) ...[
                const SizedBox(height: 8),
                Text(locErr!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      await _submitChangePw(ctx, setS, aCtrl, bCtrl, (s) => locErr = s, () => saving = true);
                    },
              icon: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );

    aCtrl.dispose();
    bCtrl.dispose();

    if (ok == true) {
      // Passwort gesetzt → direkt ins Dashboard
      _goRepDashboard();
    }
  }

  Future<void> _submitChangePw(
    BuildContext ctx,
    void Function(void Function()) setS,
    TextEditingController aCtrl,
    TextEditingController bCtrl,
    void Function(String?) setLocErr,
    void Function() markSaving,
  ) async {
    final a = aCtrl.text;
    final b = bCtrl.text;
    if (a.isEmpty || b.isEmpty) {
      setS(() => setLocErr('Bitte das neue Passwort in beiden Feldern eingeben.'));
      return;
    }
    if (a != b) {
      setS(() => setLocErr('Passwörter stimmen nicht überein.'));
      return;
    }
    if (a.length < 8) {
      setS(() => setLocErr('Das Passwort muss mindestens 8 Zeichen lang sein.'));
      return;
    }

    setS(() { markSaving(); setLocErr(null); });
    try {
      await widget.api.repChangePassword(a); // setzt ggf. neues Token
      if (ctx.mounted) Navigator.pop(ctx, true);
    } catch (e) {
      setS(() => setLocErr('Passwort setzen fehlgeschlagen: $e'));
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canLogin = !_busy && _email.text.trim().isNotEmpty && _pw.text.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Vertreter-Login')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ---- Login-Formular (immer sichtbar) ----
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'E-Mail',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
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
                    onSubmitted: (_) => canLogin ? _submitPasswordLogin() : null,
                  ),
                  const SizedBox(height: 12),
                  if (_err != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_err!, style: const TextStyle(color: Colors.red)),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: canLogin ? _submitPasswordLogin : null,
                      icon: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.login),
                      label: const Text('Anmelden'),
                    ),
                  ),

                  const SizedBox(height: 18),
                  Row(
                    children: const [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('oder'),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ---- Registrierung via temporärem Passwort ----
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _openSecretDialog,
                      icon: const Icon(Icons.key),
                      label: const Text('Ich habe ein temporäres Passwort'),
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
}
