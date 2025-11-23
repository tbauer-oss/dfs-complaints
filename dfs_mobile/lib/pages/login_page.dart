// lib/pages/login_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import 'rep_dashboard_page.dart';
import '../l10n/app_localizations.dart';
import 'reset_password_page.dart';
import '../services/push_notifications.dart';
import 'dashboard_page.dart';
import '../widgets/password_field.dart';
import '../services/biometric_auth.dart';

// **KEIN direkter dart:html-Import mehr**
import 'package:dfs_mobile/web_compat/html_stub.dart'
  if (dart.library.html) 'package:dfs_mobile/web_compat/html_web.dart' as html;

/// Kleiner Helper, damit du überall bequem auf t zugreifen kannst
extension _L10nX on BuildContext {
  AppLocalizations get t => AppLocalizations.of(this)!;
}

/// Dezente, CI-konforme PWA-Install-Schaltfläche (erscheint nur im Web)
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
    try {
      _canInstall = (html.window as dynamic).__pwaCanInstall == true;
      html.window.addEventListener('pwa-can-install', (_) {
        if (mounted) setState(() => _canInstall = true);
      });
    } catch (_) {
      // Nicht-Web: ignorieren
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canInstall) return const SizedBox.shrink();
    return OutlinedButton.icon(
      icon: const Icon(Icons.download),
      label: Text(
        'App installieren',
        textAlign: TextAlign.center,
      ),
      onPressed: () async {
        bool accepted = false;
        try {
          accepted = await (html.window as dynamic).showInstallPrompt() as bool? ?? false;
        } catch (_) {}
        if (!accepted && context.mounted) {
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
  bool _biometricAvailable = false;
  bool _hasBiometricCredentials = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
  }

  Future<void> _loadBiometricState() async {
    final bio = BiometricAuthService.instance;
    final available = await bio.isAvailable();
    final hasCreds = available && await bio.hasCredentials(BiometricProfile.customer);
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _hasBiometricCredentials = hasCreds;
    });
  }

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

  Future<void> _login({
    String? email,
    String? password,
    bool offerBiometricOptIn = true,
    bool showPushOptIn = true,
  }) async {
    final t = context.t;
    setState(() { _busy = true; _err = null; });

    final loginEmail = (email ?? _email.text).trim();
    final loginPw = password ?? _pw.text;

    try {
      final result = await widget.api.login(loginEmail, loginPw);
      if (!result.ok) {
        final err = result.revoked
            ? t.account_blocked
            : (result.statusCode == 401
                ? t.login_failed_check_credentials
                : (result.message?.isNotEmpty == true
                    ? result.message!
                    : t.login_failed));
        setState(() => _err = err);
        return;
      }

      if (!mounted) return;

      var wantsPush = false;
      final locale = Localizations.localeOf(context);

      if (showPushOptIn) {
        wantsPush = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Push-Benachrichtigungen aktivieren?'),
                content: const Text(
                  'Möchten Sie Push-Benachrichtigungen erhalten, wenn sich der '
                  'Status Ihrer Reklamationen ändert?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Nein, danke'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Ja, aktivieren'),
                  ),
                ],
              ),
            ) ??
            false;
      }

      if (wantsPush) {
        try {
          await PushNotifications.instance.setup(
            widget.api,
            languageCode: locale.languageCode,
          );
        } catch (e) {
          debugPrint('[push] customer setup failed: $e');
        }
      } else if (!showPushOptIn) {
        try {
          await PushNotifications.instance.replayLatestToken(
            widget.api,
            languageCode: locale.languageCode,
          );
        } catch (e) {
          debugPrint('[push] customer token replay failed: $e');
        }
      } else {
        try {
          await PushNotifications.instance.deactivate(widget.api);
        } catch (e) {
          debugPrint('[push] customer deactivate failed: $e');
        }
      }

      if (offerBiometricOptIn) {
        await _offerBiometricOptIn(loginEmail, loginPw);
        if (!mounted) return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => DashboardPage(api: widget.api)),
      );
    } catch (e) {
      setState(() => _err = '${t.network_error_generic} $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _offerBiometricOptIn(String email, String password) async {
    final bio = BiometricAuthService.instance;
    if (_hasBiometricCredentials) return;
    if (!await bio.isAvailable()) return;

    final t = context.t;
    final enable = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.biometric_opt_in_title),
        content: Text(t.biometric_opt_in_body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.biometric_opt_in_no),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.biometric_opt_in_yes),
          ),
        ],
      ),
    );

    if (enable != true || !mounted) return;

    final saved = await bio.saveCredentials(BiometricProfile.customer, email, password);
    if (!mounted) return;
    if (saved) {
      setState(() => _hasBiometricCredentials = true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.biometric_setup_success)));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.biometric_not_available)));
    }
  }

  Future<void> _loginWithBiometrics() async {
    final t = context.t;
    setState(() => _err = null);

    final bio = BiometricAuthService.instance;
    final creds = await bio.readCredentials(BiometricProfile.customer);
    if (creds == null) {
      setState(() => _err = t.biometric_not_available);
      await _loadBiometricState();
      return;
    }

    final ok = await bio.authenticate(t.biometric_auth_reason);
    if (!ok) {
      setState(() => _err = t.biometric_auth_failed);
      return;
    }

    await _login(
      email: creds.$1,
      password: creds.$2,
      offerBiometricOptIn: false,
      showPushOptIn: false,
    );
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
            localErr = t.passwordsDontMatch;
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
                PasswordField(
                  controller: _new1,
                  decoration: InputDecoration(
                    labelText: t.newPassword,
                    helperText: t.password_requirements,
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => (ctx as Element).markNeedsBuild(),
                ),
                const SizedBox(height: 8),
                PasswordField(
                  controller: _new2,
                  decoration: InputDecoration(
                    labelText: t.newPasswordRepeat,
                    helperText: t.password_requirements,
                    prefixIcon: const Icon(Icons.lock_reset),
                  ),
                  onSubmitted: (_) => save(),
                ),
                if (localErr != null) ...[
                  const SizedBox(height: 12),
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
            FilledButton(
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

  InputDecoration _decoration(BuildContext context, {required String label, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon != null ? Icon(icon) : null,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.6),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 1.6,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final canLogin = !_busy && _email.text.trim().isNotEmpty && _pw.text.isNotEmpty;

    // Dezenter Hintergrund mit Brand-Verlauf
    final bg = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1F4C8F), // DFS-Blau (Seed)
            Theme.of(context).colorScheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );

    // Linke Brand-Spalte (nur großflächig am Web/Desktop sichtbar)
    Widget brandPane() {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Platzhalter für Logo – falls du ein Asset hast, einfach ersetzen
            Icon(Icons.health_and_safety, size: 48, color: Colors.white.withOpacity(0.95)),
            const SizedBox(height: 16),
            Text(
              'DFS Complaints',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Sicher. Verlässlich. MDR-konform.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(Icons.verified_user, color: Colors.white70),
                const SizedBox(width: 8),
                Text('ISO 13485 • MDR', style: TextStyle(color: Colors.white.withOpacity(0.85))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.medical_services_outlined, color: Colors.white70),
                const SizedBox(width: 8),
                Text('Dental Medical Devices', style: TextStyle(color: Colors.white.withOpacity(0.85))),
              ],
            ),
            const Spacer(),
            const InstallPwaButton(),
          ],
        ),
      );
    }

    // Rechte Login-Card
    Widget formCard() {
      return Card(
        elevation: 8,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Titelzeile
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(Icons.badge, color: Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t.rep_login_title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                TextField(
                  controller: _email,
                  focusNode: _emailFocus,
                  autofillHints: const [AutofillHints.username, AutofillHints.email],
                  keyboardType: TextInputType.emailAddress,
                  decoration: _decoration(context, label: 'E-Mail', icon: Icons.mail_outline),
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _pwFocus.requestFocus(),
                ),
                const SizedBox(height: 12),
                PasswordField(
                  controller: _pw,
                  focusNode: _pwFocus,
                  autofillHints: const [AutofillHints.password],
                  decoration: _decoration(context, label: 'Password', icon: Icons.lock_outline),
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => canLogin ? _login() : null,
                ),

                if (_biometricAvailable && _hasBiometricCredentials) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _loginWithBiometrics,
                      icon: const Icon(Icons.fingerprint),
                      label: Text(t.biometric_login_button),
                    ),
                  ),
                ],

                const SizedBox(height: 10),
                if (_err != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),

                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    icon: _busy
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.login),
                    label: Text(t.login),
                    onPressed: canLogin ? _login : null,
                  ),
                ),

                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).dividerColor.withOpacity(.4),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary.withOpacity(.85),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.forgot_password_button,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(.9),
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              t.forgot_password_instructions,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    height: 1.35,
                                    color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(.8),
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                              builder: (_) => ResetPasswordPage(api: widget.api)),
                                        ),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(_busy ? .4 : .9),
                                  textStyle: Theme.of(context).textTheme.labelLarge,
                                ),
                                child: Text(t.reset_password_request_action),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.lock_reset),
                        onPressed: _busy ? null : _showChangePasswordDialog,
                        label: Text(t.changePassword),
                      ),
                    ),
                  ],
                ),

                // Funktion NICHT verändert: dieser Button bleibt erhalten
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => RepLoginPage(api: widget.api)),
                          ),
                  icon: const Icon(Icons.badge_outlined),
                  label: Text(t.rep_area, textAlign: TextAlign.center),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            bg,
            // Inhalt
            SafeArea(
              child: LayoutBuilder(
                builder: (ctx, c) {
                  final isWide = c.maxWidth >= 980;
                  final pagePad = EdgeInsets.symmetric(
                    horizontal: isWide ? 48 : 16,
                    vertical: isWide ? 28 : 16,
                  );

                  return SingleChildScrollView(
                    padding: pagePad.copyWith(
                      bottom: (MediaQuery.of(context).viewInsets.bottom + 24),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1160),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          padding: isWide ? const EdgeInsets.all(20) : EdgeInsets.zero,
                          child: isWide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Linke Brand-Spalte
                                    Expanded(child: brandPane()),
                                    const SizedBox(width: 20),
                                    // Rechte Login-Card
                                    SizedBox(width: 480, child: formCard()),
                                  ],
                                )
                              : Column(
                                  children: [
                                    // Mobile: nur kompaktes Claim-Modul
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.10),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.health_and_safety, color: Colors.white.withOpacity(0.95)),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              'DFS Complaints • ISO 13485 • MDR',
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.95),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const InstallPwaButton(),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    formCard(),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
