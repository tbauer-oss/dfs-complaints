// lib/pages/rep_dashboard_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import 'rep_profile_page.dart';
import 'dart:convert';
import 'dart:html' as html;
import '../l10n/app_localizations.dart';

// ---- L10n-Helper (top-level) ----
extension _L10nX on BuildContext {
  AppLocalizations get t => AppLocalizations.of(this)!;
}

// Filtervarianten für die Kachel-Leiste
enum _RepFilter { all, open, rejected, finished }

class RepDashboardPage extends StatefulWidget {
  final ApiClient api;
  const RepDashboardPage({super.key, required this.api});

  @override
  State<RepDashboardPage> createState() => _RepDashboardPageState();
}

class _RepDashboardPageState extends State<RepDashboardPage> {
  Map<String, dynamic>? _me;
  String _s(Object? v) => v?.toString() ?? '';

  /// Kundenliste (intern als dynamic für UI, Quelle ist strikt String/String)
  List<Map<String, Object?>> _customers = <Map<String, Object?>>[];

  /// Reklamationen
  List<Map<String, dynamic>> _complaints = [];

  bool _loading = true;
  String? _err;

  // aktiver Filter (Kacheln)
  _RepFilter _filter = _RepFilter.all;

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
      final me   = await widget.api.repMe();
      final comp = await widget.api.repComplaints();

      // Kunden – tolerant: Strings oder Objekte
      final rawCustomers = await widget.api.repCustomers(); // List<dynamic>
      final List<Map<String, Object?>> customers = <Map<String, Object?>>[];

      for (final c0 in rawCustomers) {
        if (c0 is Map) {
          // WICHTIG: Generics aufbrechen! KEIN Map<String,int> mehr durchschleifen.
          final Map<Object?, Object?> c = Map<Object?, Object?>.from(c0 as Map);

          final Map<String, Object?> map = <String, Object?>{};
          map['email']   = _s(c['email']);
          map['name']    = _s(c['name'] ?? c['company'] ?? c['displayName'] ?? c['email']);
          map['company'] = _s(c['company']);
          map['address'] = _s(c['address']);
          map['zip']     = _s(c['zip']);
          map['city']    = _s(c['city']);
          map['country'] = _s(c['country']);

          customers.add(map);
        } else if (c0 is String) {
          customers.add(<String, Object?>{'email': c0, 'name': c0});
        } else {
          // Fallback: unbekannter Typ, trotzdem nicht crashen
          customers.add(<String, Object?>{'email': _s(c0), 'name': _s(c0)});
        }
      }

      setState(() {
        _me = me;
        _customers  = customers;   // bleibt List<Map<String, Object?>>
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

  // ---- Status-Logik wie im Admin: offen/geschlossen/abgelehnt ----
  bool _isClosed(Map<String, dynamic> c) {
    final s = int.tryParse((c['status'] ?? '').toString()) ?? 0;
    final dec = (c['decision'] ?? '').toString();
    return s == 6 || (s == 4 && dec == 'rejected');
  }

  bool _isRejected(Map<String, dynamic> c) {
    final dec = (c['decision'] ?? '').toString();
    return dec == 'rejected';
  }

  List<Map<String, dynamic>> get _filteredComplaints {
    switch (_filter) {
      case _RepFilter.all:
        return _complaints;
      case _RepFilter.open:
        return _complaints.where((c) => !_isClosed(c)).toList(growable: false);
      case _RepFilter.rejected:
        return _complaints.where(_isRejected).toList(growable: false);
      case _RepFilter.finished:
        return _complaints
            .where((c) => (int.tryParse((c['status'] ?? '').toString()) ?? 0) == 6)
            .toList(growable: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    final allCount      = _complaints.length;
    final openCount     = _complaints.where((c) => !_isClosed(c)).length;
    final rejectedCount = _complaints.where(_isRejected).length;
    final finishedCount = _complaints.where((c) => (int.tryParse((c['status'] ?? '').toString()) ?? 0) == 6).length;

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
                      // ===== Kachel-Zeile (wie im Admin) =====
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _Tile(
                            icon: Icons.all_inbox_outlined,
                            title: 'Alle',
                            count: allCount,
                            selected: _filter == _RepFilter.all,
                            onTap: () => setState(() => _filter = _RepFilter.all),
                          ),
                          _Tile(
                            icon: Icons.pending_actions_outlined,
                            title: 'Offen',
                            count: openCount,
                            selected: _filter == _RepFilter.open,
                            onTap: () => setState(() => _filter = _RepFilter.open),
                          ),
                          _Tile(
                            icon: Icons.thumb_down_off_alt,
                            title: 'Abgelehnt',
                            count: rejectedCount,
                            selected: _filter == _RepFilter.rejected,
                            onTap: () => setState(() => _filter = _RepFilter.rejected),
                          ),
                          _Tile(
                            icon: Icons.check_circle_outline,
                            title: 'Abgeschlossen',
                            count: finishedCount,
                            selected: _filter == _RepFilter.finished,
                            onTap: () => setState(() => _filter = _RepFilter.finished),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ===== Profil & Passwort =====
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

                      // ===== Meine Daten =====
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
                                    '${(_me!['lastName']  ?? '').toString()}'.trim(),
                                  ),
                                  _Info(t.email_plain, (_me!['email'] ?? '').toString()),
                                  _Info(t.region, (_me!['region'] ?? '').toString()),
                                ],
                              ),
                      ),
                      const SizedBox(height: 16),

                      // ===== Kundenliste (mit Namen + Detail-Button) =====
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
                                  for (final c in _customers)
                                    ListTile(
                                      leading: const Icon(Icons.apartment_outlined),
                                      title: Text(
                                        (c['name'] ?? '').toString().isEmpty
                                            ? (c['email'] ?? '').toString()
                                            : (c['name']  ?? '').toString(),
                                      ),
                                      subtitle: Text((c['email'] ?? '').toString()),
                                      trailing: Wrap(
                                        spacing: 8,
                                        children: [
                                          IconButton(
                                            tooltip: 'Details',
                                            icon: const Icon(Icons.info_outline),
                                            onPressed: () => _showCustomerDetails(c),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.link_off),
                                            tooltip: t.deleteAdd,
                                            onPressed: () => _unassignCustomer((c['email'] ?? '').toString()),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 16),

                      // ===== Reklamationen (gefiltert) =====
                      _Card(
                        title: t.complaintsMyCustomer,
                        child: _filteredComplaints.isEmpty
                            ? Text(t.noComplaintsFound)
                            : Column(
                                children: [
                                  for (final c in _filteredComplaints)
                                    _ComplaintTile(
                                      data: c,
                                      isClosed: _isClosed(c),
                                      onDecision: (c['decision'] ?? '') == '' && !_isClosed(c)
                                          ? _decideComplaint
                                          : null,
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

  void _showCustomerDetails(Map<String, Object?> c) {
    final name    = (c['name'] ?? '').toString();
    final email   = (c['email'] ?? '').toString();
    final company = (c['company'] ?? '').toString();
    final address = (c['address'] ?? '').toString();
    final zip     = (c['zip'] ?? '').toString();
    final city    = (c['city'] ?? '').toString();
    final country = (c['country'] ?? '').toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name.isEmpty ? email : name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (company.isNotEmpty) Text(company),
            if (address.isNotEmpty) Text(address),
            if (zip.isNotEmpty || city.isNotEmpty) Text('$zip $city'.trim()),
            if (country.isNotEmpty) Text(country),
            const SizedBox(height: 8),
            if (email.isNotEmpty) SelectableText(email),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Schließen')),
        ],
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

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _Tile({
    required this.icon,
    required this.title,
    required this.count,
    required this.selected,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme;
    final selBg = base.primary.withOpacity(0.10);
    final selBr = base.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? selBg : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? selBr : base.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('$count', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ],
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
  final bool isClosed;
  final void Function(String ticket, bool approve)? onDecision;
  const _ComplaintTile({required this.data, required this.isClosed, this.onDecision});

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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onDecision != null) ...[
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
            if (isClosed) const SizedBox(width: 4),
          ],
        ),
        dense: true,
      ),
    );
  }
}
