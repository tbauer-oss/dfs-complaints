// lib/pages/rep_profile_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';

class RepProfilePage extends StatefulWidget {
  final ApiClient api;
  const RepProfilePage({super.key, required this.api});

  @override
  State<RepProfilePage> createState() => _RepProfilePageState();
}

class _RepProfilePageState extends State<RepProfilePage> {
  final _first = TextEditingController();
  final _last  = TextEditingController();
  final _region = TextEditingController();
  final _oldPw = TextEditingController();
  final _newPw = TextEditingController();
  final _newPw2 = TextEditingController();

  bool _busy = false;
  String? _msg;

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final me = await widget.api.getMyRep();
      _first.text = me.firstName ?? '';
      _last.text  = me.lastName ?? '';
      _region.text = me.region ?? '';
    } catch (e) {
      _msg = 'Fehler beim Laden: $e';
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _msg = null);
    try {
      await widget.api.repUpdate({
        'firstName': _first.text.trim(),
        'lastName':  _last.text.trim(),
        'region':    _region.text.trim(),
      });
      setState(() => _msg = 'Daten gespeichert.');
    } catch (e) {
      setState(() => _msg = 'Fehler: $e');
    }
  }

  Future<void> _changePw() async {
    if (_newPw.text != _newPw2.text) {
      setState(() => _msg = 'Passwörter stimmen nicht überein.');
      return;
    }
    try {
      await widget.api.repChangePasswordAuth(
        oldPw: _oldPw.text,
        newPw: _newPw.text,
      );
      setState(() => _msg = 'Passwort erfolgreich geändert.');
      _oldPw.clear(); _newPw.clear(); _newPw2.clear();
    } catch (e) {
      setState(() => _msg = 'Fehler: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mein Profil')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Persönliche Daten',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  TextField(controller: _first, decoration: const InputDecoration(labelText: 'Vorname')),
                  const SizedBox(height: 8),
                  TextField(controller: _last, decoration: const InputDecoration(labelText: 'Nachname')),
                  const SizedBox(height: 8),
                  TextField(controller: _region, decoration: const InputDecoration(labelText: 'Region')),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _saveProfile,
                    child: const Text('Speichern'),
                  ),
                  const Divider(height: 40),
                  const Text('Passwort ändern',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _oldPw,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Altes Passwort'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _newPw,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Neues Passwort'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _newPw2,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Neues Passwort (Wiederholung)'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _changePw,
                    child: const Text('Passwort ändern'),
                  ),
                  const SizedBox(height: 12),
                  if (_msg != null)
                    Text(_msg!,
                        style: TextStyle(
                            color: _msg!.startsWith('Fehler')
                                ? Colors.red
                                : Colors.green)),
                ],
              ),
            ),
    );
  }
}