import 'dart:html' as html; // für Datenschutz-Link
import 'package:flutter/material.dart';

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
  // --- Gate ---
  final _gateCtrl = TextEditingController();
  bool _gateBusy = false;
  String? _gateErr;

  // --- Form ---
  final _email = TextEditingController();
  final _pw1 = TextEditingController();
  final _pw2 = TextEditingController();
  final _company = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController();
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
    // Default: Deutschland, falls vorhanden
    _countrySel = kCountries.firstWhere(
      (c) => c.code == 'DE',
      orElse: () => kCountries.first,
    );
  }

  @override
  void dispose() {
    _gateCtrl.dispose();
    _email.dispose();
    _pw1.dispose();
    _pw2.dispose();
    _company.dispose();
    _first.dispose();
    _last.dispose();
    _street.dispose();
    _zip.dispose();
    _city.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _unlockGate() async {
    setState(() {
      _gateBusy = true;
      _gateErr = null;
    });
    final ok = await widget.api.gateUnlock(_gateCtrl.text.trim());
    if (!mounted) return;
    setState(() {
      _gateBusy = false;
      _gateErr = ok ? null : 'Falsches Passwort oder Serverfehler.';
    });
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

  Future<void> _submit() async {
    final t = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _err = null;
      _info = null;
    });

    try {
      if (!_privacy) {
        setState(() => _err = t.privacy_required);
        return;
      }
      if (_pw1.text != _pw2.text) {
        setState(() => _err = t.password_mismatch);
        return;
      }
      if (_first.text.trim().isEmpty || _last.text.trim().isEmpty) {
        setState(() => _err = t.name_required);
        return;
      }

      final country = _countrySel ?? kCountries.first;
      final payload = <String, dynamic>{
        'email': _email.text.trim(),
        'password': _pw1.text,
        'password2': _pw2.text,
        'company': _company.text.trim(),
        'firstName': _first.text.trim(),
        'lastName': _last.text.trim(),
        'salutation': _salutation.name, // "mr" | "ms" | "diverse"
        'contact': '${_first.text.trim()} ${_last.text.trim()}'.trim(),
        'street': _street.text.trim(),
        'zip': _zip.text.trim(),
        'city': _city.text.trim(),
        'country': country.label(context),
        'countryCode': country.code,
        'phone': _phone.text.trim(),
        'privacy': true,
        'lang': _langCode(context),
      };

      // ApiClient.register gibt String? (null = Erfolg)
      final err = await widget.api.register(payload);

      if (err == null) {
        setState(() {
          _info = t.registration_received; // „Vielen Dank! …”
        });
        // Optional: automatisch zum Login zurück
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) Navigator.of(context).pop(); // zurück zur Login-Seite
        return;
      }

      // Fehlertext heuristisch auswerten
      final e = err.toLowerCase();
      if (e.contains('user_exists') || e.contains('409')) {
        setState(() => _err = t.email_exists);
      } else if (e.contains('pending') || e.contains('resent')) {
        setState(() => _err = t.register_pending_resent);
      } else {
        setState(() => _err = t.register_failed(err));
      }
    } catch (ex) {
      setState(() => _err = 'Network/CORS error: $ex');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final hasGate = (widget.api.gate ?? '').isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.auth_register),
        actions: const [LangAction()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                if (!hasGate) ...[
                  Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Registrierungszugang',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _gateCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Einmal-Passwort (AUTH_PASSWORD)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _gateBusy ? null : _unlockGate,
                            icon: _gateBusy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.lock_open),
                            label: const Text('Zugang freischalten'),
                          ),
                          if (_gateErr != null) ...[
                            const SizedBox(height: 8),
                            Text(_gateErr!, style: const TextStyle(color: Colors.red)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Hinweis: Das Einmal-Passwort wird nur einmal benötigt. Danach bleibt der Zugang freigeschaltet.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],

                if (hasGate) ...[
                  // ---- Formular ----
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(labelText: t.email, border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _pw1,
                    obscureText: true,
                    decoration: InputDecoration(labelText: t.password, border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _pw2,
                    obscureText: true,
                    decoration: InputDecoration(labelText: t.password_repeat, border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _company,
                    decoration: InputDecoration(labelText: t.company, border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),

                  Text(t.contact_person, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),

                  DropdownButtonFormField<Salutation>(
                    value: _salutation,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: t.salutation, border: const OutlineInputBorder()),
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
                          controller: _first,
                          decoration: InputDecoration(labelText: t.first_name, border: const OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _last,
                          decoration: InputDecoration(labelText: t.last_name, border: const OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  TextField(
                    controller: _street,
                    decoration: InputDecoration(labelText: t.street, border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _zip,
                          decoration: InputDecoration(labelText: t.zip, border: const OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _city,
                          decoration: InputDecoration(labelText: t.city, border: const OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  DropdownButtonFormField<Country>(
                    value: _countrySel,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: t.country, border: const OutlineInputBorder()),
                    items: kCountries
                        .map((c) => DropdownMenuItem<Country>(value: c, child: Text(c.label(context))))
                        .toList(),
                    onChanged: (val) => setState(() => _countrySel = val),
                  ),
                  const SizedBox(height: 8),

                  TextField(
                    controller: _phone,
                    decoration: InputDecoration(labelText: t.phone, border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Checkbox(value: _privacy, onChanged: (v) => setState(() => _privacy = v ?? false)),
                      Expanded(child: Text(t.privacy_agree)),
                      TextButton(
                        onPressed: () => html.window.open('https://www.dfs-diamon.de/datenschutz', '_blank'),
                        child: Text(t.privacy_link),
                      ),
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
                      OutlinedButton(
                        onPressed: _busy ? null : () => Navigator.of(context).pop(),
                        child: Text(t.back),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
