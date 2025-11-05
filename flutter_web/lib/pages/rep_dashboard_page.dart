// lib/pages/rep_dashboard_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import 'rep_profile_page.dart'; // ← für Profil & Passwort

class RepDashboardPage extends StatefulWidget {
  final ApiClient api;
  const RepDashboardPage({super.key, required this.api});

  @override
  State<RepDashboardPage> createState() => _RepDashboardPageState();
}

class _RepDashboardPageState extends State<RepDashboardPage> {
  Map<String, dynamic>? _me;
  List<String> _customers = [];
  List<Map<String, dynamic>> _complaints = [];

  bool _loading = true;
  String? _err;

  // Einheitliche 401/Unauthorized-Behandlung
  Future<bool> _handleUnauthorized(Object e) async {
    final msg = e.toString();
    if (msg.contains('401')) {
      // Token ungültig/abgelaufen → sauber abmelden und zurück
      await widget.api.repLogout();
      if (!mounted) return true;

      // Info für den Nutzer
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sitzung abgelaufen. Bitte neu anmelden.')),
      );

      // Sicher bis zur Startseite zurück (nicht nur ein Pop)
      Navigator.of(context).popUntil((r) => r.isFirst);
      return true; // signalisiert: wurde gehandhabt
    }
    return false; // nichts getan
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final me = await widget.api.repMe();
      final cus = await widget.api.repCustomers();
      final comp = await widget.api.repComplaints();
      if (!mounted) return;
      setState(() {
        _me = me;
        _customers = cus;
        _complaints = comp;
      });
    } catch (e) {
      final handled = await _handleUnauthorized(e);
      if (!mounted) return;
      if (handled) return;            // 401 wurde bereits behandelt → NICHT mehr _err setzen
      setState(() => _err = '$e');    // andere Fehler normal anzeigen
    } finally {
      if (mounted) setState(() => _loading = false);
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
            await widget.api.repAssignCustomer(mail);
            if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
            await _loadAll();
          } catch (e) {
            locErr = 'Fehler: $e';
            saving = false;
            (ctx as Element).markNeedsBuild();
          }
        }

        return AlertDialog(
          title: const Text('Kunde zuweisen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(labelText: 'Kunden-E-Mail'),
              ),
              if (locErr != null) ...[
                const SizedBox(height: 8),
                Text(locErr!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: saving ? null : save,
              child: saving
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Zuweisen'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _unassignCustomer(String email) async {
    try {
      await widget.api.repUnassignCustomer(email);
      await _loadAll();
    } catch (e) {
      await _handleUnauthorized(e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  Future<void> _logout() async {
    await widget.api.repLogout();             // repToken löschen + persistieren
    if (!mounted) return;

    // Feedback + sicher bis zur Startseite
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Abgemeldet.')),
    );
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _err != null
            ? Center(child: Text(_err!, style: const TextStyle(color: Colors.red)))
            : Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 🔹 Neuer Button „Profil & Passwort“ – wie besprochen
                      Card(
                        elevation: 4,
                        child: ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: const Text('Profil & Passwort'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => RepProfilePage(api: widget.api),
                              ),
                            );
                            if (!mounted) return;
                            await _loadAll(); // nach Rückkehr neu laden
                          },
                            // Nach Rückkehr optional neu laden (falls Daten/Passwort geändert)
                            if (mounted) _loadAll();
                        ),
                      ),
                      const SizedBox(height: 16),

                      _Card(
                        title: 'Meine Daten',
                        child: _me == null
                            ? const Text('–')
                            : Wrap(
                                spacing: 16,
                                runSpacing: 6,
                                children: [
                                  _Info('Name',
                                      '${_me!['firstName'] ?? ''} ${_me!['lastName'] ?? ''}'.trim()),
                                  _Info('E-Mail', _me!['email'] ?? ''),
                                  _Info('Region', _me!['region'] ?? ''),
                                ],
                              ),
                      ),
                      const SizedBox(height: 16),

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

                      _Card(
                        title: 'Reklamationen meiner Kunden',
                        child: _complaints.isEmpty
                            ? const Text('Keine Reklamationen gefunden.')
                            : Column(
                                children: [
                                  for (final c in _complaints) _ComplaintTile(data: c),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              );

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
      body: body,
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(v),
      ],
    );
  }
}

class _ComplaintTile extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ComplaintTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final ticket   = (data['ticket'] ?? '').toString();
    final status   = (data['status'] ?? '').toString();
    final decision = (data['decision'] ?? '').toString();
    final created  = (data['createdAt'] ?? data['created'] ?? '').toString();
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
            Text(
              'Status: $status'
              '${decision.isNotEmpty ? ' • Entscheidung: $decision' : ''}'
              '${created.isNotEmpty ? ' • Angelegt: $created' : ''}',
            ),
          ],
        ),
        dense: true,
      ),
    );
  }
}
