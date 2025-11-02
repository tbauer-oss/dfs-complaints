import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';

import '../widgets/status_badge.dart'; // für hübsches Status-Badge (bereits vorhanden)
import '../api/client.dart';

/// Admin-Hauptseite mit drei Bereichen: Pending, Users, Offene Reklamationen
class AdminPage extends StatefulWidget {
  final ApiClient api;
  const AdminPage({super.key, required this.api});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

enum _AdminSection { pending, users, openComplaints }

class _AdminPageState extends State<AdminPage> {
  late final AdminApi _api;

  _AdminSection _section = _AdminSection.pending;

  // Shared/Error/Busy
  String? _err;

  // Pending
  bool _loadingPending = false;
  List<PendingUser> _pending = const [];
  final Map<String, ComplaintsResult> _pendingComplaints = {};

  // Users
  bool _loadingUsers = false;
  List<AdminUser> _users = const [];
  final Map<String, ComplaintsResult> _userComplaints = {};

  // Offene Reklamationen
  bool _loadingOpen = false;
  String? _openErr;
  List<AdminComplaint> _openComplaints = const [];

  @override
  void initState() {
    super.initState();
    _api = AdminApi()..setSecret(widget.api.adminSecret ?? '');
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loadingPending = true;
      _loadingUsers = true;
      _loadingOpen = true;
      _err = null;
      _openErr = null;
    });
    try {
      final p = await _api.fetchPending();
      final u = await _api.fetchUsers();
      final all = await _api.fetchAllComplaints(); // für "Offene Reklamationen"
      if (!mounted) return;
      setState(() {
        _pending = p;
        _users = u;
        _openComplaints = _filterOpen(all);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e');
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingPending = false;
        _loadingUsers = false;
        _loadingOpen = false;
      });
    }
  }

  List<AdminComplaint> _filterOpen(List<AdminComplaint> all) {
    // Offen: status != 6 (Abgeschlossen) UND decision != 'rejected'
    // (status 4 ist "Entscheidung" – offen, solange decision==null oder 'accepted' ohne Abschluss;
    // dein Backend setzt bei 'rejected' zudem statusClosed=true Logik)
    return all.where((c) => c.status != 6 && c.decision != 'rejected').toList()
      ..sort((a, b) => (b.updatedAt ?? b.createdAt ?? 0).compareTo(a.updatedAt ?? a.createdAt ?? 0));
  }

  Future<void> _refreshPending() async {
    setState(() => _loadingPending = true);
    try {
      final p = await _api.fetchPending();
      if (!mounted) return;
      setState(() => _pending = p);
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _loadingPending = false);
    }
  }

  Future<void> _refreshUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final u = await _api.fetchUsers();
      if (!mounted) return;
      setState(() => _users = u);
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _loadingUsers = false);
    }
  }

  Future<void> _refreshOpenComplaints() async {
    setState(() { _loadingOpen = true; _openErr = null; });
    try {
      final all = await _api.fetchAllComplaints();
      if (!mounted) return;
      setState(() => _openComplaints = _filterOpen(all));
    } catch (e) {
      if (!mounted) return;
      setState(() => _openErr = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _loadingOpen = false);
    }
  }

  Future<void> _loadComplaintsForEmail(String email, {required bool forPending}) async {
    final key = email.toLowerCase();
    if (forPending) {
      setState(() => _pendingComplaints[key] = ComplaintsResult.loading());
    } else {
      setState(() => _userComplaints[key] = ComplaintsResult.loading());
    }
    try {
      final tickets = await _api.fetchTicketsByEmail(email);
      if (!mounted) return;
      if (forPending) {
        setState(() => _pendingComplaints[key] = ComplaintsResult.ok(tickets));
      } else {
        setState(() => _userComplaints[key] = ComplaintsResult.ok(tickets));
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (forPending) {
        setState(() => _pendingComplaints[key] = ComplaintsResult.err(msg));
      } else {
        setState(() => _userComplaints[key] = ComplaintsResult.err(msg));
      }
    }
  }

  Future<void> _approve(String email, {String? lang}) async {
    try {
      await _api.approvePending(email, lang: lang);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Freigabe ausgelöst für $email.')),
      );
      await _refreshPending();
      await _refreshUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler bei Freigabe: $e')),
      );
    }
  }

  Future<void> _reject(String email) async {
    final ok = await _confirm(
      'Anmeldung ablehnen',
      'Soll $email wirklich abgelehnt werden?\n\nDer Eintrag wird dabei wie beim Löschen vollständig entfernt.',
    );
    if (ok != true) return;

    try {
      await _api.deletePending(email); // echte Pending-Löschung
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eintrag abgelehnt und gelöscht: $email')),
      );
      await _refreshPending();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Ablehnen: $e')),
      );
    }
  }

  Future<void> _deleteUser(String email) async {
    final ok = await _confirm(
      'Nutzer löschen',
      'Soll der Nutzer $email wirklich vollständig gelöscht werden?',
    );
    if (ok != true) return;

    try {
      await _api.deleteUser(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nutzer entfernt: $email')),
      );
      await _refreshUsers();
      await _refreshOpenComplaints(); // falls dadurch offene Fälle “verwaisen”
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Löschen: $e')),
      );
    }
  }

  Future<void> _setComplaintStatus({
    required String ticket,
    int? status,
    String? decision, // 'accepted' | 'rejected' | null
    String? reportLink,
    bool refreshOpen = false,
    bool silent = false,
  }) async {
    try {
      await _api.patchComplaint(ticket: ticket, status: status, decision: decision, reportLink: reportLink);
      if (!mounted) return;
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status für $ticket aktualisiert.')),
        );
      }
      if (refreshOpen) await _refreshOpenComplaints();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Aktualisieren: $e')),
      );
    }
  }

  Future<bool?> _confirm(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adminbereich – DFS Customer Complaint'),
        actions: [
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _sectionButton('Pending', Icons.how_to_reg_outlined, _AdminSection.pending),
                _sectionButton('Kundendatenbank', Icons.people_outline, _AdminSection.users),
                _sectionButton('Offene Reklamationen', Icons.assignment_late_outlined, _AdminSection.openComplaints),
              ],
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildSection(theme),
          ),
        ),
      ),
    );
  }

  Widget _sectionButton(String label, IconData icon, _AdminSection s) {
    final isActive = _section == s;
    return FilledButton.tonalIcon(
      icon: Icon(icon),
      label: Text(label),
      onPressed: isActive ? null : () => setState(() => _section = s),
    );
  }

  Widget _buildSection(ThemeData theme) {
    if (_err != null) {
      return Text(_err!, style: TextStyle(color: theme.colorScheme.error));
    }

    switch (_section) {
      case _AdminSection.pending:
        return _buildPending();
      case _AdminSection.users:
        return _buildUsers();
      case _AdminSection.openComplaints:
        return _buildOpenComplaints();
    }
  }

  // ---------- UI: Pending ----------
  Widget _buildPending() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.how_to_reg_outlined),
                const SizedBox(width: 8),
                const Text('Pending (Freigabe / Ablehnen)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  tooltip: 'Neu laden',
                  onPressed: _loadingPending ? null : _refreshPending,
                  icon: _loadingPending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            const Divider(),
            if (_pending.isEmpty && !_loadingPending) const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Keine offenen Pending-Einträge.'),
            ),
            if (_pending.isNotEmpty)
              Expanded(
                child: ListView.separated(
                  itemCount: _pending.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = _pending[i];
                    final c = _pendingComplaints[d.email.toLowerCase()];
                    return _PendingTile(
                      data: d,
                      complaints: c,
                      onLoadComplaints: () => _loadComplaintsForEmail(d.email, forPending: true),
                      onApprove: () => _approve(d.email, lang: d.lang),
                      onReject: () => _reject(d.email),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------- UI: Users (Kundendatenbank mit Ticketliste & Statusänderung) ----------
  Widget _buildUsers() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.people),
                const SizedBox(width: 8),
                const Text('Aktive Nutzer (Kundendatenbank)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  tooltip: 'Neu laden',
                  onPressed: _loadingUsers ? null : _refreshUsers,
                  icon: _loadingUsers
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            const Divider(),
            if (_users.isEmpty && !_loadingUsers) const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Keine aktiven Nutzer.'),
            ),
            if (_users.isNotEmpty)
              Expanded(
                child: ListView.separated(
                  itemCount: _users.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final u = _users[i];
                    final c = _userComplaints[u.email.toLowerCase()];
                    return _UserTile(
                      data: u,
                      complaints: c,
                      onLoadComplaints: () => _loadComplaintsForEmail(u.email, forPending: false),
                      onDelete: () => _deleteUser(u.email),
                      onSetStatus: ({
                        required String ticket,
                        int? status,
                        String? decision,
                        String? reportLink,
                      }) => _setComplaintStatus(
                        ticket: ticket,
                        status: status,
                        decision: decision,
                        reportLink: reportLink,
                        refreshOpen: true, // falls Ticket dadurch in/offen wird
                        silent: true,
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

  // ---------- UI: Offene Reklamationen ----------
  Widget _buildOpenComplaints() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment_late_outlined),
                const SizedBox(width: 8),
                const Text('Offene Reklamationen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  tooltip: 'Neu laden',
                  onPressed: _loadingOpen ? null : _refreshOpenComplaints,
                  icon: _loadingOpen
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            const Divider(),
            if (_openErr != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_openErr!, style: const TextStyle(color: Colors.red)),
              ),
            if (!_loadingOpen && _openComplaints.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Derzeit keine offenen Reklamationen.'),
              ),
            if (_openComplaints.isNotEmpty)
              Expanded(
                child: ListView.separated(
                  itemCount: _openComplaints.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = _openComplaints[i];
                    return _OpenComplaintTile(
                      data: c,
                      onSetStatus: ({
                        required String ticket,
                        int? status,
                        String? decision,
                        String? reportLink,
                      }) async {
                        await _setComplaintStatus(
                          ticket: ticket,
                          status: status,
                          decision: decision,
                          reportLink: reportLink,
                          refreshOpen: true,
                        );
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
}

// ============================================================================
//  Tiles / Widgets
// ============================================================================

class _PendingTile extends StatefulWidget {
  final PendingUser data;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onLoadComplaints;
  final ComplaintsResult? complaints;
  const _PendingTile({
    required this.data,
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

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return Column(
      children: [
        ListTile(
          title: Text('${d.company}  •  ${d.email}'),
          subtitle: Text('${d.contact} • ${d.country} • ${d.phone} • Sprache: ${d.lang}'),
          trailing: Wrap(
            spacing: 8,
            children: [
              TextButton(onPressed: widget.onLoadComplaints, child: const Text('Tickets anzeigen')),
              FilledButton.icon(
                onPressed: widget.onApprove,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Freigeben'),
              ),
              OutlinedButton.icon(
                onPressed: () async => widget.onReject(),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Ablehnen'),
              ),
              IconButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              ),
            ],
          ),
        ),
        if (_expanded) _ComplaintsView(email: d.email, result: widget.complaints),
        const Divider(height: 1),
      ],
    );
  }
}

class _UserTile extends StatefulWidget {
  final AdminUser data;
  final VoidCallback onLoadComplaints;
  final VoidCallback onDelete;
  final ComplaintsResult? complaints;
  final Future<void> Function({
    required String ticket,
    int? status,
    String? decision,
    String? reportLink,
  }) onSetStatus;

  const _UserTile({
    required this.data,
    required this.onLoadComplaints,
    required this.onDelete,
    required this.complaints,
    required this.onSetStatus,
  });

  @override
  State<_UserTile> createState() => _UserTileState();
}

class _UserTileState extends State<_UserTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return Column(
      children: [
        ListTile(
          title: Text('${d.company}  •  ${d.email}'),
          subtitle: Text('${d.contact} • ${d.country} • ${d.phone} • Sprache: ${d.lang}'),
          trailing: Wrap(
            spacing: 8,
            children: [
              TextButton(onPressed: widget.onLoadComplaints, child: const Text('Tickets anzeigen')),
              OutlinedButton.icon(
                onPressed: () async => widget.onDelete(),
                icon: const Icon(Icons.person_remove_alt_1_outlined),
                label: const Text('Löschen'),
              ),
              IconButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              ),
            ],
          ),
        ),
        if (_expanded) _ComplaintsView(
          email: d.email,
          result: widget.complaints,
          withStatusActions: true,
          onSetStatus: widget.onSetStatus,
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _OpenComplaintTile extends StatefulWidget {
  final AdminComplaint data;
  final Future<void> Function({
    required String ticket,
    int? status,
    String? decision,
    String? reportLink,
  }) onSetStatus;

  const _OpenComplaintTile({
    required this.data,
    required this.onSetStatus,
  });

  @override
  State<_OpenComplaintTile> createState() => _OpenComplaintTileState();
}

class _OpenComplaintTileState extends State<_OpenComplaintTile> {
  bool _busy = false;
  int? _statusSel;
  String? _decisionSel;
  final _reportCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _statusSel = widget.data.status;
    _decisionSel = widget.data.decision;
    _reportCtrl.text = widget.data.reportLink ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.data;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${c.ticket} • ${c.email}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${c.segment} • Artikel: ${c.article} • Menge: ${c.qty ?? '-'}'),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      StatusBadge(status: c.statusLabel), // vorhandenes Widget
                      const SizedBox(width: 8),
                      if (c.decision != null) Text('Decision: ${c.decision}'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: _StatusDropdown(value: _statusSel, onChanged: _busy ? null : (v) => setState(() => _statusSel = v))),
                    const SizedBox(width: 8),
                    Expanded(child: _DecisionDropdown(value: _decisionSel, onChanged: _busy ? null : (v) => setState(() => _decisionSel = v))),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _reportCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Report-Link (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : () async {
                    setState(() => _busy = true);
                    await widget.onSetStatus(
                      ticket: c.ticket,
                      status: _statusSel,
                      decision: _decisionSel,
                      reportLink: _reportCtrl.text.trim().isEmpty ? null : _reportCtrl.text.trim(),
                    );
                    setState(() => _busy = false);
                  },
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: const Text('Speichern'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ComplaintsView extends StatelessWidget {
  final String email;
  final ComplaintsResult? result;

  /// Optional: Admin-Statusaktionen einblenden (für Kundendatenbank)
  final bool withStatusActions;
  final Future<void> Function({
    required String ticket,
    int? status,
    String? decision,
    String? reportLink,
  })? onSetStatus;

  const _ComplaintsView({
    super.key,
    required this.email,
    required this.result,
    this.withStatusActions = false,
    this.onSetStatus,
  });

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null || r.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }
    if (r.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(r.error!, style: const TextStyle(color: Colors.red)),
      );
    }
    if (r.tickets.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Keine Reklamationen gefunden.'),
      );
    }

    // Nur Ticketliste – Details zieht sich der Admin in der Offenen-Liste.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 12, right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reklamationen für $email (${r.tickets.length}):', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: r.tickets.map((t) {
              if (!withStatusActions || onSetStatus == null) {
                return Chip(label: Text(t));
              }
              // Wenn du hier auch sofort Status-Aktionen möchtest, müsste man Details laden;
              // für Übersichtlichkeit belassen wir es hier bei der Ticketliste.
              return InputChip(label: Text(t));
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
//  Modelle & Admin-API (nur was diese Seite benötigt)
// ============================================================================

class PendingUser {
  final String email, company, contact, country, phone;
  final String lang;
  final String? createdAt;
  const PendingUser({
    required this.email,
    required this.company,
    required this.contact,
    required this.country,
    required this.phone,
    required this.lang,
    required this.createdAt,
  });
  factory PendingUser.fromJson(Map j) => PendingUser(
        email: j['email'] ?? '',
        company: j['company'] ?? '',
        contact: j['contact'] ?? '',
        country: j['country'] ?? '',
        phone: j['phone'] ?? '',
        lang: (j['lang'] ?? 'de').toString(),
        createdAt: j['createdAt']?.toString(),
      );
}

class AdminUser {
  final String email, company, contact, country, phone;
  final String lang;
  final String? createdAt;
  const AdminUser({
    required this.email,
    required this.company,
    required this.contact,
    required this.country,
    required this.phone,
    required this.lang,
    required this.createdAt,
  });
  factory AdminUser.fromJson(Map j) => AdminUser(
        email: j['email'] ?? '',
        company: j['company'] ?? '',
        contact: j['contact'] ?? '',
        country: j['country'] ?? '',
        phone: j['phone'] ?? '',
        lang: (j['lang'] ?? 'de').toString(),
        createdAt: j['createdAt']?.toString(),
      );
}

class AdminComplaint {
  final String ticket;
  final String email;
  final String segment;
  final String article;
  final int? qty;
  final int status;           // 1..6
  final String statusLabel;   // vom Backend geliefert
  final String? decision;     // 'accepted' | 'rejected' | null
  final String? reportLink;
  final int? createdAt;
  final int? updatedAt;

  AdminComplaint({
    required this.ticket,
    required this.email,
    required this.segment,
    required this.article,
    required this.qty,
    required this.status,
    required this.statusLabel,
    required this.decision,
    required this.reportLink,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AdminComplaint.fromJson(Map j) => AdminComplaint(
        ticket: j['ticket'] ?? '',
        email: j['email'] ?? '',
        segment: j['segment'] ?? '',
        article: j['article'] ?? '',
        qty: (j['qty'] is num) ? (j['qty'] as num).toInt() : null,
        status: (j['status'] is num) ? (j['status'] as num).toInt() : 1,
        statusLabel: j['statusLabel'] ?? 'Eingegegangen',
        decision: (j['decision'] == null) ? null : j['decision'].toString(),
        reportLink: (j['reportLink'] == null) ? null : j['reportLink'].toString(),
        createdAt: j['createdAt'] is num ? (j['createdAt'] as num).toInt() : null,
        updatedAt: j['updatedAt'] is num ? (j['updatedAt'] as num).toInt() : null,
      );
}

class ComplaintsResult {
  final bool loading;
  final String? error;
  final List<String> tickets;
  ComplaintsResult._(this.loading, this.error, this.tickets);
  factory ComplaintsResult.loading() => ComplaintsResult._(true, null, const []);
  factory ComplaintsResult.err(String e) => ComplaintsResult._(false, e, const []);
  factory ComplaintsResult.ok(List<String> t) => ComplaintsResult._(false, null, t);
}

// ---- Auswahl-Controls für Status/Decision ----

class _StatusDropdown extends StatelessWidget {
  final int? value;
  final ValueChanged<int?>? onChanged;
  const _StatusDropdown({required this.value, required this.onChanged});

  static const _items = <int, String>{
    1: 'Eingegegangen',
    2: 'In Bearbeitung',
    3: 'Rückfrage erforderlich',
    4: 'Entscheidung',
    5: 'In Nacharbeit',
    6: 'Abgeschlossen',
  };

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      value: value,
      onChanged: onChanged,
      decoration: const InputDecoration(
        labelText: 'Status',
        border: OutlineInputBorder(),
      ),
      items: _items.entries
          .map((e) => DropdownMenuItem<int>(value: e.key, child: Text(e.value)))
          .toList(),
    );
  }
}

class _DecisionDropdown extends StatelessWidget {
  final String? value; // 'accepted' | 'rejected' | null
  final ValueChanged<String?>? onChanged;
  const _DecisionDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      onChanged: onChanged,
      decoration: const InputDecoration(
        labelText: 'Entscheidung',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem<String>(value: null, child: Text('—')),
        DropdownMenuItem<String>(value: 'accepted', child: Text('Angenommen')),
        DropdownMenuItem<String>(value: 'rejected', child: Text('Abgelehnt')),
      ],
    );
  }
}

// ============================================================================
//  Admin-API (rein für AdminPage; nutzt dein bestehendes Backend)
// ============================================================================

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
        'X-Admin-Secret': _secret,
      };

  Uri _u(String p, [Map<String, String>? q]) => Uri.parse('$baseUrl$p').replace(queryParameters: q);

  // ---- Pending ----

  Future<List<PendingUser>> fetchPending() async {
    final res = await html.HttpRequest.request(
      _u('/api/admin/pending').toString(),
      method: 'GET',
      requestHeaders: _headersJson(),
      withCredentials: true,
    );
    if (res.status != 200) throw 'pending GET: HTTP ${res.status} ${res.responseText}';
    final List data = jsonDecode(res.responseText ?? '[]');
    return data.map((e) => PendingUser.fromJson(e as Map)).toList();
  }

  Future<void> approvePending(String email, {String? lang}) async {
    final res = await html.HttpRequest.request(
      _u('/api/admin/pending').toString(),
      method: 'POST',
      requestHeaders: _headersJson(),
      sendData: jsonEncode({'email': email, if (lang != null) 'lang': lang}),
      withCredentials: true,
    );
    if (res.status != 200 && res.status != 204) {
      throw 'pending POST: HTTP ${res.status} ${res.responseText}';
    }
  }

  Future<void> deletePending(String email) async {
    // robust: zuerst DELETE, falls nicht erlaubt, POST action=delete als Fallback
    final url = _u('/api/admin/pending').toString();

    // 1) DELETE als Query
    try {
      final r1 = await html.HttpRequest.request(
        '$url?email=${Uri.encodeQueryComponent(email)}',
        method: 'DELETE',
        requestHeaders: _headersJson(),
        withCredentials: true,
      );
      if (r1.status == 200 || r1.status == 204) return;
    } catch (_) {}

    // 2) DELETE Body
    try {
      final r2 = await html.HttpRequest.request(
        url,
        method: 'DELETE',
        requestHeaders: _headersJson(),
        sendData: jsonEncode({'email': email}),
        withCredentials: true,
      );
      if (r2.status == 200 || r2.status == 204) return;
    } catch (_) {}

    // 3) (optional) POST action=delete – falls du es analog users noch pflegen willst
    throw 'pending DELETE failed';
  }

  // ---- Users ----

  Future<List<AdminUser>> fetchUsers() async {
    final res = await html.HttpRequest.request(
      _u('/api/admin/users').toString(),
      method: 'GET',
      requestHeaders: _headersJson(),
      withCredentials: true,
    );
    if (res.status != 200) throw 'users GET: HTTP ${res.status} ${res.responseText}';
    final List data = jsonDecode(res.responseText ?? '[]');
    return data.map((e) => AdminUser.fromJson(e as Map)).toList();
  }

  Future<void> deleteUser(String email) async {
    final url = _u('/api/admin/users').toString();

    // 1) DELETE als Query
    try {
      final res = await html.HttpRequest.request(
        '$url?email=${Uri.encodeQueryComponent(email)}',
        method: 'DELETE',
        requestHeaders: _headersJson(),
        withCredentials: true,
      );
      if (res.status == 200 || res.status == 204) return;
    } catch (_) {}

    // 2) DELETE Body
    try {
      final res = await html.HttpRequest.request(
        url,
        method: 'DELETE',
        requestHeaders: _headersJson(),
        sendData: jsonEncode({'email': email}),
        withCredentials: true,
      );
      if (res.status == 200 || res.status == 204) return;
    } catch (_) {}

    // 3) POST action=delete (Fallback ist bei dir vorhanden)
    final res = await html.HttpRequest.request(
      url,
      method: 'POST',
      requestHeaders: _headersJson(),
      sendData: jsonEncode({'action': 'delete', 'email': email}),
      withCredentials: true,
    );
    if (res.status != 200 && res.status != 204) {
      throw 'users DELETE/POST(delete) failed: HTTP ${res.status} ${res.responseText}';
    }
  }

  // ---- Complaints ----

  Future<List<String>> fetchTicketsByEmail(String email) async {
    final res = await html.HttpRequest.request(
      _u('/api/admin/complaints', {'email': email}).toString(),
      method: 'GET',
      requestHeaders: _headersJson(),
      withCredentials: true,
    );
    if (res.status != 200) throw 'complaints GET: HTTP ${res.status} ${res.responseText}';
    final txt = res.responseText ?? '';
    if (txt.trim().isEmpty) return <String>[];
    final List data = jsonDecode(txt);
    // Backend liefert komplette Objekte – für die kleine Liste nehmen wir nur Tickets:
    return data.map((e) => (e as Map)['ticket'].toString()).toList();
  }

  Future<List<AdminComplaint>> fetchAllComplaints() async {
    final res = await html.HttpRequest.request(
      _u('/api/admin/complaints').toString(),
      method: 'GET',
      requestHeaders: _headersJson(),
      withCredentials: true,
    );
    if (res.status != 200) throw 'complaints GET: HTTP ${res.status} ${res.responseText}';
    final List data = jsonDecode(res.responseText ?? '[]');
    return data.map((e) => AdminComplaint.fromJson(e as Map)).toList();
  }

  Future<void> patchComplaint({
    required String ticket,
    int? status,
    String? decision, // 'accepted' | 'rejected' | null
    String? reportLink,
  }) async {
    final res = await html.HttpRequest.request(
      _u('/api/admin/complaints').toString(),
      method: 'PATCH',
      requestHeaders: _headersJson(),
      sendData: jsonEncode({
        'ticket': ticket,
        if (status != null) 'status': status,
        if (decision != null) 'decision': decision, // null = entfernen → hier einfach weglassen
        if (reportLink != null) 'reportLink': reportLink,
      }),
      withCredentials: true,
    );
    if (res.status != 200) throw 'complaints PATCH: HTTP ${res.status} ${res.responseText}';
  }
}
