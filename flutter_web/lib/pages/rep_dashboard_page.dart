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
      final repId = (_me?['id'] ?? '').toString();
      if (repId.isEmpty) {
        throw 'missing rep id';
      }
      await widget.api.repDecision(
        repId: repId,
        ticket: ticket,
        approve: approve,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(approve ? context.t.rep_approved : context.t.rep_rejected)),
      );
      await _loadAll(); // Liste neu laden
    } catch (e) {
      final handled = await _handleUnauthorized(e);
      if (!mounted || handled) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.t.error ?? "Fehler"}: $e')),
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
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Profil & Passwort
                      Card(
                        elevation: 4,
                        child: ListTile(
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
                      const SizedBox(height: 16),

                      _Card(
                        title: t.myData,
                        child: _me == null
                            ? const Text('–')
                            : Wrap(
                                spacing: 16,
                                runSpacing: 6,
                                children: [
                                  _Info(
                                    'Name',
                                    '${(_me!['firstName'] ?? '').toString()} '
                                    '${(_me!['lastName'] ?? '').toString()}'.trim(),
                                  ),
                                  _Info(t.email_plain, (_me!['email'] ?? '').toString()),
                                  _Info(t.region, (_me!['region'] ?? '').toString()),
                                ],
                              ),
                      ),
                      const SizedBox(height: 16),

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

                      _Card(
                        title: t.complaintsMyCustomer,
                        child: _complaints.isEmpty
                            ? Text(t.noComplaintsFound)
                            : Column(
                                children: [
                                  for (final c in _complaints)
                                    _ComplaintTile(
                                      data: c,
                                      onDecision: _decideComplaint, // ← NEU: Callback übergeben
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
  final void Function(String ticket, bool approve)? onDecision;
  const _ComplaintTile({required this.data, this.onDecision});

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    final ticket   = (data['ticket'] ?? '').toString();
    final status   = (data['status'] ?? '').toString();
    final decision = (data['decision'] ?? '').toString();
    final created  = (data['createdAt'] ?? data['created'] ?? '').toString();
    final customer = (data['customerEmail'] ?? data['email'] ?? '').toString();
    final article  = (data['payload']?['article'] ?? '').toString();
    final segment  = (data['payload']?['segment'] ?? '').toString();

    final isOpen = status == 'open' || status == 'pending';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(ticket.isEmpty ? '(ohne Ticket)' : ticket),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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

        // ↓↓↓ NEU: die beiden Buttons rechts
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onDecision != null) ...[
              IconButton(
                tooltip: t.approve ?? 'Freigeben',
                icon: const Icon(Icons.check_circle_outline),
                onPressed: () => onDecision!(ticket, true),
              ),
              IconButton(
                tooltip: t.reject ?? 'Ablehnen',
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
