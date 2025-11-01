// lib/pages/register_page.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../models/country.dart';
import '../widgets/lang_action.dart';

enum Salutation { mr, ms, diverse }

class RegisterPage extends StatefulWidget {
  final ApiClient api;
  const RegisterPage({super.key, required this.api});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // Gate
  final _gatePw = TextEditingController();
  bool _gateBusy = false;
  String? _gateErr;

  // Form
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
        setState(() => _gateErr = 'Falsches Passwort.');
      } else {
        setState(() => _gateErr = null);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _gateErr = 'Netzwerk/CORS-Fehler: $e');
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
        // Fallback-Text, da t.password_mismatch nicht existiert
        setState(() => _err = 'Passwörter stimmen nicht überein.');
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

      final selected = _countrySel ?? kCountries.first;
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
        'country': selected.label(context),
        'countryCode': selected.code,
        'phone': _phone.text.trim(),
        'privacy': true,
        'lang': _langCode(context),
      };

      final http.Response? r = await widget.api.register(payload);
      if (!mounted) return;

      if (r == null) {
        setState(() => _err = t.register_failed('no response'));
        return;
      }

      if (r.statusCode == 200 || r.statusCode == 201) {
        setState(() {
          _info = t.registration_received;
        });
        return;
      }

      // Fehlerauswertung
      final body = r.body;
      if (body.contains('user_exists') || r.statusCode == 409) {
        setState(() => _err = t.email_exists);
      } else if (body.contains('pending') || body.contains('resent')) {
        setState(() => _err = t.register_pending_resent);
      } else {
        setState(() => _err = t.register_failed(body.isNotEmpty ? body : '${r.statusCode}'));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = 'Network/CORS error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    // 1) Gate-Abfrage VOR dem Formular (einmalig)
    final needsGate = widget.api.gate == null || widget.api.gate!.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(needsGate ? 'Registrierung freischalten' : t.auth_register),
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
                  'Bitte geben Sie das Freigabe-Passwort ein, um den Registrierungsbereich zu öffnen.',
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
                      : const Text('Entsperren'),
                ),
                if (_gateErr != null) ...[
                  const SizedBox(height: 8),
                  Text(_gateErr!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  // Fallback statt t.back
                  child: const Text('Zurück'),
                ),
              ] else ...[
                // 2) Registrierungsformular
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
                      // Fallback statt t.back
                      child: const Text('Zurück'),
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
