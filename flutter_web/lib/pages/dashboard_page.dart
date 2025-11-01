// lib/pages/dashboard_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';

// existierende Seiten:
import 'complaint_form_page.dart';
import 'my_complaints_page.dart';

class DashboardPage extends StatelessWidget {
  final ApiClient api;
  const DashboardPage({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    Widget tile({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
      Color? color,
    }) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: (color ?? Theme.of(context).colorScheme.primary).withOpacity(0.12),
                  child: Icon(icon, color: color ?? Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      );
    }

    Widget statusLegend() {
      // Legende gemäß deiner Vorgabe
      Widget dot(Color c) => Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
      Text lbl(String s) => Text(s, style: const TextStyle(fontSize: 12));

      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 16,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [dot(Colors.blue), const SizedBox(width: 6), lbl('gesendet')]),
              Row(mainAxisSize: MainAxisSize.min, children: [dot(Colors.yellow.shade700), const SizedBox(width: 6), lbl('in Bearbeitung')]),
              Row(mainAxisSize: MainAxisSize.min, children: [dot(Colors.orange), const SizedBox(width: 6), lbl('Rückfrage erforderlich')]),
              Row(mainAxisSize: MainAxisSize.min, children: [dot(Colors.lightGreen), const SizedBox(width: 6), lbl('angenommen')]),
              Row(mainAxisSize: MainSize.min, children: [dot(Colors.red), const SizedBox(width: 6), lbl('abgelehnt')]),
              Row(mainAxisSize: MainAxisSize.min, children: [dot(Colors.amber), const SizedBox(width: 6), lbl('in Nacharbeit')]),
              Row(mainAxisSize: MainAxisSize.min, children: [dot(Colors.green), const SizedBox(width: 6), lbl('abgeschlossen')]),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(t.appTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // 1) Reklamation melden
          tile(
            icon: Icons.add_circle_outline,
            title: 'Reklamation melden',
            subtitle: 'Neue Meldung anlegen (Ticketnummer automatisch)',
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ComplaintFormPage(api: api),
              ));
            },
          ),
          // 2) Meine Reklamationen
          tile(
            icon: Icons.list_alt_outlined,
            title: 'Meine Reklamationen',
            subtitle: 'Statusverlauf, Bericht verlinkt (abschl./abgelehnt)',
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MyComplaintsPage(api: api),
              ));
            },
          ),
          const SizedBox(height: 8),
          statusLegend(),
          const SizedBox(height: 16),

          const Divider(height: 32),

          // 3) Mein Account
          tile(
            icon: Icons.person_outline,
            title: 'Mein Account',
            subtitle: 'Daten ändern, Passwort ändern, Account löschen',
            onTap: () {
              // Inline-Seite, wenn du noch keine eigene AccountPage hast
              Navigator.of(context).push(MaterialPageRoute(builder: (_) {
                return _InlineAccountPage(api: api);
              }));
            },
          ),

          // 4) DFS Support
          tile(
            icon: Icons.support_agent,
            title: 'DFS Support',
            subtitle: 'Allgemein, Reklamation, Technik, Account, Datenschutz, Feedback',
            onTap: () {
              // Inline-Seite, wenn du noch keine eigene SupportPage hast
              Navigator.of(context).push(MaterialPageRoute(builder: (_) {
                return _InlineSupportPage(api: api);
              }));
            },
          ),
        ],
      ),
    );
  }
}

// --------- Inline-Seiten als Platzhalter (kannst du ersetzen) ----------

class _InlineAccountPage extends StatefulWidget {
  final ApiClient api;
  const _InlineAccountPage({required this.api});
  @override
  State<_InlineAccountPage> createState() => _InlineAccountPageState();
}

class _InlineAccountPageState extends State<_InlineAccountPage> {
  bool _busy = true;
  String? _err;
  Map<String, dynamic> _data = {};

  final _pwOld = TextEditingController();
  final _pwNew1 = TextEditingController();
  final _pwNew2 = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final d = await widget.api.accountGet();
      _data = d;
      _err = null;
    } catch (e) {
      _err = '$e';
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _busy = true);
    try {
      await widget.api.accountUpdate(_data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _changePw() async {
    if (_pwNew1.text != _pwNew2.text) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Neues Passwort stimmt nicht überein.')));
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.api.accountChangePassword(_pwOld.text, _pwNew1.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwort geändert.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Account löschen?'),
        content: const Text('Sind Sie sicher? Diese Aktion kann nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Weiter')),
        ],
      ),
    );
    if (sure != true) return;

    final pw = await showDialog<String>(
      context: context,
      builder: (_) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Bestätigen'),
          content: TextField(controller: ctrl, obscureText: true, decoration: const InputDecoration(labelText: 'Passwort')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Abbrechen')),
            FilledButton.tonal(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Account löschen')),
          ],
        );
      },
    );
    if (pw == null) return;

    setState(() => _busy = true);
    try {
      await widget.api.accountDelete(pw);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account gelöscht.')));
        Navigator.of(context).pop(); // zurück zum Dashboard
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_err != null) return Scaffold(appBar: AppBar(title: const Text('Mein Account')), body: Center(child: Text(_err!)));

    return Scaffold(
      appBar: AppBar(title: const Text('Mein Account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Stammdaten', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._data.entries.map((e) {
            final key = e.key;
            final val = (e.value ?? '').toString();
            // einfache Textfelder – du kannst hier spezifische Felder hübscher machen
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: TextEditingController(text: val),
                onChanged: (v) => _data[key] = v,
                decoration: InputDecoration(labelText: key),
              ),
            );
          }),

          Row(
            children: [
              FilledButton(onPressed: _saveProfile, child: const Text('Speichern')),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: _load, child: const Text('Abbrechen')),
            ],
          ),

          const Divider(height: 32),
          Text('Passwort ändern', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(controller: _pwOld, obscureText: true, decoration: const InputDecoration(labelText: 'Altes Passwort')),
          const SizedBox(height: 8),
          TextField(controller: _pwNew1, obscureText: true, decoration: const InputDecoration(labelText: 'Neues Passwort')),
          const SizedBox(height: 8),
          TextField(controller: _pwNew2, obscureText: true, decoration: const InputDecoration(labelText: 'Neues Passwort (Wiederholung)')),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(onPressed: _changePw, child: const Text('Speichern')),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: () {}, child: const Text('Abbrechen')),
            ],
          ),

          const Divider(height: 32),
          Text('Account löschen', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _deleteAccount,
            style: FilledButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.12)),
            child: const Text('Account löschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _InlineSupportPage extends StatefulWidget {
  final ApiClient api;
  const _InlineSupportPage({required this.api});
  @override
  State<_InlineSupportPage> createState() => _InlineSupportPageState();
}

class _InlineSupportPageState extends State<_InlineSupportPage> {
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
  ];

  Future<void> _send() async {
    if (!_consent) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Datenschutz bestätigen.')));
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.api.sendSupport(category: _cat, message: _msg.text, consent: _consent);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gesendet.')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DFS Support')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  value: _cat,
                  items: _cats.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setState(() => _cat = v ?? _cat),
                  decoration: const InputDecoration(labelText: 'Kategorie'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _msg,
                  maxLines: 10,
                  decoration: const InputDecoration(labelText: 'Ihre Anfrage / Problem'),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: _consent,
                  onChanged: (v) => setState(() => _consent = v ?? false),
                  title: const Text('Ich stimme der Verarbeitung gemäß Datenschutz zu.'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                Row(
                  children: [
                    FilledButton(onPressed: _send, child: const Text('Absenden')),
                    const SizedBox(width: 12),
                    OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
                  ],
                ),
              ],
            ),
    );
  }
}
