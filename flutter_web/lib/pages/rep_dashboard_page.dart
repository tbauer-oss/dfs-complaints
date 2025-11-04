// lib/pages/rep_dashboard_page.dart
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http';

class RepDashboardPage extends StatefulWidget {
  const RepDashboardPage({super.key});

  @override
  State<RepDashboardPage> createState() => _RepDashboardPageState();
}

class _RepDashboardPageState extends State<RepDashboardPage> {
  static const String _apiBase = String.fromEnvironment('API_BASE', defaultValue: '');

  Map<String, dynamic>? _me;
  List<String> _customers = [];
  List<Map<String, dynamic>> _complaints = [];

  bool _loading = true;
  String? _err;

  String? get _token => html.window.localStorage['dfs_rep_token'];

  Map<String, String> _headers() => {
    'Content-Type': 'application/json; charset=utf-8',
    if ((_token ?? '').isNotEmpty) 'Authorization': 'Bearer ${_token!}',
  };

  Future<void> _loadAll() async {
    setState(() { _loading = true; _err = null; });
    try {
      // Profil
      final meR = await http.get(Uri.parse('$_apiBase/api/rep/me'), headers: _headers());
      if (meR.statusCode != 200) { throw 'rep/me ${meR.statusCode} ${meR.body}'; }
      _me = (jsonDecode(meR.body) as Map).cast<String, dynamic>();

      // Kunden
      final cusR = await http.get(Uri.parse('$_apiBase/api/rep/customers'), headers: _headers());
      if (cusR.statusCode != 200) { throw 'rep/customers ${cusR.statusCode} ${cusR.body}'; }
      final List c = jsonDecode(cusR.body);
      _customers = c.cast<String>();

      // Reklamationen
      final cr = await http.get(Uri.parse('$_apiBase/api/rep/complaints'), headers: _headers());
      if (cr.statusCode != 200) { throw 'rep/complaints ${cr.statusCode} ${cr.body}'; }
      final List list = jsonDecode(cr.body);
      _complaints = list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    } catch (e) {
      _err = '$e';
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _assignCustomerDialog() async {
    final ctrl = TextEditingController();
    String? locErr;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        Future<void> save() async {
          if (saving) return;
          final mail = ctrl.text.trim().toLowerCase();
          if (mail.isEmpty || !mail.contains('@')) {
            locErr = 'Bitte gültige E-Mail eingeben.';
            (ctx as Element).markNeedsBuild();
            return;
          }
          saving = true;
          (ctx as Element).markNeedsBuild();
          try {
            final r = await http.post(
              Uri.parse('$_apiBase/api/rep/customers'),
              headers: _headers(),
              body: jsonEncode({'action': 'assign', 'email': mail}),
            );
            if (r.statusCode != 200) {
              locErr = r.body.isNotEmpty ? r.body : 'Fehler (${r.statusCode})';
              saving = false;
              (ctx as Element).markNeedsBuild();
              return;
            }
            if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
            await _loadAll();
          } catch (e) {
            locErr = 'Netzwerkfehler: $e';
            saving = false;
            (ctx as Element).markNeedsBuild();
          }
        }

        return AlertDialog(
          title: const Text('Kunde zuweisen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Kunden-E-Mail')),
              if (locErr != null) ...[
                const SizedBox(height: 8),
                Text(locErr!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.of(ctx).pop(), child: const Text('Abbrechen')),
            ElevatedButton(onPressed: saving ? null : save, child: saving ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)) : const Text('Zuweisen')),
          ],
        );
      },
    );
  }

  Future<void> _unassignCustomer(String email) async {
    try {
      final r = await http.post(
        Uri.parse('$_apiBase/api/rep/customers'),
        headers: _headers(),
        body: jsonEncode({'action': 'unassign', 'email': email}),
      );
      if (r.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: ${r.statusCode}')));
        return;
      }
      await _loadAll();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Netzwerkfehler: $e')));
    }
  }

  void _logout() {
    html.window.localStorage.remove('dfs_rep_token');
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final tokenOk = (_token ?? '').isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vertreter-Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Neu laden',
            onPressed: _loading ? null : _loadAll,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: !tokenOk
          ? const Center(child: Text('Kein Vertreter-Token. Bitte erneut anmelden.'))
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _err != null
                  ? Center(child: Text(_err!, style: const TextStyle(color: Colors.red)))
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: LayoutBuilder(
                        builder: (ctx, c) {
                          return SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Profilkarte
                                _Card(
                                  title: 'Meine Daten',
                                  child: _me == null
                                      ? const Text('–')
                                      : Wrap(
                                          spacing: 16,
                                          runSpacing: 6,
                                          children: [
                                            _Info('Name', '${_me!['firstName'] ?? ''} ${_me!['lastName'] ?? ''}'.trim()),
                                            _Info('E-Mail', _me!['email'] ?? ''),
                                            _Info('Region', _me!['region'] ?? ''),
                                          ],
                                        ),
                                ),
                                const SizedBox(height: 16),
                                // Kundenliste + Zuweisung
                                _Card(
                                  title: 'Meine Kunden',
                                  actions: [
                                    ElevatedButton.icon(
                                      onPressed: _assignCustomerDialog,
                                      icon: const Icon(Icons.person_add_alt_1),
                                      label: const Text('Kunde zuweisen'),
                                    ),
                                  ],
                                  child: _customers.isEmpty
                                      ? const Text('Noch keine Kunden zugewiesen.')
                                      : Column(
                                          children: [
                                            for (final e in _customers)
                                              ListTile(
                                                leading: const Icon(Icons.person),
                                                title: Text(e),
                                                trailing: IconButton(
                                                  icon: const Icon(Icons.link_off),
                                                  tooltip: 'Zuweisung entfernen',
                                                  onPressed: () => _unassignCustomer(e),
                                                ),
                                              ),
                                          ],
                                        ),
                                ),
                                const SizedBox(height: 16),
                                // Reklamationen
                                _Card(
                                  title: 'Reklamationen meiner Kunden',
                                  child: _complaints.isEmpty
                                      ? const Text('Keine Reklamationen gefunden.')
                                      : Column(
                                          children: [
                                            for (final c in _complaints)
                                              _ComplaintTile(data: c),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final Widget child;
  const _Card({required this.title, this.actions, required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const Spacer(),
              if (actions != null) ...actions!,
            ]),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  final String k;
  final String v;
  const _Info(this.k, this.v);

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
      Text(v),
    ]);
  }
}

class _ComplaintTile extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ComplaintTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final ticket = (data['ticket'] ?? '').toString();
    final status = (data['status'] ?? '').toString();
    final decision = (data['decision'] ?? '').toString();
    final created = (data['createdAt'] ?? data['created'] ?? '').toString();
    final customer = (data['customerEmail'] ?? data['email'] ?? '').toString();
    final article  = (data['payload']?['article'] ?? '').toString();
    final segment  = (data['payload']?['segment'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(ticket.isEmpty ? '(ohne Ticket)' : ticket),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (customer.isNotEmpty) Text('Kunde: $customer'),
            if (article.isNotEmpty)  Text('Artikel: $article'),
            if (segment.isNotEmpty)  Text('Segment: $segment'),
            Text('Status: $status'
                '${decision.isNotEmpty ? ' • Entscheidung: $decision' : ''}'
                '${created.isNotEmpty ? ' • Angelegt: $created' : ''}'),
          ],
        ),
        dense: true,
      ),
    );
  }
}
