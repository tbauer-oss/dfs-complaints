// lib/pages/rep_login_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import 'rep_dashboard_page.dart';

enum _RepStep { email, otp, setPassword }

class RepLoginPage extends StatefulWidget {
  final ApiClient api;
  const RepLoginPage({super.key, required this.api});

  @override
  State<RepLoginPage> createState() => _RepLoginPageState();
}

class _RepLoginPageState extends State<RepLoginPage> {
  final _email = TextEditingController();
  final _otp   = TextEditingController(); // Einmalpasswort = REP_JWT_SECRET
  final _new1  = TextEditingController();
  final _new2  = TextEditingController();

  _RepStep _step = _RepStep.email;
  bool _busy = false;
  String? _err;

  // Hilfen
  void _setErr(String? msg) => setState(() => _err = msg);
  void _setBusy(bool b) => setState(() => _busy = b);

  // Schritt 1: E-Mail prüfen (existiert & aktiv?)
  Future<void> _checkEmail() async {
    _setErr(null);
    final email = _email.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      _setErr('Bitte eine gültige E-Mail-Adresse eingeben.');
      return;
    }
    _setBusy(true);
    try {
      final exists = await widget.api.repExists(email);
      if (!exists) {
        _setErr('Diese E-Mail ist nicht als Vertreter hinterlegt oder nicht aktiv.');
        return;
      }
      setState(() => _step = _RepStep.otp);
    } catch (e) {
      _setErr('Serverfehler beim Prüfen der E-Mail: $e');
    } finally {
      _setBusy(false);
    }
  }

  // Schritt 2: Einmalpasswort prüfen (REP_JWT_SECRET)
  // Backend gibt { token, mustChangePw: true|false } zurück.
  Future<void> _submitOtp() async {
    _setErr(null);
    final email = _email.text.trim().toLowerCase();
    final otp   = _otp.text; // hier erwartest du REP_JWT_SECRET
    if (otp.isEmpty) {
      _setErr('Bitte das Einmalpasswort eingeben.');
      return;
    }

    _setBusy(true);
    try {
      final res = await widget.api.repLogin(email, otp);
      if (!res.ok) {
        _setErr('Einmalpasswort falsch oder nicht zulässig.');
        return;
      }
      if (res.mustChange) {
        // Direkt in Schritt 3 (neues Passwort setzen)
        setState(() => _step = _RepStep.setPassword);
        return;
      }
      // Falls mustChange=false, ist bereits ein eigenes Passwort gesetzt:
      // -> Direkt ins Dashboard
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RepDashboardPage(api: widget.api)),
      );
    } catch (e) {
      _setErr('Login fehlgeschlagen: $e');
    } finally {
      _setBusy(false);
    }
  }

  // Schritt 3: Neues Passwort setzen (mit Wiederholung)
  Future<void> _setNewPassword() async {
    _setErr(null);
    final a = _new1.text;
    final b = _new2.text;

    if (a.isEmpty || b.isEmpty) {
      _setErr('Bitte neues Passwort in beiden Feldern eingeben.');
      return;
    }
    if (a != b) {
      _setErr('Passwörter stimmen nicht überein.');
      return;
    }
    if (a.length < 8) {
      _setErr('Das Passwort muss mindestens 8 Zeichen lang sein.');
      return;
    }

    _setBusy(true);
    try {
      await widget.api.repChangePassword(a);
      // Danach ist das Passwort gesetzt. Jetzt direkt ins Dashboard.
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RepDashboardPage(api: widget.api)),
      );
    } catch (e) {
      _setErr('Passwort setzen fehlgeschlagen: $e');
    } finally {
      _setBusy(false);
    }
  }

  // UI-Bausteine

  Widget _emailStep() {
    final canNext = !_busy && _email.text.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Vertreter-Login',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.username, AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'E-Mail',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => canNext ? _checkEmail() : null,
        ),
        const SizedBox(height: 16),
        if (_err != null)
          Text(_err!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: canNext ? _checkEmail : null,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.arrow_forward),
            label: const Text('Weiter'),
          ),
        ),
      ],
    );
  }

  Widget _otpStep() {
    final canNext = !_busy && _otp.text.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Einmalpasswort eingeben',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _otp,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Einmalpasswort (zugesendet/vereinbart)',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: 'Zurück zur E-Mail',
              onPressed: _busy ? null : () => setState(() => _step = _RepStep.email),
              icon: const Icon(Icons.edit),
            ),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => canNext ? _submitOtp() : null,
        ),
        const SizedBox(height: 16),
        if (_err != null)
          Text(_err!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: canNext ? _submitOtp : null,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.login),
            label: const Text('Anmelden'),
          ),
        ),
      ],
    );
  }

  Widget _setPwStep() {
    final canSave = !_busy && _new1.text.isNotEmpty && _new2.text.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Neues Passwort festlegen',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _new1,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Neues Passwort',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _new2,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Neues Passwort (Wiederholung)',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => canSave ? _setNewPassword() : null,
        ),
        const SizedBox(height: 16),
        if (_err != null)
          Text(_err!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => setState(() => _step = _RepStep.otp),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Zurück'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: canSave ? _setNewPassword : null,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: const Text('Speichern'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final child = switch (_step) {
      _RepStep.email       => _emailStep(),
      _RepStep.otp         => _otpStep(),
      _RepStep.setPassword => _setPwStep(),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Vertreter-Login')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AutofillGroup(child: child),
          ),
        ),
      ),
    );
  }
}