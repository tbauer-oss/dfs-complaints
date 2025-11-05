// lib/pages/register_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../models/country.dart';
import '../widgets/lang_action.dart';

enum Salutation { mr, ms, diverse }

extension _L10nX on BuildContext {
  AppLocalizations get t => AppLocalizations.of(this)!;
}

class RegisterPage extends StatefulWidget {
  final ApiClient api;
  const RegisterPage({super.key, required this.api});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // Gate (AUTH_PASSWORD) – vor Betreten der Registrierung
  final _gatePw = TextEditingController();
  final t = context.t;
  bool _gateBusy = false;
  String? _gateErr;

  // Formular
  final _email = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  final _company = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _street = TextEditingController();
  final _zip = TextEditingController();
  final _city = TextEditingController();
  final _phone = TextEditingController();

  Country? _countrySel;
  Salutation _salutation = Salutation.mr;
  bool _privacy = false;

  bool _busy = false;
  String? _err;
  String? _info;

  @override
  void initState() {
    super.initState();
    _countrySel = kCountries.firstWhere(
      (c) => c.code == 'DE',
      orElse: () => kCountries.first,
    );
  }

  @override
  void dispose() {
    _gatePw.dispose();
    _email.dispose();
    _pw.dispose();
    _pw2.dispose();
    _company.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _street.dispose();
    _zip.dispose();
    _city.dispose();
    _phone.dispose();
    super.dispose();
  }

  String _langCode(BuildContext ctx) {
    final lc = Localizations.localeOf(ctx).languageCode.toLowerCase();
    switch (lc) {
      case 'de':
      case 'en':
      case 'fr':
      case 'it':
      case 'es':
        return lc;
      default:
        return 'de';
    }
  }

  String _salutationLabel(AppLocalizations t, Salutation s) {
    switch (s) {
      case Salutation.mr:
        return t.salutation_mr;
      case Salutation.ms:
        return t.salutation_ms;
      case Salutation.diverse:
        return t.salutation_diverse;
    }
  }

  Future<void> _unlockGate() async {
    setState(() {
      _gateBusy = true;
      _gateErr = null;
    });
    try {
      final ok = await widget.api.gateUnlock(_gatePw.text);
      if (!mounted) return;
      if (!ok) {
        setState(() => _gateErr = t.wrongPassword);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _gateErr = '${t.network_cors_error}: $e');
    } finally {
      if (mounted) setState(() => _gateBusy = false);
    }
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _err = null;
      _info = null;
    });

    try {
      if (_pw.text != _pw2.text) {
        // Fallback-Text (kein L10n-Key nötig)
        setState(() => _err = t.password_mismatch);
        return;
      }
      if (!_privacy) {
        setState(() => _err = t.privacy_required);
        return;
      }
      if (_firstName.text.trim().isEmpty || _lastName.text.trim().isEmpty) {
        setState(() => _err = t.name_required);
        return;
      }

      final sel = _countrySel ?? kCountries.first;

      final payload = <String, dynamic>{
        'email': _email.text.trim(),
        'password': _pw.text,
        'password2': _pw2.text,
        'company': _company.text.trim(),
        'firstName': _firstName.text.trim(),
        'lastName': _lastName.text.trim(),
        'salutation': _salutation.name, // "mr" | "ms" | "diverse"
        'contact': '${_firstName.text.trim()} ${_lastName.text.trim()}'.trim(),
        'street': _street.text.trim(),
        'zip': _zip.text.trim(),
        'city': _city.text.trim(),
        'country': sel.label(context),
        'countryCode': sel.code,
        'phone': _phone.text.trim(),
        'privacy': true,
        'lang': _langCode(context),
      };

      // ApiClient.register -> Future<String?> (null = OK, sonst Fehlertext)
      final String? errMsg = await widget.api.register(payload);
      final t = context.t;
      if (!mounted) return;

      if (errMsg == null) {
        setState(() => _info = t.registration_received);
        return;
      }

      // Fehlertext heuristisch auswerten
      final em = errMsg.toLowerCase();
      final t = context.t;
      if (em.contains('user_exists') || em.contains('409')) {
        setState(() => _err = t.email_exists);
      } else if (em.contains('pending') || em.contains('resent')) {
        setState(() => _err = t.register_pending_resent);
      } else {
        setState(() => _err = t.register_failed(errMsg));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '${t.network_cors_error}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    // Gate-Abfrage VOR dem Formular
    final needsGate = widget.api.gate == null || widget.api.gate!.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(needsGate ? t.regFree : t.auth_register),
        actions: const [LangAction()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (needsGate) ...[
                Text(
                  t.gateUnlockHint,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _gatePw,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Freigabe-Passwort',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _gateBusy ? null : _unlockGate(),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _gateBusy ? null : _unlockGate,
                  child: _gateBusy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(t.unlock),
                ),
                if (_gateErr != null) ...[
                  const SizedBox(height: 8),
                  Text(_gateErr!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(t.back),
                ),
              ] else ...[
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
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _pw2,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: t.password_repeat,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _company,
                  decoration: InputDecoration(
                    labelText: t.company,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    t.contact_person,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),

                DropdownButtonFormField<Salutation>(
                  value: _salutation,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: t.salutation,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(value: Salutation.mr, child: Text(_salutationLabel(t, Salutation.mr))),
                    DropdownMenuItem(value: Salutation.ms, child: Text(_salutationLabel(t, Salutation.ms))),
                    DropdownMenuItem(value: Salutation.diverse, child: Text(_salutationLabel(t, Salutation.diverse))),
                  ],
                  onChanged: (v) => setState(() => _salutation = v ?? Salutation.mr),
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _firstName,
                        decoration: InputDecoration(
                          labelText: t.first_name,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _lastName,
                        decoration: InputDecoration(
                          labelText: t.last_name,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _street,
                  decoration: InputDecoration(
                    labelText: t.street,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _zip,
                        decoration: InputDecoration(
                          labelText: t.zip,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _city,
                        decoration: InputDecoration(
                          labelText: t.city,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                DropdownButtonFormField<Country>(
                  value: _countrySel,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: t.country,
                    border: const OutlineInputBorder(),
                  ),
                  items: kCountries
                      .map((c) => DropdownMenuItem<Country>(value: c, child: Text(c.label(context))))
                      .toList(),
                  onChanged: (val) => setState(() => _countrySel = val),
                ),
                const SizedBox(height: 8),

                TextField(
                  controller: _phone,
                  decoration: InputDecoration(
                    labelText: t.phone,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Checkbox(
                      value: _privacy,
                      onChanged: (v) => setState(() => _privacy = v ?? false),
                    ),
                    Expanded(child: Text(t.privacy_agree)),
                  ],
                ),

                if (_err != null) ...[
                  const SizedBox(height: 8),
                  Text(_err!, style: const TextStyle(color: Colors.red)),
                ],
                if (_info != null) ...[
                  const SizedBox(height: 8),
                  Text(_info!, style: const TextStyle(color: Colors.green)),
                ],

                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(t.auth_register),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Text(t.back),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
