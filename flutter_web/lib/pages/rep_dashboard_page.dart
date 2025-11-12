// lib/pages/rep_dashboard_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import 'rep_profile_page.dart';
import 'dart:html' as html;
import '../l10n/app_localizations.dart';
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
  final Set<String> _seenCustomers = <String>{};
  
  @override
  void initState() {
    super.initState();
    final loaded = _loadSeen();
    _seenCustomers
      ..clear()
      ..addAll(loaded);
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
  // Session prüfen (entfernt ungültiges repToken & verhindert leere Antworten)
  await widget.api.ensureRepSession();

  // 1) Liste über deinen ApiClient holen (kümmert sich um BaseURL, X-Gate, Bearer, Retry)
  List<Map<String, dynamic>> raw;
  try {
    raw = await widget.api.repAssignableCustomers(all: true);
  } catch (_) {
    // stabil bleiben
    return <Map<String, Object?>>[];
  }

  // 2) Normalisieren -> { email, label, assigned, assignedToLabel }
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

  // 3) Freie zuerst, danach alphabetisch
  out.sort((a, b) {
    final aa = (a['assigned'] == true);
    final bb = (b['assigned'] == true);
    if (aa != bb) return aa ? 1 : -1;
    return (a['label'] as String).toLowerCase().compareTo((b['label'] as String).toLowerCase());
  });

  return out;
}
  // ======= /FEHLENDE METHODE =======

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

      // 1) Spezifische Methode, falls vorhanden
      try { await dyn.repAssignmentNotify(payload); return; } catch (_) {}

      // 2) Admin-Notify
      try { await dyn.postJson('/api/admin/notify-rep-assignment', payload); return; } catch (_) {}

      // 3) Alternative Route
      try { await dyn.postJson('/api/rep/assignment/notify', payload); return; } catch (_) {}
    } catch (_) {
      // still ok – UI muss weiterlaufen
    }
  }

  // ==========================
  // Schöne Auswahlliste (Sheet)
  // ==========================
  Future<void> _assignCustomerDialog() async {
    final t = context.t;
    final options = await _fetchAssignableCustomers();

    if (!mounted) return;

    // Nichts da → hübscher leer-State
    if (options.isEmpty) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t.addCustomer),
          content: Text(t.noAddCustomer),
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
        // lokale Filterfunktion
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

        // Sektionen bilden
        List<Map<String, Object?>> free(List<Map<String, Object?>> src) =>
            src.where((o) => o['assigned'] != true).toList();
        List<Map<String, Object?>> taken(List<Map<String, Object?>> src) =>
            src.where((o) => o['assigned'] == true).toList();

        Future<void> doAssign(String email, String label) async {
          if (saving) return;
          saving = true;
          (ctx as Element).markNeedsBuild();

          try {
            // Session sicherstellen (falls Token abgelaufen)
            await widget.api.ensureRepSession();

            // Dein offizieller Client-Call -> erwartet 204
            await widget.api.repAssignCustomer(email);

            // optional: Notify schicken (deine Hilfsfunktion)
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

              // Sektion: freie Kunden
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

              // Sektion: bereits zugewiesen
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

  // >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
  // NUR HIER GEÄNDERT (Fix 1): ensureRepSession Ergebnis auswerten
  // >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
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

  // <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

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

            // Sprache – exakt wie in main.dart
            LangAction(onLocaleChanged: (l) => prefs.setLang(l.languageCode)),
            const SizedBox(width: 4),

            // Theme – globales Widget wie in main.dart (kein Reload)
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

  // ---- Menü (kompakt skaliert) ----
  Widget _buildMenu(int allCount, int openCount, int rejectedCount, int finishedCount) {
    return LayoutBuilder(builder: (ctx, c) {
      final width = c.maxWidth;
      final gridCount = width >= 1200 ? 4 : width >= 900 ? 3 : width >= 600 ? 2 : 1;
      final aspect = width >= 1400 ? 1.70 : width >= 1100 ? 1.60 : width >= 900 ? 1.55 : width >= 600 ? 1.45 : width >= 480 ? 1.50 : 1.75;
      final scale = width >= 1400 ? 0.84 : width >= 1100 ? 0.88 : width >= 900 ? 0.90 : width >= 600 ? 0.95 : 1.00;
      final compact = width < 600;

      return GridView.count(
        crossAxisCount: gridCount,
        crossAxisSpacing: compact ? 12 : 14,
        mainAxisSpacing: compact ? 12 : 14,
        padding: EdgeInsets.only(bottom: compact ? 4 : 8),
        childAspectRatio: aspect,
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
      );
    });
  }

  // ---- Seite: Offene Reklamationen (mit Firmen-Dropdown) ----
  Widget _buildOpenComplaints() {
    final t = context.t;

    // Firmenliste wie bei „Alle Reklamationen“
    final companies = _emailToCompany.values
        .where((s) => s.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    // Basissatz „offen“
    List<Map<String, dynamic>> items =
        _complaints.where((c) => !_isClosed(c)).toList(growable: false);

    // Firmenfilter anwenden, falls gesetzt
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
        // Filterleiste
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

        // Liste der offenen Reklamationen
        _Card(
          title: t.complaintsMyCustomer,
          child: items.isEmpty
              ? Text(t.noComplaintsFound)
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

    // Firmenliste aus Mapping ableiten
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
        // Filterleiste
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
        // Liste
        _Card(
          title: 'Alle Reklamationen',
          child: list.isEmpty
              ? Text(t.noComplaintsFound)
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
        ElevatedButton.icon(
          onPressed: _assignCustomerDialog,
          icon: const Icon(Icons.person_add_alt_1),
          label: Text(t.addCustomer),
        ),
      ],
      child: _customers.isEmpty
          ? Text(t.noAddCustomer)
          : ListView.separated(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              itemBuilder: (_, i) {
                final c = _customers[i];
                final email = (c['email'] ?? '').toString();
                final isNew = !_seenCustomers.contains(email.toLowerCase());

                final tile = InkWell(
                  onTap: () {
                    // Beim ersten Öffnen → NEW weg
                    _markCustomerSeen(email);
                    _showCustomerDetails(c);
                  },
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    leading: const Icon(Icons.apartment_outlined),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            (() {
                              final comp = (c['company'] ?? '').toString();
                              final nm   = (c['name'] ?? '').toString();
                              final em   = email;
                              if (comp.isNotEmpty) return comp;
                              if (nm.isNotEmpty)   return nm;
                              return em;
                            })(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isNew) const SizedBox(width: 8),
                        if (isNew)
                          const _PulseNewBadge(), // ← ersetzt den statischen NEW-Container (pulsierend)
                      ],
                    ),
                    subtitle: Text(
                      (() {
                        final nm = (c['name'] ?? '').toString();
                        final em = email;
                        if (nm.isNotEmpty && em.isNotEmpty) return '$nm • $em';
                        return nm.isNotEmpty ? nm : em;
                      })(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          tooltip: 'Details',
                          icon: const Icon(Icons.info_outline),
                          onPressed: () {
                            _markCustomerSeen(email);
                            _showCustomerDetails(c);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.link_off),
                          tooltip: t.deleteAdd,
                          onPressed: () => _unassignCustomer(email),
                        ),
                      ],
                    ),
                  ),
                );

                // Sanftes Aufleuchten (Fade-in) pro Karte, leicht gestaffelt
                return _FadeInOnce(
                  delayMs: 35 * i,
                  child: tile,
                );
              },
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemCount: _customers.length,
            ),
    );
  }

  // ---- Seite: Account – ohne Doppeltitel/Untertitel + getrennte PW-Änderung ----
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
              err = '${t.error ?? 'Fehler'}: Bitte alle Felder ausfüllen';
              (ctx as Element).markNeedsBuild();
              return;
            }
            if (n1 != n2) {
              err = '${t.error ?? 'Fehler'}: Passwörter stimmen nicht überein';
              (ctx as Element).markNeedsBuild();
              return;
            }
            busy = true;
            (ctx as Element).markNeedsBuild();
            try {
              // Server erwartet nur neues Passwort? (gemäß bisherigem Client)
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
            content: Column(
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

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined),
            title: Text(labelProfile),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openProfile,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.lock_reset_outlined),
            title: Text(labelPassword),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openPasswordChange,
          ),
        ],
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

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(company.isNotEmpty ? company : (name.isNotEmpty ? name : email)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (name.isNotEmpty)    Text(name),
            if (email.isNotEmpty)   SelectableText(email),
            const SizedBox(height: 8),
            if (address.isNotEmpty) Text(address),
            if (zip.isNotEmpty || city.isNotEmpty) Text('${zip.isNotEmpty ? '$zip ' : ''}$city'.trim()),
            if (country.isNotEmpty) Text(country),
            if (phone.isNotEmpty)   ...[
              const SizedBox(height: 8),
              Text('Tel.: $phone'),
            ],
            if (customerNo.isNotEmpty) Text('Kundennr.: $customerNo'),
            if (vatId.isNotEmpty)      Text('USt-Id.: $vatId'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Schließen')),
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
    // Responsive Titelgröße nur hier (mit context) berechnen:
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
    final iconSize = (compact ? 24.0 : 30.0) * scale;     // +2 px
    final circle   = (compact ? 44.0 : 52.0) * scale;     // +4 px

    final titleSizeBase = (compact ? 15.5 : 18.0);        // +1.5–2 px
    final subSizeBase   = (compact ? 13.0 : 14.0);        // +1 px
    final titleSize     = (titleSizeBase * scale * (isPhone ? 1.00 : 1.05)) * ts;
    final subSize       = (subSizeBase   * scale * (isPhone ? 1.00 : 1.05)) * ts;

    final chevron = (compact ? 22.0 : 24.0) * scale;      // +2 px
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
  bool _hoverAccept = false;
  bool _hoverReject = false;
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

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    final ticket   = (widget.data['ticket'] ?? '').toString();
    final status   = (widget.data['status'] ?? '').toString();
    final decision = (widget.data['decision'] ?? '').toString();
    final repDecision = (widget.data['repDecision'] ?? '').toString(); // 'accepted' | 'rejected' | ''

    final created   = widget.createdOverride ?? (widget.data['createdAt'] ?? widget.data['created'] ?? '').toString();
    final customer  = widget.customerOverride ?? (widget.data['customerEmail'] ?? widget.data['email'] ?? '').toString();
    
    final Map<String, dynamic>? p =
        (widget.data['payload'] is Map)
            ? (widget.data['payload'] as Map<dynamic, dynamic>).cast<String, dynamic>()
            : null;

    final segment      = _pickOrNull(p, ['segment','customer_segment','segment_code']);
    final productType  = _pickOrNull(p, ['product_type','productType','type']);
    final articleNo    = _pickOrNull(p, ['article','article_no','articleNumber','artnr']);
    final batch        = _pickOrNull(p, ['batch','batch_no','lot','lot_no']);
    final serial       = _pickOrNull(p, ['serial','serial_no','sn']);
    final qty          = _pickOrNull(p, ['qty','quantity','amount','menge']);
    final reason       = _pickOrNull(p, ['reason','failure_reason','cause']);

    // desc priorisieren
    final desc         = _pickOrNull(p, ['desc','description','comment','details','failure_desc']);
    final customerWish = _pickOrNull(p, ['handling','customer_wish','customerWish','wish','treatment_wish']);

    // NEU (aus complaint_form_page.dart)
    final returned     = _pickOrNull(p, ['returned']);   // 'Ja' | 'Nein'
    final applied      = _pickOrNull(p, ['applied']);    // 'Ja' | 'Nein' | ''
    final injury       = _pickOrNull(p, ['injury']);     // 'Ja' | 'Nein' | ''
    final injuryDesc   = _pickOrNull(p, ['injuryDesc']); // Freitext

    // kleine Punkt-Buttons (Gradient + Hover)
    Widget _dotButton({
      required bool positive,
      required String tooltip,
      required VoidCallback onTap,
      required bool hover,
      required ValueChanged<bool> setHover,
    }) {
      final gradient = positive
          ? const LinearGradient(colors: [Color(0xFF2ECC71), Color(0xFF27AE60)])
          : const LinearGradient(colors: [Color(0xFFE74C3C), Color(0xFFC0392B)]);
      final icon = positive ? Icons.check_rounded : Icons.close_rounded;

      return MouseRegion(
        onEnter: (_) => setHover(true),
        onExit: (_) => setHover(false),
        child: AnimatedScale(
          scale: hover ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: Tooltip(
            message: tooltip,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Ink(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: gradient,
                  boxShadow: [
                    BoxShadow(
                      color: (positive ? Colors.green : Colors.red).withOpacity(.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, size: 18, color: Colors.white),
              ),
            ),
          ),
        ),
      );
    }

    Widget _buttons() {
      if (widget.onDecision == null) return const SizedBox.shrink();
      if (widget.useColoredButtons) {
        return Wrap(
          spacing: 10,
          children: [
            _dotButton(
              positive: true,
              tooltip: '${t.decision}: ${t.decision_accepted}',
              onTap: () => widget.onDecision!(ticket, true),
              hover: _hoverAccept,
              setHover: (v) => setState(() => _hoverAccept = v),
            ),
            _dotButton(
              positive: false,
              tooltip: '${t.decision}: ${t.decision_rejected}',
              onTap: () => widget.onDecision!(ticket, false),
              hover: _hoverReject,
              setHover: (v) => setState(() => _hoverReject = v),
            ),
          ],
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '${t.decision}: ${t.decision_accepted}',
            icon: const Icon(Icons.check_circle_outline),
            onPressed: () => widget.onDecision!(ticket, true),
          ),
          IconButton(
            tooltip: '${t.decision}: ${t.decision_rejected}',
            icon: const Icon(Icons.cancel_outlined),
            onPressed: () => widget.onDecision!(ticket, false),
          ),
        ],
      );
    }



    return LayoutBuilder(
      builder: (ctx, cons) {
        final isNarrow = cons.maxWidth < 420;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.description_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ticket.isEmpty ? '(ohne Ticket)' : ticket,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusChip(status: status, decision: decision, closed: widget.isClosed),
                    const SizedBox(width: 6),
                    if ((repDecision).trim().isNotEmpty)
                      _RepTrafficLight(opinion: repDecision, compact: true),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (customer.isNotEmpty) _InfoCapsule('${t.customer_label}: $customer'),
                    if (widget.data['payload']?['article']?.toString().isNotEmpty ?? false)
                      _InfoCapsule('${t.articleNo}: ${widget.data['payload']['article']}'),
                    if (widget.data['payload']?['segment']?.toString().isNotEmpty ?? false)
                      _InfoCapsule('${t.segment}: ${widget.data['payload']['segment']}'),
                    if (created.isNotEmpty)
                      _InfoCapsule('${t.created_at ?? 'Angelegt'}: $created'),
                    if (decision.isNotEmpty)
                      _InfoCapsule('${t.decision ?? 'Admin-Entscheidung'}: $decision'),
                    if (repDecision.isNotEmpty)
                      _InfoCapsule('${t.my_decision ?? 'Meine Bewertung'}: $repDecision'),
                  ],
                ),              
                const SizedBox(height: 6),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                      label: Text(_expanded
                          ? (context.t.hideDetails ?? 'Details verbergen')
                          : (context.t.showDetails ?? 'Details anzeigen')),
                    ),
                  ],
                ),
                AnimatedCrossFade(
                  crossFadeState: _expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                  duration: const Duration(milliseconds: 160),
                  firstChild: _buildDetails(
                    context,
                    segment: segment,
                    productType: productType,
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
                  secondChild: const SizedBox.shrink(),
                ),
                
                if (widget.onDecision != null && !widget.isClosed && repDecision.isEmpty) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: isNarrow ? Alignment.centerLeft : Alignment.centerRight,
                    child: _buttons(),
                  ),
                ],
                if (!widget.isClosed && repDecision.isNotEmpty && widget.onWithdraw != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: isNarrow ? Alignment.centerLeft : Alignment.centerRight,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.undo),
                      label: Text(context.t.decision_withdraw ?? 'Entscheidung zurücknehmen'),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(context.t.decision_withdraw ?? 'Entscheidung zurücknehmen'),
                            content: Text(context.t.decision_withdraw_confirm ?? 'Möchtest du deine Entscheidung wirklich zurücknehmen?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(context.t.cancel)),
                              ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(context.t.ok ?? 'OK')),
                            ],
                          ),
                        ) ?? false;

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
    Widget kv(String label, String? value, {int maxLines = 2}) {
      final v = (value ?? '').trim();
      if (v.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 160, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
            const SizedBox(width: 8),
            Expanded(child: Text(v, maxLines: maxLines, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.30),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Details', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),

          kv('Segment', segment),
          kv('Produkttyp', productType),
          kv('Artikelnummer', articleNo),

          Row(
            children: [
              Expanded(child: kv('Charge / LOT', batch)),
              const SizedBox(width: 12),
              Expanded(child: kv('Seriennummer', serial)),
            ],
          ),

          // Menge: eigene, gut sichtbare Zeile
          kv('Menge', qty),

          kv('Fehler / Beschreibung', desc, maxLines: 6),
          kv('Grund / Ursache',       reason, maxLines: 4),
          kv('Wunsch des Kunden',     customerWish, maxLines: 3),

          // Zusätzliche Formularfelder
          kv('Produkte zurückgeschickt?', returned),
          kv('Am Patienten angewendet?',   applied),
          kv('Verletzung?',                injury),
          kv('Verletzungsbeschreibung',    injuryDesc, maxLines: 6),
        ],
      ),
    );
  }

}

// ---------- kleine UI-Helfer ----------

class _InfoCapsule extends StatelessWidget {
  final String text;
  const _InfoCapsule(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        style: TextStyle(fontSize: 13.5, color: cs.onSurface.withOpacity(.9)),
      ),
    );
  }
}

// ======================================
//  Ampel-Widget (wie Admin, 3 Lichter)
// ======================================
class _RepTrafficLight extends StatelessWidget {
  /// opinion: 'accepted' | 'rejected' | 'pending' | ''/null -> keine Anzeige
  final String? opinion;
  final bool compact; // für enge Layouts (z. B. Zeile neben Status)
  const _RepTrafficLight({required this.opinion, this.compact = false, super.key});

  @override
  Widget build(BuildContext context) {
    final v = (opinion ?? '').trim().toLowerCase();
    if (v.isEmpty) return const SizedBox.shrink(); // keine Ampel ohne Meinung

    const colRed   = Colors.red;
    const colAmber = Colors.amber;
    const colGreen = Colors.green;

    final onRed   = v == 'rejected';
    final onGreen = v == 'accepted';
    final onAmber = !(onRed || onGreen); // „pending“ / unklar → gelb

    // falls irgendein exotischer Wert, Ampel weglassen
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
  const _StatusChip({required this.status, required this.decision, required this.closed, super.key});

  @override
  Widget build(BuildContext context) {
    Color c;
    if (closed) {
      c = Colors.grey;
    } else if (decision == 'rejected') {
      c = Colors.red;
    } else if (decision == 'accepted') {
      c = Colors.green;
    } else {
      c = Theme.of(context).colorScheme.primary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(.12),
        border: Border.all(color: c),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('${context.t.status ?? 'Status'}: $status',
        style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _RepDecisionChip extends StatelessWidget {
  final String repDecision; // '', 'accepted', 'rejected'
  const _RepDecisionChip({required this.repDecision, super.key});

  @override
  Widget build(BuildContext context) {
    // Ampel: ''  -> gelb (noch keine Entscheidung)
    //         'accepted' -> grün
    //         'rejected' -> rot
    late final Color color;
    late final String label;

    if (repDecision == 'accepted') {
      color = Colors.green;
      label = (context.t.decision_accepted) /* z.B. "angenommen" */ ;
    } else if (repDecision == 'rejected') {
      color = Colors.red;
      label = (context.t.decision_rejected) /* z.B. "abgelehnt" */ ;
    } else {
      color = Colors.amber;
      label = (context.t.no_decision_yet ?? 'Noch keine Entscheidung');
    }

    final cs = Theme.of(context).colorScheme;

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
          // kleiner Punkt (Ampel)
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
