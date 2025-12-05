// lib/pages/admin_page.dart
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dfs_mobile/web_compat/html_stub.dart'
  if (dart.library.html) 'package:dfs_mobile/web_compat/html_web.dart' as html;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:dfs_mobile/api/client.dart';
import 'package:dfs_mobile/models/complaint.dart' show ComplaintUpload;
import 'package:dfs_mobile/models/country.dart';
import 'package:dfs_mobile/models/customer_news_entry.dart';
import 'package:dfs_mobile/widgets/dialog_content_scroll.dart';
import 'package:dfs_mobile/widgets/legal_footer.dart';
import 'package:dfs_mobile/widgets/password_field.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'admin_stats_page.dart';

// ===================================================================
// Admin Page – mit Kachel-Menü (wie Kunden-Dashboard)
// ===================================================================
class AdminPage extends StatefulWidget {
  final ApiClient api;
  const AdminPage({super.key, required this.api});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

enum _AdminView { menu, pending, users, open, reps, systemHealth, createCustomer, news }

enum _CustPasswordMode { adminSecret, generated }

class _AdminPageState extends State<AdminPage> {
  late final AdminApi _api;

  // Ladeflags / Fehler
  bool _loadPending = false;
  bool _loadUsers = false;
  bool _loadOpen = false;
  bool _loadReps = false;
  String? _fatalErr;
  String? _err;
  bool _systemHealthBusy = false;
  String? _systemHealthErr;
  SystemHealthResult? _systemHealth;
  String? _userFilterRepId;
  String _userFilterCompany = 'Alle Firmen';
  String _userFilterCountry = 'Alle Länder';


  // Vertreter-Form (persistente Felder)
  final _repFirstCtrl = TextEditingController();
  final _repLastCtrl  = TextEditingController();
  final _repMailCtrl  = TextEditingController();
  String _repRegion   = kRepRegions.first;
  List<String> _repRegionOptions = List<String>.from(kRepRegions);
  bool _repBusy       = false;

  // Admin-Kundenanlage (persistente Felder)
  final _custFormKey       = GlobalKey<FormState>();
  final _custCompanyCtrl   = TextEditingController();
  final _custFirstNameCtrl = TextEditingController();
  final _custLastNameCtrl  = TextEditingController();
  final _custEmailCtrl     = TextEditingController();
  final _custStreetCtrl    = TextEditingController();
  final _custZipCtrl       = TextEditingController();
  final _custCityCtrl      = TextEditingController();
  final _custPhoneCtrl     = TextEditingController();
  String _custLang         = 'de';
  late Country _custCountry;
  bool _custBusy           = false;
  String? _custErr;
  _CustPasswordMode _custPasswordMode = _CustPasswordMode.adminSecret;

  // Daten
  List<PendingUser> _pending = [];
  List<ActiveUser> _users = [];
  List<AdminComplaint> _openComplaints = [];
  List<Rep> _reps = [];
  List<CustomerNewsEntry> _newsEntries = [];
  bool _newsLoading = false;
  String? _newsErr;

  static const Map<String, String> _newsCategoryLabels = {
    'catalogs': 'Kataloge',
    'technical': 'Technische Änderungen',
    'regulatory': 'Regulatorik (MDR/PMCF)',
    'product': 'Produktneuheiten',
    'shortage': 'Engpässe & Einschränkungen',
    'app': 'App-Versionen',
    'general': 'Allgemein',
  };

  // Email -> detaillierte Reklamationen (für Users/Pending)
  final Map<String, _ComplaintsResult> _complaints = {};

  // Firmenfilter (Offene Reklamationen)
  String _filterCompany = 'Alle Firmen';

  // Ansicht (Menü / Bereich)
  _AdminView _view = _AdminView.menu;

  Country get _defaultCountry => kCountries.firstWhere(
        (c) => c.code == 'DE',
        orElse: () => kCountries.first,
      );

  String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    final iso = local.toIso8601String();
    final trimmed = iso.contains('.') ? iso.split('.').first : iso;
    return trimmed.replaceFirst('T', ' ');
  }

  @override
  void initState() {
    super.initState();
    _api = AdminApi(onNewsChanged: widget.api.clearCustomerNewsCache);
    _custCountry = _defaultCountry;

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

  String _newsCategoryLabel(String code) {
    final key = code.trim().toLowerCase();
    return _newsCategoryLabels[key] ?? _newsCategoryLabels['general']!;
  }

  Future<void> _handleDebugPushRegister() async {
    try {
      try {
        await Firebase.initializeApp();
      } catch (_) {
        // Bereits initialisiert ist okay.
      }

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      final token = await messaging.getToken();
      if (!mounted) return;
      if (token == null || token.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kein FCM-Token erhalten.')),
        );
        return;
      }

      await widget.api.registerPushToken(
        token,
        platform: kIsWeb ? 'web' : 'android',
        locale: '',
        lang: null,
      );

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('FCM-Token (Debug)'),
          content: DialogContentScroll(
            child: SelectableText(
              token,
              style: const TextStyle(fontSize: 10),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Schließen'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler bei Push-Register: $e')),
      );
    }
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
    final repId = _userFilterRepId;

    // Basisliste
    Iterable<ActiveUser> list = _users;

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

  List<String> _composeRepRegionOptions(Iterable<Rep> reps) {
    final options = <String>[...kRepRegions];
    final lower = options.map((e) => e.toLowerCase()).toSet();
    for (final r in reps) {
      final region = r.region.trim();
      if (region.isEmpty) continue;
      final key = region.toLowerCase();
      if (lower.add(key)) options.add(region);
    }
    return options;
  }

  Future<void> _refreshReps() async {
    setState(() { _err = null; _loadReps = true; });
    try {
      final list = await _api.fetchReps();
      if (!mounted) return;
      setState(() {
        _reps = list;
        _repRegionOptions = _composeRepRegionOptions(list);
        if (!_repRegionOptions.contains(_repRegion)) {
          _repRegion = _repRegionOptions.first;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _loadReps = false);
    }
  }

  Future<void> _promptCustomRegion() async {
    final ctrl = TextEditingController(text: _repRegion);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eigenen Länderbereich hinzufügen'),
        content: TextField(
          controller: ctrl,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Länderbereich',
            hintText: 'z. B. DACH, Südeuropa …',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Übernehmen')),
        ],
      ),
    );
    if (value == null) return;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    if (!mounted) return;
    setState(() {
      if (!_repRegionOptions.contains(trimmed)) {
        _repRegionOptions = [..._repRegionOptions, trimmed];
      }
      _repRegion = trimmed;
    });
  }

  Future<void> _loadSystemHealth({bool force = false}) async {
    if (_systemHealthBusy) return;
    if (!force && _systemHealth != null) return;
    setState(() {
      _systemHealthErr = null;
      _systemHealthBusy = true;
    });
    try {
      final status = await _api.fetchSystemHealth();
      if (!mounted) return;
      setState(() => _systemHealth = status);
    } catch (e) {
      if (mounted) setState(() => _systemHealthErr = '$e');
    } finally {
      if (mounted) setState(() => _systemHealthBusy = false);
    }
  }

  Future<void> _refreshNews() async {
    if (_newsLoading) return;
    setState(() {
      _newsLoading = true;
      _newsErr = null;
    });
    try {
      final list = await _api.fetchCustomerNewsEntries();
      if (!mounted) return;
      setState(() {
        _newsEntries = list;
        _newsErr = null;
      });
    } catch (e) {
      if (mounted) setState(() => _newsErr = '$e');
    } finally {
      if (mounted) setState(() => _newsLoading = false);
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
        content: DialogContentScroll(
          child: SizedBox(
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
        content: DialogContentScroll(child: Text(msg)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _showChangePasswordDialog() async {
    final oldPwCtrl = TextEditingController();
    final newPw1Ctrl = TextEditingController();
    final newPw2Ctrl = TextEditingController();
    String? err;
    var busy = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            Future<void> submit() async {
              if (newPw1Ctrl.text != newPw2Ctrl.text) {
                setState(() => err = 'Passwörter stimmen nicht überein.');
                return;
              }

              setState(() {
                busy = true;
                err = null;
              });

              try {
                await widget.api.accountChangePassword(
                  oldPwCtrl.text,
                  newPw1Ctrl.text,
                );

                if (!mounted || !ctx.mounted) return;
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Passwort wurde geändert.')),
                );
                return;
              } catch (e) {
                if (!ctx.mounted) return;
                setState(() => err = e.toString());
              } finally {
                if (!ctx.mounted) return;
                setState(() => busy = false);
              }
            }

            return AlertDialog(
              title: const Text('Passwort ändern'),
              content: DialogContentScroll(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (err != null) ...[
                      Text(err!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 8),
                    ],
                    PasswordField(
                      controller: oldPwCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Aktuelles Passwort',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    PasswordField(
                      controller: newPw1Ctrl,
                      decoration: const InputDecoration(
                        labelText: 'Neues Passwort',
                        helperText:
                            'Mindestens 8 Zeichen inklusive Buchstaben, Zahlen & Sonderzeichen.',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    PasswordField(
                      controller: newPw2Ctrl,
                      decoration: const InputDecoration(
                        labelText: 'Neues Passwort (Wiederholung)',
                        helperText:
                            'Mindestens 8 Zeichen inklusive Buchstaben, Zahlen & Sonderzeichen.',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );

    oldPwCtrl.dispose();
    newPw1Ctrl.dispose();
    newPw2Ctrl.dispose();
  }

  Future<void> _openNewsEditor({CustomerNewsEntry? entry}) async {
    final titleCtrl = TextEditingController(text: entry?.title ?? '');
    final summaryCtrl = TextEditingController(text: entry?.summary ?? '');
    final linkLabelCtrl = TextEditingController(text: entry?.linkLabel ?? '');
    final linkUrlCtrl = TextEditingController(text: entry?.linkUrl ?? '');
    String category = entry?.category ?? 'general';
    bool pinned = entry?.pinned ?? false;
    bool draft = entry?.draft ?? false;
    DateTime publishedAt = entry?.publishedAt ?? DateTime.now();
    final fmt = DateFormat('dd.MM.yyyy HH:mm');

    Future<void> pickDateTime(void Function(void Function()) setStateDialog) async {
      final pickedDate = await showDatePicker(
        context: context,
        initialDate: publishedAt,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (pickedDate == null) return;
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(publishedAt),
      );
      if (pickedTime == null) return;
      setStateDialog(() {
        publishedAt = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
      });
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: Text(entry == null ? 'Neuigkeit erstellen' : 'Neuigkeit bearbeiten'),
              content: DialogContentScroll(
                child: SizedBox(
                  width: 520,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(labelText: 'Titel', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: summaryCtrl,
                        minLines: 4,
                        maxLines: 8,
                        decoration: const InputDecoration(labelText: 'Beschreibung', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: category,
                        decoration: const InputDecoration(labelText: 'Kategorie'),
                        items: _newsCategoryLabels.entries
                            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                            .toList(),
                        onChanged: (v) => setModalState(() => category = v ?? 'general'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: linkLabelCtrl,
                        decoration: const InputDecoration(labelText: 'Link-Beschriftung (optional)', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: linkUrlCtrl,
                        decoration: const InputDecoration(labelText: 'Link-URL (https:// …)', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Veröffentlicht am'),
                        subtitle: Text(fmt.format(publishedAt.toLocal())),
                        trailing: IconButton(
                          icon: const Icon(Icons.schedule),
                          onPressed: () => pickDateTime(setModalState),
                        ),
                      ),
                      SwitchListTile(
                        value: pinned,
                        onChanged: (v) => setModalState(() => pinned = v),
                        title: const Text('Hervorheben'),
                      ),
                      SwitchListTile(
                        value: draft,
                        onChanged: (v) => setModalState(() => draft = v),
                        title: const Text('Als Entwurf behalten (nicht sichtbar)'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Speichern')),
              ],
            );
          },
        );
      },
    );

    if (saved != true) return;
    final title = titleCtrl.text.trim();
    final summary = summaryCtrl.text.trim();
    if (title.isEmpty || summary.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Titel und Beschreibung werden benötigt.')),
        );
      }
      return;
    }

    try {
      await _api.saveCustomerNews(
        id: entry?.id,
        title: title,
        summary: summary,
        category: category,
        pinned: pinned,
        draft: draft,
        publishedAt: publishedAt,
        linkLabel: linkLabelCtrl.text.trim().isEmpty ? null : linkLabelCtrl.text.trim(),
        linkUrl: linkUrlCtrl.text.trim().isEmpty ? null : linkUrlCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert.')));
      _refreshNews();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  Future<void> _deleteNewsEntry(CustomerNewsEntry entry) async {
    final ok = await _confirm('Neuigkeit löschen?', 'Eintrag "${entry.title}" dauerhaft entfernen?');
    if (ok != true) return;
    try {
      await _api.deleteCustomerNews(entry.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gelöscht.')));
        _refreshNews();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
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
    final title = switch (_view) {
      _AdminView.menu           => 'Adminbereich – DFS Customer Complaint',
      _AdminView.pending        => 'Pending (Freigabe ausstehend)',
      _AdminView.users          => 'Aktive Nutzer',
      _AdminView.open           => 'Offene Reklamationen',
      _AdminView.reps           => 'Vertreterverwaltung',
      _AdminView.systemHealth   => 'Systemstatus & Checks',
      _AdminView.createCustomer => 'Neuen Kunden anlegen',
      _AdminView.news           => 'Neuigkeiten & Infoscreen',
    };

    return WillPopScope(
      onWillPop: () async {
        if (_view != _AdminView.menu) {
          setState(() => _view = _AdminView.menu);
          return false;
        }
        return true;
      },
      child: Scaffold(
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
              tooltip: 'Passwort ändern',
              onPressed: _showChangePasswordDialog,
              icon: const Icon(Icons.lock_reset),
            ),
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
      ),
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
    final size = MediaQuery.of(context).size;
    final isPhone = size.width < 640;
    final compact = isPhone;

    final sections = <_AdminMenuSectionData>[
      _AdminMenuSectionData(
        title: 'Reklamationen',
        subtitle: 'Offene Fälle und Kennzahlen bearbeiten',
        tiles: [
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
            label: 'Statistik & KPIs',
            subtitle: 'Reklamationsübersicht',
            icon: Icons.query_stats_outlined,
            colorA: AdminPalette.blueA,
            colorB: AdminPalette.blueB,
            compact: compact,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AdminStatsPage(api: widget.api)),
              );
            },
          ),
        ],
      ),
      _AdminMenuSectionData(
        title: 'Kunden',
        subtitle: 'Registrierungen und Accounts steuern',
        tiles: [
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
            label: 'Neuen Kunden anlegen',
            subtitle: 'Account direkt erstellen',
            icon: Icons.person_add_alt_1_outlined,
            colorA: AdminPalette.tealA,
            colorB: AdminPalette.tealB,
            compact: compact,
            onTap: () => setState(() => _view = _AdminView.createCustomer),
          ),
        ],
      ),
      _AdminMenuSectionData(
        title: 'Vertreterverwaltung',
        subtitle: 'Zuordnungen & Regionen steuern',
        tiles: [
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
        ],
      ),
      _AdminMenuSectionData(
        title: 'Technischer Bereich',
        subtitle: 'Versionen und Hinweise pflegen',
        tiles: [
          AdminTilePro(
            label: 'Systemstatus',
            subtitle: 'Health & Konfiguration',
            icon: Icons.health_and_safety_outlined,
            colorA: AdminPalette.tealA,
            colorB: AdminPalette.tealB,
            compact: compact,
            onTap: () {
              setState(() => _view = _AdminView.systemHealth);
              _loadSystemHealth(force: true);
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
          AdminTilePro(
            label: 'Neuigkeiten / Infoscreen',
            subtitle: 'Updates für Kunden',
            icon: Icons.campaign_outlined,
            colorA: AdminPalette.amberA,
            colorB: AdminPalette.amberB,
            compact: compact,
            onTap: () {
              setState(() => _view = _AdminView.news);
              if (_newsEntries.isEmpty) _refreshNews();
            },
          ),
          AdminTilePro(
            label: 'Push-Register (Debug)',
            subtitle: 'FCM-Token testen',
            icon: Icons.notifications_active_outlined,
            colorA: AdminPalette.redA,
            colorB: AdminPalette.redB,
            compact: compact,
            onTap: () {
              _handleDebugPushRegister();
            },
          ),
        ],
      ),
    ];

    final headlineStyle = Theme.of(context)
        .textTheme
        .headlineSmall
        ?.copyWith(fontWeight: FontWeight.w700);
    final subtitleStyle = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, isPhone ? 12 : 24, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Admin-Dashboard', style: headlineStyle),
                const SizedBox(height: 6),
                Text(
                  'Verwalten Sie Reklamationen, Nutzer und Vertreter an einem Ort.',
                  style: subtitleStyle,
                ),
              ],
            ),
          ),
        ),
        for (var i = 0; i < sections.length; i++) ...[
          SliverToBoxAdapter(
            child: _buildMenuSectionHeader(
              sections[i],
              isFirst: i == 0,
              isPhone: isPhone,
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, i == sections.length - 1 ? 28 : 12),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, index) => sections[i].tiles[index],
                childCount: sections[i].tiles.length,
              ),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: isPhone ? 192 : 236,
                mainAxisSpacing: isPhone ? 14 : 26,
                crossAxisSpacing: isPhone ? 14 : 26,
                childAspectRatio: isPhone ? 0.82 : 0.92,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMenuSectionHeader(_AdminMenuSectionData section, {required bool isFirst, required bool isPhone}) {
    final titleStyle = Theme.of(context)
        .textTheme
        .titleLarge
        ?.copyWith(fontWeight: FontWeight.w700, fontSize: isPhone ? 20 : null);
    final subtitleStyle = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, isFirst ? 20 : 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.title, style: titleStyle),
          const SizedBox(height: 2),
          Text(section.subtitle, style: subtitleStyle),
        ],
      ),
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
      case _AdminView.systemHealth:
        return _buildSystemHealthPanel();
      case _AdminView.createCustomer:
        return _buildCreateCustomerPanel();
      case _AdminView.news:
        return _buildNewsPanel();
    }
  }

  Widget _buildCreateCustomerPanel() {
    String? req(String value, String label) {
      if (value.trim().isEmpty) return '$label wird benötigt';
      return null;
    }

    String? emailValidator(String? value) {
      final v = value?.trim() ?? '';
      if (v.isEmpty) return 'E-Mail wird benötigt';
      if (!v.contains('@') || !v.contains('.')) return 'E-Mail ungültig';
      return null;
    }

    final langItems = const <MapEntry<String, String>>[
      MapEntry('de', 'Deutsch'),
      MapEntry('en', 'Englisch'),
      MapEntry('fr', 'Französisch'),
      MapEntry('it', 'Italienisch'),
      MapEntry('es', 'Spanisch'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _custFormKey,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 560;

              Widget dualField(Widget a, Widget b) {
                if (isNarrow) {
                  return Column(
                    children: [
                      a,
                      const SizedBox(height: 12),
                      b,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: a),
                    const SizedBox(width: 12),
                    Expanded(child: b),
                  ],
                );
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(Icons.person_add_alt_1_outlined),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Neuen Kunden anlegen',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (_custBusy)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_custErr != null) ...[
                      Text(_custErr!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 8),
                    ],
                    TextFormField(
                      controller: _custCompanyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Firma',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (v) => req(v ?? '', 'Firma'),
                    ),
                    const SizedBox(height: 12),
                    dualField(
                      TextFormField(
                        controller: _custFirstNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Vorname',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        textInputAction: TextInputAction.next,
                        validator: (v) => req(v ?? '', 'Vorname'),
                      ),
                      TextFormField(
                        controller: _custLastNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nachname',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        textInputAction: TextInputAction.next,
                        validator: (v) => req(v ?? '', 'Nachname'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _custEmailCtrl,
                      decoration: const InputDecoration(
                        labelText: 'E-Mail',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: emailValidator,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _custStreetCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Straße & Hausnummer',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    dualField(
                      TextFormField(
                        controller: _custZipCtrl,
                        decoration: const InputDecoration(
                          labelText: 'PLZ',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      TextFormField(
                        controller: _custCityCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Ort',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<Country>(
                      value: _custCountry,
                      decoration: const InputDecoration(
                        labelText: 'Land',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      isExpanded: true,
                      items: kCountries
                          .map(
                            (c) => DropdownMenuItem<Country>(
                              value: c,
                              child: Text(c.label(context)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _custCountry = v);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _custPhoneCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Telefon (optional)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _custLang,
                      decoration: const InputDecoration(
                        labelText: 'Sprache',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: langItems
                          .map(
                            (entry) => DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _custLang = value ?? 'de'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Startpasswort',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                        ),
                      ),
                      child: Column(
                        children: [
                          RadioListTile<_CustPasswordMode>(
                            value: _CustPasswordMode.adminSecret,
                            groupValue: _custPasswordMode,
                            dense: true,
                            title: const Text('Admin-Passwort verwenden'),
                            subtitle: const Text('Keine Begrüßungsnachricht – Zugang nutzt das Admin-Passwort.'),
                            onChanged: _custBusy
                                ? null
                                : (mode) {
                                    if (mode == null) return;
                                    setState(() => _custPasswordMode = mode);
                                  },
                          ),
                          const Divider(height: 0),
                          RadioListTile<_CustPasswordMode>(
                            value: _CustPasswordMode.generated,
                            groupValue: _custPasswordMode,
                            dense: true,
                            title: const Text('Passwort generieren'),
                            subtitle: const Text('System erstellt ein 8-stelliges Passwort und verschickt es per E-Mail.'),
                            onChanged: _custBusy
                                ? null
                                : (mode) {
                                    if (mode == null) return;
                                    setState(() => _custPasswordMode = mode);
                                  },
                          ),
                        ],
                      ),
                    ),
                    if (_custPasswordMode == _CustPasswordMode.generated) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Hinweis: Das Passwort wird automatisch generiert und dem Kunden als systemgeneriertes Passwort in einer '
                        'Begrüßungsnachricht mitgeteilt. Es muss nach dem ersten Login im Kundenportal geändert werden.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Kundenaccount anlegen'),
                        onPressed: _custBusy
                            ? null
                            : () async {
                                final form = _custFormKey.currentState;
                                if (form == null || !form.validate()) return;

                                final first = _custFirstNameCtrl.text.trim();
                                final last = _custLastNameCtrl.text.trim();

                                setState(() {
                                  _custBusy = true;
                                  _custErr = null;
                                });

                                try {
                                  final selectedCountry = _custCountry;
                                  final contactCombined = '$first $last'.trim();

                                  await _api.createCustomerAdmin(
                                    company: _custCompanyCtrl.text.trim(),
                                    contact: contactCombined,
                                    email: _custEmailCtrl.text.trim(),
                                    street: _custStreetCtrl.text.trim(),
                                    zip: _custZipCtrl.text.trim(),
                                    city: _custCityCtrl.text.trim(),
                                    country: selectedCountry.label(context),
                                    countryCode: selectedCountry.code,
                                    firstName: first,
                                    lastName: last,
                                    phone: _custPhoneCtrl.text.trim(),
                                    lang: _custLang,
                                    passwordMode: _custPasswordMode == _CustPasswordMode.generated
                                        ? 'generated'
                                        : 'admin',
                                  );

                                  if (!mounted) return;
                                  FocusScope.of(context).unfocus();
                                  _resetCustomerForm();

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Kundenaccount wurde angelegt.'),
                                    ),
                                  );

                                  await _refreshAll();
                                } catch (e) {
                                  if (mounted) {
                                    setState(() => _custErr = e.toString());
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _custBusy = false);
                                  }
                                }
                              },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _resetCustomerForm() {
    _custCompanyCtrl.clear();
    _custFirstNameCtrl.clear();
    _custLastNameCtrl.clear();
    _custEmailCtrl.clear();
    _custStreetCtrl.clear();
    _custZipCtrl.clear();
    _custCityCtrl.clear();
    _custPhoneCtrl.clear();

    if (!mounted) {
      _custLang = 'de';
      _custCountry = _defaultCountry;
      _custPasswordMode = _CustPasswordMode.adminSecret;
      return;
    }

    setState(() {
      _custLang = 'de';
      _custCountry = _defaultCountry;
      _custPasswordMode = _CustPasswordMode.adminSecret;
    });
  }

  Widget _buildSystemHealthPanel() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = _systemHealth;
    final checks = status?.checks ?? const <SystemHealthCheck>[];
    final overallStatus = status?.status ??
        (status?.ok == null
            ? null
            : status!.ok
                ? SystemHealthStatus.ok
                : SystemHealthStatus.critical);
    final tsLabel = status != null ? _formatTimestamp(status.timestamp) : null;
    final warningLabels = checks.where((c) => c.isWarning).map((c) => c.label).toList();
    final failingLabels = checks.where((c) => c.isCritical).map((c) => c.label).toList();

    Color summaryBg;
    Color summaryFg;
    IconData summaryIcon;
    String summaryText;

    if (overallStatus == SystemHealthStatus.ok) {
      summaryBg = cs.primaryContainer;
      summaryFg = cs.onPrimaryContainer;
      summaryIcon = Icons.check_circle_outline;
      summaryText = 'Alle Checks erfolgreich.';
    } else if (overallStatus == SystemHealthStatus.warn) {
      summaryBg = cs.tertiaryContainer;
      summaryFg = cs.onTertiaryContainer;
      summaryIcon = Icons.warning_amber_rounded;
      final labels = [...warningLabels, ...failingLabels];
      summaryText = labels.isNotEmpty
          ? 'Eingeschränkte Verfügbarkeit/Störung: ${labels.join(', ')}'
          : 'Mindestens ein Check meldet eine Störung.';
    } else if (overallStatus == SystemHealthStatus.critical) {
      summaryBg = cs.errorContainer;
      summaryFg = cs.onErrorContainer;
      summaryIcon = Icons.error_outline;
      summaryText = failingLabels.isNotEmpty
          ? 'Ausfälle/Störungen bei: ${failingLabels.join(', ')}'
          : 'Mindestens ein Check meldet einen Ausfall.';
    } else {
      summaryBg = cs.surfaceVariant.withOpacity(0.7);
      summaryFg = cs.onSurfaceVariant;
      summaryIcon = Icons.health_and_safety_outlined;
      summaryText = _systemHealthBusy
          ? 'Prüfung läuft …'
          : 'Noch kein Ergebnis – bitte Check starten.';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.health_and_safety_outlined),
                const SizedBox(width: 8),
                const Text(
                  'Systemstatus & Validierung',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Neu laden',
                  onPressed: _systemHealthBusy ? null : () => _loadSystemHealth(force: true),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_systemHealthBusy) const LinearProgressIndicator(),
            if (_systemHealthErr != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _systemHealthErr!,
                  style: TextStyle(color: cs.onErrorContainer),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: summaryBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(summaryIcon, color: summaryFg),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(summaryText, style: TextStyle(color: summaryFg, fontWeight: FontWeight.w600)),
                        if (tsLabel != null) ...[
                          const SizedBox(height: 4),
                          Text('Stand: $tsLabel', style: TextStyle(color: summaryFg.withOpacity(0.9))),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: checks.isEmpty
                  ? Center(
                      child: Text(
                        status == null
                            ? (_systemHealthBusy ? 'Prüfung läuft …' : 'Noch kein System-Check gestartet.')
                            : 'Keine Check-Daten verfügbar.',
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemBuilder: (_, index) => _SystemHealthCheckCard(check: checks[index]),
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemCount: checks.length,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewsPanel() {
    final dateFmt = DateFormat('dd.MM.yyyy HH:mm');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Neuigkeiten & Infoscreen', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  Text('Aktuelle Hinweise für Kunden pflegen'),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Neu laden',
              onPressed: _newsLoading ? null : _refreshNews,
              icon: const Icon(Icons.refresh),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _openNewsEditor(),
              icon: const Icon(Icons.add),
              label: const Text('Neu anlegen'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_newsLoading) const LinearProgressIndicator(),
        if (_newsErr != null) ...[
          const SizedBox(height: 8),
          Text('Fehler beim Laden: $_newsErr', style: const TextStyle(color: Colors.red)),
        ],
        if (_newsEntries.isEmpty && !_newsLoading) ...[
          const SizedBox(height: 12),
          const Text('Noch keine Neuigkeiten hinterlegt.', style: TextStyle(fontStyle: FontStyle.italic)),
        ],
        for (final entry in _newsEntries) _buildNewsAdminCard(entry, dateFmt),
      ],
    );
  }

  Widget _buildNewsAdminCard(CustomerNewsEntry entry, DateFormat fmt) {
    final theme = Theme.of(context);
    final chips = <Widget>[
      Chip(label: Text(_newsCategoryLabel(entry.category))),
      if (entry.pinned) const Chip(label: Text('Hervorgehoben')), 
      if (entry.draft) const Chip(label: Text('Entwurf')),
    ];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: chips,
            ),
            const SizedBox(height: 10),
            Text(entry.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(entry.summary),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.schedule, size: 16),
                const SizedBox(width: 6),
                Text('Veröffentlicht: ${fmt.format(entry.publishedAt.toLocal())}'),
                const Spacer(),
                if (entry.linkUrl != null && entry.linkUrl!.isNotEmpty)
                  Text(entry.linkUrl!, style: TextStyle(color: theme.colorScheme.primary)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _openNewsEditor(entry: entry),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Bearbeiten'),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () => _deleteNewsEntry(entry),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Löschen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 600;

            final spinner = _loadPending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null;

            Widget header = Row(
              children: [
                const Icon(Icons.hourglass_top),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Pending (Freigabe ausstehend)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (spinner != null) ...[
                  const SizedBox(width: 8),
                  spinner,
                ],
              ],
            );

            if (isCompact) {
              header = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.hourglass_top),
                      SizedBox(width: 8),
                      Text(
                        'Pending (Freigabe ausstehend)',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  if (spinner != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: spinner,
                    ),
                  ],
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const SizedBox(height: 8),
                if (_loadPending) const LinearProgressIndicator(),
                if (_loadPending) const SizedBox(height: 8) else const SizedBox(height: 12),
                Expanded(
                  child: _pending.isEmpty
                      ? const Center(child: Text('Keine Pending-Anmeldungen.'))
                      : ListView.separated(
                          itemCount: _pending.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
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
                                final ok = await _confirm(
                                  'Anmeldung ablehnen',
                                  'Soll ${p.email} wirklich abgelehnt und gelöscht werden?',
                                );
                                if (ok != true) return;
                                try {
                                  await _api.deleteUser(p.email);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Eintrag gelöscht: ${p.email}')),
                                    );
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
            );
          },
        ),
      ),
    );
  }


Widget _buildUsersPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 720;

            final spinner = _loadUsers
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null;

            Widget header;
            if (isCompact) {
              header = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.people),
                      SizedBox(width: 8),
                      Text(
                        'Aktive Nutzer',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (spinner != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: spinner,
                        ),
                    ],
                  ),
                ],
              );
            } else {
              header = Row(
                children: [
                  const Icon(Icons.people),
                  const SizedBox(width: 8),
                  const Text(
                    'Aktive Nutzer',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (spinner != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: spinner,
                    ),
                ],
              );
            }

            final companies = <String>{
              'Alle Firmen',
              ..._users.map((e) => e.company).where((s) => s.trim().isNotEmpty),
            }.toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
            final countries = <String>{
              'Alle Länder',
              ..._users.map((e) => e.country).where((s) => s.trim().isNotEmpty),
            }.toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

            String repName(String? id) {
              if (id == null) return 'Alle';
              if (id.isEmpty) return 'Ohne';
              final rep = _reps.firstWhere(
                (r) => r.id == id,
                orElse: () => Rep(
                  id: '',
                  firstName: '',
                  lastName: '',
                  email: '',
                  region: '',
                  customers: const [],
                ),
              );
              if (rep.id.isEmpty) return 'Alle';
              final dn = rep.displayName.trim();
              return dn.isEmpty ? rep.email : dn;
            }

            final filterWrap = Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                _FilterChipButton<String>(
                  icon: Icons.business,
                  label: 'Firma',
                  valueLabel:
                      _userFilterCompany == 'Alle Firmen' ? 'Alle' : _userFilterCompany,
                  maxWidth: isCompact ? constraints.maxWidth : 220,
                  initialValue: _userFilterCompany,
                  onSelected: (value) =>
                      setState(() => _userFilterCompany = value),
                  items: [
                    ...companies.map(
                      (c) => PopupMenuItem<String>(
                        value: c,
                        child: Text(c),
                      ),
                    ),
                  ],
                ),
                _FilterChipButton<String>(
                  icon: Icons.public,
                  label: 'Land',
                  valueLabel:
                      _userFilterCountry == 'Alle Länder' ? 'Alle' : _userFilterCountry,
                  maxWidth: isCompact ? constraints.maxWidth : 200,
                  initialValue: _userFilterCountry,
                  onSelected: (value) =>
                      setState(() => _userFilterCountry = value),
                  items: [
                    ...countries.map(
                      (c) => PopupMenuItem<String>(
                        value: c,
                        child: Text(c),
                      ),
                    ),
                  ],
                ),
                _FilterChipButton<String?>(
                  icon: Icons.badge_outlined,
                  label: 'Vertreter',
                  valueLabel: repName(_userFilterRepId),
                  maxWidth: isCompact ? constraints.maxWidth : 240,
                  initialValue: _userFilterRepId,
                  onSelected: (value) => setState(() => _userFilterRepId = value),
                  items: [
                    const PopupMenuItem<String?>(value: null, child: Text('Alle Vertreter')),
                    const PopupMenuItem<String?>(value: '', child: Text('Ohne Vertreter')),
                    ..._reps.map(
                      (r) => PopupMenuItem<String?>(
                        value: r.id,
                        child: Text(r.displayName.isEmpty ? r.email : r.displayName),
                      ),
                    ),
                  ],
                ),
                ],
              ),
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const SizedBox(height: 8),
                filterWrap,
                const SizedBox(height: 6),
                if (_loadUsers) const LinearProgressIndicator(),
                if (_loadUsers) const SizedBox(height: 12) else const SizedBox(height: 8),
                Expanded(
                  child: () {
                    final data = _filterUsers();
                    return data.isEmpty
                        ? const Center(child: Text('Keine aktiven Nutzer.'))
                        : ListView.separated(
                            itemCount: data.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
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
                                        SnackBar(content: Text('Nutzer gelöscht: ${u.email}')),
                                      );
                                      await _refreshAll();
                                      await _refreshOpen();
                                    }
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(content: Text('Fehler: $e')));
                                  }
                                },
                                onLoadComplaints: () => _loadComplaintsDetailed(u.email),
                                complaints: _complaints[u.email],
                                onClosedFromEditor: () {
                                  _refreshOpen();
                                },
                                repName: repName,
                                onToggleRevoked: (revoked) async {
                                  final title = revoked ? 'Nutzer sperren' : 'Sperre aufheben';
                                  final msg = revoked
                                      ? 'Soll der Zugang für ${u.email} wirklich gesperrt werden?'
                                      : 'Soll der Zugang für ${u.email} wieder freigeschaltet werden?';
                                  final ok = await _confirm(title, msg);
                                  if (ok != true) return;
                                  try {
                                    await _api.setUserRevoked(u.email, revoked);
                                    if (!mounted) return;
                                    final info = revoked
                                        ? 'Account gesperrt: ${u.email}'
                                        : 'Account freigeschaltet: ${u.email}';
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(content: Text(info)));
                                    await _refreshAll();
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(content: Text('Fehler: $e')));
                                  }
                                },
                              );
                            },
                          );
                  }(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildOpenPanel() {
    // Firmenliste für Filter-Dropdown (lokal)
    final List<String> companies = <String>{
      'Alle Firmen',
      ..._openComplaints
          .map((c) => (_companyByEmail(c.email) ?? ''))
          .where((s) => s.trim().isNotEmpty),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 720;
            final companyMenu = companies
                .map((s) => PopupMenuItem<String>(value: s, child: Text(s)))
                .toList();

            final spinner = _loadOpen
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null;

            final filterWrap = Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FilterChipButton<String>(
                    icon: Icons.business,
                    label: 'Firma',
                    valueLabel: _filterCompany == 'Alle Firmen' ? 'Alle' : _filterCompany,
                    initialValue: _filterCompany,
                    maxWidth: isCompact ? constraints.maxWidth : 220,
                    onSelected: (value) => setState(() => _filterCompany = value),
                    items: companyMenu,
                  ),
                ],
              ),
            );

            final titleRow = Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.receipt_long),
                SizedBox(width: 8),
                Text(
                  'Offene Reklamationen',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            );

            Widget header;
            if (isCompact) {
              header = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titleRow,
                  if (spinner != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: spinner,
                      ),
                    ),
                  ],
                ],
              );
            } else {
              header = Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  titleRow,
                  const Spacer(),
                  if (spinner != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: spinner,
                    ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 8),
                filterWrap,
                const SizedBox(height: 6),
                if (_loadOpen) const LinearProgressIndicator(),
                if (_loadOpen) const SizedBox(height: 12) else const SizedBox(height: 8),
                Expanded(
                  child: list.isEmpty
                      ? const Center(child: Text('Keine offenen Reklamationen.'))
                      : ListView.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (ctx, i) {
                            final c = list[i];
                            return _ComplaintEditor(
                              api: _api,
                              c: c,
                              companyHint: _companyByEmail(c.email),
                              hasRep: _customerHasRep(c.email),
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
            );
          },
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
          '&body=${Uri.encodeComponent(body ?? 'Guten Tag,\n\n…\n')}';
      if (kIsWeb) {
        html.window.open(url, '_self');
      }
    }

    Future<bool> _save({String? id}) async {
      if (_repBusy) return false;
      setState(() => _repBusy = true);
      try {
        final rep = await _api.upsertRep(
          id: id,
          firstName: _repFirstCtrl.text.trim(),
          lastName: _repLastCtrl.text.trim(),
          email: _repMailCtrl.text.trim(),
          region: _repRegion,
        );

        _repFirstCtrl.clear();
        _repLastCtrl.clear();
        _repMailCtrl.clear();
        _repRegion = _repRegionOptions.first;

        await _refreshReps();
        if (!mounted) return true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gespeichert: ${rep.displayName}')),
        );
        return true;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
        }
        return false;
      } finally {
        if (mounted) setState(() => _repBusy = false);
      }
    }

    Future<void> _edit(Rep r) async {
      _repFirstCtrl.text = r.firstName;
      _repLastCtrl.text = r.lastName;
      _repMailCtrl.text = r.email;
      _repRegion = r.region.isNotEmpty ? r.region : _repRegionOptions.first;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Vertreter bearbeiten'),
          content: DialogContentScroll(
            child: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: _repFirstCtrl, decoration: const InputDecoration(labelText: 'Vorname')),
                  const SizedBox(height: 8),
                  TextField(controller: _repLastCtrl, decoration: const InputDecoration(labelText: 'Nachname')),
                  const SizedBox(height: 8),
                  TextField(controller: _repMailCtrl, decoration: const InputDecoration(labelText: 'E-Mail')),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _repRegion,
                          decoration: const InputDecoration(labelText: 'Länderbereich'),
                          items: _repRegionOptions
                              .map((s) => DropdownMenuItem<String>(value: s, child: Text(s)))
                              .toList(),
                          onChanged: (v) => _repRegion = v ?? _repRegionOptions.first,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Eigenen Bereich hinzufügen',
                        child: IconButton(
                          onPressed: _promptCustomRegion,
                          icon: const Icon(Icons.add),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _save(id: r.id);
              },
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
          content: DialogContentScroll(child: Text('Soll ${r.displayName} wirklich gelöscht werden?')),
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

    Future<void> _openCreateRepSheet() async {
      _repFirstCtrl.clear();
      _repLastCtrl.clear();
      _repMailCtrl.clear();
      setState(() => _repRegion = _repRegionOptions.first);

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) {
          final bottom = MediaQuery.of(ctx).viewInsets.bottom;
          final theme = Theme.of(ctx);
          return Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Neuen Vertreter hinzufügen',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Schließen',
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _repFirstCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Vorname',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _repLastCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nachname',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _repMailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'E-Mail',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _repRegion,
                            decoration: const InputDecoration(
                              labelText: 'Länderbereich',
                              border: OutlineInputBorder(),
                            ),
                            items: _repRegionOptions
                                .map((s) => DropdownMenuItem<String>(value: s, child: Text(s)))
                                .toList(),
                            onChanged: (v) => setState(() => _repRegion = v ?? _repRegionOptions.first),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: 'Eigenen Bereich hinzufügen',
                          child: IconButton(
                            onPressed: _repBusy ? null : _promptCustomRegion,
                            icon: const Icon(Icons.add),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.person_add_alt_1),
                        onPressed: _repBusy
                            ? null
                            : () async {
                                final ok = await _save();
                                if (!mounted) return;
                                if (ok) Navigator.pop(ctx);
                              },
                        label: const Text('Vertreter speichern'),
                      ),
                    ),
                    if (_repBusy) ...[
                      const SizedBox(height: 16),
                      const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    Future<void> _openRepCustomersDialog(Rep rep) async {
      final Map<String, String> emailAssignedToRepId = {};
      for (final r in _reps) {
        for (final e in r.customers) {
          emailAssignedToRepId[e] ??= r.id;
        }
      }

      var assignedGlobal = emailAssignedToRepId.keys.toSet();
      final allUserEmails = _users.map((u) => u.email.trim()).where((e) => e.isNotEmpty).toSet();
      final all = allUserEmails.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      String? nextAssignableEmail() {
        final candidate = all.firstWhere(
          (e) => !assignedGlobal.contains(e),
          orElse: () => '',
        );
        return candidate.isEmpty ? null : candidate;
      }

      String? selEmail = nextAssignableEmail();

      bool busy = false;
      var localCustomers = List<String>.from(rep.customers);
      final media = MediaQuery.of(context);
      final useBottomSheet = media.size.width < 640;

      Widget buildBody(BuildContext ctx, StateSetter setLocal) {
        final theme = Theme.of(ctx);
        final textTheme = theme.textTheme;
        final listMaxHeight = useBottomSheet
            ? MediaQuery.of(ctx).size.height * 0.4
            : 280.0;
        final constrainedListHeight = listMaxHeight.clamp(160.0, 360.0).toDouble();

        Future<void> doAssign() async {
          if (selEmail == null || selEmail!.trim().isEmpty) return;
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

            await _refreshReps();

            setLocal(() {
              emailAssignedToRepId
                ..clear()
                ..addEntries(_reps.expand((r) => r.customers.map((e) => MapEntry(e, r.id))));
              assignedGlobal = emailAssignedToRepId.keys.toSet();
              busy = false;
              localCustomers = List<String>.from(customers);
              selEmail = nextAssignableEmail();
            });
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

            await _refreshReps();

            setLocal(() {
              emailAssignedToRepId
                ..clear()
                ..addEntries(_reps.expand((r) => r.customers.map((e) => MapEntry(e, r.id))));
              assignedGlobal = emailAssignedToRepId.keys.toSet();
              busy = false;
              localCustomers = List<String>.from(customers);
              if (selEmail != null && assignedGlobal.contains(selEmail)) {
                selEmail = nextAssignableEmail();
              }
            });
          } catch (e) {
            setLocal(() => busy = false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
            }
          }
        }

        final assignDropdown = DropdownButtonFormField<String>(
          value: selEmail,
          decoration: const InputDecoration(
            labelText: 'Kunde (E-Mail)',
            border: OutlineInputBorder(),
          ),
          items: all.map((e) {
            final isAssignedSomewhere = assignedGlobal.contains(e);
            final label = _companyByEmail(e) ?? e;
            final assignedHint = (isAssignedSomewhere && emailAssignedToRepId[e] != rep.id)
                ? ' (bereits zugewiesen)'
                : '';

            return DropdownMenuItem<String>(
              value: e,
              enabled: !isAssignedSomewhere,
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
                  if (assignedGlobal.contains(v)) return;
                  setLocal(() => selEmail = v);
                },
        );

        Widget buildAssignControls(BoxConstraints constraints) {
          final isNarrow = constraints.maxWidth < 420;
          final assignButton = FilledButton.icon(
            onPressed: busy || selEmail == null ? null : doAssign,
            icon: const Icon(Icons.add),
            label: const Text('Zuweisen'),
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                assignDropdown,
                const SizedBox(height: 12),
                assignButton,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: assignDropdown),
              const SizedBox(width: 12),
              assignButton,
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Zugewiesene Kunden (${localCustomers.length}) – jeder Kunde kann nur genau einem Vertreter zugeordnet sein.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: constrainedListHeight),
                  child: localCustomers.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('Keine Kunden zugewiesen.'),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: localCustomers.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final email = localCustomers[i];
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
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Kunden zuweisen',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600) ??
                    const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (ctx, constraints) => buildAssignControls(constraints)),
          ],
        );
      }

      if (useBottomSheet) {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setLocal) {
              return DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.9,
                minChildSize: 0.6,
                maxChildSize: 0.95,
                builder: (context, scrollController) {
                  final viewInsets = MediaQuery.of(context).viewInsets.bottom;
                  return Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + viewInsets),
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Kunden für ${rep.displayName}',
                                    style: Theme.of(ctx).textTheme.titleLarge,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Schließen',
                                  icon: const Icon(Icons.close),
                                  onPressed: () => Navigator.pop(ctx),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            buildBody(ctx, setLocal),
                            if (busy)
                              const Padding(
                                padding: EdgeInsets.only(top: 16),
                                child: Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                              ),
                            SizedBox(height: MediaQuery.of(ctx).padding.bottom),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text('Kunden für ${rep.displayName}'),
              content: DialogContentScroll(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: buildBody(ctx, setLocal),
                ),
              ),
              actions: [
                if (busy)
                  const Padding(
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
            LayoutBuilder(
              builder: (context, constraints) {
                final spinner = _loadReps
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : null;
                final isCompact = constraints.maxWidth < 720;

                final titleRow = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.badge_outlined),
                    SizedBox(width: 8),
                    Text('Vertreterverwaltung', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                );

                final actions = Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _repBusy ? null : _openCreateRepSheet,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Neuen Vertreter hinzufügen'),
                    ),
                    if (spinner != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: spinner,
                      ),
                  ],
                );

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      titleRow,
                      const SizedBox(height: 12),
                      actions,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleRow,
                    const Spacer(),
                    actions,
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            Expanded(
              child: _reps.isEmpty
                  ? const Center(child: Text('Keine Vertreter angelegt.'))
                  : ListView.separated(
                      itemCount: _reps.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final r = _reps[i];
                        return _RepTile(
                          rep: r,
                          onMail: () => _composeMail(
                            r.email,
                            subject: 'DFS-DIAMON – Anfrage / ${r.displayName}',
                            body: 'Guten Tag ${r.displayName},\n\n— Nachricht —\n\nBeste Grüße\nDFS-DIAMON GmbH',
                          ),
                          onEdit: () => _edit(r),
                          onDelete: () => _confirmDelete(r),
                          onManageCustomers: () => _openRepCustomersDialog(r),
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
  void dispose() {
    _repFirstCtrl.dispose();
    _repLastCtrl.dispose();
    _repMailCtrl.dispose();

    _custCompanyCtrl.dispose();
    _custFirstNameCtrl.dispose();
    _custLastNameCtrl.dispose();
    _custEmailCtrl.dispose();
    _custStreetCtrl.dispose();
    _custZipCtrl.dispose();
    _custCityCtrl.dispose();
    _custPhoneCtrl.dispose();

    super.dispose();
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

class _FilterChipButton<T> extends StatelessWidget {
  final IconData icon;
  final String label;
  final String valueLabel;
  final T initialValue;
  final List<PopupMenuEntry<T>> items;
  final ValueChanged<T> onSelected;
  final double? maxWidth;

  const _FilterChipButton({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.initialValue,
    required this.items,
    required this.onSelected,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = Color.alphaBlend(
      scheme.surfaceTint.withOpacity(isDark ? 0.16 : 0.22),
      scheme.surfaceContainerHigh.withOpacity(isDark ? 0.25 : 0.5),
    );
    final borderColor = scheme.outlineVariant.withOpacity(isDark ? 0.5 : 0.35);
    final baseStyle = theme.textTheme.labelLarge ?? const TextStyle(fontSize: 14);
    final textStyle = baseStyle.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.15,
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
      child: PopupMenuButton<T>(
        initialValue: initialValue,
        onSelected: onSelected,
        itemBuilder: (_) => items,
        offset: const Offset(0, 40),
        tooltip: '$label wählen',
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: scheme.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$label: $valueLabel',
                  style: textStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.keyboard_arrow_down, size: 17, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ===================================================================
// Admin-Menü-Kachel + Busy-Dot (Top-Level Widgets, nicht verschachteln)
// ===================================================================
class _AdminMenuSectionData {
  const _AdminMenuSectionData({
    required this.title,
    required this.subtitle,
    required this.tiles,
  });

  final String title;
  final String subtitle;
  final List<Widget> tiles;
}

class _SystemHealthCheckCard extends StatelessWidget {
  final SystemHealthCheck check;
  const _SystemHealthCheckCard({required this.check});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final statusColor = _statusColor(theme);
    final icon = switch (check.status) {
      SystemHealthStatus.ok => Icons.check_circle_outline,
      SystemHealthStatus.warn => Icons.warning_amber_rounded,
      SystemHealthStatus.critical => Icons.error_outline,
    };
    final iconColor = statusColor;
    final chips = _buildChips(theme);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.5 : 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: iconColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            check.label,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      check.statusLabel,
                      style: theme.textTheme.labelMedium?.copyWith(color: statusColor, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(check.message, style: theme.textTheme.bodyMedium),
                    if (check.details != null && check.details!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        check.details!,
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: chips,
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(ThemeData theme) {
    final cs = theme.colorScheme;
    switch (check.status) {
      case SystemHealthStatus.ok:
        return cs.primary;
      case SystemHealthStatus.warn:
        return Colors.orange.shade800;
      case SystemHealthStatus.critical:
        return cs.error;
    }
  }

  List<Widget> _buildChips(ThemeData theme) {
    final cs = theme.colorScheme;
    final chips = <Widget>[];
    final statusBg = switch (check.status) {
      SystemHealthStatus.ok => cs.primaryContainer,
      SystemHealthStatus.warn => cs.tertiaryContainer,
      SystemHealthStatus.critical => cs.errorContainer,
    };
    final statusFg = switch (check.status) {
      SystemHealthStatus.ok => cs.onPrimaryContainer,
      SystemHealthStatus.warn => cs.onTertiaryContainer,
      SystemHealthStatus.critical => cs.onErrorContainer,
    };
    chips.add(_metaChip(statusBg, statusFg, Icons.circle, check.statusLabel));
    final duration = check.durationMs;
    if (duration != null) {
      final label = duration >= 100
          ? '${duration.round()} ms'
          : '${duration.toStringAsFixed(1)} ms';
      chips.add(_metaChip(cs.primaryContainer, cs.onPrimaryContainer, Icons.speed, label));
    }
    final value = check.value;
    if (value != null) {
      chips.add(_metaChip(cs.secondaryContainer, cs.onSecondaryContainer, Icons.link, value));
    }
    final httpStatus = check.httpStatus;
    if (httpStatus != null) {
      chips.add(_metaChip(cs.surfaceVariant, cs.onSurfaceVariant, Icons.http, 'HTTP $httpStatus'));
    }
    final uptime = check.uptimeSeconds;
    if (uptime != null) {
      final uptimeMinutes = (uptime / 60).floor();
      chips.add(_metaChip(cs.secondaryContainer, cs.onSecondaryContainer, Icons.timer, 'Uptime: ${uptimeMinutes} min'));
    }
    final meanLatency = check.meanLatencyMs;
    final maxLatency = check.maxLatencyMs;
    if (meanLatency != null || maxLatency != null) {
      final parts = <String>[];
      if (meanLatency != null) parts.add('Ø ${meanLatency.toStringAsFixed(1)} ms');
      if (maxLatency != null) parts.add('max ${maxLatency.toStringAsFixed(1)} ms');
      chips.add(_metaChip(cs.surfaceVariant, cs.onSurfaceVariant, Icons.multiline_chart, parts.join(' · ')));
    }
    final url = check.targetUrl;
    if (url != null) {
      chips.add(_metaChip(cs.surfaceVariant, cs.onSurfaceVariant, Icons.public, url));
    }
    for (final miss in check.missingRequired) {
      chips.add(_metaChip(cs.errorContainer, cs.onErrorContainer, Icons.report_problem, 'Fehlt: $miss'));
    }
    for (final miss in check.missingOptional) {
      chips.add(_metaChip(cs.surfaceVariant, cs.onSurfaceVariant, Icons.info_outline, 'Optional: $miss'));
    }
    for (final note in check.notes) {
      chips.add(_metaChip(cs.tertiaryContainer, cs.onTertiaryContainer, Icons.sticky_note_2_outlined, note));
    }
    return chips;
  }

  Widget _metaChip(Color bg, Color fg, IconData icon, String label) {
    return Chip(
      backgroundColor: bg,
      avatar: Icon(icon, size: 16, color: fg),
      label: Text(label, style: TextStyle(color: fg)),
      visualDensity: VisualDensity.compact,
    );
  }
}

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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 36, color: color),
                const SizedBox(height: 8),
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
        content: DialogContentScroll(
          child: Column(
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 640;

        Widget buildIconButton({
          required String tooltip,
          required IconData icon,
          required VoidCallback onPressed,
        }) {
          return IconButton(
            tooltip: tooltip,
            icon: Icon(icon),
            onPressed: onPressed,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          );
        }

        Widget buildApproveButton({double? width}) {
          final button = FilledButton(onPressed: widget.onApprove, child: const Text('Freigeben'));
          if (width == null) return button;
          return SizedBox(width: width, child: button);
        }

        Widget buildRejectButton({double? width}) {
          final button = OutlinedButton(onPressed: widget.onReject, child: const Text('Ablehnen'));
          if (width == null) return button;
          return SizedBox(width: width, child: button);
        }

        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(subtitle.isEmpty ? '—' : subtitle),
            const SizedBox(height: 4),
            Text(d.email, style: Theme.of(context).textTheme.bodySmall),
          ],
        );

        Widget actionSection;
        if (isCompact) {
          actionSection = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: buildIconButton(
                      tooltip: 'Adressdaten',
                      icon: Icons.info_outline,
                      onPressed: _showAddress,
                    ),
                  ),
                  buildIconButton(
                    tooltip: 'Reklamationen anzeigen',
                    icon: _expanded ? Icons.expand_less : Icons.receipt_long,
                    onPressed: () {
                      setState(() => _expanded = !_expanded);
                      if (_expanded) widget.onLoadComplaints();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              buildApproveButton(width: double.infinity),
              const SizedBox(height: 8),
              buildRejectButton(width: double.infinity),
            ],
          );
        } else {
          actionSection = Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              buildIconButton(
                tooltip: 'Adressdaten',
                icon: Icons.info_outline,
                onPressed: _showAddress,
              ),
              buildIconButton(
                tooltip: 'Reklamationen anzeigen',
                icon: _expanded ? Icons.expand_less : Icons.receipt_long,
                onPressed: () {
                  setState(() => _expanded = !_expanded);
                  if (_expanded) widget.onLoadComplaints();
                },
              ),
              buildApproveButton(),
              buildRejectButton(),
            ],
          );
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  Theme.of(context).colorScheme.outlineVariant.withOpacity(0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isCompact) ...[
                header,
                const SizedBox(height: 12),
                actionSection,
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: header),
                    const SizedBox(width: 12),
                    actionSection,
                  ],
                ),
              ],
              if (_expanded) ...[
                const SizedBox(height: 12),
                _ComplaintsDetailList(
                  result: widget.complaints,
                  api: widget.api,
                  onClosed: () {},
                  companyHint: d.company,
                  padding: EdgeInsets.zero,
                ),
              ],
            ],
          ),
        );
      },
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
  final Future<void> Function(bool revoked) onToggleRevoked;

  const _UserTile({
    required this.data,
    required this.api,
    required this.onDelete,
    required this.onLoadComplaints,
    required this.complaints,
    required this.onClosedFromEditor,
    required this.onToggleRevoked,
    this.repName,
  });

  @override
  State<_UserTile> createState() => _UserTileState();
}

class _UserTileState extends State<_UserTile> {
  bool _expanded = false;
  bool _busyAction = false;

  void _showAddress() {
    final d = widget.data;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adressdaten'),
        content: DialogContentScroll(
          child: Column(
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 640;

        Widget buildIconButton({
          required String tooltip,
          required IconData icon,
          required VoidCallback onPressed,
        }) {
          return IconButton(
            tooltip: tooltip,
            icon: Icon(icon),
            onPressed: onPressed,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          );
        }

        final repInfo = widget.repName != null && widget.repName!.trim().isNotEmpty
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.badge_outlined, size: 16),
                  const SizedBox(width: 6),
                  Text('Vertreter: ${widget.repName}', style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              )
            : null;

        Widget buildStatusBadge(String text, Color color) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          );
        }

        final statusBadges = <Widget>[];
        if (d.revoked) {
          final color = Theme.of(context).colorScheme.error;
          statusBadges.add(buildStatusBadge('Account gesperrt', color));
        }
        if (d.selfDeleted) {
          statusBadges.add(buildStatusBadge('Account durch User gelöscht', Colors.red.shade700));
        }

        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(subtitle),
            const SizedBox(height: 4),
            Text(d.email, style: Theme.of(context).textTheme.bodySmall),
            if (repInfo != null) ...[
              const SizedBox(height: 6),
              repInfo,
            ],
            if (statusBadges.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: statusBadges,
              ),
            ],
          ],
        );

        Widget buildRevokeButton({bool expand = false}) {
          final icon = d.revoked ? Icons.lock_open : Icons.lock_outline;
          final label = d.revoked ? 'Freigeben' : 'Sperren';
          final button = OutlinedButton.icon(
            onPressed: _busyAction
                ? null
                : () async {
                    setState(() => _busyAction = true);
                    try {
                      await widget.onToggleRevoked(!d.revoked);
                    } finally {
                      if (mounted) setState(() => _busyAction = false);
                    }
                  },
            icon: Icon(icon),
            label: Text(label),
          );
          if (expand) {
            return SizedBox(width: double.infinity, child: button);
          }
          return button;
        }

        Widget buildDeleteButton({bool expand = false}) {
          final btn = OutlinedButton(
            onPressed: _busyAction ? null : () async => widget.onDelete(),
            child: const Text('Löschen'),
          );
          if (expand) {
            return SizedBox(width: double.infinity, child: btn);
          }
          return btn;
        }

        Widget actionSection;
        if (isCompact) {
          actionSection = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: buildIconButton(
                      tooltip: 'Adressdaten',
                      icon: Icons.info_outline,
                      onPressed: _showAddress,
                    ),
                  ),
                  buildIconButton(
                    tooltip: 'Reklamationen anzeigen',
                    icon: _expanded ? Icons.expand_less : Icons.receipt_long,
                    onPressed: () {
                      setState(() => _expanded = !_expanded);
                      if (_expanded) widget.onLoadComplaints();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              buildRevokeButton(expand: true),
              const SizedBox(height: 8),
              buildDeleteButton(expand: true),
            ],
          );
        } else {
          actionSection = Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              buildIconButton(
                tooltip: 'Adressdaten',
                icon: Icons.info_outline,
                onPressed: _showAddress,
              ),
              buildIconButton(
                tooltip: 'Reklamationen anzeigen',
                icon: _expanded ? Icons.expand_less : Icons.receipt_long,
                onPressed: () {
                  setState(() => _expanded = !_expanded);
                  if (_expanded) widget.onLoadComplaints();
                },
              ),
              buildRevokeButton(),
              buildDeleteButton(),
            ],
          );
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  Theme.of(context).colorScheme.outlineVariant.withOpacity(0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isCompact) ...[
                header,
                const SizedBox(height: 12),
                actionSection,
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: header),
                    const SizedBox(width: 12),
                    actionSection,
                  ],
                ),
              ],
              if (_expanded) ...[
                const SizedBox(height: 12),
                _ComplaintsDetailList(
                  result: widget.complaints,
                  api: widget.api,
                  onClosed: widget.onClosedFromEditor,
                  companyHint: d.company,
                  padding: EdgeInsets.zero,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _RepTile extends StatelessWidget {
  final Rep rep;
  final VoidCallback onMail;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onManageCustomers;

  const _RepTile({
    required this.rep,
    required this.onMail,
    required this.onEdit,
    required this.onDelete,
    required this.onManageCustomers,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 640;
        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(rep.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('${rep.email} • ${rep.region} • Kunden: ${rep.customers.length}'),
          ],
        );

        IconButton action({
          required String tooltip,
          required IconData icon,
          required VoidCallback onPressed,
        }) {
          return IconButton(
            tooltip: tooltip,
            icon: Icon(icon),
            onPressed: onPressed,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          );
        }

        final actionBar = Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            action(tooltip: 'E-Mail schreiben', icon: Icons.mail_outline, onPressed: onMail),
            action(tooltip: 'Bearbeiten', icon: Icons.edit_outlined, onPressed: onEdit),
            action(tooltip: 'Löschen', icon: Icons.delete_outline, onPressed: onDelete),
            action(tooltip: 'Kunden zuweisen/anzeigen', icon: Icons.group_add_outlined, onPressed: onManageCustomers),
          ],
        );

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  Theme.of(context).colorScheme.outlineVariant.withOpacity(0.4),
            ),
          ),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    header,
                    const SizedBox(height: 12),
                    actionBar,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: header),
                    const SizedBox(width: 12),
                    actionBar,
                  ],
                ),
        );
      },
    );
  }
}

class _ComplaintsDetailList extends StatelessWidget {
  final _ComplaintsResult? result;
  final AdminApi api;
  final VoidCallback onClosed;
  final String? companyHint;
  final EdgeInsetsGeometry? padding;

  const _ComplaintsDetailList({
    required this.result,
    required this.api,
    required this.onClosed,
    this.companyHint,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final r = result;
    final contentPadding = padding ?? const EdgeInsets.fromLTRB(16, 0, 16, 12);
    if (r == null) {
      return Padding(
        padding: contentPadding,
        child: const Text('Noch nicht geladen.'),
      );
    }
    if (r.loading) {
      return Padding(
        padding: contentPadding,
        child: const LinearProgressIndicator(),
      );
    }
    if (r.error != null) {
      return Padding(
        padding: contentPadding,
        child: Text('Fehler beim Laden: ${r.error}', style: const TextStyle(color: Colors.red)),
      );
    }
    if (r.items.isEmpty) {
      return Padding(
        padding: contentPadding,
        child: const Text('Keine Reklamationen gefunden.'),
      );
    }

    // Einmalig den Parent-State holen (performanter als pro Item)
    final parent = context.findAncestorStateOfType<_AdminPageState>();

    return Padding(
      padding: contentPadding,
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
  final bool revoked;
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
    required this.revoked,
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
        revoked: (j['revoked'] ?? false) == true,
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
        revoked: false,
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
  String? adminNotes;
  final Map<String, dynamic>? payload;
  final List<ComplaintUpload> uploads;

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
    this.adminNotes,
    this.payload,
    this.repOpinion,
    this.repId,
    List<ComplaintUpload>? uploads,
  }) : uploads = List.unmodifiable(uploads ?? const <ComplaintUpload>[]);

  static Map<String, dynamic> _coerceMap(dynamic value) {
    if (value is Map) {
      return value.map((key, v) => MapEntry('$key', v));
    }
    return <String, dynamic>{};
  }

  static List<ComplaintUpload> _parseUploads(dynamic value) {
    if (value is List) {
      final out = <ComplaintUpload>[];
      for (final entry in value) {
        if (entry is Map<String, dynamic>) {
          out.add(ComplaintUpload.fromJson(entry));
        } else if (entry is Map) {
          out.add(ComplaintUpload.fromJson(_coerceMap(entry)));
        }
      }
      return out;
    }
    return const <ComplaintUpload>[];
  }

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
    final uploads = _parseUploads(j['uploads'] ?? j['files']);

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
      adminNotes: (j['adminNotes'] ?? j['notes']) == null
          ? null
          : j['adminNotes']?.toString() ?? j['notes']?.toString(),
      payload: payload,
      repOpinion: _norm(repRaw),
      repId: repIdLocal,
      uploads: uploads,
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

enum SystemHealthStatus { ok, warn, critical }

SystemHealthStatus _parseHealthStatus(String? raw, {bool? okFallback}) {
  final normalized = raw?.toString().toLowerCase().trim();
  switch (normalized) {
    case 'ok':
      return SystemHealthStatus.ok;
    case 'warn':
    case 'warning':
      return SystemHealthStatus.warn;
    case 'critical':
    case 'error':
    case 'fail':
    case 'failed':
      return SystemHealthStatus.critical;
  }
  if (okFallback != null) {
    return okFallback ? SystemHealthStatus.ok : SystemHealthStatus.critical;
  }
  return SystemHealthStatus.warn;
}

String systemHealthStatusLabel(SystemHealthStatus status) {
  switch (status) {
    case SystemHealthStatus.ok:
      return 'Läuft';
    case SystemHealthStatus.warn:
      return 'Störung';
    case SystemHealthStatus.critical:
      return 'Ausfall';
  }
}

SystemHealthStatus combineHealthStatuses(Iterable<SystemHealthStatus> statuses) {
  var current = SystemHealthStatus.ok;
  for (final status in statuses) {
    if (status == SystemHealthStatus.critical) return SystemHealthStatus.critical;
    if (status == SystemHealthStatus.warn) current = SystemHealthStatus.warn;
  }
  return current;
}

class SystemHealthResult {
  final bool ok;
  final DateTime timestamp;
  final List<SystemHealthCheck> checks;
  final SystemHealthStatus status;

  SystemHealthResult({
    required this.ok,
    required this.timestamp,
    required List<SystemHealthCheck> checks,
    required this.status,
  }) : checks = List.unmodifiable(checks);

  factory SystemHealthResult.fromJson(Map<String, dynamic> json) {
    final rawTs = json['timestamp']?.toString();
    final ts = (rawTs != null && rawTs.isNotEmpty)
        ? (DateTime.tryParse(rawTs) ?? DateTime.now())
        : DateTime.now();
    final rawChecks = json['checks'];
    final list = <SystemHealthCheck>[];
    if (rawChecks is Map) {
      rawChecks.forEach((key, value) {
        if (value is Map) {
          list.add(SystemHealthCheck.fromJson(key.toString(), Map<String, dynamic>.from(value)));
        }
      });
    }
    list.sort((a, b) => a.order.compareTo(b.order));
    final status = combineHealthStatuses([
      _parseHealthStatus(json['status']?.toString(), okFallback: json['ok'] as bool?),
      ...list.map((c) => c.status),
    ]);
    return SystemHealthResult(ok: status == SystemHealthStatus.ok, timestamp: ts, checks: list, status: status);
  }
}

class SystemHealthCheck {
  final String key;
  final String label;
  final bool ok;
  final SystemHealthStatus status;
  final String message;
  final String? details;
  final Map<String, dynamic> meta;
  final int order;

  SystemHealthCheck({
    required this.key,
    required this.label,
    required this.ok,
    required this.status,
    required this.message,
    this.details,
    Map<String, dynamic>? meta,
    required this.order,
  }) : meta = Map.unmodifiable(meta ?? const {});

  factory SystemHealthCheck.fromJson(String key, Map<String, dynamic> json) {
    final meta = json['meta'];
    final metaMap = meta is Map
        ? Map<String, dynamic>.from(meta as Map)
        : <String, dynamic>{};
    final order = json['order'] is num
        ? (json['order'] as num).toInt()
        : int.tryParse('${json['order'] ?? ''}') ?? 100;
    return SystemHealthCheck(
      key: key,
      label: (json['label'] ?? key).toString(),
      ok: json['ok'] == true,
      status: _parseHealthStatus(json['status']?.toString(), okFallback: json['ok'] as bool?),
      message: (json['message'] ?? '').toString(),
      details: json['details']?.toString(),
      meta: metaMap,
      order: order,
    );
  }

  List<String> _metaList(String key) {
    final raw = meta[key];
    if (raw is List) {
      return raw
          .map((e) => e?.toString() ?? '')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  List<String> get missingRequired => _metaList('missingRequired');
  List<String> get missingOptional => _metaList('missingOptional');
  List<String> get notes => _metaList('notes');

  String get statusLabel => systemHealthStatusLabel(status);
  bool get isWarning => status == SystemHealthStatus.warn;
  bool get isCritical => status == SystemHealthStatus.critical;

  double? get durationMs => meta['durationMs'] is num
      ? (meta['durationMs'] as num).toDouble()
      : null;

  int? get httpStatus => meta['httpStatus'] is num
      ? (meta['httpStatus'] as num).toInt()
      : null;

  int? get uptimeSeconds => meta['uptimeSeconds'] is num
      ? (meta['uptimeSeconds'] as num).round()
      : null;

  double? get meanLatencyMs => meta['meanLatencyMs'] is num
      ? (meta['meanLatencyMs'] as num).toDouble()
      : null;

  double? get maxLatencyMs => meta['maxLatencyMs'] is num
      ? (meta['maxLatencyMs'] as num).toDouble()
      : null;

  String? get value {
    final raw = meta['value'];
    if (raw == null) return null;
    final s = raw.toString().trim();
    return s.isEmpty ? null : s;
  }

  String? get targetUrl {
    final raw = meta['url'];
    if (raw == null) return null;
    final s = raw.toString().trim();
    return s.isEmpty ? null : s;
  }
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
  {'label': 'Entscheidung', 'value': 4},
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
    final uploads = AdminComplaint._parseUploads(data['uploads'] ?? data['files']);
    final ticket = (data['ticket'] ?? '').toString();

    String _formatBytes(int size) {
      if (size <= 0) return '0 B';
      const kb = 1024;
      const mb = kb * 1024;
      if (size >= mb) {
        final value = size / mb;
        return value >= 10 ? '${value.toStringAsFixed(0)} MB' : '${value.toStringAsFixed(1)} MB';
      }
      if (size >= kb) {
        final value = size / kb;
        return value >= 10 ? '${value.toStringAsFixed(0)} KB' : '${value.toStringAsFixed(1)} KB';
      }
      return '$size B';
    }

    String _formatDate(DateTime date) {
      final l = date.toLocal();
      String two(int x) => x < 10 ? '0$x' : '$x';
      return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
    }

    Widget row(String l, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                flex: 0,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(l, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 8),
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
              if (uploads.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Anhänge:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                ...uploads.map(
                  (upload) => _AdminAttachmentPreviewTile(
                    upload: upload,
                    formatBytes: _formatBytes,
                    formatDate: _formatDate,
                    fallbackName: 'Unbenannte Datei',
                  ),
                ),
              ],
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
  final _notesCtrl = TextEditingController();
  bool _busy = false;
  bool _expanded = false;
  bool _noteOpen = false;

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

    const labelStyle = TextStyle(fontWeight: FontWeight.w600);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final valueStyle = Theme.of(context).textTheme.bodyMedium;
        final effectiveMaxLines = compact ? null : maxLines;

        final valueText = Text(
          v,
          style: valueStyle,
          maxLines: effectiveMaxLines,
          softWrap: true,
        );

        if (compact) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: labelStyle),
                const SizedBox(height: 4),
                valueText,
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
                child: Text(label, style: labelStyle),
              ),
              const SizedBox(width: 12),
              Expanded(child: valueText),
            ],
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _reportCtrl.text = widget.c.reportLink ?? '';
    _internalCtrl.text = widget.c.internalNo ?? '';
    _notesCtrl.text = widget.c.adminNotes ?? '';
    _status = widget.c.status;
    _decision = widget.c.decision;
  }

  @override
  void dispose() {
    _reportCtrl.dispose();
    _internalCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _syncNotesFrom(AdminComplaint updated) {
    final previous = widget.c.adminNotes ?? '';
    final next = updated.adminNotes ?? '';
    widget.c.adminNotes = updated.adminNotes;
    if (!_noteOpen || _notesCtrl.text == previous) {
      _notesCtrl.text = next;
    }
  }

  void _toggleNotes() {
    if (_noteOpen) {
      _closeNotes();
    } else {
      setState(() {
        _noteOpen = true;
        _notesCtrl.text = widget.c.adminNotes ?? '';
      });
    }
  }

  void _closeNotes() {
    setState(() {
      _noteOpen = false;
      _notesCtrl.text = widget.c.adminNotes ?? '';
    });
  }

  Future<void> _saveNotes() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.api.adminComplaintUpdate(
        ticket: widget.c.ticket,
        notes: _notesCtrl.text,
      );
      _syncNotesFrom(updated);
      _notesCtrl.text = updated.adminNotes ?? '';
      if (updated.status == 6 || updated.decision == 'rejected') {
        widget.onClosed();
      }
      setState(() {
        _noteOpen = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notiz gespeichert.')),
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
      _syncNotesFrom(updated);

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
      _syncNotesFrom(updated);

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
      _syncNotesFrom(updated);
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
      _syncNotesFrom(updated);

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
        content: DialogContentScroll(child: Text('Soll Ticket ${widget.c.ticket} wirklich gelöscht werden?')),
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

  String _fmtDateTime(DateTime d) {
    final local = d.toLocal();
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  String _formatBytes(int size) {
    if (size <= 0) return '0 B';
    const kb = 1024;
    const mb = kb * 1024;
    if (size >= mb) {
      final value = size / mb;
      return value >= 10 ? '${value.toStringAsFixed(0)} MB' : '${value.toStringAsFixed(1)} MB';
    }
    if (size >= kb) {
      final value = size / kb;
      return value >= 10 ? '${value.toStringAsFixed(0)} KB' : '${value.toStringAsFixed(1)} KB';
    }
    return '$size B';
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
    final storedNote = widget.c.adminNotes ?? '';
    final hasNote = storedNote.trim().isNotEmpty;
    final noteChanged = _notesCtrl.text != storedNote;
    // ---- Payload-Felder (nur lesend) ----
    final Map<String, dynamic>? p = (c.payload is Map) ? (c.payload as Map).cast<String, dynamic>() : null;
    final segment      = _detPickOrNull(p, ['segment','customer_segment','segment_code']);
    final productType  = _detPickOrNull(p, ['product_type','productType','type']);
    final articleNo    = _detPickOrNull(p, ['article_no','articleNumber','article','artnr']);
    final batch        = _detPickOrNull(p, ['batch_no','lot','lot_no','batch']);
    final serial       = _detPickOrNull(c.payload, ['serial_no', 'serial', 'sn']);
    final qty          = _detPickOrNull(p, ['qty','quantity','amount','menge']);
    final reason       = _detPickOrNull(p, ['reason','failure_reason','cause']);
    final desc         = _detPickOrNull(p, ['desc','description','comment','details','failure_desc']);
    final customerWish = _detPickOrNull(p, ['customer_wish','customerWish','wish','treatment_wish']);
    final applied     = _detPickOrNull(p, ['applied']);          // 'Ja' | 'Nein' | ''
    final injury      = _detPickOrNull(p, ['injury']);           // 'Ja' | 'Nein' | ''
    final injuryDesc  = _detPickOrNull(p, ['injuryDesc']);       // Freitext
    final returned    = _detPickOrNull(p, ['returned']);         // 'Ja' | 'Nein'
    final attachments = c.uploads;

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


    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 720;
        final isNarrow = constraints.maxWidth < 560;
        final currentStatus = kStatusItems.any((e) => e['value'] == _status)
            ? _status
            : null;

        final headerLeft = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Ticket: ${c.ticket}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                if (hasNote)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.sticky_note_2,
                      size: 16,
                      color: Colors.amber.shade800,
                    ),
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
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.event, size: 16),
                    const SizedBox(width: 6),
                    Text('Eingang: ${_fmtDate(c.createdAt)}'),
                  ],
                ),
                _statusChip(c.status),
                if (widget.hasRep)
                  _RepTrafficLight(
                    opinion: ((c.repOpinion ?? '').trim().isEmpty) ? 'pending' : c.repOpinion,
                    compact: true,
                  ),
              ],
            ),
          ],
        );

        final contactInfo = Builder(
          builder: (ctx) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final label = (widget.companyHint != null && widget.companyHint!.trim().isNotEmpty)
                ? 'Firma: ${widget.companyHint}'
                : 'E-Mail: ${c.email}';
            final width = isCompact ? constraints.maxWidth : math.min(360.0, constraints.maxWidth);
            return SizedBox(
              width: width,
              child: Row(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        tooltip: _noteOpen
                            ? 'Notiz schließen'
                            : (hasNote ? 'Notiz anzeigen/bearbeiten' : 'Notiz hinzufügen'),
                        icon: Icon(
                          (_noteOpen || hasNote) ? Icons.sticky_note_2 : Icons.sticky_note_2_outlined,
                          color: (_noteOpen || hasNote) ? const Color(0xFF8D6E63) : null,
                        ),
                        onPressed: _busy ? null : _toggleNotes,
                      ),
                      if (hasNote)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.amber.shade700,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.amber.shade200,
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Theme.of(ctx).colorScheme.onSurface : Colors.black,
                      ),
                      softWrap: true,
                      overflow: TextOverflow.fade,
                      maxLines: isNarrow ? 4 : 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'E-Mail an Kunden verfassen',
                    icon: const Icon(Icons.email_outlined),
                    onPressed: _busy ? null : _composeMailToCustomer,
                  ),
                ],
              ),
            );
          },
        );

        final topSection = isCompact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  headerLeft,
                  const SizedBox(height: 12),
                  contactInfo,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: headerLeft),
                  const SizedBox(width: 12),
                  Align(alignment: Alignment.topRight, child: contactInfo),
                ],
              );

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                topSection,
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) =>
                      SizeTransition(sizeFactor: anim, axisAlignment: -1, child: child),
                  child: !_noteOpen
                      ? const SizedBox.shrink()
                      : Builder(
                          builder: (ctx) {
                            final editingHasNote = _notesCtrl.text.trim().isNotEmpty;
                            return LayoutBuilder(
                              builder: (ctx, noteConstraints) {
                                final isNoteCompact = noteConstraints.maxWidth < 520;
                                final isVeryNarrow = noteConstraints.maxWidth < 380;
                                final noteMinLines = isNoteCompact ? 3 : 4;
                                final noteMaxLines = isNoteCompact ? 6 : 10;
                                final padding = EdgeInsets.fromLTRB(
                                  isNoteCompact ? 12 : 16,
                                  14,
                                  isNoteCompact ? 12 : 16,
                                  isNoteCompact ? 14 : 16,
                                );

                                final infoText = Text(
                                  editingHasNote
                                      ? 'Notizen sind nur im Adminbereich sichtbar.'
                                      : 'Noch keine Notiz gespeichert – alles bleibt intern.',
                                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                        color: const Color(0xFF6D4C41),
                                      ),
                                );

                                final closeButton = TextButton.icon(
                                  onPressed: _busy ? null : _closeNotes,
                                  icon: const Icon(Icons.close),
                                  label: const Text('Schließen'),
                                );

                                final saveButton = FilledButton.icon(
                                  onPressed: (_busy || !noteChanged) ? null : _saveNotes,
                                  icon: const Icon(Icons.save_outlined),
                                  label: const Text('Notiz speichern'),
                                );

                                Widget actionSection;
                                if (isNoteCompact) {
                                  actionSection = Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      infoText,
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: Wrap(
                                          alignment:
                                              isVeryNarrow ? WrapAlignment.center : WrapAlignment.end,
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            SizedBox(
                                              width: isVeryNarrow ? double.infinity : null,
                                              child: closeButton,
                                            ),
                                            SizedBox(
                                              width: isVeryNarrow ? double.infinity : null,
                                              child: saveButton,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                } else {
                                  actionSection = Row(
                                    children: [
                                      Expanded(child: infoText),
                                      closeButton,
                                      const SizedBox(width: 8),
                                      saveButton,
                                    ],
                                  );
                                }

                                return Container(
                                  key: const ValueKey('admin-note'),
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: padding,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF9C4),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.brown.withOpacity(0.18),
                                        blurRadius: 14,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                    border: Border.all(color: Colors.amber.shade200, width: 1.2),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.sticky_note_2, color: Color(0xFF8D6E63)),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Interne Notiz',
                                              style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                    color: const Color(0xFF5D4037),
                                                  ),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Schließen',
                                            onPressed: _busy ? null : _closeNotes,
                                            icon: const Icon(Icons.close),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: isNoteCompact ? 6 : 8),
                                      Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF8DC),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: Colors.amber.shade100),
                                        ),
                                        padding: const EdgeInsets.all(6),
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFFDF4),
                                            borderRadius: BorderRadius.circular(10),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Color(0x33BCAAA4),
                                                blurRadius: 8,
                                                offset: Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: TextField(
                                            controller: _notesCtrl,
                                            minLines: noteMinLines,
                                            maxLines: noteMaxLines,
                                            keyboardType: TextInputType.multiline,
                                            textInputAction: TextInputAction.newline,
                                            scrollPadding: EdgeInsets.only(
                                              bottom: MediaQuery.of(ctx).viewInsets.bottom + 80,
                                            ),
                                            enabled: !_busy,
                                            onChanged: (_) => setState(() {}),
                                            decoration: const InputDecoration(
                                              border: InputBorder.none,
                                              hintText:
                                                  'Hier deine interne Notiz zur Reklamation erfassen ...',
                                              contentPadding: EdgeInsets.fromLTRB(18, 16, 18, 18),
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: isNoteCompact ? 10 : 12),
                                      actionSection,
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
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

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      left,
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => setState(() => _expanded = !_expanded),
                        icon: Icon(_expanded ? Icons.expand_less : Icons.edit),
                        label: Text(_expanded ? 'Bearbeiten schließen' : 'Bearbeiten'),
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: left),
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

              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final theme = Theme.of(context);
                    final textTheme = theme.textTheme;
                    final colorScheme = theme.colorScheme;
                    final useTwoColumns = constraints.maxWidth >= 820;

                    void addDetail(
                      List<Widget> list,
                      String label,
                      String? value, {
                      int maxLines = 2,
                    }) {
                      final trimmed = (value ?? '').trim();
                      if (trimmed.isEmpty) return;
                      list.add(_detKv(label, trimmed, maxLines: maxLines));
                    }

                    List<Widget> spaced(List<Widget> items) {
                      final result = <Widget>[];
                      for (var i = 0; i < items.length; i++) {
                        result.add(items[i]);
                        if (i < items.length - 1) {
                          result.add(const SizedBox(height: 8));
                        }
                      }
                      return result;
                    }

                    final leftColumn = <Widget>[];
                    final rightColumn = <Widget>[];
                    final bottomSection = <Widget>[];

                    addDetail(leftColumn, 'Segment', segment);
                    addDetail(leftColumn, 'Produkttyp', productType);
                    addDetail(leftColumn, 'Artikelnummer', articleNo);
                    addDetail(leftColumn, 'Charge / LOT', batch);
                    addDetail(leftColumn, 'Seriennummer', serial);
                    addDetail(leftColumn, 'Menge', qty);

                    addDetail(rightColumn, 'Produkte zurückgeschickt?', returned);
                    addDetail(rightColumn, 'Am Patienten angewendet?', applied);
                    addDetail(rightColumn, 'Verletzung?', injury);

                    addDetail(bottomSection, 'Verletzungsbeschreibung', injuryDesc,
                        maxLines: 6);
                    addDetail(bottomSection, 'Fehler / Beschreibung', desc,
                        maxLines: 6);
                    addDetail(bottomSection, 'Grund / Ursache', reason,
                        maxLines: 4);
                    addDetail(bottomSection, 'Wunsch des Kunden', customerWish,
                        maxLines: 3);

                    final hasDetails = leftColumn.isNotEmpty ||
                        rightColumn.isNotEmpty ||
                        bottomSection.isNotEmpty;

                    if (!hasDetails) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Details der Reklamation',
                            style: textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Keine zusätzlichen Angaben vorhanden.',
                            style: textTheme.bodyMedium?.copyWith(
                              color:
                                  colorScheme.onSurfaceVariant.withOpacity(0.72),
                            ),
                          ),
                        ],
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Details der Reklamation',
                          style: textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        if (useTwoColumns &&
                            (leftColumn.isNotEmpty || rightColumn.isNotEmpty))
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (leftColumn.isNotEmpty)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: spaced(leftColumn),
                                  ),
                                ),
                              if (leftColumn.isNotEmpty &&
                                  rightColumn.isNotEmpty)
                                const SizedBox(width: 24),
                              if (rightColumn.isNotEmpty)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: spaced(rightColumn),
                                  ),
                                ),
                            ],
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ...spaced(leftColumn),
                              if (leftColumn.isNotEmpty &&
                                  rightColumn.isNotEmpty)
                                const Divider(height: 24),
                              ...spaced(rightColumn),
                            ],
                          ),
                        if (bottomSection.isNotEmpty &&
                            (leftColumn.isNotEmpty || rightColumn.isNotEmpty))
                          const Divider(height: 28),
                        if (bottomSection.isNotEmpty)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: spaced(bottomSection),
                          ),
                        if (attachments.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Text(
                            'Anhänge',
                            style: textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          ...attachments.map(
                            (upload) => _AdminAttachmentPreviewTile(
                              upload: upload,
                              formatBytes: _formatBytes,
                              formatDate: (dt) => _fmtDateTime(dt),
                              fallbackName: 'Unbenannte Datei',
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),

              // ====== Editor-Bereich (unverändert inhaltlich) ======                        
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isNarrow) ...[
                    DropdownButtonFormField<int>(
                      value: currentStatus,
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
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
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
                      onChanged: (v) => setState(() => _decision = (v == null || v.isEmpty) ? null : v),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _saveStatusDecision,
                        child: const Text('Speichern'),
                      ),
                    ),
                  ] else
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: currentStatus,
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
      },
    );
  }
}

class _AdminAttachmentPreviewTile extends StatefulWidget {
  final ComplaintUpload upload;
  final String Function(int size) formatBytes;
  final String Function(DateTime date) formatDate;
  final String fallbackName;

  const _AdminAttachmentPreviewTile({
    required this.upload,
    required this.formatBytes,
    required this.formatDate,
    required this.fallbackName,
  });

  @override
  State<_AdminAttachmentPreviewTile> createState() => _AdminAttachmentPreviewTileState();
}

class _AdminAttachmentPreviewTileState extends State<_AdminAttachmentPreviewTile> {
  bool _expanded = false;
  Uint8List? _previewBytes;
  ImageProvider<Object>? _previewProvider;

  bool get _hasPreview => _previewProvider != null;

  @override
  void initState() {
    super.initState();
    _previewProvider = _createPreviewProvider(widget.upload);
  }

  @override
  void didUpdateWidget(covariant _AdminAttachmentPreviewTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.upload.preview != widget.upload.preview ||
        oldWidget.upload.url != widget.upload.url ||
        oldWidget.upload.downloadUrl != widget.upload.downloadUrl) {
      final next = _createPreviewProvider(widget.upload);
      setState(() {
        _previewProvider = next;
        if (!_hasPreview) _expanded = false;
      });
    }
  }

  ImageProvider<Object>? _createPreviewProvider(ComplaintUpload upload) {
    _previewBytes = null;
    final preview = upload.preview;
    if (preview != null && preview.isNotEmpty && upload.isImage) {
      try {
        _previewBytes = base64Decode(preview);
        return MemoryImage(_previewBytes!);
      } catch (_) {
        _previewBytes = null;
      }
    }
    final remote = upload.imageUrl;
    if (remote != null && remote.isNotEmpty) {
      return NetworkImage(remote);
    }
    return null;
  }

  void _toggle() {
    if (!_hasPreview) return;
    setState(() => _expanded = !_expanded);
  }

  Future<void> _showLargePreview() async {
    if (!_hasPreview) return;
    final upload = widget.upload;
    final theme = Theme.of(context);
    final name = upload.name.trim().isEmpty ? widget.fallbackName : upload.name.trim();
    final meta = <String>[];
    if (upload.size > 0) meta.add(widget.formatBytes(upload.size));
    if (upload.uploadedAt != null) meta.add(widget.formatDate(upload.uploadedAt!.toLocal()));
    final media = MediaQuery.of(context);
    double dialogWidth = media.size.width * 0.9;
    double dialogHeight = media.size.height * 0.9;
    if (dialogWidth > 640) dialogWidth = 640;
    if (dialogHeight > 720) dialogHeight = 720;

    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: dialogWidth,
          height: dialogHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (meta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(meta.join(' • '), style: theme.textTheme.bodySmall),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceVariant,
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 5,
                        child: Center(
                          child: Image(
                            image: _previewProvider!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 12, 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Schließen'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final upload = widget.upload;
    final theme = Theme.of(context);
    final name = upload.name.trim().isEmpty ? widget.fallbackName : upload.name.trim();
    final meta = <String>[];
    if (upload.size > 0) meta.add(widget.formatBytes(upload.size));
    if (upload.uploadedAt != null) meta.add(widget.formatDate(upload.uploadedAt!.toLocal()));
    const double previewWidth = 220;
    const double previewHeight = 165;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _hasPreview ? _toggle : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  upload.isImage ? Icons.image_outlined : Icons.attachment_outlined,
                  size: 18,
                  color: _hasPreview ? theme.colorScheme.primary : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (meta.isNotEmpty)
                        Text(
                          meta.join(' • '),
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (_hasPreview)
                  Icon(
                    _expanded ? Icons.expand_less : Icons.visibility_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
          ),
          if (_hasPreview && _expanded) ...[
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 6),
              child: GestureDetector(
                onTap: _showLargePreview,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                      color: theme.colorScheme.surfaceVariant,
                    ),
                    width: previewWidth,
                    height: previewHeight,
                    child: Image(image: _previewProvider!, fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _showLargePreview,
                  icon: const Icon(Icons.open_in_full),
                  label: const Text('Größere Ansicht'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ===================================================================
// Admin API – http-basiert (kein dart:html HttpRequest mehr)
// ===================================================================
class AdminApi {
  AdminApi({this.onNewsChanged});

  final VoidCallback? onNewsChanged;
  String _secret = '';
  void setSecret(String s) => _secret = s;

  String get baseUrl {
    const b = String.fromEnvironment('API_BASE', defaultValue: '');
    if (b.isNotEmpty) return b;
    if (kIsWeb) {
      try {
        return html.window.location.origin;
      } catch (_) {}
    }
    // Mobile/Desktop-Fallback
    return 'https://dfs-complaints-backend.vercel.app';
  }

  Map<String, String> _headersJson() => {
        'Content-Type': 'application/json; charset=utf-8',
        if (_secret.isNotEmpty) 'X-Admin-Secret': _secret,
      };

  Uri _u(String path, [Map<String, String>? q]) {
    final uri = Uri.parse('$baseUrl$path');
    return (q == null || q.isEmpty) ? uri : uri.replace(queryParameters: q);
  }

  Future<_Resp> _request(
    String method,
    String path, {
    Map<String, String>? q,
    Object? body,
  }) async {
    final uri = _u(path, q);
    final hdrs = _headersJson();

    String? payload;
    if (body != null) {
      payload = body is String ? body : jsonEncode(body);
    }

    http.Response r;
    switch (method.toUpperCase()) {
      case 'GET':
        r = await http.get(uri, headers: hdrs);
        break;
      case 'POST':
        r = await http.post(uri, headers: hdrs, body: payload);
        break;
      case 'PUT':
        r = await http.put(uri, headers: hdrs, body: payload);
        break;
      case 'PATCH':
        r = await http.patch(uri, headers: hdrs, body: payload);
        break;
      case 'DELETE':
        // Einige Endpunkte akzeptieren Body bei DELETE → unterstützt
        r = await http.delete(uri, headers: hdrs, body: payload);
        break;
      default:
        throw UnsupportedError('Unsupported method: $method');
    }

    return _Resp(
      r.statusCode,
      r.body,
      r.reasonPhrase ?? '',
      r.headers,
    );
  }

  // ---------------- Pending ----------------
  Future<List<PendingUser>> fetchPending() async {
    final res = await _request('GET', '/api/admin/pending');
    if (res.status != 200) throw 'pending GET: HTTP ${res.status} ${res.body}';
    final txt = res.body.trim();
    if (txt.isEmpty) return const <PendingUser>[];
    final List data = jsonDecode(txt);
    return data.map((e) => PendingUser.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<void> approvePending(String email, {String? lang}) async {
    final body = {'email': email, 'action': 'approve', if (lang != null) 'lang': lang};
    final res = await _request('POST', '/api/admin/pending', body: body);
    if (res.status != 200 && res.status != 204) {
      throw 'pending POST approve: HTTP ${res.status} ${res.body}';
    }
  }

  Future<void> createCustomerAdmin({
    required String company,
    required String contact,
    required String email,
    required String street,
    required String zip,
    required String city,
    required String country,
    String? countryCode,
    required String lang,
    String? firstName,
    String? lastName,
    String? phone,
    String? password,
    String? passwordMode,
  }) async {
    final body = <String, dynamic>{
      'company': company,
      'contact': contact,
      'email': email,
      'street': street,
      'zip': zip,
      'city': city,
      'country': country,
      if (countryCode != null && countryCode.isNotEmpty) 'countryCode': countryCode,
      if (firstName != null && firstName.isNotEmpty) 'firstName': firstName,
      if (lastName != null && lastName.isNotEmpty) 'lastName': lastName,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      'lang': lang,
    };
    if (password != null && password.isNotEmpty) {
      body['password'] = password;
    }
    if (passwordMode != null && passwordMode.isNotEmpty) {
      body['passwordMode'] = passwordMode;
    }

    final res = await _request('POST', '/api/admin/customers', body: body);
    if (res.status != 200 && res.status != 201 && res.status != 204) {
      throw 'admin customers POST: HTTP ${res.status} ${res.body}';
    }
  }

  // ---------------- Users ----------------
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
      throw 'users DELETE/POST(delete) failed: HTTP ${r3.status} ${r3.body}';
    }
  }

  Future<void> setUserRevoked(String email, bool revoked) async {
    final res = await _request('PATCH', '/api/admin/users', body: {'email': email, 'revoked': revoked});
    if (res.status != 200 && res.status != 204) {
      throw 'users PATCH revoke failed: HTTP ${res.status} ${res.body}';
    }
  }

  Future<List<ActiveUser>> fetchUsers() async {
    final res = await _request('GET', '/api/admin/users');
    if (res.status != 200) throw 'users GET: HTTP ${res.status} ${res.body}';
    final txt = res.body.trim();
    if (txt.isEmpty) return const <ActiveUser>[];
    final List data = jsonDecode(txt);
    return data.map((e) => ActiveUser.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  // ---------------- Complaints ----------------
  Future<List<AdminComplaint>> fetchComplaintsByEmailDetailed(String email) async {
    final res = await _request('GET', '/api/admin/complaints', q: {'email': email, 'details': '1'});
    if (res.status != 200) throw 'complaints email GET: HTTP ${res.status} ${res.body}';
    final List data = jsonDecode(res.body.isEmpty ? '[]' : res.body);
    return data.map((e) => AdminComplaint.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<List<AdminComplaint>> fetchOpenComplaints() async {
    final res = await _request('GET', '/api/admin/complaints', q: {'open': '1'});
    if (res.status != 200) throw 'open complaints GET: HTTP ${res.status} ${res.body}';
    final List data = jsonDecode(res.body.isEmpty ? '[]' : res.body);
    return data.map((e) => AdminComplaint.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<Map<String, dynamic>> fetchComplaintRawByTicket(String ticket) async {
    final res = await _request('GET', '/api/admin/complaints', q: {'ticket': ticket});
    if (res.status != 200) {
      throw 'complaint GET by ticket: HTTP ${res.status} ${res.body}';
    }
    return (res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body)) as Map<String, dynamic>;
  }

  Future<AdminComplaint> adminComplaintUpdate({
    required String ticket,
    int? status,
    String? decision,
    String? reportLink,
    String? internalNo,
    String? notes,
  }) async {
    final body = <String, dynamic>{'ticket': ticket};
    if (status != null) body['status'] = status;
    body['decision'] = decision ?? '';
    if (reportLink != null) body['reportLink'] = reportLink;
    if (internalNo != null) body['internalNo'] = internalNo;
    if (notes != null) body['notes'] = notes;

    final res = await _request('POST', '/api/admin/complaints', body: body);
    if (res.status != 200) {
      throw 'HTTP ${res.status} ${res.statusText} — ${res.body}';
    }
    final Map<String, dynamic> j = (res.body.trim().isEmpty) ? <String, dynamic>{} : jsonDecode(res.body);
    return AdminComplaint.fromJson(j);
  }

  Future<void> deleteComplaint(String ticket) async {
    // 1) DELETE ?ticket=...
    try {
      final r1 = await _request('DELETE', '/api/admin/complaints', q: {'ticket': ticket});
      if (r1.status == 200 || r1.status == 204) return;
    } catch (_) {}
    // 2) DELETE Body
    final r2 = await _request('DELETE', '/api/admin/complaints', body: {'ticket': ticket});
    if (r2.status != 200 && r2.status != 204) {
      throw 'HTTP ${r2.status} ${r2.statusText} — ${r2.body}';
    }
  }

  // ---------------- Representatives (Vertreter) ----------------
  Future<Rep> upsertRep({
    String? id,
    required String firstName,
    required String lastName,
    required String email,
    required String region,
  }) async {
    final body = {
      'action': 'upsert',
      if (id != null && id.isNotEmpty) 'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'region': region,
    };
    final res = await _request('POST', '/api/admin/reps', body: body);
    if (res.status != 200 && res.status != 201) {
      throw 'reps POST: HTTP ${res.status} ${res.body}';
    }
    final Map<String, dynamic> j = (res.body.trim().isEmpty) ? <String, dynamic>{} : jsonDecode(res.body);
    return Rep.fromJson(j);
  }

  Future<void> deleteRep(String id) async {
    try {
      final r1 = await _request('DELETE', '/api/admin/reps', q: {'id': id});
      if (r1.status == 200 || r1.status == 204) return;
    } catch (_) {}
    final r2 = await _request('DELETE', '/api/admin/reps', body: {'action': 'delete', 'id': id});
    if (r2.status != 200 && r2.status != 204) {
      throw 'reps DELETE: HTTP ${r2.status} ${r2.body}';
    }
  }

  Future<List<Rep>> fetchReps({bool includeCustomers = true}) async {
    final q = includeCustomers ? {'includeCustomers': '1'} : null;
    final res = await _request('GET', '/api/admin/reps', q: q);
    if (res.status != 200) {
      throw 'reps GET: HTTP ${res.status} ${res.body}';
    }
    final List data = jsonDecode(res.body.isEmpty ? '[]' : res.body);
    return data.map((e) => Rep.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<List<String>> assignCustomerToRep({required String repId, required String email}) async {
    final res = await _request('POST', '/api/admin/reps', body: {
      'action': 'assign',
      'repId': repId,
      'email': email,
    });
    if (res.status != 200) {
      throw 'reps assign: HTTP ${res.status} ${res.body}';
    }
    final Map<String, dynamic> j = (res.body.trim().isEmpty) ? <String, dynamic>{} : jsonDecode(res.body);
    final list = (j['customers'] is List) ? (j['customers'] as List) : const [];
    return List<String>.from(list.map((e) => e.toString()));
  }

  Future<List<String>> unassignCustomerFromRep({required String repId, required String email}) async {
    final res = await _request('POST', '/api/admin/reps', body: {
      'action': 'unassign',
      'repId': repId,
      'email': email,
    });
    if (res.status != 200) {
      throw 'reps unassign: HTTP ${res.status} ${res.body}';
    }
    final Map<String, dynamic> j = (res.body.trim().isEmpty) ? <String, dynamic>{} : jsonDecode(res.body);
    final list = (j['customers'] is List) ? (j['customers'] as List) : const [];
    return List<String>.from(list.map((e) => e.toString()));
  }

  Future<SystemHealthResult> fetchSystemHealth() async {
    final res = await _request('GET', '/api/admin/health');
    if (res.status != 200) {
      throw 'admin health GET: HTTP ${res.status} ${res.body}';
    }
    final txt = res.body.trim();
    final raw = txt.isEmpty ? <String, dynamic>{} : jsonDecode(txt);
    final map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    return SystemHealthResult.fromJson(map);
  }

  Future<List<CustomerNewsEntry>> fetchCustomerNewsEntries() async {
    final res = await _request('GET', '/api/admin/news');
    if (res.status != 200) {
      throw 'admin news GET: HTTP ${res.status} ${res.body}';
    }
    final txt = res.body.trim();
    dynamic data = txt.isEmpty ? const {} : jsonDecode(txt);
    if (data is Map && data['items'] is List) {
      data = data['items'];
    }
    final List list = data is List ? data : const [];
    return list
        .whereType<Map>()
        .map((e) => CustomerNewsEntry.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<CustomerNewsEntry> saveCustomerNews({
    String? id,
    required String title,
    required String summary,
    required String category,
    required bool pinned,
    required bool draft,
    required DateTime publishedAt,
    String? linkLabel,
    String? linkUrl,
  }) async {
    final body = <String, dynamic>{
      if (id != null && id.isNotEmpty) 'id': id,
      'title': title,
      'summary': summary,
      'category': category,
      'pinned': pinned,
      'draft': draft,
      'publishedAt': publishedAt.toUtc().toIso8601String(),
      if (linkLabel != null) 'linkLabel': linkLabel,
      if (linkUrl != null) 'linkUrl': linkUrl,
    };
    final res = await _request('POST', '/api/admin/news', body: body);
    if (res.status != 200) {
      throw 'admin news POST: HTTP ${res.status} ${res.body}';
    }
    final txt = res.body.trim();
    final Map<String, dynamic> j = txt.isEmpty ? <String, dynamic>{} : jsonDecode(txt);
    onNewsChanged?.call();
    return CustomerNewsEntry.fromJson(j);
  }

  Future<void> deleteCustomerNews(String id) async {
    final body = {'id': id};
    final res = await _request('DELETE', '/api/admin/news', body: body);
    if (res.status != 200 && res.status != 204) {
      throw 'admin news DELETE: HTTP ${res.status} ${res.body}';
    }
    onNewsChanged?.call();
  }
}

  // Kleiner interner Response-Wrapper (angleicht an das frühere HttpRequest-Handling)
class _Resp {
    final int status;
    final String body;
    final String statusText;
    final Map<String, String> headers;
    _Resp(this.status, this.body, this.statusText, this.headers);
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

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight.isFinite ? constraints.maxHeight : 0;
          final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 0;
          final dense = height > 0 && height < 190;
          final ultraCompact = height > 0 && height < 160 || width > 0 && width < 150;

          double adaptiveIcon() {
            if (ultraCompact) {
              final basis = height > 0 ? height * 0.32 : 40;
              return basis.clamp(34, 46).toDouble();
            }
            if (dense) {
              return widget.compact ? 44.0 : 50.0;
            }
            return widget.compact ? 48.0 : 56.0;
          }

          final iconSize = adaptiveIcon();
          final verticalPadding = ultraCompact ? 14.0 : (dense ? 16.0 : 20.0);
          final horizontalPadding = ultraCompact ? 14.0 : 18.0;
          final gap = ultraCompact ? 8.0 : (dense ? 11.0 : 14.0);
          final subtitleGap = ultraCompact ? 6.0 : 8.0;

          final textTheme = Theme.of(context).textTheme;
          final titleStyle = (textTheme.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(
            fontSize: ultraCompact ? 15.6 : (dense ? 16.4 : 17.0),
            fontWeight: FontWeight.w700,
            color: titleColor,
            height: 1.25,
            letterSpacing: 0.2,
          );
          final subtitleStyle = (textTheme.bodySmall ?? const TextStyle(fontSize: 13)).copyWith(
            color: subtitleColor,
            height: 1.28,
            fontSize: ultraCompact ? 12.2 : 13.0,
          );

          return AnimatedContainer(
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
                      color: isDark
                          ? cs.outlineVariant.withOpacity(0.35)
                          : cs.outlineVariant.withOpacity(0.25),
                    ),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: verticalPadding,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                      SizedBox(height: gap),
                      Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                      if ((widget.subtitle ?? '').isNotEmpty) ...[
                        SizedBox(height: subtitleGap),
                        Text(
                          widget.subtitle!,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: subtitleStyle,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
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
