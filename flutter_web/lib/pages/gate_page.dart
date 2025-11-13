// lib/pages/gate_page.dart
import 'package:flutter/material.dart';
import 'dart:html' as html;

import '../api/client.dart';
import '../l10n/app_localizations.dart';

class GatePage extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onUnlocked;
  const GatePage({super.key, required this.api, required this.onUnlocked});
  @override
  State<GatePage> createState() => _GatePageState();
}

class _GatePageState extends State<GatePage> {
  final _ctrl = TextEditingController();
  String? _err;
  bool _busy = false;

  // === Admin: Secret-Dialog + Preflight-Check ===
  Future<void> _openAdmin() async {
    final secretCtrl = TextEditingController(
      text: html.window.localStorage['admin_secret'] ?? '',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Admin-Secret'),
        content: TextField(
          controller: secretCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'X-Admin-Secret',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Weiter')),
        ],
      ),
    );

    if (ok != true) return;

    final secret = secretCtrl.text.trim();
    if (secret.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte ein Admin-Secret eingeben.')),
      );
      return;
    }

    // Persistieren
    html.window.localStorage['admin_secret'] = secret;

    // Preflight gegen /api/admin/users prüfen
    try {
      final base = const String.fromEnvironment('API_BASE', defaultValue: '');
      final apiBase = base.isNotEmpty ? base : html.window.location.origin;

      final res = await html.HttpRequest.request(
        '$apiBase/api/admin/users',
        method: 'GET',
        withCredentials: true,
        requestHeaders: {
          'X-Admin-Secret': secret,
          'Content-Type': 'application/json; charset=utf-8',
        },
      );

      if (res.status == 200) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pushNamed('/admin');
      } else {
        throw 'HTTP ${res.status}';
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Adminzugang verweigert (Secret ungültig/CORS): $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Center(
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ===== Adminbereich-Button GANZ OBEN (mit Secret-Dialog & Preflight) =====
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.admin_panel_settings),
                label: const Text('Adminbereich'),
                onPressed: _openAdmin, // <— WICHTIG: nicht direkt pushNamed!
              ),
            ),
            const SizedBox(height: 12),

            // ===== ursprünglicher Gate-Inhalt =====
            Text(t.gate_prompt, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              obscureText: true,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: t.gate_password,
              ),
            ),
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_err!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      _err = null;
                      final ok = await widget.api.gateUnlock(_ctrl.text);
                      setState(() => _busy = false);
                      if (ok) {
                        widget.onUnlocked();
                      } else {
                        setState(() => _err = t.invalid);
                      }
                    },
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t.continueLabel),
            ),
          ],
        ),
      ),
    );
  }
}
