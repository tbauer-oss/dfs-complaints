import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api/client.dart';

enum Salutation { mr, ms, diverse }

class RegisterPage extends StatefulWidget {
  final ApiClient api;
  const RegisterPage({super.key, required this.api});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
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

  Salutation _salutation = Salutation.mr;
  bool _privacy = false;
  bool _busy = false;
  String? _err;
  String? _info;

  @override
  void dispose() {
    _email.dispose(); _pw.dispose(); _pw2.dispose();
    _company.dispose(); _firstName.dispose(); _lastName.dispose();
    _street.dispose(); _zip.dispose(); _city.dispose(); _phone.dispose();
    super.dispose();
  }

  String _langCode(BuildContext ctx) {
    final lc = Localizations.localeOf(ctx).languageCode.toLowerCase();
    switch (lc) { case 'de': case 'en': case 'fr': case 'it': case 'es': return lc; default: return 'de'; }
  }

  Future<void> _submit() async {
    setState(() { _busy = true; _err = null; _info = null; });
    try {
      if (!_privacy) { setState(() => _err = 'Bitte Datenschutzhinweis bestätigen.'); return; }
      if (_firstName.text.trim().isEmpty || _lastName.text.trim().isEmpty) {
        setState(() => _err = 'Bitte Vor- und Nachname angeben.'); return;
      }
      if (_pw.text != _pw2.text) {
        setState(() => _err = 'Passwörter stimmen nicht überein.'); return;
      }

      final r = await widget.api.register({
        'email': _email.text.trim(),
        'password': _pw.text,
        'password2': _pw2.text,
        'company': _company.text.trim(),
        'firstName': _firstName.text.trim(),
        'lastName' : _lastName.text.trim(),
        'salutation': _salutation.name, // "mr" | "ms" | "diverse"
        'contact'  : '${_firstName.text.trim()} ${_lastName.text.trim()}'.trim(),
        'street': _street.text.trim(),
        'zip': _zip.text.trim(),
        'city': _city.text.trim(),
        // Country kannst du später ergänzen falls benötigt
        'country': '',
        'countryCode': '',
        'phone': _phone.text.trim(),
        'privacy': true,
        'lang': _langCode(context),
      });

      if (r.statusCode == 200 || r.statusCode == 201) {
        setState(() => _info = 'Registrierung eingegangen. Bitte warte auf Freigabe.');
        return;
      }

      final errStr = (r.body.isNotEmpty ? r.body : '${r.statusCode}');
      if (errStr.contains('user_exists') || r.statusCode == 409) {
        setState(() => _err = 'E-Mail existiert bereits.');
      } else if (errStr.contains('pending') || errStr.contains('resent')) {
        setState(() => _info = 'Registrierung bereits ausstehend. Bestätigungslink erneut versendet.');
      } else {
        setState(() => _err = 'Registrierung fehlgeschlagen: $errStr');
      }
    } catch (e) {
      setState(() => _err = 'Netzwerk-/CORS-Fehler: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrierung'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(controller: _email, keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-Mail', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: _pw, obscureText: true,
                  decoration: const InputDecoration(labelText: 'Passwort', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: _pw2, obscureText: true,
                  decoration: const InputDecoration(labelText: 'Passwort (Wiederholung)', border: OutlineInputBorder())),
                const SizedBox(height: 16),

                Align(alignment: Alignment.centerLeft, child:
                  Text('Ansprechpartner', style: Theme.of(context).textTheme.titleMedium)),
                const SizedBox(height: 8),

                DropdownButtonFormField<Salutation>(
                  value: _salutation,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Anrede', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: Salutation.mr, child: Text('Herr')),
                    DropdownMenuItem(value: Salutation.ms, child: Text('Frau')),
                    DropdownMenuItem(value: Salutation.diverse, child: Text('Divers')),
                  ],
                  onChanged: (v) => setState(() => _salutation = v ?? Salutation.mr),
                ),
                const SizedBox(height: 8),

                Row(children: [
                  Expanded(child: TextField(controller: _firstName,
                    decoration: const InputDecoration(labelText: 'Vorname', border: OutlineInputBorder()))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _lastName,
                    decoration: const InputDecoration(labelText: 'Nachname', border: OutlineInputBorder()))),
                ]),
                const SizedBox(height: 12),

                TextField(controller: _company,
                  decoration: const InputDecoration(labelText: 'Firma', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: _street,
                  decoration: const InputDecoration(labelText: 'Straße / Nr.', border: OutlineInputBorder())),
                const SizedBox(height: 8),

                Row(children: [
                  Expanded(child: TextField(controller: _zip,
                    decoration: const InputDecoration(labelText: 'PLZ', border: OutlineInputBorder()))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _city,
                    decoration: const InputDecoration(labelText: 'Ort', border: OutlineInputBorder()))),
                ]),
                const SizedBox(height: 8),

                TextField(controller: _phone,
                  decoration: const InputDecoration(labelText: 'Telefon', border: OutlineInputBorder())),
                const SizedBox(height: 8),

                Row(children: [
                  Checkbox(value: _privacy, onChanged: (v) => setState(() => _privacy = v ?? false)),
                  const Expanded(child: Text('Ich stimme der Datenschutzerklärung zu.')),
                ]),

                if (_err != null) Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_err!, style: const TextStyle(color: Colors.red)),
                ),
                if (_info != null) Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_info!, style: const TextStyle(color: Colors.green)),
                ),

                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Registrierung absenden'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
