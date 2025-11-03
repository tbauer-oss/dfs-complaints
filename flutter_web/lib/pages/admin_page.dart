import 'dart:convert';
import 'package:flutter/material.dart';
import '../api/client.dart'; // enthält ApiClient, AdminApi, AdminComplaint usw.
import '../models/user.dart'; // enthält ActiveUser, PendingUser (anpassen, falls anders benannt)

// =====================================================
// ==================== ADMIN PAGE =====================
// =====================================================

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

  String? _fatalErr;
  String? _err;

  List<PendingUser> _pending = [];
  List<ActiveUser> _users = [];
  List<AdminComplaint> _openComplaints = [];

  final Map<String, _ComplaintsResult> _complaints = {};

  @override
  void initState() {
    super.initState();
    _api = AdminApi();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _refreshPending(),
      _refreshUsers(),
      _refreshOpenComplaints(),
    ]);
  }

  Future<void> _refreshPending() async {
    setState(() => _loadingPending = true);
    try {
      final list = await _api.listPending();
      setState(() => _pending = list);
    } catch (e) {
      _err = 'Fehler beim Laden der Pending-User: $e';
    } finally {
      setState(() => _loadingPending = false);
    }
  }

  Future<void> _refreshUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final list = await _api.listActive();
      setState(() => _users = list);
    } catch (e) {
      _err = 'Fehler beim Laden der Benutzer: $e';
    } finally {
      setState(() => _loadingUsers = false);
    }
  }

  Future<void> _refreshOpenComplaints() async {
    setState(() => _loadingOpen = true);
    try {
      final list = await _api.listOpenComplaints();
      setState(() => _openComplaints = list);
    } catch (e) {
      _err = 'Fehler beim Laden der Reklamationen: $e';
    } finally {
      setState(() => _loadingOpen = false);
    }
  }

  String? _companyByEmail(String email) {
    try {
      final match = _users.firstWhere((u) => u.email == email);
      return match.company;
    } catch (_) {
      return null;
    }
  }

  // =====================================================
  // =============== PANEL: OFFENE REKLAS ================
  // =====================================================

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
                if (_loadingOpen)
                  const Padding(
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
                        return _ComplaintTileCompact(
                          c: c,
                          companyHint: _companyByEmail(c.email),
                          onOpenEditor: () async {
                            await showDialog<void>(
                              context: context,
                              builder: (_) => Dialog(
                                insetPadding: const EdgeInsets.all(16),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 780),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: _ComplaintEditor(
                                      api: _api,
                                      c: c,
                                      onClosed: () {
                                        setState(() {
                                          _openComplaints.removeWhere((x) => x.ticket == c.ticket);
                                        });
                                        Navigator.of(context, rootNavigator: true).maybePop();
                                      },
                                      companyHint: _companyByEmail(c.email),
                                    ),
                                  ),
                                ),
                              ),
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

  @override
  Widget build(BuildContext context) {
    if (_fatalErr != null) {
      return Center(child: Text(_fatalErr!, style: const TextStyle(color: Colors.red)));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adminbereich'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Expanded(child: _buildOpenComplaintsPanel()),
          ],
        ),
      ),
    );
  }
}

// =====================================================
// =============== KOMPAKTE REKLAMATIONSKARTE ==========
// =====================================================

class _ComplaintTileCompact extends StatelessWidget {
  final AdminComplaint c;
  final String? companyHint;
  final VoidCallback onOpenEditor;

  const _ComplaintTileCompact({
    Key? key,
    required this.c,
    required this.onOpenEditor,
    this.companyHint,
  }) : super(key: key);

  Color _statusColor(int s, String? decision) {
    switch (s) {
      case 1:
        return Colors.blue;
      case 2:
        return Colors.amber.shade800;
      case 3:
        return Colors.orange;
      case 4:
        return (decision == 'rejected')
            ? Colors.red
            : (decision == 'accepted' ? Colors.lightGreen : Colors.grey);
      case 5:
        return Colors.amber;
      case 6:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _statusText(int s, String? decision) {
    switch (s) {
      case 1:
        return 'Eingegegangen';
      case 2:
        return 'In Bearbeitung';
      case 3:
        return 'Rückfrage erforderlich';
      case 4:
        if (decision == 'rejected') return 'Abgelehnt';
        if (decision == 'accepted') return 'Angenommen';
        return 'Entscheidung';
      case 5:
        return 'In Nacharbeit';
      case 6:
        return 'Abgeschlossen';
      default:
        return 'Unbekannt';
    }
  }

  String get handlingLabel {
    final p = c.payload;
    if (p == null) return '—';
    final v = p['handling'] ?? p['Wunsch'] ?? '';
    final s = v.toString().trim();
    return s.isEmpty ? '—' : s;
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  border: Border.all(color: statusColor, width: 1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('Status: $statusText',
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w600)),
              ),
              if ((c.decision ?? '').isNotEmpty)
                Builder(
                  builder: (_) {
                    final dec = c.decision!;
                    final decText = (dec == 'accepted') ? 'Angenommen' : 'Abgelehnt';
                    final decColor = (dec == 'accepted') ? Colors.green : Colors.red;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: decColor.withOpacity(0.12),
                        border: Border.all(color: decColor, width: 1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('Entscheidung: $decText',
                          style: TextStyle(color: decColor, fontWeight: FontWeight.w600)),
                    );
                  },
                ),
              if (handlingLabel != '—')
                Builder(
                  builder: (_) {
                    Color col;
                    switch (handlingLabel) {
                      case 'Ersatz':
                        col = Colors.indigo;
                        break;
                      case 'Gutschrift':
                        col = Colors.teal;
                        break;
                      case 'Nacharbeit':
                        col = Colors.deepOrange;
                        break;
                      default:
                        col = Colors.grey;
                    }
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: col.withOpacity(0.12),
                        border: Border.all(color: col, width: 1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('Wunsch: $handlingLabel',
                          style: TextStyle(color: col, fontWeight: FontWeight.w600)),
                    );
                  },
                ),
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
}

// =====================================================
// ================== REKLAMATION EDITOR ===============
// =====================================================

class _ComplaintEditor extends StatefulWidget {
  final AdminApi api;
  final AdminComplaint c;
  final VoidCallback onClosed;
  final String? companyHint;

  const _ComplaintEditor({
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

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ticket: ${c.ticket}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Kunde: ${widget.companyHint ?? c.email}'),
          const Divider(),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : () {},
                icon: const Icon(Icons.save_outlined),
                label: const Text('Speichern'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Reklamation löschen'),
                            content: Text(
                                'Ticket ${c.ticket} wirklich löschen?\nDieser Vorgang kann nicht rückgängig gemacht werden.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Abbrechen'),
                              ),
                              FilledButton(
                                style: ButtonStyle(
                                  backgroundColor: WidgetStateProperty.all(Colors.red),
                                ),
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Löschen'),
                              ),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        setState(() => _busy = true);
                        try {
                          await widget.api.deleteComplaint(c.ticket);
                          widget.onClosed();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Reklamation gelöscht.')),
                            );
                            Navigator.of(context, rootNavigator: true).maybePop();
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Reklamation löschen'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =====================================================
// ================== INTERNES MODEL ===================
// =====================================================

class _ComplaintsResult {
  final bool loading;
  final String? error;
  final List<AdminComplaint> items;
  const _ComplaintsResult(this.loading, this.error, this.items);

  factory _ComplaintsResult.loading() => const _ComplaintsResult(true, null, []);
  factory _ComplaintsResult.ok(List<AdminComplaint> list) =>
      _ComplaintsResult(false, null, list);
  factory _ComplaintsResult.err(String e) => _ComplaintsResult(false, e, []);
}