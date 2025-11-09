// lib/pages/admin_page.dart
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../widgets/legal_footer.dart';

// ===================================================================
// Admin Page – mit Kachel-Menü (wie Kunden-Dashboard)
// ===================================================================
class AdminPage extends StatefulWidget {
  final ApiClient api;
  const AdminPage({super.key, required this.api});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

enum _AdminView { menu, pending, users, open, reps }

class _AdminPageState extends State<AdminPage> {
  late final AdminApi _api;

  // Ladeflags / Fehler
  bool _loadPending = false;
  bool _loadUsers = false;
  bool _loadOpen = false;
  bool _loadReps = false;
  String? _fatalErr;
  String? _err;
  String _userFilterQuery = '';
  String? _userFilterRepId;
  String _userFilterCompany = 'Alle Firmen';
  String _userFilterCountry = 'Alle Länder';


  // Vertreter-Form (persistente Felder)
  final _repFirstCtrl = TextEditingController();
  final _repLastCtrl  = TextEditingController();
  final _repMailCtrl  = TextEditingController();
  String _repRegion   = kRepRegions.first;
  bool _repBusy       = false;

  // Daten
  List<PendingUser> _pending = [];
  List<ActiveUser> _users = [];
  List<AdminComplaint> _openComplaints = [];
  List<Rep> _reps = [];

  // Email -> detaillierte Reklamationen (für Users/Pending)
  final Map<String, _ComplaintsResult> _complaints = {};

  // Firmenfilter (Offene Reklamationen)
  String _filterCompany = 'Alle Firmen';

  // Ansicht (Menü / Bereich)
  _AdminView _view = _AdminView.menu;

  @override
  void initState() {
    super.initState();
    _api = AdminApi();

    // Secret zuerst aus der API (wenn über Admin-Button gekommen),
    // sonst aus LocalStorage (dfs_admin).
    String secret = widget.api.adminSecret ?? '';
    if (secret.isEmpty) {
      secret = html.window.localStorage['dfs_admin'] ?? '';
    }
    _api.setSecret(secret);

    if (secret.isEmpty) {
      _fatalErr =
          'Kein Admin-Secret gefunden. Bitte den Adminbereich über den Start-Button öffnen '
          'oder im Browser-Storage dfs_admin setzen.';
      return;
    }

    _refreshAll();
    _refreshOpen();
    _refreshReps();
  }

  bool _customerHasRep(String email) {
    final e = email.trim().toLowerCase();
    for (final r in _reps) {
      for (final c in r.customers) {
        if (c.trim().toLowerCase() == e) return true;
      }
    }
    return false;
  }

  // Hilfsfunktionen ---------------------------------------------------
  String? _companyByEmail(String email) {
    final e = email.trim().toLowerCase();
    final u = _users.firstWhere(
      (x) => x.email.trim().toLowerCase() == e,
      orElse: () => ActiveUser.empty(),
    );
    if (u.email.isNotEmpty) return u.company.trim().isEmpty ? null : u.company.trim();

    final p = _pending.firstWhere(
      (x) => x.email.trim().toLowerCase() == e,
      orElse: () => PendingUser.empty(),
    );
    return p.company.trim().isEmpty ? null : p.company.trim();
  }

  List<ActiveUser> _filterUsers() {
    final q = _userFilterQuery.trim().toLowerCase();
    final repId = _userFilterRepId;

    // Basisliste
    Iterable<ActiveUser> list = _users;

    // Textsuche: Firma, Kontakt, E-Mail, Land
    if (q.isNotEmpty) {
      bool m(String s) => s.toLowerCase().contains(q);
      list = list.where((u) =>
        m(u.company) || m(u.contact) || m(u.email) || m(u.country));
    }

    // Vertreter-Filter
    if (repId != null) {
      if (repId.isEmpty) {
        // „Ohne Vertreter“
        final mapped = <String, String>{};
        for (final r in _reps) {
          for (final e in r.customers) {
            mapped[e.trim().toLowerCase()] = r.id;
          }
        }
        list = list.where((u) =>
          !mapped.containsKey(u.email.trim().toLowerCase()));
      } else {
        final r = _reps.firstWhere(
          (x) => x.id == repId,
          orElse: () => Rep(id: '', firstName: '', lastName: '', email: '', region: '', customers: const []),
        );
        final emails = r.customers.map((e) => e.trim().toLowerCase()).toSet();
        list = list.where((u) => emails.contains(u.email.trim().toLowerCase()));
      }
    }

    // Firmen-Filter
    final selCompany = _userFilterCompany.trim();
    if (selCompany.isNotEmpty && selCompany != 'Alle Firmen') {
      list = list.where((u) => u.company.trim() == selCompany);
    }

    // Länder-Filter
    final selCountry = _userFilterCountry.trim();
    if (selCountry.isNotEmpty && selCountry != 'Alle Länder') {
      list = list.where((u) => u.country.trim() == selCountry);
    }

    return list.toList();
  }

  String? _repNameForEmail(String email) {
    final e = email.trim().toLowerCase();
    for (final r in _reps) {
      for (final c in r.customers) {
        if (c.trim().toLowerCase() == e) {
          final dn = r.displayName.trim();
          return dn.isNotEmpty ? dn : r.email;
        }
      }
    }
    return null;
  }

  Future<void> _refreshAll() async {
    setState(() {
      _err = null;
      _loadPending = true;
      _loadUsers = true;
    });
    try {
      final pF = _api.fetchPending();
      final uF = _api.fetchUsers();
      final both = await Future.wait([pF, uF]);
      if (!mounted) return;
      setState(() {
        _pending = both[0] as List<PendingUser>;
        _users = both[1] as List<ActiveUser>;
      });
    } catch (e) {
      setState(() => _err = '$e');
    } finally {
      if (!mounted) return;
      setState(() {
        _loadPending = false;
        _loadUsers = false;
      });
    }
  }

  Future<void> _refreshOpen() async {
    setState(() {
      _err = null;
      _loadOpen = true;
    });
    try {
      final list = await _api.fetchOpenComplaints();
      if (!mounted) return;
      setState(() => _openComplaints = list);
    } catch (e) {
      setState(() => _err = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _loadOpen = false);
    }
  }

  Future<void> _refreshReps() async {
    setState(() { _err = null; _loadReps = true; });
    try {
      final list = await _api.fetchReps();
      if (!mounted) return;
      setState(() => _reps = list);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _loadReps = false);
    }
  }

  Future<void> _loadComplaintsDetailed(String email) async {
    final cur = _complaints[email];
    if (cur?.loading == true) return;
    setState(() {
      _complaints[email] = _ComplaintsResult.loading();
    });
    try {
      final list = await _api.fetchComplaintsByEmailDetailed(email);
      if (!mounted) return;
      setState(() {
        _complaints[email] = _ComplaintsResult.ok(list);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _complaints[email] = _ComplaintsResult.err('$e');
      });
    }
  }

  Future<void> _editAppMeta(BuildContext context) async {
    final api = widget.api;
    Map<String, dynamic>? meta;
    try { meta = await widget.api.getAppMeta(refresh: true); } catch (_) {}

    final vCtrl = TextEditingController(text: meta?['version']?.toString() ?? '');
    final bCtrl = TextEditingController(text: meta?['build']?.toString() ?? '');
    final nCtrl = TextEditingController(text: meta?['notes']?.toString() ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('App-Version bearbeiten'),
        content: SizedBox(
          width: 420,
         child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: vCtrl, decoration: const InputDecoration(labelText: 'Version', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: bCtrl, decoration: const InputDecoration(labelText: 'Build', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: nCtrl, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Hinweise', border: OutlineInputBorder())),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Speichern')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await widget.api.setAppMeta(
        version: vCtrl.text.trim(),
        build: bCtrl.text.trim().isEmpty ? null : bCtrl.text.trim(),
        notes: nCtrl.text.trim().isEmpty ? null : nCtrl.text.trim(),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  Future<bool?> _confirm(String title, String msg) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
  }

  // UI ----------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_fatalErr != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Adminbereich – DFS Customer Complaint'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 44),
                  const SizedBox(height: 12),
                  Text(_fatalErr!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Zurück')),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);

    // ---- Payload-Felder (nur lesend) ----
    final Map<String, dynamic>? p = (c.payload is Map) ? (c.payload as Map).cast<String, dynamic>() : null;
    final segment      = _detPickOrNull(p, ['segment','customer_segment','segment_code']);
    final productType  = _detPickOrNull(p, ['product_type','productType','type']);
    final articleNo    = _detPickOrNull(p, ['article_no','articleNumber','article','artnr']);
    final batch        = _detPickOrNull(p, ['batch_no','lot','lot_no','batch']);
    final serial       = _detPickOrNull(p, ['serial_no','serial','sn']);
    final qty          = _detPickOrNull(p, ['qty','quantity','amount','menge']);
    final reason       = _detPickOrNull(p, ['reason','failure_reason','cause']);
    final desc         = _detPickOrNull(p, ['description','comment','details','failure_desc']);
    final customerWish = _detPickOrNull(p, ['customer_wish','customerWish','wish','treatment_wish']);

    final title = switch (_view) {
      _AdminView.menu    => 'Adminbereich – DFS Customer Complaint',
      _AdminView.pending => 'Pending (Freigabe ausstehend)',
      _AdminView.users   => 'Aktive Nutzer',
      _AdminView.open    => 'Offene Reklamationen',
      _AdminView.reps    => 'Vertreterverwaltung',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: _view == _AdminView.menu
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : IconButton(
                icon: const Icon(Icons.home_outlined),
                tooltip: 'Zurück zum Admin-Menü',
                onPressed: () => setState(() => _view = _AdminView.menu),
              ),
        actions: [
          IconButton(
            tooltip: 'Alles neu laden',
            onPressed: () async {
              await _refreshAll();
              await _refreshOpen();
            },
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _buildBody(theme),
          ),
        ),
      ),
      bottomNavigationBar: LegalFooter(api: widget.api),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_err != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_err!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 8),
          Expanded(child: _view == _AdminView.menu ? _buildMenu() : _buildView()),
        ],
      );
    }
    return _view == _AdminView.menu ? _buildMenu() : _buildView();
  }

  // ------------------ Kachel-Menü (neues Design) ------------------
  Widget _buildMenu() {
    final w = MediaQuery.of(context).size.width;
    final isPhone = w < 640;
    final compact = isPhone;

    final tiles = <Widget>[
      AdminTilePro(
        label: 'Offene Reklamationen',
        subtitle: 'Bearbeiten & Entscheiden',
        icon: Icons.assignment_late_outlined,
        colorA: AdminPalette.redA,
        colorB: AdminPalette.redB,
        count: _openComplaints.length,
        compact: compact,
        onTap: () => setState(() => _view = _AdminView.open),
      ),
      AdminTilePro(
        label: 'Anträge / Pending',
        subtitle: 'Registrierungen prüfen',
        icon: Icons.verified_user_outlined,
        colorA: AdminPalette.amberA,
        colorB: AdminPalette.amberB,
        count: _pending.length,
        compact: compact,
        onTap: () => setState(() => _view = _AdminView.pending),
      ),
      AdminTilePro(
        label: 'Aktive Nutzer',
        subtitle: 'Firmen & Kontakte',
        icon: Icons.group_outlined,
        colorA: AdminPalette.tealA,
        colorB: AdminPalette.tealB,
        count: _users.length,
        compact: compact,
        onTap: () => setState(() => _view = _AdminView.users),
      ),
      AdminTilePro(
        label: 'Vertreterverwaltung',
        subtitle: 'Zuordnen & Regionen',
        icon: Icons.badge_outlined,
        colorA: AdminPalette.blueA,
        colorB: AdminPalette.blueB,
        compact: compact,
        onTap: () {
          setState(() => _view = _AdminView.reps);
          if (_reps.isEmpty) _refreshReps();
        },
      ),
      AdminTilePro(
        label: 'App-Version',
        subtitle: 'Version, Build, Hinweise',
        icon: Icons.app_settings_alt_outlined,
        colorA: AdminPalette.blueA,
        colorB: AdminPalette.blueB,
        compact: compact,
        onTap: () => _editAppMeta(context),
      ),
    ];
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: isPhone ? 220 : 260,
        mainAxisSpacing: 60,
        crossAxisSpacing: 60,
        childAspectRatio: isPhone ? 0.92 : 1.0,
      ),
      itemCount: tiles.length,
      itemBuilder: (_, i) => tiles[i],
    );
  }
  
  // ------------------ Panel-Ansichten ------------------
  Widget _buildView() {
    switch (_view) {
      case _AdminView.pending:
        return _buildPendingPanel();
      case _AdminView.users:
        return _buildUsersPanel();
      case _AdminView.open:
        return _buildOpenPanel();
      case _AdminView.menu:
        return const SizedBox.shrink();
      case _AdminView.reps:
        return _buildRepsPanel();
    }
  }

  Widget _buildPendingPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.hourglass_top),
              const SizedBox(width: 8),
              const Text('Pending (Freigabe ausstehend)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                tooltip: 'Neu laden',
                onPressed: _loadPending ? null : () async {
                  setState(() => _loadPending = true);
                  try {
                    final list = await _api.fetchPending();
                    if (!mounted) return;
                    setState(() => _pending = list);
                  } catch (e) {
                    setState(() => _err = '$e');
                  } finally {
                    if (mounted) setState(() => _loadPending = false);
                  }
                },
                icon: const Icon(Icons.refresh),
              ),
            ]),
            const SizedBox(height: 8),
            if (_loadPending) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Expanded(
              child: _pending.isEmpty
                  ? const Center(child: Text('Keine Pending-Anmeldungen.'))
                  : ListView.separated(
                      itemCount: _pending.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final p = _pending[i];
                        return _PendingTile(
                          data: p,
                          api: _api,
                          onApprove: () async {
                            try {
                              await _api.approvePending(p.email, lang: p.lang);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Freigabe ausgelöst für ${p.email}.')),
                              );
                              await _refreshAll();
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text('Fehler: $e')));
                            }
                          },
                          onReject: () async {
                            final ok = await _confirm('Anmeldung ablehnen',
                                'Soll ${p.email} wirklich abgelehnt und gelöscht werden?');
                            if (ok != true) return;
                            try {
                              await _api.deleteUser(p.email);
                              if (mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(content: Text('Eintrag gelöscht: ${p.email}')));
                                await _refreshAll();
                              }
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text('Fehler: $e')));
                            }
                          },
                          onLoadComplaints: () => _loadComplaintsDetailed(p.email),
                          complaints: _complaints[p.email],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

Widget _buildUsersPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.people),
              const SizedBox(width: 8),
              const Text(
                'Aktive Nutzer',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Neu laden',
                onPressed: _loadUsers
                    ? null
                    : () async {
                        setState(() => _loadUsers = true);
                        try {
                          final list = await _api.fetchUsers();
                          if (!mounted) return;
                          setState(() => _users = list);
                        } catch (e) {
                          setState(() => _err = '$e');
                        } finally {
                          if (mounted) setState(() => _loadUsers = false);
                        }
                      },
                icon: const Icon(Icons.refresh),
              ),
            ]),


            // >>> NEU: Filterzeile direkt unter der Überschrift <<<
            const SizedBox(height: 8),
            Row(
              children: [
                // Suche (Firma/Kontakt/E-Mail/Land)
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Suchen… (Firma, Kontakt, E-Mail, Land)',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _userFilterQuery = v),
                  ),
                ),
                const SizedBox(width: 8),
                // Firmen-Dropdown
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    value: _userFilterCompany,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Firma',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: (() {
                      final list = <String>{
                        'Alle Firmen',
                        ..._users.map((e) => e.company).where((s) => s.trim().isNotEmpty),
                      }.toList()
                        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                      return list.map((c) => DropdownMenuItem<String>(value: c, child: Text(c))).toList();
                    })(),
                    onChanged: (v) => setState(() => _userFilterCompany = v ?? 'Alle Firmen'),
                  ),
                ),
                const SizedBox(width: 8),

                // Länder-Dropdown
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String>(
                    value: _userFilterCountry,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Land',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: (() {
                      final list = <String>{
                        'Alle Länder',
                        ..._users.map((e) => e.country).where((s) => s.trim().isNotEmpty),
                      }.toList()
                        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                      return list.map((c) => DropdownMenuItem<String>(value: c, child: Text(c))).toList();
                    })(),
                    onChanged: (v) => setState(() => _userFilterCountry = v ?? 'Alle Länder'),
                  ),
                ),
                const SizedBox(width: 8),
                
                // Vertreter-Dropdown
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<String?>(
                    value: _userFilterRepId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Vertreter',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: (() {
                      final list = <String>{
                        'Alle Länder',
                        ..._users.map((e) => e.country).where((s) => s.trim().isNotEmpty),
                      }.toList()
                        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                      return list.map((c) => DropdownMenuItem<String>(value: c, child: Text(c))).toList();
                    })(),
                    onChanged: (v) => setState(() => _userFilterRepId = v),
                  ),
                ),
              ],
            ),
            // <<< Ende Filterzeile >>>

            const SizedBox(height: 8),
            if (_loadUsers) const LinearProgressIndicator(),
            const SizedBox(height: 8),

            // Gefilterte Daten verwenden
            Expanded(
              child: () {
                final data = _filterUsers();
                return data.isEmpty
                    ? const Center(child: Text('Keine aktiven Nutzer.'))
                    : ListView.separated(
                        itemCount: data.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final u = data[i];
                          final repName = _repNameForEmail(u.email);
                          return _UserTile(
                            data: u,
                            api: _api,
                            onDelete: () async {
                              final ok = await _confirm(
                                'Nutzer löschen',
                                'Soll der aktive Nutzer ${u.email} wirklich gelöscht werden?',
                              );
                              if (ok != true) return;
                              try {
                                await _api.deleteUser(u.email);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Nutzer gelöscht: ${u.email}'),
                                    ),
                                  );
                                  await _refreshAll();
                                  await _refreshOpen();
                                }
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Fehler: $e')),
                                );
                              }
                            },
                            onLoadComplaints: () =>
                                _loadComplaintsDetailed(u.email),
                            complaints: _complaints[u.email],
                            onClosedFromEditor: () {
                              _refreshOpen();
                            },
                            repName: repName,
                          );
                        },
                      );
              }(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpenPanel() {
    // Firmenliste für Filter-Dropdown (lokal)
    final List<String> companies = <String>{
      'Alle Firmen',
      ..._openComplaints.map((c) => (_companyByEmail(c.email) ?? '')).where((s) => s.trim().isNotEmpty),
      ..._users.map((e) => e.company).where((s) => s.trim().isNotEmpty),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    // ggf. gefilterte Liste bilden
    final list = (_filterCompany == 'Alle Firmen')
        ? _openComplaints
        : _openComplaints
            .where((c) => (_companyByEmail(c.email) ?? '') == _filterCompany)
            .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.receipt_long),
              const SizedBox(width: 8),
              const Text('Offene Reklamationen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              DropdownButton<String>(
                value: _filterCompany,
                onChanged: (v) => setState(() => _filterCompany = v ?? 'Alle Firmen'),
                items: companies.map((s) => DropdownMenuItem<String>(value: s, child: Text(s))).toList(),
              ),
              const SizedBox(width: 8),
              if (_loadOpen)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              IconButton(
                tooltip: 'Neu laden',
                onPressed: _loadOpen ? null : _refreshOpen,
                icon: const Icon(Icons.refresh),
              ),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Keine offenen Reklamationen.'))
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final c = list[i];
                        return _ComplaintEditor(
                          api: _api,
                          c: c,
                          companyHint: _companyByEmail(c.email),
                          hasRep: _customerHasRep(c.email), // ← NEU
                          onClosed: () {
                            setState(() {
                              _openComplaints.removeWhere((x) => x.ticket == c.ticket);
                            });
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

  Widget _buildRepsPanel() {
    // kleine Helper zum Mail-Schreiben
    void _composeMail(String to, {String? subject, String? body}) {
      if (to.trim().isEmpty) return;
      final url = 'mailto:$to'
          '?subject=${Uri.encodeComponent(subject ?? 'Anfrage / DFS-DIAMON')}'
          '&body=${Uri.encodeComponent(body ?? 'Guten Tag,\n\nich melde mich als Ihr Ansprechpartner.\n\nBeste Grüße\nDFS-DIAMON GmbH')}';
      html.window.open(url, '_self');
    }

    Future<void> _save({String? id}) async {
      if (_repBusy) return;
      setState(() => _repBusy = true);
      try {
        final rep = await _api.upsertRep(
          id: id,
          firstName: _repFirstCtrl.text.trim(),
          lastName:  _repLastCtrl.text.trim(),
          email:     _repMailCtrl.text.trim(),
          region:    _repRegion,
        );

        // Felder leeren + Liste neu laden
        _repFirstCtrl.clear();
        _repLastCtrl.clear();
        _repMailCtrl.clear();
        _repRegion = kRepRegions.first;

        await _refreshReps();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gespeichert: ${rep.displayName}')),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
        }
      } finally {
        if (mounted) setState(() => _repBusy = false);
      }
    }

    Future<void> _edit(Rep r) async {
      _repFirstCtrl.text = r.firstName;
      _repLastCtrl.text  = r.lastName;
      _repMailCtrl.text  = r.email;
      _repRegion         = r.region.isNotEmpty ? r.region : kRepRegions.first;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Vertreter bearbeiten'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: _repFirstCtrl, decoration: const InputDecoration(labelText: 'Vorname')),
                const SizedBox(height: 8),
                TextField(controller: _repLastCtrl,  decoration: const InputDecoration(labelText: 'Nachname')),
                const SizedBox(height: 8),
                TextField(controller: _repMailCtrl,  decoration: const InputDecoration(labelText: 'E-Mail')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _repRegion,
                  decoration: const InputDecoration(labelText: 'Länderbereich'),
                  items: kRepRegions.map((s) => DropdownMenuItem<String>(value: s, child: Text(s))).toList(),
                  onChanged: (v) => _repRegion = v ?? kRepRegions.first,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () async { Navigator.pop(ctx); await _save(id: r.id); },
              child: const Text('Speichern'),
            ),
          ],
        ),
      );
    }

    Future<void> _confirmDelete(Rep r) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Vertreter löschen'),
          content: Text('Soll ${r.displayName} wirklich gelöscht werden?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
          ],
        ),
      );
      if (ok == true) {
        try {
          await _api.deleteRep(r.id);
          await _refreshReps();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gelöscht: ${r.displayName}')));
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
          }
        }
      }
    }

    Future<void> _openRepCustomersDialog(Rep rep) async {
      // Globale Belegung: email -> repId
      final Map<String, String> emailAssignedToRepId = {};
      for (final r in _reps) {
        for (final e in r.customers) {
          emailAssignedToRepId[e] ??= r.id; // first wins
        }
      }

      // Menge aller bereits irgendwo zugewiesenen Kunden
      var assignedGlobal = emailAssignedToRepId.keys.toSet();

      // Aktuelle Belegung dieses Reps (veränderlich, wir aktualisieren im Dialog)
      var assignedThis = rep.customers.toSet();

      // Kandidaten = ALLE aktiven User (im Dropdown sichtbar, aber ggf. disabled)
      final allUserEmails = _users.map((u) => u.email.trim()).where((e) => e.isNotEmpty).toSet();
      final all = allUserEmails.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      // Vorauswahl = erster freier (global nicht zugewiesener)
      String? selEmail = all.firstWhere(
        (e) => !assignedGlobal.contains(e),
        orElse: () => '',
      );
      if ((selEmail ?? '').isEmpty) selEmail = null;

      bool busy = false;

      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> doAssign() async {
              if (selEmail == null || selEmail!.trim().isEmpty) return;

              // Schutz: Falls ein anderer Rep in der Zwischenzeit zugewiesen hat
              final otherRepId = emailAssignedToRepId[selEmail!];
              if (otherRepId != null && otherRepId != rep.id) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Dieser Kunde ist bereits einem anderen Vertreter zugewiesen.')),
                );
                return;
              }

              setLocal(() => busy = true);
              try {
                final customers = await _api.assignCustomerToRep(repId: rep.id, email: selEmail!.trim());

                // Parent aktualisieren
                setState(() {
                  final idx = _reps.indexWhere((x) => x.id == rep.id);
                  if (idx >= 0) {
                    _reps[idx] = Rep(
                      id: _reps[idx].id,
                      firstName: _reps[idx].firstName,
                      lastName: _reps[idx].lastName,
                      email: _reps[idx].email,
                      region: _reps[idx].region,
                      customers: customers,
                    );
                  }
                });

                // Zur Sicherheit die gesamte Repliste neu laden (Race-Conditions vermeiden)
                await _refreshReps();

                // Globale Maps/Mengen nachladen
                emailAssignedToRepId
                  ..clear()
                  ..addEntries(_reps.expand((r) => r.customers.map((e) => MapEntry(e, r.id))));
                assignedGlobal = emailAssignedToRepId.keys.toSet();

                // Lokale Sets aktualisieren
                assignedThis = customers.toSet();

                // Neue Vorauswahl: nächster freier Kunde
                selEmail = all.firstWhere(
                  (e) => !assignedGlobal.contains(e),
                  orElse: () => '',
                );
                if ((selEmail ?? '').isEmpty) selEmail = null;

                setLocal(() => busy = false);
              } catch (e) {
                setLocal(() => busy = false);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
                }
              }
            }

            Future<void> doUnassign(String email) async {
              setLocal(() => busy = true);
              try {
                final customers = await _api.unassignCustomerFromRep(repId: rep.id, email: email);

                // Parent aktualisieren
                setState(() {
                  final idx = _reps.indexWhere((x) => x.id == rep.id);
                  if (idx >= 0) {
                    _reps[idx] = Rep(
                      id: _reps[idx].id,
                      firstName: _reps[idx].firstName,
                      lastName: _reps[idx].lastName,
                      email: _reps[idx].email,
                      region: _reps[idx].region,
                      customers: customers,
                    );
                  }
                });

                // Globale Reps neu ziehen
                await _refreshReps();

                // Globale Maps/Mengen nachladen
                emailAssignedToRepId
                  ..clear()
                  ..addEntries(_reps.expand((r) => r.customers.map((e) => MapEntry(e, r.id))));
                assignedGlobal = emailAssignedToRepId.keys.toSet();

                // Lokale Sets aktualisieren
                assignedThis = customers.toSet();

                // Vorauswahl korrigieren (falls aktuell verbotener Wert selektiert war)
                if (selEmail != null && assignedGlobal.contains(selEmail)) {
                  selEmail = all.firstWhere(
                    (e) => !assignedGlobal.contains(e),
                    orElse: () => '',
                  );
                  if ((selEmail ?? '').isEmpty) selEmail = null;
                }

                setLocal(() => busy = false);
              } catch (e) {
                setLocal(() => busy = false);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
                }
              }
            }

            return AlertDialog(
              title: Text('Kunden für ${rep.displayName}'),
              content: SizedBox(
                width: 620,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Bestehende Kundenliste
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Zugewiesene Kunden (${rep.customers.length}) – jeder Kunde kann nur genau einem Vertreter zugeordnet sein.',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 280),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: (rep.customers.isEmpty)
                        ? const Center(child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('Keine Kunden zugewiesen.'),
                          ))
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: rep.customers.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final email = rep.customers[i];
                              final company = _companyByEmail(email) ?? '';
                              return ListTile(
                                leading: const Icon(Icons.person_outline),
                                title: Text(company.isNotEmpty ? company : email),
                                subtitle: company.isNotEmpty ? Text(email) : null,
                                trailing: IconButton(
                                  tooltip: 'Zuweisung entfernen',
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: busy ? null : () async => await doUnassign(email),
                                ),
                              );
                            },
                          ),
                    ),
                    const SizedBox(height: 16),

                    // Neuer Kunde zuweisen
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Kunden zuweisen', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selEmail,
                            decoration: const InputDecoration(
                              labelText: 'Kunde (E-Mail)',
                              border: OutlineInputBorder(),
                            ),
                            items: all.map((e) {
                              final isAssignedSomewhere = assignedGlobal.contains(e);
                              final label = _companyByEmail(e) ?? e;
                              // Optional: zeigen, wo belegt (nur für Klarheit im UI)
                              final assignedHint = (isAssignedSomewhere && emailAssignedToRepId[e] != rep.id)
                                  ? ' (bereits zugewiesen)'
                                  : '';

                              return DropdownMenuItem<String>(
                                value: e,
                                enabled: !isAssignedSomewhere, // global belegt => disabled
                                child: Text(
                                  '$label$assignedHint',
                                  style: isAssignedSomewhere
                                      ? TextStyle(color: Theme.of(context).disabledColor)
                                      : null,
                                ),
                              );
                            }).toList(),
                            onChanged: busy
                                ? null
                                : (v) {
                                    if (v == null) return;
                                    // Safety: global gesperrt bleibt gesperrt
                                    if (assignedGlobal.contains(v)) return;
                                    setLocal(() => selEmail = v);
                                  },
                          )
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: busy || selEmail == null ? null : doAssign,
                          icon: const Icon(Icons.add),
                          label: const Text('Zuweisen'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                if (busy) const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen')),
              ],
            );
          },
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kopfzeile
            Row(children: [
              const Icon(Icons.badge_outlined),
              const SizedBox(width: 8),
              const Text('Vertreterverwaltung', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (_loadReps)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              IconButton(
                tooltip: 'Neu laden',
                onPressed: _loadReps ? null : _refreshReps,
                icon: const Icon(Icons.refresh),
              ),
            ]),
            const SizedBox(height: 12),

            // Anlegen-Form
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Neuen Vertreter anlegen', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 240,
                        child: TextField(controller: _repFirstCtrl, decoration: const InputDecoration(labelText: 'Vorname')),
                      ),
                      SizedBox(
                        width: 260,
                        child: TextField(controller: _repLastCtrl, decoration: const InputDecoration(labelText: 'Nachname')),
                      ),
                      SizedBox(
                        width: 300,
                        child: TextField(controller: _repMailCtrl, decoration: const InputDecoration(labelText: 'E-Mail')),
                      ),
                      SizedBox(
                        width: 300,
                        child: DropdownButtonFormField<String>(
                          value: _repRegion,
                          decoration: const InputDecoration(labelText: 'Länderbereich'),
                          items: kRepRegions.map((s) => DropdownMenuItem<String>(value: s, child: Text(s))).toList(),
                          onChanged: (v) => setState(() => _repRegion = v ?? kRepRegions.first),
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.save_outlined),
                          onPressed: _repBusy ? null : () => _save(),
                          label: const Text('Anlegen'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Liste der Vertreter
            Expanded(
              child: _reps.isEmpty
                  ? const Center(child: Text('Keine Vertreter angelegt.'))
                  : ListView.separated(
                      itemCount: _reps.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final r = _reps[i];
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                          title: Text(r.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${r.email} • ${r.region} • Kunden: ${r.customers.length}'),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              IconButton(
                                tooltip: 'E-Mail schreiben',
                                icon: const Icon(Icons.mail_outline),
                                onPressed: () => _composeMail(
                                  r.email,
                                  subject: 'DFS-DIAMON – Anfrage / ${r.displayName}',
                                  body: 'Guten Tag ${r.displayName},\n\n— Nachricht —\n\nBeste Grüße\nDFS-DIAMON GmbH',
                                ),
                              ),
                              IconButton(
                                tooltip: 'Bearbeiten',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _edit(r),
                              ),
                              IconButton(
                                tooltip: 'Löschen',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _confirmDelete(r),
                              ),
                              IconButton(
                                tooltip: 'Kunden zuweisen/anzeigen',
                                icon: const Icon(Icons.group_add_outlined),
                                onPressed: () => _openRepCustomersDialog(r),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===================================================================
// Kleine Hilfswidgets
// ===================================================================
class _Field extends StatelessWidget {
  final String label;
  final String value;
  const _Field({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('$label:', style: muted),
          Text(value.isEmpty ? '—' : value),
        ],
      ),
    );
  }
}

// ===================================================================
// Admin-Menü-Kachel + Busy-Dot (Top-Level Widgets, nicht verschachteln)
// ===================================================================
class _AdminTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final Widget? badge;

  const _AdminTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      elevation: 1.5,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 44, color: color),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (badge == null) return card;

    return Stack(
      children: [
        card,
        Positioned(right: 10, top: 10, child: badge!),
      ],
    );
  }
}

class _BusyDot extends StatelessWidget {
  const _BusyDot({super.key});
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

class _RepTrafficLight extends StatelessWidget {
  /// 'accepted' | 'rejected' | 'pending' | andere/leer -> keine Anzeige
  final String? opinion;
  final bool compact; // für enge Layouts
  const _RepTrafficLight({required this.opinion, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final v = (opinion ?? '').trim().toLowerCase();
    if (v.isEmpty) return const SizedBox.shrink(); // keine Ampel ohne Meinung

    // Farben
    const colRed    = Colors.red;
    const colAmber  = Colors.amber;
    const colGreen  = Colors.green;

    // aktives Licht bestimmen
    bool onRed   = v == 'rejected';
    bool onAmber = v == 'pending' || v == 'open' || v == 'yellow' || v == 'gelb';
    bool onGreen = v == 'accepted' || v == 'accept' || v == 'green' || v == 'gruen' || v == 'grün';

    // Falls unbekannter Wert -> neutrale Anzeige vermeiden (Ampel ganz weglassen)
    if (!(onRed || onAmber || onGreen)) {
      return const SizedBox.shrink();
    }

    // Maße
    final size    = compact ? 10.0 : 12.0;     // Kreis-Durchmesser
    final gap     = compact ? 4.0  : 6.0;      // Abstand zwischen Kreisen
    final radius  = size / 2;

    Widget dot(Color c, bool on) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: on ? c : c.withOpacity(0.18),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: on ? c : c.withOpacity(0.6), width: 1),
        boxShadow: on
            ? [BoxShadow(color: c.withOpacity(0.45), blurRadius: 6, spreadRadius: 0)]
            : const [],
      ),
    );

    // Beschriftung rechts daneben (kompakt gehalten)
    String label;
    if (onGreen)      label = 'Vertreter: akzeptiert';
    else if (onRed)   label = 'Vertreter: abgelehnt';
    else              label = 'Vertreter: offen';

    final textStyle = TextStyle(
      fontWeight: FontWeight.w700,
      color: onGreen ? colGreen : (onRed ? colRed : colAmber),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Ampel (vertikal)
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
        Text(label, style: textStyle),
      ],
    );
  }
}

class _RepOpinionBadge extends StatelessWidget {
  final String? opinion; // 'accepted' | 'rejected' | 'pending' | null
  const _RepOpinionBadge({required this.opinion});

  @override
  Widget build(BuildContext context) {
    final v = (opinion ?? '').trim().toLowerCase();
    Color bg;
    Color fg;
    String label;

    switch (v) {
      case 'accepted':
        bg = Colors.green;
        label = 'Vertreter: akzeptiert';
        break;
      case 'rejected':
        bg = Colors.red;
        label = 'Vertreter: abgelehnt';
        break;
      case 'pending':
      case '':
        bg = Colors.amber;
        label = 'Vertreter: offen';
        break;
      default:
        // unbekannt → neutral
        bg = Theme.of(context).colorScheme.outline;
        label = 'Vertreter: ${v}';
        break;
    }
    fg = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark ? Colors.white : Colors.black;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.12),
        border: Border.all(color: bg, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(color: bg, fontWeight: FontWeight.w700)),
    );
  }
}

class _PendingTile extends StatefulWidget {
  final PendingUser data;
  final AdminApi api;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final Future<void> Function() onLoadComplaints;
  final _ComplaintsResult? complaints;
  const _PendingTile({
    required this.data,
    required this.api,
    required this.onApprove,
    required this.onReject,
    required this.onLoadComplaints,
    required this.complaints,
  });

  @override
  State<_PendingTile> createState() => _PendingTileState();
}

class _PendingTileState extends State<_PendingTile> {
  bool _expanded = false;

  void _showAddress() {
    final d = widget.data;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adressdaten (Pending)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Field(label: 'Firma', value: d.company),
            _Field(label: 'Kontakt', value: d.contact),
            const SizedBox(height: 6),
            _Field(label: 'Straße', value: d.street),
            _Field(label: 'PLZ/Ort', value: '${d.zip} ${d.city}'.trim()),
            _Field(label: 'Land', value: d.country),
            const SizedBox(height: 6),
            _Field(label: 'Telefon', value: d.phone),
            _Field(label: 'E-Mail', value: d.email),
            _Field(label: 'Sprache', value: d.lang.toUpperCase()),
            _Field(label: 'Erstellt', value: d.createdAt ?? '—'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final title = d.company.isNotEmpty ? d.company : d.email;
    final subtitle = (d.country.isNotEmpty) ? d.country : '${d.zip} ${d.city}'.trim();

    return Column(
      children: [
        ListTile(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle.isEmpty ? '—' : subtitle),
          trailing: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(tooltip: 'Adressdaten', onPressed: _showAddress, icon: const Icon(Icons.info_outline)),
              IconButton(
                tooltip: 'Reklamationen anzeigen',
                onPressed: () {
                  setState(() => _expanded = !_expanded);
                  if (_expanded) widget.onLoadComplaints();
                },
                icon: Icon(_expanded ? Icons.expand_less : Icons.receipt_long),
              ),
              FilledButton(onPressed: widget.onApprove, child: const Text('Freigeben')),
              OutlinedButton(onPressed: widget.onReject, child: const Text('Ablehnen')),
            ],
          ),
        ),
        if (_expanded)
          _ComplaintsDetailList(
            result: widget.complaints,
            api: widget.api,
            onClosed: () {},
            companyHint: d.company,
          ),
        const Divider(height: 1),
      ],
    );
  }
}

class _UserTile extends StatefulWidget {
  final ActiveUser data;
  final AdminApi api;
  final Future<void> Function() onDelete;
  final Future<void> Function() onLoadComplaints;
  final _ComplaintsResult? complaints;
  final VoidCallback onClosedFromEditor;
  final String? repName;
  
  const _UserTile({
    required this.data,
    required this.api,
    required this.onDelete,
    required this.onLoadComplaints,
    required this.complaints,
    required this.onClosedFromEditor,
    this.repName,
  });

  @override
  State<_UserTile> createState() => _UserTileState();
}

class _UserTileState extends State<_UserTile> {
  bool _expanded = false;

  void _showAddress() {
    final d = widget.data;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adressdaten'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Field(label: 'Firma', value: d.company),
            _Field(label: 'Kontakt', value: d.contact),
            const SizedBox(height: 6),
            _Field(label: 'Straße', value: d.street),
            _Field(label: 'PLZ/Ort', value: '${d.zip} ${d.city}'.trim()),
            _Field(label: 'Land', value: d.country),
            const SizedBox(height: 6),
            _Field(label: 'Telefon', value: d.phone),
            _Field(label: 'E-Mail', value: d.email),
            _Field(label: 'Sprache', value: d.lang.toUpperCase()),
            _Field(label: 'Aktiv seit', value: d.createdAt ?? '—'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final title = d.company.isNotEmpty ? d.company : d.email;
    final subtitle = d.country.isNotEmpty ? d.country : d.email;

    return Column(
      children: [
        ListTile(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle),
              if (widget.repName != null && widget.repName!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.badge_outlined, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Vertreter: ${widget.repName}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
              if (d.selfDeleted) const SizedBox(height: 4),
              if (d.selfDeleted)
                const Text(
                  'Account durch User gelöscht!',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                ),
            ],
          ),
          trailing: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(tooltip: 'Adressdaten', onPressed: _showAddress, icon: const Icon(Icons.info_outline)),
              IconButton(
                tooltip: 'Reklamationen anzeigen',
                onPressed: () {
                  setState(() => _expanded = !_expanded);
                  if (_expanded) widget.onLoadComplaints();
                },
                icon: Icon(_expanded ? Icons.expand_less : Icons.receipt_long),
              ),
              OutlinedButton(onPressed: () async => widget.onDelete(), child: const Text('Löschen')),
            ],
          ),
        ),
        if (_expanded)
          _ComplaintsDetailList(
            result: widget.complaints,
            api: widget.api,
            onClosed: widget.onClosedFromEditor,
            companyHint: d.company,
          ),
        const Divider(height: 1),
      ],
    );
  }
}

class _ComplaintsDetailList extends StatelessWidget {
  final _ComplaintsResult? result;
  final AdminApi api;
  final VoidCallback onClosed;
  final String? companyHint;

  const _ComplaintsDetailList({
    required this.result,
    required this.api,
    required this.onClosed,
    this.companyHint,
  });

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('Noch nicht geladen.'),
      );
    }
    if (r.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: LinearProgressIndicator(),
      );
    }
    if (r.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('Fehler beim Laden: ${r.error}', style: TextStyle(color: Colors.red)),
      );
    }
    if (r.items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('Keine Reklamationen gefunden.'),
      );
    }

    // Einmalig den Parent-State holen (performanter als pro Item)
    final parent = context.findAncestorStateOfType<_AdminPageState>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const Text('Reklamationen (Details):', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ...r.items
              .map((c) => _ComplaintEditor(
                    api: api,
                    c: c,
                    onClosed: onClosed,
                    companyHint: companyHint,
                    hasRep: (c.email.isNotEmpty)
                        ? (parent?._customerHasRep(c.email) ?? false)
                        : false,
                  ))
              .toList(),
        ],
      ),
    );
  }
}

// ===================================================================
// Modelle
// ===================================================================
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
        email: j['email'] ?? '',
        company: j['company'] ?? '',
        contact: j['contact'] ?? '',
        street: j['street'] ?? '',
        zip: j['zip'] ?? '',
        city: j['city'] ?? '',
        country: j['country'] ?? '',
        phone: j['phone'] ?? '',
        lang: (j['lang'] ?? 'de').toString(),
        createdAt: j['createdAt']?.toString(),
      );

  factory PendingUser.empty() => PendingUser(
        email: '',
        company: '',
        contact: '',
        street: '',
        zip: '',
        city: '',
        country: '',
        phone: '',
        lang: 'de',
        createdAt: '',
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
        email: j['email'] ?? '',
        company: j['company'] ?? '',
        contact: j['contact'] ?? '',
        street: j['street'] ?? '',
        zip: j['zip'] ?? '',
        city: j['city'] ?? '',
        country: j['country'] ?? '',
        phone: j['phone'] ?? '',
        lang: (j['lang'] ?? 'de').toString(),
        createdAt: j['createdAt']?.toString(),
        selfDeleted: (j['selfDeleted'] ?? false) == true,
      );

  factory ActiveUser.empty() => ActiveUser(
        email: '',
        company: '',
        contact: '',
        street: '',
        zip: '',
        city: '',
        country: '',
        phone: '',
        lang: 'de',
        createdAt: '',
        selfDeleted: false,
      );
}

class AdminComplaint {
  final String ticket;
  final String email;
  final DateTime createdAt;
  final DateTime updatedAt;
  int status;
  String? decision;
  String? reportLink;
  String? internalNo;
  final Map<String, dynamic>? payload;

  // Vertreter-Daten
  String? repOpinion; // 'accepted' | 'rejected' | 'pending'
  final String? repId; // z. B. Rep-UID oder E-Mail

  bool get hasRep => (repId ?? '').trim().isNotEmpty;

  // Wunsch/Handling lesbar (für UI/E-Mail)
  String get handlingLabel {
    final p = payload;
    if (p == null) return '—';
    final v = p['handling'] ?? p['Wunsch'] ?? '';
    final s = v.toString().trim();
    return s.isEmpty ? '—' : s;
  }

  AdminComplaint({
    required this.ticket,
    required this.email,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    this.decision,
    this.reportLink,
    this.internalNo,
    this.payload,
    this.repOpinion,
    this.repId,
  });

  factory AdminComplaint.fromJson(Map<String, dynamic> j) {
    DateTime _dt(v) {
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v is String && v.trim().isNotEmpty) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    int _i(v) => (v is num) ? v.toInt() : int.tryParse('${v ?? ''}') ?? 1;

    String? _norm(String? v) {
      final s = (v ?? '').trim().toLowerCase();
      if (s.isEmpty) return null;
      if (s == 'accepted' || s == 'accept' || s == 'green' || s == 'gruen' || s == 'grün') return 'accepted';
      if (s == 'rejected' || s == 'reject' || s == 'red' || s == 'rot') return 'rejected';
      if (s == 'pending' || s == 'wait' || s == 'gelb' || s == 'yellow' || s == 'open') return 'pending';
      return s;
    }

    final payload =
        (j['payload'] is Map) ? (j['payload'] as Map).cast<String, dynamic>() : null;

    String? repRaw = (j['repOpinion']
          ?? j['rep_opinion']
          ?? j['repDecision']
          ?? j['rep_decision']
          ?? j['repStatus']
          ?? j['rep_status'])
        ?.toString();

    if ((repRaw == null || repRaw.trim().isEmpty) && payload != null) {
      repRaw = (payload['repOpinion']
            ?? payload['rep_opinion']
            ?? payload['repDecision']
            ?? payload['rep_decision']
            ?? payload['repStatus']
            ?? payload['rep_status'])
          ?.toString();
    }

    String? _pickRepId(Map<String, dynamic> j, Map<String, dynamic>? p) {
      String pick(Object? v) => (v ?? '').toString().trim();
      final direct = pick(j['repId'] ?? j['rep_id'] ?? j['rep'] ?? j['representative']);
      if (direct.isNotEmpty) return direct;
      if (p != null) {
        final inPayload = pick(p['repId'] ?? p['rep_id'] ?? p['rep'] ?? p['representative']);
        if (inPayload.isNotEmpty) return inPayload;
      }
      return null;
    }

    final repIdLocal = _pickRepId(j, payload);

    return AdminComplaint(
      ticket: (j['ticket'] ?? '').toString(),
      email: (j['email'] ?? '').toString(),
      createdAt: _dt(j['createdAt']),
      updatedAt: _dt(j['updatedAt']),
      status: _i(j['status']),
      decision: (j['decision'] == null || (j['decision'] as String?)?.isEmpty == true)
          ? null
          : j['decision']?.toString(),
      reportLink: j['reportLink']?.toString(),
      internalNo: (j['internalNo']?.toString().trim().isEmpty ?? true)
          ? null
          : j['internalNo']!.toString().trim(),
      payload: payload,
      repOpinion: _norm(repRaw),
      repId: repIdLocal,
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
        'internalNo': internalNo,
        'payload': payload,
        if (repOpinion != null) 'repOpinion': repOpinion,
        if (repId != null) 'repId': repId,
      };
}

class Rep {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String region;
  final List<String> customers;

  Rep({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.region,
    required this.customers,
  });

  factory Rep.fromJson(Map<String, dynamic> j) => Rep(
    id: (j['id'] ?? j['email'] ?? '').toString(),
    firstName: (j['firstName'] ?? '').toString(),
    lastName: (j['lastName'] ?? '').toString(),
    email: (j['email'] ?? '').toString(),
    region: (j['region'] ?? '').toString(),
    customers: (j['customers'] is List)
        ? List<String>.from((j['customers'] as List).map((e) => e.toString()))
        : const <String>[],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'region': region,
    'customers': customers,
  };

  String get displayName {
    final fn = firstName.trim();
    final ln = lastName.trim();
    if (fn.isEmpty && ln.isEmpty) return email;
    return [fn, ln].where((s) => s.isNotEmpty).join(' ');
  }
}

// ===================================================================
// Status-/Decision-Listen + Details-Dialog + Editor
// ===================================================================
const kStatusItems = <Map<String, dynamic>>[
  {'label': 'Eingegegangen', 'value': 1},
  {'label': 'In Bearbeitung', 'value': 2},
  {'label': 'Rückfrage erforderlich', 'value': 3},
  {'label': 'In Nacharbeit', 'value': 5},
  {'label': 'Abgeschlossen', 'value': 6},
];

const kDecisionItems = <Map<String, String>>[
  {'label': '—', 'value': ''}, // keine Entscheidung
  {'label': 'Angenommen', 'value': 'accepted'},
  {'label': 'Abgelehnt', 'value': 'rejected'},
];

// Vertreter – Regionen (fixe Auswahl)
const kRepRegions = <String>[
  'Lateinamerika',
  'Osteuropa',
  'Italien',
  'China & Mongolei & Philippinen',
  'Mittlerer Osten & Afrika',
];

class _ComplaintDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> data; // vollständiges Complaint-Objekt
  const _ComplaintDetailsDialog({required this.data});

  @override
  Widget build(BuildContext context) {
    final payload = (data['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    final files = (data['files'] as List?)?.cast<Map>() ?? const [];
    final ticket = (data['ticket'] ?? '').toString();

    Widget row(String l, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 160, child: Text(l, style: const TextStyle(fontWeight: FontWeight.w600))),
              Expanded(child: Text(v.isEmpty ? '—' : v)),
            ],
          ),
        );

    return AlertDialog(
      title: Text('Details – $ticket'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (payload.isEmpty)
                const Text('Keine Payload übermittelt.')
              else ...[
                row('Segment', (payload['segment'] ?? '').toString()),
                row('Artikel', (payload['article'] ?? '').toString()),
                row('Charge', (payload['batch'] ?? '').toString()),
                row('Menge', (payload['qty'] ?? '').toString()),
                row('Ablauf', (payload['expiry'] ?? '').toString()),
                row('Beschreibung', (payload['desc'] ?? '').toString()),
                row('Produkte zurückgeschickt?', (payload['returned'] ?? '').toString()),
                row('Gewünschte Behandlung', (payload['handling'] ?? '').toString()),
                if ((payload['applied'] ?? '') != '')
                  row('Am Patienten angewendet?', (payload['applied'] ?? '').toString()),
                if ((payload['injury'] ?? '') != '')
                  row('Verletzung?', (payload['injury'] ?? '').toString()),
                if ((payload['injuryDesc'] ?? '').toString().trim().isNotEmpty)
                  row('Verletzungsbeschreibung', (payload['injuryDesc'] ?? '').toString()),
              ],
              const SizedBox(height: 10),
              if (files.isNotEmpty) const Text('Dateien:', style: TextStyle(fontWeight: FontWeight.w600)),
              if (files.isNotEmpty)
                ...files.map((f) => Text('- ${f['name'] ?? 'Datei'} (${f['mime'] ?? 'mime'})')).toList(),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen'))],
    );
  }
}

class _ComplaintEditor extends StatefulWidget {
  final AdminApi api;
  final AdminComplaint c;
  final VoidCallback onClosed;
  final String? companyHint;
  final bool hasRep;
  
  const _ComplaintEditor({
    super.key,
    required this.api,
    required this.c,
    required this.onClosed,
    this.companyHint,
    this.hasRep = false,
  });

  @override
  State<_ComplaintEditor> createState() => _ComplaintEditorState();
}

class _ComplaintEditorState extends State<_ComplaintEditor> {
  final _reportCtrl = TextEditingController();
  final _internalCtrl = TextEditingController();
  bool _busy = false;
  bool _expanded = false;

  int? _status; // 1..6
  String? _decision;
  
  // ---- Details-Helper (nur lesend, keine Kollisionen dank Präfix) ----
  String _detPick(Map<String, dynamic>? p, List<String> keys) {
    if (p == null) return '';
    for (final k in keys) {
      final v = p[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  String? _detPickOrNull(Map<String, dynamic>? p, List<String> keys) {
    final s = _detPick(p, keys);
    return s.isEmpty ? null : s;
  }

  Widget _detKv(String label, String? value, {int maxLines = 2}) {
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

  @override
  void initState() {
    super.initState();
    _reportCtrl.text = widget.c.reportLink ?? '';
    _internalCtrl.text = widget.c.internalNo ?? '';
    _status = widget.c.status;
    _decision = widget.c.decision;
  }

  @override
  void dispose() {
    _reportCtrl.dispose();
    _internalCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveReportLink() async {
    setState(() => _busy = true);
    try {
      final link = _reportCtrl.text.trim();
      final updated = await widget.api.adminComplaintUpdate(
        ticket: widget.c.ticket,
        reportLink: link.isEmpty ? '' : link,
      );
      widget.c.reportLink = updated.reportLink;
      widget.c.status = updated.status;
      widget.c.decision = updated.decision;

      if (updated.status == 6 || updated.decision == 'rejected') {
        widget.onClosed();
      }

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

  Future<void> _saveInternalNo() async {
    if (_busy) return;
    setState(() => _busy = true);

    final newVal = _internalCtrl.text.trim();

    // UI sofort updaten, damit es direkt neben der Ticketnummer erscheint
    setState(() {
      widget.c.internalNo = newVal;
    });

    try {
      final updated = await widget.api.adminComplaintUpdate(
        ticket: widget.c.ticket,
        internalNo: newVal,
      );
      // Fallback, falls dein Backend etwas „bereinigt“ zurückgibt
      setState(() {
       widget.c.internalNo = updated.internalNo ?? newVal;
      });

      if (updated.status == 6 || updated.decision == 'rejected') {
        widget.onClosed();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Interne Nummer gespeichert.')),
        );
      }
    } catch (e) {
      // Bei Fehler: alten Wert wiederherstellen (leer oder vorheriger Text)
      setState(() {
        widget.c.internalNo = (widget.c.internalNo ?? '').isEmpty ? null : widget.c.internalNo;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearInternalNo() async {
    if (_busy) return;
    setState(() => _busy = true);

    // UI sofort leeren
    setState(() {
      _internalCtrl.text = '';
      widget.c.internalNo = null;
    });

    try {
      final updated = await widget.api.adminComplaintUpdate(
        ticket: widget.c.ticket,
        internalNo: '',
      );
      setState(() {
        widget.c.internalNo = updated.internalNo; // bleibt i. d. R. null/leer
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Interne Nummer entfernt.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearReportLink() async {
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

      if (updated.status == 6 || updated.decision == 'rejected') {
        widget.onClosed();
      }

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Status/Entscheidung gespeichert.')));
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
      builder: (ctx) => AlertDialog(
        title: const Text('Reklamation löschen'),
        content: Text('Soll Ticket ${widget.c.ticket} wirklich gelöscht werden?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await widget.api.deleteComplaint(widget.c.ticket);
      widget.onClosed();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ticket ${widget.c.ticket} gelöscht.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  String _statusLabel(int v) {
    final m = kStatusItems.firstWhere((e) => e['value'] == v, orElse: () => const {});
    return (m['label'] ?? 'Status $v').toString();
  }

  // --- E-Mail an Kunden ------------------------------------------------
  String _buildMailSubject(AdminComplaint c) {
    final wish = c.handlingLabel == '—' ? '' : ' – ${c.handlingLabel}';
    return '[DFS Complaint ${c.ticket}] Rückfrage zu Ihrer Reklamation$wish';
  }

  String _buildMailBody(AdminComplaint c) {
    final p = c.payload ?? const <String, dynamic>{};
    final company = (widget.companyHint ?? '').trim();
    final greet = company.isNotEmpty ? 'Guten Tag $company,' : 'Guten Tag,';

    String line(String k, Object? v) {
      final s = (v ?? '').toString().trim();
      return s.isEmpty ? '' : '$k: $s\n';
    }

    final sb = StringBuffer()
      ..writeln(greet)
      ..writeln()
      ..writeln('wir haben Ihre Reklamation erhalten und benötigen noch eine kurze Rückmeldung zu einigen Punkten.')
      ..writeln('Nachfolgend finden Sie die bisherigen Angaben zur schnellen Übersicht:')
      ..writeln()
      ..writeln('— Reklamationsdetails —')
      ..write(line('Ticket', c.ticket))
      ..write(line('Segment', p['segment']))
      ..write(line('Artikel', p['article']))
      ..write(line('Charge', p['batch']))
      ..write(line('Menge', p['qty']))
      ..write(line('Ablaufdatum', p['expiry']))
      ..write(line('Beschreibung', p['desc']))
      ..write(line('Produkte zurückgeschickt', p['returned']))
      ..write(line('Gewünschte Behandlung', p['handling']))
      ..writeln()
      ..writeln('— Interner Bearbeitungsstand —')
      ..write(line('Status', _labelForStatus(c.status)))
      ..write(line('Entscheidung', _labelForDecision(c.decision)))
      ..write(line('Report-Link', c.reportLink))
      ..writeln()
      ..writeln('Können Sie uns bitte folgende Punkte kurz bestätigen/ergänzen?')
      ..writeln('• Sind alle betroffenen Artikel korrekt aufgeführt?')
      ..writeln('• Falls vorhanden: Bitte Bilder/weitere Hinweise beifügen.')
      ..writeln('• Bei Rücksendung: Tracking/Datum?')
      ..writeln()
      ..writeln('Vielen Dank im Voraus! Bei Rückfragen sind wir jederzeit gerne für Sie da.')
      ..writeln()
      ..writeln('Mit freundlichen Grüßen')
      ..writeln('DFS-DIAMON GmbH – Quality Management');

    return sb.toString();
  }

  String _labelForStatus(int s) {
    switch (s) {
      case 1: return 'Eingegangen';
      case 2: return 'In Bearbeitung';
      case 3: return 'Rückfrage erforderlich';
      case 5: return 'In Nacharbeit';
      case 6: return 'Abgeschlossen';
      default: return 'Unbekannt';
    }
  }

  String _labelForDecision(String? d) {
    switch ((d ?? '').trim()) {
      case 'accepted': return 'Angenommen';
      case 'rejected': return 'Abgelehnt';
      case '': return '—';
      default: return d!.trim();
    }
  }

  Color _decisionColor(String? d) {
    final v = (d ?? '').trim();
    if (v == 'accepted') return const Color(0xFF1B5E20); // grün
    if (v == 'rejected') return const Color(0xFFB71C1C); // rot
    return Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black54;
  }

  String _fmtDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  void _composeMailToCustomer() {
    final to = widget.c.email.trim();
    if (to.isEmpty) return;

    final subject = _buildMailSubject(widget.c);
    final body    = _buildMailBody(widget.c);

    final url = 'mailto:$to'
        '?subject=${Uri.encodeComponent(subject)}'
        '&body=${Uri.encodeComponent(body)}';

    html.window.open(url, '_self');
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final scheme = Theme.of(context).colorScheme;

    Color _statusColor(int s) {
      // gleiche Logik/Farben wie im Kundenbereich
      switch (s) {
        case 1:
          return scheme.outline; // Eingegangen – neutral
        case 2:
          return scheme.primary; // In Bearbeitung – primär
        case 3:
          return scheme.tertiary; // Rückfrage – tertiary/amber-ähnlich
        case 5:
          return scheme.secondary; // In Nacharbeit
        case 6:
          return Colors.green; // Abgeschlossen
        default:
          return scheme.outline;
      }
    }
  
    Widget _statusChip(int s) {
      final col = _statusColor(s);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: col.withOpacity(0.12),
          border: Border.all(color: col, width: 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _statusLabel(s),
          style: TextStyle(color: col, fontWeight: FontWeight.w700),
        ),
      );
    }

    String _fmtDate(DateTime d) {
      String two(int n) => n < 10 ? '0$n' : '$n';
      return '${two(d.day)}.${two(d.month)}.${d.year}';
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // =====================
            // Kopfzeile (übersichtlich)
            // =====================
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Linke Seite: Ticket + Interne Nr. + Datum + Status-Chip
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1) Ticket + (optional) Interne Nr. als Tag direkt daneben
                      Row(
                        children: [
                          Text(
                            'Ticket: ${c.ticket}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                          const SizedBox(width: 10),
                          if ((c.internalNo ?? '').trim().isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceVariant,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outlineVariant,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.tag, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Intern: ${c.internalNo}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // 3) Datum + Status + (optional) Vertreter-Ampel
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.event, size: 16),
                              SizedBox(width: 6),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.event, size: 16),
                              const SizedBox(width: 6),
                              Text('Eingang: ${_fmtDate(c.createdAt)}'),
                            ],
                          ),
                          _statusChip(c.status),

                          // Ampel nur zeigen, wenn Kunde einem Vertreter zugeordnet ist
                          if (widget.hasRep)
                            _RepTrafficLight(
                              opinion: ((c.repOpinion ?? '').trim().isEmpty) ? 'pending' : c.repOpinion,
                              compact: true,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Rechte Seite: Firma/E-Mail – lesbar (Light: schwarz, Dark: onSurface) + Mail-Icon
                Builder(
                  builder: (ctx) {
                    final isDark = Theme.of(ctx).brightness == Brightness.dark;
                    final label = (widget.companyHint != null && widget.companyHint!.trim().isNotEmpty)
                        ? 'Firma: ${widget.companyHint}'
                        : 'E-Mail: ${c.email}';
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Theme.of(ctx).colorScheme.onSurface : Colors.black,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'E-Mail an Kunden verfassen',
                          icon: const Icon(Icons.email_outlined),
                          onPressed: _busy ? null : _composeMailToCustomer,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 10),

            // ===================== Entscheidung + Wunsch (gemeinsame Meta-Zeile) =====================
            Builder(
              builder: (_) {
                final decText = _labelForDecision(c.decision);
                final decCol  = _decisionColor(c.decision);
                final wish    = c.handlingLabel; // kommt aus payload['handling'] / 'Wunsch'

                // Linker Teil: Entscheidung (farbig) + Wunsch (neutral)
                final left = Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Entscheidung: '),
                        Text(
                          decText,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: decCol,
                          ),
                        ),
                      ],
                    ),
                    // Trenner-Punkt
                    const Text('•'),
                    // Wunsch des Kunden (immer anzeigen, Strich wenn leer)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Wunsch: ',
                          style: TextStyle(fontWeight: FontWeight.w400),
                        ),
                        Text(
                          (wish.trim().isEmpty || wish == '—') ? '—' : wish,
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Theme.of(context).textTheme.bodyMedium?.color,
                          ),
                        ),
                      ],
                    ),
                  ],
                );

                return Row(
                  children: [
                    // links: Entscheidung + Wunsch im Wrap (bricht sauber auf kleinen Screens)
                    Expanded(child: left),
                    // rechts: Bearbeiten-Button wie gehabt
                    TextButton.icon(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      icon: Icon(_expanded ? Icons.expand_less : Icons.edit),
                      label: Text(_expanded ? 'Bearbeiten schließen' : 'Bearbeiten'),
                    ),
                  ],
                );
              },
            ),

            // KEIN prominenter Wunsch-Banner mehr!

            if (_expanded) ...[
              const SizedBox(height: 10),

              // ---- Toggle + Details-Container (NEU, optional ein/ausklappbar) ----
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                    label: const Text('Details anzeigen'), // ändert sich unten dynamisch
                  ),
                ],
              ),
              AnimatedCrossFade(
                crossFadeState: _expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                duration: const Duration(milliseconds: 160),
                firstChild: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Details der Reklamation',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      _detKv('Segment',       segment),
                      _detKv('Produkttyp',    productType),
                      _detKv('Artikelnummer', articleNo),
                      Row(
                       children: [
                          Expanded(child: _detKv('Charge / LOT', batch)),
                          const SizedBox(width: 12),
                          Expanded(child: _detKv('Seriennummer', serial)),
                          const SizedBox(width: 12),
                          SizedBox(width: 160, child: _detKv('Menge', qty)),
                        ],
                      ),
                      _detKv('Fehler / Beschreibung', desc, maxLines: 6),
                      _detKv('Grund / Ursache',       reason, maxLines: 4),
                      _detKv('Wunsch des Kunden',     customerWish, maxLines: 3),
                    ],
                  ),
                ),
                secondChild: const SizedBox.shrink(),
              ),

              // ====== Editor-Bereich (unverändert inhaltlich) ======                        
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _status,
                          decoration: const InputDecoration(
                            labelText: 'Status',
                            border: OutlineInputBorder(),
                          ),
                          items: kStatusItems
                              .map((e) => DropdownMenuItem<int>(
                                    value: e['value'] as int,
                                    child: Text(e['label'] as String),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _status = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _decision ?? '',
                          decoration: const InputDecoration(
                            labelText: 'Entscheidung',
                            border: OutlineInputBorder(),
                          ),
                          items: kDecisionItems
                              .map((e) => DropdownMenuItem<String>(
                                    value: e['value']!,
                                    child: Text(e['label']!),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _decision = (v == null || v.isEmpty) ? null : v),
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

                  TextField(
                    controller: _internalCtrl,
                    decoration: InputDecoration(
                      labelText: 'Interne DFS-Reklamationsnummer',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.tag),
                      suffixIcon: IconButton(
                        tooltip: 'Interne Nummer entfernen',
                        onPressed: _busy ? null : _clearInternalNo,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                    onSubmitted: (_) => _busy ? null : _saveInternalNo(), // ← NEU
                  ),

                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _saveInternalNo,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Interne Nummer speichern'),
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: _reportCtrl,
                    decoration: InputDecoration(
                      labelText: 'Report-Link (optional)',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'Link entfernen',
                        onPressed: _busy ? null : _clearReportLink,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _saveReportLink,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Link speichern'),
                    ),
                  ),

                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _busy ? null : _deleteComplaint,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Ticket löschen'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
// ===================================================================
// Admin API (Browser, dart:html)
// ===================================================================
class AdminApi {
  String _secret = '';
  void setSecret(String s) => _secret = s;

  String get baseUrl {
    final b = const String.fromEnvironment('API_BASE', defaultValue: '');
    if (b.isNotEmpty) return b;
    return html.window.location.origin;
  }

  Map<String, String> _headersJson() => {
        'Content-Type': 'application/json; charset=utf-8',
        if (_secret.isNotEmpty) 'X-Admin-Secret': _secret,
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
    try {
      final res = await html.HttpRequest.request(
        _u(path, q).toString(),
        method: method,
        requestHeaders: _headersJson(),
        sendData: body is String ? body : (body == null ? null : jsonEncode(body)),
        withCredentials: true,
      );
      return res;
    } catch (e) {
      if (e is html.ProgressEvent) {
        final t = e.target;
        if (t is html.HttpRequest) {
          final st = t.status;
          final txt = t.responseText ?? '';
          final stx = t.statusText ?? '';
          throw 'HTTP $st $stx — ${txt.isEmpty ? "Request fehlgeschlagen" : txt}';
        }
      }
      throw e.toString();
    }
  }

  // Pending
  Future<List<PendingUser>> fetchPending() async {
    final res = await _request('GET', '/api/admin/pending');
    if (res.status != 200) throw 'pending GET: HTTP ${res.status} ${res.responseText}';
    final txt = res.responseText ?? '';
    if (txt.trim().isEmpty) return <PendingUser>[];
    final List data = jsonDecode(txt);
    return data.map((e) => PendingUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> approvePending(String email, {String? lang}) async {
    final body = {'email': email, 'action': 'approve', if (lang != null) 'lang': lang};
    final res = await _request('POST', '/api/admin/pending', body: body);
    if (res.status != 200 && res.status != 204) {
      throw 'pending POST approve: HTTP ${res.status} ${res.responseText}';
    }
  }

  Future<void> deleteUser(String email) async {
    // Versuch 1: DELETE mit Query
    try {
      final r1 = await _request('DELETE', '/api/admin/users', q: {'email': email});
      if (r1.status == 200 || r1.status == 204) return;
    } catch (_) {}
    // Versuch 2: DELETE mit Body
    try {
      final r2 = await _request('DELETE', '/api/admin/users', body: {'email': email});
      if (r2.status == 200 || r2.status == 204) return;
    } catch (_) {}
    // Versuch 3: POST action=delete
    final r3 = await _request('POST', '/api/admin/users', body: {'action': 'delete', 'email': email});
    if (r3.status != 200 && r3.status != 204) {
      throw 'users DELETE/POST(delete) failed: HTTP ${r3.status} ${r3.responseText}';
    }
  }

  // Users
  Future<List<ActiveUser>> fetchUsers() async {
    final res = await _request('GET', '/api/admin/users');
    if (res.status != 200) throw 'users GET: HTTP ${res.status} ${res.responseText}';
    final txt = res.responseText ?? '';
    if (txt.trim().isEmpty) return <ActiveUser>[];
    final List data = jsonDecode(txt);
    return data.map((e) => ActiveUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  // Complaints (by email / open)
  Future<List<AdminComplaint>> fetchComplaintsByEmailDetailed(String email) async {
    final res = await _request('GET', '/api/admin/complaints', q: {'email': email, 'details': '1'});
    if (res.status != 200) throw 'complaints email GET: HTTP ${res.status} ${res.responseText}';
    final List data = jsonDecode(res.responseText ?? '[]');
    return data.map((e) => AdminComplaint.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<AdminComplaint>> fetchOpenComplaints() async {
    final res = await _request('GET', '/api/admin/complaints', q: {'open': '1'});
    if (res.status != 200) throw 'open complaints GET: HTTP ${res.status} ${res.responseText}';
    final List data = jsonDecode(res.responseText ?? '[]');
    return data.map((e) => AdminComplaint.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> fetchComplaintRawByTicket(String ticket) async {
    final res = await _request('GET', '/api/admin/complaints', q: {'ticket': ticket});
    if (res.status != 200) {
      throw 'complaint GET by ticket: HTTP ${res.status} ${res.responseText}';
    }
    final Map<String, dynamic> j = jsonDecode(res.responseText ?? '{}');
    return j;
  }

  // Update / Delete
  Future<AdminComplaint> adminComplaintUpdate({
    required String ticket,
    int? status,
    String? decision,
    String? reportLink,
    String? internalNo, // ← NEU
  }) async {
    final body = <String, dynamic>{'ticket': ticket};
    if (status != null) body['status'] = status;
    body['decision'] = decision ?? '';
    if (reportLink != null) body['reportLink'] = reportLink;
    if (internalNo != null) body['internalNo'] = internalNo; // ← NEU

    final res = await _request('POST', '/api/admin/complaints', body: body);
    if (res.status != 200) {
      throw 'HTTP ${res.status} ${res.statusText} — ${res.responseText ?? ''}';
    }
    final Map<String, dynamic> j =
        (res.responseText ?? '').trim().isEmpty ? <String, dynamic>{} : jsonDecode(res.responseText!);
    return AdminComplaint.fromJson(j);
  }

  Future<void> deleteComplaint(String ticket) async {
    // 1) DELETE ?ticket=...
    try {
      final r1 = await _request('DELETE', '/api/admin/complaints', q: {'ticket': ticket});
      if (r1.status == 200 || r1.status == 204) return;
    } catch (_) {/* Fallback */}
    // 2) DELETE Body
    final r2 = await _request('DELETE', '/api/admin/complaints', body: {'ticket': ticket});
    if (r2.status != 200 && r2.status != 204) {
      throw 'HTTP ${r2.status} ${r2.statusText} — ${r2.responseText ?? ''}';
    }
  }

  // ---------- Representatives (Vertreter) ----------
 Future<Rep> upsertRep({
    String? id,
    required String firstName,
    required String lastName,
    required String email,
    required String region,
  }) async {
    final body = {
      'action': 'upsert',                 // <-- NEU
      if (id != null && id.isNotEmpty) 'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'region': region,
    };
    final res = await _request('POST', '/api/admin/reps', body: body);
    if (res.status != 200 && res.status != 201) {
      throw 'reps POST: HTTP ${res.status} ${res.responseText}';
    }
    final Map<String, dynamic> j =
        (res.responseText ?? '').trim().isEmpty ? <String, dynamic>{} : jsonDecode(res.responseText!);
    return Rep.fromJson(j);
  }

  Future<void> deleteRep(String id) async {
    // Query-Variante (falls dein Backend das unterstützt)
    try {
      final r1 = await _request('DELETE', '/api/admin/reps', q: {'id': id});
      if (r1.status == 200 || r1.status == 204) return;
    } catch (_) {}

    // Body-Variante mit action: 'delete'
    final r2 = await _request('DELETE', '/api/admin/reps', body: {'action': 'delete', 'id': id});
    if (r2.status != 200 && r2.status != 204) {
      throw 'reps DELETE: HTTP ${r2.status} ${r2.responseText}';
    }
  }

  Future<List<Rep>> fetchReps({bool includeCustomers = true}) async {
    final q = includeCustomers ? {'includeCustomers': '1'} : null;
    final res = await _request('GET', '/api/admin/reps', q: q);
    if (res.status != 200) {
      throw 'reps GET: HTTP ${res.status} ${res.responseText}';
    }
    final List data = jsonDecode(res.responseText ?? '[]');
    return data.map((e) => Rep.fromJson((e as Map).cast<String, dynamic>())).toList();
  }
  Future<List<String>> assignCustomerToRep({required String repId, required String email}) async {
  final res = await _request('POST', '/api/admin/reps', body: {
    'action': 'assign',
    'repId': repId,
    'email': email,
  });
  if (res.status != 200) {
    throw 'reps assign: HTTP ${res.status} ${res.responseText}';
  }
  final Map<String, dynamic> j = jsonDecode(res.responseText ?? '{}');
  return (j['customers'] is List)
      ? List<String>.from((j['customers'] as List).map((e) => e.toString()))
      : const <String>[];
}

  Future<List<String>> unassignCustomerFromRep({required String repId, required String email}) async {
    final res = await _request('POST', '/api/admin/reps', body: {
      'action': 'unassign',
      'repId': repId,
      'email': email,
    });
    if (res.status != 200) {
      throw 'reps unassign: HTTP ${res.status} ${res.responseText}';
    }
    final Map<String, dynamic> j = jsonDecode(res.responseText ?? '{}');
    return (j['customers'] is List)
        ? List<String>.from((j['customers'] as List).map((e) => e.toString()))
        : const <String>[];
  }
}

// Farb-Mixer: mischt "top" mit Deckkraft t über "base"
Color _blend(Color base, Color top, double t) {
  return Color.alphaBlend(top.withOpacity(t.clamp(0, 1)), base);
}

// Kontrastfarbe für Text auf einem Farbfeld ermitteln
Color _bestOnColor(Color c) {
  final b = ThemeData.estimateBrightnessForColor(c);
  return (b == Brightness.dark) ? Colors.white : Colors.black;
}

// ===================================================================
// interne Hilfs-Resultklasse
// ===================================================================
class _ComplaintsResult {
  final bool loading;
  final String? error;
  final List<AdminComplaint> items;
  _ComplaintsResult._(this.loading, this.error, this.items);
  factory _ComplaintsResult.loading() => _ComplaintsResult._(true, null, const []);
  factory _ComplaintsResult.err(String e) => _ComplaintsResult._(false, e, const []);
  factory _ComplaintsResult.ok(List<AdminComplaint> list) => _ComplaintsResult._(false, null, list);
}

// ===================================================================
// Admin UI – Farbpalette & Kachel (Pro)
// ===================================================================
class AdminPalette {
  static const redA   = Color(0xFFFDE7E9);
  static const redB   = Color(0xFFE53935);
  static const amberA = Color(0xFFFFF4E5);
  static const amberB = Color(0xFFFF8F00);
  static const tealA  = Color(0xFFE6F4F1);
  static const tealB  = Color(0xFF00897B);
  static const blueA  = Color(0xFFE7F0FF);
  static const blueB  = Color(0xFF1E88E5);
}

class AdminTilePro extends StatefulWidget {
  final String label;
  final String? subtitle;
  final IconData icon;
  final Color colorA; // Hintergrund (hell)
  final Color colorB; // Akzent/Ikone
  final int? count;   // optionaler Zähler
  final bool compact; // für kleine Screens
  final VoidCallback onTap;

  const AdminTilePro({
    super.key,
    required this.label,
    this.subtitle,
    required this.icon,
    required this.colorA,
    required this.colorB,
    this.count,
    this.compact = false,
    required this.onTap,
  });

  @override
  State<AdminTilePro> createState() => _AdminTileProState();
}

class _AdminTileProState extends State<AdminTilePro> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accent = widget.colorB;
    final baseSurface = isDark ? cs.surfaceContainerHighest : cs.surface;
    final bgA = _blend(baseSurface, accent, isDark ? 0.08 : 0.06);
    final bgB = _blend(baseSurface, accent, isDark ? 0.04 : 0.00);

    final iconColor = isDark ? _blend(accent, cs.onSurface, 0.20) : accent;
    final titleColor = cs.onSurface;
    final subtitleColor = cs.onSurfaceVariant;

    final badgeBg = accent;
    final badgeFg = _bestOnColor(badgeBg);

    final br = BorderRadius.circular(14);
    final liftY = _hovering ? -7.0 : 0.0;
    final scale = _hovering ? 1.015 : 1.0;
    final elevation = _hovering ? 12.0 : 3.0;

    final iconSize = widget.compact ? 44.0 : 54.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.identity()..translate(0.0, liftY)..scale(scale),
        child: Material(
          elevation: elevation,
          borderRadius: br,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: br,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [bgA, bgB],
                ),
                border: Border.all(
                  color: isDark ? cs.outlineVariant.withOpacity(0.35) : cs.outlineVariant.withOpacity(0.25),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(widget.icon, size: iconSize, color: iconColor),
                      if (widget.count != null)
                        Positioned(
                          right: -6,
                          top: -6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [
                                if (isDark)
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.25),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                              ],
                            ),
                            child: Text(
                              '${widget.count}',
                              style: TextStyle(
                                color: badgeFg,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                      fontSize: 15.5,
                    ),
                  ),
                  if ((widget.subtitle ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.subtitle!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 13.0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DfsStatusPalette {
  static const entered     = Color(0xFF6E7B91); // 1
  static const inProgress  = Color(0xFF1F4C8F); // 2
  static const inquiry     = Color(0xFF8A6D00); // 3
  static const rework      = Color(0xFF0F766E); // 5
  static const closed      = Color(0xFF1B5E20); // 6
}
