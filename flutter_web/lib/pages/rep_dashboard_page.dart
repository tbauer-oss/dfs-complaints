import 'package:flutter/material.dart';
import '../api/client.dart';
import 'rep_profile_page.dart';
import 'dart:html' as html;
import '../l10n/app_localizations.dart';

// ---- L10n-Helper (top-level) ----
extension _L10nX on BuildContext {
  AppLocalizations get t => AppLocalizations.of(this)!;
}

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
      await widget.api.repLogout();
      if (!mounted) return true;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.session_expired_login_again)),
      );
      Navigator.of(context).popUntil((r) => r.isFirst);
      return true;
    }
    return false;
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
      if (handled) return;
      setState(() => _err = '$e');
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
        final t = ctx.t;

        Future<void> save() async {
          if (saving) return;
          final mail = ctrl.text.trim().toLowerCase();
          if (mail.isEmpty || !mail.contains('@')) {
            locErr = t.correctMail;
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
            locErr = '${ctx.t.error ?? 'Fehler'}: $e';
            saving = false;
            (ctx as Element).markNeedsBuild();
          }
        }

        return AlertDialog(
          title: Text(t.addCustomer),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                decoration: InputDecoration(labelText: t.customerMail ?? 'Kunden-E-Mail'),
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
              child: Text(t.cancel),
            ),
            ElevatedButton(
              onPressed: saving ? null : save,
              child: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t.add),
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
      final handled = await _handleUnauthorized(e);
      if (!mounted) return;
      if (!handled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.t.error ?? 'Fehler'}: $e')),
        );
      }
    }
  }

  Future<void> _decideComplaint(String ticket, bool approve) async {
    try {
      await widget.api.repDecision(ticket: ticket, approve: approve);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(approve ? context.t.decision_accepted : context.t.decision_rejected)),
      );
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.t.error ?? 'Fehler'}: $e')),
      );
    }
  }

  Future<void> _logout() async {
    await widget.api.repLogout();
    try {
      html.window.localStorage.remove('dfs_mode');
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (Route<dynamic> r) => false);
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  // --- Statistik-Helfer ---
  Map<int, int> _statusCounts() {
    final counts = <int, int>{};
    for (final c in _complaints) {
      final s = int.tryParse(c['status'].toString()) ?? 0;
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts;
  }

  Color _statusColor(int s) {
    switch (s) {
      case 1: return Colors.blue;
      case 2: return Colors.orange;
      case 3: return Colors.amber;
      case 4: return Colors.red;
      case 5: return Colors.purple;
      case 6: return Colors.green;
      default: return Colors.grey;
    }
  }

  String _statusLabel(BuildContext ctx, int s) {
    final t = ctx.t;
    switch (s) {
      case 1: return t.status_sent;
      case 2: return t.status_in_progress;
      case 3: return t.status_needs_info;
      case 4: return t.status_final_decision;
      case 5: return t.status_rework;
      case 6: return t.status_closed;
      default: return '–';
    }
  }

  String _statusText(BuildContext ctx, int s) {
    final t = ctx.t;
    switch (s) {
      case 1: return t.status_sent ?? 'Eingegangen';
      case 2: return t.status_in_progress ?? 'In Bearbeitung';
      case 3: return t.status_needs_info ?? 'Rückfrage erforderlich';
      case 4: return t.status_final_decision ?? 'Entscheidung';
      case 5: return t.status_rework ?? 'In Nacharbeit';
      case 6: return t.status_closed ?? 'Abgeschlossen';
      default: return 'Status $s';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;

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
                      // Profil-Kachel
                      _TileCard(
                        icon: Icons.person_outline,
                        title: t.profilePW,
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RepProfilePage(api: widget.api),
                            ),
                          );
                          if (mounted) await _loadAll();
                        },
                      ),
                      const SizedBox(height: 16),

                      // Kunden-Kachel
                      _Card(
                        title: t.myCustomers,
                        actions: [
                          ElevatedButton.icon(
                            onPressed: _assignCustomerDialog,
                            icon: const Icon(Icons.person_add_alt_1),
                            label: Text(t.addCustomer),
                          ),
                        ],
                        child: _customers.isEmpty
                            ? Text(t.noAddCustomer)
                            : Column(
                                children: [
                                  for (final e in _customers)
                                    ListTile(
                                      leading: const Icon(Icons.person),
                                      title: Text(e),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.link_off),
                                        tooltip: t.deleteAdd,
                                        onPressed: () => _unassignCustomer(e),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 16),

                      // Reklamations-Kachel
                      _Card(
                        title: t.complaintsMyCustomer,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: _statusCounts().entries.map((e) {
                                return Chip(
                                  label: Text('${_statusLabel(context, e.key)} (${e.value})'),
                                  backgroundColor: _statusColor(e.key).withOpacity(0.15),
                                  labelStyle: TextStyle(
                                    color: _statusColor(e.key),
                                    fontWeight: FontWeight.w600,
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 10),
                            if (_complaints.isEmpty)
                              Text(t.noComplaintsFound)
                            else
                              Column(
                                children: [
                                  for (final c in _complaints)
                                    _ComplaintTile(
                                      data: c,
                                      onDecision: _decideComplaint,
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );

    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (Route<dynamic> r) => false);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(t.rep_dashboard),
          actions: [
            IconButton(
              tooltip: t.newLoad,
              onPressed: _loading ? null : _loadAll,
              icon: const Icon(Icons.refresh),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: Text(t.logout),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: body,
      ),
    );
  }
}

/* ---------------- Hilfskomponenten ---------------- */

class _Card extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final Widget child;
  const _Card({required this.title, this.actions, required this.child});

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

class _TileCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  const _TileCard({required this.icon, required this.title, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _ComplaintTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final void Function(String ticket, bool approve)? onDecision;
  const _ComplaintTile({required this.data, this.onDecision});

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    final ticket = (data['ticket'] ?? '').toString();
    final status = (data['status'] ?? '').toString();
    final decision = (data['decision'] ?? '').toString();
    final created = (data['createdAt'] ?? data['created'] ?? '').toString();
    final customer = (data['customerEmail'] ?? data['email'] ?? '').toString();
    final article = (data['payload']?['article'] ?? '').toString();
    final segment = (data['payload']?['segment'] ?? '').toString();

    final isOpen = status == '1' || status == '2' || status == '3';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(ticket.isEmpty ? '(ohne Ticket)' : ticket),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (customer.isNotEmpty) Text('${t.customer_label}: $customer'),
            if (article.isNotEmpty) Text('${t.articleNo}: $article'),
            if (segment.isNotEmpty) Text('${t.segment}: $segment'),
            Text(
              'Status: $status'
              '${decision.isNotEmpty ? ' • ${t.decision}: $decision' : ''}'
              '${created.isNotEmpty ? ' • ${t.created_at ?? 'Angelegt'}: $created' : ''}',
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onDecision != null && isOpen && decision.isEmpty) ...[
              IconButton(
                tooltip: '${t.decision}: ${t.decision_accepted}',
                icon: const Icon(Icons.check_circle_outline),
                onPressed: () => onDecision!(ticket, true),
              ),
              IconButton(
                tooltip: '${t.decision}: ${t.decision_rejected}',
                icon: const Icon(Icons.cancel_outlined),
                onPressed: () => onDecision!(ticket, false),
              ),
            ],
          ],
        ),
        dense: true,
      ),
    );
  }
}
