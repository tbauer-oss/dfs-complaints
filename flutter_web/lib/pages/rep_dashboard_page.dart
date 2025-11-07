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

  /// Kundenliste (aus Backend normalisiert)
  List<Map<String, Object?>> _customers = <Map<String, Object?>>[];

  /// Reklamationen (aus Backend)
  List<Map<String, dynamic>> _complaints = [];

  bool _loading = true;
  String? _err;

  // alter Filter bleibt intern für _filteredComplaints
  _RepFilter _filter = _RepFilter.all;

  // neue Menü-/Seitenlogik
  _RepView _view = _RepView.menu;

  // "Alle Reklamationen": Filter
  final TextEditingController _companyCtrl = TextEditingController();
  bool _showClosedAll = false;
  bool _showRejectedAll = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
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

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _err = null;
    });

    try {
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
      final em = (c['email'] ?? '').toString();
      final co = (c['company'] ?? '').toString();
      if (em.isNotEmpty && co.isNotEmpty) m[em] = co;
    }
    return m;
  }

  // ------ Anzeige-Helper ------
  String _displayCustomerFor(Map<String, dynamic> c) {
    final em = (c['customerEmail'] ?? c['email'] ?? '').toString();
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
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (Route<dynamic> r) => false);
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

  // ---- Seite: Offene Reklamationen ----
  Widget _buildOpenComplaints() {
    final t = context.t;
    final items = _complaints.where((c) => !_isClosed(c)).toList(growable: false);

    return _Card(
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
                  useColoredButtons: true,
                  customerOverride: customerDisplay,
                  createdOverride: createdDisplay,
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemCount: items.length,
            ),
    );
  }

  // ---- Seite: Alle Reklamationen ----
  Widget _buildAllComplaints() {
    final t = context.t;
    final query = _companyCtrl.text.trim().toLowerCase();

    List<Map<String, dynamic>> list = List<Map<String, dynamic>>.from(_complaints);

    if (!_showClosedAll) {
      list = list.where((c) => !_isClosed(c)).toList();
    }
    if (_showRejectedAll) {
      list = list.where(_isRejected).toList();
    }
    if (query.isNotEmpty) {
      list = list.where((c) {
        final em = (c['customerEmail'] ?? c['email'] ?? '').toString();
        final co = (_emailToCompany[em] ?? '').toLowerCase();
        return co.contains(query);
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
                  width: 280,
                  child: TextField(
                    controller: _companyCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Firmenname filtern',
                      prefixIcon: Icon(Icons.search),
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
                      onDecision: (c['decision'] ?? '') == '' && !_isClosed(c)
                          ? _decideComplaint
                          : null,
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
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  leading: const Icon(Icons.apartment_outlined),
                  title: Text(
                    (() {
                      final comp = (c['company'] ?? '').toString();
                      final nm   = (c['name'] ?? '').toString();
                      final em   = (c['email'] ?? '').toString();
                      if (comp.isNotEmpty) return comp;
                      if (nm.isNotEmpty)   return nm;
                      return em;
                    })(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    (() {
                      final nm = (c['name'] ?? '').toString();
                      final em = (c['email'] ?? '').toString();
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
                        onPressed: () => _showCustomerDetails(c),
                      ),
                      IconButton(
                        icon: const Icon(Icons.link_off),
                        tooltip: t.deleteAdd,
                        onPressed: () => _unassignCustomer((c['email'] ?? '').toString()),
                      ),
                    ],
                  ),
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
        MaterialPageRoute(builder: (_) => RepProfilePage(api: widget.api)), // Profilseite (ohne Passwort)
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
              err = t.errorGeneric?.replaceFirst('{msg}', t.password_required ?? 'Bitte alle Felder ausfüllen') ?? 'Fehler: Bitte alle Felder ausfüllen';
              (ctx as Element).markNeedsBuild();
              return;
            }
            if (n1 != n2) {
              err = t.errorGeneric?.replaceFirst('{msg}', t.password_mismatch ?? 'Passwörter stimmen nicht überein') ?? 'Fehler: Passwörter stimmen nicht überein';
              (ctx as Element).markNeedsBuild();
              return;
            }
            busy = true;
            (ctx as Element).markNeedsBuild();
            try {
              // HINWEIS: Falls dein Api-Methodenname abweicht, sag Bescheid – ich passe exakt an.
              await widget.api.repChangePassword(oldPw, n1);
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
                  decoration: InputDecoration(labelText: t.password_old ?? 'Altes Passwort'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: new1Ctrl,
                  obscureText: true,
                  decoration: InputDecoration(labelText: t.password_new ?? 'Neues Passwort'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: new2Ctrl,
                  obscureText: true,
                  decoration: InputDecoration(labelText: t.password_new_repeat ?? 'Neues Passwort (Wiederholung)'),
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
          // Kopfzeile entfällt (kein doppelter Titel)
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
            onTap: _openPasswordChange, // eigener Dialog nur fürs Passwort
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
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
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

    final pad = (compact ? 12.0 : 18.0) * scale;
    final iconSize = (compact ? 22.0 : 28.0) * scale;
    final circle = (compact ? 40.0 : 48.0) * scale;
    final titleSize = (compact ? 14.0 : 16.0) * scale;
    final subSize = (compact ? 12.0 : 13.0) * scale;
    final chevron = (compact ? 20.0 : 22.0) * scale;
    final radius = (compact ? 16.0 : 20.0) * scale;

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
                          fontSize: 12,
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
  final bool useColoredButtons;
  final String? customerOverride; // Anzeige „Kunde“ (Firma bevorzugt)
  final String? createdOverride;  // Anzeige „Angelegt“ formatiert

  const _ComplaintTile({
    required this.data,
    required this.isClosed,
    this.onDecision,
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

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    final ticket   = (widget.data['ticket'] ?? '').toString();
    final status   = (widget.data['status'] ?? '').toString();
    final decision = (widget.data['decision'] ?? '').toString();

    final createdRaw   = widget.data['createdAt'] ?? widget.data['created'] ?? '';
    final created      = widget.createdOverride ?? createdRaw.toString();
    final customerRaw  = (widget.data['customerEmail'] ?? widget.data['email'] ?? '').toString();
    final customer     = widget.customerOverride ?? customerRaw;

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
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusChip(status: status, decision: decision, closed: widget.isClosed),
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
                    if (created.isNotEmpty)  _InfoCapsule('${t.created_at ?? 'Angelegt'}: $created'),
                    if (decision.isNotEmpty) _InfoCapsule('${t.decision}: $decision'),
                  ],
                ),
                if (widget.onDecision != null && !widget.isClosed) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: isNarrow ? Alignment.centerLeft : Alignment.centerRight,
                    child: _buttons(),
                  ),
                ],
              ],
            ),
          ),
        );
      },
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        style: TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(.9)),
      ),
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
      child: Text(
        'Status $status',
        style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
