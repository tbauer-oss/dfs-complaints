// lib/pages/support_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';

class SupportPage extends StatefulWidget {
  final ApiClient api;
  const SupportPage({super.key, required this.api});
  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  final _msg = TextEditingController();
  String _cat = 'Allgemeine Anfrage';
  bool _consent = false;
  bool _busy = false;

  final _cats = const [
    'Allgemeine Anfrage',
    'Problem mit einer Reklamation',
    'Technisches Problem',
    'Anfragen zum Account',
    'Datenschutz',
    'Feedback',
    'Vorschlag zur Verbesserung',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
        title: const Text('DFS Support'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField(
                value: _cat,
                items: _cats.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _cat = v as String),
                decoration: const InputDecoration(labelText: 'Kategorie'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _msg,
                minLines: 6,
                maxLines: 16,
                decoration: const InputDecoration(
                  labelText: 'Ihre Nachricht',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(value: _consent, onChanged: (v) => setState(() => _consent = v ?? false)),
                  const Expanded(child: Text('Ich stimme der Verarbeitung gemäß Datenschutzhinweis zu.')),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton(
                    onPressed: _busy ? null : () async {
                      if (_msg.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte eine Nachricht eingeben.')));
                        return;
                      }
                      if (!_consent) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Datenschutz bestätigen.')));
                        return;
                      }
                      setState(() => _busy = true);
                      try {
                        await widget.api.sendSupport(category: _cat, message: _msg.text.trim(), consent: true);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nachricht gesendet.')));
                        Navigator.of(context).pop();
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
                      } finally { if (mounted) setState(() => _busy = false); }
                    },
                    child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Absenden'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
