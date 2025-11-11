// lib/pages/login_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import 'rep_dashboard_page.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dfs_mobile/web_compat/html_stub.dart'
  if (dart.library.html) 'package:dfs_mobile/web_compat/html_web.dart' as html;

/// Kleiner Helper, damit du überall bequem auf t zugreifen kannst
extension _L10nX on BuildContext {
  AppLocalizations get t => AppLocalizations.of(this)!;
}

class InstallPwaButton extends StatefulWidget {
  const InstallPwaButton({super.key});
  @override
  State<InstallPwaButton> createState() => _InstallPwaButtonState();
}

class _InstallPwaButtonState extends State<InstallPwaButton> {
  bool _canInstall = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;

    try {
      _canInstall = (html.window as dynamic).__pwaCanInstall == true;
    } catch (_) {
      _canInstall = false;
    }

    html.window.addEventListener('pwa-can-install', (_) {
      if (mounted) setState(() => _canInstall = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !_canInstall) return const SizedBox.shrink();
    return ElevatedButton.icon(
      icon: const Icon(Icons.download),
      label: const Flexible(
        child: Text(
          'App installieren',
          textAlign: TextAlign.center,
        ),
      ),
      onPressed: () async {
        if (!kIsWeb) return;

        final accepted = await (html.window as dynamic).showInstallPrompt() as bool? ?? false;
        if (!accepted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Installation abgebrochen.')));
        }
      },
    );
  }
}

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

  final _emailFocus = FocusNode();
  final _pwFocus    = FocusNode();

  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    _new1.dispose();
    _new2.dispose();
    _emailFocus.dispose();
    _pwFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final t = context.t;
    setState(() { _busy = true; _err = null; });
    try {
      final ok = await widget.api.login(_email.text.trim(), _pw.text);
      if (!ok) {
        setState(() => _err = t.login_failed);
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RepDashboardPage(api: widget.api)),
      );
    } catch (e) {
      // falls t.network_error_generic ein Formatter ist – ansonsten einfach '$e'
      setState(() => _err = t.network_error_generic('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final t = context.t;
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
            localErr = t.new_password_both_required;
            (ctx as Element).markNeedsBuild();
            return;
          }
          if (a != b) {
            localErr = t.passwords_no_match;
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
              SnackBar(content: Text(t.password_changed)),
            );
          } catch (e) {
            localErr = 'Error: $e';
            saving = false;
            (ctx as Element).markNeedsBuild();
          }
        }

        return AlertDialog(
          title: Text(t.new_password_title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _new1,
                  obscureText: true,
                  decoration: InputDecoration(labelText: t.new_password),
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => (ctx as Element).markNeedsBuild(),
                ),
                TextField(
                  controller: _new2,
                  obscureText: true,
                  decoration: InputDecoration(labelText: t.new_password_repeat),
                  onSubmitted: (_) => save(),
                ),
                if (localErr != null) ...[
                  const SizedBox(height: 8),
                  Text(localErr!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(ctx).pop(),
              child: Text(t.cancel),
            ),
            ElevatedButton(
              onPressed: saving ? null : save,
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t.save),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final canLogin = !_busy && _email.text.trim().isNotEmpty && _pw.text.isNotEmpty;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        // wichtig für mobiles Scrollen mit Keyboard
        resizeToAvoidBottomInset: true,
        appBar: AppBar(title: Text(t.rep_login_title)),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              // Scroll-Wrapper für kleine Displays
              return Scrollbar(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 16,
                    // Platz für die Tastatur auf Mobilgeräten
                    bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _email,
                              focusNode: _emailFocus,
                              autofillHints: const [AutofillHints.username, AutofillHints.email],
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(labelText: 'E-Mail'),
                              textInputAction: TextInputAction.next,
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) => _pwFocus.requestFocus(),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _pw,
                              focusNode: _pwFocus,
                              obscureText: true,
                              autofillHints: const [AutofillHints.password],
                              decoration: const InputDecoration(labelText: 'Password'),
                              textInputAction: TextInputAction.done,
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) => canLogin ? _login() : null,
                            ),
                            const SizedBox(height: 16),
                            if (_err != null)
                              Text(_err!, style: const TextStyle(color: Colors.red)),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              icon: _busy
                                  ? const SizedBox(
                                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.login),
                              label: Text(t.login_action ?? 'Anmelden'),
                              onPressed: canLogin ? _login : null,
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _busy ? null : _showChangePasswordDialog,
                              icon: const Icon(Icons.lock_reset),
                              label: Text(t.changePassword),
                            ),
                            // Falls du hier absichtlich erneut auf die Login-Seite wolltest, lassen wir das.
                            // Andernfalls könntest du das entfernen oder auf eine Info-Seite verlinken.
                            TextButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.of(context).push(
                                        MaterialPageRoute(builder: (_) => RepLoginPage(api: widget.api)),
                                      ),
                              icon: const Icon(Icons.badge_outlined),
                              label: Text(t.rep_area),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
