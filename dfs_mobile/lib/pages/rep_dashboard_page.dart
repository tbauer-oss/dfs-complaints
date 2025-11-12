// lib/pages/rep_dashboard_page.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../api/client.dart';
import 'rep_profile_page.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dfs_mobile/web_compat/html_stub.dart'
  if (dart.library.html) 'package:dfs_mobile/web_compat/html_web.dart' as html;
import '../l10n/app_localizations.dart';
import '../widgets/dialog_content_scroll.dart';
import '../widgets/lang_action.dart';
import '../widgets/theme_action.dart' as w;
import '../services/app_prefs_scope.dart';
import '../widgets/legal_footer.dart';

// ---- L10n-Helper (top-level) ----
extension _L10nX on BuildContext {
  AppLocalizations get t => AppLocalizations.of(this)!;
}

// Filtervarianten (intern noch genutzt)
enum _RepFilter { all, open, rejected, finished }

// Menü-Views
enum _RepView { menu, open, all, customers, account }

class RepDashboardPage extends StatefulWidget {
  final ApiClient api;
  const RepDashboardPage({super.key, required this.api});

  @override
  State<RepDashboardPage> createState() => _RepDashboardPageState();
}

class _RepDashboardPageState extends State<RepDashboardPage> {
  Map<String, dynamic>? _me;

  /// Kundenliste (aus Backend normalisiert) – zugewiesene Kunden dieses Vertreters
  List<Map<String, Object?>> _customers = <Map<String, Object?>>[];

  /// Reklamationen (aus Backend)
  List<Map<String, dynamic>> _complaints = [];

  bool _loading = true;
  String? _err;

  // alter Filter bleibt intern für _filteredComplaints
  _RepFilter _filter = _RepFilter.all;

  // neue Menü-/Seitenlogik
  _RepView _view = _RepView.menu;

  // Firmenfilter (Dropdown) – gilt für „Alle Reklamationen“ und „Offene Reklamationen“
  String? _selectedCompany;
  bool _showClosedAll = false;
  bool _showRejectedAll = false;

  // "NEU"-Badges: lokal gemerkte "schon gesehen" Kunden (E-Mails als Key)
  static const _seenKey = 'rep_seen_customers_v1';
  late final Set<String> _seenCustomers;

  // Brandfarbe (DFS Blau)
  static const _brand = Color(0xFF0865A2);

  @override
  void initState() {
    super.initState();
    _seenCustomers = _loadSeen();
    _loadAll();
  }

  Set<String> _loadSeen() {
    try {
      final raw = html.window.localStorage[_seenKey];
      if (raw == null || raw.isEmpty) return <String>{};
      final parts = raw.split(';').map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toSet();
      return parts;
    } catch (_) {
      return <String>{};
    }
  }

  void _persistSeen() {
    try {
      html.window.localStorage[_seenKey] = _seenCustomers.join(';');
    } catch (_) {}
  }

  void _markCustomerSeen(String email) {
    final em = email.toLowerCase();
    if (_seenCustomers.add(em)) {
      _persistSeen();
      if (mounted) setState(() {});
    }
  }

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

  // ---- Admin-gleiche „freie Kunden“-Quelle holen (identisch & live) ----
  // NEU: zieht jetzt aus /api/rep/assignable-customers?all=1
  // und liefert: email, label, assigned(bool), assignedToLabel (String)
  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _err = null;
    });

    try {
      // Sicherstellen, dass repToken gültig ist
      await widget.api.ensureRepSession();

      final me   = await widget.api.repMe();
      final comp = await widget.api.repComplaints();

      // Kunden – tolerant: Details (neu) ODER Strings (alt)
      List<dynamic> rawCustomers;
      try {
        rawCustomers = await widget.api.repCustomersDetailed();
      } catch (_) {
        rawCustomers = await widget.api.repCustomers();
      }

      // Normalisieren auf List<Map<String, Object?>>
      final List<Map<String, Object?>> customers = <Map<String, Object?>>[];
      for (final c in rawCustomers) {
        if (c is Map) {
          String s(Object? v) => (v ?? '').toString();
          final email      = s(c['email']);
          final name       = s(c['name']).isEmpty ? email : s(c['name']);
          final company    = s(c['company']);
          final address    = s(c['address']);
          final zip        = s(c['zip']);
          final city       = s(c['city']);
          final country    = s(c['country']);
          final phone      = s(c['phone']);
          final customerNo = s(c['customerNo']);
          final vatId      = s(c['vatId']);

          customers.add(<String, Object?>{
            'email': email,
            'name' : name,
            'company': company,
            'address': address,
            'zip': zip,
            'city': city,
            'country': country,
            'phone': phone,
            'customerNo': customerNo,
            'vatId': vatId,
          });
        } else if (c is String) {
          customers.add(<String, Object?>{
            'email': c,
            'name' : c,
            'company': '',
            'address': '',
            'zip': '',
            'city': '',
            'country': '',
            'phone': '',
            'customerNo': '',
            'vatId': '',
          });
        }
      }

      if (!mounted) return;
      setState(() {
        _me = me;
        _customers  = customers;
        _complaints = comp;
      });

    } catch (e) {
      final handled = await _handleUnauthorized(e);
      if (!mounted) return;
      if (handled) return;
      setState(() => _err = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ======= FEHLENDE METHODE (jetzt robust mit Token-GET) =======
  Future<List<Map<String, Object?>>> _fetchAssignableCustomers() async {
    await widget.api.ensureRepSession();

    List<Map<String, dynamic>> raw;
    try {
      raw = await widget.api.repAssignableCustomers(all: true);
    } catch (_) {
      return <Map<String, Object?>>[];
    }

    String s(Object? v) => (v ?? '').toString();
    final out = <Map<String, Object?>>[];
    for (final it in raw) {
      final email = s(it['email']).toLowerCase();
      if (email.isEmpty) continue;

      final company = s(it['company']);
      final name    = s(it['name']);
      final label   = company.isNotEmpty
          ? company
          : (name.isNotEmpty ? '$name • $email' : email);

      final assigned = (it['assigned'] == true) ||
          (s(it['assigned']).toLowerCase() == 'true');

      final assignedToLabel =
          s(it['assignedToName']).isNotEmpty ? s(it['assignedToName'])
              : s(it['assignedToEmail']).isNotEmpty ? s(it['assignedToEmail'])
              : s(it['assignedTo']);

      out.add({
        'email': email,
        'label': label,
        'assigned': assigned,
        'assignedToLabel': assignedToLabel,
      });
    }

    out.sort((a, b) {
      final aa = (a['assigned'] == true);
      final bb = (b['assigned'] == true);
      if (aa != bb) return aa ? 1 : -1;
      return (a['label'] as String).toLowerCase().compareTo((b['label'] as String).toLowerCase());
    });

    return out;
  }

  Widget _buildOverviewHeader({
    required int openCount,
    required int allCount,
    required int rejectedCount,
    required int finishedCount,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // kompaktere Abstände/Typo
    const avatarSize = 36.0;
    const pad = EdgeInsets.fromLTRB(14, 12, 14, 12);

    String _initials() {
      final fn = (_me?['firstName'] ?? '').toString().trim();
      final ln = (_me?['lastName']  ?? '').toString().trim();
      final em = (_me?['email']     ?? '').toString().trim();
      if (fn.isNotEmpty && ln.isNotEmpty) return '${fn[0]}${ln[0]}'.toUpperCase();
      if (fn.isNotEmpty) return fn[0].toUpperCase();
      if (em.isNotEmpty) return em[0].toUpperCase();
      return 'U';
    }

    String _fullName() {
      final fn = (_me?['firstName'] ?? '').toString().trim();
      final ln = (_me?['lastName']  ?? '').toString().trim();
      final em = (_me?['email']     ?? '').toString().trim();
      final n = [fn, ln].where((e) => e.isNotEmpty).join(' ');
      return n.isNotEmpty ? n : em;
    }

    return Card(
      elevation: 2, // dezenter
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Ink(
        decoration: BoxDecoration(
          // leichte, zurückhaltende Fläche (hell/dunkel tauglich)
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.surfaceVariant.withOpacity(.18),
              cs.surface.withOpacity(.60),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withOpacity(.5)),
        ),
        child: Padding(
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Kopfzeile: Avatar + Name + Mail
              Row(
                children: [
                  Container(
                    width: avatarSize,
                    height: avatarSize,
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(.16),
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.primary.withOpacity(.35)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _initials(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fullName(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800, // kleiner als vorher
                          ),
                        ),
                        if ((_me?['email'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            (_me?['email'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // kleine, dezente Counter-Chips (2 pro Zeile, dann 1/1)
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _overviewStat(
                    icon: Icons.report_problem_rounded,
                    label: 'Offen',
                    value: openCount,
                    color: Colors.red.shade600,
                  ),
                  _overviewStat(
                    icon: Icons.all_inbox_rounded,
                    label: 'Alle',
                    value: allCount,
                    color: cs.primary,
                  ),
                  _overviewStat(
                    icon: Icons.thumb_down_alt_rounded,
                    label: 'Abgelehnt',
                    value: rejectedCount,
                    color: Colors.orange.shade700,
                  ),
                  _overviewStat(
                    icon: Icons.check_circle_rounded,
                    label: 'Abgeschlossen',
                    value: finishedCount,
                    color: Colors.green.shade600,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _overviewStat({
    required IconData icon,
    required String label,
    required int value,
    required Color color,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // kleiner
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(12), // kleiner
        border: Border.all(color: color.withOpacity(.45), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
              fontSize: 13, // kleiner
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$value',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12, // kleiner
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // Mail/Benachrichtigung an complaint@dfs-diamon.de bei Selbst-Zuweisung
  Future<void> _notifySelfAssignment({required String customerEmail, required String? company}) async {
    try {
      final dyn = widget.api as dynamic;
      final payload = {
        'repEmail'    : _me?['email'] ?? '',
        'repName'     : [ _me?['firstName'], _me?['lastName'] ].where((e) => (e ?? '').toString().isNotEmpty).join(' ').trim(),
        'customerEmail': customerEmail,
        'company'     : company ?? '',
      };

      try { await dyn.repAssignmentNotify(payload); return; } catch (_) {}
      try { await dyn.postJson('/api/admin/notify-rep-assignment', payload); return; } catch (_) {}
      try { await dyn.postJson('/api/rep/assignment/notify', payload); return; } catch (_) {}
    } catch (_) {}
  }

  // ==========================
  // Schöne Auswahlliste (Sheet)
  // ==========================
  Future<void> _assignCustomerDialog() async {
    final t = context.t;
    final options = await _fetchAssignableCustomers();

    if (!mounted) return;

    if (options.isEmpty) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t.addCustomer),
          content: DialogContentScroll(child: Text(t.noAddCustomer)),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(t.close)),
          ],
        ),
      );
      return;
    }

    String query = '';
    String? locErr;
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        List<Map<String, Object?>> filtered() {
          if (query.trim().isEmpty) return options;
          final q = query.toLowerCase();
          return options.where((o) {
            final label = (o['label'] as String).toLowerCase();
            final email = (o['email'] as String).toLowerCase();
            final assTo = (o['assignedToLabel']?.toString() ?? '').toLowerCase();
            return label.contains(q) || email.contains(q) || assTo.contains(q);
          }).toList();
        }

        List<Map<String, Object?>> free(List<Map<String, Object?>> src) =>
            src.where((o) => o['assigned'] != true).toList();
        List<Map<String, Object?>> taken(List<Map<String, Object?>> src) =>
            src.where((o) => o['assigned'] == true).toList();

        Future<void> doAssign(String email, String label) async {
          if (saving) return;
          saving = true;
          (ctx as Element).markNeedsBuild();

          try {
            await widget.api.ensureRepSession();
            await widget.api.repAssignCustomer(email);
            await _notifySelfAssignment(customerEmail: email, company: label);

            if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
            await _loadAll();

            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.t.saved)),
            );
          } catch (e) {
            locErr = '${context.t.error ?? 'Fehler'}: $e';
            saving = false;
            (ctx as Element).markNeedsBuild();
          }
        }

        final list = filtered();
        final listFree  = free(list);
        final listTaken = taken(list);

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
            top: 12, left: 12, right: 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46, height: 5,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).dividerColor,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.person_add_alt_1),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(t.addCustomer, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  IconButton(
                    tooltip: t.close,
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (v) { query = v; (ctx as Element).markNeedsBuild(); },
                decoration: InputDecoration(
                  hintText: t.search ?? 'Suchen…',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),

              if (listFree.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 18, color: Colors.green),
                    const SizedBox(width: 6),
                    Text(t.free ?? 'Frei', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: listFree.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final o = listFree[i];
                      final email = o['email'] as String;
                      final label = o['label'] as String;
                      return ListTile(
                        onTap: saving ? null : () => doAssign(email, label),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                        leading: const CircleAvatar(child: Icon(Icons.apartment, size: 18)),
                        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(email, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: saving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.add_circle_outline),
                      );
                    },
                  ),
                ),
              ],

              if (listTaken.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.lock_outline, size: 18, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(t.assigned ?? 'Zugewiesen', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: listTaken.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final o = listTaken[i];
                      final label = (o['label'] as String);
                      final email = (o['email'] as String);
                      final asTo  = (o['assignedToLabel']?.toString() ?? '');
                      return Opacity(
                        opacity: 0.50,
                        child: ListTile(
                          enabled: false,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                          leading: const CircleAvatar(child: Icon(Icons.apartment, size: 18)),
                          title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            asTo.isNotEmpty
                                ? '$email  •  (${t.assigned_to ?? 'zugewiesen an'}: $asTo)'
                                : email,
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.do_not_disturb_on, color: Colors.grey),
                        ),
                      );
                    },
                  ),
                ),
              ],

              if (listFree.isEmpty && listTaken.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    t.noAddCustomer,
                    textAlign: TextAlign.center,
                  ),
                ),

              if (locErr != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(locErr!, style: const TextStyle(color: Colors.red)),
                ),
              ],
              const SizedBox(height: 6),
            ],
          ),
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
        SnackBar(
          content: Text(
            (context.t.my_decision ?? 'Meine Bewertung') + ': ' +
            (approve ? context.t.decision_accepted : context.t.decision_rejected),
          ),
        ),
      );
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.t.error ?? 'Fehler'}: $e')),
      );
    }
  }

  Future<void> _withdrawRepDecision(String ticket) async {
    try {
      await widget.api.ensureRepSession();
      await widget.api.repDecisionReset(ticket: ticket);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.decision_withdrawn ?? 'Entscheidung zurückgenommen')),
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

  // ---- Status-Logik (wie bisher) ----
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

  // Mapping E-Mail -> Firma (für Firmenanzeige)
  Map<String, String> get _emailToCompany {
    final m = <String, String>{};
    for (final c in _customers) {
      final em = (c['email'] ?? '').toString().toLowerCase();
      final co = (c['company'] ?? '').toString();
      if (em.isNotEmpty && co.isNotEmpty) m[em] = co;
    }
    for (final c in _complaints) {
      final em = (c['customerEmail'] ?? c['email'] ?? '').toString().toLowerCase();
      final co = (c['payload']?['company'] ?? '').toString();
      if (em.isNotEmpty && co.isNotEmpty) m.putIfAbsent(em, () => co);
    }
    return m;
  }

  // ------ Anzeige-Helper ------
  String _displayCustomerFor(Map<String, dynamic> c) {
    final em = (c['customerEmail'] ?? c['email'] ?? '').toString().toLowerCase();
    final co = _emailToCompany[em] ?? '';
    return co.isNotEmpty ? co : em;
  }

  String _formatCreated(dynamic v) {
    final s = v?.toString() ?? '';
    if (s.isEmpty) return s;
    int? ms;
    final n = int.tryParse(s);
    if (n != null) {
      ms = n > 20000000000 ? n : n * 1000;
    }
    if (ms != null) {
      final dt = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
      String two(int x) => x < 10 ? '0$x' : '$x';
      return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
    }
    DateTime? dt;
    try { dt = DateTime.parse(s).toLocal(); } catch (_) {}
    if (dt != null) {
      String two(int x) => x < 10 ? '0$x' : '$x';
      return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
    }
    return s;
  }

  // -------- UI --------

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final prefs = AppPrefsScope.of(context);
    final allCount      = _complaints.length;
    final openCount     = _complaints.where((c) => !_isClosed(c)).length;
    final rejectedCount = _complaints.where(_isRejected).length;
    final finishedCount = _complaints.where((c) => (int.tryParse((c['status'] ?? '').toString()) ?? 0) == 6).length;
    final title = switch (_view) {
      _RepView.menu      => t.rep_dashboard,
      _RepView.open      => t.complaintsMyCustomer,
      _RepView.all       => 'Alle Reklamationen',
      _RepView.customers => t.myCustomers,
      _RepView.account   => t.profilePW,
    };

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _err != null
            ? Center(child: Text(_err!, style: const TextStyle(color: Colors.red)))
            : switch (_view) {
                _RepView.menu      => _buildMenu(allCount, openCount, rejectedCount, finishedCount),
                _RepView.open      => _scrollWrap(_buildOpenComplaints()),
                _RepView.all       => _scrollWrap(_buildAllComplaints()),
                _RepView.customers => _scrollWrap(_buildCustomersCard()),
                _RepView.account   => _scrollWrap(_buildAccountCard()),
              };

    final canGoBack = _view != _RepView.menu;

    return WillPopScope(
      onWillPop: () async {
        if (canGoBack) {
          setState(() => _view = _RepView.menu);
          return false;
        }
        Navigator.of(context).pushNamedAndRemoveUntil('/', (Route<dynamic> r) => false);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(title),
          centerTitle: false,
          leading: canGoBack
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _view = _RepView.menu),
                )
              : null,
          actions: [
            IconButton(
              tooltip: t.newLoad,
              onPressed: _loading ? null : _loadAll,
              icon: const Icon(Icons.refresh),
            ),
            const SizedBox(width: 4),
            LangAction(onLocaleChanged: (l) => prefs.setLang(l.languageCode)),
            const SizedBox(width: 4),
            w.ThemeAction(),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: Text(t.logout),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Padding(padding: const EdgeInsets.all(16), child: body),
        bottomNavigationBar: LegalFooter(api: widget.api),
      ),
    );
  }

  // Wrapper: macht Seiten scrollbar (auch auf Handy)
  Widget _scrollWrap(Widget child) {
    return LayoutBuilder(
      builder: (_, cons) => SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: cons.maxHeight),
          child: child,
        ),
      ),
    );
  }

  // ---- Menü (mit Hero-Header + KPI-Chips + Kacheln) ----
  Widget _buildMenu(int allCount, int openCount, int rejectedCount, int finishedCount) {
    return LayoutBuilder(builder: (ctx, c) {
      final width = c.maxWidth;
      final gridCount = width >= 1200 ? 4 : width >= 900 ? 3 : width >= 600 ? 2 : 1;
      final aspect = width >= 1400 ? 1.70 : width >= 1100 ? 1.60 : width >= 900 ? 1.55 : width >= 600 ? 1.45 : width >= 480 ? 1.50 : 1.75;
      final scale = width >= 1400 ? 0.84 : width >= 1100 ? 0.88 : width >= 900 ? 0.90 : width >= 600 ? 0.95 : 1.00;
      final compact = width < 600;

      return SingleChildScrollView(
        child: Column(
          children: [
            _buildOverviewHeader(
              openCount: openCount,
              allCount: allCount,
              rejectedCount: rejectedCount,
              finishedCount: finishedCount,
            ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: gridCount,
              crossAxisSpacing: compact ? 12 : 14,
              mainAxisSpacing: compact ? 12 : 14,
              padding: EdgeInsets.only(bottom: compact ? 4 : 8),
              childAspectRatio: aspect,
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              children: [
                _MenuCard(
                  color: Colors.red,
                  icon: Icons.report_gmailerrorred_outlined,
                  title: 'Offene Reklamationen',
                  subtitle: 'Bearbeiten & Entscheiden',
                  count: openCount,
                  compact: compact,
                  scale: scale,
                  onTap: () => setState(() {
                    _filter = _RepFilter.open;
                    _view = _RepView.open;
                  }),
                ),
                _MenuCard(
                  color: Colors.indigo,
                  icon: Icons.all_inbox_outlined,
                  title: 'Alle Reklamationen',
                  subtitle: 'Filtern & Suchen',
                  count: allCount,
                  compact: compact,
                  scale: scale,
                  onTap: () => setState(() => _view = _RepView.all),
                ),
                _MenuCard(
                  color: Colors.teal,
                  icon: Icons.apartment_outlined,
                  title: 'Kundendatenbank',
                  subtitle: 'Firmen & Kontakte',
                  count: _customers.length,
                  compact: compact,
                  scale: scale,
                  onTap: () => setState(() => _view = _RepView.customers),
                ),
                _MenuCard(
                  color: Colors.blueGrey,
                  icon: Icons.person_outline,
                  title: 'Mein Account',
                  subtitle: 'Profil & Passwort',
                  count: null,
                  compact: compact,
                  scale: scale,
                  onTap: () => setState(() => _view = _RepView.account),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  // ---- Seite: Offene Reklamationen (mit Firmen-Dropdown) ----
  Widget _buildOpenComplaints() {
    final t = context.t;

    final companies = _emailToCompany.values
        .where((s) => s.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    List<Map<String, dynamic>> items =
        _complaints.where((c) => !_isClosed(c)).toList(growable: false);

    if ((_selectedCompany ?? '').isNotEmpty) {
      items = items.where((c) {
        final em = (c['customerEmail'] ?? c['email'] ?? '').toString().toLowerCase();
        final co = (_emailToCompany[em] ?? '');
        return co == _selectedCompany;
      }).toList(growable: false);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: SizedBox(
              width: 320,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: _selectedCompany,
                items: <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(
                    value: '',
                    child: Text(t.allCompanies ?? 'Alle Firmen'),
                  ),
                  ...companies.map((co) => DropdownMenuItem<String>(
                        value: co,
                        child: Text(co),
                      )),
                ],
                onChanged: (v) => setState(() => _selectedCompany = (v ?? '')),
                decoration: const InputDecoration(
                  labelText: 'Firmenname filtern',
                  prefixIcon: Icon(Icons.apartment_outlined),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        _Card(
          title: t.complaintsMyCustomer,
          child: items.isEmpty
              ? _EmptyState(icon: Icons.inbox_outlined, title: t.noComplaintsFound)
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (_, i) {
                    final c = items[i];
                    final customerDisplay = _displayCustomerFor(c);
                    final createdDisplay  = _formatCreated(c['createdAt'] ?? c['created']);
                    return _ComplaintTile(
                      data: c,
                      isClosed: false,
                      onDecision: (ticket, approve) => _decideComplaint(ticket, approve),
                      onWithdraw: (ticket) => _withdrawRepDecision(ticket),
                      useColoredButtons: true,
                      customerOverride: customerDisplay,
                      createdOverride: createdDisplay,
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemCount: items.length,
                ),
        ),
      ],
    );
  }

  // ---- Seite: Alle Reklamationen ----
  Widget _buildAllComplaints() {
    final t = context.t;

    final companies = _emailToCompany.values
        .where((s) => s.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    List<Map<String, dynamic>> list = List<Map<String, dynamic>>.from(_complaints);

    if (!_showClosedAll) {
      list = list.where((c) => !_isClosed(c)).toList();
    }
    if (_showRejectedAll) {
      list = list.where(_isRejected).toList();
    }
    if ((_selectedCompany ?? '').isNotEmpty) {
      list = list.where((c) {
        final em = (c['customerEmail'] ?? c['email'] ?? '').toString().toLowerCase();
        final co = (_emailToCompany[em] ?? '');
        return co == _selectedCompany;
      }).toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Wrap(
              spacing: 14,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _selectedCompany,
                    items: <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(
                        value: '',
                        child: Text(t.allCompanies ?? 'Alle Firmen'),
                      ),
                      ...companies.map((co) => DropdownMenuItem<String>(
                            value: co,
                            child: Text(co),
                          )),
                    ],
                    onChanged: (v) => setState(() => _selectedCompany = (v ?? '')),
                    decoration: const InputDecoration(
                      labelText: 'Firmenname filtern',
                      prefixIcon: Icon(Icons.apartment_outlined),
                    ),
                  ),
                ),
                FilterChip(
                  label: const Text('Abgeschlossen anzeigen'),
                  selected: _showClosedAll,
                  onSelected: (v) => setState(() => _showClosedAll = v),
                ),
                FilterChip(
                  label: const Text('Nur abgelehnte'),
                  selected: _showRejectedAll,
                  onSelected: (v) => setState(() => _showRejectedAll = v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          title: 'Alle Reklamationen',
          child: list.isEmpty
              ? _EmptyState(icon: Icons.inbox_outlined, title: t.noComplaintsFound)
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (_, i) {
                    final c = list[i];
                    final customerDisplay = _displayCustomerFor(c);
                    final createdDisplay  = _formatCreated(c['createdAt'] ?? c['created']);
                    return _ComplaintTile(
                      data: c,
                      isClosed: _isClosed(c),
                      onDecision: ((c['repDecision'] ?? '') as String).isEmpty && !_isClosed(c)
                          ? _decideComplaint
                          : null,
                      onWithdraw: !_isClosed(c) ? (ticket) => _withdrawRepDecision(ticket) : null,
                      useColoredButtons: true,
                      customerOverride: customerDisplay,
                      createdOverride: createdDisplay,
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemCount: list.length,
                ),
        ),
      ],
    );
  }

  // ---- Seite: Kundendatenbank ----
  Widget _buildCustomersCard() {
    final t = context.t;
    return _Card(
      title: t.myCustomers,
      actions: [
        FilledButton.tonalIcon(
          onPressed: _assignCustomerDialog,
          icon: const Icon(Icons.person_add_alt_1),
          label: Text(t.addCustomer),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: const StadiumBorder(),
          ),
        ),
      ],
      child: _customers.isEmpty
          ? _EmptyState(icon: Icons.apartment_outlined, title: t.noAddCustomer)
          : ListView.separated(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final c = _customers[i];
                final email = (c['email'] ?? '').toString();
                final isNew = !_seenCustomers.contains(email.toLowerCase());

                return _FadeInOnce(
                  delayMs: 35 * i,
                  child: _CustomerTile(
                    data: c,
                    isNew: isNew,
                    t: t,
                    onOpen: () {
                      _markCustomerSeen(email);
                      _showCustomerDetails(c);
                    },
                    onInfo: () {
                      _markCustomerSeen(email);
                      _showCustomerDetails(c);
                    },
                    onRemove: () => _unassignCustomer(email),
                  ),
                );
              },
              itemCount: _customers.length,
            ),
    );
  }

  // ---- Seite: Account ----
  Widget _buildAccountCard() {
    final t = context.t;
    final labelProfile   = t.profile_edit ?? 'Profil bearbeiten';
    final labelPassword  = t.password_change ?? 'Passwort ändern';

    Future<void> _openProfile() async {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RepProfilePage(
            api: widget.api,
            hidePasswordSection: true,
          ),
        ),
      );
      if (!mounted) return;
      await _loadAll();
    }

    Future<void> _openPasswordChange() async {
      final oldCtrl = TextEditingController();
      final new1Ctrl = TextEditingController();
      final new2Ctrl = TextEditingController();
      String? err;
      bool busy = false;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          Future<void> _submit() async {
            if (busy) return;
            final oldPw = oldCtrl.text;
            final n1 = new1Ctrl.text;
            final n2 = new2Ctrl.text;
            if (oldPw.isEmpty || n1.isEmpty || n2.isEmpty) {
              err = t.errorGeneric('Bitte alle Felder ausfüllen');
              (ctx as Element).markNeedsBuild();
              return;
            }
            if (n1 != n2) {
              err = t.errorGeneric('Passwörter stimmen nicht überein');
              (ctx as Element).markNeedsBuild();
              return;
            }
            busy = true;
            (ctx as Element).markNeedsBuild();
            try {
              await widget.api.repChangePassword(n1);
              if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.saved)));
            } catch (e) {
              err = '${t.error ?? 'Fehler'}: $e';
              busy = false;
              (ctx as Element).markNeedsBuild();
            }
          }

          return AlertDialog(
            title: Text(labelPassword),
            content: DialogContentScroll(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: oldCtrl,
                    obscureText: true,
                    decoration: InputDecoration(labelText: t.oldPassword),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: new1Ctrl,
                    obscureText: true,
                    decoration: InputDecoration(labelText: t.newPassword),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: new2Ctrl,
                    obscureText: true,
                    decoration: InputDecoration(labelText: t.newPasswordRepeat),
                  ),
                  if (err != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(err!, style: const TextStyle(color: Colors.red)),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                child: Text(t.cancel),
              ),
              ElevatedButton(
                onPressed: busy ? null : _submit,
                child: busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(t.save),
              ),
            ],
          );
        },
      );
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final profileHint = t.profile_edit_hint ?? labelProfile;
    final passwordHint = t.password_change_hint ?? labelPassword;

    Widget action({
      required IconData icon,
      required String label,
      required String description,
      required Color color,
      required VoidCallback onTap,
    }) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withOpacity(0.18), cs.surfaceVariant.withOpacity(.45)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withOpacity(.35), width: 1),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(.22),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: cs.onSurface.withOpacity(.7)),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            action(
              icon: Icons.manage_accounts_outlined,
              label: labelProfile,
              description: profileHint,
              color: cs.primary,
              onTap: _openProfile,
            ),
            const SizedBox(height: 16),
            action(
              icon: Icons.lock_reset_outlined,
              label: labelPassword,
              description: passwordHint,
              color: cs.tertiary,
              onTap: _openPasswordChange,
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomerDetails(Map<String, Object?> c) {
    String s(Object? v) => (v ?? '').toString();

    final name       = s(c['name']);
    final email      = s(c['email']);
    final company    = s(c['company']);
    final address    = s(c['address']);
    final zip        = s(c['zip']);
    final city       = s(c['city']);
    final country    = s(c['country']);
    final phone      = s(c['phone']);
    final customerNo = s(c['customerNo']);
    final vatId      = s(c['vatId']);

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final contactTitle = name.isNotEmpty
        ? name
        : (email.isNotEmpty ? email : (company.isNotEmpty ? company : context.t.customer_label));
    final location = [zip, city].where((e) => e.trim().isNotEmpty).join(' ');

    Widget detailRow({required IconData icon, required Widget child}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(child: child),
          ],
        ),
      );
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(contactTitle),
        content: SingleChildScrollView(
          child: ListBody(
            children: [
              if (company.isNotEmpty)
                detailRow(
                  icon: Icons.apartment_outlined,
                  child: Text(company, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
              if (email.isNotEmpty)
                detailRow(
                  icon: Icons.alternate_email,
                  child: SelectableText(email),
                ),
              if (phone.isNotEmpty)
                detailRow(
                  icon: Icons.phone_outlined,
                  child: Text('${context.t.phone ?? 'Telefon'}: $phone'),
                ),
              if (address.isNotEmpty)
                detailRow(
                  icon: Icons.location_on_outlined,
                  child: Text(address),
                ),
              if (location.isNotEmpty)
                detailRow(
                  icon: Icons.map_outlined,
                  child: Text(location),
                ),
              if (country.isNotEmpty)
                detailRow(
                  icon: Icons.public,
                  child: Text(country),
                ),
              if (customerNo.isNotEmpty)
                detailRow(
                  icon: Icons.badge_outlined,
                  child: Text('${context.t.customer_number_label ?? 'Kundennr.'}: $customerNo'),
                ),
              if (vatId.isNotEmpty)
                detailRow(
                  icon: Icons.receipt_long_outlined,
                  child: Text('${context.t.vat_id_label ?? 'USt-Id.'}: $vatId'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(context.t.close ?? 'Schließen')),
        ],
      ),
    );
  }
}

// ----------------- UI Bausteine -----------------

class _Card extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final Widget child;
  const _Card({required this.title, this.actions, required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final width   = MediaQuery.of(context).size.width;
    final isPhone = width < 600;
    final fsTitle = isPhone ? 17.0 : 19.0;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: fsTitle)),
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

/// Menü-Kachel (kompakt, skaliert)
class _MenuCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final int? count;
  final VoidCallback onTap;
  final bool compact;
  final double scale;

  const _MenuCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.count,
    this.compact = false,
    this.scale = 1.0,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg1 = color.withOpacity(0.08);
    final bg2 = cs.surface;
    final ts = MediaQuery.of(context).textScaleFactor.clamp(1.0, 1.15);
    final isPhone = MediaQuery.of(context).size.width < 600;

    final pad      = (compact ? 12.0 : 18.0) * scale;
    final iconSize = (compact ? 24.0 : 30.0) * scale;
    final circle   = (compact ? 44.0 : 52.0) * scale;

    final titleSizeBase = (compact ? 15.5 : 18.0);
    final subSizeBase   = (compact ? 13.0 : 14.0);
    final titleSize     = (titleSizeBase * scale * (isPhone ? 1.00 : 1.05)) * ts;
    final subSize       = (subSizeBase   * scale * (isPhone ? 1.00 : 1.05)) * ts;

    final chevron = (compact ? 22.0 : 24.0) * scale;
    final radius  = (compact ? 16.0 : 20.0) * scale;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [bg1, bg2],
          ),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: compact ? 10 : 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: circle,
                  height: circle,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: iconSize),
                ),
                if (count != null)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.35),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(width: compact ? 10 * scale : 14 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: titleSize,
                      letterSpacing: .2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface.withOpacity(0.7),
                      fontSize: subSize,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: chevron),
          ],
        ),
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final Map<String, Object?> data;
  final bool isNew;
  final AppLocalizations t;
  final VoidCallback onOpen;
  final VoidCallback onInfo;
  final VoidCallback onRemove;

  const _CustomerTile({
    required this.data,
    required this.isNew,
    required this.t,
    required this.onOpen,
    required this.onInfo,
    required this.onRemove,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    String pick(String key) => (data[key] ?? '').toString();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final email = pick('email');
    final contact = pick('name');
    final company = pick('company');
    final phone = pick('phone');
    final address = pick('address');
    final zip = pick('zip');
    final city = pick('city');
    final country = pick('country');

    final contactLabel = contact.isNotEmpty
        ? contact
        : (company.isNotEmpty ? company : email);

    final locationParts = <String>[
      [zip, city].where((e) => e.trim().isNotEmpty).join(' ').trim(),
      country.trim(),
    ].where((e) => e.isNotEmpty).toList();
    final location = locationParts.join(' · ');

    final accent = isNew ? cs.primary : cs.secondary;
    final initialsSource = contactLabel.trim().isNotEmpty ? contactLabel.trim() : email.trim();
    final initials = initialsSource.isNotEmpty ? initialsSource[0].toUpperCase() : 'C';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Color.alphaBlend(cs.surfaceVariant.withOpacity(isNew ? 0.18 : 0.12), cs.surface),
            border: Border.all(color: cs.outlineVariant.withOpacity(isNew ? 0.65 : 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initials,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                contactLabel,
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isNew) const SizedBox(width: 8),
                            if (isNew) const _PulseNewBadge(),
                          ],
                        ),
                        if (company.isNotEmpty && company != contactLabel) ...[
                          const SizedBox(height: 4),
                          Text(
                            company,
                            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    children: [
                      IconButton(
                        tooltip: t.showDetails ?? 'Details anzeigen',
                        icon: const Icon(Icons.info_outline),
                        onPressed: onInfo,
                        style: IconButton.styleFrom(
                          backgroundColor: cs.surfaceVariant.withOpacity(0.25),
                          foregroundColor: cs.onSurface,
                          padding: const EdgeInsets.all(10),
                          minimumSize: const Size(40, 40),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      IconButton(
                        tooltip: t.deleteAdd,
                        icon: const Icon(Icons.link_off),
                        onPressed: onRemove,
                        style: IconButton.styleFrom(
                          foregroundColor: cs.error,
                          padding: const EdgeInsets.all(10),
                          minimumSize: const Size(40, 40),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (address.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  address,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.3),
                ),
              ],
              if (phone.isNotEmpty || location.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    if (phone.isNotEmpty)
                      _CustomerInfoChip(
                        icon: Icons.phone_outlined,
                        label: phone,
                      ),
                    if (location.isNotEmpty)
                      _CustomerInfoChip(
                        icon: Icons.location_on_outlined,
                        label: location,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _CustomerInfoChip({required this.icon, required this.label, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ComplaintTile extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool isClosed;
  final void Function(String ticket, bool approve)? onDecision;
  final void Function(String ticket)? onWithdraw;
  final bool useColoredButtons;
  final String? customerOverride; // Anzeige „Kunde“ (Firma bevorzugt)
  final String? createdOverride;  // Anzeige „Angelegt“ formatiert

  const _ComplaintTile({
    required this.data,
    required this.isClosed,
    this.onDecision,
    this.onWithdraw,
    this.useColoredButtons = false,
    this.customerOverride,
    this.createdOverride,
    super.key,
  });

  @override
  State<_ComplaintTile> createState() => _ComplaintTileState();
}

class _ComplaintTileState extends State<_ComplaintTile> {
  bool _expanded = false; // Toggle für Details

  String _pick(Map<String, dynamic>? p, List<String> keys) {
    if (p == null) return '';
    for (final k in keys) {
      final v = p[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  String? _pickOrNull(Map<String, dynamic>? p, List<String> keys) {
    final s = _pick(p, keys);
    return s.isEmpty ? null : s;
  }

  String _localizeDecisionText(AppLocalizations t, String raw) {
    final value = raw.trim().toLowerCase();
    if (value == 'accepted') return t.decision_accepted;
    if (value == 'rejected') return t.decision_rejected;
    if (value == 'pending') return t.decision_pending ?? raw;
    return raw;
  }

  String? _resolveProductArea(AppLocalizations t, String? segment, String? productType) {
    final values = <String?>[segment, productType];
    for (final raw in values) {
      final v = (raw ?? '').trim().toLowerCase();
      if (v.isEmpty) continue;
      if (v.contains('zahnarzt') || v.contains('zahnmedizin')) return t.product_area_medical;
      if (v.contains('dentist') || v == t.segment_dentist.toLowerCase()) return t.product_area_medical;
      if (v.contains('dentallabor') || v.contains('zahntechnik')) return t.product_area_lab;
      if (v.contains('lab') || v == t.segment_lab.toLowerCase()) return t.product_area_lab;
    }
    return null;
  }

  Color _decisionTint(ColorScheme cs, String normalized) {
    final value = normalized.trim().toLowerCase();
    if (value == 'accepted') return Colors.green.shade600;
    if (value == 'rejected') return Colors.red.shade600;
    if (value == 'pending') return Colors.amber.shade700;
    return cs.primary;
  }

  Widget _infoPill(BuildContext context, {required IconData icon, required String text}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.42),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(
    BuildContext context, {
    required IconData icon,
    required String text,
    double? maxWidth,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 3,                 // <- mehr Zeilen erlaubt
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );

    // maxWidth (falls gesetzt) respektieren – keine künstliche Mindestbreite
    if (maxWidth != null && maxWidth.isFinite) {
      return SizedBox(width: maxWidth, child: chip);
    }
    return chip; // volle Breite zulassen
  }

  Widget _decisionBadge(BuildContext context, {required IconData icon, required String text, required Color color}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailField(BuildContext context, {required String label, required String value}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.32),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _decisionButtons(AppLocalizations t, String ticket) {
    if (widget.onDecision == null) return const SizedBox.shrink();

    Widget buildButton({required IconData icon, required Color color, required bool approve}) {
      return IconButton(
        onPressed: () => widget.onDecision!(ticket, approve),
        icon: Icon(icon, size: 22),
        tooltip: approve ? t.decision_accepted : t.decision_rejected,
        style: IconButton.styleFrom(
          backgroundColor: color.withOpacity(0.12),
          foregroundColor: color,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
    }

    return Wrap(
      spacing: 14,
      runSpacing: 10,
      alignment: WrapAlignment.end,
      children: [
        buildButton(icon: Icons.check_rounded, color: Colors.green.shade600, approve: true),
        buildButton(icon: Icons.close_rounded, color: Colors.red.shade600, approve: false),
      ],
    );
  }

  Widget _metaRowFullWidth(BuildContext context,
      {required IconData icon, required String text}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 3,
              softWrap: true,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    final ticket   = (widget.data['ticket'] ?? '').toString();
    final status   = (widget.data['status'] ?? '').toString();
    final decision = (widget.data['decision'] ?? '').toString();
    final repDecision = (widget.data['repDecision'] ?? '').toString();

    final created   = widget.createdOverride ?? (widget.data['createdAt'] ?? widget.data['created'] ?? '').toString();
    final customer  = widget.customerOverride ?? (widget.data['customerEmail'] ?? widget.data['email'] ?? '').toString();

    final Map<String, dynamic>? p =
        (widget.data['payload'] is Map) ? (widget.data['payload'] as Map).cast<String, dynamic>() : null;

    final segment      = _pickOrNull(p, ['segment','customer_segment','segment_code']);
    final productType  = _pickOrNull(p, ['product_type','productType','type']);
    final articleNo    = _pickOrNull(p, ['article','article_no','articleNumber','artnr']);
    final batch        = _pickOrNull(p, ['batch','batch_no','lot','lot_no','charge','lotnumber','lot_number']);
    final serial       = _pickOrNull(p, ['serial','serial_no','sn']);
    final qty          = _pickOrNull(p, ['qty','quantity','amount','menge']);
    final reason       = _pickOrNull(p, ['reason','failure_reason','cause']);
    final internalNo  = _pickOrNull(p, ['internalComplaintNo','internalComplaint','internalNo','internal','complaintNo','complaint_no','reklamationsnummer','rekl_nr','reklamationsnr']) ?? (widget.data['internalNo']?.toString());

    final desc         = _pickOrNull(p, ['desc','description','comment','details','failure_desc']);
    final customerWish = _pickOrNull(p, ['handling','customer_wish','customerWish','wish','treatment_wish']);

    final returned     = _pickOrNull(p, ['returned']);
    final applied      = _pickOrNull(p, ['applied']);
    final injury       = _pickOrNull(p, ['injury']);
    final injuryDesc   = _pickOrNull(p, ['injuryDesc']);

    final productArea  = _resolveProductArea(t, segment, productType);
    final articleLabel = articleNo == null || articleNo.isEmpty
        ? null
        : productArea == null
            ? articleNo
            : '$articleNo · $productArea';

    final createdLabel = created.trim().isEmpty ? null : created.trim();
    final decisionLabel = decision.trim().isEmpty ? null : _localizeDecisionText(t, decision);
    final repDecisionLabel = repDecision.trim().isEmpty ? null : _localizeDecisionText(t, repDecision);
    final repDecisionNormalized = repDecision.trim().toLowerCase();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Color background = Color.alphaBlend(cs.surfaceVariant.withOpacity(0.14), cs.surface);
    Color borderColor = cs.outlineVariant.withOpacity(0.45);

    if (repDecisionNormalized == 'accepted') {
      background = Color.alphaBlend(Colors.green.shade500.withOpacity(0.08), cs.surface);
      borderColor = Colors.green.shade400.withOpacity(0.4);
    } else if (repDecisionNormalized == 'rejected') {
      background = Color.alphaBlend(Colors.red.shade500.withOpacity(0.08), cs.surface);
      borderColor = Colors.red.shade400.withOpacity(0.4);
    } else if (repDecisionNormalized == 'pending') {
      background = Color.alphaBlend(Colors.amber.shade700.withOpacity(0.08), cs.surface);
      borderColor = Colors.amber.shade600.withOpacity(0.38);
    }

    if (widget.isClosed) {
      background = Color.alphaBlend(cs.surfaceContainerHighest.withOpacity(0.4), background);
      borderColor = Color.alphaBlend(cs.outline.withOpacity(0.25), borderColor);
    }

    final decisionBadges = <Widget>[];
    if (decisionLabel != null) {
      decisionBadges.add(_decisionBadge(context, icon: Icons.gavel_outlined, text: decisionLabel, color: cs.primary));
    }
    if (repDecisionLabel != null) {
      final icon = repDecisionNormalized == 'rejected'
          ? Icons.thumb_down_alt_outlined
          : Icons.thumb_up_alt_outlined;
      decisionBadges.add(
        _decisionBadge(
          context,
          icon: icon,
          text: repDecisionLabel,
          color: _decisionTint(cs, repDecisionNormalized),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = MediaQuery.of(context).size.width < 600;
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final double halfWidth = (availableWidth - 12) / 2;

        // === Desktop/Tablet-Chips (2 Spalten) ===
        final desktopChips = <Widget>[];
        if (customer.isNotEmpty) {
          desktopChips.add(_metaChip(
            context,
            icon: Icons.person_outline_rounded,
            text: customer,
            maxWidth: halfWidth,
          ));
        }
        if (articleLabel != null) {
          desktopChips.add(_metaChip(
            context,
            icon: Icons.qr_code_2_outlined,
            text: articleLabel!,
            maxWidth: halfWidth,
          ));
        }
        // NEU: Charge / LOT statt Datum/Uhrzeit
        if ((batch ?? '').trim().isNotEmpty) {
          desktopChips.add(_metaChip(
            context,
            icon: Icons.inventory_2_outlined,
            text: batch!.trim(),
            maxWidth: halfWidth,
          ));
        }
        if (internalNo != null && internalNo!.trim().isNotEmpty) {
          desktopChips.add(_metaChip(
            context,
            icon: Icons.confirmation_number_outlined,
            text: internalNo!.trim(),
            maxWidth: halfWidth,
          ));
        }

        // === Phone: volle Breite, untereinander ===
        final phoneRows = <Widget>[
          if (customer.isNotEmpty)
            _metaRowFullWidth(context,
                icon: Icons.person_outline_rounded, text: customer),
          if (articleLabel != null)
            _metaRowFullWidth(context,
                icon: Icons.qr_code_2_outlined, text: articleLabel!),
          // NEU: Charge / LOT statt Datum/Uhrzeit
          if ((batch ?? '').trim().isNotEmpty)
            _metaRowFullWidth(context,
                icon: Icons.inventory_2_outlined, text: batch!.trim()),
          if (internalNo != null && internalNo!.trim().isNotEmpty)
            _metaRowFullWidth(context,
                icon: Icons.confirmation_number_outlined, text: internalNo!.trim()),
        ];

        // Header (Phone: Ticket allein + Status darunter; Desktop: links Ticket+Status+Chips, rechts Ampel)
        final showAmpel = repDecision.trim().isNotEmpty;
        final Widget topHeader = isPhone
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ticketzeile allein
                  Text(
                    ticket.isEmpty ? '(ohne Ticket)' : ticket,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // kleiner Status darunter
                  _StatusChip(
                    status: status,
                    decision: decision,
                    closed: widget.isClosed,
                    compact: true,
                  ),
                  if (showAmpel) ...[
                    const SizedBox(height: 8),
                    _RepTrafficLight(opinion: repDecision, compact: true),
                  ],
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // linke Spalte
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ticket.isEmpty ? '(ohne Ticket)' : ticket,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _StatusChip(
                          status: status,
                          decision: decision,
                          closed: widget.isClosed,
                          compact: true,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: desktopChips,
                        ),
                      ],
                    ),
                  ),
                  // rechte Spalte: nur Ampel wenn vorhanden
                  if (showAmpel) const SizedBox(width: 12),
                  if (showAmpel)
                    _RepTrafficLight(opinion: repDecision, compact: true),
                ],
              );

        return AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(widget.isClosed ? 0.015 : 0.035),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1) Header (Phone/Desktop)
                topHeader,

                const SizedBox(height: 12),

                // 2) Nur Phone: zusätzliche Zeilen in Vollbreite
                if (isPhone) ...[
                  for (int i = 0; i < phoneRows.length; i++) ...[
                    phoneRows[i],
                    if (i != phoneRows.length - 1) const SizedBox(height: 8),
                  ],
                ],

                // 3) Entscheidungs-Badges (falls vorhanden)
                if (decisionBadges.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: decisionBadges,
                  ),
                ],

                const SizedBox(height: 14),

                // 4) Details-Button
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: const StadiumBorder(),
                      foregroundColor: cs.primary,
                      textStyle: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: AnimatedRotation(
                      turns: _expanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                    label: Text(
                      _expanded
                          ? (t.hideDetails ?? 'Details verbergen')
                          : (t.showDetails ?? 'Details anzeigen'),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 5) Detailsbereich (animiert)
                ClipRect(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    child: !_expanded
                        ? const SizedBox.shrink()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 16),
                              _buildDetails(
                                context,
                                segment: segment,
                                productType: productType,
                                productArea: productArea,
                                articleNo: articleNo,
                                batch: batch,
                                serial: serial,
                                qty: qty,
                                reason: reason,
                                desc: desc,
                                customerWish: customerWish,
                                returned: returned,
                                applied: applied,
                                injury: injury,
                                injuryDesc: injuryDesc,
                              ),
                            ],
                          ),
                  ),
                ),

                // 6) Aktionen (Entscheiden / Zurücknehmen)
                if (widget.onDecision != null &&
                    !widget.isClosed &&
                    repDecision.isEmpty) ...[
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _decisionButtons(t, ticket),
                  ),
                ],
                if (!widget.isClosed &&
                    repDecision.isNotEmpty &&
                    widget.onWithdraw != null) ...[
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      icon: const Icon(Icons.undo),
                      label:
                          Text(t.decision_withdraw ?? 'Entscheidung zurücknehmen'),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text(
                                    t.decision_withdraw ?? 'Entscheidung zurücknehmen'),
                                content: DialogContentScroll(
                                  child: Text(t.decision_withdraw_confirm ??
                                      'Möchtest du deine Entscheidung wirklich zurücknehmen?'),
                                ),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.of(ctx).pop(false),
                                      child: Text(t.cancel ?? 'Abbrechen')),
                                  ElevatedButton(
                                      onPressed: () => Navigator.of(ctx).pop(true),
                                      child: Text(t.ok ?? 'OK')),
                                ],
                              ),
                            ) ??
                            false;

                        if (ok) widget.onWithdraw!(ticket);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetails(
    BuildContext context, {
    String? segment,
    String? productType,
    String? productArea,
    String? articleNo,
    String? batch,
    String? serial,
    String? qty,
    String? reason,
    String? desc,
    String? customerWish,
    String? returned,
    String? applied,
    String? injury,
    String? injuryDesc,
  }) {
    final t = context.t;
    final fields = <_DetailFieldData>[];

    void add(String label, String? value, {bool wide = false}) {
      final v = (value ?? '').trim();
      if (v.isEmpty) return;
      fields.add(_DetailFieldData(label: label, value: v, wide: wide));
    }

    add(t.segment, segment);
    add(t.product_type, productType);
    add(t.product_area_label ?? 'Produktbereich', productArea);
    add(t.articleNo, articleNo);
    add('${t.batch ?? 'Charge'} / LOT', batch);
    add(t.serial_number ?? 'Seriennummer', serial);
    add(t.quantity ?? 'Menge', qty);
    add(t.problem_desc ?? 'Fehler / Beschreibung', desc, wide: true);
    add(t.reason_label ?? 'Grund / Ursache', reason, wide: true);
    add(t.handling ?? 'Wunsch des Kunden', customerWish, wide: true);
    add(t.returned_question ?? 'Produkte zurückgeschickt?', returned);
    add(t.applied_to_patient ?? 'Am Patienten angewendet?', applied);
    add(t.injury_question ?? 'Verletzung?', injury);
    add(t.injury_desc ?? 'Verletzungsbeschreibung', injuryDesc, wide: true);

    if (fields.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final maxWidth = constraints.maxWidth;
        final multiColumn = maxWidth >= 560;
        final columnWidth = multiColumn ? (maxWidth - 12) / 2 : maxWidth;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.32),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.details ?? 'Details',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final field in fields)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: field.wide || !multiColumn ? maxWidth : columnWidth,
                        minWidth: field.wide || !multiColumn ? maxWidth : math.min(columnWidth, maxWidth),
                      ),
                      child: _detailField(
                        context,
                        label: field.label,
                        value: field.value,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DetailFieldData {
  final String label;
  final String value;
  final bool wide;

  const _DetailFieldData({required this.label, required this.value, this.wide = false});
}

// ======================================
//  Ampel-Widget (wie Admin, 3 Lichter)
// ======================================
class _RepTrafficLight extends StatelessWidget {
  final String? opinion;
  final bool compact;
  const _RepTrafficLight({required this.opinion, this.compact = false, super.key});

  @override
  Widget build(BuildContext context) {
    final v = (opinion ?? '').trim().toLowerCase();
    if (v.isEmpty) return const SizedBox.shrink();

    const colRed   = Colors.red;
    const colAmber = Colors.amber;
    const colGreen = Colors.green;

    final onRed   = v == 'rejected';
    final onGreen = v == 'accepted';
    final onAmber = !(onRed || onGreen);

    if (!(onRed || onAmber || onGreen)) return const SizedBox.shrink();

    final size   = compact ? 10.0 : 12.0;
    final gap    = compact ? 4.0  : 6.0;
    final radius = size / 2;

    Widget dot(Color c, bool on) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: on ? c : c.withOpacity(0.18),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: on ? c : c.withOpacity(0.6), width: 1),
        boxShadow: on ? [BoxShadow(color: c.withOpacity(0.45), blurRadius: 6)] : const [],
      ),
    );

    String label;
    Color labelColor;
    if (onGreen)      { label = context.t.decision_accepted; labelColor = colGreen; }
    else if (onRed)   { label = context.t.decision_rejected; labelColor = colRed; }
    else              { label = context.t.no_decision_yet ?? 'Noch keine Entscheidung'; labelColor = colAmber; }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.35),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              dot(colRed, onRed),
              SizedBox(height: gap),
              dot(colAmber, onAmber),
              SizedBox(height: gap),
              dot(colGreen, onGreen),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${context.t.my_decision ?? 'Meine Bewertung'}: $label',
          style: TextStyle(fontWeight: FontWeight.w700, color: labelColor, fontSize: compact ? 12.5 : 13.5),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final String decision;
  final bool closed;
  final bool compact; // NEU: kleiner Style
  const _StatusChip({
    required this.status,
    required this.decision,
    required this.closed,
    this.compact = false, // default: wie bisher
    super.key,
  });

  int? _statusNumber() {
    final trimmed = status.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
  }

  String _statusLabel(AppLocalizations t, int? value) {
    final decisionLower = decision.trim().toLowerCase();
    switch (value) {
      case 1: return t.status_sent;
      case 2: return t.status_in_progress;
      case 3: return t.status_question;
      case 4:
        if (decisionLower == 'rejected') return t.status_rejected;
        if (decisionLower == 'accepted') return t.status_accepted;
        return t.status_decision;
      case 5: return t.status_rework;
      case 6: return t.status_closed;
      default:
        final raw = status.trim();
        return raw.isEmpty ? t.status_unknown : raw;
    }
  }

  Color _statusColor(BuildContext context, int? value) {
    final decisionLower = decision.trim().toLowerCase();
    if (closed) return Colors.grey;
    switch (value) {
      case 1: return Colors.blue;
      case 2: return Colors.amber.shade800;
      case 3: return Colors.orange;
      case 4:
        if (decisionLower == 'rejected') return Colors.red;
        if (decisionLower == 'accepted') return Colors.green;
        return Colors.grey;
      case 5: return Colors.amber;
      case 6: return Colors.green;
      default: return Theme.of(context).colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final number = _statusNumber();
    final label = _statusLabel(t, number);
    final color = _statusColor(context, number);

    final padV = compact ? 4.0  : 6.0;
    final padH = compact ? 8.0  : 10.0;
    final icon = compact ? 14.0 : 16.0;
    final fs   = compact ? 12.0 : 13.0;
    final rad  = compact ? 16.0 : 20.0;
    final borderOpacity = compact ? .55 : .70;
    final chipColor = color.withOpacity(compact ? .10 : .14);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(rad),
        border: Border.all(color: color.withOpacity(borderOpacity)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag_rounded, size: icon, color: color),
          const SizedBox(width: 6),
          Text(
            '${t.status ?? "Status"}: $label',
            style: TextStyle(color: color, fontSize: fs, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _RepDecisionChip extends StatelessWidget {
  final String repDecision; // '', 'accepted', 'rejected'
  const _RepDecisionChip({required this.repDecision, super.key});

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final String label;

    if (repDecision == 'accepted') {
      color = Colors.green;
      label = (context.t.decision_accepted);
    } else if (repDecision == 'rejected') {
      color = Colors.red;
      label = (context.t.decision_rejected);
    } else {
      color = Colors.amber;
      label = (context.t.no_decision_yet ?? 'Noch keine Entscheidung');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Text(
            (context.t.my_decision ?? 'Meine Bewertung') + ': ' + label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================================================
///  Visuelle Helfer: sanftes Fade-in + pulsierender NEW-Badge
/// ===============================================================

class _FadeInOnce extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final int durationMs;
  const _FadeInOnce({
    required this.child,
    this.delayMs = 0,
    this.durationMs = 320,
    super.key,
  });

  @override
  State<_FadeInOnce> createState() => _FadeInOnceState();
}

class _FadeInOnceState extends State<_FadeInOnce> with SingleTickerProviderStateMixin {
  double _opacity = 0.0;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (!mounted) return;
      setState(() => _opacity = 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _opacity,
      duration: Duration(milliseconds: widget.durationMs),
      curve: Curves.easeOut,
      child: widget.child,
    );
  }
}

class _PulseNewBadge extends StatefulWidget {
  const _PulseNewBadge({super.key});

  @override
  State<_PulseNewBadge> createState() => _PulseNewBadgeState();
}

class _PulseNewBadgeState extends State<_PulseNewBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _ac;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.35, end: 1.0).animate(CurvedAnimation(
      parent: _ac,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(.15),
          border: Border.all(color: Colors.orange),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          'NEW',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 11,
            color: Colors.orange,
            letterSpacing: .4,
          ),
        ),
      ),
    );
  }
}

/// ==============================
///  Neue Header- & KPI-Widgets
/// ==============================
class _WelcomeHeader extends StatelessWidget {
  final Map<String, dynamic>? me;
  final int open;
  final int all;
  final int rejected;
  final int finished;
  final Color brand;

  const _WelcomeHeader({
    required this.me,
    required this.open,
    required this.all,
    required this.rejected,
    required this.finished,
    required this.brand,
  });

  String _initials(Map<String, dynamic>? me) {
    final f = (me?['firstName'] ?? '').toString().trim();
    final l = (me?['lastName'] ?? '').toString().trim();
    if (f.isEmpty && l.isEmpty) {
      final e = (me?['email'] ?? '').toString();
      return e.isNotEmpty ? e[0].toUpperCase() : 'R';
    }
    return ((f.isNotEmpty ? f[0] : '') + (l.isNotEmpty ? l[0] : '')).toUpperCase();
    }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final name = [
      (me?['firstName'] ?? '').toString().trim(),
      (me?['lastName'] ?? '').toString().trim()
    ].where((e) => e.isNotEmpty).join(' ');
    final email = (me?['email'] ?? '').toString();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [brand.withOpacity(.14), cs.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: brand.withOpacity(.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: brand.withOpacity(.35)),
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials(me),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: brand,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .2,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isNotEmpty ? name : t.rep_dashboard,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: .2,
                      ),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (ctx, c) {
              final isNarrow = c.maxWidth < 520;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _KpiChip(icon: Icons.report_gmailerrorred_outlined, label: 'Offen', value: open, color: Colors.red),
                  _KpiChip(icon: Icons.all_inbox_outlined, label: 'Alle', value: all, color: brand),
                  _KpiChip(icon: Icons.thumb_down_alt_outlined, label: 'Abgelehnt', value: rejected, color: Colors.orange),
                  _KpiChip(icon: Icons.verified_outlined, label: 'Abgeschlossen', value: finished, color: Colors.green),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _KpiChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color color;

  const _KpiChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withOpacity(.08), cs.surface),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(.35)),
        boxShadow: [BoxShadow(color: color.withOpacity(.08), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '$value',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  const _EmptyState({required this.icon, required this.title, super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
