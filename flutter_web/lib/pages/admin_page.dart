// lib/pages/admin_page.dart
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';

// ------------------------------------------------------
// AdminPage – eigenständig (Modelle + AdminApi inklusive)
// ------------------------------------------------------

class AdminPage extends StatefulWidget {
  // Hinweis: ApiClient wird hier nicht benötigt; Signatur bleibt kompatibel.
  final Object? api;
  const AdminPage({super.key, this.api});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final AdminApi _api = AdminApi();

  bool _loadingOpen = false;
  bool _loadingUsers = false;
  String? _err;

  // Daten
  List<AdminComplaint> _open = [];
  List<ActiveUser> _users = [];

  // Filter (Firma)
  String _filterCompany = 'Alle Firmen';

  @override
  void initState() {
    super.initState();
    _refreshUsers();
    _refreshOpen();
  }

  Future<void> _refreshUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final list = await _api.fetchUsers();
      setState(() => _users = list);
    } catch (e) {
      setState(() => _err = 'Benutzer konnten nicht geladen werden: $e');
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  Future<void> _refreshOpen() async {
    setState(() => _loadingOpen = true);
    try {
      final list = await _api.fetchOpenComplaints();
      setState(() => _open = list);
    } catch (e) {
      setState(() => _err = 'Reklamationen konnten nicht geladen werden: $e');
    } finally {
      if (mounted) setState(() => _loadingOpen = false);
    }
  }

  String? _companyByEmail(String email) {
    final e = email.trim().toLowerCase();
    for (final u in _users) {
      if (u.email.trim().toLowerCase() == e) return (u.company.trim().isEmpty ? null : u.company.trim());
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final companies = <String>{};
    for (final u in _users) {
      if (u.company.trim().isNotEmpty) companies.add(u.company.trim());
    }
    final companyOptions = ['Alle Firmen', ...companies.toList()..sort()];

    final list = (_filterCompany == 'Alle Firmen')
        ? _open
        : _open.where((c) => (_companyByEmail(c.email) ?? '') == _filterCompany).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adminbereich – DFS Customer Complaint'),
        actions: [
          if (_loadingUsers || _loadingOpen)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          IconButton(
            tooltip: 'Neu laden',
            onPressed: _loadingOpen ? null : () async {
              await _refreshUsers();
              await _refreshOpen();
            },
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_err!, style: const TextStyle(color: Colors.red)),
              ),
            Row(
              children: [
                const Icon(Icons.filter_alt_outlined),
                const SizedBox(width: 8),
                const Text('Firma:'),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _filterCompany,
                  items: companyOptions
                      .map((c) => DropdownMenuItem<String>(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _filterCompany = v ?? 'Alle Firmen'),
                ),
                const Spacer(),
                const Text('Offene Reklamationen', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loadingOpen
                  ? const Center(child: CircularProgressIndicator())
                  : (list.isEmpty
                      ? const Center(child: Text('Keine offenen Reklamationen.'))
                      : ListView.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            final c = list[i];
                            return _ComplaintTileCompact(
                              c: c,
                              companyHint: _companyByEmail(c.email),
                              onOpenEditor: () async {
                                await showDialog<void>(
                                  context: context,
                                  builder: (_) => Dialog(
                                    insetPadding: const EdgeInsets.all(16),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 880),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: _ComplaintEditor(
                                          api: _api,
                                          c: c,
                                          companyHint: _companyByEmail(c.email),
                                          onClosed: () {
                                            setState(() {
                                              _open.removeWhere((x) => x.ticket == c.ticket);
                                            });
                                            Navigator.of(context, rootNavigator: true).maybePop();
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        )),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------
// Kompakte Karte (Listenansicht)
// ------------------------------------------------------

class _ComplaintTileCompact extends StatelessWidget {
  final AdminComplaint c;
  final String? companyHint;
  final VoidCallback onOpenEditor;

  const _ComplaintTileCompact({
    super.key,
    required this.c,
    required this.onOpenEditor,
    this.companyHint,
  });

  String get handlingLabel {
    final p = c.payload;
    if (p == null) return '—';
    final v = p['handling'] ?? p['Wunsch'] ?? '';
    final s = v.toString().trim();
    return s.isEmpty ? '—' : s;
  }

  Color _statusColor(int s, String? decision) {
    switch (s) {
      case 1: return Colors.blue;
      case 2: return Colors.amber.shade800;
      case 3: return Colors.orange;
      case 5: return Colors.amber;
      case 6: return Colors.green;
      default:
        // 4 = „Entscheidung“ – farblich je nach decision
        if (decision == 'accepted') return Colors.lightGreen;
        if (decision == 'rejected') return Colors.red;
        return Colors.grey;
    }
  }

  String _statusText(int s, String? decision) {
    switch (s) {
      case 1: return 'Eingegegangen';
      case 2: return 'In Bearbeitung';
      case 3: return 'Rückfrage erforderlich';
      case 5: return 'In Nacharbeit';
      case 6: return 'Abgeschlossen';
      default:
        if (decision == 'accepted') return 'Angenommen';
        if (decision == 'rejected') return 'Abgelehnt';
        return 'Entscheidung';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusText = _statusText(c.status, c.decision);
    final statusColor = _statusColor(c.status, c.decision);
    final rightLabel = (companyHint != null && companyHint!.trim().isNotEmpty)
        ? 'Firma: ${companyHint!}'
        : 'E-Mail: ${c.email}';

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        title: Row(
          children: [
            Text('Ticket: ${c.ticket}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(rightLabel, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Status
              _chip('Status: $statusText', statusColor),
              // Entscheidung
              if ((c.decision ?? '').isNotEmpty)
                _chip('Entscheidung: ${c.decision == 'accepted' ? 'Angenommen' : 'Abgelehnt'}',
                    c.decision == 'accepted' ? Colors.green : Colors.red),
              // Wunsch
              if (handlingLabel != '—')
                _chip('Wunsch: $handlingLabel', switch (handlingLabel) {
                  'Ersatz'      => Colors.indigo,
                  'Gutschrift'  => Colors.teal,
                  'Nacharbeit'  => Colors.deepOrange,
                  _              => Colors.grey,
                }),
            ],
          ),
        ),
        trailing: FilledButton.icon(
          onPressed: onOpenEditor,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Bearbeiten / Details'),
        ),
      ),
    );
  }

  Widget _chip(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.withOpacity(0.12),
          border: Border.all(color: c, width: 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: TextStyle(color: c, fontWeight: FontWeight.w600)),
      );
}

// ------------------------------------------------------
// Editor-Dialog (Details + Aktionen)
// ------------------------------------------------------

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
  bool _busy = false;

  int? _status;
  String? _decision;
  final _reportCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _status = widget.c.status;
    _decision = widget.c.decision;
    _reportCtrl.text = widget.c.reportLink ?? '';
  }

  @override
  void dispose() {
    _reportCtrl.dispose();
    super.dispose();
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

      // Falls durch Entscheidung/Status geschlossen → onClosed
      if (updated.status == 6 || updated.decision == 'rejected') {
        widget.onClosed();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Status/Entscheidung gespeichert.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveReport() async {
    setState(() => _busy = true);
    try {
      final link = _reportCtrl.text.trim();
      final updated = await widget.api.adminComplaintUpdate(
        ticket: widget.c.ticket,
        reportLink: link.isEmpty ? '' : link,
      );
      widget.c.reportLink = updated.reportLink;
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

  Future<void> _clearReport() async {
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

  Future<void> _deleteComplaint() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reklamation löschen'),
        content: Text('Ticket ${widget.c.ticket} wirklich löschen?\nDieser Vorgang kann nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(
            style: ButtonStyle(backgroundColor: WidgetStateProperty.all(Colors.red)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await widget.api.deleteComplaint(widget.c.ticket);
      widget.onClosed();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reklamation gelöscht.')));
        Navigator.of(context, rootNavigator: true).maybePop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Löschen fehlgeschlagen: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final payload = c.payload ?? const <String, dynamic>{};
    final files = c.files;

    Widget row(String l, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 200, child: Text(l, style: const TextStyle(fontWeight: FontWeight.w600))),
              Expanded(child: Text(v.isEmpty ? '—' : v)),
            ],
          ),
        );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ticket: ${c.ticket}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Text('Kunde: ${widget.companyHint ?? c.email}'),
          const Divider(height: 20),

          // Payload-Details
          const Text('Details aus der Meldung', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (payload.isEmpty)
            const Text('Keine Payload übermittelt.')
          else ...[
            row('Segment', (payload['segment'] ?? '').toString()),
            row('Artikel', (payload['article'] ?? '').toString()),
            row('Charge', (payload['batch'] ?? '').toString()),
            row('Menge', (payload['qty'] ?? '').toString()),
            row('Ablauf', (payload['expiry'] ?? '').toString()),
            row('Beschreibung', (payload['desc'] ?? '').toString()),
            if ((payload['applied'] ?? '').toString().trim().isNotEmpty)
              row('Am Patienten angewendet?', (payload['applied'] ?? '').toString()),
            if ((payload['injury'] ?? '').toString().trim().isNotEmpty)
              row('Verletzung?', (payload['injury'] ?? '').toString()),
            if ((payload['injuryDesc'] ?? '').toString().trim().isNotEmpty)
              row('Verletzungsbeschreibung', (payload['injuryDesc'] ?? '').toString()),
            row('Produkte zurückgeschickt?', (payload['returned'] ?? '').toString()),
            row('Gewünschte Behandlung', (payload['handling'] ?? '').toString()),
          ],
          const SizedBox(height: 10),
          if (files.isNotEmpty) ...[
            const Text('Dateien:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            ...files.map((f) => Text('- ${f.name} (${f.mime})')).toList(),
          ],

          const Divider(height: 24),

          // Status / Entscheidung
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _status,
                  decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('Eingegegangen')),
                    DropdownMenuItem(value: 2, child: Text('In Bearbeitung')),
                    DropdownMenuItem(value: 3, child: Text('Rückfrage erforderlich')),
                    DropdownMenuItem(value: 5, child: Text('In Nacharbeit')),
                    DropdownMenuItem(value: 6, child: Text('Abgeschlossen')),
                    // (4 ist „Entscheidung“, wird über decision abgebildet)
                  ],
                  onChanged: (v) => setState(() => _status = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _decision ?? '',
                  decoration: const InputDecoration(labelText: 'Entscheidung', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('—')),
                    DropdownMenuItem(value: 'accepted', child: Text('Angenommen')),
                    DropdownMenuItem(value: 'rejected', child: Text('Abgelehnt')),
                  ],
                  onChanged: (v) => setState(() => _decision = (v == null || v.isEmpty) ? null : v),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _busy ? null : _saveStatusDecision,
                child: const Text('Speichern'),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Report-Link
          TextField(
            controller: _reportCtrl,
            decoration: InputDecoration(
              labelText: 'Report-Link (optional)',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Link entfernen',
                onPressed: _busy ? null : _clearReport,
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _saveReport,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Link speichern'),
          ),

          const SizedBox(height: 16),
          // Löschen
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : _deleteComplaint,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Reklamation löschen'),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------
// Modelle
// ------------------------------------------------------

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
        email: (j['email'] ?? '').toString(),
        company: (j['company'] ?? '').toString(),
        contact: (j['contact'] ?? '').toString(),
        street: (j['street'] ?? '').toString(),
        zip: (j['zip'] ?? '').toString(),
        city: (j['city'] ?? '').toString(),
        country: (j['country'] ?? '').toString(),
        phone: (j['phone'] ?? '').toString(),
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
        email: (j['email'] ?? '').toString(),
        company: (j['company'] ?? '').toString(),
        contact: (j['contact'] ?? '').toString(),
        street: (j['street'] ?? '').toString(),
        zip: (j['zip'] ?? '').toString(),
        city: (j['city'] ?? '').toString(),
        country: (j['country'] ?? '').toString(),
        phone: (j['phone'] ?? '').toString(),
        lang: (j['lang'] ?? 'de').toString(),
        createdAt: j['createdAt']?.toString(),
        selfDeleted: (j['selfDeleted'] ?? false) == true,
      );
}

class AdminComplaint {
  final String ticket;
  final String email;
  final DateTime createdAt;
  final DateTime updatedAt;
  int status;               // 1..6 – UI mutierbar
  String? decision;         // 'accepted' | 'rejected' | null
  String? reportLink;

  final Map<String, dynamic>? payload;
  final List<_FileInfo> files;

  AdminComplaint({
    required this.ticket,
    required this.email,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    required this.decision,
    required this.reportLink,
    required this.payload,
    required this.files,
  });

  factory AdminComplaint.fromJson(Map<String, dynamic> j) {
    DateTime _dt(v) {
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v is String && v.trim().isNotEmpty) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    final payload = (j['payload'] is Map)
        ? (j['payload'] as Map).cast<String, dynamic>()
        : null;

    final List<_FileInfo> files = <_FileInfo>[];
    final rawFiles = j['files'];
    if (rawFiles is List) {
      for (final f in rawFiles) {
        if (f is Map) {
          files.add(_FileInfo(
            name: (f['name'] ?? 'Datei').toString(),
            mime: (f['mime'] ?? 'application/octet-stream').toString(),
          ));
        }
      }
    }

    return AdminComplaint(
      ticket: (j['ticket'] ?? '').toString(),
      email: (j['email'] ?? '').toString(),
      createdAt: _dt(j['createdAt']),
      updatedAt: _dt(j['updatedAt']),
      status: (j['status'] is num) ? (j['status'] as num).toInt() : int.tryParse('${j['status'] ?? 1}') ?? 1,
      decision: (j['decision'] == null || (j['decision'].toString().trim().isEmpty))
          ? null
          : j['decision'].toString(),
      reportLink: j['reportLink']?.toString(),
      payload: payload,
      files: files,
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
        'files': files.map((f) => {'name': f.name, 'mime': f.mime}).toList(),
      };
}

class _FileInfo {
  final String name;
  final String mime;
  _FileInfo({required this.name, required this.mime});
}

// ------------------------------------------------------
// Admin API (Browser, dart:html)
// ------------------------------------------------------

class AdminApi {
  String get baseUrl {
    final b = const String.fromEnvironment('API_BASE', defaultValue: '');
    if (b.isNotEmpty) return b;
    return html.window.location.origin;
  }

  Map<String, String> _headersJson() => {
        'Content-Type': 'application/json; charset=utf-8',
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
    final res = await html.HttpRequest.request(
      _u(path, q).toString(),
      method: method,
      requestHeaders: _headersJson(),
      sendData: body is String ? body : (body == null ? null : jsonEncode(body)),
      withCredentials: true,
    );
    return res;
  }

  // Nutzer
  Future<List<ActiveUser>> fetchUsers() async {
    final res = await _request('GET', '/api/admin/users');
    if (res.status != 200) {
      throw 'users GET: HTTP ${res.status} ${res.responseText}';
    }
    final txt = res.responseText ?? '';
    if (txt.trim().isEmpty) return <ActiveUser>[];
    final List data = jsonDecode(txt);
    return data.map((e) => ActiveUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  // Offene Reklamationen (ohne E-Mail-Filter)
  Future<List<AdminComplaint>> fetchOpenComplaints() async {
    final res = await _request('GET', '/api/admin/complaints', q: {'open': '1'});
    if (res.status != 200) throw 'open complaints GET: HTTP ${res.status}';
    final List data = jsonDecode(res.responseText ?? '[]');
    return data.map((e) => AdminComplaint.fromJson(e as Map<String, dynamic>)).toList();
  }

  // Update
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
    final Map<String, dynamic> j = (res.responseText ?? '').trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(res.responseText!);
    return AdminComplaint.fromJson(j);
  }

  // Löschen
  Future<void> deleteComplaint(String ticket) async {
    // Versuch 1: DELETE ?ticket=...
    try {
      final r1 = await _request('DELETE', '/api/admin/complaints', q: {'ticket': ticket});
      if (r1.status == 200 || r1.status == 204) return;
    } catch (_) {}
    // Fallback: DELETE mit Body
    final r2 = await _request('DELETE', '/api/admin/complaints', body: {'ticket': ticket});
    if (r2.status != 200 && r2.status != 204) {
      throw 'HTTP ${r2.status} ${r2.statusText} — ${r2.responseText ?? ''}';
    }
  }
}