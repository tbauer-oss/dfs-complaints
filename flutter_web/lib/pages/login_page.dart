// lib/pages/login_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';

class LoginPage extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onLoggedIn;
  final VoidCallback onOpenRegister;
  final VoidCallback onOpenAdmin;
  final VoidCallback onOpenRep;

  const LoginPage({
    super.key,
    required this.api,
    required this.onLoggedIn,
    required this.onOpenRegister,
    required this.onOpenAdmin,
    required this.onOpenRep,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;
  bool _repCheckBusy = true;
  String? _err;

  final Color dfsBlue = const Color(0xFF005A9C); // DFS-Blau

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoOpenRepIfValid());
  }

  Future<void> _autoOpenRepIfValid() async {
    setState(() => _repCheckBusy = true);
    try {
      await widget.api.restoreSession();
      final tok = widget.api.repToken;
      if (tok != null && tok.isNotEmpty) {
        try {
          await widget.api.repMe();
          if (!mounted) return;
          widget.onOpenRep();
          return;
        } catch (_) {
          await widget.api.repLogout();
        }
      }
    } finally {
      if (mounted) setState(() => _repCheckBusy = false);
    }
  }

  Future<void> _doLogin() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final ok = await widget.api.login(_email.text.trim(), _pw.text);
      if (ok) {
        widget.onLoggedIn();
      } else {
        setState(() => _err =
            AppLocalizations.of(context)?.loginFailed ?? 'Login fehlgeschlagen.');
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
    final repLoggedIn = (widget.api.repToken ?? '').isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [dfsBlue.withOpacity(0.95), dfsBlue.withOpacity(0.75)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            elevation: 12,
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo / Titel
                  Column(
                    children: [
                      const Icon(Icons.medical_services_rounded,
                          color: Color(0xFF005A9C), size: 64),
                      const SizedBox(height: 8),
                      Text(
                        'DFS-Customer Complaint',
                        style: TextStyle(
                          color: dfsBlue,
                          fontWeight: FontWeight.w700,
                          fontSize: 22,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Loginbereich',
                        style: TextStyle(
                            color: Colors.black54,
                            fontSize: 14,
                            fontWeight: FontWeight.w400),
                      ),
                      const Divider(height: 28, thickness: 1),
                    ],
                  ),

                  // Admin- & Vertreterzugang
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed:
                            _busy ? null : widget.onOpenAdmin,
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        label: const Text('Admin'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: dfsBlue,
                          side: BorderSide(color: dfsBlue.withOpacity(0.5)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed:
                            (_busy || _repCheckBusy) ? null : widget.onOpenRep,
                        icon: const Icon(Icons.handshake_outlined),
                        label: Text(repLoggedIn
                            ? 'Vertreter (aktiv)'
                            : 'Vertreter'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: dfsBlue,
                          side: BorderSide(color: dfsBlue.withOpacity(0.5)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Eingabefelder
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: t?.email ?? 'E-Mail*',
                      prefixIcon:
                          const Icon(Icons.email_outlined, color: Colors.grey),
                      border: const OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(
                        borderSide:
                            BorderSide(color: dfsBlue.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    enabled: !_busy && !_repCheckBusy,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _pw,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: t?.password ?? 'Passwort*',
                      prefixIcon:
                          const Icon(Icons.lock_outline, color: Colors.grey),
                      border: const OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(
                        borderSide:
                            BorderSide(color: dfsBlue.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    enabled: !_busy && !_repCheckBusy,
                  ),
                  const SizedBox(height: 18),

                  // Login-Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: dfsBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 4,
                      ),
                      onPressed: (_busy || _repCheckBusy) ? null : _doLogin,
                      child: (_busy || _repCheckBusy)
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'Login',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 16),
                            ),
                    ),
                  ),

                  if (_err != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _err!,
                      style:
                          const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ],

                  const SizedBox(height: 22),

                  // Registrieren
                  TextButton.icon(
                    icon: const Icon(Icons.person_add_alt, color: Colors.black54),
                    label: Text(
                      t?.register ?? 'Registrieren',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    onPressed:
                        (_busy || _repCheckBusy) ? null : widget.onOpenRegister,
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
