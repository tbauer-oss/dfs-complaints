// lib/pages/rep_login_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import 'rep_dashboard_page.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../widgets/password_field.dart';
import '../widgets/legal_footer.dart';

// L10n-Helper
extension _L10nX on BuildContext {
  AppLocalizations get t => AppLocalizations.of(this)!;
}

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
    final t = context.t;
    _setErr(null);
    final email = _email.text.trim().toLowerCase();
    final pw    = _pw.text;

    if (email.isEmpty || !email.contains('@')) {
      _setErr(t.email_invalid); // NEU
      return;
    }
    if (pw.isEmpty) {
      _setErr(t.password_required); // NEU
      return;
    }

    _setBusy(true);
    try {
      final res = await widget.api.repLogin(email, pw);
      if (!res.ok) {
        _setErr(t.login_failed_check_credentials); // NEU
        return;
      }
      if (res.mustChange) {
        await _openChangePwDialog();
        return;
      }
      _goRepDashboard();
    } catch (e) {
      _setErr(t.login_failed_with_error('$e')); // NEU (parametrisierter Key)
    } finally {
      _setBusy(false);
    }
  }

  // =========
  // SECRET-REGISTRATION FLOW
  // =========
  Future<void> _openSecretDialog() async {
    final t = context.t;
    final mailCtrl = TextEditingController(text: _email.text.trim());
    final secCtrl  = TextEditingController();
    String? locErr;
    bool saving = false;

    final want = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(t.register_temp_password_title), // NEU
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: mailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: t.rep_email_label, // NEU
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              PasswordField(
                controller: secCtrl,
                decoration: InputDecoration(
                  labelText: t.temp_password_label, // NEU
                  border: const OutlineInputBorder(),
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
              child: Text(t.cancel),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      final email = mailCtrl.text.trim().toLowerCase();
                      final sec   = secCtrl.text.trim();
                      if (email.isEmpty || !email.contains('@')) {
                        setS(() => locErr = t.email_invalid); // NEU
                        return;
                      }
                      if (sec.isEmpty) {
                        setS(() => locErr = t.temp_password_required); // NEU
                        return;
                      }
                      setS(() { saving = true; locErr = null; });
                      try {
                        final ok = await widget.api.repLoginWithSecret(email, sec);
                        if (!ok) {
                          setS(() {
                            saving = false;
                            locErr = t.temp_password_invalid; // NEU
                          });
                          return;
                        }
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setS(() {
                          saving = false;
                          locErr = '${t.error ?? 'Fehler'}: $e';
                        });
                      }
                    },
              icon: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.login),
              label: Text(t.continueLabel),
            ),
          ],
        ),
      ),
    );

    if (want == true) {
      await _openChangePwDialog();
    }

    mailCtrl.dispose();
    secCtrl.dispose();
  }

  // Dialog zum Passwort-Ändern (nach Secret-Login oder mustChangePw)
  Future<void> _openChangePwDialog() async {
    final t = context.t;
    final aCtrl = TextEditingController();
    final bCtrl = TextEditingController();
    String? locErr;
    bool saving = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(t.new_password_title), // NEU
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PasswordField(
                controller: aCtrl,
                decoration: InputDecoration(
                  labelText: t.new_password_min8, // NEU
                  border: const OutlineInputBorder(),
                  helperText: t.password_requirements,
                ),
              ),
              const SizedBox(height: 10),
              PasswordField(
                controller: bCtrl,
                decoration: InputDecoration(
                  labelText: t.new_password_repeat_label, // NEU
                  border: const OutlineInputBorder(),
                  helperText: t.password_requirements,
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
              child: Text(t.cancel),
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
              label: Text(t.save ?? 'Speichern'),
            ),
          ],
        ),
      ),
    );

    aCtrl.dispose();
    bCtrl.dispose();

    if (ok == true) {
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
    final t = ctx.t;
    final a = aCtrl.text;
    final b = bCtrl.text;
    if (a.isEmpty || b.isEmpty) {
      setS(() => setLocErr(t.password_both_required)); // NEU
      return;
    }
    if (a != b) {
      setS(() => setLocErr(t.passwordsDontMatch ?? 'Passwörter stimmen nicht überein.'));
      return;
    }
    if (a.length < 8) {
      setS(() => setLocErr(t.password_min_length)); // NEU
      return;
    }

    setS(() { markSaving(); setLocErr(null); });
    try {
      await widget.api.repChangePassword(a);
      if (ctx.mounted) Navigator.pop(ctx, true);
    } catch (e) {
      setS(() => setLocErr(t.password_set_failed('$e'))); // NEU (parametrisiert)
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
    final t = context.t;
    final canLogin = !_busy && _email.text.trim().isNotEmpty && _pw.text.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(t.rep_login_title)), // NEU
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ---- Login-Formular ----
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    decoration: InputDecoration(
                      labelText: t.email,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: _pw,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: t.password,
                      border: const OutlineInputBorder(),
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
                      label: Text(t.login), // NEU
                    ),
                  ),

                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(t.or), // NEU
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ---- Registrierung via temporärem Passwort ----
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _openSecretDialog,
                      icon: const Icon(Icons.key),
                      label: Text(t.i_have_temp_password), // NEU
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: LegalFooter(api: widget.api),
    );
  }
}
