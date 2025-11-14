import 'package:flutter/material.dart';
import 'dart:html' as html;
import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../models/country.dart';
import '../services/app_prefs_scope.dart';
import '../utils/lang_utils.dart';

enum Salutation { mr, ms, diverse }

class AuthPage extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onLoggedIn;
  const AuthPage({super.key, required this.api, required this.onLoggedIn});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool isLogin = true;

  final _email = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  final _company = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName  = TextEditingController();
  final _street = TextEditingController();
  final _zip = TextEditingController();
  final _city = TextEditingController();
  final _phone = TextEditingController();

  Country? _countrySel;
  Salutation _salutation = Salutation.mr;

  bool _privacy = false;
  String? _err;
  bool _busy = false;
  String _selectedLang = 'de';

  @override
  void initState() {
    super.initState();
    _countrySel = kCountries.firstWhere(
      (c) => c.code == 'DE',
      orElse: () => kCountries.first,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final prefs = AppPrefsScope.of(context);
    final locale = prefs.locale ?? Localizations.localeOf(context);
    final normalized = normalizeLangCode(locale.languageCode);
    if (_selectedLang != normalized) {
      _selectedLang = normalized;
    }
  }

  @override
  void dispose() {
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

  String _salutationLabel(BuildContext context, Salutation s) {
    final t = AppLocalizations.of(context)!;
    switch (s) {
      case Salutation.mr:     return t.salutation_mr;
      case Salutation.ms:     return t.salutation_ms;
      case Salutation.diverse:return t.salutation_diverse;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final prefs = AppPrefsScope.of(context);

    return Center(
      child: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ToggleButtons(
              isSelected: [isLogin, !isLogin],
              onPressed: (i) => setState(() => isLogin = (i == 0)),
              children: [
                Padding(padding: const EdgeInsets.all(8), child: Text(t.auth_login)),
                Padding(padding: const EdgeInsets.all(8), child: Text(t.auth_register)),
              ],
            ),
            const SizedBox(height: 16),

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

            if (!isLogin) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _pw2,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: t.password_repeat,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _company,
                decoration: InputDecoration(
                  labelText: t.company,
                  border: const OutlineInputBorder(),
                ),
              ),

              // ===== Ansprechpartner-Block =====
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  t.contact_person,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 8),

              // Anrede
              DropdownButtonFormField<Salutation>(
                value: _salutation,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t.salutation,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(value: Salutation.mr, child: Text(_salutationLabel(context, Salutation.mr))),
                  DropdownMenuItem(value: Salutation.ms, child: Text(_salutationLabel(context, Salutation.ms))),
                  DropdownMenuItem(value: Salutation.diverse, child: Text(_salutationLabel(context, Salutation.diverse))),
                ],
                onChanged: (v) => setState(() => _salutation = v ?? Salutation.mr),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedLang,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t.catalog_select_language,
                  border: const OutlineInputBorder(),
                ),
                items: supportedLangCodes
                    .map((code) => DropdownMenuItem<String>(
                          value: code,
                          child: Text(langNameFor(t, code)),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedLang = value);
                  prefs.setLang(value);
                },
              ),
              const SizedBox(height: 8),

              // Vorname / Nachname
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

              const SizedBox(height: 16),

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
                items: kCountries.map((c) {
                  return DropdownMenuItem<Country>(
                    value: c,
                    child: Text(c.label(context)),
                  );
                }).toList(),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _privacy,
                    onChanged: (v) => setState(() => _privacy = v ?? false),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(t.privacy_agree),
                        TextButton.icon(
                          onPressed: () => html.window.open('https://dfs-diamon.de/de/datenschutz', '_blank'),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: Text(t.privacy_view), // z.B. "Datenschutzhinweise ansehen"
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],

            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_err!, style: const TextStyle(color: Colors.red)),
              ),

            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _busy ? null : () async => _handlePress(context),
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(isLogin ? t.auth_login : t.auth_register),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePress(BuildContext context) async {
    final t = AppLocalizations.of(context)!;

    setState(() {
      _busy = true;
      _err = null;
    });

    try {
      // ---------- LOGIN ----------
      if (isLogin) {
        final ok = await widget.api.login(_email.text.trim(), _pw.text);
        if (!mounted) return;
        if (ok) {
          widget.onLoggedIn();
        } else {
          setState(() => _err = t.login_failed);
        }
        return;
      }

      // ---------- REGISTER ----------
      if (!_privacy) {
        if (!mounted) return;
        setState(() => _err = t.privacy_required);
        return;
      }
      if (_firstName.text.trim().isEmpty || _lastName.text.trim().isEmpty) {
        if (!mounted) return;
        setState(() => _err = t.name_required);
        return;
      }

      final selected = _countrySel ?? kCountries.first;
      final contactCombined = '${_firstName.text.trim()} ${_lastName.text.trim()}'.trim();

      final errStr = await widget.api.register({
        'email': _email.text.trim(),
        'password': _pw.text,
        'password2': _pw2.text,
        'company': _company.text.trim(),
        'firstName': _firstName.text.trim(),
        'lastName' : _lastName.text.trim(),
        'salutation': _salutation.name, // "mr" | "ms" | "diverse"
        'contact'  : contactCombined,   // Legacy/Kompatibilität
        'street': _street.text.trim(),
        'zip': _zip.text.trim(),
        'city': _city.text.trim(),
        'country': selected.label(context),
        'countryCode': selected.code,
        'phone': _phone.text.trim(),
        'privacy': true,
        'lang': _selectedLang,
      });

      if (!mounted) return;

      if (errStr == null) {
        // Erfolg: zurück zum Login und Hinweis ausgeben
        setState(() {
          isLogin = true;
          _err = t.registration_received;
        });
      } else {
        // Fehlertext vom Backend/Client anzeigen
        // Häufige Fälle: "409 user exists", "pending resent", generische Fehler
        if (errStr.contains('user_exists') || errStr.contains('409')) {
          setState(() => _err = t.email_exists);
        } else if (errStr.contains('pending') || errStr.contains('resent')) {
          setState(() => _err = t.register_pending_resent);
        } else {
          setState(() => _err = t.register_failed(errStr));
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = 'Network/CORS error: $e');
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }
}
