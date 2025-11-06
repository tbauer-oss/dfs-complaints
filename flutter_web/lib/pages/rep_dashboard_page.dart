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

  // Mapping E-Mail -> Firma (für Firmenfilter in "Alle Reklamationen")
  Map<String, String> get _emailToCompany {
    final m = <String, String>{};
    for (final c in _customers) {
      final em = (c['email'] ?? '').toString();
      final co = (c['company'] ?? '').toString();
      if (em.isNotEmpty && co.isNotEmpty) m[em] = co;
    }
    return m;
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

  // ---- Menü mit „schönen“ Kacheln im Admin-Stil ----
  Widget _buildMenu(int allCount, int openCount, int rejectedCount, int finishedCount) {
    return LayoutBuilder(builder: (ctx, c) {
      final width = c.maxWidth;
      final gridCount = width >= 1200 ? 4 : width >= 900 ? 3 : width >= 600 ? 2 : 1;

      return GridView.count(
        crossAxisCount: gridCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        padding: const EdgeInsets.only(bottom: 8),
        childAspectRatio: 1.2,
        children: [
          _MenuCard(
            color: Colors.red,
            icon: Icons.report_gmailerrorred_outlined,
            title: 'Offene Reklamationen',
            subtitle: 'Bearbeiten & Entscheiden',
            count: openCount,
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
            onTap: () => setState(() => _view = _RepView.all),
          ),
          _MenuCard(
            color: Colors.teal,
            icon: Icons.apartment_outlined,
            title: 'Kundendatenbank',
            subtitle: 'Firmen & Kontakte',
            count: _customers.length,
            onTap: () => setState(() => _view = _RepView.customers),
          ),
          _MenuCard(
            color: Colors.blueGrey,
            icon: Icons.person_outline,
            title: 'Mein Account',
            subtitle: 'Profil & Passwort',
            count: null,
            onTap: () => setState(() => _view = _RepView.account),
          ),
        ],
      );
    });
  }

  // ---- Seite: Offene Reklamationen (mobilfreundlich) ----
  Widget _buildOpenComplaints() {
    final t = context.t;
    final items = _complaints.where((c) => !_isClosed(c)).toList(growable: false);

    return _Card(
      title: t.complaintsMyCustomer,
      child: items.isEmpty
          ? Text(t.noComplaintsFound)
          : ListView.separated(
              // jetzt scrollbar
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              itemBuilder: (_, i) {
                final c = items[i];
                return _ComplaintTile(
                  data: c,
                  isClosed: false,
                  onDecision: (ticket, approve) => _decideComplaint(ticket, approve),
                  useColoredButtons: true, // -> grün/rot modern
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemCount: items.length,
            ),
    );
  }

  // ---- Seite: Alle Reklamationen (Firmenfilter + Chips) ----
  Widget _buildAllComplaints() {
    final t = context.t;
    final email2Co = _emailToCompany;
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
        final co = (email2Co[em] ?? '').toLowerCase();
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
                  // jetzt scrollbar
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (_, i) {
                    final c = list[i];
                    return _ComplaintTile(
                      data: c,
                      isClosed: _isClosed(c),
                      // in "Alle" keine Auto-Buttons, außer offen & ohne Entscheidung
                      onDecision: (c['decision'] ?? '') == '' && !_isClosed(c)
                          ? _decideComplaint
                          : null,
                      useColoredButtons: true,
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
              // jetzt scrollbar
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
                      if (comp.isNotEmpty) return comp;      // Firma zuerst
                      if (nm.isNotEmpty)   return nm;        // dann Name
                      return em;                              // sonst E-Mail
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

  // ---- Seite: Account – zwei getrennte Einträge (Navigation bleibt wie gehabt) ----
  Widget _buildAccountCard() {
    final t = context.t;
    final labelProfile   = t.profile_edit ?? 'Profil bearbeiten';
    final labelPassword  = t.password_change ?? 'Passwort ändern';

    Future<void> _openProfile() async {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RepProfilePage(api: widget.api)),
      );
      if (!mounted) return;
      await _loadAll();
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            leading: const Icon(Icons.person_outline),
            title: Text(t.profilePW),
          ),
          const Divider(height: 1),
          // Profil bearbeiten – zeigt Profilbereich in RepProfilePage
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined),
            title: Text(labelProfile),
            subtitle: Text(t.profilePW),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openProfile,
          ),
          const Divider(height: 1),
          // Passwort ändern – führt ebenfalls zu RepProfilePage (Funktionen unverändert)
          ListTile(
            leading: const Icon(Icons.lock_reset_outlined),
            title: Text(labelPassword),
            subtitle: Text(t.password_change_hint ?? 'Passwort sicher aktualisieren'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openProfile,
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
        // etwas kompakter für Mobile
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

/// Schöne Menü-Kachel (Admin-Look) mit Farb-Icon, Verlauf und Badge
class _MenuCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final int? count;           // null => kein Badge
  final VoidCallback onTap;

  const _MenuCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.count,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg1 = color.withOpacity(0.08);
    final bg2 = cs.surface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [bg1, bg2],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon + Badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 28),
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
            const SizedBox(width: 14),
            // Titel + Untertitel
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
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
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 22),
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
  final bool useColoredButtons; // neu: modern

  const _ComplaintTile({
    required this.data,
    required this.isClosed,
    this.onDecision,
    this.useColoredButtons = false,
    super.key,
  });

  @override
  State<_ComplaintTile> createState() => _ComplaintTileState();
}

class _ComplaintTileState extends State<_ComplaintTile> with SingleTickerProviderStateMixin {
  bool _hoverAccept = false;
  bool _hoverReject = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    final ticket   = (widget.data['ticket'] ?? '').toString();
    final status   = (widget.data['status'] ?? '').toString();
    final decision = (widget.data['decision'] ?? '').toString();
    final created  = (widget.data['createdAt'] ?? widget.data['created'] ?? '').toString();
    final customer = (widget.data['customerEmail'] ?? widget.data['email'] ?? '').toString();
    final article  = (widget.data['payload']?['article'] ?? '').toString();
    final segment  = (widget.data['payload']?['segment'] ?? '').toString();

    Widget _modernButton({
      required bool positive,
      required VoidCallback onTap,
      required bool hover,
      required ValueChanged<bool> setHover,
      required String label,
      required IconData icon,
    }) {
      final baseColor = positive ? Colors.green : Colors.red;
      return MouseRegion(
        onEnter: (_) => setHover(true),
        onExit: (_) => setHover(false),
        child: AnimatedScale(
          scale: hover ? 1.03 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: ElevatedButton.icon(
            onPressed: onTap,
            icon: Icon(icon),
            label: Text(label),
            style: ButtonStyle(
              elevation: MaterialStateProperty.resolveWith<double>(
                (states) => states.contains(MaterialState.pressed) ? 1 : 4,
              ),
              shadowColor: MaterialStateProperty.all(baseColor.withOpacity(.35)),
              backgroundColor: MaterialStateProperty.resolveWith<Color>(
                (states) => states.contains(MaterialState.pressed)
                    ? baseColor.withOpacity(.85)
                    : baseColor,
              ),
              foregroundColor: MaterialStateProperty.all(Colors.white),
              shape: MaterialStateProperty.all(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              padding: MaterialStateProperty.all(const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
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
            _modernButton(
              positive: true,
              onTap: () => widget.onDecision!(ticket, true),
              hover: _hoverAccept,
              setHover: (v) => setState(() => _hoverAccept = v),
              label: t.decision_accepted,
              icon: Icons.check_rounded,
            ),
            _modernButton(
              positive: false,
              onTap: () => widget.onDecision!(ticket, false),
              hover: _hoverReject,
              setHover: (v) => setState(() => _hoverReject = v),
              label: t.decision_rejected,
              icon: Icons.close_rounded,
            ),
          ],
        );
      }
      // Fallback (Icons)
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
                // Kopfzeile: Ticket + Status/Decision Chips
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
                // Infos als Wrap -> mobilfreundlich
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (customer.isNotEmpty) _InfoCapsule('${t.customer_label}: $customer'),
                    if (article.isNotEmpty)  _InfoCapsule('${t.articleNo}: $article'),
                    if (segment.isNotEmpty)  _InfoCapsule('${t.segment}: $segment'),
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

// ---------- kleine UI-Helfer für die mobilfreundliche Liste ----------

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