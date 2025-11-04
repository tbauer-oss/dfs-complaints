// lib/pages/rep_login_page.dart
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'rep_dashboard_page.dart';

class RepLoginPage extends StatefulWidget {
  const RepLoginPage({super.key});

  @override
  State<RepLoginPage> createState() => _RepLoginPageState();
}

class _RepLoginPageState extends State<RepLoginPage> {
  static const String _apiBase = String.fromEnvironment('API_BASE', defaultValue: '');

  final _email = TextEditingController();
  final _pw    = TextEditingController();
  final _new1  = TextEditingController();
  final _new2  = TextEditingController();

  bool _busy = false;
  String? _err;

  Future<void> _login() async {
    setState(() { _busy = true; _err = null; });
    try {
      final r = await http.post(
        Uri.parse('$_apiBase/api/rep/login'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({'email': _email.text.trim(), 'password': _pw.text}),
      );

      if (r.statusCode != 200) {
        setState(() => _err = r.body.isNotEmpty ? r.body : 'Login failed (${r.statusCode})');
        return;
      }
      final j = jsonDecode(r.body) as Map;
      final token = (j['token'] ?? '').toString();
      final mustChange = (j['mustChangePw'] ?? false) == true;

      if (token.isEmpty) {
        setState(() => _err = 'Invalid response (no token)');
        return;
      }

      // Token speichern
      html.window.localStorage['dfs_rep_token'] = token;

      if (mustChange) {
        // Direkt Passwort-Änderung anfordern
        if (!mounted) return;
        await _showChangePasswordDialog(token);
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RepDashboardPage()),
      );
    } catch (e) {
      setState(() => _err = 'Network error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _showChangePasswordDialog(String token) async {
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
          final a = _new1.text;
          final b = _new2.text;
          if (a.isEmpty || b.isEmpty) {
            localErr = 'Bitte neues Passwort in beiden Feldern eingeben.';
            (ctx as Element).markNeedsBuild();
            return;
          }
          if (a != b) {
            localErr = 'Passwörter stimmen nicht überein.';
            (ctx as Element).markNeedsBuild();
            return;
          }
          saving = true;
          (ctx as Element).markNeedsBuild();
          try {
            final r = await http.post(
              Uri.parse('$_apiBase/api/rep/password'),
              headers: {
                'Content-Type': 'application/json; charset=utf-8',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode({'new': a}),
            );
            if (r.statusCode != 200 && r.statusCode != 204) {
              localErr = r.body.isNotEmpty ? r.body : 'Fehler (${r.statusCode})';
              saving = false;
              (ctx as Element).markNeedsBuild();
              return;
            }
            if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
          } catch (e) {
            localErr = 'Netzwerkfehler: $e';
            saving = false;
            (ctx as Element).markNeedsBuild();
          }
        }

        return AlertDialog(
          title: const Text('Neues Passwort setzen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _new1,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Neues Passwort'),
              ),
              TextField(
                controller: _new2,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Neues Passwort (Wiederholung)'),
              ),
              if (localErr != null) ...[
                const SizedBox(height: 8),
                Text(localErr!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Später'),
            ),
            ElevatedButton(
              onPressed: saving ? null : save,
              child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Speichern'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final canLogin = !_busy && _email.text.trim().isNotEmpty && _pw.text.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Vertreter-Login')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _email,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'E-Mail'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pw,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Passwort'),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => canLogin ? _login() : null,
                  ),
                  const SizedBox(height: 16),
                  if (_err != null) Text(_err!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login),
                      label: const Text('Anmelden'),
                      onPressed: canLogin ? _login : null,
                    ),
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
