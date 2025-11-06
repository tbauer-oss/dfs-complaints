// lib/pages/rep_dashboard_page.dart
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
  State<RepDashboardPage> createState() => RepDashboardPageState();
}

class RepDashboardPage extends State<RepDashboardPage> {
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
      await widget.api.repDecision(
        ticket: ticket,
        approve: approve,
      );
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
    try { html.window.localStorage.remove('dfs_mode'); } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (Route<dynamic> r) => false);
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
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
                child: LayoutBuilder(
                  builder: (ctx, c) {
                    final w = c.maxWidth;
                    // 1 Spalte (<=720), 2 Spalten (<=1100), 3 Spalten darüber
                    final cols = w <= 720 ? 1 : (w <= 1100 ? 2 : 3);
                    return SingleChildScrollView(
                      child: _DashboardGrid(
                        columns: cols,
                        children: [
                          // Kachel: Profil/Passwort
                          _DashboardTile(
                            icon: Icons.manage_accounts_outlined,
                            title: t.profilePW,
                            actions: [
                              IconButton(
                                tooltip: t.newLoad,
                                onPressed: _loading ? null : _loadAll,
                                icon: const Icon(Icons.refresh),
                              ),
                            ],
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.person_outline),
                              title: Text(t.profilePW),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => RepProfilePage(api: widget.api),
                                  ),
                                );
                                if (!mounted) return;
                                await _loadAll();
                              },
                            ),
                          ),

                          // Kachel: Meine Daten
                          _DashboardTile(
                            icon: Icons.badge_outlined,
                            title: t.myData,
                            child: _me == null
                                ? const Text('–')
                                : Wrap(
                                    spacing: 16,
                                    runSpacing: 8,
                                    children: [
                                      _Info('Name',
                                          '${(_me!['firstName'] ?? '').toString()} ${(_me!['lastName'] ?? '').toString()}'.trim()),
                                      _Info(t.email_plain, (_me!['email'] ?? '').toString()),
                                      _Info(t.region, (_me!['region'] ?? '').toString()),
                                    ],
                                  ),
                          ),

                          // Kachel: Meine Kunden (links Liste, oben Action)
                          _DashboardTile(
                            icon: Icons.groups_outlined,
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
                                          contentPadding: EdgeInsets.zero,
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

                          // Kachel: Reklamationen der zugewiesenen Kunden
                          _DashboardTile(
                            icon: Icons.description_outlined,
                            title: t.complaintsMyCustomer,
                            subtitle: _complaints.isNotEmpty
                                ? Text('${_complaints.length} ${t.complaintsMyCustomer}')
                                : null,
                            child: _complaints.isEmpty
                                ? Text(t.noComplaintsFound)
                                : Column(
                                    children: [
                                      for (final c in _complaints)
                                        _ComplaintTile(
                                          data: c,
                                          onDecision: _decideComplaint,
                                        ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
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

/* =======================
   Dashboard-Grundelemente
   ======================= */

class _DashboardGrid extends StatelessWidget {
  final int columns;
  final List<Widget> children;
  const _DashboardGrid({required this.columns, required this.children});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: columns,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.25, // dezent breiter; passt zu "Admin-Kacheln"
      children: children,
    );
  }
}

class _DashboardTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? subtitle;

  const _DashboardTile({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.actions,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header mit Icon + Titel + Actions
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      if (subtitle != null) DefaultTextStyle.merge(
                        style: Theme.of(context).textTheme.bodySmall!,
                        child: subtitle!,
                      ),
                    ],
                  ),
                ),
                if (actions != null) ...actions!,
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: SingleChildScrollView(
                  child: child,
                ),
              ),
            ),
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
    return Chip(
      label: Text('$k: $v'),
      visualDensity: VisualDensity.compact,
    );
  }
}

/* ==========================
   Complaint-ListTile (Kachel)
   ========================== */

class _ComplaintTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final void Function(String ticket, bool approve)? onDecision;
  const _ComplaintTile({required this.data, this.onDecision});

  Color _statusColor(int s, String decision) {
    // einfache, zur Admin-Logik passende Grundfarben
    switch (s) {
      case 1: return Colors.blue;               // SENT
      case 2: return Colors.amber[800] ?? Colors.amber;
      case 3: return Colors.orange;
      case 4: return (decision == 'accepted') ? Colors.lightGreen[700]! : Colors.redAccent;
      case 5: return Colors.teal;
      case 6: return Colors.green;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    final ticket   = (data['ticket'] ?? '').toString();
    final status   = (data['status'] ?? '').toString();                // numerisch (1..6)
    final decision = (data['decision'] ?? '').toString();              // 'accepted' | 'rejected' | ''
    final created  = (data['createdAt'] ?? data['created'] ?? '').toString();
    final customer = (data['customerEmail'] ?? data['email'] ?? '').toString();
    final article  = (data['payload']?['article'] ?? '').toString();
    final segment  = (data['payload']?['segment'] ?? '').toString();

    final int s = int.tryParse(status) ?? 0;
    final bool isOpen = (s != 6) && !(s == 4 && decision == 'rejected');
    final bool canDecide = onDecision != null && isOpen && decision.isEmpty;

    final color = _statusColor(s, decision);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: color.withOpacity(0.35), width: 1),
        borderRadius: BorderRadius.circular(12),
        color: color.withOpacity(0.06),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.description_outlined, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.bodyMedium!,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ticket.isEmpty ? '(ohne Ticket)' : ticket,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  if (customer.isNotEmpty) Text('${t.customer_label}: $customer'),
                  if (article.isNotEmpty)  Text('${t.articleNo}: $article'),
                  if (segment.isNotEmpty)  Text('${t.segment}: $segment'),
                  Text(
                    'Status: $status'
                    '${decision.isNotEmpty ? ' • ${t.decision}: $decision' : ''}'
                    '${created.isNotEmpty ? ' • ${t.created_at ?? 'Angelegt'}: $created' : ''}',
                  ),
                ],
              ),
            ),
          ),
          if (canDecide) ...[
            const SizedBox(width: 12),
            Wrap(
              spacing: 6,
              children: [
                Tooltip(
                  message: '${t.decision}: ${t.decision_accepted}',
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(t.decision_accepted),
                    onPressed: () => onDecision!(ticket, true),
                  ),
                ),
                Tooltip(
                  message: '${t.decision}: ${t.decision_rejected}',
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cancel_outlined),
                    label: Text(t.decision_rejected),
                    onPressed: () => onDecision!(ticket, false),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
