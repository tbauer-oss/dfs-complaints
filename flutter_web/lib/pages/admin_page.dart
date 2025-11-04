// lib/pages/admin_page.dart
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../api/client.dart';

// ===================================================================
// Admin Page – mit Kachel-Menü (wie Kunden-Dashboard)
// ===================================================================
class AdminPage extends StatefulWidget {
  final ApiClient api;
  const AdminPage({super.key, required this.api});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

enum _AdminView { menu, pending, users, open, reps }

class _AdminPageState extends State<AdminPage> {
  late final AdminApi _api;

  // Ladeflags / Fehler
  bool _loadPending = false;
  bool _loadUsers = false;
  bool _loadOpen = false;
  bool _loadReps = false;
  String? _fatalErr;
  String? _err;

  // Daten
  List<PendingUser> _pending = [];
  List<ActiveUser> _users = [];
  List<AdminComplaint> _openComplaints = [];
  List<Rep> _reps = [];

  // Email -> detaillierte Reklamationen (für Users/Pending)
  final Map<String, _ComplaintsResult> _complaints = {};

  // Firmenfilter (Offene Reklamationen)
  String _filterCompany = 'Alle Firmen';

  // Ansicht (Menü / Bereich)
  _AdminView _view = _AdminView.menu;

  @override
  void initState() {
    super.initState();
    _api = AdminApi();

    // Secret zuerst aus der API (wenn über Admin-Button gekommen),
    // sonst aus LocalStorage (dfs_admin).
    String secret = widget.api.adminSecret ?? '';
    if (secret.isEmpty) {
      secret = html.window.localStorage['dfs_admin'] ?? '';
    }
    _api.setSecret(secret);

    if (secret.isEmpty) {
      _fatalErr =
          'Kein Admin-Secret gefunden. Bitte den Adminbereich über den Start-Button öffnen '
          'oder im Browser-Storage dfs_admin setzen.';
      return;
    }

    _refreshAll();
    _refreshOpen();
  }

  // Hilfsfunktionen ---------------------------------------------------
  String? _companyByEmail(String email) {
    final e = email.trim().toLowerCase();
    final u = _users.firstWhere(
      (x) => x.email.trim().toLowerCase() == e,
      orElse: () => ActiveUser.empty(),
    );
    if (u.email.isNotEmpty) return u.company.trim().isEmpty ? null : u.company.trim();

    final p = _pending.firstWhere(
      (x) => x.email.trim().toLowerCase() == e,
      orElse: () => PendingUser.empty(),
    );
    return p.company.trim().isEmpty ? null : p.company.trim();
  }

  Future<void> _refreshAll() async {
    setState(() {
      _err = null;
      _loadPending = true;
      _loadUsers = true;
    });
    try {
      final pF = _api.fetchPending();
      final uF = _api.fetchUsers();
      final both = await Future.wait([pF, uF]);
      if (!mounted) return;
      setState(() {
        _pending = both[0] as List<PendingUser>;
        _users = both[1] as List<ActiveUser>;
      });
    } catch (e) {
      setState(() => _err = '$e');
    } finally {
      if (!mounted) return;
      setState(() {
        _loadPending = false;
        _loadUsers = false;
      });
    }
  }

  Future<void> _refreshOpen() async {
    setState(() {
      _err = null;
      _loadOpen = true;
    });
    try {
      final list = await _api.fetchOpenComplaints();
      if (!mounted) return;
      setState(() => _openComplaints = list);
    } catch (e) {
      setState(() => _err = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _loadOpen = false);
    }
  }

  Future<void> _refreshReps() async {
    setState(() { _err = null; _loadReps = true; });
    try {
      final list = await _api.fetchReps();
      if (!mounted) return;
      setState(() => _reps = list);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _loadReps = false);
    }
  }

  Future<void> _loadComplaintsDetailed(String email) async {
    final cur = _complaints[email];
    if (cur?.loading == true) return;
    setState(() {
      _complaints[email] = _ComplaintsResult.loading();
    });
    try {
      final list = await _api.fetchComplaintsByEmailDetailed(email);
      if (!mounted) return;
      setState(() {
        _complaints[email] = _ComplaintsResult.ok(list);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _complaints[email] = _ComplaintsResult.err('$e');
      });
    }
  }

  Future<bool?> _confirm(String title, String msg) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
  }

  // UI ----------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_fatalErr != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Adminbereich – DFS Customer Complaint'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 44),
                  const SizedBox(height: 12),
                  Text(_fatalErr!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Zurück')),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final companies = <String>{
      'Alle Firmen',
      ..._users.map((e) => e.company).where((s) => s.trim().isNotEmpty),
      ..._pending.map((e) => e.company).where((s) => s.trim().isNotEmpty),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final title = switch (_view) {
      _AdminView.menu    => 'Adminbereich – DFS Customer Complaint',
      _AdminView.pending => 'Pending (Freigabe ausstehend)',
      _AdminView.users   => 'Aktive Nutzer',
      _AdminView.open    => 'Offene Reklamationen',
      _AdminView.reps    => 'Vertreterverwaltung',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: _view == _AdminView.menu
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : IconButton(
                icon: const Icon(Icons.home_outlined),
                tooltip: 'Zurück zum Admin-Menü',
                onPressed: () => setState(() => _view = _AdminView.menu),
              ),
        actions: [
          IconButton(
            tooltip: 'Alles neu laden',
            onPressed: () async {
              await _refreshAll();
              await _refreshOpen();
            },
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _buildBody(theme, companies),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, List<String> companies) {
    if (_err != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_err!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 8),
          Expanded(child: _view == _AdminView.menu ? _buildMenu() : _buildView(companies)),
        ],
      );
    }
    return _view == _AdminView.menu ? _buildMenu() : _buildView(companies);
  }

  // ------------------ Kachel-Menü ------------------
  Widget _buildMenu() {
    final w = MediaQuery.of(context).size.width;
    final cross = w > 900 ? 4 : (w > 600 ? 3 : 2);

    final tiles = <_AdminTile>[
      _AdminTile(
        icon: Icons.hourglass_top,
        label: 'Pending',
        color: Colors.amber,
        onTap: () => setState(() => _view = _AdminView.pending),
        badge: _loadPending ? const _BusyDot() : null,
      ),
      _AdminTile(
        icon: Icons.people,
        label: 'Aktive Nutzer',
        color: Colors.cyan,
        onTap: () => setState(() => _view = _AdminView.users),
        badge: _loadUsers ? const _BusyDot() : null,
      ),
      _AdminTile(
        icon: Icons.receipt_long,
        label: 'Offene Reklamationen',
        color: Colors.indigo,
        onTap: () => setState(() => _view = _AdminView.open),
        badge: _loadOpen ? const _BusyDot() : null,
      ),
      _AdminTile(
        icon: Icons.badge_outlined,
        label: 'Vertreter',
        color: Colors.green,
        onTap: () {
          setState(() => _view = _AdminView.reps);
          if (_reps.isEmpty) _refreshReps();
        },
        badge: _loadReps ? const _BusyDot() : null,
      ),
    ];

    return GridView.count(
      padding: const EdgeInsets.all(16),
      crossAxisCount: cross,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      children: [
        for (final t in tiles) t,
      ],
    );
  }

  // ------------------ Panel-Ansichten ------------------
  Widget _buildView(List<String> companies) {
    switch (_view) {
      case _AdminView.pending:
        return _buildPendingPanel();
      case _AdminView.users:
        return _buildUsersPanel();
      case _AdminView.open:
        return _buildOpenPanel(companies);
      case _AdminView.menu:
        return const SizedBox.shrink();
      case _AdminView.reps:
        return _buildRepsPanel();
    }
  }

  Widget _buildPendingPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.hourglass_top),
              const SizedBox(width: 8),
              const Text('Pending (Freigabe ausstehend)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                tooltip: 'Neu laden',
                onPressed: _loadPending ? null : () async {
                  setState(() => _loadPending = true);
                  try {
                    final list = await _api.fetchPending();
                    if (!mounted) return;
                    setState(() => _pending = list);
                  } catch (e) {
                    setState(() => _err = '$e');
                  } finally {
                    if (mounted) setState(() => _loadPending = false);
                  }
                },
                icon: const Icon(Icons.refresh),
              ),
            ]),
            const SizedBox(height: 8),
            if (_loadPending) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Expanded(
              child: _pending.isEmpty
                  ? const Center(child: Text('Keine Pending-Anmeldungen.'))
                  : ListView.separated(
                      itemCount: _pending.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final p = _pending[i];
                        return _PendingTile(
                          data: p,
                          api: _api,
                          onApprove: () async {
                            try {
                              await _api.approvePending(p.email, lang: p.lang);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Freigabe ausgelöst für ${p.email}.')),
                              );
                              await _refreshAll();
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text('Fehler: $e')));
                            }
                          },
                          onReject: () async {
                            final ok = await _confirm('Anmeldung ablehnen',
                                'Soll ${p.email} wirklich abgelehnt und gelöscht werden?');
                            if (ok != true) return;
                            try {
                              await _api.deleteUser(p.email);
                              if (mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(content: Text('Eintrag gelöscht: ${p.email}')));
                                await _refreshAll();
                              }
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text('Fehler: $e')));
                            }
                          },
                          onLoadComplaints: () => _loadComplaintsDetailed(p.email),
                          complaints: _complaints[p.email],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.people),
              const SizedBox(width: 8),
              const Text('Aktive Nutzer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                tooltip: 'Neu laden',
                onPressed: _loadUsers ? null : () async {
                  setState(() => _loadUsers = true);
                  try {
                    final list = await _api.fetchUsers();
                    if (!mounted) return;
                    setState(() => _users = list);
                  } catch (e) {
                    setState(() => _err = '$e');
                  } finally {
                    if (mounted) setState(() => _loadUsers = false);
                  }
                },
                icon: const Icon(Icons.refresh),
              ),
            ]),
            const SizedBox(height: 8),
            if (_loadUsers) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Expanded(
              child: _users.isEmpty
                  ? const Center(child: Text('Keine aktiven Nutzer.'))
                  : ListView.separated(
                      itemCount: _users.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final u = _users[i];
                        return _UserTile(
                          data: u,
                          api: _api,
                          onDelete: () async {
                            final ok = await _confirm('Nutzer löschen',
                                'Soll der aktive Nutzer ${u.email} wirklich gelöscht werden?');
                            if (ok != true) return;
                            try {
                              await _api.deleteUser(u.email);
                              if (mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(content: Text('Nutzer gelöscht: ${u.email}')));
                                await _refreshAll();
                                await _refreshOpen();
                              }
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text('Fehler: $e')));
                            }
                          },
                          onLoadComplaints: () => _loadComplaintsDetailed(u.email),
                          complaints: _complaints[u.email],
                          onClosedFromEditor: () {
                            // wenn im Editor geschlossen → Liste „Offen“ aktualisieren
                            _refreshOpen();
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpenPanel(List<String> companies) {
    // ggf. gefilterte Liste bilden
    final list = (_filterCompany == 'Alle Firmen')
        ? _openComplaints
        : _openComplaints
            .where((c) => (_companyByEmail(c.email) ?? '') == _filterCompany)
            .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.receipt_long),
              const SizedBox(width: 8),
              const Text('Offene Reklamationen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              DropdownButton<String>(
                value: _filterCompany,
                onChanged: (v) => setState(() => _filterCompany = v ?? 'Alle Firmen'),
                items: companies.map((s) => DropdownMenuItem<String>(value: s, child: Text(s))).toList(),
              ),
              const SizedBox(width: 8),
              if (_loadOpen)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              IconButton(
                tooltip: 'Neu laden',
                onPressed: _loadOpen ? null : _refreshOpen,
                icon: const Icon(Icons.refresh),
              ),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Keine offenen Reklamationen.'))
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final c = list[i];
                        return _ComplaintEditor(
                          api: _api,
                          c: c,
                          companyHint: _companyByEmail(c.email),
                          onClosed: () {
                            // Sofort aus der Offenen-Liste entfernen
                            setState(() {
                              _openComplaints.removeWhere((x) => x.ticket == c.ticket);
                            });
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRepsPanel() {
    final fnCtrl = TextEditingController();
    final lnCtrl = TextEditingController();
    final mailCtrl = TextEditingController();
    String region = kRepRegions.first;
    bool busy = false;

    void _composeMail(String to, {String? subject, String? body}) {
      if (to.trim().isEmpty) return;
      final url = 'mailto:$to'
          '?subject=${Uri.encodeComponent(subject ?? 'Anfrage / DFS-DIAMON') }'
          '&body=${Uri.encodeComponent(body ?? 'Guten Tag,\n\nich melde mich als Ihr Ansprechpartner.\n\nBeste Grüße\nDFS-DIAMON GmbH') }';
      html.window.open(url, '_self');
    }

    Future<void> _save({String? id}) async {
      if (busy) return;
      setState(() => busy = true);
      try {
        final rep = await _api.upsertRep(
          id: id,
          firstName: fnCtrl.text.trim(),
          lastName: lnCtrl.text.trim(),
          email: mailCtrl.text.trim(),
          region: region,
        );
        // Felder leeren, Liste neu
        fnCtrl.clear(); lnCtrl.clear(); mailCtrl.clear(); region = kRepRegions.first;
        await _refreshReps();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gespeichert: ${rep.displayName}')),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
        }
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }

    Future<void> _edit(Rep r) async {
      fnCtrl.text = r.firstName;
      lnCtrl.text = r.lastName;
      mailCtrl.text = r.email;
      region = r.region.isNotEmpty ? r.region : kRepRegions.first;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Vertreter bearbeiten'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: fnCtrl, decoration: const InputDecoration(labelText: 'Vorname')),
                const SizedBox(height: 8),
                TextField(controller: lnCtrl, decoration: const InputDecoration(labelText: 'Nachname')),
                const SizedBox(height: 8),
                TextField(controller: mailCtrl, decoration: const InputDecoration(labelText: 'E-Mail')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: region,
                  decoration: const InputDecoration(labelText: 'Länderbereich'),
                  items: kRepRegions
                      .map((s) => DropdownMenuItem<String>(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => region = v ?? kRepRegions.first,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () async { Navigator.pop(ctx); await _save(id: r.id); },
              child: const Text('Speichern'),
            ),
          ],
        ),
      );
    }

    Future<void> _confirmDelete(Rep r) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Vertreter löschen'),
          content: Text('Soll ${r.displayName} wirklich gelöscht werden?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
          ],
        ),
      );
      if (ok == true) {
        try {
          await _api.deleteRep(r.id);
          await _refreshReps();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gelöscht: ${r.displayName}')));
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
          }
        }
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.badge_outlined),
              const SizedBox(width: 8),
              const Text('Vertreterverwaltung', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (_loadReps)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              IconButton(
                tooltip: 'Neu laden',
                onPressed: _loadReps ? null : _refreshReps,
                icon: const Icon(Icons.refresh),
              ),
            ]),
            const SizedBox(height: 12),

            // --- Anlegen-Form ---
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Neuen Vertreter anlegen', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 240,
                        child: TextField(controller: fnCtrl, decoration: const InputDecoration(labelText: 'Vorname')),
                      ),
                      SizedBox(
                        width: 260,
                        child: TextField(controller: lnCtrl, decoration: const InputDecoration(labelText: 'Nachname')),
                      ),
                      SizedBox(
                        width: 300,
                        child: TextField(controller: mailCtrl, decoration: const InputDecoration(labelText: 'E-Mail')),
                      ),
                      SizedBox(
                        width: 300,
                        child: DropdownButtonFormField<String>(
                          value: region,
                          decoration: const InputDecoration(labelText: 'Länderbereich'),
                          items: kRepRegions
                              .map((s) => DropdownMenuItem<String>(value: s, child: Text(s)))
                              .toList(),
                          onChanged: (v) => region = v ?? kRepRegions.first,
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.save_outlined),
                          onPressed: busy ? null : () => _save(),
                          label: const Text('Anlegen'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // --- Liste ---
            Expanded(
              child: _reps.isEmpty
                  ? const Center(child: Text('Keine Vertreter angelegt.'))
                  : ListView.separated(
                      itemCount: _reps.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final r = _reps[i];
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                          title: Text(r.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${r.email} • ${r.region}'),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              IconButton(
                                tooltip: 'E-Mail schreiben',
                                icon: const Icon(Icons.mail_outline),
                                onPressed: () => _composeMail(
                                  r.email,
                                  subject: 'DFS-DIAMON – Anfrage / ${r.displayName}',
                                  body: 'Guten Tag ${r.displayName},\n\n— Nachricht —\n\nBeste Grüße\nDFS-DIAMON GmbH',
                                ),
                              ),
                              IconButton(
                                tooltip: 'Bearbeiten',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _edit(r),
                              ),
                              IconButton(
                                tooltip: 'Löschen',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _confirmDelete(r),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

// ===================================================================
// Menü-Kachel
// ===================================================================
class _AdminTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final Widget? badge;

  const _AdminTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 44, color: color),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (badge == null) return card;

    return Stack(
      children: [
        card,
        Positioned(right: 10, top: 10, child: badge!),
      ],
    );
  }
}

class _BusyDot extends StatelessWidget {
  const _BusyDot();
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 14,
      height: 14,
      child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
  }
}

// ===================================================================
// Kleine Hilfswidgets
// ===================================================================
class _Field extends StatelessWidget {
  final String label;
  final String value;
  const _Field({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('$label:', style: muted),
          Text(value.isEmpty ? '—' : value),
        ],
      ),
    );
  }
}

class _PendingTile extends StatefulWidget {
  final PendingUser data;
  final AdminApi api;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final Future<void> Function() onLoadComplaints;
  final _ComplaintsResult? complaints;
  const _PendingTile({
    required this.data,
    required this.api,
    required this.onApprove,
    required this.onReject,
    required this.onLoadComplaints,
    required this.complaints,
  });

  @override
  State<_PendingTile> createState() => _PendingTileState();
}

class _PendingTileState extends State<_PendingTile> {
  bool _expanded = false;

  void _showAddress() {
    final d = widget.data;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adressdaten (Pending)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Field(label: 'Firma', value: d.company),
            _Field(label: 'Kontakt', value: d.contact),
            const SizedBox(height: 6),
            _Field(label: 'Straße', value: d.street),
            _Field(label: 'PLZ/Ort', value: '${d.zip} ${d.city}'.trim()),
            _Field(label: 'Land', value: d.country),
            const SizedBox(height: 6),
            _Field(label: 'Telefon', value: d.phone),
            _Field(label: 'E-Mail', value: d.email),
            _Field(label: 'Sprache', value: d.lang.toUpperCase()),
            _Field(label: 'Erstellt', value: d.createdAt ?? '—'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final title = d.company.isNotEmpty ? d.company : d.email;
    final subtitle = (d.country.isNotEmpty) ? d.country : '${d.zip} ${d.city}'.trim();

    return Column(
      children: [
        ListTile(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle.isEmpty ? '—' : subtitle),
          trailing: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(tooltip: 'Adressdaten', onPressed: _showAddress, icon: const Icon(Icons.info_outline)),
              IconButton(
                tooltip: 'Reklamationen anzeigen',
                onPressed: () {
                  setState(() => _expanded = !_expanded);
                  if (_expanded) widget.onLoadComplaints();
                },
                icon: Icon(_expanded ? Icons.expand_less : Icons.receipt_long),
              ),
              FilledButton(onPressed: widget.onApprove, child: const Text('Freigeben')),
              OutlinedButton(onPressed: widget.onReject, child: const Text('Ablehnen')),
            ],
          ),
        ),
        if (_expanded)
          _ComplaintsDetailList(
            result: widget.complaints,
            api: widget.api,
            onClosed: () {},
            companyHint: d.company,
          ),
        const Divider(height: 1),
      ],
    );
  }
}

class _UserTile extends StatefulWidget {
  final ActiveUser data;
  final AdminApi api;
  final Future<void> Function() onDelete;
  final Future<void> Function() onLoadComplaints;
  final _ComplaintsResult? complaints;
  final VoidCallback onClosedFromEditor;
  const _UserTile({
    required this.data,
    required this.api,
    required this.onDelete,
    required this.onLoadComplaints,
    required this.complaints,
    required this.onClosedFromEditor,
  });

  @override
  State<_UserTile> createState() => _UserTileState();
}

class _UserTileState extends State<_UserTile> {
  bool _expanded = false;

  void _showAddress() {
    final d = widget.data;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adressdaten'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Field(label: 'Firma', value: d.company),
            _Field(label: 'Kontakt', value: d.contact),
            const SizedBox(height: 6),
            _Field(label: 'Straße', value: d.street),
            _Field(label: 'PLZ/Ort', value: '${d.zip} ${d.city}'.trim()),
            _Field(label: 'Land', value: d.country),
            const SizedBox(height: 6),
            _Field(label: 'Telefon', value: d.phone),
            _Field(label: 'E-Mail', value: d.email),
            _Field(label: 'Sprache', value: d.lang.toUpperCase()),
            _Field(label: 'Aktiv seit', value: d.createdAt ?? '—'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final title = d.company.isNotEmpty ? d.company : d.email;
    final subtitle = d.country.isNotEmpty ? d.country : d.email;

    return Column(
      children: [
        ListTile(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle),
              if (d.selfDeleted) const SizedBox(height: 4),
              if (d.selfDeleted)
                const Text('Account durch User gelöscht!', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            ],
          ),
          trailing: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(tooltip: 'Adressdaten', onPressed: _showAddress, icon: const Icon(Icons.info_outline)),
              IconButton(
                tooltip: 'Reklamationen anzeigen',
                onPressed: () {
                  setState(() => _expanded = !_expanded);
                  if (_expanded) widget.onLoadComplaints();
                },
                icon: Icon(_expanded ? Icons.expand_less : Icons.receipt_long),
              ),
              OutlinedButton(onPressed: () async => widget.onDelete(), child: const Text('Löschen')),
            ],
          ),
        ),
        if (_expanded)
          _ComplaintsDetailList(
            result: widget.complaints,
            api: widget.api,
            onClosed: widget.onClosedFromEditor,
            companyHint: d.company,
          ),
        const Divider(height: 1),
      ],
    );
  }
}

class _ComplaintsDetailList extends StatelessWidget {
  final _ComplaintsResult? result;
  final AdminApi api;
  final VoidCallback onClosed;
  final String? companyHint;
  const _ComplaintsDetailList({
    required this.result,
    required this.api,
    required this.onClosed,
    this.companyHint,
  });

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('Noch nicht geladen.'),
      );
    }
    if (r.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: LinearProgressIndicator(),
      );
    }
    if (r.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('Fehler beim Laden: ${r.error}', style: const TextStyle(color: Colors.red)),
      );
    }
    if (r.items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('Keine Reklamationen gefunden.'),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const Text('Reklamationen (Details):', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ...r.items.map((c) => _ComplaintEditor(api: api, c: c, onClosed: onClosed, companyHint: companyHint)).toList(),
        ],
      ),
    );
  }
}

// ===================================================================
// Modelle
// ===================================================================
class PendingUser {
  final String email;
  final String company;
  final String contact;
  final String street;
  final String zip;
  final String city;
  final String country;
  final String phone;
  final String lang;
  final String? createdAt;

  PendingUser({
    required this.email,
    required this.company,
    required this.contact,
    required this.street,
    required this.zip,
    required this.city,
    required this.country,
    required this.phone,
    required this.lang,
    required this.createdAt,
  });

  factory PendingUser.fromJson(Map<String, dynamic> j) => PendingUser(
        email: j['email'] ?? '',
        company: j['company'] ?? '',
        contact: j['contact'] ?? '',
        street: j['street'] ?? '',
        zip: j['zip'] ?? '',
        city: j['city'] ?? '',
        country: j['country'] ?? '',
        phone: j['phone'] ?? '',
        lang: (j['lang'] ?? 'de').toString(),
        createdAt: j['createdAt']?.toString(),
      );

  factory PendingUser.empty() => PendingUser(
        email: '',
        company: '',
        contact: '',
        street: '',
        zip: '',
        city: '',
        country: '',
        phone: '',
        lang: 'de',
        createdAt: '',
      );
}

class ActiveUser {
  final String email;
  final String company;
  final String contact;
  final String street;
  final String zip;
  final String city;
  final String country;
  final String phone;
  final String lang;
  final String? createdAt;
  final bool selfDeleted;

  ActiveUser({
    required this.email,
    required this.company,
    required this.contact,
    required this.street,
    required this.zip,
    required this.city,
    required this.country,
    required this.phone,
    required this.lang,
    required this.createdAt,
    required this.selfDeleted,
  });

  factory ActiveUser.fromJson(Map<String, dynamic> j) => ActiveUser(
        email: j['email'] ?? '',
        company: j['company'] ?? '',
        contact: j['contact'] ?? '',
        street: j['street'] ?? '',
        zip: j['zip'] ?? '',
        city: j['city'] ?? '',
        country: j['country'] ?? '',
        phone: j['phone'] ?? '',
        lang: (j['lang'] ?? 'de').toString(),
        createdAt: j['createdAt']?.toString(),
        selfDeleted: (j['selfDeleted'] ?? false) == true,
      );

  factory ActiveUser.empty() => ActiveUser(
        email: '',
        company: '',
        contact: '',
        street: '',
        zip: '',
        city: '',
        country: '',
        phone: '',
        lang: 'de',
        createdAt: '',
        selfDeleted: false,
      );
}

class AdminComplaint {
  final String ticket;
  final String email;
  final DateTime createdAt;
  final DateTime updatedAt;
  int status;               // 1..6 (mutierbar für UI)
  String? decision;         // 'accepted' | 'rejected' | null
  String? reportLink;

  // komplettes Payload vom Backend (für Wunsch etc.)
  final Map<String, dynamic>? payload;

  AdminComplaint({
    required this.ticket,
    required this.email,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    this.decision,
    this.reportLink,
    this.payload,
  });

  factory AdminComplaint.fromJson(Map<String, dynamic> j) {
    DateTime _dt(v) {
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v is String && v.trim().isNotEmpty) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }
    int _i(v) => (v is num) ? v.toInt() : int.tryParse('${v ?? ''}') ?? 1;

    return AdminComplaint(
      ticket: (j['ticket'] ?? '').toString(),
      email: (j['email'] ?? '').toString(),
      createdAt: _dt(j['createdAt']),
      updatedAt: _dt(j['updatedAt']),
      status: _i(j['status']),
      decision: (j['decision'] == null || (j['decision'] as String?)?.isEmpty == true)
          ? null
          : j['decision']?.toString(),
      reportLink: j['reportLink']?.toString(),
      payload: (j['payload'] is Map)
          ? (j['payload'] as Map).cast<String, dynamic>()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'ticket': ticket,
        'email': email,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'status': status,
        'decision': decision,
        'reportLink': reportLink,
        'payload': payload,
      };

  String get handlingLabel {
    final p = payload;
    if (p == null) return '—';
    final v = p['handling'] ?? p['Wunsch'] ?? '';
    final s = v.toString().trim();
    return s.isEmpty ? '—' : s; // Ersatz | Gutschrift | Nacharbeit
  }
}

class Rep {
  final String id;        // vom Backend vergeben oder email-basiert
  final String firstName;
  final String lastName;
  final String email;
  final String region;

  Rep({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.region,
  });

  factory Rep.fromJson(Map<String, dynamic> j) => Rep(
    id: (j['id'] ?? j['email'] ?? '').toString(),
    firstName: (j['firstName'] ?? '').toString(),
    lastName: (j['lastName'] ?? '').toString(),
    email: (j['email'] ?? '').toString(),
    region: (j['region'] ?? '').toString(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'region': region,
  };

  String get displayName {
    final fn = firstName.trim();
    final ln = lastName.trim();
    if (fn.isEmpty && ln.isEmpty) return email;
    return [fn, ln].where((s) => s.isNotEmpty).join(' ');
  }
}

// ===================================================================
// Status-/Decision-Listen + Details-Dialog + Editor
// ===================================================================
const kStatusItems = <Map<String, dynamic>>[
  {'label': 'Eingegegangen', 'value': 1},
  {'label': 'In Bearbeitung', 'value': 2},
  {'label': 'Rückfrage erforderlich', 'value': 3},
  {'label': 'In Nacharbeit', 'value': 5},
  {'label': 'Abgeschlossen', 'value': 6},
];

const kDecisionItems = <Map<String, String>>[
  {'label': '—', 'value': ''}, // keine Entscheidung
  {'label': 'Angenommen', 'value': 'accepted'},
  {'label': 'Abgelehnt', 'value': 'rejected'},
];

// Vertreter – Regionen (fixe Auswahl)
const kRepRegions = <String>[
  'Lateinamerika',
  'Osteuropa',
  'Italien',
  'China & Mongolei & Philippinen',
  'Mittlerer Osten & Afrika',
];

class _ComplaintDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> data; // vollständiges Complaint-Objekt
  const _ComplaintDetailsDialog({required this.data});

  @override
  Widget build(BuildContext context) {
    final payload = (data['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    final files = (data['files'] as List?)?.cast<Map>() ?? const [];
    final ticket = (data['ticket'] ?? '').toString();

    Widget row(String l, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 160, child: Text(l, style: const TextStyle(fontWeight: FontWeight.w600))),
              Expanded(child: Text(v.isEmpty ? '—' : v)),
            ],
          ),
        );

    return AlertDialog(
      title: Text('Details – $ticket'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (payload.isEmpty)
                const Text('Keine Payload übermittelt.')
              else ...[
                row('Segment', (payload['segment'] ?? '').toString()),
                row('Artikel', (payload['article'] ?? '').toString()),
                row('Charge', (payload['batch'] ?? '').toString()),
                row('Menge', (payload['qty'] ?? '').toString()),
                row('Ablauf', (payload['expiry'] ?? '').toString()),
                row('Beschreibung', (payload['desc'] ?? '').toString()),
                row('Produkte zurückgeschickt?', (payload['returned'] ?? '').toString()),
                row('Gewünschte Behandlung', (payload['handling'] ?? '').toString()),
                if ((payload['applied'] ?? '') != '')
                  row('Am Patienten angewendet?', (payload['applied'] ?? '').toString()),
                if ((payload['injury'] ?? '') != '')
                  row('Verletzung?', (payload['injury'] ?? '').toString()),
                if ((payload['injuryDesc'] ?? '').toString().trim().isNotEmpty)
                  row('Verletzungsbeschreibung', (payload['injuryDesc'] ?? '').toString()),
              ],
              const SizedBox(height: 10),
              if (files.isNotEmpty) const Text('Dateien:', style: TextStyle(fontWeight: FontWeight.w600)),
              if (files.isNotEmpty)
                ...files.map((f) => Text('- ${f['name'] ?? 'Datei'} (${f['mime'] ?? 'mime'})')).toList(),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen'))],
    );
  }
}

class _ComplaintEditor extends StatefulWidget {
  final AdminApi api;
  final AdminComplaint c;
  final VoidCallback onClosed;
  final String? companyHint;
  const _ComplaintEditor({
    super.key,
    required this.api,
    required this.c,
    required this.onClosed,
    this.companyHint,
  });

  @override
  State<_ComplaintEditor> createState() => _ComplaintEditorState();
}

class _ComplaintEditorState extends State<_ComplaintEditor> {
  final _reportCtrl = TextEditingController();
  bool _busy = false;
  bool _expanded = false;

  int? _status; // 1..6
  String? _decision; // null | accepted | rejected

  @override
  void initState() {
    super.initState();
    _reportCtrl.text = widget.c.reportLink ?? '';
    _status = widget.c.status;
    _decision = widget.c.decision;
  }

  @override
  void dispose() {
    _reportCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveReportLink() async {
    setState(() => _busy = true);
    try {
      final link = _reportCtrl.text.trim();
      final updated = await widget.api.adminComplaintUpdate(
        ticket: widget.c.ticket,
        reportLink: link.isEmpty ? '' : link,
      );
      widget.c.reportLink = updated.reportLink;
      widget.c.status = updated.status;
      widget.c.decision = updated.decision;

      if (updated.status == 6 || updated.decision == 'rejected') {
        widget.onClosed();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report-Link gespeichert.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearReportLink() async {
    setState(() => _busy = true);
    try {
      await widget.api.adminComplaintUpdate(ticket: widget.c.ticket, reportLink: '');
      _reportCtrl.text = '';
      widget.c.reportLink = null;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report-Link entfernt.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveStatusDecision() async {
    if (_status == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Status auswählen.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final updated = await widget.api.adminComplaintUpdate(
        ticket: widget.c.ticket,
        status: _status,
        decision: _decision ?? '',
      );
      widget.c.status = updated.status;
      widget.c.decision = updated.decision;

      if (updated.status == 6 || updated.decision == 'rejected') {
        widget.onClosed();
      }

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Status/Entscheidung gespeichert.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteComplaint() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reklamation löschen'),
        content: Text('Soll Ticket ${widget.c.ticket} wirklich gelöscht werden?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await widget.api.deleteComplaint(widget.c.ticket);
      widget.onClosed();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ticket ${widget.c.ticket} gelöscht.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  String _statusLabel(int v) {
    final m = kStatusItems.firstWhere((e) => e['value'] == v, orElse: () => const {});
    return (m['label'] ?? 'Status $v').toString();
  }

  // --- E-Mail an Kunden ------------------------------------------------
  String _buildMailSubject(AdminComplaint c) {
    final wish = c.handlingLabel == '—' ? '' : ' – ${c.handlingLabel}';
    return '[DFS Complaint ${c.ticket}] Rückfrage zu Ihrer Reklamation$wish';
  }

  String _buildMailBody(AdminComplaint c) {
    final p = c.payload ?? const <String, dynamic>{};
    final company = (widget.companyHint ?? '').trim();
    final greet = company.isNotEmpty ? 'Guten Tag $company,' : 'Guten Tag,';

    String line(String k, Object? v) {
      final s = (v ?? '').toString().trim();
      return s.isEmpty ? '' : '$k: $s\n';
    }

    final sb = StringBuffer()
      ..writeln(greet)
      ..writeln()
      ..writeln('wir haben Ihre Reklamation erhalten und benötigen noch eine kurze Rückmeldung zu einigen Punkten.')
      ..writeln('Nachfolgend finden Sie die bisherigen Angaben zur schnellen Übersicht:')
      ..writeln()
      ..writeln('— Reklamationsdetails —')
      ..write(line('Ticket', c.ticket))
      ..write(line('Segment', p['segment']))
      ..write(line('Artikel', p['article']))
      ..write(line('Charge', p['batch']))
      ..write(line('Menge', p['qty']))
      ..write(line('Ablaufdatum', p['expiry']))
      ..write(line('Beschreibung', p['desc']))
      ..write(line('Produkte zurückgeschickt', p['returned']))
      ..write(line('Gewünschte Behandlung', p['handling']))
      ..writeln()
      ..writeln('— Interner Bearbeitungsstand —')
      ..write(line('Status', _labelForStatus(c.status)))
      ..write(line('Entscheidung', _labelForDecision(c.decision)))
      ..write(line('Report-Link', c.reportLink))
      ..writeln()
      ..writeln('Können Sie uns bitte folgende Punkte kurz bestätigen/ergänzen?')
      ..writeln('• Sind alle betroffenen Artikel korrekt aufgeführt?')
      ..writeln('• Falls vorhanden: Bitte Bilder/weitere Hinweise beifügen.')
      ..writeln('• Bei Rücksendung: Tracking/Datum?')
      ..writeln()
      ..writeln('Vielen Dank im Voraus! Bei Rückfragen sind wir jederzeit gerne für Sie da.')
      ..writeln()
      ..writeln('Mit freundlichen Grüßen')
      ..writeln('DFS-DIAMON GmbH – Quality Management');

    return sb.toString();
  }

  String _labelForStatus(int s) {
    switch (s) {
      case 1: return 'Eingegangen';
      case 2: return 'In Bearbeitung';
      case 3: return 'Rückfrage erforderlich';
      case 5: return 'In Nacharbeit';
      case 6: return 'Abgeschlossen';
      default: return 'Unbekannt';
    }
  }

  String _labelForDecision(String? d) {
    switch ((d ?? '').trim()) {
      case 'accepted': return 'Angenommen';
      case 'rejected': return 'Abgelehnt';
      case '': return '—';
      default: return d!.trim();
    }
  }

  void _composeMailToCustomer() {
    final to = widget.c.email.trim();
    if (to.isEmpty) return;

    final subject = _buildMailSubject(widget.c);
    final body    = _buildMailBody(widget.c);

    final url = 'mailto:$to'
        '?subject=${Uri.encodeComponent(subject)}'
        '&body=${Uri.encodeComponent(body)}';

    html.window.open(url, '_self');
  }

  @override
  Widget build(BuildContext context) {
    final wish = widget.c.handlingLabel;
    Color wishCol;
    switch (wish) {
      case 'Ersatz':
        wishCol = Colors.indigo;
        break;
      case 'Gutschrift':
        wishCol = Colors.teal;
        break;
      case 'Nacharbeit':
        wishCol = Colors.deepOrange;
        break;
      default:
        wishCol = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kopfzeile (Ticket + Aktionen + rechter Hinweis)
            Row(
              children: [
                Text(
                  'Ticket: ${widget.c.ticket}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),

                // Mail an Kunden
                Tooltip(
                  message: 'E-Mail an Kunden verfassen',
                  child: IconButton(
                    icon: const Icon(Icons.email_outlined),
                    onPressed: _busy ? null : _composeMailToCustomer,
                  ),
                ),
                const SizedBox(width: 8),

                // rechter Hinweis (Firma oder E-Mail)
                Text(
                  (widget.companyHint != null && widget.companyHint!.trim().isNotEmpty)
                      ? 'Firma: ${widget.companyHint}'
                      : 'E-Mail: ${widget.c.email}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Wunsch-Flag
            if (wish != '—')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: wishCol.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: wishCol),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.flag, size: 18),
                    const SizedBox(width: 8),
                    Text('Gewünschte Behandlung: $wish',
                        style: TextStyle(fontWeight: FontWeight.w700, color: wishCol)),
                  ],
                ),
              ),

            // kompakte Anzeige + Expand
            Row(
              children: [
                Text('Status: ${_statusLabel(widget.c.status)}'),
                const SizedBox(width: 12),
                Text('Entscheidung: ${widget.c.decision?.toString() == 'accepted' ? 'Angenommen' : widget.c.decision == 'rejected' ? 'Abgelehnt' : '—'}'),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(_expanded ? Icons.expand_less : Icons.edit),
                  label: Text(_expanded ? 'Bearbeiten schließen' : 'Bearbeiten'),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Details anzeigen',
                  onPressed: () async {
                    try {
                      final raw = await widget.api.fetchComplaintRawByTicket(widget.c.ticket);
                      if (!context.mounted) return;
                      showDialog<void>(
                        context: context,
                        builder: (_) => _ComplaintDetailsDialog(data: raw),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
                    }
                  },
                  icon: const Icon(Icons.info_outline),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Reklamation löschen',
                  onPressed: _deleteComplaint,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),

            if (_expanded) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _status,
                      decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                      items: kStatusItems
                          .map((e) => DropdownMenuItem<int>(
                                value: e['value'] as int,
                                child: Text(e['label'] as String),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _status = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _decision ?? '',
                      decoration: const InputDecoration(labelText: 'Entscheidung', border: OutlineInputBorder()),
                      items: kDecisionItems
                          .map((e) => DropdownMenuItem<String>(
                                value: e['value']!,
                                child: Text(e['label']!),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _decision = (v == null || v.isEmpty) ? null : v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(onPressed: _busy ? null : _saveStatusDecision, child: const Text('Speichern')),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reportCtrl,
                decoration: InputDecoration(
                  labelText: 'Report-Link (optional)',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'Link entfernen',
                    onPressed: _busy ? null : _clearReportLink,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _saveReportLink,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Link speichern'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ===================================================================
// Admin API (Browser, dart:html)
// ===================================================================
class AdminApi {
  String _secret = '';
  void setSecret(String s) => _secret = s;

  String get baseUrl {
    final b = const String.fromEnvironment('API_BASE', defaultValue: '');
    if (b.isNotEmpty) return b;
    return html.window.location.origin;
  }

  Map<String, String> _headersJson() => {
        'Content-Type': 'application/json; charset=utf-8',
        if (_secret.isNotEmpty) 'X-Admin-Secret': _secret,
      };

  Uri _u(String path, [Map<String, String>? q]) {
    final uri = Uri.parse('$baseUrl$path');
    if (q == null || q.isEmpty) return uri;
    return uri.replace(queryParameters: q);
  }

  Future<html.HttpRequest> _request(
    String method,
    String path, {
    Map<String, String>? q,
    Object? body,
  }) async {
    try {
      final res = await html.HttpRequest.request(
        _u(path, q).toString(),
        method: method,
        requestHeaders: _headersJson(),
        sendData: body is String ? body : (body == null ? null : jsonEncode(body)),
        withCredentials: true,
      );
      return res;
    } catch (e) {
      if (e is html.ProgressEvent) {
        final t = e.target;
        if (t is html.HttpRequest) {
          final st = t.status;
          final txt = t.responseText ?? '';
          final stx = t.statusText ?? '';
          throw 'HTTP $st $stx — ${txt.isEmpty ? "Request fehlgeschlagen" : txt}';
        }
      }
      throw e.toString();
    }
  }

  // Pending
  Future<List<PendingUser>> fetchPending() async {
    final res = await _request('GET', '/api/admin/pending');
    if (res.status != 200) throw 'pending GET: HTTP ${res.status} ${res.responseText}';
    final txt = res.responseText ?? '';
    if (txt.trim().isEmpty) return <PendingUser>[];
    final List data = jsonDecode(txt);
    return data.map((e) => PendingUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> approvePending(String email, {String? lang}) async {
    final body = {'email': email, 'action': 'approve', if (lang != null) 'lang': lang};
    final res = await _request('POST', '/api/admin/pending', body: body);
    if (res.status != 200 && res.status != 204) {
      throw 'pending POST approve: HTTP ${res.status} ${res.responseText}';
    }
  }

  Future<void> deleteUser(String email) async {
    // Versuch 1: DELETE mit Query
    try {
      final r1 = await _request('DELETE', '/api/admin/users', q: {'email': email});
      if (r1.status == 200 || r1.status == 204) return;
    } catch (_) {}
    // Versuch 2: DELETE mit Body
    try {
      final r2 = await _request('DELETE', '/api/admin/users', body: {'email': email});
      if (r2.status == 200 || r2.status == 204) return;
    } catch (_) {}
    // Versuch 3: POST action=delete
    final r3 = await _request('POST', '/api/admin/users', body: {'action': 'delete', 'email': email});
    if (r3.status != 200 && r3.status != 204) {
      throw 'users DELETE/POST(delete) failed: HTTP ${r3.status} ${r3.responseText}';
    }
  }

  // Users
  Future<List<ActiveUser>> fetchUsers() async {
    final res = await _request('GET', '/api/admin/users');
    if (res.status != 200) throw 'users GET: HTTP ${res.status} ${res.responseText}';
    final txt = res.responseText ?? '';
    if (txt.trim().isEmpty) return <ActiveUser>[];
    final List data = jsonDecode(txt);
    return data.map((e) => ActiveUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  // Complaints (by email / open)
  Future<List<AdminComplaint>> fetchComplaintsByEmailDetailed(String email) async {
    final res = await _request('GET', '/api/admin/complaints', q: {'email': email, 'details': '1'});
    if (res.status != 200) throw 'complaints email GET: HTTP ${res.status} ${res.responseText}';
    final List data = jsonDecode(res.responseText ?? '[]');
    return data.map((e) => AdminComplaint.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<AdminComplaint>> fetchOpenComplaints() async {
    final res = await _request('GET', '/api/admin/complaints', q: {'open': '1'});
    if (res.status != 200) throw 'open complaints GET: HTTP ${res.status} ${res.responseText}';
    final List data = jsonDecode(res.responseText ?? '[]');
    return data.map((e) => AdminComplaint.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> fetchComplaintRawByTicket(String ticket) async {
    final res = await _request('GET', '/api/admin/complaints', q: {'ticket': ticket});
    if (res.status != 200) {
      throw 'complaint GET by ticket: HTTP ${res.status} ${res.responseText}';
    }
    final Map<String, dynamic> j = jsonDecode(res.responseText ?? '{}');
    return j;
  }

  // Update / Delete
  Future<AdminComplaint> adminComplaintUpdate({
    required String ticket,
    int? status,
    String? decision,
    String? reportLink,
  }) async {
    final body = <String, dynamic>{'ticket': ticket};
    if (status != null) body['status'] = status;
    body['decision'] = decision ?? '';
    if (reportLink != null) body['reportLink'] = reportLink;

    final res = await _request('POST', '/api/admin/complaints', body: body);
    if (res.status != 200) {
      throw 'HTTP ${res.status} ${res.statusText} — ${res.responseText ?? ''}';
    }
    final Map<String, dynamic> j =
        (res.responseText ?? '').trim().isEmpty ? <String, dynamic>{} : jsonDecode(res.responseText!);
    return AdminComplaint.fromJson(j);
  }

  Future<void> deleteComplaint(String ticket) async {
    // 1) DELETE ?ticket=...
    try {
      final r1 = await _request('DELETE', '/api/admin/complaints', q: {'ticket': ticket});
      if (r1.status == 200 || r1.status == 204) return;
    } catch (_) {/* Fallback */}
    // 2) DELETE Body
    final r2 = await _request('DELETE', '/api/admin/complaints', body: {'ticket': ticket});
    if (r2.status != 200 && r2.status != 204) {
      throw 'HTTP ${r2.status} ${r2.statusText} — ${r2.responseText ?? ''}';
    }
  }

  // ---------- Representatives (Vertreter) ----------
  Future<List<Rep>> fetchReps() async {
    final res = await _request('GET', '/api/admin/reps');
    if (res.status != 200) {
      throw 'reps GET: HTTP ${res.status} ${res.responseText}';
    }
    final List data = jsonDecode(res.responseText ?? '[]');
    return data.map((e) => Rep.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  /// upsert: legt an oder aktualisiert (falls id != leer)
  Future<Rep> upsertRep({
    String? id,
    required String firstName,
    required String lastName,
    required String email,
    required String region,
  }) async {
    final body = {
      if (id != null && id.isNotEmpty) 'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'region': region,
    };
    final res = await _request('POST', '/api/admin/reps', body: body);
    if (res.status != 200 && res.status != 201) {
      throw 'reps POST: HTTP ${res.status} ${res.responseText}';
    }
    final Map<String, dynamic> j =
        (res.responseText ?? '').trim().isEmpty ? <String, dynamic>{} : jsonDecode(res.responseText!);
    return Rep.fromJson(j);
  }

  Future<void> deleteRep(String id) async {
    // Query-Variante
    try {
      final r1 = await _request('DELETE', '/api/admin/reps', q: {'id': id});
      if (r1.status == 200 || r1.status == 204) return;
    } catch (_) {}
    // Body-Variante Fallback
    final r2 = await _request('DELETE', '/api/admin/reps', body: {'id': id});
    if (r2.status != 200 && r2.status != 204) {
      throw 'reps DELETE: HTTP ${r2.status} ${r2.responseText}';
    }
  }
 }

// ===================================================================
// interne Hilfs-Resultklasse
// ===================================================================
class _ComplaintsResult {
  final bool loading;
  final String? error;
  final List<AdminComplaint> items;
  _ComplaintsResult._(this.loading, this.error, this.items);
  factory _ComplaintsResult.loading() => _ComplaintsResult._(true, null, const []);
  factory _ComplaintsResult.err(String e) => _ComplaintsResult._(false, e, const []);
  factory _ComplaintsResult.ok(List<AdminComplaint> list) => _ComplaintsResult._(false, null, list);
}
