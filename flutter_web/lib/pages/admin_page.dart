// lib/pages/admin_page.dart
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:markdown/markdown.dart' as md;
import '../api/client.dart';
import '../models/country.dart';
import '../models/complaint.dart' show ComplaintUpload;
import '../models/customer_news_entry.dart';
import '../models/dfs_product.dart';
import '../models/faq.dart';
import '../data/knowledge_base_data.dart';
import '../l10n/app_localizations.dart';
import '../services/dfs_product_service.dart';
import '../widgets/dialog_content_scroll.dart';
import '../widgets/legal_footer.dart';
import '../widgets/theme_action.dart' as w;
import '../utils/lang_utils.dart';
import 'admin_stats_page.dart';
import 'product_catalog_page.dart';
import 'admin_wiki_categories_page.dart';
import 'admin_wiki_articles_page.dart';
import 'rep_wiki_list_page.dart';

// ===================================================================
// Admin Page – mit Kachel-Menü (wie Kunden-Dashboard)
// ===================================================================
class AdminPage extends StatefulWidget {
  final ApiClient api;
  final void Function(Map<String, dynamic> meta)? onMetaUpdated;
  final _AdminView initialView;
  const AdminPage({super.key, required this.api, this.onMetaUpdated, this.initialView = _AdminView.menu});

  const AdminPage.wiki({super.key, required this.api, this.onMetaUpdated})
      : initialView = _AdminView.wiki;

  const AdminPage.wikiCategories({super.key, required this.api, this.onMetaUpdated})
      : initialView = _AdminView.wikiCategories;

  const AdminPage.wikiArticles({super.key, required this.api, this.onMetaUpdated})
      : initialView = _AdminView.wikiArticles;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

enum _AdminView {
  menu,
  all,
  pending,
  users,
  open,
  reps,
  news,
  products,
  faq,
  wiki,
  catalogs,
  systemHealth,
  activity,
  createCustomer,
  pushBroadcast,
  wikiCategories,
  wikiArticles,
}

enum _CustPasswordMode { adminSecret, generated }

String _internalNumberPrefix({DateTime? now}) {
  final date = now ?? DateTime.now();
  final yy = DateFormat('yy').format(date);
  return 'R820-${yy}_';
}

String _extractOrDefaultInternalPrefix(String value) {
  final trimmed = value.trim();
  if (trimmed.startsWith('R820-')) {
    final idx = trimmed.indexOf('_');
    if (idx >= 0) {
      return trimmed.substring(0, idx + 1);
    }
  }
  return _internalNumberPrefix();
}

void _guardInternalNumberPrefix(TextEditingController controller) {
  var adjusting = false;

  controller.addListener(() {
    if (adjusting) return;
    adjusting = true;

    final current = controller.text;
    final prefix = _extractOrDefaultInternalPrefix(current);

    final suffix = current.startsWith(prefix)
        ? current.substring(prefix.length)
        : current.replaceFirst(RegExp(r'^R820-\d{2}_?'), '');

    final enforced = '$prefix$suffix';

    if (enforced != current || controller.selection.baseOffset < prefix.length) {
      controller.value = TextEditingValue(
        text: enforced,
        selection: TextSelection.collapsed(offset: enforced.length),
      );
    }

    adjusting = false;
  });
}

String _ensureInternalNumberPrefix(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.startsWith('R820-')) return trimmed;
  return '${_internalNumberPrefix()}$trimmed';
}

class _AdminPageState extends State<AdminPage> {
  static const int _repReminderDefaultDelayDays = 4;
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
  bool _repRemindersBusy = false;
  String? _repRemindersErr;
  RepReminderReport? _repReminderReport;
  DateTime? _repReminderLastRun;
  String _userFilterQuery = '';
  String? _userFilterRepId;
  String _userFilterCompany = 'Alle Firmen';
  String _userFilterCountry = 'Alle Länder';


  // Vertreter-Form (persistente Felder)
  final _repFirstCtrl = TextEditingController();
  final _repLastCtrl  = TextEditingController();
  final _repMailCtrl  = TextEditingController();
  String _repRegion   = kRepRegions.first;
  String _repLang     = 'de';
  List<String> _repRegionOptions = List<String>.from(kRepRegions);
  bool _repBusy       = false;

  // Admin-Kundenanlage (Form-Felder)
  final _custCompanyCtrl   = TextEditingController();
  final _custFirstNameCtrl = TextEditingController();
  final _custLastNameCtrl  = TextEditingController();
  final _custEmailCtrl     = TextEditingController();
  final _custStreetCtrl    = TextEditingController();
  final _custZipCtrl       = TextEditingController();
  final _custCityCtrl      = TextEditingController();
  final _custPhoneCtrl     = TextEditingController();
  String _custLang        = 'de';
  late Country _custCountry;
  bool _custBusy          = false;
  String? _custErr;
  _CustPasswordMode _custPasswordMode = _CustPasswordMode.adminSecret;
  final _createCustomerFormKey = GlobalKey<FormState>();

  // Daten
  List<PendingUser> _pending = [];
  List<ActiveUser> _users = [];
  List<AdminComplaint> _allComplaints = [];
  List<AdminComplaint> _openComplaints = [];
  List<Rep> _reps = [];
  final Map<String, bool> _repAssignmentBusy = {};
  List<CustomerNewsEntry> _newsEntries = [];
  bool _newsLoading = false;
  String? _newsErr;

  // Artikelliste (CSV)
  final DfsProductService _productService = DfsProductService();
  List<DfsProduct> _products = [];
  Map<String, DfsProduct> _productIndex = {};
  bool _productsLoading = false;
  String? _productErr;

  // FAQ / Wissensdatenbank
  List<FaqCategory> _faqCategories = [];
  List<FaqEntry> _faqEntries = [];
  bool _faqLoading = false;
  bool _faqSeeding = false;
  String? _faqErr;
  String? _faqSeedErr;
  bool _faqShowInactive = true;
  String _faqAudienceFilter = 'both';
  String? _faqCategoryFilter;
  String _faqSearch = '';
  bool _faqShowCategories = true;

  // Email -> detaillierte Reklamationen (für Users/Pending)
  final Map<String, _ComplaintsResult> _complaints = {};

  // Firmenfilter (Offene Reklamationen)
  String _filterCompany = 'Alle Firmen';

  // Filter "Alle Reklamationen"
  String _allSearch = '';
  String _allCompanyFilter = 'Alle Firmen';
  String _allRepFilter = 'Alle Vertreter';
  String _allDecisionFilter = '';
  int? _allStatusFilter;
  String _allInternalFilter = 'Alle Nummern';
  bool _showAllFilters = false;
  bool _showBulkAssignAll = false;
  bool _showBulkAssignOpen = false;

  // Admin-Dashboard-Bearbeitung
  bool _menuEditMode = false;
  final Set<String> _archivedTileIds = <String>{};

  bool _navCollapsed = true;

  // Mehrfach-Zuordnung interne Nummer
  final Set<String> _selectedAllTickets = <String>{};
  final Set<String> _selectedOpenTickets = <String>{};
  final _bulkInternalAllCtrl = TextEditingController();
  final _bulkInternalOpenCtrl = TextEditingController();
  bool _bulkAssigningAll = false;
  bool _bulkAssigningOpen = false;

  bool _loadAllComplaints = false;

  static const _menuLayoutStorageKey = 'admin_menu_layout_v1';
  static const double _tileScaleMin = 0.6;
  static const double _tileScaleMax = 1.35;
  late final Map<String, String> _tileDefaultSection;
  late final Set<String> _menuTileIds;
  late List<_AdminMenuSectionState> _menuSections;
  double _menuTileScale = 1.0;

  static const double _sectionReorderHeight = 40;

  // Ansicht (Menü / Bereich)
  _AdminView _view = _AdminView.menu;

  Country get _defaultCountry => kCountries.firstWhere(
        (c) => c.code == 'DE',
        orElse: () => kCountries.first,
      );

  static const Map<String, String> _newsCategoryLabels = {
    'catalogs': 'Kataloge',
    'technical': 'Technik',
    'regulatory': 'Regulatorik',
    'product': 'Produkte',
    'shortage': 'Einschränkungen',
    'app': 'App-Versionen',
    'general': 'Allgemein',
  };

  String _langLabel(String code) => deeplLangLabel(code);

  String _newsCategoryLabel(String code) {
    final key = code.trim().toLowerCase();
    return _newsCategoryLabels[key] ?? _newsCategoryLabels['general']!;
  }

  // ---- Katalog-Konfig (4 Felder) ----
  final _labDefaultCtrl  = TextEditingController();
  final _labEsfrCtrl     = TextEditingController();
  final _dentDefaultCtrl = TextEditingController();
  final _dentEsfrCtrl    = TextEditingController();

  bool _catCfgBusy = false;
  String? _catCfgErr;

  // Push-Broadcast
  final _pushTitleCtrl = TextEditingController();
  final _pushBodyCtrl = TextEditingController();
  final _pushLinkCtrl = TextEditingController();
  bool _pushBusy = false;
  String? _pushErr;
  AdminPushBroadcastResult? _pushResult;

  // Aktivitäts-Check (Kunden & Vertreter)
  final _activityEmailCtrl = TextEditingController();
  String _activityKind = 'customer';
  String? _activitySelectedEmail;
  _ActivitySnapshot? _activity;
  bool _activityLoading = false;
  String? _activityErr;

  String _stripPdfsPrefix(String? v) {
    if (v == null) return '';
    var s = v.trim();
    if (s.startsWith('pdfs/')) {
      s = s.substring(5);
    }
    if (s.toLowerCase().endsWith('.pdf')) {
      s = s.substring(0, s.length - 4);
    }
    return s;
  }

  String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    final iso = local.toIso8601String();
    final trimmed = iso.contains('.') ? iso.split('.').first : iso;
    return trimmed.replaceFirst('T', ' ');
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
    _createCustomerFormKey.currentState?.reset();

    if (!mounted) {
      _custLang = 'de';
      _custCountry = _defaultCountry;
      _custErr = null;
      _custPasswordMode = _CustPasswordMode.adminSecret;
      return;
    }

    setState(() {
      _custLang = 'de';
      _custCountry = _defaultCountry;
      _custErr = null;
      _custPasswordMode = _CustPasswordMode.adminSecret;
    });
  }

  @override
  void initState() {
    super.initState();
    _api = AdminApi(onNewsChanged: widget.api.clearCustomerNewsCache);
    _custCountry = _defaultCountry;
    _bulkInternalAllCtrl.text = _internalNumberPrefix();
    _bulkInternalOpenCtrl.text = _internalNumberPrefix();
    _guardInternalNumberPrefix(_bulkInternalAllCtrl);
    _guardInternalNumberPrefix(_bulkInternalOpenCtrl);

    // Secret zuerst aus der API (wenn über Admin-Button gekommen),
    // sonst aus LocalStorage (dfs_admin).
    String secret = widget.api.adminSecret ?? '';
    if (secret.isEmpty) {
      secret = html.window.localStorage['dfs_admin'] ?? '';
    }
    _api.setSecret(secret);

    _initMenuLayout();
    _view = widget.initialView;

    if (secret.isEmpty) {
      _fatalErr =
          'Kein Admin-Secret gefunden. Bitte den Adminbereich über den Start-Button öffnen '
          'oder im Browser-Storage dfs_admin setzen.';
      return;
    }

    _refreshAll();
    _refreshAllComplaints();
    _refreshOpen();
    _refreshReps();
    _loadCatalogConfigAdmin();
    _loadProducts();
    _refreshFaq();
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
    _labDefaultCtrl.dispose();
    _labEsfrCtrl.dispose();
    _dentDefaultCtrl.dispose();
    _dentEsfrCtrl.dispose();
    _pushTitleCtrl.dispose();
    _pushBodyCtrl.dispose();
    _pushLinkCtrl.dispose();
    _activityEmailCtrl.dispose();
    _bulkInternalAllCtrl.dispose();
    _bulkInternalOpenCtrl.dispose();
    super.dispose();
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
          orElse: () => Rep(id: '', firstName: '', lastName: '', email: '', region: '', lang: 'de', customers: const []),
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

  String? _repIdForEmail(String email) {
    final normalized = email.trim().toLowerCase();
    for (final r in _reps) {
      for (final c in r.customers) {
        if (c.trim().toLowerCase() == normalized) {
          return r.id;
        }
      }
    }
    return null;
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

  void _updateRepCustomers(String repId, List<String> customers) {
    setState(() {
      final idx = _reps.indexWhere((r) => r.id == repId);
      if (idx >= 0) {
        final r = _reps[idx];
        _reps[idx] = Rep(
          id: r.id,
          firstName: r.firstName,
          lastName: r.lastName,
          email: r.email,
          region: r.region,
          lang: r.lang,
          customers: customers,
        );
      }
    });
  }

  bool _isRepAssignmentBusy(String email) {
    return _repAssignmentBusy[email.trim().toLowerCase()] ?? false;
  }

  void _setRepAssignmentBusy(String email, bool value) {
    setState(() {
      _repAssignmentBusy[email.trim().toLowerCase()] = value;
    });
  }

  Future<void> _changeUserRep({required String email, String? repId}) async {
    final targetRepId = (repId ?? '').trim();
    final currentRepId = (_repIdForEmail(email) ?? '').trim();

    if (currentRepId == targetRepId) return;

    _setRepAssignmentBusy(email, true);
    try {
      if (targetRepId.isEmpty) {
        if (currentRepId.isEmpty) return;
        final customers = await _api.unassignCustomerFromRep(
          repId: currentRepId,
          email: email,
        );
        _updateRepCustomers(currentRepId, customers);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Vertreter entfernt für ${_companyByEmail(email) ?? email}.')),
        );
        return;
      }

      if (currentRepId.isNotEmpty && currentRepId != targetRepId) {
        final customers = await _api.unassignCustomerFromRep(
          repId: currentRepId,
          email: email,
        );
        _updateRepCustomers(currentRepId, customers);
      }

      final customers = await _api.assignCustomerToRep(
        repId: targetRepId,
        email: email,
      );
      _updateRepCustomers(targetRepId, customers);

      if (!mounted) return;
      final rep = _reps.firstWhere(
        (r) => r.id == targetRepId,
        orElse: () => Rep(
          id: targetRepId,
          firstName: '',
          lastName: '',
          email: '',
          region: '',
          lang: 'de',
          customers: const [],
        ),
      );
      final label = rep.displayName.isNotEmpty ? rep.displayName : targetRepId;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunde wurde ${label} zugewiesen.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler bei Vertreterzuordnung: $e')),
      );
    } finally {
      _setRepAssignmentBusy(email, false);
    }
  }

  String _repLabelForComplaint(AdminComplaint c) {
    final id = (c.repId ?? '').trim();
    final assigned = _repNameForEmail(c.email);
    final fromId = _reps.firstWhere(
      (r) => r.id.trim().toLowerCase() == id.toLowerCase(),
      orElse: () => Rep(
        id: '',
        firstName: '',
        lastName: '',
        email: '',
        region: '',
        lang: '',
        customers: const [],
      ),
    );

    if (fromId.id.isNotEmpty) return fromId.displayName;
    if (assigned != null && assigned.trim().isNotEmpty) return assigned.trim();
    if (id.isNotEmpty) return id;
    return 'Ohne Vertreter';
  }

  Color _statusColor(int status) {
    switch (status) {
      case 1:
        return const Color(0xFF1565C0);
      case 2:
        return const Color(0xFF6A1B9A);
      case 3:
        return const Color(0xFFEF6C00);
      case 4:
        return const Color(0xFF00897B);
      case 5:
        return const Color(0xFF2E7D32);
      default:
        return Colors.grey.shade700;
    }
  }

  String _labelForStatus(int s) {
    switch (s) {
      case 1:
        return 'Eingegangen';
      case 2:
        return 'In Bearbeitung';
      case 3:
        return 'Rückfrage erforderlich';
      case 4:
        return 'In Nacharbeit';
      case 5:
        return 'Abgeschlossen';
      default:
        return 'Unbekannt';
    }
  }

  String _labelForDecision(String? d) {
    switch ((d ?? '').trim()) {
      case 'accepted':
        return 'Angenommen';
      case 'rejected':
        return 'Abgelehnt';
      case '':
        return '—';
      default:
        return d!.trim();
    }
  }

  Color _decisionColor(String? d) {
    final v = (d ?? '').trim();
    if (v == 'accepted') return const Color(0xFF1B5E20);
    if (v == 'rejected') return const Color(0xFFB71C1C);
    return Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black54;
  }

  String _fmtDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
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
        _syncActivitySelection();
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
      setState(() {
        _openComplaints = list;
        _selectedOpenTickets.removeWhere(
          (ticket) => !_openComplaints.any((c) => c.ticket == ticket),
        );
      });
    } catch (e) {
      setState(() => _err = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _loadOpen = false);
    }
  }

  Future<void> _refreshAllComplaints() async {
    setState(() {
      _err = null;
      _loadAllComplaints = true;
    });
    try {
      final list = await _api.fetchAllComplaints();
      if (!mounted) return;
      setState(() {
        _allComplaints = list;
        _selectedAllTickets.removeWhere(
          (ticket) => !_allComplaints.any((c) => c.ticket == ticket),
        );
      });
    } catch (e) {
      setState(() => _err = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _loadAllComplaints = false);
    }
  }

  Future<void> _loadProducts() async {
    setState(() {
      _productsLoading = true;
      _productErr = null;
    });

    try {
      final list = await _productService.loadProducts();
      if (!mounted) return;
      setState(() => _applyProducts(list));
    } catch (e) {
      setState(() => _productErr = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _productsLoading = false);
    }
  }

  void _applyProducts(List<DfsProduct> list) {
    _products = List.unmodifiable(list);
    _productIndex = {
      for (final p in _products)
        if (p.articleNumber.trim().isNotEmpty) p.articleNumber.trim(): p,
    };
  }

  DfsProduct? _productByArticle(String? article) {
    final key = (article ?? '').trim();
    if (key.isEmpty) return null;
    return _productIndex[key];
  }

  void _syncComplaint(AdminComplaint updated) {
    setState(() {
      final allIdx = _allComplaints.indexWhere((c) => c.ticket == updated.ticket);
      if (allIdx != -1) {
        _allComplaints[allIdx] = updated;
      }

      final openIdx = _openComplaints.indexWhere((c) => c.ticket == updated.ticket);
      if (openIdx != -1) {
        _openComplaints[openIdx] = updated;
      }
    });
  }

  void _toggleTicketSelection(String ticket, bool selected, {required bool isOpenList}) {
    setState(() {
      final set = isOpenList ? _selectedOpenTickets : _selectedAllTickets;
      if (selected) {
        set.add(ticket);
      } else {
        set.remove(ticket);
      }
    });
  }

  void _clearTicketSelection({required bool isOpenList}) {
    setState(() {
      (isOpenList ? _selectedOpenTickets : _selectedAllTickets).clear();
    });
  }

  Future<void> _assignInternalNoBulk({required bool isOpenList}) async {
    final controller = isOpenList ? _bulkInternalOpenCtrl : _bulkInternalAllCtrl;
    final selected = isOpenList ? _selectedOpenTickets : _selectedAllTickets;
    final rawInternal = controller.text.trim();
    final internal = _ensureInternalNumberPrefix(rawInternal);

    if (internal.isEmpty || internal == _internalNumberPrefix()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte interne Nummer eingeben.')),
      );
      return;
    }

    controller.text = internal;

    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte mindestens ein Ticket auswählen.')),
      );
      return;
    }

    setState(() {
      if (isOpenList) {
        _bulkAssigningOpen = true;
      } else {
        _bulkAssigningAll = true;
      }
    });

    final tickets = List<String>.from(selected);
    var success = 0;

    try {
      for (final t in tickets) {
        final updated = await _api.adminComplaintUpdate(ticket: t, internalNo: internal);
        _syncComplaint(updated);
        success++;
      }

      if (!mounted) return;
      setState(() {
        selected.clear();
      });

      if (mounted) {
        final suffix = success == 1 ? '' : 's';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Interne Nummer bei $success Ticket$suffix gesetzt.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          if (isOpenList) {
            _bulkAssigningOpen = false;
          } else {
            _bulkAssigningAll = false;
          }
        });
      }
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
      if (!mounted) return;
      setState(() => _newsErr = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _newsLoading = false);
    }
  }

  String _faqAudienceLabel(String code) {
    switch (code) {
      case 'customer':
        return 'Nur Kunden';
      case 'rep':
        return 'Nur Reps';
      default:
        return 'Kunden & Reps';
    }
  }

  String _faqCategoryName(String id) {
    final lang = normalizeLangCode(Localizations.localeOf(context).languageCode);
    final found = _faqCategories.firstWhere(
      (c) => c.id == id,
      orElse: () => const FaqCategory(id: '', title: ''),
    );
    final title = found.localizedTitle(lang);
    return title.isEmpty ? 'Unbekannte Kategorie' : title;
  }

  String _legacyCategoryId(KnowledgeCategory cat) =>
      'legacy_${knowledgeCategoryCode(cat)}';

  Future<void> _seedFaqFromLegacyKnowledgeBase() async {
    if (_faqSeeding) return;
    final t = AppLocalizations.of(context);
    if (t == null) return;

    setState(() {
      _faqSeeding = true;
      _faqSeedErr = null;
    });

    try {
      final Map<KnowledgeCategory, FaqCategory> createdCats = {};
      for (final cat in KnowledgeCategory.values) {
        final saved = await _api.saveFaqCategory(
          id: _legacyCategoryId(cat),
          title: knowledgeCategoryLabel(cat, t),
          order: KnowledgeCategory.values.indexOf(cat),
          active: true,
        );
        createdCats[cat] = saved;
      }

      for (final item in knowledgeItems) {
        final cat = createdCats[item.category];
        if (cat == null) continue;
        await _api.saveFaqEntry(
          id: 'legacy_item_${item.id}',
          categoryId: cat.id,
          question: item.question(t),
          answer: item.answer(t),
          audience: 'both',
          order: item.id,
          active: true,
        );
      }

      await _refreshFaq();
    } catch (e) {
      if (!mounted) return;
      setState(() => _faqSeedErr = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _faqSeeding = false);
    }
  }

  Future<void> _refreshFaq() async {
    if (_faqLoading) return;
    setState(() {
      _faqLoading = true;
      _faqErr = null;
    });
    try {
      final data = await _api.fetchFaq();
      if (!mounted) return;
      setState(() {
        _faqCategories = data.categories;
        _faqEntries = data.entries;
        _faqErr = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _faqErr = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _faqLoading = false);
    }
  }

  Future<void> _sendPushBroadcast({bool dryRun = false}) async {
    if (_pushBusy) return;
    final title = _pushTitleCtrl.text.trim();
    final message = _pushBodyCtrl.text.trim();
    final actionUrl = _pushLinkCtrl.text.trim();

    if (title.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Titel und Nachricht ausfüllen.')),
      );
      return;
    }

    setState(() {
      _pushBusy = true;
      _pushErr = null;
    });

    try {
      final result = await _api.sendPushBroadcast(
        title: title,
        body: message,
        actionUrl: actionUrl.isEmpty ? null : actionUrl,
        dryRun: dryRun,
      );
      if (!mounted) return;
      setState(() => _pushResult = result);
      final text = dryRun
          ? 'Testlauf erfolgreich: ${result.totalTokens} Geräte gefunden.'
          : 'Push gesendet an ${result.totalTokens} Geräte.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _pushErr = e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Push-Versand: $e')),
      );
    } finally {
      if (mounted) setState(() => _pushBusy = false);
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
        _syncActivitySelection();
      });
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _loadReps = false);
    }
  }

  List<_ActivityChoice> _activityChoicesForKind(String kind) {
    if (kind == 'rep') {
      final reps = _reps
          .where((r) => r.email.trim().isNotEmpty)
          .map((r) {
            final name = '${r.firstName} ${r.lastName}'.trim();
            final label = name.isNotEmpty ? '$name (${r.email})' : r.email;
            return _ActivityChoice(r.email.trim(), label);
          })
          .toList();
      reps.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
      return reps;
    }

    final customers = _users
        .where((u) => u.email.trim().isNotEmpty)
        .map((u) {
          final parts = <String>[];
          if (u.company.trim().isNotEmpty) parts.add(u.company.trim());
          if (u.contact.trim().isNotEmpty) parts.add(u.contact.trim());
          parts.add(u.email.trim());
          return _ActivityChoice(u.email.trim(), parts.join(' • '));
        })
        .toList();
    customers.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return customers;
  }

  void _syncActivitySelection() {
    final options = _activityChoicesForKind(_activityKind);
    if (options.isEmpty) {
      _activitySelectedEmail = null;
      _activityEmailCtrl.clear();
      return;
    }

    final current = _activitySelectedEmail;
    if (current == null || !options.any((o) => o.email == current)) {
      _activitySelectedEmail = options.first.email;
      _activityEmailCtrl.text = _activitySelectedEmail!;
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

  Future<void> _runRepReminders() async {
    if (_repRemindersBusy) return;
    setState(() {
      _repRemindersBusy = true;
      _repRemindersErr = null;
    });
    try {
      final result = await _api.triggerRepReminders();
      if (!mounted) return;
      setState(() {
        _repReminderReport = result;
        _repReminderLastRun = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.remindersSent > 0
                ? 'Es wurden ${result.remindersSent} Erinnerungen verschickt.'
                : 'Keine Erinnerungen notwendig – alle Vertreter sind aktuell.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _repRemindersErr = '$e');
    } finally {
      if (mounted) setState(() => _repRemindersBusy = false);
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

  Future<void> _loadCatalogConfigAdmin() async {
    try {
      final m = await _api.fetchCatalogConfig();
      _labDefaultCtrl.text  = _stripPdfsPrefix(
        m['lab_default']  ?? 'pdfs/DFS-Labor-DE-US-2025-26_1.pdf',
      );
      _labEsfrCtrl.text     = _stripPdfsPrefix(
        m['lab_esfr']     ?? 'pdfs/DFS-Labor-ES-FR-2025-26_1.pdf',
      );
      _dentDefaultCtrl.text = _stripPdfsPrefix(
        m['dent_default'] ?? 'pdfs/DFS-Praxis-DE-US-2025-2026_1.pdf',
      );
      _dentEsfrCtrl.text    = _stripPdfsPrefix(
        m['dent_esfr']    ?? 'pdfs/DFS-Praxis-ES-FR-2025-2026_1.pdf',
      );
      if (mounted) setState(() {});
    } catch (e) {
      setState(() => _catCfgErr = e.toString());
    }
  }

  Future<void> _editAppMeta(BuildContext context) async {
    final theme = Theme.of(context);
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: vCtrl,
                decoration: const InputDecoration(
                  labelText: 'Version',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: bCtrl,
                decoration: const InputDecoration(
                  labelText: 'Build',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nCtrl,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Hinweise',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.science_outlined, color: theme.colorScheme.primary),
                title: const Text('Testmodus separat verwalten'),
                subtitle: const Text(
                  'Live/Test-Umschaltung und Routing liegen jetzt in der Kachel "Testmodus & Routing".',
                ),
              ),
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
      final version = vCtrl.text.trim();
      if (version.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Version erforderlich.')));
        }
        return;
      }

      final saved = await widget.api.setAppMeta(
        version: version,
        build: bCtrl.text.trim().isEmpty ? null : bCtrl.text.trim(),
        notes: nCtrl.text.trim(),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert.')));
      }

      // Aktualisierte Metadaten laden und an den Caller weiterreichen, damit das
      // TESTSYSTEM-Banner unmittelbar sichtbar wird, ohne dass ein Reload nötig ist.
      try {
        final refreshed = saved.isNotEmpty
            ? saved
            : await widget.api.getAppMeta(refresh: true) ?? <String, dynamic>{};
        if (refreshed.isNotEmpty) {
          widget.onMetaUpdated?.call(refreshed);
        }
      } catch (_) {}
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  Future<void> _editTestMode(BuildContext context) async {
    Map<String, dynamic>? meta;
    try { meta = await widget.api.getAppMeta(refresh: true); } catch (_) {}

    final testMailCtrl = TextEditingController(text: meta?['testEmail']?.toString() ?? '');
    final testPushCtrl = TextEditingController(
      text: (meta?['testPushTokens'] is List)
          ? (meta!['testPushTokens'] as List).join(', ')
          : '',
    );
    bool testMode = meta?['testMode'] == true;
    bool suppressMails = testMailCtrl.text.trim().isEmpty;
    bool suppressPush = testPushCtrl.text.trim().isEmpty;

    final version = meta?['version']?.toString().trim() ?? '';
    final build = meta?['build']?.toString() ?? '';
    final notes = meta?['notes']?.toString() ?? '';

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          final theme = Theme.of(ctx);
          Widget infoRow(IconData icon, String text) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Text(text)),
                ],
              ),
            );
          }

          return AlertDialog(
            title: const Text('Testmodus & Routing'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceVariant.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.shield_outlined, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              const Text('Sicherer Testmodus ohne Einfluss auf Live'),
                            ],
                          ),
                          const SizedBox(height: 8),
                          infoRow(Icons.verified_user_outlined,
                              'Produktive Daten und Live-Nutzer bleiben unverändert, auch wenn Tests aktiv sind.'),
                          infoRow(Icons.mark_email_unread_outlined,
                              'E-Mails werden je nach Einstellung unterdrückt oder nur an Testadressen zugestellt.'),
                          infoRow(Icons.wifi_tethering_outlined,
                              'Push-Mitteilungen erreichen ausschließlich freigegebene Testgeräte.'),
                          infoRow(Icons.label_important_outline,
                              'Alle Testfälle werden gekennzeichnet und nicht für produktive Analysen verwendet.'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      value: testMode,
                      onChanged: (v) => setStateDialog(() => testMode = v),
                      title: const Text('System im Testmodus'),
                      subtitle: const Text('Zeigt TESTSYSTEM-Banner und aktiviert isoliertes Routing.'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const Divider(height: 18),
                    Text('Mails im Testmodus', style: theme.textTheme.titleMedium),
                    CheckboxListTile(
                      value: suppressMails,
                      onChanged: (v) {
                        setStateDialog(() {
                          suppressMails = v ?? false;
                          if (suppressMails) testMailCtrl.clear();
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Keine produktiven Mails versenden'),
                      subtitle: const Text('Unterdrückt alle E-Mails, sofern keine Testadresse gesetzt ist.'),
                    ),
                    TextField(
                      controller: testMailCtrl,
                      enabled: !suppressMails,
                      decoration: const InputDecoration(
                        labelText: 'Test-Mailadresse',
                        hintText: 'z. B. qa@example.com',
                        helperText: 'Leer lassen, um alle Mails während des Tests zu blockieren.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Push im Testmodus', style: theme.textTheme.titleMedium),
                    CheckboxListTile(
                      value: suppressPush,
                      onChanged: (v) {
                        setStateDialog(() {
                          suppressPush = v ?? false;
                          if (suppressPush) testPushCtrl.clear();
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Push-Benachrichtigungen unterdrücken'),
                      subtitle: const Text('Ohne Tokens werden keine realen Geräte erreicht.'),
                    ),
                    TextField(
                      controller: testPushCtrl,
                      enabled: !suppressPush,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Erlaubte Testgeräte (Tokens)',
                        hintText: 'Kommagetrennt oder Zeilen',
                        helperText: 'Nur hier angegebene Tokens dürfen Push-Nachrichten erhalten.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Speichern')),
            ],
          );
        },
      ),
    );

    if (ok != true) return;

    if (version.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bitte zuerst eine App-Version hinterlegen.')),
        );
      }
      return;
    }

    try {
      final saved = await widget.api.setAppMeta(
        version: version,
        build: build.trim().isEmpty ? null : build.trim(),
        notes: notes.trim().isEmpty ? null : notes.trim(),
        testMode: testMode,
        testEmail: suppressMails ? '' : testMailCtrl.text.trim(),
        testPushTokens: suppressPush
            ? <String>[]
            : testPushCtrl.text
                .split(RegExp('[,\n]'))
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert.')));
      }

      try {
        final refreshed = saved.isNotEmpty
            ? saved
            : await widget.api.getAppMeta(refresh: true) ?? <String, dynamic>{};
        if (refreshed.isNotEmpty) {
          widget.onMetaUpdated?.call(refreshed);
        }
      } catch (_) {}
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
                        decoration: const InputDecoration(
                          labelText: 'Link-Beschriftung (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: linkUrlCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Link-URL (https:// …)',
                          border: OutlineInputBorder(),
                        ),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Titel und Beschreibung werden benötigt.')));
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

  // ---------------------------------------------
  // Kataloge – Panel
  // ---------------------------------------------
  Widget _buildCatalogsPanel() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final formKey = GlobalKey<FormState>();

    String? _validate(String v) {
      final s = v.trim();
      if (s.isEmpty) return 'Bitte Dateinamen angeben.';
      if (s.contains('/') || s.contains('\\')) {
        return 'Bitte nur den Dateinamen ohne Pfad eingeben (ohne „pdfs/“).';
      }
      return null;
    }

    String _ensurePdf(String name) {
      final n = name.trim();
      if (n.isEmpty) return n;
      return n.toLowerCase().endsWith('.pdf') ? n : '$n.pdf';
    }

    InputDecoration _dec(String label, {String? hint}) => InputDecoration(
      labelText: label.isEmpty ? null : label,
      hintText: hint,
      prefixText: 'pdfs/',
      suffixText: '.pdf',
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );

    TextStyle _sectionTitle() => theme.textTheme.titleMedium!.copyWith(
        fontWeight: FontWeight.w700,
      );

    TextStyle _sectionSubtitle() =>
        theme.textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant);
  
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------- Kopfzeile ----------
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      cs.primary.withOpacity(0.14),
                      cs.primary.withOpacity(0.05),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.menu_book_outlined, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Kataloge verwalten',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'PDF-Links für Labor- und Praxiskatalog zentral pflegen.',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Neu laden',
                      onPressed: _loadCatalogConfigAdmin,
                      icon: const Icon(Icons.refresh),
                    ),
                    const SizedBox(width: 4),
                    OutlinedButton.icon(
                      onPressed: () => html.window.open(
                        'https://www.dfs-diamon.de/de/user',
                        '_blank',
                      ),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Kataloge austauschen'),
                    ),
                    const SizedBox(width: 4),
                    FilledButton.icon(
                      onPressed: _catCfgBusy
                          ? null
                          : () async {
                              if (!(formKey.currentState?.validate() ?? false)) return;
                              setState(() {
                                _catCfgBusy = true;
                                _catCfgErr = null;
                              });
                              try {
                                await _api.updateCatalogConfig({
                                  'lab_default': 'pdfs/${_ensurePdf(_labDefaultCtrl.text)}',
                                  'lab_esfr':    'pdfs/${_ensurePdf(_labEsfrCtrl.text)}',
                                  'dent_default':'pdfs/${_ensurePdf(_dentDefaultCtrl.text)}',
                                  'dent_esfr':   'pdfs/${_ensurePdf(_dentEsfrCtrl.text)}',
                                });
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Katalog-Konfiguration gespeichert.'),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  setState(() => _catCfgErr = e.toString());
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => _catCfgBusy = false);
                                }
                              }
                            },
                      icon: _catCfgBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('Speichern'),
                    ),
                  ],
                ),
              ),

              if (_catCfgErr != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          size: 18, color: cs.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _catCfgErr!,
                          style: TextStyle(
                            color: cs.onErrorContainer,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // ---------- LABOR ----------
              Row(
                children: [
                  const Icon(Icons.science_outlined, size: 20),
                  const SizedBox(width: 6),
                  Text('Dentallabor (Lab)', style: _sectionTitle()),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Links für den Labor-Katalog – je nach Sprache werden passende PDFs geöffnet.',
                style: _sectionSubtitle(),
              ),
              const SizedBox(height: 10),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceVariant.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: cs.outlineVariant.withOpacity(0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DE / EN / IT (Standard)',
                            style: _sectionSubtitle(),
                          ),
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: _labDefaultCtrl,
                            decoration: _dec(
                              '',
                              hint: 'DFS-Labor-DE-US-2025-26_1',
                            ),
                            validator: (v) => _validate(v ?? ''),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ES / FR',
                            style: _sectionSubtitle(),
                          ),
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: _labEsfrCtrl,
                            decoration: _dec(
                              '',
                              hint: 'DFS-Labor-ES-FR-2025-26_1',
                            ),
                            validator: (v) => _validate(v ?? ''),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // ---------- PRAXIS ----------
              Row(
                children: [
                  const Icon(Icons.medical_services_outlined, size: 20),
                  const SizedBox(width: 6),
                  Text('Zahnmedizin (Dent)', style: _sectionTitle()),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Links für den Praxis-Katalog – analog zum Labor-Katalog.',
                style: _sectionSubtitle(),
              ),
              const SizedBox(height: 10),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceVariant.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: cs.outlineVariant.withOpacity(0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DE / EN / IT (Standard)',
                            style: _sectionSubtitle(),
                          ),
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: _dentDefaultCtrl,
                            decoration: _dec(
                              '',
                              hint: 'DFS-Praxis-DE-US-2025-2026_1',
                            ),
                            validator: (v) => _validate(v ?? ''),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ES / FR',
                            style: _sectionSubtitle(),
                          ),
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: _dentEsfrCtrl,
                            decoration: _dec(
                              '',
                              hint: 'DFS-Praxis-ES-FR-2025-2026_1',
                            ),
                            validator: (v) => _validate(v ?? ''),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceVariant.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Icon(Icons.info_outline, size: 18),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Die Kataloge werden immer aus dem Ordner „pdfs/“ im Webprojekt geladen. '
                        'Bitte hier nur den Dateinamen ohne Pfad eingeben; die App verwendet automatisch '
                        '„pdfs/<Dateiname>.pdf“.',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPushBroadcastPanel() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final result = _pushResult;
    final dateFmt = DateFormat('dd.MM.yyyy HH:mm');

    InputDecoration _dec(String label, {String? hint, Widget? prefix}) => InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: prefix,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          alignLabelWithHint: true,
        );

    Widget _buildResult(AdminPushBroadcastResult res) {
      final ts = dateFmt.format(res.timestamp.toLocal());
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            res.dryRun ? 'Letzter Testlauf ($ts)' : 'Letzter Versand ($ts)',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text('${res.totalTokens} registrierte Geräte in ${res.languages.length} Sprachgruppen.'),
          if (res.invalidTokens > 0) ...[
            const SizedBox(height: 6),
            Text('Ungültige Tokens bereinigt: ${res.invalidTokens}', style: TextStyle(color: cs.error)),
          ],
          if (res.languages.isEmpty) ...[
            const SizedBox(height: 12),
            const Text('Keine aktiven Push-Empfänger vorhanden.'),
          ] else ...[
            const SizedBox(height: 12),
            Column(
              children: res.languages
                  .map(
                    (entry) => Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: cs.outlineVariant),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(entry.lang.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Geräte: ${entry.tokens}'),
                                if (!res.dryRun)
                                  Text('Versendet: ${entry.sent}', style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                          Icon(
                            entry.ok ? Icons.check_circle_outline : Icons.error_outline,
                            color: entry.ok ? cs.primary : cs.error,
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (res.errors.isNotEmpty) ...[
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hinweise / Fehler:', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                for (final err in res.errors)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('• $err', style: TextStyle(color: cs.error)),
                  ),
              ],
            ),
          ],
        ],
      );
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final minHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : 0.0;
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            cs.secondaryContainer.withOpacity(0.5),
                            cs.surfaceVariant,
                          ],
                        ),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.notifications_active_outlined),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Push-Benachrichtigung versenden',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Sende eine einmalige Push-Nachricht an alle Kunden mit registrierten Geräten. '
                      'Nutze den Testlauf, um zunächst nur die Empfängerzahl zu prüfen.',
                    ),
                    const SizedBox(height: 16),
                  TextField(
                    controller: _pushTitleCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _dec('Titel', hint: 'z. B. Geplante Wartung am 18.06.'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pushBodyCtrl,
                    minLines: 4,
                    maxLines: 6,
                    decoration: _dec('Nachricht', hint: 'Kurzer Text für die Push-Mitteilung'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pushLinkCtrl,
                    decoration: _dec('Optionale Link-URL', hint: 'https://…'),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _pushBusy ? null : () => _sendPushBroadcast(dryRun: false),
                        icon: _pushBusy
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send_outlined),
                        label: const Text('Push senden'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _pushBusy ? null : () => _sendPushBroadcast(dryRun: true),
                        icon: const Icon(Icons.calculate_outlined),
                        label: const Text('Testlauf (nur zählen)'),
                      ),
                    ],
                  ),
                  if (_pushBusy) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                  if (_pushErr != null) ...[
                    const SizedBox(height: 12),
                    Text('Fehler: $_pushErr', style: TextStyle(color: cs.error)),
                  ],
                  if (result != null) ...[
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),
                    _buildResult(result),
                  ],
                ],
              ),
             ),
            );
          },
        ),
      ),
    );
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

    Widget buildRepReminderCard(bool compact) {
      final report = _repReminderReport;
      final entries = report?.reminders ?? const <RepReminderEntry>[];
      final delayDays = report?.delayDays ?? _repReminderDefaultDelayDays.toDouble();
      final delayLabel = delayDays % 1 == 0 ? delayDays.toInt().toString() : delayDays.toStringAsFixed(1);
      final lastRunLabel = _repReminderLastRun != null ? _formatTimestamp(_repReminderLastRun!) : null;
      final infoStyle = theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant);

      String summaryLine() {
        if (report == null) {
          return 'Hier können Erinnerungsmails an Vertreter ausgelöst werden.';
        }
        final count = report.remindersSent;
        final eligible = report.eligible;
        final suffix = count == 1 ? 'Erinnerung' : 'Erinnerungen';
        final eligibleLabel = eligible == 1 ? 'Fall' : 'Fälle';
        return count > 0
            ? 'Zuletzt wurden $count $suffix verschickt ($eligible überfällige $eligibleLabel).'
            : 'Zuletzt waren keine Erinnerungen notwendig ($eligible überfällige $eligibleLabel).';
      }

      Widget header() {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.mark_email_unread_outlined, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Vertreter erinnern',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sendet eine Erinnerungsmail an Vertreter, wenn nach $delayLabel Tagen noch keine Entscheidung '
                    'erfolgt ist (CC an complaint@dfs-diamon.de).',
                    style: infoStyle,
                  ),
                ],
              ),
            ),
          ],
        );
      }

      final reminderButton = FilledButton.icon(
        onPressed: _repRemindersBusy ? null : _runRepReminders,
        icon: _repRemindersBusy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.send_outlined),
        label: Text(_repRemindersBusy ? 'Läuft …' : 'Erinnerungen senden'),
      );

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: cs.surfaceVariant.withOpacity(0.5),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (compact) ...[
              header(),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: reminderButton,
              ),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: header()),
                  const SizedBox(width: 12),
                  reminderButton,
                ],
              ),
            ],
            const SizedBox(height: 12),
            Text(summaryLine(), style: theme.textTheme.bodyMedium),
            if (lastRunLabel != null) ...[
              const SizedBox(height: 4),
              Text('Letzter Lauf: $lastRunLabel', style: infoStyle),
            ],
            if (_repRemindersErr != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_repRemindersErr!, style: TextStyle(color: cs.onErrorContainer)),
              ),
            ],
            if (report != null && entries.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 20),
              ...entries.map(
                (entry) {
                  final langLabel = entry.lang.isEmpty ? '' : entry.lang.toUpperCase();
                  final repLabel = entry.repEmail.isEmpty ? entry.repId ?? '-' : entry.repEmail;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.chevron_right, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${entry.ticket} – $repLabel${langLabel.isEmpty ? '' : ' ($langLabel)'}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ] else if (!_repRemindersBusy && report == null) ...[
              const SizedBox(height: 12),
              Text(
                'Noch kein Erinnerungsdurchlauf gestartet.',
                style: infoStyle,
              ),
            ],
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final bool compact = maxWidth < 720;
        final double horizontalPadding = compact ? 12 : 24;
        final double maxContentWidth = maxWidth > 1100 ? 1020 : maxWidth;
        final EdgeInsets cardPadding = EdgeInsets.symmetric(
          horizontal: compact ? 16 : 24,
          vertical: compact ? 18 : 24,
        );

        final refreshButton = IconButton(
          tooltip: 'Neu laden',
          onPressed: _systemHealthBusy ? null : () => _loadSystemHealth(force: true),
          icon: const Icon(Icons.refresh),
        );

        Widget buildHeader() {
          final title = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: const [
              Icon(Icons.health_and_safety_outlined),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Systemstatus & Validierung',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: refreshButton),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: title),
              const SizedBox(width: 12),
              refreshButton,
            ],
          );
        }

        Widget buildChecks() {
          if (checks.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  status == null
                      ? (_systemHealthBusy ? 'Prüfung läuft …' : 'Noch kein System-Check gestartet.')
                      : 'Keine Check-Daten verfügbar.',
                ),
              ),
            );
          }

          return ListView.separated(
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemBuilder: (_, index) => _SystemHealthCheckCard(check: checks[index]),
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemCount: checks.length,
          );
        }

        return Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: EdgeInsets.fromLTRB(horizontalPadding, 16, horizontalPadding, 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: cardPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      buildHeader(),
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
                                  Text(summaryText,
                                      style: TextStyle(color: summaryFg, fontWeight: FontWeight.w600)),
                                  if (tsLabel != null) ...[
                                    const SizedBox(height: 4),
                                    Text('Stand: $tsLabel',
                                        style: TextStyle(color: summaryFg.withOpacity(0.9))),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      buildRepReminderCard(compact),
                      const SizedBox(height: 16),
                      buildChecks(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadActivity() async {
    final email = (_activitySelectedEmail ?? _activityEmailCtrl.text).trim();
    if (email.isEmpty) {
      setState(() {
        _activityErr = 'Bitte eine Auswahl treffen.';
        _activity = null;
      });
      return;
    }
    setState(() {
      _activityLoading = true;
      _activityErr = null;
    });
    try {
      final res = await widget.api.adminActivity(email: email, kind: _activityKind);
      if (res == null || res['found'] != true) {
        setState(() {
          _activity = null;
          _activityErr = 'Kein Datensatz gefunden.';
        });
      } else {
        setState(() {
          _activity = _ActivitySnapshot.fromJson(res);
          _activityErr = null;
        });
      }
    } catch (e) {
      setState(() {
        _activityErr = e.toString();
        _activity = null;
      });
    } finally {
      setState(() => _activityLoading = false);
    }
  }

  List<DropdownMenuItem<String>> _activityDropdownItems() {
    return _activityChoicesForKind(_activityKind)
        .map(
          (o) => DropdownMenuItem<String>(
            value: o.email,
            child: Text(o.label, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList();
  }

  Widget _buildActivityPanel() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final result = _activity;
    final activityItems = _activityDropdownItems();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.query_stats_outlined, color: cs.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Kunden-/Rep-Aktivitätsübersicht',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    value: _activityKind,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Typ',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'customer', child: Text('Kunde')),
                      DropdownMenuItem(value: 'rep', child: Text('Vertreter')),
                    ],
                    onChanged: (v) {
                      final nextKind = v ?? 'customer';
                      setState(() {
                        _activityKind = nextKind;
                        _activitySelectedEmail = null;
                        _activityEmailCtrl.clear();
                        final options = _activityChoicesForKind(nextKind);
                        if (options.isNotEmpty) {
                          _activitySelectedEmail = options.first.email;
                          _activityEmailCtrl.text = _activitySelectedEmail!;
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 360,
                  child: DropdownButtonFormField<String>(
                    value: _activitySelectedEmail,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: _activityKind == 'rep' ? 'Vertreter' : 'Kunde',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: activityItems,
                    onChanged: _activityLoading || activityItems.isEmpty
                        ? null
                        : (v) => setState(() {
                              _activitySelectedEmail = v;
                              _activityEmailCtrl.text = v ?? '';
                            }),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _activityLoading ? null : _loadActivity,
                  icon: _activityLoading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search),
                  label: Text(_activityLoading ? 'Lädt …' : 'Abrufen'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_activityLoading) const LinearProgressIndicator(),
            if (_activityErr != null) ...[
              const SizedBox(height: 8),
              Text('Fehler: $_activityErr', style: TextStyle(color: cs.error)),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: result == null
                  ? const Center(
                      child: Text('Eintrag auswählen und Abrufen klicken, um Aktivitätsdaten zu sehen.'),
                    )
                  : _buildActivityDetails(result, cs),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityDetails(_ActivitySnapshot data, ColorScheme cs) {
    String tsLabel(int? ts) {
      if (ts == null || ts <= 0) return 'Keine Daten';
      try {
        return _formatTimestamp(DateTime.fromMillisecondsSinceEpoch(ts));
      } catch (_) {
        return ts.toString();
      }
    }

    String pushLabel() {
      final base = data.pushValid ? 'Ja' : 'Nein';
      return data.pushUpdatedMs != null ? '$base – aktualisiert ${tsLabel(data.pushUpdatedMs)}' : base;
    }

    final stats = [
      _activityStatCard('Letzter Login', tsLabel(data.lastLoginMs), Icons.login_rounded, cs.primary),
      _activityStatCard(
        'Letzte Reklamation',
        data.lastComplaintTicket != null
            ? '${tsLabel(data.lastComplaintMs)} (Ticket ${data.lastComplaintTicket})'
            : tsLabel(data.lastComplaintMs),
        Icons.assignment_outlined,
        cs.secondary,
      ),
      _activityStatCard('Offene Tickets', data.openTickets.toString(), Icons.pending_actions_outlined, cs.tertiary),
      _activityStatCard(
        'Push-Token gültig?',
        '${pushLabel()} (${data.tokens} Token)',
        data.pushValid ? Icons.verified_user_outlined : Icons.error_outline,
        data.pushValid ? cs.primary : cs.error,
      ),
      _activityStatCard('App-Version', data.appVersionLabel, Icons.system_update_alt_outlined, cs.primary),
      _activityStatCard('Standort', data.locationLabel, Icons.location_on_outlined, cs.outline),
    ];

    final assignedCustomers = data.customerLabels;

    return ListView(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data.displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Chip(label: Text(data.kindLabel)),
                      Chip(label: Text(data.email)),
                      if (data.company.isNotEmpty) Chip(label: Text(data.company)),
                      if (data.contact.isNotEmpty) Chip(label: Text(data.contact)),
                      if (data.region.isNotEmpty) Chip(label: Text('Region ${data.region}')),
                      Chip(label: Text('${data.tokens} Push-Token')),
                      if (assignedCustomers.isNotEmpty)
                        Chip(label: Text('${assignedCustomers.length} zugewiesene Kunden')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: stats,
        ),
        if (data.isRep && assignedCustomers.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Zugeordnete Kunden (${assignedCustomers.length}):',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final label in assignedCustomers.take(20)) Chip(label: Text(label)),
              if (assignedCustomers.length > 20)
                Chip(label: Text('… ${assignedCustomers.length - 20} weitere')),
            ],
          ),
        ],
      ],
    );
  }

  Widget _activityStatCard(String title, String value, IconData icon, Color color) {
    final theme = Theme.of(context);
    return Container(
      width: 260,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateCustomerPanel() {
    String? _req(String v, String label) {
      if (v.trim().isEmpty) return '$label wird benötigt';
      return null;
    }

    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final bool compact = availableWidth < 720;
        final double horizontalPadding = compact ? 12 : 24;
        final double maxCardWidth = availableWidth > 980 ? 940 : availableWidth;
        final EdgeInsets cardPadding = EdgeInsets.symmetric(
          horizontal: compact ? 18 : 28,
          vertical: compact ? 20 : 26,
        );

        return Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: EdgeInsets.fromLTRB(horizontalPadding, 16, horizontalPadding, 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxCardWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 18 : 26,
                      vertical: compact ? 20 : 26,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.colorScheme.primaryContainer,
                          theme.colorScheme.primaryContainer.withOpacity(0.72),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: theme.colorScheme.primary,
                              child: const Icon(Icons.person_add_alt_1_outlined, color: Colors.white),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Neuen Kunden anlegen',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Erstelle strukturierte Kundenkonten mit klaren Abschnitten und hilfreichen Hinweisen. '
                                    'Alle Pflichtfelder sind mit einem Stern (*) markiert.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onPrimaryContainer.withOpacity(0.9),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_custBusy)
                              const Padding(
                                padding: EdgeInsets.only(left: 12),
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2.4),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: const [
                            _FeatureHighlight(icon: Icons.auto_fix_high_outlined, label: 'Automatische Begrüßungs-Mail'),
                            _FeatureHighlight(icon: Icons.security_outlined, label: 'Sichere Zugangsdaten'),
                            _FeatureHighlight(icon: Icons.event_available_outlined, label: 'Sofort einsatzbereit'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 2,
                    child: Container(
                      padding: cardPadding,
                      child: Form(
                        key: _createCustomerFormKey,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_custErr != null) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.errorContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _custErr!,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: theme.colorScheme.onErrorContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                            ],

                            _AdminFormSection(
                              icon: Icons.apartment_outlined,
                              title: 'Firmendaten',
                              description: 'Allgemeine Informationen zum Unternehmen.',
                              fields: [
                                _FieldConfig(
                                  preferredWidth: 380,
                                  child: TextFormField(
                                    controller: _custCompanyCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Firma *',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    validator: (v) => _req(v ?? '', 'Firma'),
                                  ),
                                ),
                                _FieldConfig(
                                  preferredWidth: 380,
                                  child: TextFormField(
                                    controller: _custEmailCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'E-Mail *',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    validator: (v) => _req(v ?? '', 'E-Mail'),
                                  ),
                                ),
                                _FieldConfig(
                                  preferredWidth: 240,
                                  child: DropdownButtonFormField<String>(
                                    value: _custLang,
                                    decoration: const InputDecoration(
                                      labelText: 'Sprache *',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    items: const [
                                      DropdownMenuItem(value: 'de', child: Text('Deutsch')),
                                      DropdownMenuItem(value: 'en', child: Text('Englisch')),
                                      DropdownMenuItem(value: 'fr', child: Text('Französisch')),
                                      DropdownMenuItem(value: 'it', child: Text('Italienisch')),
                                      DropdownMenuItem(value: 'es', child: Text('Spanisch')),
                                    ],
                                    onChanged: (v) => setState(() => _custLang = v ?? 'de'),
                                  ),
                                ),
                              ],
                            ),

                            _AdminFormSection(
                              icon: Icons.person_outline,
                              title: 'Ansprechpartner',
                              description: 'Persönliche Daten für den Kontakt.',
                              fields: [
                                _FieldConfig(
                                  preferredWidth: 260,
                                  child: TextFormField(
                                    controller: _custFirstNameCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Vorname *',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    validator: (v) => _req(v ?? '', 'Vorname'),
                                  ),
                                ),
                                _FieldConfig(
                                  preferredWidth: 260,
                                  child: TextFormField(
                                    controller: _custLastNameCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Nachname *',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    validator: (v) => _req(v ?? '', 'Nachname'),
                                  ),
                                ),
                                _FieldConfig(
                                  preferredWidth: 260,
                                  child: TextFormField(
                                    controller: _custPhoneCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Telefon (optional)',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            _AdminFormSection(
                              icon: Icons.map_outlined,
                              title: 'Adresse',
                              description: 'Standort des Kundenunternehmens.',
                              fields: [
                                _FieldConfig(
                                  preferredWidth: 480,
                                  child: TextFormField(
                                    controller: _custStreetCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Straße und Hausnummer *',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    validator: (v) => _req(v ?? '', 'Straße'),
                                  ),
                                ),
                                _FieldConfig(
                                  preferredWidth: 220,
                                  child: TextFormField(
                                    controller: _custZipCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'PLZ *',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    validator: (v) => _req(v ?? '', 'PLZ'),
                                  ),
                                ),
                                _FieldConfig(
                                  preferredWidth: 280,
                                  child: TextFormField(
                                    controller: _custCityCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Ort *',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    validator: (v) => _req(v ?? '', 'Ort'),
                                  ),
                                ),
                                _FieldConfig(
                                  preferredWidth: 320,
                                  child: DropdownButtonFormField<Country>(
                                    value: _custCountry,
                                    decoration: const InputDecoration(
                                      labelText: 'Land *',
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
                                      if (v == null) return;
                                      setState(() => _custCountry = v);
                                    },
                                    validator: (v) => v == null ? 'Land auswählen' : null,
                                  ),
                                ),
                              ],
                            ),

                            _AdminFormSection(
                              icon: Icons.lock_outline,
                              title: 'Startpasswort',
                              description: 'Steuert, ob das Admin-Passwort genutzt oder ein Systempasswort generiert wird.',
                              fields: [
                                _FieldConfig(
                                  preferredWidth: 420,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outline
                                                .withOpacity(0.5),
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            RadioListTile<_CustPasswordMode>(
                                              value: _CustPasswordMode.adminSecret,
                                              groupValue: _custPasswordMode,
                                              dense: true,
                                              title: const Text('Admin-Passwort verwenden'),
                                              subtitle: const Text(
                                                  'Keine Begrüßungsnachricht – Zugang nutzt das Admin-Passwort.'),
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
                                              subtitle: const Text(
                                                  'System erstellt ein 8-stelliges Passwort und verschickt es per E-Mail.'),
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
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 8),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.refresh_outlined),
                                  label: const Text('Formular zurücksetzen'),
                                  onPressed: _custBusy
                                      ? null
                                      : () {
                                          FocusScope.of(context).unfocus();
                                          _resetCustomerForm();
                                        },
                                ),
                                const Spacer(),
                                FilledButton.icon(
                                  icon: const Icon(Icons.save_outlined),
                                  label: const Text('Kundenaccount anlegen'),
                                  onPressed: _custBusy
                                      ? null
                                      : () async {
                                          final isValid =
                                              _createCustomerFormKey.currentState?.validate() ?? false;
                                          if (!isValid) {
                                            return;
                                          }
                                          FocusScope.of(context).unfocus();
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
                                              passwordMode:
                                                  _custPasswordMode == _CustPasswordMode.generated
                                                      ? 'generated'
                                                      : 'admin',
                                            );

                                            _resetCustomerForm();

                                            if (!mounted) {
                                              return;
                                            }

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
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
    final title = switch (_view) {
      _AdminView.menu           => 'Adminbereich – DFS Customer Complaint',
      _AdminView.all            => 'Alle Reklamationen',
      _AdminView.pending        => 'Pending (Freigabe ausstehend)',
      _AdminView.users          => 'Kundendatenbank',
      _AdminView.open           => 'Offene Reklamationen',
      _AdminView.reps           => 'Vertreterverwaltung',
      _AdminView.faq            => 'Wissensdatenbank (FAQ)',
      _AdminView.wiki           => 'Vertreter-Wiki',
      _AdminView.products       => 'Artikelliste',
      _AdminView.news           => 'Neuigkeiten & Infoscreen',
      _AdminView.catalogs       => 'Katalog-Konfiguration',
      _AdminView.systemHealth   => 'Systemstatus & Checks',
      _AdminView.createCustomer => 'Neuen Kunden anlegen',
      _AdminView.activity       => 'Aktivitätsübersicht',
      _AdminView.pushBroadcast  => 'Push-Benachrichtigungen',
      _AdminView.wikiCategories => 'Vertreter-Wiki Kategorien',
      _AdminView.wikiArticles   => 'Vertreter-Wiki Artikel',
    };

    return WillPopScope(
      onWillPop: () async {
        if (_view != _AdminView.menu) {
          setState(() => _view = _AdminView.menu);
          return false;
        }
        return true;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 960;

          return Scaffold(
            backgroundColor: theme.colorScheme.surface,
            drawer: isNarrow ? Drawer(child: _buildNavigation(isCompact: false)) : null,
            appBar: _buildTopBar(title, isNarrow: isNarrow),
            body: SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isNarrow)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: _navCollapsed ? 112 : 280,
                      margin: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          theme.colorScheme.surfaceVariant.withOpacity(
                            theme.brightness == Brightness.dark ? 0.36 : 0.6,
                          ),
                          theme.colorScheme.surface,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: theme.dividerColor.withOpacity(0.4)),
                      ),
                      child: _buildNavigation(isCompact: _navCollapsed),
                    ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1280),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          switchInCurve: Curves.easeOutQuad,
                          switchOutCurve: Curves.easeInQuad,
                          child: Padding(
                            key: ValueKey(_view),
                            padding: EdgeInsets.symmetric(
                              horizontal: isNarrow ? 12 : 18,
                              vertical: isNarrow ? 12 : 18,
                            ),
                            child: _buildBody(theme),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: LegalFooter(api: widget.api),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildTopBar(String title, {required bool isNarrow}) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context)!;
    final onSurfaceMuted = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
    );

    return AppBar(
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      leadingWidth: 56,
      leading: isNarrow
          ? Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu),
                tooltip: 'Navigation öffnen',
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            )
          : _navToggleButton(
              icon: _navCollapsed ? Icons.chevron_right : Icons.chevron_left,
              tooltip: _navCollapsed ? 'Sidebar erweitern' : 'Sidebar einklappen',
              onPressed: () => setState(() => _navCollapsed = !_navCollapsed),
            ),
      titleSpacing: isNarrow ? 0 : 12,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Adminbereich', style: onSurfaceMuted),
          const SizedBox(height: 2),
          Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Zurück zum Admin-Dashboard',
          onPressed: () => setState(() => _view = _AdminView.menu),
          icon: const Icon(Icons.home_outlined),
        ),
        IconButton(
          tooltip: t.logoutTitle,
          onPressed: _logoutAdmin,
          icon: const Icon(Icons.logout),
        ),
        w.ThemeAction(),
        const SizedBox(width: 2),
        IconButton(
          tooltip: 'Alles neu laden',
          onPressed: () async {
            await _refreshAll();
            await _refreshAllComplaints();
            await _refreshOpen();
            await _refreshNews();
            await _refreshFaq();
          },
          icon: const Icon(Icons.refresh),
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  void _handleNavigation(_AdminView view) {
    final shouldRefreshFaq = view == _AdminView.faq &&
        !_faqLoading &&
        (_faqCategories.isEmpty || _faqEntries.isEmpty);

    if (_view != view) {
      setState(() => _view = view);
    }

    if (shouldRefreshFaq) {
      _refreshFaq();
    }
  }

    Future<void> _logoutAdmin() async {
    final t = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.logoutTitle),
        content: Text(t.logoutConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.logout)),
        ],
      ),
    );

    if (confirmed == true) {
      widget.api.clearAdminSecret();
      if (mounted) Navigator.of(context).pop();
    }
  }

  Widget _buildNavigation({required bool isCompact}) {
    final theme = Theme.of(context);
    final Color accent = theme.colorScheme.primary;
    final Color subtle = theme.colorScheme.onSurfaceVariant;
    final sections = _navSections();
    final surfaceBlend = Color.alphaBlend(
      theme.colorScheme.surfaceVariant.withOpacity(theme.brightness == Brightness.dark ? 0.28 : 0.46),
      theme.colorScheme.surface,
    );

    Widget navBadge(String label, {required bool selected, required bool compact}) {
      final baseColor = selected ? accent : subtle;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 4 : 6),
        decoration: BoxDecoration(
          color: selected
              ? accent.withOpacity(theme.brightness == Brightness.dark ? 0.22 : 0.14)
              : theme.colorScheme.surfaceVariant.withOpacity(0.75),
          borderRadius: BorderRadius.circular(compact ? 10 : 12),
          border: Border.all(
            color: selected ? accent.withOpacity(0.5) : theme.colorScheme.outlineVariant.withOpacity(0.6),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: baseColor,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      );
    }

    Widget buildTile(_AdminNavItem item) {
      final selected = _view == item.view;
      final badgeWidget = item.badge == null
          ? null
          : navBadge(item.badge!, selected: selected, compact: isCompact);

      if (isCompact) {
        return Tooltip(
          message: item.label,
          verticalOffset: 12,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Scaffold.maybeOf(context)?.closeDrawer();
              _handleNavigation(item.view);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        height: 40,
                        width: 40,
                        decoration: BoxDecoration(
                          color: selected
                              ? accent.withOpacity(theme.brightness == Brightness.dark ? 0.18 : 0.16)
                              : theme.colorScheme.surfaceVariant.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? accent.withOpacity(0.65) : theme.colorScheme.outlineVariant,
                          ),
                        ),
                        child: Icon(item.icon, color: selected ? accent : subtle, size: 20),
                      ),
                      if (badgeWidget != null)
                        Positioned(
                          right: -2,
                          top: -4,
                          child: badgeWidget,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 3,
                    width: 30,
                    decoration: BoxDecoration(
                      color: selected ? accent : theme.colorScheme.outlineVariant.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return Material(
        color: selected
            ? accent.withOpacity(theme.brightness == Brightness.dark ? 0.18 : 0.14)
            : surfaceBlend,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Scaffold.maybeOf(context)?.closeDrawer();
            _handleNavigation(item.view);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  height: 44,
                  width: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        accent.withOpacity(selected ? 0.3 : 0.12),
                        accent.withOpacity(selected ? 0.18 : 0.08),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: selected ? accent.withOpacity(0.65) : theme.colorScheme.outlineVariant.withOpacity(0.55),
                    ),
                  ),
                  child: Icon(item.icon, color: selected ? accent : subtle, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: selected ? accent : theme.colorScheme.onSurface,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        selected ? 'Aktuell geöffnet' : 'Tippen zum Wechseln',
                        style: theme.textTheme.labelSmall?.copyWith(color: subtle),
                      ),
                    ],
                  ),
                ),
                if (badgeWidget != null) ...[
                  badgeWidget,
                  const SizedBox(width: 10),
                ],
                Icon(Icons.arrow_forward_ios_rounded, size: 16, color: subtle),
              ],
            ),
          ),
        ),
      );
    }

    Widget buildHeader() {
      return Padding(
        padding: EdgeInsets.fromLTRB(isCompact ? 8 : 16, 14, isCompact ? 8 : 16, isCompact ? 6 : 10),
        child: Row(
          children: [
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surface,
                border: Border.all(color: accent.withOpacity(0.5)),
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(Icons.dashboard_customize_outlined, color: accent, size: 24),
            ),
            if (!isCompact) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin-Cockpit',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.tune_rounded, size: 16, color: subtle),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Strukturierte Navigation, jederzeit einklappbar.',
                            style: theme.textTheme.labelMedium?.copyWith(color: subtle),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _navToggleButton(
                tooltip: 'Sidebar einklappen',
                icon: Icons.chevron_left,
                onPressed: () => setState(() => _navCollapsed = true),
              ),
            ] else ...[
              const Spacer(),
              _navToggleButton(
                tooltip: 'Sidebar erweitern',
                icon: Icons.chevron_right,
                onPressed: () => setState(() => _navCollapsed = false),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: surfaceBlend,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.55)),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.14),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          buildHeader(),
          Expanded(
            child: Scrollbar(
              thickness: 4,
              radius: const Radius.circular(12),
              interactive: true,
              thumbVisibility: true,
              child: ListView(
                primary: false,
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: isCompact ? 6 : 16, vertical: isCompact ? 4 : 8),
                children: [
                  for (final section in sections) ...[
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _NavigationSection(
                        key: ValueKey('${section.title}-$isCompact'),
                        title: section.title,
                        isCompact: isCompact,
                        children: section.items.map(buildTile).toList(),
                      ),
                    ),
                    SizedBox(height: isCompact ? 6 : 8),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(isCompact ? 8 : 16, 10, isCompact ? 8 : 16, 12),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 10 : 14, vertical: isCompact ? 8 : 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(theme.brightness == Brightness.dark ? 0.55 : 0.75),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
              ),
              child: isCompact
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.tips_and_updates_outlined, size: 18, color: subtle),
                        const SizedBox(width: 10),
                        _navToggleButton(
                          tooltip: _navCollapsed ? 'Sidebar erweitern' : 'Sidebar einklappen',
                          icon: _navCollapsed ? Icons.chevron_right : Icons.chevron_left,
                          onPressed: () => setState(() => _navCollapsed = !_navCollapsed),
                          color: subtle,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Icon(Icons.tips_and_updates_outlined, size: 18, color: subtle),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Navigation anpassbar: einklappen, Badges immer sichtbar, klare Gruppen.',
                            style: theme.textTheme.labelSmall?.copyWith(color: subtle),
                          ),
                        ),
                        _navToggleButton(
                          tooltip: _navCollapsed ? 'Sidebar erweitern' : 'Sidebar einklappen',
                          icon: _navCollapsed ? Icons.chevron_right : Icons.chevron_left,
                          onPressed: () => setState(() => _navCollapsed = !_navCollapsed),
                          color: subtle,
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navToggleButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: color),
        onPressed: onPressed,
        padding: const EdgeInsets.all(10),
        splashRadius: 24,
      ),
    );
  }

  List<_AdminNavSection> _navSections() {
    return [
      _AdminNavSection(
        title: 'Dashboard',
        items: [
          _AdminNavItem(
            label: 'Dashboard',
            icon: Icons.dashboard_outlined,
            view: _AdminView.menu,
          ),
        ],
      ),
      _AdminNavSection(
        title: 'Vorgänge',
        items: [
          _AdminNavItem(
            label: 'Offene Reklamationen',
            icon: Icons.assignment_late_outlined,
            view: _AdminView.open,
            badge: _openComplaints.isNotEmpty ? '${_openComplaints.length}' : null,
          ),
          _AdminNavItem(
            label: 'Alle Reklamationen',
            icon: Icons.dashboard_customize_outlined,
            view: _AdminView.all,
            badge: _allComplaints.isNotEmpty ? '${_allComplaints.length}' : null,
          ),
          _AdminNavItem(
            label: 'Pending / Review',
            icon: Icons.hourglass_bottom_outlined,
            view: _AdminView.pending,
            badge: _pending.isNotEmpty ? '${_pending.length}' : null,
          ),
        ],
      ),
      _AdminNavSection(
        title: 'Kunden & Reps',
        items: [
          _AdminNavItem(
            label: 'Kundendatenbank',
            icon: Icons.people_outline,
            view: _AdminView.users,
            badge: _users.isNotEmpty ? '${_users.length}' : null,
          ),
          _AdminNavItem(
            label: 'Kunden anlegen',
            icon: Icons.person_add_alt_1_outlined,
            view: _AdminView.createCustomer,
          ),
          _AdminNavItem(
            label: 'Vertreterverwaltung',
            icon: Icons.support_agent_outlined,
            view: _AdminView.reps,
            badge: _reps.isNotEmpty ? '${_reps.length}' : null,
          ),
          _AdminNavItem(
            label: 'Aktivität',
            icon: Icons.query_stats_outlined,
            view: _AdminView.activity,
          ),
        ],
      ),
      _AdminNavSection(
        title: 'Inhalte',
        items: [
          _AdminNavItem(
            label: 'News & Infos',
            icon: Icons.campaign_outlined,
            view: _AdminView.news,
          ),
          _AdminNavItem(
            label: 'FAQ / Wissen',
            icon: Icons.help_outline,
            view: _AdminView.faq,
          ),
          _AdminNavItem(
            label: 'Artikelliste',
            icon: Icons.inventory_2_outlined,
            view: _AdminView.products,
            badge: _products.isNotEmpty ? '${_products.length}' : null,
          ),
          _AdminNavItem(
            label: 'Kataloge',
            icon: Icons.menu_book_outlined,
            view: _AdminView.catalogs,
          ),
          _AdminNavItem(
            label: 'Push-Broadcasts',
            icon: Icons.wifi_tethering_outlined,
            view: _AdminView.pushBroadcast,
            badge: _pushResult?.totalTokens != null && _pushResult!.totalTokens! > 0
                ? '${_pushResult!.totalTokens}'
                : null,
          ),
        ],
      ),
      _AdminNavSection(
        title: 'Vertreter-Wiki',
        items: [
          _AdminNavItem(
            label: 'Vertreter-Wiki',
            icon: Icons.menu_book_rounded,
            view: _AdminView.wiki,
          ),
          _AdminNavItem(
            label: 'Kategorien verwalten',
            icon: Icons.category_outlined,
            view: _AdminView.wikiCategories,
          ),
          _AdminNavItem(
            label: 'Artikel verwalten',
            icon: Icons.menu_book_outlined,
            view: _AdminView.wikiArticles,
          ),
        ],
      ),
      _AdminNavSection(
        title: 'System',
        items: [
          _AdminNavItem(
            label: 'Systemstatus',
            icon: Icons.health_and_safety_outlined,
            view: _AdminView.systemHealth,
          ),
          _AdminNavItem(
            label: 'Aktivitäts-Checks',
            icon: Icons.analytics_outlined,
            view: _AdminView.activity,
          ),
        ],
      ),
    ];
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

  List<_AdminMenuSectionState> _baseMenuSections() {
    return [
      const _AdminMenuSectionState(
        title: 'Reklamationen',
        subtitle: 'Offene Fälle, Suche und Kennzahlen',
        tileIds: ['open', 'all', 'stats'],
      ),
      const _AdminMenuSectionState(
        title: 'Kunden & Vertreter',
        subtitle: 'Anträge prüfen, Accounts und Teams steuern',
        tileIds: ['pending', 'users', 'createCustomer', 'reps'],
      ),
      const _AdminMenuSectionState(
        title: 'Kommunikation & Inhalte',
        subtitle: 'Informationen und Push-Kanäle pflegen',
        tileIds: ['news', 'faq', 'wiki', 'products', 'push'],
      ),
      const _AdminMenuSectionState(
        title: 'System & Konfiguration',
        subtitle: 'Kataloge, Versionen, Testmodus und Monitoring',
        tileIds: ['catalogs', 'appMeta', 'testMode', 'systemHealth', 'activity'],
      ),
    ];
  }

  void _initMenuLayout() {
    final defaults = _baseMenuSections();
    _tileDefaultSection = {
      for (final section in defaults) for (final id in section.tileIds) id: section.title,
    };
    _menuTileIds = _tileDefaultSection.keys.toSet();
    _menuSections = _loadMenuLayout(defaults: defaults);
  }

  List<_AdminMenuSectionState> _loadMenuLayout({required List<_AdminMenuSectionState> defaults}) {
    _menuTileScale = 1.0;
    _archivedTileIds.clear();
    final raw = html.window.localStorage[_menuLayoutStorageKey];
    if (raw == null) {
      return defaults.map((s) => s.copy()).toList();
    }

    try {
      final parsed = jsonDecode(raw);
      List<dynamic>? sectionData;

      if (parsed is Map) {
        final scale = parsed['tileScale'];
        if (scale is num) {
          _menuTileScale = scale.clamp(_tileScaleMin, _tileScaleMax).toDouble();
        }
        final sections = parsed['sections'];
        if (sections is List) sectionData = sections;
        final archived = parsed['archived'];
        if (archived is List) {
          _archivedTileIds.addAll(
            archived.whereType<String>().where(_menuTileIds.contains),
          );
        }
      } else if (parsed is List) {
        sectionData = parsed;
      }

      if (sectionData == null) return defaults.map((s) => s.copy()).toList();

      final used = <String>{};
      final sections = <_AdminMenuSectionState>[];

      for (final entry in sectionData) {
        if (entry is! Map) continue;
        final title = entry['title'] as String?;
        final subtitle = entry['subtitle'] as String? ?? '';
        final tiles = (entry['tiles'] as List?)?.whereType<String>().toList() ?? <String>[];
        if (title == null) continue;

        final filtered =
            tiles.where((id) => _menuTileIds.contains(id) && !_archivedTileIds.contains(id)).toList();
        used.addAll(filtered);
        sections.add(_AdminMenuSectionState(title: title, subtitle: subtitle, tileIds: filtered));
      }

      if (sections.isEmpty) return defaults.map((s) => s.copy()).toList();

      for (final id in _menuTileIds) {
        if (used.contains(id) || _archivedTileIds.contains(id)) continue;
        final targetTitle = _tileDefaultSection[id];
        final targetSection = sections.firstWhere(
          (s) => s.title == targetTitle,
          orElse: () => sections.first,
        );
        targetSection.tileIds.add(id);
      }

      return sections;
    } catch (_) {
      _menuTileScale = 1.0;
      _archivedTileIds.clear();
      return defaults.map((s) => s.copy()).toList();
    }
  }

  Future<void> _addMenuSection() async {
    final titleCtrl = TextEditingController();
    final subtitleCtrl = TextEditingController();

    final created = await showDialog<_AdminMenuSectionState>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Neue Kategorie hinzufügen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Titel'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subtitleCtrl,
                decoration: const InputDecoration(labelText: 'Beschreibung'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                final title = titleCtrl.text.trim();
                final subtitle = subtitleCtrl.text.trim();
                if (title.isEmpty) return;
                Navigator.of(context).pop(
                  _AdminMenuSectionState(
                    title: title,
                    subtitle: subtitle,
                    tileIds: <String>[],
                  ),
                );
              },
              child: const Text('Hinzufügen'),
            ),
          ],
        );
      },
    );

    if (created == null) return;

    setState(() {
      _menuSections = [..._menuSections, created];
    });
    _persistMenuLayout();
  }

  void _persistMenuLayout() {
    html.window.localStorage[_menuLayoutStorageKey] = jsonEncode({
      'sections': _menuSections.map((s) => s.toJson()).toList(),
      'tileScale': _menuTileScale,
      'archived': _archivedTileIds.toList(),
    });
  }

  void _resetMenuLayout() {
    setState(() {
      _menuSections = _baseMenuSections().map((s) => s.copy()).toList();
      _menuTileScale = 1.0;
      _archivedTileIds.clear();
    });
    _persistMenuLayout();
  }

  // ------------------ Kachel-Menü (neues Design) ------------------
  Widget _buildMenu() {
    final w = MediaQuery.of(context).size.width;
    final isPhone = w < 640;
    final compact = isPhone;
    final sections = _menuSections;
    final baseTileWidth = isPhone ? 200.0 : 240.0;
    final aspectRatio = isPhone ? 0.94 : 1.05;
    final tileWidth = baseTileWidth * _menuTileScale;
    final tileHeight = tileWidth / aspectRatio;
    final spacing = (isPhone ? 14.0 : 28.0) * _menuTileScale;
    final runSpacing = (isPhone ? 20.0 : 32.0) * _menuTileScale;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(
                  _menuEditMode ? Icons.drag_indicator_outlined : Icons.dashboard_customize_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _menuEditMode
                            ? 'Kacheln per Drag & Drop zwischen Bereichen verschieben oder neu anordnen.'
                            : 'Admin-Dashboard anpassen',
                      ),
                      if (_menuEditMode)
                        Text(
                          'Zum Beenden unten auf "Bearbeitung schließen" klicken.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (_menuEditMode)
                        Text(
                          'Kacheln können ausgeblendet und im Archiv später wieder eingeblendet werden.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (!_menuEditMode)
                  FilledButton.icon(
                    onPressed: () => setState(() => _menuEditMode = true),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Bearbeiten'),
                  ),
                if (_menuEditMode) ...[
                  TextButton.icon(
                    onPressed: _addMenuSection,
                    icon: const Icon(Icons.add_outlined),
                    label: const Text('Kategorie hinzufügen'),
                  ),
                  TextButton.icon(
                    onPressed: _resetMenuLayout,
                    icon: const Icon(Icons.refresh_outlined),
                    label: const Text('Layout zurücksetzen'),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_menuEditMode)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Card(
                margin: EdgeInsets.zero,
                color: Theme.of(context).colorScheme.surfaceVariant,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.aspect_ratio_outlined),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Kachelgröße einstellen',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          Text('${(_menuTileScale * 100).round()}%'),
                        ],
                      ),
                      Slider.adaptive(
                        value: _menuTileScale,
                        min: _tileScaleMin,
                        max: _tileScaleMax,
                        label: '${(_menuTileScale * 100).round()}%',
                        onChanged: (value) {
                          setState(
                            () => _menuTileScale = value.clamp(_tileScaleMin, _tileScaleMax),
                          );
                          _persistMenuLayout();
                        },
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Stufenlose Anpassung zwischen 60% und 135%; gilt für alle Kacheln und wird beim Speichern der Dashboard-Anpassung übernommen.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (_menuEditMode) _buildSectionReorderTarget(index: 0),
        for (var i = 0; i < sections.length; i++) ...[
          SliverToBoxAdapter(child: const SizedBox(height: 4)),
          SliverToBoxAdapter(
            child: _buildMenuSectionHeader(
              sections[i],
              isFirst: i == 0,
              index: i,
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, i == sections.length - 1 ? 28 : 12),
            sliver: SliverToBoxAdapter(
              child: _buildSectionGrid(
                sectionIndex: i,
                section: sections[i],
                compact: compact,
                tileWidth: tileWidth,
                tileHeight: tileHeight,
                spacing: spacing,
                runSpacing: runSpacing,
              ),
            ),
          ),
          if (_menuEditMode) _buildSectionReorderTarget(index: i + 1),
        ],
        if (_menuEditMode)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _buildArchivedTilesPanel(
                compact: compact,
                tileWidth: tileWidth,
                tileHeight: tileHeight,
                spacing: spacing,
                runSpacing: runSpacing,
              ),
            ),
          ),
        if (_menuEditMode)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _menuEditMode = false),
                  icon: const Icon(Icons.close_outlined),
                  label: const Text('Bearbeitung schließen'),
                ),
              ),
            ),
          ),
      ],
    );
  }

  SliverToBoxAdapter _buildSectionReorderTarget({required int index}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SliverToBoxAdapter(
      child: DragTarget<_DraggedSection>(
        onWillAccept: (_) => true,
        onAccept: (data) => _handleSectionDrop(data, index),
        builder: (context, candidate, rejected) {
          final highlight = candidate.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            height: _sectionReorderHeight,
            decoration: BoxDecoration(
              color: highlight ? cs.primary.withOpacity(0.08) : cs.surfaceVariant.withOpacity(0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: highlight ? cs.primary : cs.outlineVariant,
                width: highlight ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.swap_vert, color: highlight ? cs.primary : cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  'Kategorie hier ablegen',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: highlight ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionGrid({
    required int sectionIndex,
    required _AdminMenuSectionState section,
    required bool compact,
    required double tileWidth,
    required double tileHeight,
    required double spacing,
    required double runSpacing,
  }) {
    if (!_menuEditMode) {
      return Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        children: [
          for (final tileId in section.tileIds)
            SizedBox(
              width: tileWidth,
              height: tileHeight,
              child: _buildMenuTile(tileId, compact),
            ),
        ],
      );
    }

    final tiles = <Widget>[];
    for (var tileIndex = 0; tileIndex < section.tileIds.length; tileIndex++) {
      tiles.add(
        _buildDraggableTile(
          sectionIndex: sectionIndex,
          tileIndex: tileIndex,
          tileId: section.tileIds[tileIndex],
          compact: compact,
          tileWidth: tileWidth,
          tileHeight: tileHeight,
        ),
      );
    }

    tiles.add(
      _buildDropTarget(
        sectionIndex: sectionIndex,
        insertIndex: section.tileIds.length,
        compact: compact,
        tileWidth: tileWidth,
        tileHeight: tileHeight,
        highlightLabel: 'Hierhin verschieben',
      ),
    );

    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      children: tiles,
    );
  }

  Widget _buildArchivedTilesPanel({
    required bool compact,
    required double tileWidth,
    required double tileHeight,
    required double spacing,
    required double runSpacing,
  }) {
    final archived = _archivedTileIds.toList()..sort();

    return Card(
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.inventory_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ausgeblendete Kacheln',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        archived.isEmpty
                            ? 'Hier erscheinen Kacheln, die aus dem Dashboard ausgeblendet wurden.'
                            : 'Kacheln können jederzeit wieder eingeblendet und automatisch zugeordnet werden.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (archived.isEmpty)
              Text(
                'Aktuell sind keine Kacheln archiviert.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              Wrap(
                spacing: spacing,
                runSpacing: runSpacing,
                children: [
                  for (final id in archived)
                    SizedBox(
                      width: tileWidth,
                      height: tileHeight,
                      child: _buildMenuTile(
                        id,
                        compact,
                        isPreview: true,
                        onActionTap: () => _restoreArchivedTile(id),
                        actionLabel: 'Kachel einblenden',
                        actionIcon: Icons.unarchive_outlined,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraggableTile({
    required int sectionIndex,
    required int tileIndex,
    required String tileId,
    required bool compact,
    required double tileWidth,
    required double tileHeight,
  }) {
    return DragTarget<_DraggedTile>(
      onWillAccept: (_) => true,
      onAccept: (data) => _handleTileDrop(data, sectionIndex, tileIndex),
      builder: (context, candidate, rejected) {
        final highlight = candidate.isNotEmpty;
        final tile = SizedBox(
          width: tileWidth,
          height: tileHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: _buildAdaptiveDraggable(
                  tileId: tileId,
                  sectionIndex: sectionIndex,
                  tileWidth: tileWidth,
                  tileHeight: tileHeight,
                  compact: compact,
                  highlight: highlight,
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: Tooltip(
                  message: 'Kachel ausblenden/archivieren',
                  child: IconButton.filledTonal(
                    icon: const Icon(Icons.visibility_off_outlined),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(36, 36),
                      padding: const EdgeInsets.all(8),
                    ),
                    onPressed: () => _archiveTile(tileId, sectionIndex),
                  ),
                ),
              ),
            ],
          ),
        );
        return tile;
      },
    );
  }

  Widget _buildAdaptiveDraggable({
    required String tileId,
    required int sectionIndex,
    required double tileWidth,
    required double tileHeight,
    required bool compact,
    required bool highlight,
  }) {
    final data = _DraggedTile(tileId: tileId, sectionIndex: sectionIndex);

    Widget buildChild(Widget child) => _decorateDropCandidate(
          highlight: highlight,
          child: child,
        );

    Widget buildFeedback() => Material(
          color: Colors.transparent,
          child: SizedBox(
            width: tileWidth,
            height: tileHeight,
            child: _buildMenuTile(tileId, compact, isPreview: true),
          ),
        );

    final childWhenDragging = Opacity(
      opacity: 0.3,
      child: _buildMenuTile(tileId, compact),
    );

    if (_useLongPressDrag()) {
      return LongPressDraggable<_DraggedTile>(
        data: data,
        feedback: buildFeedback(),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        childWhenDragging: childWhenDragging,
        child: buildChild(_buildMenuTile(tileId, compact)),
      );
    }

    return Draggable<_DraggedTile>(
      data: data,
      feedback: buildFeedback(),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      childWhenDragging: childWhenDragging,
      child: buildChild(_buildMenuTile(tileId, compact)),
    );
  }

  bool _useLongPressDrag() {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return true;
      default:
        return false;
    }
  }

  Widget _buildDropTarget({
    required int sectionIndex,
    required int insertIndex,
    required bool compact,
    required double tileWidth,
    required double tileHeight,
    String? highlightLabel,
  }) {
    return DragTarget<_DraggedTile>(
      onWillAccept: (_) => true,
      onAccept: (data) => _handleTileDrop(data, sectionIndex, insertIndex),
      builder: (context, candidate, rejected) {
        final highlight = candidate.isNotEmpty;
        return SizedBox(
          width: tileWidth,
          height: tileHeight,
          child: _decorateDropCandidate(
            highlight: highlight,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: highlight ? 1 : 0.12,
              child: AdminTilePro(
                label: highlightLabel ?? 'Ablegen',
                subtitle: 'Neue Position',
                icon: Icons.open_with_outlined,
                colorA: AdminPalette.blueA,
                colorB: AdminPalette.blueB,
                compact: compact,
                onTap: () {},
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _decorateDropCandidate({required bool highlight, required Widget child}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        border: Border.all(
          color: highlight ? Theme.of(context).colorScheme.primary : Colors.transparent,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }

  void _handleTileDrop(_DraggedTile data, int targetSectionIndex, int insertIndex) {
    if (targetSectionIndex < 0 || targetSectionIndex >= _menuSections.length) return;
    setState(() {
      if (data.sectionIndex >= _menuSections.length) return;
      final sourceSection = _menuSections[data.sectionIndex];
      final currentIndex = sourceSection.tileIds.indexOf(data.tileId);
      if (currentIndex == -1) return;

      final isSameSection = data.sectionIndex == targetSectionIndex;
      var targetInsertIndex = insertIndex;
      if (isSameSection && insertIndex > currentIndex) {
        targetInsertIndex -= 1;
      }

      sourceSection.tileIds.removeAt(currentIndex);
      final targetSection = _menuSections[targetSectionIndex];
      targetInsertIndex = targetInsertIndex.clamp(0, targetSection.tileIds.length);
      targetSection.tileIds.insert(targetInsertIndex, data.tileId);
    });
    _persistMenuLayout();
  }

  void _handleSectionDrop(_DraggedSection data, int targetIndex) {
    if (targetIndex < 0 || targetIndex > _menuSections.length) return;
    if (data.sectionIndex < 0 || data.sectionIndex >= _menuSections.length) return;

    setState(() {
      final moving = _menuSections.removeAt(data.sectionIndex);
      var insertIndex = targetIndex;
      if (targetIndex > data.sectionIndex) {
        insertIndex -= 1;
      }
      insertIndex = insertIndex.clamp(0, _menuSections.length);
      _menuSections.insert(insertIndex, moving);
    });
    _persistMenuLayout();
  }

  void _archiveTile(String tileId, int sectionIndex) {
    if (!_menuTileIds.contains(tileId)) return;

    setState(() {
      if (sectionIndex >= 0 && sectionIndex < _menuSections.length) {
        _menuSections[sectionIndex].tileIds.remove(tileId);
      } else {
        for (final section in _menuSections) {
          section.tileIds.remove(tileId);
        }
      }
      _archivedTileIds.add(tileId);
    });
    _persistMenuLayout();
  }

  void _restoreArchivedTile(String tileId) {
    if (!_archivedTileIds.contains(tileId)) return;

    setState(() {
      if (_menuSections.isEmpty) {
        _menuSections = _baseMenuSections().map((s) => s.copy()).toList();
      }

      _archivedTileIds.remove(tileId);
      final targetTitle = _tileDefaultSection[tileId];
      final targetSection = targetTitle != null
          ? _menuSections.firstWhere(
              (s) => s.title == targetTitle,
              orElse: () => _menuSections.first,
            )
          : _menuSections.first;

      if (!targetSection.tileIds.contains(tileId)) {
        targetSection.tileIds.add(tileId);
      }
    });

    _persistMenuLayout();
  }

  Widget _buildMenuTile(
    String tileId,
    bool compact, {
    bool isPreview = false,
    VoidCallback? onActionTap,
    String? actionLabel,
    IconData? actionIcon,
  }) {
    final resolvedActionLabel =
        onActionTap == null ? null : (actionLabel ?? 'Kachel einblenden');
    final resolvedActionIcon = onActionTap == null ? null : (actionIcon ?? Icons.unarchive_outlined);
    switch (tileId) {
      case 'open':
        return AdminTilePro(
          label: 'Offene Reklamationen',
          subtitle: 'Bearbeiten & Entscheiden',
          icon: Icons.assignment_late_outlined,
          colorA: AdminPalette.redA,
          colorB: AdminPalette.redB,
          count: _openComplaints.length,
          compact: compact,
          onTap: isPreview ? () {} : () => setState(() => _view = _AdminView.open),
          actionLabel: resolvedActionLabel,
          actionIcon: resolvedActionIcon,
          onActionTap: onActionTap,
        );
      case 'all':
        return AdminTilePro(
          label: 'Alle Reklamationen',
          subtitle: 'Suche & Filter',
          icon: Icons.dashboard_customize_outlined,
          colorA: AdminPalette.purpleA,
          colorB: AdminPalette.purpleB,
          count: _allComplaints.length,
          compact: compact,
          onTap: isPreview ? () {} : () => setState(() => _view = _AdminView.all),
          actionLabel: resolvedActionLabel,
          actionIcon: resolvedActionIcon,
          onActionTap: onActionTap,
        );
      case 'stats':
        return AdminTilePro(
          label: 'Statistik & KPIs',
          subtitle: 'Übersicht & Trends',
          icon: Icons.query_stats_outlined,
          colorA: AdminPalette.blueA,
          colorB: AdminPalette.blueB,
          compact: compact,
          onTap: isPreview
              ? () {}
              : () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => AdminStatsPage(api: widget.api)),
                  );
                },
          actionLabel: resolvedActionLabel,
          actionIcon: resolvedActionIcon,
          onActionTap: onActionTap,
        );
      case 'pending':
        return AdminTilePro(
          label: 'Anträge / Pending',
          subtitle: 'Registrierungen prüfen',
          icon: Icons.verified_user_outlined,
          colorA: AdminPalette.amberA,
          colorB: AdminPalette.amberB,
          count: _pending.length,
          compact: compact,
          onTap: isPreview ? () {} : () => setState(() => _view = _AdminView.pending),
          actionLabel: resolvedActionLabel,
          actionIcon: resolvedActionIcon,
          onActionTap: onActionTap,
        );
      case 'users':
        return AdminTilePro(
          label: 'Kundendatenbank',
          subtitle: 'Firmen & Kontakte',
          icon: Icons.group_outlined,
          colorA: AdminPalette.tealA,
          colorB: AdminPalette.tealB,
          count: _users.length,
          compact: compact,
          onTap: isPreview ? () {} : () => setState(() => _view = _AdminView.users),
          actionLabel: resolvedActionLabel,
          actionIcon: resolvedActionIcon,
          onActionTap: onActionTap,
        );
      case 'createCustomer':
        return AdminTilePro(
          label: 'Neuen Kunden anlegen',
          subtitle: 'Account direkt erstellen',
          icon: Icons.person_add_alt_1_outlined,
          colorA: AdminPalette.tealA,
          colorB: AdminPalette.tealB,
          compact: compact,
          onTap: isPreview ? () {} : () => setState(() => _view = _AdminView.createCustomer),
          actionLabel: resolvedActionLabel,
          actionIcon: resolvedActionIcon,
          onActionTap: onActionTap,
        );
      case 'reps':
        return AdminTilePro(
          label: 'Vertreterverwaltung',
          subtitle: 'Zuordnen & Regionen',
          icon: Icons.badge_outlined,
          colorA: AdminPalette.blueA,
          colorB: AdminPalette.blueB,
          compact: compact,
          onTap: isPreview
              ? () {}
              : () {
                  setState(() => _view = _AdminView.reps);
                  if (_reps.isEmpty) _refreshReps();
                },
          actionLabel: resolvedActionLabel,
          actionIcon: resolvedActionIcon,
          onActionTap: onActionTap,
        );
      case 'news':
        return AdminTilePro(
          label: 'Neuigkeiten & Infoscreen',
          subtitle: 'Kundenticker pflegen',
          icon: Icons.campaign_outlined,
          colorA: AdminPalette.amberA,
          colorB: AdminPalette.amberB,
          compact: compact,
          count: _newsEntries.length,
          onTap: isPreview
              ? () {}
              : () {
                  setState(() => _view = _AdminView.news);
                  if (_newsEntries.isEmpty) _refreshNews();
                },
          actionLabel: resolvedActionLabel,
          actionIcon: resolvedActionIcon,
          onActionTap: onActionTap,
        );
      case 'faq':
        return AdminTilePro(
          label: 'Wissensdatenbank (FAQ)',
          subtitle: 'Artikel & Kategorien verwalten',
          icon: Icons.library_books_outlined,
          colorA: AdminPalette.blueA,
          colorB: AdminPalette.blueB,
          compact: compact,
          count: _faqEntries.length,
          onTap: isPreview ? () {} : () => _handleNavigation(_AdminView.faq),
          actionLabel: resolvedActionLabel,
          actionIcon: resolvedActionIcon,
          onActionTap: onActionTap,
        );
      case 'wiki':
        return AdminTilePro(
          label: 'Vertreter-Wiki',
          subtitle: 'Kundenwissen & Produktinfos',
          icon: Icons.menu_book_rounded,
          colorA: AdminPalette.tealA,
          colorB: AdminPalette.tealB,
          compact: compact,
          onTap: isPreview ? () {} : () => setState(() => _view = _AdminView.wiki),
          actionLabel: resolvedActionLabel,
          actionIcon: resolvedActionIcon,
          onActionTap: onActionTap,
        );
      case 'products':
        return AdminTilePro(
          label: 'Artikelliste',
          subtitle: 'Produktdaten filtern & pflegen',
          icon: Icons.inventory_2_outlined,
          colorA: AdminPalette.blueA,
          colorB: AdminPalette.blueB,
          compact: compact,
          count: _products.length,
          onTap: isPreview ? () {} : () => setState(() => _view = _AdminView.products),
          actionLabel: resolvedActionLabel,
          actionIcon: resolvedActionIcon,
          onActionTap: onActionTap,
        );
      case 'push':
        return AdminTilePro(
          label: 'Push-Mitteilungen',
          subtitle: 'Broadcast an alle Kunden',
          icon: Icons.notifications_active_outlined,
          colorA: AdminPalette.amberA,
          colorB: AdminPalette.amberB,
          compact: compact,
          count: _pushResult?.totalTokens,
          onTap: isPreview ? () {} : () => setState(() => _view = _AdminView.pushBroadcast),
          actionLabel: resolvedActionLabel,
          actionIcon: resolvedActionIcon,
          onActionTap: onActionTap,
        );
      case 'catalogs':
        return AdminTilePro(
          label: 'Kataloge',
          subtitle: 'Links & Sprachen',
          icon: Icons.menu_book_outlined,
          colorA: AdminPalette.blueA,
          colorB: AdminPalette.blueB,
          compact: compact,
          onTap: isPreview ? () {} : () => setState(() => _view = _AdminView.catalogs),
          actionLabel: resolvedActionLabel,
          actionIcon: resolvedActionIcon,
          onActionTap: onActionTap,
        );
      case 'appMeta':
        return AdminTilePro(
          label: 'App-Version',
          subtitle: 'Version, Build, Release-Hinweise',
          icon: Icons.app_settings_alt_outlined,
          colorA: AdminPalette.blueA,
          colorB: AdminPalette.blueB,
          compact: compact,
          onTap: isPreview ? () {} : () => _editAppMeta(context),
          actionLabel: resolvedActionLabel,
          actionIcon: resolvedActionIcon,
          onActionTap: onActionTap,
        );
      case 'testMode':
        return AdminTilePro(
          label: 'Testmodus & Routing',
          subtitle: 'Testmails, Push-Filter und Sicherungen',
          icon: Icons.science_outlined,
          colorA: AdminPalette.blueA,
          colorB: AdminPalette.blueB,
          compact: compact,
          onTap: isPreview ? () {} : () => _editTestMode(context),
          actionLabel: resolvedActionLabel,
          actionIcon: resolvedActionIcon,
          onActionTap: onActionTap,
        );
      case 'systemHealth':
        return AdminTilePro(
          label: 'Systemstatus',
          subtitle: 'Health & Konfiguration',
          icon: Icons.health_and_safety_outlined,
          colorA: AdminPalette.tealA,
          colorB: AdminPalette.tealB,
          compact: compact,
          onTap: isPreview
              ? () {}
              : () {
                  setState(() => _view = _AdminView.systemHealth);
                  _loadSystemHealth(force: true);
                },
          actionLabel: resolvedActionLabel,
          actionIcon: resolvedActionIcon,
          onActionTap: onActionTap,
        );
      case 'activity':
        return AdminTilePro(
          label: 'Aktivitätsübersicht',
          subtitle: 'Login, Tickets, Push',
          icon: Icons.query_stats_outlined,
          colorA: AdminPalette.tealA,
          colorB: AdminPalette.tealB,
          compact: compact,
          onTap: isPreview ? () {} : () => setState(() => _view = _AdminView.activity),
          actionLabel: resolvedActionLabel,
          actionIcon: resolvedActionIcon,
          onActionTap: onActionTap,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _editMenuSection(int index) async {
    final section = _menuSections[index];
    final titleCtrl = TextEditingController(text: section.title);
    final subtitleCtrl = TextEditingController(text: section.subtitle);

    final updated = await showDialog<_AdminMenuSectionState>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Kategorie bearbeiten'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Titel'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subtitleCtrl,
                decoration: const InputDecoration(labelText: 'Beschreibung'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                final newTitle = titleCtrl.text.trim();
                final newSubtitle = subtitleCtrl.text.trim();
                if (newTitle.isEmpty) return;
                Navigator.of(context).pop(
                  section.copyWith(
                    title: newTitle,
                    subtitle: newSubtitle,
                  ),
                );
              },
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    );

    if (updated == null) return;

    setState(() {
      _menuSections[index] = updated;
    });
    _persistMenuLayout();
  }

  Future<void> _confirmDeleteMenuSection(int index) async {
    if (index < 0 || index >= _menuSections.length) return;
    final section = _menuSections[index];
    final tileCount = section.tileIds.length;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Kategorie löschen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('"${section.title}" entfernen?'),
              const SizedBox(height: 8),
              Text(
                tileCount == 0
                    ? 'Es sind keine Kacheln in dieser Kategorie enthalten.'
                    : 'Die ${tileCount == 1 ? 'eine Kachel' : '$tileCount Kacheln'} wird automatisch in Standardbereiche verschoben.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Löschen'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;
    _removeMenuSection(index);
  }

  void _removeMenuSection(int index) {
    if (index < 0 || index >= _menuSections.length) return;
    final removed = _menuSections[index];
    final tilesToReassign = List<String>.from(removed.tileIds);

    setState(() {
      _menuSections = List<_AdminMenuSectionState>.from(_menuSections)..removeAt(index);
      if (_menuSections.isEmpty) {
        _menuSections = _baseMenuSections().map((s) => s.copy()).toList();
      }

      for (final tileId in tilesToReassign) {
        final targetTitle = _tileDefaultSection[tileId];
        final targetSection = targetTitle != null
            ? _menuSections.firstWhere(
                (s) => s.title == targetTitle,
                orElse: () => _menuSections.first,
              )
            : _menuSections.first;
        if (!targetSection.tileIds.contains(tileId)) {
          targetSection.tileIds.add(tileId);
        }
      }
    });
    _persistMenuLayout();
  }

  Widget _buildMenuSectionHeader(
    _AdminMenuSectionState section, {
    required bool isFirst,
    required int index,
  }) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700);
    final subtitleStyle = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final header = _buildMenuSectionHeaderContent(section, titleStyle, subtitleStyle, index: index);

    if (!_menuEditMode) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, isFirst ? 16 : 8, 16, 4),
        child: header,
      );
    }

    final data = _DraggedSection(sectionIndex: index);
    final dragHandle = _useLongPressDrag()
        ? LongPressDraggable<_DraggedSection>(
            data: data,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: _buildSectionDragFeedback(section),
            childWhenDragging: _buildMenuSectionHeaderContent(
              section,
              titleStyle,
              subtitleStyle,
              muted: true,
              index: index,
            ),
            child: header,
          )
        : Draggable<_DraggedSection>(
            data: data,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: _buildSectionDragFeedback(section),
            childWhenDragging: _buildMenuSectionHeaderContent(
              section,
              titleStyle,
              subtitleStyle,
              muted: true,
              index: index,
            ),
            child: header,
          );

    return Padding(
      padding: EdgeInsets.fromLTRB(16, isFirst ? 16 : 8, 16, 4),
      child: dragHandle,
    );
  }

  Widget _buildMenuSectionHeaderContent(
    _AdminMenuSectionState section,
    TextStyle? titleStyle,
    TextStyle? subtitleStyle, {
    bool muted = false,
    required int index,
  }) {
    final cs = Theme.of(context).colorScheme;
    final color = muted ? cs.onSurfaceVariant.withOpacity(0.6) : cs.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_menuEditMode)
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 12),
            child: Icon(Icons.drag_indicator, color: color),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(section.title, style: titleStyle?.copyWith(color: color)),
              const SizedBox(height: 4),
              Text(section.subtitle, style: subtitleStyle?.copyWith(color: color)),
            ],
          ),
        ),
        if (_menuEditMode) ...[
          IconButton(
            tooltip: 'Kategorie löschen',
            icon: const Icon(Icons.delete_outline),
            onPressed: _menuSections.length <= 1 ? null : () => _confirmDeleteMenuSection(index),
          ),
          IconButton(
            tooltip: 'Kategorie bearbeiten',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editMenuSection(index),
          ),
        ],
      ],
    );
  }

  Widget _buildSectionDragFeedback(_AdminMenuSectionState section) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 320,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: theme.colorScheme.primary, width: 1.5),
        ),
        child: Row(
          children: [
            const Icon(Icons.folder_copy_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(section.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(section.subtitle, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // ------------------ Panel-Ansichten ------------------
  Widget _buildView() {
    switch (_view) {
      case _AdminView.all:
        return _buildAllComplaintsPanel();
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
      case _AdminView.news:
        return _buildNewsPanel();
      case _AdminView.products:
        return _buildProductsPanel();
      case _AdminView.faq:
        return _buildFaqPanel();
      case _AdminView.wiki:
        return _buildWikiOverview();
      case _AdminView.catalogs:
        return _buildCatalogsPanel();
      case _AdminView.systemHealth:
        return _buildSystemHealthPanel();
      case _AdminView.activity:
        return _buildActivityPanel();
      case _AdminView.createCustomer:
        return _buildCreateCustomerPanel();
      case _AdminView.pushBroadcast:
        return _buildPushBroadcastPanel();
      case _AdminView.wikiCategories:
        return AdminWikiCategoriesPage(
          api: widget.api,
          onBack: () => setState(() => _view = _AdminView.wiki),
        );
      case _AdminView.wikiArticles:
        return AdminWikiArticlesPage(
          api: widget.api,
          onBack: () => setState(() => _view = _AdminView.wiki),
        );
    }
  }

  Widget _buildWikiOverview() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget tile({
      required IconData icon,
      required String title,
      required String desc,
      required VoidCallback onTap,
      Color? accent,
      Widget? footer,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withOpacity(.7)),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withOpacity(.06),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: accent ?? cs.primaryContainer,
                    foregroundColor: accent != null ? cs.onPrimaryContainer : cs.primary,
                    child: Icon(icon),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_forward_ios_rounded, color: cs.onSurfaceVariant, size: 16),
                ],
              ),
              const SizedBox(height: 14),
              Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(desc, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              if (footer != null) ...[const SizedBox(height: 12), footer],
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primaryContainer, cs.surface, cs.surfaceVariant],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: cs.shadow.withOpacity(.08), blurRadius: 18, offset: const Offset(0, 10)),
              ],
              border: Border.all(color: cs.primary.withOpacity(.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: cs.primary.withOpacity(.25), blurRadius: 16, offset: const Offset(0, 10))],
                  ),
                  child: Icon(Icons.menu_book_rounded, color: cs.onPrimary, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Vertreter-Wiki',
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: .2)),
                      const SizedBox(height: 6),
                      Text(
                          'Gestalte die Wissensbasis mit klaren Kategorien, gepflegten Artikeln und einer hochwertigen Vertreteransicht.',
                          style: theme.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: const [
                          Chip(label: Text('Kachelübersicht')),
                          Chip(label: Text('Schnellzugriff')),
                          Chip(label: Text('Vertreteransicht in Sekunden')),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              tile(
                icon: Icons.category_outlined,
                title: 'Kategorien verwalten',
                desc: 'Struktur, Sortierung und Aktivierung der Wissensbereiche im Blick behalten.',
                accent: cs.primaryContainer,
                onTap: () => setState(() => _view = _AdminView.wikiCategories),
                footer: Wrap(
                  spacing: 8,
                  children: const [
                    Chip(label: Text('Status-Badges')),
                    Chip(label: Text('Sortierung')),
                  ],
                ),
              ),
              tile(
                icon: Icons.article_outlined,
                title: 'Artikel verwalten',
                desc: 'Markdown-Inhalte pflegen, Produktgruppen zuordnen und Veröffentlichungen steuern.',
                accent: cs.secondaryContainer,
                onTap: () => setState(() => _view = _AdminView.wikiArticles),
                footer: Wrap(
                  spacing: 8,
                  children: const [
                    Chip(label: Text('Teaser & Tags')),
                    Chip(label: Text('Produktgruppen')),
                  ],
                ),
              ),
              tile(
                icon: Icons.open_in_new_rounded,
                title: 'Vertreteransicht öffnen',
                desc: 'So sehen Vertriebsteams die Inhalte: sofortige Vorschau in einem neuen Fenster.',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Vertreter-Wiki Vorschau')),
                      body: RepWikiListPage(api: widget.api),
                    ),
                  ),
                ),
                footer: Wrap(
                  spacing: 8,
                  children: const [
                    Chip(label: Text('Live-Vorschau')),
                    Chip(label: Text('Responsiv')),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNewsPanel() {
    final dateFmt = DateFormat('dd.MM.yyyy HH:mm');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.campaign_outlined),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Neuigkeiten & Infoscreen',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
            const SizedBox(height: 8),
            Expanded(
              child: _newsEntries.isEmpty && !_newsLoading
                  ? const Center(child: Text('Noch keine Neuigkeiten hinterlegt.'))
                  : ListView.builder(
                      itemCount: _newsEntries.length,
                      itemBuilder: (_, index) => _buildNewsAdminCard(_newsEntries[index], dateFmt),
                    ),
            ),
          ],
        ),
      ),
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

  Widget _buildFaqPanel() {
    final theme = Theme.of(context);
    final filteredCategories = (_faqShowInactive
            ? _faqCategories
            : _faqCategories.where((c) => c.active))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    final query = _faqSearch.trim().toLowerCase();
    final lang = normalizeLangCode(Localizations.localeOf(context).languageCode);
    final filteredEntries = _faqEntries.where((e) {
      if (!_faqShowInactive && !e.active) return false;
      if (_faqCategoryFilter != null && _faqCategoryFilter!.isNotEmpty) {
        if (e.categoryId != _faqCategoryFilter) return false;
      }
      if (_faqAudienceFilter != 'both') {
        final a = e.audience.isEmpty ? 'both' : e.audience;
        if (a != 'both' && a != _faqAudienceFilter) return false;
      }
      if (query.isNotEmpty) {
        final q = e.localizedQuestion(lang).toLowerCase();
        final a = e.localizedAnswer(lang).toLowerCase();
        if (!q.contains(query) && !a.contains(query)) return false;
      }
      if (!_faqShowInactive) {
        final exists = filteredCategories.any((c) => c.id == e.categoryId);
        if (!exists) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final cmp = a.order.compareTo(b.order);
        if (cmp != 0) return cmp;
        return a.localizedQuestion(lang).compareTo(b.localizedQuestion(lang));
      });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.library_books_outlined),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Wissensdatenbank (FAQ)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Neu laden',
                  onPressed: _faqLoading ? null : _refreshFaq,
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 6),
                FilledButton.tonalIcon(
                  onPressed: () => _openFaqCategoryEditor(),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Kategorie'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _faqCategories.isEmpty
                      ? null
                      : () => _openFaqEntryEditor(),
                  icon: const Icon(Icons.post_add_outlined),
                  label: const Text('Artikel'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_faqLoading) const LinearProgressIndicator(),
            if (_faqErr != null) ...[
              const SizedBox(height: 8),
              Text('Fehler: $_faqErr', style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 12),
            _buildFaqFilters(theme, filteredCategories, lang),
            const SizedBox(height: 20),
            Row(
              children: [
                Text(
                  'Kategorien (${filteredCategories.length})',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _faqShowCategories = !_faqShowCategories),
                  icon: Icon(_faqShowCategories ? Icons.visibility_off : Icons.visibility),
                  label: Text(_faqShowCategories ? 'Ausblenden' : 'Einblenden'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_faqShowCategories)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: filteredCategories.isEmpty
                    ? [const Text('Keine Kategorien hinterlegt.')]
                    : filteredCategories.map((cat) => _buildFaqCategoryChip(cat, lang)).toList(),
              ),
            const SizedBox(height: 16),
            Text(
              'Artikel (${filteredEntries.length})',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filteredEntries.isEmpty
                  ? _buildFaqEmptyState(theme)
                  : ListView.builder(
                      itemCount: filteredEntries.length,
                      itemBuilder: (_, idx) {
                        final entry = filteredEntries[idx];
                        return _buildFaqEntryCard(entry, theme);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFaqFilters(ThemeData theme, List<FaqCategory> categories, String lang) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilterChip(
            label: Text(_faqShowInactive ? 'Aktive anzeigen' : 'Inaktive anzeigen'),
            selected: _faqShowInactive,
            onSelected: (v) => setState(() => _faqShowInactive = v),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            avatar: Icon(
              _faqShowInactive ? Icons.visibility : Icons.visibility_off,
              size: 18,
            ),
          ),
          _buildFilterDropdown<String>(
            label: 'Zielgruppe',
            value: _faqAudienceFilter,
            items: const [
              DropdownMenuItem(value: 'both', child: Text('Alle Zielgruppen')),
              DropdownMenuItem(value: 'customer', child: Text('Nur Kunden')),
              DropdownMenuItem(value: 'rep', child: Text('Nur Reps')),
            ],
            onChanged: (v) => setState(() => _faqAudienceFilter = v ?? 'both'),
          ),
          _buildFilterDropdown<String?>(
            label: 'Kategorie',
            value: _faqCategoryFilter,
            hint: 'Alle Kategorien',
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Alle Kategorien'),
              ),
              ...categories.map(
                (c) => DropdownMenuItem<String?>(
                  value: c.id,
                  child: Text(c.localizedTitle(lang)),
                ),
              ),
            ],
            onChanged: (v) => setState(() => _faqCategoryFilter = v),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 240, maxWidth: 300),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Suche in Frage / Antwort',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _faqSearch = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    String? hint,
    required void Function(T?) onChanged,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 220),
      child: DropdownButtonFormField<T>(
        value: value,
        items: items,
        isDense: true,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildFaqCategoryChip(FaqCategory cat, String lang) {
    final label = '${cat.localizedTitle(lang)}${cat.active ? '' : ' (inaktiv)'}';
    return InputChip(
      label: Text(label),
      avatar: const Icon(Icons.folder_open, size: 18),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 10),
      onPressed: () => _openFaqCategoryEditor(cat),
      onDeleted: () => _confirmDeleteCategory(cat),
    );
  }

  Widget _buildFaqEmptyState(ThemeData theme) {
    final t = AppLocalizations.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(theme.brightness == Brightness.dark ? 0.25 : 0.45),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Keine FAQ-Einträge vorhanden',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Wir haben noch keine Datensätze im neuen Admin-FAQ-Store gefunden.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Tipp: Du kannst die bestehende Wissensdatenbank aus der App automatisch übernehmen.',
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.primary),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _faqSeeding ? null : _seedFaqFromLegacyKnowledgeBase,
                  icon: _faqSeeding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.import_contacts_outlined),
                  label: Text(
                    'Wissensdatenbank importieren (${KnowledgeCategory.values.length} Kategorien / ${knowledgeItems.length} Einträge)'
                        .trim(),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _faqSeeding ? null : _refreshFaq,
                  child: const Text('Neu laden'),
                ),
              ],
            ),
            if (_faqSeedErr != null) ...[
              const SizedBox(height: 10),
              Text(
                _faqSeedErr!,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ],
            if (t != null) ...[
              const SizedBox(height: 12),
              Text(
                'Aktuelle Inhalte (Auszug):',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              ...knowledgeItems.take(3).map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• ${item.question(t)}'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFaqEntryCard(FaqEntry entry, ThemeData theme) {
    final catName = _faqCategoryName(entry.categoryId);
    final lang = normalizeLangCode(Localizations.localeOf(context).languageCode);
    final question = entry.localizedQuestion(lang);
    final answer = entry.localizedAnswer(lang);
    final chips = <Widget>[
      Chip(label: Text(catName)),
      Chip(label: Text(_faqAudienceLabel(entry.audience))),
      if (!entry.active) const Chip(label: Text('Inaktiv')),
    ];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        question,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(spacing: 6, runSpacing: 6, children: chips),
                      const SizedBox(height: 8),
                      Text(answer),
                    ],
                  ),
                ),
                Column(
                  children: [
                    IconButton(
                      tooltip: 'Bearbeiten',
                      onPressed: () => _openFaqEntryEditor(entry),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Löschen',
                      onPressed: () => _confirmDeleteEntry(entry),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteCategory(FaqCategory category) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kategorie löschen?'),
        content: Text('"${category.title}" und alle zugehörigen Einträge entfernen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteFaqCategory(category.id);
      await _refreshFaq();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Löschen: $e')),
      );
    }
  }

  Future<void> _confirmDeleteEntry(FaqEntry entry) async {
    final lang = normalizeLangCode(Localizations.localeOf(context).languageCode);
    final title = entry.localizedQuestion(lang);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eintrag löschen?'),
        content: Text('"$title" entfernen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteFaqEntry(entry.id);
      await _refreshFaq();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Löschen: $e')),
      );
    }
  }

  Future<void> _openFaqCategoryEditor([FaqCategory? category]) async {
    final lang = normalizeLangCode(Localizations.localeOf(context).languageCode);
    final titleCtrls = <String, TextEditingController>{};
    final descCtrls = <String, TextEditingController>{};
    for (final lc in supportedLangCodes) {
      final title = category == null ? '' : category.localizedTitle(lc);
      final desc = category == null ? '' : category.localizedDescription(lc);
      titleCtrls[lc] = TextEditingController(text: title);
      descCtrls[lc] = TextEditingController(text: desc);
    }
    final orderCtrl = TextEditingController(text: category?.order.toString() ?? '0');
    bool active = category?.active ?? true;
    String translateSource = lang;
    bool translating = false;
    String? translateErr;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(category == null ? 'Kategorie anlegen' : 'Kategorie bearbeiten'),
        content: StatefulBuilder(
          builder: (ctx, setModalState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Kategoriename und Beschreibung in allen Sprachen',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                ...supportedLangCodes.expand((lc) sync* {
                  final langLabel = langNameFor(AppLocalizations.of(context), lc);
                  yield Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('${lc.toUpperCase()} – $langLabel',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                  );
                  yield const SizedBox(height: 4);
                  yield TextField(
                    controller: titleCtrls[lc],
                    decoration: InputDecoration(labelText: 'Titel (${lc.toUpperCase()})'),
                  );
                  yield const SizedBox(height: 6);
                  yield TextField(
                    controller: descCtrls[lc],
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: 'Beschreibung (${lc.toUpperCase()}, optional)'),
                  );
                }),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Automatisch übersetzen von:'),
                      DropdownButton<String>(
                        value: translateSource,
                        items: supportedLangCodes
                            .map(
                              (lc) => DropdownMenuItem(
                                value: lc,
                                child: Text('${lc.toUpperCase()} – ${langNameFor(AppLocalizations.of(context), lc)}'),
                              ),
                            )
                            .toList(),
                        onChanged: translating
                            ? null
                            : (v) {
                                if (v == null || v.isEmpty) return;
                                setModalState(() => translateSource = v);
                              },
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.auto_mode),
                        label: Text(translating ? 'Übersetze…' : 'Alle Sprachen automatisch ausfüllen'),
                        onPressed: translating
                            ? null
                            : () async {
                                final baseTitle = titleCtrls[translateSource]?.text.trim() ?? '';
                                final baseDesc = descCtrls[translateSource]?.text.trim() ?? '';
                                if (baseTitle.isEmpty && baseDesc.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Bitte zuerst Titel oder Beschreibung in der Quellsprache eingeben.')),
                                  );
                                  return;
                                }

                                setModalState(() {
                                  translating = true;
                                  translateErr = null;
                                });

                                try {
                                  final translations = await _api.translateFaqDraft(
                                    sourceLang: translateSource,
                                    targetLangs: supportedLangCodes.where((lc) => lc != translateSource).toList(),
                                    title: baseTitle,
                                    description: baseDesc,
                                  );

                                  translations.forEach((lc, fields) {
                                    if (lc == translateSource) return;
                                    final t = (fields['title'] ?? '').trim();
                                    final d = (fields['description'] ?? '').trim();
                                    if (t.isNotEmpty && titleCtrls.containsKey(lc)) {
                                      titleCtrls[lc]!.text = t;
                                    }
                                    if (d.isNotEmpty && descCtrls.containsKey(lc)) {
                                      descCtrls[lc]!.text = d;
                                    }
                                  });

                                  if (translations.isNotEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Übersetzungen für ${translations.length} Sprachen eingefügt.')),
                                    );
                                  }
                                } catch (e) {
                                  setModalState(() {
                                    translateErr = e.toString();
                                  });
                                } finally {
                                  if (ctx.mounted) {
                                    setModalState(() {
                                      translating = false;
                                    });
                                  }
                                }
                              },
                      ),
                      if (translateErr != null)
                        Text(
                          translateErr!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: orderCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Reihenfolge (Zahl, optional)'),
                ),
                Row(
                  children: [
                    Switch(value: active, onChanged: (v) => setModalState(() => active = v)),
                    Text(active ? 'Aktiv' : 'Inaktiv'),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () async {
              final titles = <String, String>{};
              final descriptions = <String, String>{};
              for (final lc in supportedLangCodes) {
                final t = titleCtrls[lc]?.text.trim() ?? '';
                final d = descCtrls[lc]?.text.trim() ?? '';
                if (t.isNotEmpty) titles[lc] = t;
                if (d.isNotEmpty) descriptions[lc] = d;
              }

              if (titles.length != supportedLangCodes.length) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Bitte alle Sprachen mit Titel ausfüllen.')),
                );
                return;
              }

              final order = int.tryParse(orderCtrl.text.trim());
              final primaryTitle = titles[translateSource] ?? titles['de'] ?? titles.values.first;
              final primaryDescription = descriptions[translateSource] ?? descriptions['de'];

              try {
                final saved = await _api.saveFaqCategory(
                  id: category?.id,
                  title: primaryTitle,
                  titleIntl: titles,
                  description: primaryDescription?.isEmpty == true ? null : primaryDescription,
                  descriptionIntl: descriptions,
                  order: order,
                  active: active,
                  primaryLang: translateSource,
                );
                if (!mounted) return;
                setState(() {
                  final next = [..._faqCategories];
                  final idx = next.indexWhere((c) => c.id == saved.id);
                  if (idx >= 0) {
                    next[idx] = saved;
                  } else {
                    next.add(saved);
                  }
                  _faqCategories = next;
                });
                Navigator.of(context).pop();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Fehler: $e')),
                );
              }
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    for (final ctrl in [...titleCtrls.values, ...descCtrls.values]) {
      ctrl.dispose();
    }
    orderCtrl.dispose();
  }

  Future<void> _openFaqEntryEditor([FaqEntry? entry]) async {
    if (_faqCategories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte zuerst eine Kategorie anlegen.')),
      );
      return;
    }

    final lang = normalizeLangCode(Localizations.localeOf(context).languageCode);
    final questionCtrls = <String, TextEditingController>{};
    final answerCtrls = <String, TextEditingController>{};
    for (final lc in supportedLangCodes) {
      final qText = entry == null ? '' : entry.localizedQuestion(lc);
      final aText = entry == null ? '' : entry.localizedAnswer(lc);
      questionCtrls[lc] = TextEditingController(text: qText);
      answerCtrls[lc] = TextEditingController(text: aText);
    }
    final orderCtrl = TextEditingController(text: entry == null || entry.order == 0 ? '' : entry.order.toString());
    String audience = entry?.audience.isNotEmpty == true ? entry!.audience : 'both';
    String categoryId = entry?.categoryId ?? _faqCategories.first.id;
    bool active = entry?.active ?? true;
    String previewLang = lang;
    String translateSource = lang;
    bool translating = false;
    String? translateErr;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(entry == null ? 'FAQ-Eintrag anlegen' : 'FAQ-Eintrag bearbeiten'),
        content: StatefulBuilder(
          builder: (ctx, setModalState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: categoryId,
                  items: _faqCategories
                      .map(
                        (c) => DropdownMenuItem<String>(
                          value: c.id,
                          child: Text(c.localizedTitle(lang)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setModalState(() => categoryId = v ?? categoryId),
                  decoration: const InputDecoration(labelText: 'Kategorie'),
                ),
                DropdownButtonFormField<String>(
                  value: audience,
                  items: const [
                    DropdownMenuItem(value: 'both', child: Text('Kunden & Reps')),
                    DropdownMenuItem(value: 'customer', child: Text('Nur Kunden')),
                    DropdownMenuItem(value: 'rep', child: Text('Nur Reps')),
                  ],
                  onChanged: (v) => setModalState(() => audience = v ?? 'both'),
                  decoration: const InputDecoration(labelText: 'Zielgruppe'),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Fragen und Antworten in allen Sprachen',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                ...supportedLangCodes.expand((lc) sync* {
                  final langLabel = langNameFor(AppLocalizations.of(context), lc);
                  yield Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('${lc.toUpperCase()} – $langLabel',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                  );
                  yield const SizedBox(height: 4);
                  yield TextField(
                    controller: questionCtrls[lc],
                    maxLines: 2,
                    decoration: InputDecoration(labelText: 'Frage (${lc.toUpperCase()})'),
                  );
                  yield const SizedBox(height: 6);
                  yield TextField(
                    controller: answerCtrls[lc],
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(labelText: 'Antwort (${lc.toUpperCase()})'),
                  );
                }),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Automatisch übersetzen von:'),
                      DropdownButton<String>(
                        value: translateSource,
                        items: supportedLangCodes
                            .map(
                              (lc) => DropdownMenuItem(
                                value: lc,
                                child: Text('${lc.toUpperCase()} – ${langNameFor(AppLocalizations.of(context), lc)}'),
                              ),
                            )
                            .toList(),
                        onChanged: translating
                            ? null
                            : (v) {
                                if (v == null || v.isEmpty) return;
                                setModalState(() => translateSource = v);
                              },
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.auto_mode),
                        label: Text(translating ? 'Übersetze…' : 'Alle Sprachen automatisch ausfüllen'),
                        onPressed: translating
                            ? null
                            : () async {
                                final baseQ = questionCtrls[translateSource]?.text.trim() ?? '';
                                final baseA = answerCtrls[translateSource]?.text.trim() ?? '';
                                if (baseQ.isEmpty && baseA.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Bitte zunächst Frage oder Antwort in der Quellsprache eingeben.')),
                                  );
                                  return;
                                }

                                setModalState(() {
                                  translating = true;
                                  translateErr = null;
                                });

                                try {
                                  final translations = await _api.translateFaqDraft(
                                    sourceLang: translateSource,
                                    targetLangs:
                                        supportedLangCodes.where((lc) => lc != translateSource).toList(),
                                    question: baseQ,
                                    answer: baseA,
                                  );

                                  translations.forEach((lc, fields) {
                                    if (lc == translateSource) return;
                                    final q = (fields['question'] ?? '').trim();
                                    final a = (fields['answer'] ?? '').trim();
                                    if (q.isNotEmpty && questionCtrls.containsKey(lc)) {
                                      questionCtrls[lc]!.text = q;
                                    }
                                    if (a.isNotEmpty && answerCtrls.containsKey(lc)) {
                                      answerCtrls[lc]!.text = a;
                                    }
                                  });

                                  if (translations.isNotEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Übersetzungen für ${translations.length} Sprachen eingefügt.')),
                                    );
                                  }
                                } catch (e) {
                                  setModalState(() {
                                    translateErr = e.toString();
                                  });
                                } finally {
                                  if (ctx.mounted) {
                                    setModalState(() {
                                      translating = false;
                                    });
                                  }
                                }
                              },
                      ),
                      if (translating)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          ),
                        ),
                    ],
                  ),
                ),
                if (translateErr != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        translateErr!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Live-Vorschau für Sprache:'),
                      DropdownButton<String>(
                        value: previewLang,
                        items: supportedLangCodes
                            .map(
                              (lc) => DropdownMenuItem(
                                value: lc,
                                child: Text('${lc.toUpperCase()} – ${langNameFor(AppLocalizations.of(context), lc)}'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null || v.isEmpty) return;
                          setModalState(() => previewLang = v);
                        },
                      ),
                      _TextFormatChip(
                        icon: Icons.format_bold,
                        label: 'Fett',
                        onTap: () => _applyTextFormat(
                          answerCtrls[previewLang]!,
                          prefix: '**',
                          suffix: '**',
                          placeholder: 'fetter Text',
                        ),
                      ),
                      _TextFormatChip(
                        icon: Icons.format_italic,
                        label: 'Kursiv',
                        onTap: () => _applyTextFormat(
                          answerCtrls[previewLang]!,
                          prefix: '_',
                          suffix: '_',
                          placeholder: 'kursiver Text',
                        ),
                      ),
                      _TextFormatChip(
                        icon: Icons.format_underline,
                        label: 'Unterstrichen',
                        onTap: () => _applyTextFormat(
                          answerCtrls[previewLang]!,
                          prefix: '<u>',
                          suffix: '</u>',
                          placeholder: 'unterstrichen',
                        ),
                      ),
                      _TextFormatChip(
                        icon: Icons.format_color_fill,
                        label: 'Markieren',
                        onTap: () => _applyTextFormat(
                          answerCtrls[previewLang]!,
                          prefix: '<mark>',
                          suffix: '</mark>',
                          placeholder: 'markierter Text',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: answerCtrls[previewLang]!,
                  builder: (_, value, __) {
                    final previewText = value.text.trim().isEmpty
                        ? '_(Noch keine Antwort eingegeben)_'
                        : value.text;
                    final theme = Theme.of(context);
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withOpacity(0.6),
                        ),
                      ),
                      child: MarkdownBody(
                        data: previewText,
                        softLineBreak: true,
                        extensionSet: md.ExtensionSet.gitHubFlavored,
                        inlineSyntaxes: [
                          _UnderlineTagSyntax(),
                          _MarkTagSyntax(),
                        ],
                        selectable: true,
                        styleSheet: MarkdownStyleSheet(
                          p: theme.textTheme.bodyMedium,
                          strong: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          em: theme.textTheme.bodyMedium?.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        builders: {
                          'u': _UnderlineMarkdownBuilder(theme.textTheme.bodyMedium),
                          'mark': _MarkMarkdownBuilder(
                            theme.colorScheme.tertiaryContainer,
                            theme.colorScheme.onTertiaryContainer,
                            theme.textTheme.bodyMedium,
                          ),
                        },
                      ),
                    );
                  },
                ),
                TextField(
                  controller: orderCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Reihenfolge (Zahl, optional)'),
                ),
                Row(
                  children: [
                    Switch(value: active, onChanged: (v) => setModalState(() => active = v)),
                    Text(active ? 'Aktiv' : 'Inaktiv'),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () async {
              final questions = <String, String>{};
              final answers = <String, String>{};
              for (final lc in supportedLangCodes) {
                final q = questionCtrls[lc]?.text.trim() ?? '';
                final a = answerCtrls[lc]?.text.trim() ?? '';
                if (q.isNotEmpty) questions[lc] = q;
                if (a.isNotEmpty) answers[lc] = a;
              }

              if (questions.length != supportedLangCodes.length || answers.length != supportedLangCodes.length) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Bitte alle Sprachen mit Frage und Antwort ausfüllen.')),
                );
                return;
              }

              final order = int.tryParse(orderCtrl.text.trim().isEmpty ? '' : orderCtrl.text.trim());
              final question = questions[lang] ?? questions['de'] ?? questions.values.first;
              final answer = answers[lang] ?? answers['de'] ?? answers.values.first;
              try {
                final saved = await _api.saveFaqEntry(
                  id: entry?.id,
                  categoryId: categoryId,
                  question: question,
                  answer: answer,
                  questionIntl: questions,
                  answerIntl: answers,
                  audience: audience,
                  order: order,
                  active: active,
                );
                if (!mounted) return;
                setState(() {
                  final next = [..._faqEntries];
                  final idx = next.indexWhere((e) => e.id == saved.id);
                  if (idx >= 0) {
                    next[idx] = saved;
                  } else {
                    next.add(saved);
                  }
                  _faqEntries = next;
                });
                Navigator.of(context).pop();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Fehler: $e')),
                );
              }
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    for (final ctrl in questionCtrls.values) {
      ctrl.dispose();
    }
    for (final ctrl in answerCtrls.values) {
      ctrl.dispose();
    }
    orderCtrl.dispose();
  }

  void _applyTextFormat(
    TextEditingController controller, {
    required String prefix,
    required String suffix,
    required String placeholder,
  }) {
    final text = controller.text;
    final selection = controller.selection;
    int start = selection.start;
    int end = selection.end;

    if (start < 0 || end < 0) {
      start = end = text.length;
    }

    final hasSelection = start != end;
    final selectedText = hasSelection ? text.substring(start, end) : placeholder;

    final newText = text.replaceRange(start, end, '$prefix$selectedText$suffix');
    final newSelectionStart = start + prefix.length;
    final newSelectionEnd = newSelectionStart + selectedText.length;

    controller.value = controller.value.copyWith(
      text: newText,
      selection: TextSelection(
        baseOffset: newSelectionStart,
        extentOffset: newSelectionEnd,
      ),
      composing: TextRange.empty,
    );
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
                'Kundendatenbank',
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
                
                // Vertreter-Dropdown (KORRIGIERT)
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<String>(
                    value: _userFilterRepId ?? 'Alle Vertreter',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Vertreter',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'Alle Vertreter',        // → repId = null
                        child: Text('Alle Vertreter'),
                      ),
                      const DropdownMenuItem(
                        value: '',                      // → repId = ""  = ohne Vertreter
                        child: Text('Ohne Vertreter'),
                      ),
                      ..._reps.map(
                        (r) => DropdownMenuItem(
                          value: r.id,                  // → repId = r.id
                          child: Text('${r.firstName} ${r.lastName} (${r.region})'),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() {
                        if (v == 'Alle Vertreter') {
                          _userFilterRepId = null;     // kein Vertreterfilter
                        } else {
                          _userFilterRepId = v;        // "" oder r.id
                        }
                      });
                    },
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
                          final repId = _repIdForEmail(u.email);
                          final repBusy = _isRepAssignmentBusy(u.email);
                          return _UserTile(
                            data: u,
                            api: _api,
                            onDelete: () async {
                              final ok = await _confirm(
                                'Kunde löschen',
                                'Soll der Kunde ${u.company} wirklich gelöscht werden?',
                              );
                              if (ok != true) return;
                              try {
                                await _api.deleteUser(u.email);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Kunde gelöscht: ${u.company}'),
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
                            reps: _reps,
                            repBusy: repBusy,
                            assignedRepId: repId,
                            onChangeRep: (value) => _changeUserRep(
                              email: u.email,
                              repId: value,
                            ),
                            onToggleRevoked: (revoked) async {
                              final title = revoked ? 'Kunde sperren' : 'Sperre aufheben';
                              final msg = revoked
                                  ? 'Soll der Zugang für ${u.company} wirklich gesperrt werden?'
                                  : 'Soll der Zugang für ${u.company} wieder freigeschaltet werden?';
                              final ok = await _confirm(title, msg);
                              if (ok != true) return;
                              try {
                                await _api.setUserRevoked(u.email, revoked);
                                if (!mounted) return;
                                final info = revoked
                                    ? 'Account gesperrt: ${u.company}'
                                    : 'Account freigeschaltet: ${u.company}';
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
        ),
      ),
    );
  }

  Widget _buildBulkInternalBar({required bool isOpenList}) {
    final controller = isOpenList ? _bulkInternalOpenCtrl : _bulkInternalAllCtrl;
    final selected = isOpenList ? _selectedOpenTickets : _selectedAllTickets;
    final busy = isOpenList ? _bulkAssigningOpen : _bulkAssigningAll;
    final expanded = isOpenList ? _showBulkAssignOpen : _showBulkAssignAll;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.link_outlined),
                  const SizedBox(width: 8),
                  const Text(
                    'Mehrere Tickets einer internen Nummer zuordnen',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  if (busy)
                    const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              Chip(
                avatar: const Icon(Icons.confirmation_number_outlined, size: 18),
                label:
                    Text('${selected.length} Ticket${selected.length == 1 ? '' : 's'} ausgewählt'),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  if (isOpenList) {
                    _showBulkAssignOpen = !_showBulkAssignOpen;
                  } else {
                    _showBulkAssignAll = !_showBulkAssignAll;
                  }
                }),
                icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                label: Text(expanded ? 'Zuordnung ausblenden' : 'Zuordnung einblenden'),
              ),
            ],
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 240,
                    child: TextField(
                      controller: controller,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Interne Nummer',
                        prefixIcon: const Icon(Icons.tag),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        suffixIcon: controller.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Eingabe leeren',
                                onPressed: busy
                                    ? null
                                    : () {
                                        controller.clear();
                                        setState(() {});
                                      },
                                icon: const Icon(Icons.close),
                              ),
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: busy || selected.isEmpty || controller.text.trim().isEmpty
                        ? null
                        : () => _assignInternalNoBulk(isOpenList: isOpenList),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Interne Nummer zuweisen'),
                  ),
                  TextButton.icon(
                    onPressed: busy || selected.isEmpty
                        ? null
                        : () => _clearTicketSelection(isOpenList: isOpenList),
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Auswahl zurücksetzen'),
                  ),
                ],
              ),
            ),
            crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 150),
          ),
        ],
      ),
    );
  }

  Widget _buildAllComplaintsPanel() {
    final theme = Theme.of(context);

    final companies = <String>{
      'Alle Firmen',
      ..._allComplaints
          .map((c) => (_companyByEmail(c.email) ?? '').trim())
          .where((s) => s.isNotEmpty),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final reps = <String>{
      'Alle Vertreter',
      ..._allComplaints.map(_repLabelForComplaint).where((s) => s.trim().isNotEmpty),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final internalNos = <String>{
      'Alle Nummern',
      ..._allComplaints.map((c) => (c.internalNo ?? '').trim()).where((s) => s.isNotEmpty),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    List<AdminComplaint> list = _allComplaints.where((c) {
      final company = (_companyByEmail(c.email) ?? '').trim();
      final repLabel = _repLabelForComplaint(c).trim();
      final decision = (c.decision ?? '').trim();
      final status = c.status;
      final internal = (c.internalNo ?? '').trim();
      final search = _allSearch.trim().toLowerCase();

      bool matchesQuery() {
        if (search.isEmpty) return true;
        bool contains(Object? v) => v.toString().toLowerCase().contains(search);
        final payloadMatches = (c.payload?.values.any(contains) ?? false);
        return payloadMatches ||
            contains(c.ticket) ||
            contains(c.email) ||
            contains(company) ||
            contains(repLabel) ||
            contains(decision) ||
            contains(_labelForStatus(status)) ||
            contains(c.handlingLabel) ||
            contains(c.adminNotes ?? '') ||
            contains(internal);
      }

      final companyMatch = _allCompanyFilter == 'Alle Firmen'
          ? true
          : company.toLowerCase() == _allCompanyFilter.toLowerCase();
      final repMatch = _allRepFilter == 'Alle Vertreter'
          ? true
          : repLabel.toLowerCase() == _allRepFilter.toLowerCase();
      final decisionMatch = _allDecisionFilter.isEmpty || decision == _allDecisionFilter;
      final statusMatch = _allStatusFilter == null || status == _allStatusFilter;
      final internalMatch = _allInternalFilter == 'Alle Nummern'
          ? true
          : internal == _allInternalFilter;

      return matchesQuery() && companyMatch && repMatch && decisionMatch && statusMatch && internalMatch;
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    Widget buildFilterBar() {
      Widget buildMoreFilters() {
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String>(
                  value: _allCompanyFilter,
                  isExpanded: true,
                  items: companies
                      .map((c) => DropdownMenuItem<String>(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _allCompanyFilter = v ?? 'Alle Firmen'),
                  decoration: const InputDecoration(
                    labelText: 'Kunden (Firmenname)',
                    prefixIcon: Icon(Icons.apartment_outlined),
                  ),
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  value: _allRepFilter,
                  items: reps
                      .map((r) => DropdownMenuItem<String>(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => setState(() => _allRepFilter = v ?? 'Alle Vertreter'),
                  decoration: const InputDecoration(
                    labelText: 'Vertreter',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  value: _allDecisionFilter,
                  items: [
                    const DropdownMenuItem<String>(value: '', child: Text('Alle Entscheidungen')),
                    ...kDecisionItems.map((d) => DropdownMenuItem<String>(
                          value: d['value']!,
                          child: Text(d['label']!),
                        )),
                  ],
                  onChanged: (v) => setState(() => _allDecisionFilter = v ?? ''),
                  decoration: const InputDecoration(
                    labelText: 'Entscheidungen',
                    prefixIcon: Icon(Icons.how_to_vote_outlined),
                  ),
                ),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<int?>(
                  value: _allStatusFilter,
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Alle Stati')),
                    ...kStatusItems.map((s) => DropdownMenuItem<int?>(
                          value: s['value'] as int,
                          child: Text(s['label'] as String),
                        )),
                  ],
                  onChanged: (v) => setState(() => _allStatusFilter = v),
                  decoration: const InputDecoration(
                    labelText: 'Stati',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  value: _allInternalFilter,
                  items: internalNos
                      .map((n) => DropdownMenuItem<String>(value: n, child: Text(n.isEmpty ? '—' : n)))
                      .toList(),
                  onChanged: (v) => setState(() => _allInternalFilter = v ?? 'Alle Nummern'),
                  decoration: const InputDecoration(
                    labelText: 'Interne Reklamationsnummer',
                    prefixIcon: Icon(Icons.confirmation_number_outlined),
                  ),
                ),
              ),
            ],
          ),
        );
      }

      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  SizedBox(
                    width: 320,
                    child: TextField(
                      onChanged: (v) => setState(() => _allSearch = v),
                      decoration: InputDecoration(
                        labelText: 'Schnellsuche (Ticket, Kunde, Stichwort …)',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _showAllFilters = !_showAllFilters),
                    icon: Icon(_showAllFilters ? Icons.expand_less : Icons.expand_more),
                    label: Text(_showAllFilters ? 'Filter ausblenden' : 'Weitere Filter'),
                  ),
                ],
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: buildMoreFilters(),
                crossFadeState:
                    _showAllFilters ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 150),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.dashboard_customize_outlined),
                const SizedBox(width: 8),
                const Text('Alle Reklamationen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${list.length} gefiltert',
                      style: TextStyle(color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                if (_loadAllComplaints)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                IconButton(
                  tooltip: 'Neu laden',
                  onPressed: _loadAllComplaints ? null : _refreshAllComplaints,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 10),
            buildFilterBar(),
            const SizedBox(height: 10),
            _buildBulkInternalBar(isOpenList: false),
            const SizedBox(height: 6),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Keine Reklamationen gefunden.'))
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final c = list[i];
                        return _ComplaintEditor(
                          key: ValueKey('complaint-${c.ticket}'),
                          api: _api,
                          c: c,
                          productLookup: _productByArticle,
                          companyHint: _companyByEmail(c.email),
                          hasRep: _customerHasRep(c.email),
                          selectable: true,
                          selected: _selectedAllTickets.contains(c.ticket),
                          onSelected: (v) =>
                              _toggleTicketSelection(c.ticket, v ?? false, isOpenList: false),
                          onChanged: _syncComplaint,
                          onClosed: () {
                            _syncComplaint(c);
                            setState(() {
                              _openComplaints.removeWhere((x) => x.ticket == c.ticket);
                              _selectedAllTickets.remove(c.ticket);
                              _selectedOpenTickets.remove(c.ticket);
                            });
                            _refreshAllComplaints();
                            _refreshOpen();
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

  Widget _buildProductsPanel() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ProductCatalogPage(
        products: _products,
        loading: _productsLoading,
        error: _productErr,
        onReload: _productsLoading ? null : _loadProducts,
        onProductsChanged: (items) => setState(() => _applyProducts(items)),
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
            _buildBulkInternalBar(isOpenList: true),
            const SizedBox(height: 6),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Keine offenen Reklamationen.'))
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final c = list[i];
                        return _ComplaintEditor(
                          key: ValueKey('complaint-${c.ticket}'),
                          api: _api,
                          c: c,
                          productLookup: _productByArticle,
                          companyHint: _companyByEmail(c.email),
                          hasRep: _customerHasRep(c.email), // ← NEU
                          selectable: true,
                          selected: _selectedOpenTickets.contains(c.ticket),
                          onSelected: (v) =>
                              _toggleTicketSelection(c.ticket, v ?? false, isOpenList: true),
                          onChanged: _syncComplaint,
                          onClosed: () {
                            _syncComplaint(c);
                            setState(() {
                              _openComplaints.removeWhere((x) => x.ticket == c.ticket);
                              _selectedOpenTickets.remove(c.ticket);
                              _selectedAllTickets.remove(c.ticket);
                            });
                            _refreshAllComplaints();
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

  Future<bool> _saveRep({String? id}) async {
    if (_repBusy) return false;
    if (!mounted) return false;

    setState(() => _repBusy = true);
    var success = false;
    try {
      final rep = await _api.upsertRep(
        id: id,
        firstName: _repFirstCtrl.text.trim(),
        lastName:  _repLastCtrl.text.trim(),
        email:     _repMailCtrl.text.trim(),
        region:    _repRegion,
        lang:      _repLang,
      );

      _repFirstCtrl.clear();
      _repLastCtrl.clear();
      _repMailCtrl.clear();
      _repRegion = _repRegionOptions.first;
      _repLang = 'de';

      await _refreshReps();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gespeichert: ${rep.displayName}')),
        );
      }
      success = true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _repBusy = false);
    }

    return success;
  }

  Future<void> _editRep(Rep r) async {
    _repFirstCtrl.text = r.firstName;
    _repLastCtrl.text  = r.lastName;
    _repMailCtrl.text  = r.email;
    _repRegion         = r.region.isNotEmpty ? r.region : _repRegionOptions.first;
    _repLang           = r.lang.isNotEmpty ? r.lang : 'de';

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
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _repRegion,
                      decoration: const InputDecoration(labelText: 'Länderbereich'),
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
                      onPressed: _promptCustomRegion,
                      icon: const Icon(Icons.add),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _repLang,
                decoration: const InputDecoration(labelText: 'Korrespondenzsprache'),
                items: supportedLangCodes
                    .map((code) => DropdownMenuItem<String>(
                          value: code,
                          child: Text(_langLabel(code)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _repLang = v ?? 'de'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _saveRep(id: r.id);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteRep(Rep r) async {
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gelöscht: ${r.displayName}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e')),
          );
        }
      }
    }
  }

  Future<void> _openCreateRepSheet() async {
    _repFirstCtrl.clear();
    _repLastCtrl.clear();
    _repMailCtrl.clear();
    setState(() {
      _repRegion = _repRegionOptions.first;
      _repLang   = 'de';
    });

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
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _repLang,
                    decoration: const InputDecoration(
                      labelText: 'Korrespondenzsprache',
                      border: OutlineInputBorder(),
                    ),
                    items: supportedLangCodes
                        .map((code) => DropdownMenuItem<String>(
                              value: code,
                              child: Text(_langLabel(code)),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _repLang = v ?? 'de'),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.person_add_alt_1),
                      onPressed: _repBusy
                          ? null
                          : () async {
                              final ok = await _saveRep();
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
    var currentRep = rep;
    final Map<String, String> emailAssignedToRepId = {};
    for (final r in _reps) {
      for (final e in r.customers) {
        emailAssignedToRepId[e] ??= r.id;
      }
    }

    var assignedGlobal = emailAssignedToRepId.keys.toSet();

    final allUserEmails = _users.map((u) => u.email.trim()).where((e) => e.isNotEmpty).toSet();
    final all = allUserEmails.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

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

            final otherRepId = emailAssignedToRepId[selEmail!];
            if (otherRepId != null && otherRepId != currentRep.id) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Dieser Kunde ist bereits einem anderen Vertreter zugewiesen.')),
              );
              return;
            }

            setLocal(() => busy = true);
            try {
              final customers = await _api.assignCustomerToRep(repId: currentRep.id, email: selEmail!.trim());
              Rep? updatedRep;

              setState(() {
                final idx = _reps.indexWhere((x) => x.id == currentRep.id);
                if (idx >= 0) {
                  updatedRep = Rep(
                    id: _reps[idx].id,
                    firstName: _reps[idx].firstName,
                    lastName: _reps[idx].lastName,
                    email: _reps[idx].email,
                    region: _reps[idx].region,
                    lang: _reps[idx].lang,
                    customers: customers,
                  );
                  _reps[idx] = updatedRep!;
                }
              });

              await _refreshReps();

              final refreshedRep = _reps.firstWhere(
                (x) => x.id == currentRep.id,
                orElse: () => updatedRep ?? currentRep,
              );

              emailAssignedToRepId
                ..clear()
                ..addEntries(_reps.expand((r) => r.customers.map((e) => MapEntry(e, r.id))));
              assignedGlobal = emailAssignedToRepId.keys.toSet();

              selEmail = all.firstWhere(
                (e) => !assignedGlobal.contains(e),
                orElse: () => '',
              );
              if ((selEmail ?? '').isEmpty) selEmail = null;

              setLocal(() {
                currentRep = refreshedRep;
                busy = false;
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
              final customers = await _api.unassignCustomerFromRep(repId: currentRep.id, email: email);
              Rep? updatedRep;

              setState(() {
                final idx = _reps.indexWhere((x) => x.id == currentRep.id);
                if (idx >= 0) {
                  updatedRep = Rep(
                    id: _reps[idx].id,
                    firstName: _reps[idx].firstName,
                    lastName: _reps[idx].lastName,
                    email: _reps[idx].email,
                    region: _reps[idx].region,
                    lang: _reps[idx].lang,
                    customers: customers,
                  );
                  _reps[idx] = updatedRep!;
                }
              });

              await _refreshReps();

              final refreshedRep = _reps.firstWhere(
                (x) => x.id == currentRep.id,
                orElse: () => updatedRep ?? currentRep,
              );

              emailAssignedToRepId
                ..clear()
                ..addEntries(_reps.expand((r) => r.customers.map((e) => MapEntry(e, r.id))));
              assignedGlobal = emailAssignedToRepId.keys.toSet();

              if (selEmail != null && assignedGlobal.contains(selEmail)) {
                selEmail = all.firstWhere(
                  (e) => !assignedGlobal.contains(e),
                  orElse: () => '',
                );
                if ((selEmail ?? '').isEmpty) selEmail = null;
              }

              setLocal(() {
                currentRep = refreshedRep;
                busy = false;
              });
            } catch (e) {
              setLocal(() => busy = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
              }
            }
          }

          return AlertDialog(
            title: Text('Kunden für ${currentRep.displayName}'),
            content: SizedBox(
              width: 620,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.25),
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: (currentRep.customers.isEmpty)
                        ? const Center(child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('Keine Kunden zugewiesen.'),
                          ))
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: currentRep.customers.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final email = currentRep.customers[i];
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
                            labelText: 'Kunde (Firma)',
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
                        ),
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

  Widget _buildRepsPanel() {
    // kleine Helper zum Mail-Schreiben
    void _composeMail(String to, {String? subject, String? body}) {
      if (to.trim().isEmpty) return;
      final url = 'mailto:$to'
          '?subject=${Uri.encodeComponent(subject ?? 'Anfrage / DFS-DIAMON')}'
          '&body=${Uri.encodeComponent(body ?? 'Guten Tag,\n\nich melde mich als Ihr Ansprechpartner.\n\nBeste Grüße\nDFS-DIAMON GmbH')}';
      html.window.open(url, '_self');
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
              FilledButton.icon(
                icon: const Icon(Icons.person_add_alt_1_outlined),
                onPressed: _openCreateRepSheet,
                label: const Text('Vertreter anlegen'),
              ),
              const SizedBox(width: 8),
              if (_loadReps)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              IconButton(
                tooltip: 'Neu laden',
                onPressed: _loadReps ? null : _refreshReps,
                icon: const Icon(Icons.refresh),
              ),
            ]),
            const SizedBox(height: 12),

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
                          subtitle: Text('${r.email} • ${r.region} • ${_langLabel(r.lang)} • Kunden: ${r.customers.length}'),
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
                                onPressed: () => _editRep(r),
                              ),
                              IconButton(
                                tooltip: 'Löschen',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _confirmDeleteRep(r),
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

class _NavigationSection extends StatelessWidget {
  const _NavigationSection({
    super.key,
    required this.title,
    required this.children,
    required this.isCompact,
  });

  final String title;
  final List<Widget> children;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtle = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 0 : 4, vertical: isCompact ? 4 : 10),
      child: Column(
        crossAxisAlignment: isCompact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          if (!isCompact)
            Padding(
              padding: const EdgeInsets.only(bottom: 10, left: 2, right: 6),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: subtle,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ...children.expand((child) => [child, SizedBox(height: isCompact ? 6 : 10)]),
        ],
      ),
    );
  }
}

class _FieldConfig {
  const _FieldConfig({required this.child, this.preferredWidth});

  final Widget child;
  final double? preferredWidth;
}

class _AdminFormSection extends StatelessWidget {
  const _AdminFormSection({
    required this.icon,
    required this.title,
    required this.fields,
    this.description,
  });

  final IconData icon;
  final String title;
  final String? description;
  final List<_FieldConfig> fields;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const spacing = 16.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final bool threeColumns = maxWidth >= 1024;
        final bool twoColumns = !threeColumns && maxWidth >= 720;
        final double columnWidth;

        if (threeColumns) {
          columnWidth = (maxWidth - spacing * 2) / 3;
        } else if (twoColumns) {
          columnWidth = (maxWidth - spacing) / 2;
        } else {
          columnWidth = maxWidth;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceVariant.withOpacity(0.32),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (description != null && description!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              description!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: fields.map((field) {
                  double widthForField = columnWidth;
                  if (field.preferredWidth != null) {
                    widthForField = field.preferredWidth!;
                    if (widthForField < columnWidth) {
                      widthForField = columnWidth;
                    }
                    if (widthForField > maxWidth) {
                      widthForField = maxWidth;
                    }
                  }

                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: columnWidth,
                      maxWidth: widthForField,
                    ),
                    child: SizedBox(
                      width: widthForField,
                      child: field.child,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FeatureHighlight extends StatelessWidget {
  const _FeatureHighlight({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color textColor = theme.colorScheme.onPrimaryContainer;
    return Container(
      decoration: BoxDecoration(
        color: textColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
// Navigation (Sidebar)
// ===================================================================
class _AdminNavItem {
  const _AdminNavItem({
    required this.label,
    required this.icon,
    required this.view,
    this.badge,
  });

  final String label;
  final IconData icon;
  final _AdminView view;
  final String? badge;
}

class _AdminNavSection {
  const _AdminNavSection({required this.title, required this.items});

  final String title;
  final List<_AdminNavItem> items;
}

// ===================================================================
// Admin-Menü-Kachel + Busy-Dot (Top-Level Widgets, nicht verschachteln)
// ===================================================================
  class _AdminMenuSectionState {
    const _AdminMenuSectionState({
      required this.title,
      required this.subtitle,
      required this.tileIds,
    });

  final String title;
  final String subtitle;
  final List<String> tileIds;

  _AdminMenuSectionState copy() =>
      _AdminMenuSectionState(title: title, subtitle: subtitle, tileIds: List<String>.from(tileIds));

  _AdminMenuSectionState copyWith({String? title, String? subtitle, List<String>? tileIds}) =>
      _AdminMenuSectionState(
        title: title ?? this.title,
        subtitle: subtitle ?? this.subtitle,
        tileIds: tileIds ?? List<String>.from(this.tileIds),
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'subtitle': subtitle,
        'tiles': tileIds,
      };
}

class _DraggedTile {
  final String tileId;
  final int sectionIndex;

  const _DraggedTile({required this.tileId, required this.sectionIndex});
}

class _DraggedSection {
  final int sectionIndex;

  const _DraggedSection({required this.sectionIndex});
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
    if (onGreen)      label = 'Vertreterentscheidung: akzeptiert';
    else if (onRed)   label = 'Vertreterentscheidung: abgelehnt';
    else              label = 'Vertreterentscheidung: offen';

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
  final String? assignedRepId;
  final List<Rep> reps;
  final bool repBusy;
  final Future<void> Function(String? repId) onChangeRep;
  final Future<void> Function(bool revoked) onToggleRevoked;

  const _UserTile({
    required this.data,
    required this.api,
    required this.onDelete,
    required this.onLoadComplaints,
    required this.complaints,
    required this.onClosedFromEditor,
    required this.onToggleRevoked,
    required this.reps,
    required this.repBusy,
    required this.onChangeRep,
    this.assignedRepId,
    this.repName,
  });

  @override
  State<_UserTile> createState() => _UserTileState();
}

class _UserTileState extends State<_UserTile> {
  bool _expanded = false;
  bool _busy = false; // NEU: für Laden/Speichern Kundennummer

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
            const SizedBox(height: 6),
            _Field(
              label: 'Kundennummer',
              value: (d.customerNumber ?? '').isEmpty
                  ? 'nicht hinterlegt'
                  : (d.customerNumber ?? ''),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  Future<void> _editCustomerNumber() async {
    final d = widget.data;
    final ctrl = TextEditingController(text: d.customerNumber ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kundennummer bearbeiten'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Kundennr.',
              hintText: 'aus ERP-System (abas)',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await widget.api.updateCustomerNumber(
        email: d.email,
        customerNumber: ctrl.text,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kundennummer gespeichert.')),
      );

      // Optional: _refreshAll() im Eltern-Widget – du rufst das ja schon nach Aktionen
      // Hier belassen wir es bei der Info; das nächste Neu-Laden zieht den Wert.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Speichern: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleRevoked() async {
    if (_busy || widget.repBusy) return;
    setState(() => _busy = true);
    try {
      await widget.onToggleRevoked(!widget.data.revoked);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final title = d.company.isNotEmpty ? d.company : d.email;
    final subtitle = d.country.isNotEmpty ? d.country : d.email;

    final hasCustomerNo =
        (d.customerNumber != null && d.customerNumber!.trim().isNotEmpty);

    final tileBusy = _busy || widget.repBusy;

    Widget statusBadge(String text, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        );

    final statusBadges = <Widget>[];
    if (d.revoked) {
      final color = Theme.of(context).colorScheme.error;
      statusBadges.add(statusBadge('Account gesperrt', color));
    }
    if (d.selfDeleted) {
      statusBadges.add(statusBadge('Account durch User gelöscht', Colors.red.shade700));
    }

    return Column(
      children: [
        ListTile(
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle),

              // Vertreter
              if (widget.repName != null &&
                  widget.repName!.trim().isNotEmpty) ...[
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

              if (statusBadges.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: statusBadges,
                ),
              ],

              // NEU: Kundennummer-Zeile
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Kundennr.: ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    hasCustomerNo
                        ? d.customerNumber!
                        : 'nicht hinterlegt',
                    style: TextStyle(
                      fontStyle:
                          hasCustomerNo ? FontStyle.normal : FontStyle.italic,
                      color: hasCustomerNo
                          ? null
                          : Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: tileBusy ? null : _editCustomerNumber,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text(
                      'Bearbeiten',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: DropdownButtonFormField<String>(
                          value: widget.assignedRepId ?? '',
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Vertreter zuweisen',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(value: '', child: Text('Kein Vertreter')),
                            ...widget.reps.map(
                              (r) => DropdownMenuItem<String>(
                                value: r.id,
                                child: Text(r.displayName.isNotEmpty ? r.displayName : r.email),
                              ),
                            ),
                          ],
                          onChanged: widget.repBusy
                              ? null
                              : (v) async {
                                  await widget.onChangeRep(v?.trim().isEmpty == true ? null : v);
                                },
                        ),
                      ),
                      if (widget.repBusy) ...[
                        const SizedBox(width: 10),
                        const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          trailing: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: 'Adressdaten',
                onPressed: tileBusy ? null : _showAddress,
                icon: const Icon(Icons.info_outline),
              ),
              IconButton(
                tooltip: 'Reklamationen anzeigen',
                onPressed: () {
                  setState(() => _expanded = !_expanded);
                  if (_expanded) widget.onLoadComplaints();
                },
                icon:
                    Icon(_expanded ? Icons.expand_less : Icons.receipt_long),
              ),
              OutlinedButton.icon(
                onPressed: tileBusy ? null : _toggleRevoked,
                icon: Icon(widget.data.revoked ? Icons.lock_open : Icons.lock_outline),
                label: Text(widget.data.revoked ? 'Freigeben' : 'Sperren'),
              ),
              FilledButton.icon(
                onPressed: tileBusy ? null : () async => widget.onDelete(),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Löschen'),
              ),
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
                    key: ValueKey('complaint-${c.ticket}'),
                    api: api,
                    c: c,
                    productLookup: parent?._productByArticle,
                    onChanged: parent?._syncComplaint,
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

  // NEU:
  final String? customerNumber; // Kundennummer aus ERP

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
    this.customerNumber, // NEU
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
        // NEU: mehrere mögliche Feldnamen abfangen
        customerNumber: j['customerNumber']?.toString() ??
            j['customer_no']?.toString() ??
            null,
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
        customerNumber: null, // NEU
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
  Map<String, dynamic>? payload;
  final List<ComplaintUpload> uploads;
  List<ComplaintHistoryEntry> history;

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
    List<ComplaintHistoryEntry>? history,
    List<ComplaintUpload>? uploads,
  })  : uploads = List.unmodifiable(uploads ?? const <ComplaintUpload>[]),
        history = List<ComplaintHistoryEntry>.unmodifiable(history ?? const <ComplaintHistoryEntry>[]);

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

  static List<ComplaintHistoryEntry> _parseHistory(dynamic value) {
    if (value is List) {
      return List<ComplaintHistoryEntry>.unmodifiable(value.map((entry) {
        if (entry is Map<String, dynamic>) return ComplaintHistoryEntry.fromJson(entry);
        if (entry is Map) return ComplaintHistoryEntry.fromJson(_coerceMap(entry));
        return null;
      }).whereType<ComplaintHistoryEntry>());
    }
    return const <ComplaintHistoryEntry>[];
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

    final payload = (j['payload'] is Map)
        ? Map<String, dynamic>.from((j['payload'] as Map).cast<String, dynamic>())
        : null;

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
    final history = _parseHistory(j['history']);

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
      history: history,
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
        'adminNotes': adminNotes,
        'payload': payload,
        'history': history.map((e) => e.toJson()).toList(),
        if (repOpinion != null) 'repOpinion': repOpinion,
        if (repId != null) 'repId': repId,
      };
}

class ComplaintHistoryEntry {
  final DateTime at;
  final String actor;
  final String type;
  final String message;
  final Map<String, dynamic>? data;

  ComplaintHistoryEntry({
    required this.at,
    required this.actor,
    required this.type,
    required this.message,
    this.data,
  });

  factory ComplaintHistoryEntry.fromJson(Map<String, dynamic> j) {
    DateTime _dt(v) {
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
      if (v is String && v.trim().isNotEmpty) {
        final parsed = DateTime.tryParse(v.trim());
        if (parsed != null) return parsed;
      }
      return DateTime.now();
    }

    Map<String, dynamic>? _map(v) {
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return v.map((key, value) => MapEntry('$key', value));
      return null;
    }

    return ComplaintHistoryEntry(
      at: _dt(j['at']),
      actor: (j['actor'] ?? 'system').toString(),
      type: (j['type'] ?? 'info').toString(),
      message: (j['message'] ?? '').toString(),
      data: _map(j['data']),
    );
  }

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'actor': actor,
        'type': type,
        'message': message,
        if (data != null) 'data': data,
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

class _ActivityChoice {
  final String email;
  final String label;

  const _ActivityChoice(this.email, this.label);
}

class _ActivityCustomer {
  final String email;
  final String company;
  final String contact;

  const _ActivityCustomer({
    required this.email,
    required this.company,
    required this.contact,
  });

  factory _ActivityCustomer.fromJson(Map<String, dynamic> json) {
    return _ActivityCustomer(
      email: (json['email'] ?? '').toString(),
      company: (json['company'] ?? '').toString(),
      contact: (json['contact'] ?? '').toString(),
    );
  }

  String get label {
    if (company.trim().isNotEmpty) return company.trim();
    if (contact.trim().isNotEmpty) return contact.trim();
    return email;
  }
}

class _ActivitySnapshot {
  final String kind;
  final String email;
  final String name;
  final String company;
  final String contact;
  final String region;
  final List<String> customers;
  final List<_ActivityCustomer> customerProfiles;
  final int? lastLoginMs;
  final int? lastComplaintMs;
  final String? lastComplaintTicket;
  final int openTickets;
  final bool pushValid;
  final int? pushUpdatedMs;
  final String pushPlatform;
  final String appVersion;
  final String appBuild;
  final Map<String, dynamic>? location;
  final int tokens;

  const _ActivitySnapshot({
    required this.kind,
    required this.email,
    required this.name,
    required this.company,
    required this.contact,
    required this.region,
    required this.customers,
    required this.customerProfiles,
    required this.lastLoginMs,
    required this.lastComplaintMs,
    required this.lastComplaintTicket,
    required this.openTickets,
    required this.pushValid,
    required this.pushUpdatedMs,
    required this.pushPlatform,
    required this.appVersion,
    required this.appBuild,
    required this.location,
    required this.tokens,
  });

  static int? _parseMillis(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    if (value is String && value.trim().isNotEmpty) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
      final dt = DateTime.tryParse(value.trim());
      if (dt != null) return dt.millisecondsSinceEpoch;
    }
    return null;
  }

  factory _ActivitySnapshot.fromJson(Map<String, dynamic> json) {
    List<String> _strList(dynamic raw) {
      if (raw is List) return raw.map((e) => e.toString()).toList();
      return const [];
    }

    List<_ActivityCustomer> _customerProfiles(dynamic raw) {
      if (raw is! List) return const [];
      final parsed = <_ActivityCustomer>[];
      for (final entry in raw) {
        if (entry is Map<String, dynamic>) parsed.add(_ActivityCustomer.fromJson(entry));
        if (entry is Map) parsed.add(_ActivityCustomer.fromJson(entry.cast<String, dynamic>()));
      }
      return parsed;
    }

    return _ActivitySnapshot(
      kind: (json['kind'] ?? 'customer').toString(),
      email: (json['email'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      company: (json['company'] ?? '').toString(),
      contact: (json['contact'] ?? '').toString(),
      region: (json['region'] ?? '').toString(),
      customers: _strList(json['customers']),
      customerProfiles: _customerProfiles(json['customerProfiles']),
      lastLoginMs: _parseMillis(json['lastLoginAt']),
      lastComplaintMs: _parseMillis(json['lastComplaintAt']),
      lastComplaintTicket: json['lastComplaintTicket']?.toString(),
      openTickets: (json['openTickets'] is num) ? (json['openTickets'] as num).toInt() : 0,
      pushValid: json['pushValid'] == true,
      pushUpdatedMs: _parseMillis(json['pushUpdatedAt']),
      pushPlatform: (json['pushPlatform'] ?? '').toString(),
      appVersion: (json['appVersion'] ?? '').toString(),
      appBuild: (json['appBuild'] ?? '').toString(),
      location: (json['location'] is Map) ? (json['location'] as Map).cast<String, dynamic>() : null,
      tokens: (json['tokens'] is num) ? (json['tokens'] as num).toInt() : 0,
    );
  }

  bool get isRep => kind.toLowerCase() == 'rep';

  String get kindLabel => isRep ? 'Vertreter' : 'Kunde';

  String get displayName {
    final base = (name.isNotEmpty ? name : contact).trim();
    if (base.isNotEmpty) return base;
    if (company.isNotEmpty) return company;
    return email;
  }

  List<String> get customerLabels {
    List<String> _labels() {
      if (customerProfiles.isNotEmpty) return customerProfiles.map((c) => c.label).toList();
      return customers;
    }

    List<String> _distinctLabels(List<String> labels) {
      final counts = <String, int>{};
      for (final label in labels) {
        final trimmed = label.trim();
        if (trimmed.isEmpty) continue;
        counts[trimmed] = (counts[trimmed] ?? 0) + 1;
      }

      final seen = <String>{};
      final result = <String>[];
      for (final label in labels) {
        final trimmed = label.trim();
        if (trimmed.isEmpty || seen.contains(trimmed)) continue;
        final count = counts[trimmed] ?? 1;
        result.add(count > 1 ? '$trimmed ($count)' : trimmed);
        seen.add(trimmed);
      }

      return result;
    }

    return _distinctLabels(_labels());
  }

  String get appVersionLabel {
    if (appVersion.isEmpty && appBuild.isEmpty) return 'Unbekannt';
    if (appVersion.isNotEmpty && appBuild.isNotEmpty) return '$appVersion (Build $appBuild)';
    if (appVersion.isNotEmpty) return appVersion;
    return 'Build $appBuild';
  }

  String get locationLabel {
    final loc = location ?? const <String, dynamic>{};
    final label = (loc['label'] ?? '').toString().trim();
    final city = (loc['city'] ?? '').toString().trim();
    final country = (loc['country'] ?? '').toString().trim();
    final lat = loc['lat'];
    final lng = loc['lng'];
    String coords = '';
    if (lat is num && lng is num) {
      coords = '(${lat.toStringAsFixed(2)}, ${lng.toStringAsFixed(2)})';
    }
    final parts = [label, city, country, coords].where((e) => e.trim().isNotEmpty).toList();
    return parts.isEmpty ? 'Keine Angabe' : parts.join(' · ');
  }
}

class AdminPushBroadcastResult {
  final bool dryRun;
  final int totalTokens;
  final int invalidTokens;
  final List<AdminPushBroadcastLanguage> languages;
  final List<String> errors;
  final DateTime timestamp;

  AdminPushBroadcastResult({
    required this.dryRun,
    required this.totalTokens,
    required this.invalidTokens,
    required List<AdminPushBroadcastLanguage> languages,
    required List<String> errors,
    required this.timestamp,
  })  : languages = List.unmodifiable(languages),
        errors = List.unmodifiable(errors);

  factory AdminPushBroadcastResult.fromJson(Map<String, dynamic> json) {
    final langs = <AdminPushBroadcastLanguage>[];
    final rawLangs = json['languages'];
    if (rawLangs is List) {
      for (final entry in rawLangs) {
        if (entry is Map) {
          langs.add(AdminPushBroadcastLanguage.fromJson(Map<String, dynamic>.from(entry)));
        }
      }
    }
    final rawErrors = json['errors'];
    final errs = <String>[];
    if (rawErrors is List) {
      for (final e in rawErrors) {
        if (e == null) continue;
        final s = e.toString().trim();
        if (s.isNotEmpty) errs.add(s);
      }
    }
    final tsRaw = json['timestamp']?.toString();
    final ts = (tsRaw != null && tsRaw.isNotEmpty) ? (DateTime.tryParse(tsRaw) ?? DateTime.now()) : DateTime.now();
    return AdminPushBroadcastResult(
      dryRun: json['dryRun'] == true,
      totalTokens: json['totalTokens'] is num ? (json['totalTokens'] as num).toInt() : 0,
      invalidTokens: json['invalidTokens'] is num ? (json['invalidTokens'] as num).toInt() : 0,
      languages: langs,
      errors: errs,
      timestamp: ts,
    );
  }
}

class AdminPushBroadcastLanguage {
  final String lang;
  final int tokens;
  final int sent;
  final bool ok;

  AdminPushBroadcastLanguage({
    required this.lang,
    required this.tokens,
    required this.sent,
    required this.ok,
  });

  factory AdminPushBroadcastLanguage.fromJson(Map<String, dynamic> json) {
    return AdminPushBroadcastLanguage(
      lang: (json['lang'] ?? 'de').toString(),
      tokens: json['tokens'] is num ? (json['tokens'] as num).toInt() : 0,
      sent: json['sent'] is num ? (json['sent'] as num).toInt() : 0,
      ok: json['ok'] == true,
    );
  }
}

class Rep {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String region;
  final String lang;
  final List<String> customers;

  Rep({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.region,
    required this.lang,
    required this.customers,
  });

  factory Rep.fromJson(Map<String, dynamic> j) => Rep(
    id: (j['id'] ?? j['email'] ?? '').toString(),
    firstName: (j['firstName'] ?? '').toString(),
    lastName: (j['lastName'] ?? '').toString(),
    email: (j['email'] ?? '').toString(),
    region: (j['region'] ?? '').toString(),
    lang: normalizeLangCode(j['lang']?.toString()),
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
    'lang': lang,
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
  {'label': 'In Nacharbeit', 'value': 4},
  {'label': 'Abgeschlossen', 'value': 5},
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
  final DfsProduct? Function(String articleNumber)? productLookup;
  final String? companyHint;
  final bool hasRep;
  final bool selectable;
  final bool selected;
  final ValueChanged<bool?>? onSelected;
  final void Function(AdminComplaint c)? onChanged;

  const _ComplaintEditor({
    super.key,
    required this.api,
    required this.c,
    required this.onClosed,
    this.productLookup,
    this.companyHint,
    this.hasRep = false,
    this.selectable = false,
    this.selected = false,
    this.onSelected,
    this.onChanged,
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
  bool _historyExpanded = false;
  bool _showProductInfo = false;
  bool _noteOpen = false;
  bool _descTranslating = false;
  String? _descTranslation;
  String? _descTranslationErr;
  bool _descAutoDetectSource = true;
  String _descSourceLang = 'en';
  String? _payloadLang;

  static const Map<String, List<String>> _payloadKeyMap = {
    'segment': ['segment', 'customer_segment', 'segment_code'],
    'productType': ['product_type', 'productType', 'type'],
    'article': ['article', 'article_no', 'articleNumber', 'artnr'],
    'batch': ['batch', 'batch_no', 'lot', 'lot_no'],
    'serial': ['serial', 'serial_no', 'sn'],
    'qty': ['qty', 'quantity', 'amount', 'menge'],
    'expiry': ['expiry', 'expiry_date', 'exp'],
    'desc': ['desc', 'description', 'comment', 'details', 'failure_desc'],
    'reason': ['reason', 'failure_reason', 'cause'],
    'returned': ['returned'],
    'handling': ['handling', 'customer_wish', 'customerWish', 'wish', 'treatment_wish'],
    'applied': ['applied'],
    'injury': ['injury'],
    'injuryDesc': ['injuryDesc'],
  };

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

  String _langLabel(String code) => deeplLangLabel(code);

  String? _detectPayloadLang(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    const candidates = ['lang', 'language', 'lang_code', 'language_code', 'locale'];
    for (final key in candidates) {
      final raw = payload[key];
      if (raw == null) continue;
      final value = raw.toString().trim();
      if (value.isEmpty) continue;
      final lower = value.toLowerCase();
      if (deeplLangCodes.contains(lower)) return lower;
      final short = lower.split(RegExp('[-_]')).first;
      if (deeplLangCodes.contains(short)) return short;
    }
    return null;
  }

  Map<String, String> _payloadSnapshot() {
    final payload = (widget.c.payload is Map) ? (widget.c.payload as Map).cast<String, dynamic>() : null;
    final out = <String, String>{};
    _payloadKeyMap.forEach((key, aliases) {
      out[key] = _detPick(payload, aliases);
    });
    return out;
  }

  Widget _detKv(String label, String? value, {int? maxLines = 2}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final textTheme = theme.textTheme;
        final compact = constraints.maxWidth < 520;
        final effectiveMaxLines = compact ? null : maxLines;

        final labelStyle = textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: colorScheme.onSurfaceVariant.withOpacity(0.9),
        );

        final valueText = Text(
          v,
          maxLines: effectiveMaxLines,
          softWrap: true,
          style: textTheme.bodyMedium?.copyWith(
            height: 1.32,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        );

        final content = compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label.toUpperCase(), style: labelStyle),
                  const SizedBox(height: 2),
                  valueText,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 164,
                    child: Text(label.toUpperCase(), style: labelStyle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: valueText),
                ],
              );

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest.withOpacity(0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.4),
            ),
          ),
          child: content,
        );
      },
    );
  }

  Widget _productInfoTile(String label, String value) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      width: 340,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surfaceVariant.withOpacity(0.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant.withOpacity(0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                letterSpacing: 0.4,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _productInfoToggleButton() {
    return FilledButton.tonalIcon(
      onPressed: () => setState(() => _showProductInfo = !_showProductInfo),
      icon: Icon(_showProductInfo ? Icons.expand_less : Icons.unfold_more),
      label: Text(
        _showProductInfo ? 'Artikelliste ausblenden' : 'Artikelliste anzeigen',
      ),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    );
  }

  Widget _buildProductInfoCard(DfsProduct product) {
    final scheme = Theme.of(context).colorScheme;
    final entries = <Widget>[];
    final map = product.toHeaderMap();

    for (final key in DfsProduct.fieldOrder) {
      final value = (map[key] ?? '').trim();
      if (value.isEmpty) continue;
      final label = DfsProduct.fieldLabels[key] ?? key;
      entries.add(_productInfoTile(label, value));
    }

    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.inventory_2_outlined, color: scheme.onPrimary),
              ),
              const SizedBox(width: 10),
              Text(
                'Produktinformationen (Artikelliste)',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: entries,
          ),
        ],
      ),
    );
  }

  void _notifyChanged() {
    widget.onChanged?.call(widget.c);
  }

  @override
  void initState() {
    super.initState();
    _reportCtrl.text = widget.c.reportLink ?? '';
    _internalCtrl.text =
        (widget.c.internalNo == null || widget.c.internalNo!.trim().isEmpty)
            ? _internalNumberPrefix()
            : widget.c.internalNo!;
    _guardInternalNumberPrefix(_internalCtrl);
    _notesCtrl.text = widget.c.adminNotes ?? '';
    _status = widget.c.status;
    _decision = widget.c.decision;
    _payloadLang = _detectPayloadLang(widget.c.payload);
    final detected = _payloadLang;
    if (detected != null && deeplLangCodes.contains(detected)) {
      _descSourceLang = detected;
    }
  }

  @override
  void dispose() {
    _reportCtrl.dispose();
    _internalCtrl.dispose();
    _notesCtrl.dispose();

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
      widget.c.history = updated.history;

      _notifyChanged();

      if (updated.status == 5 || updated.decision == 'rejected') {
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

    final entered = _internalCtrl.text.trim();
    final newVal = _ensureInternalNumberPrefix(entered);

    if (newVal.isEmpty || newVal == _internalNumberPrefix()) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Nummer hinter dem Prefix ergänzen.')),
      );
      return;
    }

    // UI sofort updaten, damit es direkt neben der Ticketnummer erscheint
    setState(() {
      _internalCtrl.text = newVal;
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
        widget.c.history = updated.history;
      });

      _notifyChanged();

      if (updated.status == 5 || updated.decision == 'rejected') {
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

  void _toggleNotes() {
    setState(() {
      if (!_noteOpen) {
        _notesCtrl.text = widget.c.adminNotes ?? '';
      }
      _noteOpen = !_noteOpen;
    });
  }

  void _closeNotes() {
    FocusScope.of(context).unfocus();
    setState(() {
      _noteOpen = false;
      _notesCtrl.text = widget.c.adminNotes ?? '';
    });
  }

  Future<void> _translateDescription(String description) async {
    setState(() {
      _descTranslating = true;
      _descTranslationErr = null;
      _descTranslation = null;
    });

    try {
      final translations = await widget.api.translateFaqDraft(
        sourceLang: _descAutoDetectSource ? null : _descSourceLang,
        targetLangs: const ['de'],
        description: description,
      );

      final deMap = translations['de'];
      String? translated;
      if (deMap != null) {
        translated = deMap['description'] ??
            deMap.values.firstWhere(
              (v) => v.trim().isNotEmpty,
              orElse: () => '',
            );
      }

      if (!mounted) return;
      setState(() {
        _descTranslation = (translated ?? '').trim().isEmpty ? null : translated!.trim();
      });

      if (_descTranslation == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine Übersetzung erhalten.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _descTranslationErr = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _descTranslating = false);
      }
    }
  }

  Widget _buildDescriptionTranslationBox(String description) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final detected = _payloadLang;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceVariant.withOpacity(0.42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.translate, color: scheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Beschreibung auf Deutsch anzeigen',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Original bleibt unverändert – nur zur besseren Lesbarkeit.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant.withOpacity(0.75),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (_descTranslating)
                const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox.adaptive(
                    value: _descAutoDetectSource,
                    onChanged: (v) {
                      setState(() {
                        _descAutoDetectSource = v ?? true;
                      });
                    },
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Quellsprache automatisch erkennen',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant.withOpacity(0.9),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              DropdownButton<String>(
                value: deeplLangCodes.contains(_descSourceLang) ? _descSourceLang : 'en',
                onChanged: _descAutoDetectSource
                    ? null
                    : (v) {
                        if (v == null) return;
                        setState(() => _descSourceLang = v);
                      },
                items: deeplLangCodes
                    .map(
                      (code) => DropdownMenuItem<String>(
                        value: code,
                        child: Text(
                          _langLabel(code),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
              ),
              if (detected != null)
                Text(
                  'Erkannt: ${_langLabel(detected)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant.withOpacity(0.78),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              FilledButton.icon(
                onPressed: _descTranslating ? null : () => _translateDescription(description),
                icon: const Icon(Icons.g_translate),
                label: const Text('Übersetzung abrufen'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Hinweis: Übersetzung dient nur der Anzeige. Es wird nichts gespeichert oder überschrieben.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant.withOpacity(0.75),
            ),
          ),
          if (_descTranslationErr != null) ...[
            const SizedBox(height: 8),
            Text(
              _descTranslationErr!,
              style: TextStyle(color: scheme.error),
            ),
          ],
          if (_descTranslation != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withOpacity(0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.primary.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Übersetzung (Deutsch, nur Anzeige)',
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    _descTranslation!,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _saveNotes() async {
    if (_busy) return;

    final current = widget.c.adminNotes ?? '';
    final local = _notesCtrl.text;
    if (local == current) {
      _closeNotes();
      return;
    }

    setState(() => _busy = true);
    try {
      final trimmedRight = local.trimRight();
      final normalized = trimmedRight.trim().isEmpty ? '' : trimmedRight;

      final updated = await widget.api.adminComplaintUpdate(
        ticket: widget.c.ticket,
        notes: normalized,
      );

      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() {
        widget.c.adminNotes = updated.adminNotes;
        _notesCtrl.text = updated.adminNotes ?? '';
        _noteOpen = false;
        widget.c.history = updated.history;
      });

      _notifyChanged();

      final hasNote = (updated.adminNotes ?? '').trim().isNotEmpty;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(hasNote ? 'Notiz gespeichert.' : 'Notiz entfernt.')),
      );
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

  Future<void> _clearInternalNo() async {
    if (_busy) return;
    setState(() => _busy = true);

    // UI sofort leeren
    setState(() {
      _internalCtrl.text = _internalNumberPrefix();
      widget.c.internalNo = null;
    });

    try {
      final updated = await widget.api.adminComplaintUpdate(
        ticket: widget.c.ticket,
        internalNo: '',
      );
      setState(() {
        widget.c.internalNo = updated.internalNo; // bleibt i. d. R. null/leer
        widget.c.history = updated.history;
      });

      _notifyChanged();
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
      final updated = await widget.api.adminComplaintUpdate(ticket: widget.c.ticket, reportLink: '');
      _reportCtrl.text = '';
      widget.c.reportLink = updated.reportLink;
      widget.c.status = updated.status;
      widget.c.decision = updated.decision;
      widget.c.history = updated.history;

      _notifyChanged();

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

    final originalStatus = widget.c.status;
    final newStatus = _status!;
    bool sendPush = false;

    if (newStatus != originalStatus) {
      final answer = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Push-Benachrichtigung senden?'),
          content: const Text(
            'Der Status der Reklamation wurde geändert. Möchten Sie eine Push-Benachrichtigung an den Kunden (und ggf. Vertreter) senden?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nein')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ja')),
          ],
        ),
      );
      if (!mounted) return;
      sendPush = answer == true;
    }

    setState(() => _busy = true);
    try {
      final updated = await widget.api.adminComplaintUpdate(
        ticket: widget.c.ticket,
        status: newStatus,
        decision: _decision ?? '',
        sendPush: sendPush,
      );
      widget.c.status = updated.status;
      widget.c.decision = updated.decision;
      widget.c.history = updated.history;

      _notifyChanged();

      if (updated.status == 5 || updated.decision == 'rejected') {
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

  Future<void> _openEditDialog() async {
    if (_busy) return;

    final snapshot = _payloadSnapshot();
    final formKey = GlobalKey<FormState>();

    String segment = snapshot['segment'] ?? '';
    String productType = snapshot['productType'] ?? '';
    final productTypeCtrl = TextEditingController(text: productType);
    final articleCtrl = TextEditingController(text: snapshot['article'] ?? '');
    final batchCtrl = TextEditingController(text: snapshot['batch'] ?? '');
    final serialCtrl = TextEditingController(text: snapshot['serial'] ?? '');
    final qtyCtrl = TextEditingController(text: snapshot['qty'] ?? '');
    final expiryCtrl = TextEditingController(text: snapshot['expiry'] ?? '');
    final descCtrl = TextEditingController(text: snapshot['desc'] ?? '');
    final reasonCtrl = TextEditingController(text: snapshot['reason'] ?? '');
    String returned = snapshot['returned'] ?? '';
    String handling = snapshot['handling'] ?? '';
    final handlingCtrl = TextEditingController(text: handling);
    String applied = snapshot['applied'] ?? '';
    String injury = snapshot['injury'] ?? '';
    final injuryDescCtrl = TextEditingController(text: snapshot['injuryDesc'] ?? '');

    final controllers = <TextEditingController>[
      productTypeCtrl,
      articleCtrl,
      batchCtrl,
      serialCtrl,
      qtyCtrl,
      expiryCtrl,
      descCtrl,
      reasonCtrl,
      handlingCtrl,
      injuryDescCtrl,
    ];

    void disposeControllers() {
      for (final c in controllers) {
        c.dispose();
      }
    }

    Map<String, String>? updatedPayload = await showDialog<Map<String, String>?>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          String? normalizedDropdown(String value) => value.trim().isEmpty ? null : value;

          List<DropdownMenuItem<String>> yesNoItems() => const [
                DropdownMenuItem(value: 'Ja', child: Text('Ja')),
                DropdownMenuItem(value: 'Nein', child: Text('Nein')),
              ];

          return AlertDialog(
            title: const Text('Reklamation ändern'),
            content: SizedBox(
              width: 720,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: normalizedDropdown(segment),
                              items: const [
                                DropdownMenuItem(value: 'Zahnmedizin', child: Text('Zahnmedizin')),
                                DropdownMenuItem(value: 'Dentallabor', child: Text('Dentallabor')),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Produktbereich',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() => segment = v ?? ''),
                              isExpanded: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: productTypeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Produkttyp (optional)',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => productType = v,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: articleCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Artikelnummer',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Artikelnummer erforderlich'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: batchCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Charge / Lot',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: qtyCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Menge',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: expiryCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Ablaufdatum',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: serialCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Seriennummer (optional)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: normalizedDropdown(returned),
                              items: const [
                                DropdownMenuItem(value: 'Ja', child: Text('Ja')),
                                DropdownMenuItem(value: 'Nein', child: Text('Nein')),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Produkte zurückgeschickt?',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() => returned = v ?? ''),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: handlingCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Gewünschte Behandlung',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => handling = v,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: descCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Fehler / Beschreibung',
                          border: OutlineInputBorder(),
                        ),
                        minLines: 3,
                        maxLines: 6,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Bitte eine Beschreibung angeben'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: reasonCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Grund / Ursache (optional)',
                          border: OutlineInputBorder(),
                        ),
                        minLines: 2,
                        maxLines: 4,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: normalizedDropdown(applied),
                              items: yesNoItems(),
                              decoration: const InputDecoration(
                                labelText: 'Am Patienten angewendet?',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() => applied = v ?? ''),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: normalizedDropdown(injury),
                              items: yesNoItems(),
                              decoration: const InputDecoration(
                                labelText: 'Verletzung?',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() => injury = v ?? ''),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: injuryDescCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Beschreibung der Verletzung (optional)',
                          border: OutlineInputBorder(),
                        ),
                        minLines: 2,
                        maxLines: 5,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Abbrechen'),
              ),
              FilledButton.icon(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  Navigator.pop(ctx, {
                    'segment': segment,
                    'productType': productTypeCtrl.text,
                    'article': articleCtrl.text,
                    'batch': batchCtrl.text,
                    'serial': serialCtrl.text,
                    'qty': qtyCtrl.text,
                    'expiry': expiryCtrl.text,
                    'desc': descCtrl.text,
                    'reason': reasonCtrl.text,
                    'returned': returned,
                    'handling': handlingCtrl.text,
                    'applied': applied,
                    'injury': injury,
                    'injuryDesc': injuryDescCtrl.text,
                  });
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Änderungen speichern'),
              ),
            ],
          );
        });
      },
    );

    if (updatedPayload == null) {
      disposeControllers();
      return;
    }

    updatedPayload = updatedPayload.map((k, v) => MapEntry(k, v.trim()));

    bool hasChanges = false;
    updatedPayload.forEach((key, value) {
      if ((snapshot[key] ?? '').trim() != value) hasChanges = true;
    });

    if (!hasChanges) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Keine Änderungen vorgenommen.')));
      }
      disposeControllers();
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Änderungen übernehmen?'),
        content: Text('Änderungen an Ticket ${widget.c.ticket} speichern und den Kunden per Mail informieren?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ja, speichern')),
        ],
      ),
    );

    if (confirm != true) {
      disposeControllers();
      return;
    }

    setState(() => _busy = true);
    try {
      final updated = await widget.api.updateComplaintDetails(
        ticket: widget.c.ticket,
        payload: updatedPayload,
      );

      final newPayload = updated.payload ?? <String, dynamic>{};
      widget.c.payload ??= <String, dynamic>{};
      widget.c.payload!
        ..clear()
        ..addAll(newPayload);
      widget.c.history = updated.history;

      _notifyChanged();

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reklamation aktualisiert. Info-Mail wurde versendet.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      disposeControllers();
    }
  }

  String _statusLabel(int v) {
    final m = kStatusItems.firstWhere((e) => e['value'] == v, orElse: () => const {});
    return (m['label'] ?? 'Status $v').toString();
  }

  // --- E-Mail an Kunden ------------------------------------------------
  String _buildMailSubject(AdminComplaint c) {
    final wish = c.handlingLabel == '—' ? '' : ' – ${c.handlingLabel}';
    final internal = (c.internalNo ?? '').trim();
    final ticketLabel = internal.isNotEmpty ? '${c.ticket} – Intern $internal' : c.ticket;
    return '[DFS Complaint $ticketLabel] Rückfrage zu Ihrer Reklamation$wish';
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
      case 4: return 'In Nacharbeit';
      case 5: return 'Abgeschlossen';
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

  String _historyTypeLabel(String raw) {
    switch (raw.trim()) {
      case 'created':
        return 'Erstellt';
      case 'status':
        return 'Status';
      case 'decision':
        return 'Entscheidung';
      case 'payload':
        return 'Details';
      case 'report':
        return 'Report-Link';
      case 'internal':
        return 'Interne Nummer';
      case 'notes':
        return 'Notiz';
      default:
        return raw.trim().isEmpty ? 'Aktualisierung' : raw;
    }
  }

  String _historyDetails(ComplaintHistoryEntry entry) {
    final data = entry.data;
    if (data == null || data.isEmpty) return '';

    if (data['changes'] is List) {
      final parts = <String>[];
      for (final change in data['changes'] as List) {
        if (change is Map) {
          final label = (change['label'] ?? '').toString();
          final before = (change['before'] ?? '—').toString();
          final after = (change['after'] ?? '—').toString();
          parts.add(label.isEmpty ? '$before → $after' : '$label: $before → $after');
        }
      }
      return parts.join(' | ');
    }

    if (data['link'] != null) return data['link'].toString();
    if (data['internalNo'] != null) return data['internalNo'].toString();

    return data.entries.map((e) => '${e.key}: ${e.value}').join(' | ');
  }

  void _exportHistoryCsv() {
    final entries = List<ComplaintHistoryEntry>.from(widget.c.history);
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Keine Historie zum Export vorhanden.')));
      return;
    }

    entries.sort((a, b) => a.at.compareTo(b.at));
    const sep = ';';
    String esc(String v) => '"${v.replaceAll('"', '""')}"';

    final buffer = StringBuffer();
    buffer.writeln([ 'Datum', 'Typ', 'Quelle', 'Beschreibung', 'Details' ].map(esc).join(sep));

    for (final entry in entries) {
      final row = [
        _fmtDateTime(entry.at),
        _historyTypeLabel(entry.type),
        entry.actor,
        entry.message,
        _historyDetails(entry),
      ].map((v) => esc(v)).join(sep);
      buffer.writeln(row);
    }

    final blob = html.Blob([buffer.toString()], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', 'reklamation_${widget.c.ticket}_historie.csv');
    anchor.click();
    html.Url.revokeObjectUrl(url);
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
    // ---- Payload-Felder (nur lesend) ----
    final currentNote = widget.c.adminNotes ?? '';
    final hasNote = currentNote.trim().isNotEmpty;
    final noteChanged = _notesCtrl.text != currentNote;
    final Map<String, dynamic>? p = (c.payload is Map) ? (c.payload as Map).cast<String, dynamic>() : null;
    final segment      = _detPickOrNull(p, ['segment','customer_segment','segment_code']);
    final productType  = _detPickOrNull(p, ['product_type','productType','type']);
    final articleNo    = _detPickOrNull(p, ['article_no','articleNumber','article','artnr']);
    final batch        = _detPickOrNull(p, ['batch_no','lot','lot_no','batch']);
    final serial       = _detPickOrNull(c.payload, ['serial_no', 'serial', 'sn']);
    final qty          = _detPickOrNull(p, ['qty','quantity','amount','menge']);
    final reason       = _detPickOrNull(p, ['reason','failure_reason','cause']);
    final desc         = _detPickOrNull(p, ['desc','description','comment','details','failure_desc']);
    final descText     = (desc ?? '').trim();
    final customerWish = _detPickOrNull(p, ['customer_wish','customerWish','wish','treatment_wish']);
    final applied     = _detPickOrNull(p, ['applied']);          // 'Ja' | 'Nein' | ''
    final injury      = _detPickOrNull(p, ['injury']);           // 'Ja' | 'Nein' | ''
    final injuryDesc  = _detPickOrNull(p, ['injuryDesc']);       // Freitext
    final returned    = _detPickOrNull(p, ['returned']);         // 'Ja' | 'Nein'
    final attachments = c.uploads;
    final matchedProduct = widget.productLookup?.call(articleNo ?? '');
    final articleLabel = matchedProduct == null
        ? articleNo
        : [
            (articleNo ?? '').trim().isNotEmpty ? articleNo!.trim() : matchedProduct.articleNumber,
            matchedProduct.productName,
          ].where((v) => v.trim().isNotEmpty).join(' – ');

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
                if (widget.selectable)
                  Padding(
                    padding: const EdgeInsets.only(right: 12, top: 2),
                    child: Checkbox(
                      value: widget.selected,
                      onChanged: widget.onSelected,
                    ),
                  ),
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
                    Widget noteButton() {
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            tooltip: hasNote ? 'Notiz anzeigen/bearbeiten' : 'Notiz hinzufügen',
                            icon: Icon(_noteOpen ? Icons.sticky_note_2 : Icons.sticky_note_2_outlined),
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
                      );
                    }

                    return Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        noteButton(),
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
                          ),
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

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) => SizeTransition(sizeFactor: anim, axisAlignment: -1, child: child),
              child: !_noteOpen
                  ? const SizedBox.shrink()
                  : Container(
                      key: const ValueKey('admin-note'),
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF9C4),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.brown.withOpacity(0.18),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                        border: Border.all(color: Colors.amber.shade200, width: 1.2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.sticky_note_2, color: Color(0xFF8D6E63)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Interne Notiz',
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF5D4037),
                                      ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Schließen',
                                onPressed: _closeNotes,
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
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
                                minLines: 4,
                                maxLines: 10,
                                enabled: !_busy,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  hintText: 'Hier deine interne Notiz zur Reklamation erfassen ...',
                                  contentPadding: EdgeInsets.fromLTRB(18, 16, 18, 18),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  hasNote
                                      ? 'Notizen sind nur im Adminbereich sichtbar.'
                                      : 'Noch keine Notiz gespeichert – alles bleibt intern.',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: const Color(0xFF6D4C41),
                                      ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _busy ? null : _closeNotes,
                                icon: const Icon(Icons.close),
                                label: const Text('Schließen'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                onPressed: (_busy || !noteChanged) ? null : _saveNotes,
                                icon: const Icon(Icons.save_outlined),
                                label: const Text('Notiz speichern'),
                              ),
                            ],
                          ),
                        ],
                      ),
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
              AnimatedCrossFade(
                crossFadeState: _expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                duration: const Duration(milliseconds: 160),
                firstChild: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.surface,
                        Theme.of(context)
                            .colorScheme
                            .surfaceVariant
                            .withOpacity(0.35),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withOpacity(0.55),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context)
                            .colorScheme
                            .shadow
                            .withOpacity(0.05),
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final theme = Theme.of(context);
                      final textTheme = theme.textTheme;
                      final colorScheme = theme.colorScheme;
                      // Show the details in two columns even on slightly
                      // narrower layouts so that the description and patient
                      // questions appear beside the product details.
                      final useTwoColumns = constraints.maxWidth >= 720;

                      void addDetail(List<Widget> list, String label, String? value,
                          {int? maxLines = 2}) {
                        final trimmed = (value ?? '').trim();
                        if (trimmed.isEmpty) return;
                        final widget = _detKv(label, value, maxLines: maxLines);
                        list.add(widget);
                      }

                      List<Widget> spaced(List<Widget> items) {
                        final result = <Widget>[];
                        for (var i = 0; i < items.length; i++) {
                          result.add(items[i]);
                          if (i < items.length - 1) {
                            result.add(const SizedBox(height: 10));
                          }
                        }
                        return result;
                      }

                      String? normalizeSegment(String? value) {
                        final raw = (value ?? '').trim();
                        if (raw.isEmpty) return null;
                        switch (raw.toLowerCase()) {
                          case 'zahnarzt':
                            return 'Zahnmedizin';
                          case 'zahntechnik':
                            return 'Dentallabor';
                        }
                        return raw;
                      }

                      String? deriveProductType(String? area) {
                        if (area == null) return null;
                        switch (area.toLowerCase()) {
                          case 'zahnmedizin':
                            return 'Medizinprodukt';
                          case 'dentallabor':
                            return 'Laborprodukt';
                        }
                        return null;
                      }

                      final productArea = normalizeSegment(segment);
                      final derivedProductType =
                          deriveProductType(productArea ?? segment);
                      final productDetails =
                          matchedProduct == null ? null : _buildProductInfoCard(matchedProduct);
                      final hasProductInfo = productDetails != null;

                      final primaryColumn = <Widget>[];
                      final secondaryColumn = <Widget>[];

                      addDetail(primaryColumn, 'Produktbereich', productArea ?? segment);
                      addDetail(primaryColumn, 'Produkttyp',
                          derivedProductType ?? productType);
                      addDetail(primaryColumn, 'Artikelnummer', articleLabel);
                      addDetail(primaryColumn, 'Charge / Lot', batch);
                      addDetail(primaryColumn, 'Menge', qty);
                      addDetail(primaryColumn, 'Produkte zurückgeschickt?', returned);

                      addDetail(secondaryColumn, 'Fehler / Beschreibung', descText,
                          maxLines: null);
                      addDetail(secondaryColumn, 'Am Patienten angewendet?', applied);
                      addDetail(
                          secondaryColumn,
                          'Wurde ein Patient, Anwender oder Dritter verletzt?',
                          injury);
                      addDetail(secondaryColumn, 'Beschreibung der Verletzung',
                          injuryDesc,
                          maxLines: null);
                      addDetail(secondaryColumn, 'Grund / Ursache', reason,
                          maxLines: 4);
                      addDetail(secondaryColumn, 'Wunsch des Kunden', customerWish,
                          maxLines: 3);

                      final hasDetails = primaryColumn.isNotEmpty ||
                          secondaryColumn.isNotEmpty ||
                          productDetails != null;

                      if (!hasDetails) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Icon(Icons.info_outline,
                                        size: 18, color: colorScheme.primary),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Details der Reklamation',
                                    style: textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.15,
                                    ),
                                  ),
                                ),
                                if (hasProductInfo) _productInfoToggleButton(),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Keine zusätzlichen Angaben vorhanden.',
                              style: textTheme.bodyMedium?.copyWith(
                                color:
                                    colorScheme.onSurfaceVariant.withOpacity(0.74),
                              ),
                            ),
                            if (productDetails != null) ...[
                              const SizedBox(height: 12),
                              if (_showProductInfo) productDetails,
                            ],
                          ],
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: colorScheme.shadow.withOpacity(0.08),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Icon(Icons.info_outline,
                                      size: 18, color: colorScheme.primary),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Details der Reklamation',
                                      style: textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.15,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Wichtigste Angaben kompakt und geordnet.',
                                      style: textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant
                                            .withOpacity(0.78),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (hasProductInfo) _productInfoToggleButton(),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (useTwoColumns &&
                              (primaryColumn.isNotEmpty ||
                                  secondaryColumn.isNotEmpty))
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (primaryColumn.isNotEmpty)
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: spaced(primaryColumn),
                                    ),
                                  ),
                                if (primaryColumn.isNotEmpty &&
                                    secondaryColumn.isNotEmpty)
                                  const SizedBox(width: 16),
                                if (secondaryColumn.isNotEmpty)
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: spaced(secondaryColumn),
                                    ),
                                  ),
                              ],
                            )
                          else
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ...spaced(primaryColumn),
                                if (primaryColumn.isNotEmpty &&
                                    secondaryColumn.isNotEmpty)
                                  const Divider(height: 22),
                                ...spaced(secondaryColumn),
                              ],
                            ),
                          if (productDetails != null) ...[
                            const SizedBox(height: 12),
                            if (_showProductInfo) productDetails,
                          ],
                          if (descText.isNotEmpty)
                            _buildDescriptionTranslationBox(descText),
                          if (attachments.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Anhänge',
                              style: textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
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
                secondChild: const SizedBox.shrink(),
              ),

              // ====== Editor-Bereich (Layout überarbeitet) ======
              LayoutBuilder(
                builder: (context, constraints) {
                  final theme = Theme.of(context);
                  final scheme = theme.colorScheme;
                  final textTheme = theme.textTheme;
                  final isWide = constraints.maxWidth >= 920;
                  final inlineActions = constraints.maxWidth >= 720;
                  final secondaryTextColor =
                      theme.textTheme.bodySmall?.color?.withOpacity(0.7) ??
                          scheme.onSurfaceVariant.withOpacity(0.85);

                  Widget buildStatusSection() {
                    final dropdownStyle = const InputDecoration(
                      border: OutlineInputBorder(),
                    );

                    final statusField = DropdownButtonFormField<int>(
                      value: _status,
                      decoration: dropdownStyle.copyWith(labelText: 'Status'),
                      items: kStatusItems
                          .map((e) => DropdownMenuItem<int>(
                                value: e['value'] as int,
                                child: Text(e['label'] as String),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _status = v),
                    );

                    final decisionField = DropdownButtonFormField<String>(
                      value: _decision ?? '',
                      decoration: dropdownStyle.copyWith(labelText: 'Entscheidung'),
                      items: kDecisionItems
                          .map((e) => DropdownMenuItem<String>(
                                value: e['value']!,
                                child: Text(e['label']!),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _decision = (v == null || v.isEmpty) ? null : v),
                    );

                    final saveButton = FilledButton.icon(
                      onPressed: _busy ? null : _saveStatusDecision,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Änderungen speichern'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 56),
                      ),
                    );

                    if (isWide) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Status & Entscheidung',
                            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(child: statusField),
                              const SizedBox(width: 12),
                              Expanded(child: decisionField),
                              const SizedBox(width: 12),
                              SizedBox(width: 200, child: saveButton),
                            ],
                          ),
                        ],
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Status & Entscheidung',
                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        statusField,
                        const SizedBox(height: 12),
                        decisionField,
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(width: 220, child: saveButton),
                        ),
                      ],
                    );
                  }

                  Widget buildFieldWithAction({
                    required Widget field,
                    required Widget action,
                  }) {
                    if (inlineActions) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(child: field),
                          const SizedBox(width: 12),
                          SizedBox(height: 52, child: action),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        field,
                        const SizedBox(height: 8),
                        Align(alignment: Alignment.centerRight, child: action),
                      ],
                    );
                  }

                  Widget buildMetaSection() {
                    final internalField = TextField(
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
                      onSubmitted: (_) => _busy ? null : _saveInternalNo(),
                    );

                    final internalAction = OutlinedButton.icon(
                      onPressed: _busy ? null : _saveInternalNo,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Interne Nummer speichern'),
                    );

                    final reportField = TextField(
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
                    );

                    final reportAction = OutlinedButton.icon(
                      onPressed: _busy ? null : _saveReportLink,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Link speichern'),
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Meta & Aktionen',
                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        buildFieldWithAction(field: internalField, action: internalAction),
                        const SizedBox(height: 16),
                        buildFieldWithAction(field: reportField, action: reportAction),
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _busy ? null : _deleteComplaint,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Ticket löschen'),
                          ),
                        ),
                      ],
                    );
                  }

                  Widget buildHistorySection() {
                    final history = List<ComplaintHistoryEntry>.from(c.history);
                    history.sort((a, b) => b.at.compareTo(a.at));

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => setState(() => _historyExpanded = !_historyExpanded),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _historyExpanded
                                            ? Icons.expand_less_outlined
                                            : Icons.expand_more_outlined,
                                      ),
                                      const SizedBox(width: 6),
                                      const Icon(Icons.timeline_outlined),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Reklamationshistorie',
                                        style:
                                            textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(width: 8),
                                      if (history.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
                                          decoration: BoxDecoration(
                                            color: scheme.primary.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            '${history.length} Einträge',
                                            style: textTheme.labelMedium?.copyWith(color: scheme.primary),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: history.isEmpty ? null : _exportHistoryCsv,
                              icon: const Icon(Icons.download_outlined),
                              label: const Text('Exportieren'),
                            ),
                          ],
                        ),
                        if (_historyExpanded) ...[
                          const SizedBox(height: 12),
                          if (history.isEmpty)
                            Text(
                              'Keine Einträge vorhanden.',
                              style: textTheme.bodySmall?.copyWith(color: secondaryTextColor),
                            )
                          else
                            ...history.map((entry) {
                              final details = _historyDetails(entry);
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.history, size: 18, color: scheme.outline),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _fmtDateTime(entry.at),
                                            style: textTheme.bodySmall?.copyWith(color: secondaryTextColor),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            entry.message.isEmpty
                                                ? '(ohne Beschreibung)'
                                                : entry.message,
                                            style: textTheme.bodyMedium,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${_historyTypeLabel(entry.type)} • ${entry.actor}',
                                            style: textTheme.bodySmall?.copyWith(color: secondaryTextColor),
                                          ),
                                          if (details.isNotEmpty)
                                            Text(
                                              details,
                                              style: textTheme.bodySmall?.copyWith(color: secondaryTextColor),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ],
                    );
                  }

                  final editor = isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: buildStatusSection()),
                            const SizedBox(width: 28),
                            Expanded(child: buildMetaSection()),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            buildStatusSection(),
                            const SizedBox(height: 24),
                            buildMetaSection(),
                          ],
                        );

                  final baseColor = scheme.surface;
                  final overlay = theme.brightness == Brightness.dark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.black.withOpacity(0.04);

                  return Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: isWide ? 24 : 18,
                      vertical: 22,
                    ),
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(overlay, baseColor),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: scheme.outline.withOpacity(0.35)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(
                            theme.brightness == Brightness.dark ? 0.35 : 0.08,
                          ),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: scheme.primary.withOpacity(0.12),
                                  child: Icon(
                                    Icons.manage_accounts_outlined,
                                    color: scheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Reklamation bearbeiten',
                                  style: textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                TextButton.icon(
                                  onPressed: _busy ? null : _openEditDialog,
                                  icon: const Icon(Icons.edit_note_outlined),
                                  label: const Text('Reklamation ändern'),
                                ),
                              ],
                            ),
                            if (!isWide)
                              Text(
                                'Ticket: ${c.ticket}',
                                style: textTheme.bodySmall?.copyWith(
                                  color: secondaryTextColor,
                                ),
                              ),
                          ],
                        ),
                        if (isWide) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Ticket: ${c.ticket}',
                            style: textTheme.bodySmall?.copyWith(
                              color: secondaryTextColor,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        buildHistorySection(),
                        const SizedBox(height: 20),
                        editor,
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
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
    if (dialogWidth > 720) dialogWidth = 720;
    if (dialogHeight > 760) dialogHeight = 760;

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
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
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
                  padding: const EdgeInsets.all(20),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
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
                padding: const EdgeInsets.fromLTRB(0, 0, 16, 16),
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

class _TextFormatChip extends StatelessWidget {
  const _TextFormatChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ActionChip(
      avatar: Icon(icon, size: 18, color: colorScheme.primary),
      label: Text(label),
      labelStyle: theme.textTheme.labelLarge,
      shape: StadiumBorder(
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      backgroundColor: colorScheme.surfaceVariant.withOpacity(0.4),
      onPressed: onTap,
    );
  }
}
// ===================================================================
// Admin API (Browser, dart:html)
// ===================================================================
class AdminApi {
  AdminApi({this.onNewsChanged});

  final VoidCallback? onNewsChanged;
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
      throw 'admin customers POST: HTTP ${res.status} ${res.responseText}';
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

  Future<void> setUserRevoked(String email, bool revoked) async {
    final res = await _request('PATCH', '/api/admin/users', body: {'email': email, 'revoked': revoked});
    if (res.status != 200 && res.status != 204) {
      throw 'users PATCH revoke failed: HTTP ${res.status} ${res.responseText}';
    }
  }

  Future<void> updateCustomerNumber({
    required String email,
    required String? customerNumber,
  }) async {
    final body = <String, dynamic>{
      'action': 'updateCustomerNumber',
      'email': email,
      'customerNumber': (customerNumber ?? '').trim(),
    };

    final res = await _request('POST', '/api/admin/users', body: body);
    if (res.status != 200 && res.status != 204) {
      throw 'users POST(updateCustomerNumber): HTTP ${res.status} ${res.responseText}';
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

  Future<List<AdminComplaint>> fetchAllComplaints() async {
    final res = await _request('GET', '/api/admin/complaints', q: {'all': '1'});
    if (res.status != 200) throw 'all complaints GET: HTTP ${res.status} ${res.responseText}';
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
    String? internalNo,
    String? notes,
    bool? sendPush,
  }) async {
    final body = <String, dynamic>{'ticket': ticket};
    if (status != null) body['status'] = status;
    body['decision'] = decision ?? '';
    if (reportLink != null) body['reportLink'] = reportLink;
    if (internalNo != null) body['internalNo'] = internalNo;
    if (notes != null) body['notes'] = notes;
    if (sendPush != null) body['sendPush'] = sendPush;

    final res = await _request('POST', '/api/admin/complaints', body: body);
    if (res.status != 200) {
      throw 'HTTP ${res.status} ${res.statusText} — ${res.responseText ?? ''}';
    }
    final Map<String, dynamic> j =
        (res.responseText ?? '').trim().isEmpty ? <String, dynamic>{} : jsonDecode(res.responseText!);
    return AdminComplaint.fromJson(j);
  }

  Future<AdminComplaint> updateComplaintDetails({
    required String ticket,
    required Map<String, String> payload,
  }) async {
    final body = <String, dynamic>{
      'ticket': ticket,
      'payload': payload,
    };

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
    required String lang,
  }) async {
    final body = {
      'action': 'upsert',                 // <-- NEU
      if (id != null && id.isNotEmpty) 'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'region': region,
      'lang': lang,
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

    // ---------- Catalogs (Katalog-Konfiguration) ----------
  Future<Map<String, String>> fetchCatalogConfig() async {
    final res = await _request('GET', '/api/catalogs/config');
    if (res.status != 200) {
      throw 'catalog config GET: HTTP ${res.status} ${res.responseText}';
    }
    final txt = res.responseText ?? '{}';
    final Map j = (txt.trim().isEmpty) ? <String, dynamic>{} : jsonDecode(txt);
    final out = <String, String>{};
    for (final k in ['lab_default','lab_esfr','dent_default','dent_esfr']) {
      final v = j[k];
      if (v is String && v.trim().isNotEmpty) out[k] = v.trim();
    }
    return out;
  }

  Future<void> updateCatalogConfig(Map<String, String> cfg) async {
    final body = <String, String>{};
    for (final k in ['lab_default','lab_esfr','dent_default','dent_esfr']) {
      final v = cfg[k];
      if (v != null) body[k] = v;
    }
    final res = await _request('PUT', '/api/catalogs/config', body: body);
    if (res.status != 200 && res.status != 204) {
      throw 'catalog config PUT: HTTP ${res.status} ${res.responseText}';
    }
  }

  Future<List<CustomerNewsEntry>> fetchCustomerNewsEntries() async {
    final res = await _request('GET', '/api/admin/news');
    if (res.status != 200) {
      throw 'admin news GET: HTTP ${res.status} ${res.responseText}';
    }
    final txt = res.responseText?.trim() ?? '';
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
      throw 'admin news POST: HTTP ${res.status} ${res.responseText}';
    }
    final txt = res.responseText?.trim() ?? '';
    final Map<String, dynamic> j = txt.isEmpty ? <String, dynamic>{} : jsonDecode(txt);
    onNewsChanged?.call();
    return CustomerNewsEntry.fromJson(j);
  }

  Future<void> deleteCustomerNews(String id) async {
    final body = {'id': id};
    final res = await _request('DELETE', '/api/admin/news', body: body);
    if (res.status != 200 && res.status != 204) {
      throw 'admin news DELETE: HTTP ${res.status} ${res.responseText}';
    }
    onNewsChanged?.call();
  }

  Future<FaqData> fetchFaq() async {
    final res = await _request('GET', '/api/admin/faq');
    if (res.status != 200) {
      throw 'admin faq GET: HTTP ${res.status} ${res.responseText}';
    }
    final txt = res.responseText?.trim() ?? '';
    final Map<String, dynamic> data =
        txt.isEmpty ? <String, dynamic>{} : jsonDecode(txt);
    return FaqData.fromJson(data);
  }

  Future<FaqCategory> saveFaqCategory({
    String? id,
    required String title,
    Map<String, String>? titleIntl,
    String? description,
    Map<String, String>? descriptionIntl,
    int? order,
    bool? active,
    String? primaryLang,
  }) async {
    final body = <String, dynamic>{
      'type': 'category',
      if (id != null && id.isNotEmpty) 'id': id,
      'title': title,
      if (titleIntl != null) 'titleIntl': titleIntl,
      if (description != null) 'description': description,
      if (descriptionIntl != null) 'descriptionIntl': descriptionIntl,
      if (order != null) 'order': order,
      if (active != null) 'active': active,
      if (primaryLang != null) 'lang': primaryLang,
    };
    final res = await _request('POST', '/api/admin/faq', body: body);
    if (res.status != 200) {
      throw 'admin faq category POST: HTTP ${res.status} ${res.responseText}';
    }
    final Map<String, dynamic> j =
        (res.responseText?.trim().isEmpty ?? true)
            ? <String, dynamic>{}
            : jsonDecode(res.responseText!);
    return FaqCategory.fromJson(j);
  }

  Future<FaqEntry> saveFaqEntry({
    String? id,
    required String categoryId,
    required String question,
    required String answer,
    Map<String, String>? questionIntl,
    Map<String, String>? answerIntl,
    String audience = 'both',
    int? order,
    bool? active,
  }) async {
    final body = <String, dynamic>{
      'type': 'entry',
      'categoryId': categoryId,
      'question': question,
      'answer': answer,
      if (questionIntl != null) 'questionIntl': questionIntl,
      if (answerIntl != null) 'answerIntl': answerIntl,
      'audience': audience,
      if (id != null && id.isNotEmpty) 'id': id,
      if (order != null) 'order': order,
      if (active != null) 'active': active,
    };
    final res = await _request('POST', '/api/admin/faq', body: body);
    if (res.status != 200) {
      throw 'admin faq entry POST: HTTP ${res.status} ${res.responseText}';
    }
    final Map<String, dynamic> j =
        (res.responseText?.trim().isEmpty ?? true)
            ? <String, dynamic>{}
            : jsonDecode(res.responseText!);
    return FaqEntry.fromJson(j);
  }

  Future<Map<String, Map<String, String>>> translateFaqDraft({
    String? sourceLang,
    required List<String> targetLangs,
    String? question,
    String? answer,
    String? title,
    String? description,
  }) async {
    final payload = <String, dynamic>{
      'targets': targetLangs,
    };

    if (sourceLang != null && sourceLang.trim().isNotEmpty) {
      payload['sourceLang'] = sourceLang.trim();
    }

    if (question != null && question.trim().isNotEmpty) {
      payload['question'] = question.trim();
    }
    if (answer != null && answer.trim().isNotEmpty) {
      payload['answer'] = answer.trim();
    }
    if (title != null && title.trim().isNotEmpty) {
      payload['title'] = title.trim();
    }
    if (description != null && description.trim().isNotEmpty) {
      payload['description'] = description.trim();
    }

    final res = await _request('POST', '/api/admin/translate', body: payload);
    if (res.status != 200) {
      throw 'admin translate POST: HTTP ${res.status} ${res.responseText}';
    }

    final txt = res.responseText?.trim() ?? '';
    if (txt.isEmpty) return <String, Map<String, String>>{};
    final decoded = jsonDecode(txt);
    final translations = <String, Map<String, String>>{};
    if (decoded is Map && decoded['translations'] is Map) {
      (decoded['translations'] as Map).forEach((key, value) {
        if (value is Map) {
          translations[key.toString()] =
              value.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()));
        }
      });
    }
    return translations;
  }

  Future<void> deleteFaqCategory(String id) async {
    final res = await _request('DELETE', '/api/admin/faq', body: {
      'type': 'category',
      'id': id,
    });
    if (res.status != 200 && res.status != 204) {
      throw 'admin faq DELETE category: HTTP ${res.status} ${res.responseText}';
    }
  }

  Future<void> deleteFaqEntry(String id) async {
    final res = await _request('DELETE', '/api/admin/faq', body: {
      'type': 'entry',
      'id': id,
    });
    if (res.status != 200 && res.status != 204) {
      throw 'admin faq DELETE entry: HTTP ${res.status} ${res.responseText}';
    }
  }

  Future<AdminPushBroadcastResult> sendPushBroadcast({
    required String title,
    required String body,
    String? actionUrl,
    bool dryRun = false,
  }) async {
    final payload = <String, dynamic>{
      'title': title,
      'body': body,
      if (actionUrl != null && actionUrl.trim().isNotEmpty) 'actionUrl': actionUrl.trim(),
      if (dryRun) 'dryRun': true,
    };
    final res = await _request('POST', '/api/admin/push-broadcast', body: payload);
    if (res.status != 200) {
      throw 'push broadcast POST: HTTP ${res.status} ${res.responseText}';
    }
    final txt = res.responseText?.trim() ?? '';
    final Map<String, dynamic> j = txt.isEmpty ? <String, dynamic>{} : jsonDecode(txt);
    return AdminPushBroadcastResult.fromJson(j);
  }

  Future<SystemHealthResult> fetchSystemHealth() async {
    final res = await _request('GET', '/api/admin/health');
    if (res.status != 200) {
      throw 'admin health GET: HTTP ${res.status} ${res.responseText}';
    }
    final txt = res.responseText ?? '{}';
    final raw = txt.trim().isEmpty ? <String, dynamic>{} : jsonDecode(txt);
    final map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    return SystemHealthResult.fromJson(map);
  }

  Future<RepReminderReport> triggerRepReminders() async {
    final res = await _request('POST', '/api/admin/rep-reminders');
    if (res.status != 200) {
      throw 'rep-reminders POST: HTTP ${res.status} ${res.responseText}';
    }
    final txt = res.responseText ?? '{}';
    final raw = txt.trim().isEmpty ? <String, dynamic>{} : jsonDecode(txt);
    final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return RepReminderReport.fromJson(map);
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

class RepReminderReport {
  final bool ok;
  final int remindersSent;
  final int eligible;
  final double delayDays;
  final List<RepReminderEntry> reminders;

  RepReminderReport({
    required this.ok,
    required this.remindersSent,
    required this.eligible,
    required this.delayDays,
    required this.reminders,
  });

  factory RepReminderReport.fromJson(Map<String, dynamic> json) {
    final rawList = json['reminders'];
    final entries = <RepReminderEntry>[];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map) {
          entries.add(RepReminderEntry.fromJson(item.cast<String, dynamic>()));
        }
      }
    }
    return RepReminderReport(
      ok: json['ok'] == true,
      remindersSent: (json['remindersSent'] is num) ? (json['remindersSent'] as num).toInt() : 0,
      eligible: (json['eligible'] is num) ? (json['eligible'] as num).toInt() : 0,
      delayDays: (json['delayDays'] is num) ? (json['delayDays'] as num).toDouble() : 0,
      reminders: entries,
    );
  }
}

class RepReminderEntry {
  final String ticket;
  final String? repId;
  final String repEmail;
  final String lang;

  RepReminderEntry({
    required this.ticket,
    required this.repId,
    required this.repEmail,
    required this.lang,
  });

  factory RepReminderEntry.fromJson(Map<String, dynamic> json) {
    return RepReminderEntry(
      ticket: json['ticket']?.toString() ?? '',
      repId: json['repId']?.toString(),
      repEmail: json['repEmail']?.toString() ?? '',
      lang: json['lang']?.toString() ?? '',
    );
  }
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
  static const purpleA = Color(0xFFF1E8FF);
  static const purpleB = Color(0xFF7E57C2);
}

class AdminTilePro extends StatefulWidget {
  final String label;
  final String? subtitle;
  final IconData icon;
  final Color colorA;
  final Color colorB;
  final int? count;
  final bool compact;
  final VoidCallback onTap;

  // NEU: optionaler Extra-Button in der Kachel
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onActionTap;

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
    this.actionLabel,
    this.actionIcon,
    this.onActionTap,
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

    final iconSize = widget.compact ? 40.0 : 48.0;

    final hasAction = widget.onActionTap != null;

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
                  color: isDark
                      ? cs.outlineVariant.withOpacity(0.35)
                      : cs.outlineVariant.withOpacity(0.25),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
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
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.label,
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                      fontSize: 14.5,
                    ),
                  ),
                  if ((widget.subtitle ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.subtitle!,
                      textAlign: TextAlign.start,
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 12.0,
                      ),
                    ),
                  ],

                  // NEU: Extra-Button in der Kachel
                  if (hasAction) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: widget.onActionTap,
                        icon: Icon(
                          widget.actionIcon ?? Icons.add,
                          size: 18,
                        ),
                        label: Text(
                          widget.actionLabel ?? 'Aktion',
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accent,
                          side: BorderSide(color: accent.withOpacity(0.85)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
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

class _UnderlineTagSyntax extends md.InlineSyntax {
  _UnderlineTagSyntax() : super(r'<u>(.*?)</u>');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('u', match[1]!));
    return true;
  }
}

class _MarkTagSyntax extends md.InlineSyntax {
  _MarkTagSyntax() : super(r'<mark>(.*?)</mark>');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('mark', match[1]!));
    return true;
  }
}

class _UnderlineMarkdownBuilder extends MarkdownElementBuilder {
  _UnderlineMarkdownBuilder(this.baseStyle);

  final TextStyle? baseStyle;

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    return Text(
      text.text,
      style: (preferredStyle ?? baseStyle)?.copyWith(
        decoration: TextDecoration.underline,
      ),
    );
  }
}

class _MarkMarkdownBuilder extends MarkdownElementBuilder {
  _MarkMarkdownBuilder(this.backgroundColor, this.textColor, this.baseStyle);

  final Color backgroundColor;
  final Color textColor;
  final TextStyle? baseStyle;

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        text.text,
        style: (preferredStyle ?? baseStyle)?.copyWith(color: textColor),
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
