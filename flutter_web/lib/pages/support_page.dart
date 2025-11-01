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
  bool consent = false;
  String category = 'general';
  bool busy = false;

  final cats = const <String, String>{
    'general': 'Allgemeine Anfrage',
    'complaint': 'Problem mit einer Reklamation',
    'technical': 'Technisches Problem',
    'account': 'Anfragen zum Account',
    'privacy': 'Datenschutz',
    'feedback': 'Feedback',
    'other': 'Sonstiges',
  };

  Future<void> _send() async {
    setState(()=> busy = true);
    try {
      await widget.api.sendSupport(category: category, message: _msg.text, consent: consent);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nachricht gesendet. Kopie per E-Mail.')));
        _msg.clear(); consent = false; setState(()=> busy = false);
      }
    } catch (e) {
      setState(()=> busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DFS Support')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: category,
              items: cats.entries.map((e)=>DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: (v)=> setState(()=> category = v ?? 'other'),
              decoration: const InputDecoration(labelText: 'Kategorie'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _msg,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  labelText: 'Ihre Anfrage / Ihr Anliegen',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(value: consent, onChanged: (v)=> setState(()=> consent = v ?? false)),
                const Expanded(child: Text('Ich bestätige die Hinweise zum Datenschutz.')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(onPressed: busy ? null : _send, child: const Text('Absenden')),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: busy ? null : (){ _msg.clear(); setState(()=> consent = false); }, child: const Text('Abbrechen')),
              ],
            )
          ],
        ),
      ),
    );
  }
}
