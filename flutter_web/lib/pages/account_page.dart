import 'package:flutter/material.dart';
import '../api/client.dart';

class AccountPage extends StatefulWidget {
  final ApiClient api;
  const AccountPage({super.key, required this.api});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool loading = true;
  String? err;

  // Accountfelder
  final _company = TextEditingController();
  final _first = TextEditingController();
  final _last  = TextEditingController();
  final _street= TextEditingController();
  final _zip   = TextEditingController();
  final _city  = TextEditingController();
  final _phone = TextEditingController();
  String email = '';

  // PW Felder
  final _oldPw = TextEditingController();
  final _newPw = TextEditingController();
  final _newPw2= TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final u = await widget.api.accountGet();
      setState(() {
        email = u['email'] ?? '';
        _company.text = u['company'] ?? '';
        _first.text   = u['firstName'] ?? '';
        _last.text    = u['lastName'] ?? '';
        _street.text  = u['street'] ?? '';
        _zip.text     = u['zip'] ?? '';
        _city.text    = u['city'] ?? '';
        _phone.text   = u['phone'] ?? '';
        err = null;
        loading = false;
      });
    } catch (e) {
      setState(() { err = '$e'; loading = false; });
    }
  }

  Future<void> _saveAccount() async {
    setState(()=> loading = true);
    try {
      await widget.api.accountUpdate({
        'company': _company.text,
        'firstName': _first.text,
        'lastName': _last.text,
        'street': _street.text,
        'zip': _zip.text,
        'city': _city.text,
        'phone': _phone.text,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gespeichert. E-Mail-Benachrichtigung gesendet.'))
        );
      }
      await _load();
    } catch (e) {
      setState(()=> loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _changePw() async {
    if (_newPw.text != _newPw2.text) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwörter stimmen nicht überein.')));
      return;
    }
    setState(()=> loading = true);
    try {
      await widget.api.accountChangePassword(_oldPw.text, _newPw.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Passwort geändert. E-Mail-Benachrichtigung gesendet.'))
        );
      }
      setState(()=> loading = false);
      _oldPw.clear(); _newPw.clear(); _newPw2.clear();
    } catch (e) {
      setState(()=> loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deleteAccountFlow() async {
    final q1 = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Account löschen?'),
        content: const Text('Bist du sicher? Diese Aktion kann nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(onPressed: ()=> Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: ()=> Navigator.pop(context, true), child: const Text('Weiter')),
        ],
      ),
    );
    if (q1 != true) return;

    final pwCtrl = TextEditingController();
    final doDelete = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Passwort bestätigen'),
        content: TextField(
          controller: pwCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Passwort'),
        ),
        actions: [
          TextButton(onPressed: ()=> Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: ()=> Navigator.pop(context, true), child: const Text('Account löschen')),
        ],
      ),
    );
    if (doDelete != true) return;

    setState(()=> loading = true);
    try {
      await widget.api.accountDelete(pwCtrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account gelöscht. E-Mail-Benachrichtigung gesendet.'))
        );
      }
      if (mounted) Navigator.of(context).pop(); // zurück in Kundenbereich
    } catch (e) {
      setState(()=> loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mein Account')),
      body: loading
        ? const Center(child: CircularProgressIndicator())
        : err != null
          ? Center(child: Text(err!))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // Daten ändern
                  Text('Daten ändern', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('E-Mail (fest): $email'),
                  const SizedBox(height: 8),

                  Wrap(spacing: 16, runSpacing: 8, children: [
                    SizedBox(width: 320, child: TextField(controller: _company, decoration: const InputDecoration(labelText: 'Firma'))),
                    SizedBox(width: 320, child: TextField(controller: _first, decoration: const InputDecoration(labelText: 'Vorname'))),
                    SizedBox(width: 320, child: TextField(controller: _last,  decoration: const InputDecoration(labelText: 'Nachname'))),
                    SizedBox(width: 320, child: TextField(controller: _street,decoration: const InputDecoration(labelText: 'Adresse'))),
                    SizedBox(width: 160, child: TextField(controller: _zip,   decoration: const InputDecoration(labelText: 'PLZ'))),
                    SizedBox(width: 320, child: TextField(controller: _city,  decoration: const InputDecoration(labelText: 'Ort'))),
                    SizedBox(width: 320, child: TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Telefon'))),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    FilledButton(onPressed: _saveAccount, child: const Text('Speichern')),
                    const SizedBox(width: 8),
                    OutlinedButton(onPressed: _load, child: const Text('Abbrechen')),
                  ]),

                  const Divider(height: 32),

                  // Passwort ändern
                  Text('Passwort ändern', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  SizedBox(width: 320, child: TextField(controller: _oldPw, obscureText: true, decoration: const InputDecoration(labelText: 'Altes Passwort'))),
                  SizedBox(width: 320, child: TextField(controller: _newPw, obscureText: true, decoration: const InputDecoration(labelText: 'Neues Passwort'))),
                  SizedBox(width: 320, child: TextField(controller: _newPw2, obscureText: true, decoration: const InputDecoration(labelText: 'Neues Passwort (Wiederholung)'))),
                  const SizedBox(height: 12),
                  Row(children: [
                    FilledButton(onPressed: _changePw, child: const Text('Speichern')),
                    const SizedBox(width: 8),
                    OutlinedButton(onPressed: () { _oldPw.clear(); _newPw.clear(); _newPw2.clear(); }, child: const Text('Abbrechen')),
                  ]),

                  const Divider(height: 32),

                  // Account löschen
                  Text('Account löschen', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: _deleteAccountFlow,
                    child: const Text('Account löschen'),
                  ),
                ],
              ),
            ),
    );
  }
}
