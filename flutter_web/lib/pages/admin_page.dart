import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../api/client.dart';

class AdminPage extends StatefulWidget {
  final ApiClient api;
  const AdminPage({super.key, required this.api});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  late final AdminApi _api;

  bool _loadingPending = false;
  bool _loadingUsers = false;
  bool _loadingOpen = false;

  String? _fatalErr; // Ungültiges/missing Secret -> blockiert
  String? _err;      // Nicht-blockierende Fehlermeldungen

  List<PendingUser> _pending = [];
  List<ActiveUser> _users = [];
  List<AdminComplaint> _openComplaints = [];

  // E-Mail -> geladene Reklamationen (Details)
  final Map<String, _ComplaintsResult> _complaints = {};

  @override
  void initState() {
    super.initState();
    _api = AdminApi();

    // 1) Primär: aus dem ApiClient, der von main.dart übergeben wird
    String secret = widget.api.adminSecret ?? '';

    // 2) Fallback: aus localStorage lesen – aber bitte den richtigen Key "dfs_admin"
    if (secret.isEmpty) {
      secret = html.window.localStorage['dfs_admin'] ?? '';
    }

    _api.setSecret(secret);

    if (secret.isEmpty) {
      _fatalErr = 'Kein Admin-Secret gefunden. Bitte über den Admin-Button (Startseite) öffnen.';
      return;
    }

    _refreshAll();
    _refreshOpenComplaints();
  }

  Future<void> _refreshAll() async {
    setState(() {
      _err = null;
      _loadingPending = true;
      _loadingUsers = true;
    });
    try {
      final p = _api.fetchPending();
      final u = _api.fetchUsers();
      final both = await Future.wait([p, u]);
      if (!mounted) return;
      setState(() {
        _pending = both[0] as List<PendingUser>;
        _users   = both[1] as List<ActiveUser>;
      });
    } catch (e) {
      // 401 → Secret ungültig
      if (e.toString().contains('401')) {
        setState(() => _fatalErr = 'Admin-Secret ungültig. Bitte erneut über den Admin-Button (Startseite) mit richtigem Secret öffnen.');
      } else {
        setState(() => _err = '$e');
      }
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingPending = false;
        _loadingUsers = false;
      });
    }
  }

  Future<void> _refreshOpenComplaints() async {
    setState(() => _loadingOpen = true);
    try {
      final list = await _api.fetchOpenComplaints();
      if (!mounted) return;
      setState(() => _openComplaints = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _loadingOpen = false);
    }
  }

  Future<void> _approve(String email, {String? lang}) async {
    try {
      await _api.approvePending(email, lang: lang);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Freigabe ausgelöst für $email.')),
      );
      await _refreshAll();
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
      await _api.deleteUser(email); // identische Logik wie Löschen
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eintrag abgelehnt und gelöscht: $email')),
      );
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Ablehnen: $e')),
      );
    }
  }

  Future<void> _deleteUser(String email) async {
    final ok = await _confirm('Nutzer löschen', 'Soll der aktive Nutzer $email wirklich gelöscht werden?');
    if (ok != true) return;
    try {
      await _api.deleteUser(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nutzer gelöscht: $email')),
      );
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Löschen: $e')),
      );
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

  Future<bool?> _confirm(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    if (_fatalErr != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Adminbereich – DFS Customer Complaint')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    _fatalErr!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                    child: const Text('Zurück'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Adminbereich – DFS Customer Complaint'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.hourglass_top), text: 'Pending'),
              Tab(icon: Icon(Icons.people), text: 'Aktive Nutzer'),
              Tab(icon: Icon(Icons.receipt_long), text: 'Offene Reklamationen'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Offene Reklamationen neu laden',
              onPressed: _loadingOpen ? null : _refreshOpenComplaints,
              icon: const Icon(Icons.refresh),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (_err != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_err!, style: TextStyle(color: theme.colorScheme.error)),
                    ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildPendingPanel(),
                        _buildUsersPanel(),
                        _buildOpenComplaintsPanel(),
                      ],
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

  // ----- Panels -----

  Widget _buildPendingPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hourglass_top),
                const SizedBox(width: 8),
                const Text('Pending (Freigabe ausstehend)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  tooltip: 'Neu laden',
                  onPressed: _loadingPending ? null : () async {
                    setState(() => _loadingPending = true);
                    try {
                      final list = await _api.fetchPending();
                      if (!mounted) return;
                      setState(() => _pending = list);
                    } catch (e) {
                      if (!mounted) return;
                      setState(() => _err = '$e');
                    } finally {
                      if (!mounted) return;
                      setState(() => _loadingPending = false);
                    }
                  },
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loadingPending) const LinearProgressIndicator(),
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
                          onApprove: () => _approve(p.email, lang: p.lang),
                          onReject: () => _reject(p.email),
                          onLoadComplaints: () => _loadComplaintsDetailed(p.email),
                          complaints: _complaints[p.email],
                          api: _api,
                          // Beim Pending sollen geschlossene Fälle nicht automatisch verschwinden;
                          // daher onClosed leer lassen.
                          onClosedFromEditor: () {},
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
            Row(
              children: [
                const Icon(Icons.people),
                const SizedBox(width: 8),
                const Text('Aktive Nutzer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  tooltip: 'Neu laden',
                  onPressed: _loadingUsers ? null : () async {
                    setState(() => _loadingUsers = true);
                    try {
                      final list = await _api.fetchUsers();
                      if (!mounted) return;
                      setState(() => _users = list);
                    } catch (e) {
                      if (!mounted) return;
                      setState(() => _err = '$e');
                    } finally {
                      if (!mounted) return;
                      setState(() => _loadingUsers = false);
                    }
                  },
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loadingUsers) const LinearProgressIndicator(),
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
                          onDelete: () => _deleteUser(u.email),
                          onLoadComplaints: () => _loadComplaintsDetailed(u.email),
                          complaints: _complaints[u.email],
                          api: _api,
                          onClosedFromEditor: () {
                            // Falls in User-Ansicht ein Fall geschlossen wird, nur globale Offene-Liste updaten:
                            _refreshOpenComplaints();
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

  Widget _buildOpenComplaintsPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long),
                const SizedBox(width: 8),
                const Text('Offene Reklamationen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (_loadingOpen) const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                IconButton(
                  tooltip: 'Neu laden',
                  onPressed: _loadingOpen ? null : _refreshOpenComplaints,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _openComplaints.isEmpty
                  ? const Center(child: Text('Keine offenen Reklamationen.'))
                  : ListView.separated(
                      itemCount: _openComplaints.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final c = _openComplaints[i];
                        return _ComplaintEditor(
                          api: _api,
                          c: c,
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
}

// ---------- UI Hilfs-Widgets ----------

class _Field extends StatelessWidget {
  final String label;
  final String value;
  const _Field({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall;
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('$label:', style: muted),
        Text(value.isEmpty ? '—' : value),
      ],
    );
  }
}

class _PendingTile extends StatefulWidget {
  final PendingUser data;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final Future<void> Function() onLoadComplaints;
  final _ComplaintsResult? complaints;
  final AdminApi api;
  final VoidCallback onClosedFromEditor;

  const _PendingTile({
    required this.data,
    required this.onApprove,
    required this.onReject,
    required this.onLoadComplaints,
    required this.complaints,
    required this.api,
    required this.onClosedFromEditor,
  });

  @override
  State<_PendingTile> createState() => _PendingTileState();
}

class _PendingTileState extends State<_PendingTile> {
  bool _expanded = false;

  void _showAddressDialog() {
    final d = widget.data;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Adressdaten (Pending)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Field(label: 'Firma',   value: d.company),
              _Field(label: 'Kontakt', value: d.contact),
              const SizedBox(height: 6),
              _Field(label: 'Straße',  value: d.street),
              _Field(label: 'PLZ/Ort', value: '${d.zip} ${d.city}'.trim()),
              _Field(label: 'Land',    value: d.country),
              const SizedBox(height: 6),
              _Field(label: 'Telefon', value: d.phone),
              _Field(label: 'E-Mail',  value: d.email),
              _Field(label: 'Sprache', value: d.lang.toUpperCase()),
              _Field(label: 'Erstellt', value: d.createdAt ?? '—'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Schließen'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    // Kompakte Darstellung: Firma + Land (Fallbacks)
    final title = (d.company.isNotEmpty) ? d.company : d.email;
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
              IconButton(
                tooltip: 'Adressdaten anzeigen',
                onPressed: _showAddressDialog,
                icon: const Icon(Icons.info_outline),
              ),
              IconButton(
                tooltip: 'Reklamationen anzeigen',
                onPressed: () {
                  setState(() => _expanded = !_expanded);
                  if (_expanded) widget.onLoadComplaints();
                },
                icon: Icon(_expanded ? Icons.expand_less : Icons.receipt_long),
              ),
              FilledButton(
                onPressed: widget.onApprove,
                child: const Text('Freigeben'),
              ),
              OutlinedButton(
                onPressed: widget.onReject,
                child: const Text('Ablehnen'),
              ),
            ],
          ),
        ),
        if (_expanded)
          _ComplaintsDetailList(
            result: widget.complaints,
            api: widget.api,
            onClosed: widget.onClosedFromEditor,
          ),
        const Divider(height: 1),
      ],
    );
  }
}

class _UserTile extends StatefulWidget {
  final ActiveUser data;
  final Future<void> Function() onDelete;
  final Future<void> Function() onLoadComplaints;
  final _ComplaintsResult? complaints;
  final AdminApi api;
  final VoidCallback onClosedFromEditor;
  const _UserTile({
    required this.data,
    required this.onDelete,
    required this.onLoadComplaints,
    required this.complaints,
    required this.api,
    required this.onClosedFromEditor,
  });

  @override
  State<_UserTile> createState() => _UserTileState();
}

class _UserTileState extends State<_UserTile> {
  bool _expanded = false;
  bool _busy = false;

  void _showAddressDialog() {
    final d = widget.data;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Adressdaten'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Field(label: 'Firma',   value: d.company),
              _Field(label: 'Kontakt', value: d.contact),
              const SizedBox(height: 6),
              _Field(label: 'Straße',  value: d.street),
              _Field(label: 'PLZ/Ort', value: '${d.zip} ${d.city}'.trim()),
              _Field(label: 'Land',    value: d.country),
              const SizedBox(height: 6),
              _Field(label: 'Telefon', value: d.phone),
              _Field(label: 'E-Mail',  value: d.email),
              _Field(label: 'Sprache', value: d.lang.toUpperCase()),
              _Field(label: 'Aktiv seit', value: d.createdAt ?? '—'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Schließen'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final title = (d.company.isNotEmpty) ? d.company : d.email;
    final subtitle = (d.country.isNotEmpty) ? d.country : d.email;

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
                const Text(
                  'Account durch User gelöscht!',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                ),
            ],
          ),
          trailing: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: 'Adressdaten anzeigen',
                onPressed: _showAddressDialog,
                icon: const Icon(Icons.info_outline),
              ),
              IconButton(
                tooltip: 'Reklamationen anzeigen',
                onPressed: () {
                  setState(() => _expanded = !_expanded);
                  if (_expanded) widget.onLoadComplaints();
                },
                icon: Icon(_expanded ? Icons.expand_less : Icons.receipt_long),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        await widget.onDelete();
                        if (mounted) setState(() => _busy = false);
                      },
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Löschen'),
              ),
            ],
          ),
        ),
        if (_expanded)
          _ComplaintsDetailList(
            result: widget.complaints,
            api: widget.api,
            onClosed: widget.onClosedFromEditor,
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
  const _ComplaintsDetailList({
    required this.result,
    required this.api,
    required this.onClosed,
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
          ...r.items.map((c) => _ComplaintEditor(api: api, c: c, onClosed: onClosed)).toList(),
        ],
      ),
    );
  }
}

// ---------- Modelle ----------

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
        selfDeleted: (j['selfDeleted'] ?? false) == true, // 🔴 NEU
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

  AdminComplaint({
    required this.ticket,
    required this.email,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    this.decision,
    this.reportLink,
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
      decision: (j['decision'] == null || (j['decision'] as String?)?.isEmpty == true) ? null : j['decision']?.toString(),
      reportLink: j['reportLink']?.toString(),
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
  };
}

class _ComplaintsResult {
  final bool loading;
  final String? error;
  final List<AdminComplaint> items;
  _ComplaintsResult._(this.loading, this.error, this.items);
  factory _ComplaintsResult.loading() => _ComplaintsResult._(true, null, const []);
  factory _ComplaintsResult.err(String e) => _ComplaintsResult._(false, e, const []);
  factory _ComplaintsResult.ok(List<AdminComplaint> list) => _ComplaintsResult._(false, null, list);
}

// ---------- Admin-API Helper ----------
class AdminApi {
  String _secret = '';

  void setSecret(String s) { _secret = s; }

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

  // ---- Pending ----
  Future<List<PendingUser>> fetchPending() async {
    final res = await html.HttpRequest.request(
      _u('/api/admin/pending').toString(),
      method: 'GET',
      requestHeaders: _headersJson(),
      withCredentials: true,
    );
    if (res.status != 200) throw 'pending GET: HTTP ${res.status} ${res.responseText}';
    final txt = res.responseText ?? '';
    if (txt.trim().isEmpty) return <PendingUser>[];
    final List data = jsonDecode(txt);
    return data.map((e) => PendingUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> approvePending(String email, {String? lang}) async {
    final body = jsonEncode({'email': email, 'action': 'approve', if (lang != null) 'lang': lang});
    final res = await html.HttpRequest.request(
      _u('/api/admin/pending').toString(),
      method: 'POST',
      requestHeaders: _headersJson(),
      sendData: body,
      withCredentials: true,
    );
    if (res.status != 200 && res.status != 204) {
      throw 'pending POST approve: HTTP ${res.status} ${res.responseText}';
    }
  }

  Future<void> deleteUser(String email) async {
    final urlQ = _u('/api/admin/users', {'email': email}).toString();
    final url  = _u('/api/admin/users').toString();

    // 1) DELETE ?email=...
    try {
      final res = await html.HttpRequest.request(
        urlQ, method: 'DELETE', requestHeaders: _headersJson(), withCredentials: true,
      );
      if (res.status == 200 || res.status == 204) return;
    } catch (_) {}

    // 2) DELETE Body
    try {
      final res = await html.HttpRequest.request(
        url, method: 'DELETE', requestHeaders: _headersJson(), sendData: jsonEncode({'email': email}), withCredentials: true,
      );
      if (res.status == 200 || res.status == 204) return;
    } catch (_) {}

    // 3) POST action=delete
    final res = await html.HttpRequest.request(
      url, method: 'POST', requestHeaders: _headersJson(), sendData: jsonEncode({'action': 'delete', 'email': email}), withCredentials: true,
    );
    if (res.status != 200 && res.status != 204) {
      throw 'users DELETE/POST(delete) failed: HTTP ${res.status} ${res.responseText}';
    }
  }

  Future<List<ActiveUser>> fetchUsers() async {
    final res = await html.HttpRequest.request(
      _u('/api/admin/users').toString(),
      method: 'GET',
      requestHeaders: _headersJson(),
      withCredentials: true,
    );
    if (res.status != 200) throw 'users GET: HTTP ${res.status} ${res.responseText}';
    final txt = res.responseText ?? '';
    if (txt.trim().isEmpty) return <ActiveUser>[];
    final List data = jsonDecode(txt);
    return data.map((e) => ActiveUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ---- Complaints (neu/erweitert) ----

  // Detaillierte Liste für Kundendatenbank
  Future<List<AdminComplaint>> fetchComplaintsByEmailDetailed(String email) async {
    final res = await html.HttpRequest.request(
      _u('/api/admin/complaints', {'email': email, 'details': '1'}).toString(),
      method: 'GET',
      requestHeaders: _headersJson(),
      withCredentials: true,
    );
    if (res.status != 200) throw 'complaints email GET: HTTP ${res.status}';
    final List data = jsonDecode(res.responseText ?? '[]');
    return data.map((e) => AdminComplaint.fromJson(e as Map<String, dynamic>)).toList();
  }

  // Nur offene Reklamationen (für dritten Tab)
  Future<List<AdminComplaint>> fetchOpenComplaints() async {
    final res = await html.HttpRequest.request(
      _u('/api/admin/complaints', {'open': '1'}).toString(),
      method: 'GET',
      requestHeaders: _headersJson(),
      withCredentials: true,
    );
    if (res.status != 200) throw 'open complaints GET: HTTP ${res.status}';
    final List data = jsonDecode(res.responseText ?? '[]');
    return data.map((e) => AdminComplaint.fromJson(e as Map<String, dynamic>)).toList();
  }

  // Einzel-Complaint (roh) per Ticket (inkl. payload)
  Future<Map<String, dynamic>> fetchComplaintRawByTicket(String ticket) async {
    final res = await html.HttpRequest.request(
      _u('/api/admin/complaints', {'ticket': ticket}).toString(),
      method: 'GET',
      requestHeaders: _headersJson(),
      withCredentials: true, // wir senden nur X-Admin-Secret
    );
    if (res.status != 200) {
      throw 'complaint GET by ticket: HTTP ${res.status} ${res.responseText}';
    }
    final Map<String, dynamic> j = jsonDecode(res.responseText ?? '{}');
    return j;
  }

  // Status/Decision/Report-Link aktualisieren
  Future<AdminComplaint> updateComplaint({
    required String ticket,
    int? status,
    String? decision,
    String? reportLink,
  }) async {
    final body = <String, dynamic>{ 'ticket': ticket };
    if (status != null) body['status'] = status;
    if (decision != null) body['decision'] = decision;
    if (reportLink != null) body['reportLink'] = reportLink;

    final res = await html.HttpRequest.request(
      _u('/api/admin/complaints').toString(),
      method: 'POST',
      requestHeaders: _headersJson(),
      sendData: jsonEncode(body),
      withCredentials: true,
    );
    if (res.status != 200) {
      throw 'complaint update: HTTP ${res.status} ${res.responseText}';
    }
    final Map<String, dynamic> j = jsonDecode(res.responseText ?? '{}');
    return AdminComplaint.fromJson(j);
  }

  // Reklamation löschen (Admin)
  Future<void> deleteComplaint(String ticket) async {
    // Versuch 1: DELETE ?ticket=...
    try {
      final res = await html.HttpRequest.request(
        _u('/api/admin/complaints', {'ticket': ticket}).toString(),
        method: 'DELETE',
        requestHeaders: _headersJson(),
        withCredentials: true,
      );
      if (res.status == 200 || res.status == 204) return;
    } catch (_) {}
    // Fallback: DELETE mit Body
    final res = await html.HttpRequest.request(
      _u('/api/admin/complaints').toString(),
      method: 'DELETE',
      requestHeaders: _headersJson(),
      sendData: jsonEncode({'ticket': ticket}),
      withCredentials: true,
    );
    if (res.status != 200 && res.status != 204) {
      throw 'complaint DELETE failed: HTTP ${res.status} ${res.responseText}';
    }
  }
}

// ---------- Status-/Decision-Editor ----------

const kStatusItems = <Map<String, dynamic>>[
  {'label': 'Eingegegangen',          'value': 1},
  {'label': 'In Bearbeitung',         'value': 2},
  {'label': 'Rückfrage erforderlich', 'value': 3},
  {'label': 'Entscheidung',           'value': 4},
  {'label': 'In Nacharbeit',          'value': 5},
  {'label': 'Abgeschlossen',          'value': 6},
];

const kDecisionItems = <Map<String, String>>[
  {'label': '—',          'value': ''},          // nicht senden -> null
  {'label': 'Angenommen', 'value': 'accepted'},
  {'label': 'Abgelehnt',  'value': 'rejected'},
];

class _ComplaintDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> data; // vollständiges Complaint-Objekt (inkl. payload)
  const _ComplaintDetailsDialog({required this.data});

  @override
  Widget build(BuildContext context) {
    final payload = (data['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    final files   = (data['files'] as List?)?.cast<Map>() ?? const [];
    final ticket  = (data['ticket'] ?? '').toString();

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
                row('Charge',  (payload['batch'] ?? '').toString()),
                row('Menge',   (payload['qty'] ?? '').toString()),
                row('Ablauf',  (payload['expiry'] ?? '').toString()),
                row('Beschreibung', (payload['desc'] ?? '').toString()),
              ],
              const SizedBox(height: 10),
              if (files.isNotEmpty) const Text('Dateien:', style: TextStyle(fontWeight: FontWeight.w600)),
              if (files.isNotEmpty)
                ...files.map((f) => Text('- ${f['name'] ?? 'Datei'} (${f['mime'] ?? 'mime'})')).toList(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen')),
      ],
    );
  }
}

class _ComplaintEditor extends StatefulWidget {
  final AdminApi api;
  final AdminComplaint c;
  final VoidCallback onClosed; // aufgerufen, wenn der Fall aus "Offene" verschwinden soll

  const _ComplaintEditor({
    required this.api,
    required this.c,
    required this.onClosed,
  });

  @override
  State<_ComplaintEditor> createState() => _ComplaintEditorState();
}

class _ComplaintEditorState extends State<_ComplaintEditor> {
  bool _busy = false;
  late int _status;
  String? _decision;
  final _reportCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _status = widget.c.status;
    _decision = widget.c.decision;
    _reportCtrl.text = widget.c.reportLink ?? '';
  }

  bool get _isNowClosed {
    // Abgeschlossen oder (Entscheidung + rejected)
    return _status == 6 || (_status == 4 && _decision == 'rejected');
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Ticket: ${c.ticket}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('Kunde: ${c.email}'),
                Text('Erstellt: ${c.createdAt.toIso8601String().split(".").first}'),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<int>(
                  value: _status,
                  onChanged: _busy ? null : (v) => setState(() => _status = v ?? _status),
                  items: [
                    for (final it in kStatusItems)
                      DropdownMenuItem(value: it['value'] as int, child: Text(it['label'] as String)),
                  ],
                ),
                if (_status == 4)
                  DropdownButton<String>(
                    value: _decision ?? '',
                    onChanged: _busy ? null : (v) => setState(() => _decision = (v ?? '').isEmpty ? null : v),
                    items: [
                      for (final it in kDecisionItems)
                        DropdownMenuItem(value: it['value'], child: Text(it['label']!)),
                    ],
                  ),
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _reportCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Report-Link (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),

                TextButton.icon(
                  onPressed: _busy ? null : () async {
                    try {
                      final raw = await widget.api.fetchComplaintRawByTicket(c.ticket);
                      if (!context.mounted) return;
                      await showDialog(
                        context: context,
                        builder: (_) => _ComplaintDetailsDialog(data: raw),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Details laden fehlgeschlagen: $e')),
                      );
                    }
                  },
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Details'),
                ),

                // SPEICHERN
                ElevatedButton.icon(
                  onPressed: _busy ? null : () async {
                    setState(() => _busy = true);
                    try {
                      final updated = await widget.api.adminComplaintUpdate(
                        ticket: c.ticket,
                        status: _status,
                        decision: _decision,
                        reportLink: _reportCtrl.text.trim().isEmpty ? '' : _reportCtrl.text.trim(),
                      );
                      final link = _reportCtrl.text.trim();
                      await widget.api.adminComplaintUpdate(
                        ticket: c.ticket,
                        reportLink: link.isEmpty ? '' : link, // "" => löschen
                        // ggf. status / decision mitgeben
                      );
                      setState(() {
                        _status = updated.status;
                        _decision = updated.decision;
                      });
                      if (_status == 6 || (_status == 4 && _decision == 'rejected')) {
                        widget.onClosed(); // falls jetzt „geschlossen“, sofort aus Liste entfernen
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Status aktualisiert.')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Fehler: $e')),
                      );
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Speichern'),
                ),

                // ← HIER NEU: LÖSCHEN (siehe Block oben)
                TextButton.icon(
                  onPressed: _busy ? null : () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Reklamation löschen'),
                        content: Text('Ticket ${c.ticket} wirklich endgültig löschen?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
                        ],
                      ),
                    );
                    if (ok != true) return;

                    setState(() => _busy = true);
                    try {
                      await widget.api.deleteComplaint(c.ticket);
                      // Aus der Liste entfernen (Panel "Offene Reklamationen")
                      widget.onClosed();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Ticket ${c.ticket} gelöscht.')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Löschen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
