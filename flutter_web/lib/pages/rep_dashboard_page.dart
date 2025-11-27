// lib/pages/rep_dashboard_page.dart
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../api/client.dart';
import 'rep_profile_page.dart';
import 'rep_support_contact_form.dart';
import 'dart:html' as html;
import '../l10n/app_localizations.dart';
import '../widgets/lang_action.dart';
import '../widgets/theme_action.dart' as w;
import '../services/app_prefs_scope.dart';
import '../widgets/legal_footer.dart';
import '../models/country.dart';
import '../utils/lang_utils.dart';
import '../widgets/password_field.dart';
import 'rep_wiki_list_page.dart';
import '../models/rep_download_item.dart';
import '../data/download_categories.dart';
import '../models/rep_early_warning.dart';
import 'rep_product_list_page.dart';

// ---- L10n-Helper (top-level) ----
extension _L10nX on BuildContext {
  AppLocalizations get t => AppLocalizations.of(this)!;
}

// Filtervarianten (intern noch genutzt)
enum _RepFilter { all, open, rejected, finished }

// Menü-Views
enum _RepView { menu, earlyWarning, open, all, customers, support, account, wiki, downloads }

enum _RepPasswordMode { manual, generated }

enum _DownloadsView { grid, list }

enum _RepMenuTileSize { small, medium, large }

class _RepMenuTileState {
  final String id;
  _RepMenuTileSize size;
  bool visible;

  _RepMenuTileState({required this.id, this.size = _RepMenuTileSize.medium, this.visible = true});

  _RepMenuTileState copy() => _RepMenuTileState(id: id, size: size, visible: visible);

  Map<String, Object> toJson() => {
        'id': id,
        'size': size.name,
        'visible': visible,
      };

  static _RepMenuTileState fromJson(Map<String, Object?> data) {
    final rawSize = (data['size'] ?? 'medium').toString();
    final size = _RepMenuTileSize.values.firstWhere(
      (s) => s.name == rawSize,
      orElse: () => _RepMenuTileSize.medium,
    );
    return _RepMenuTileState(
      id: (data['id'] ?? '').toString(),
      size: size,
      visible: data['visible'] != false,
    );
  }
}

class _RepMenuSectionState {
  final String id;
  final bool isSystem;
  final bool protected;
  String? l10nKey;
  String? customLabel;
  List<_RepMenuTileState> tiles;

  _RepMenuSectionState({
    required this.id,
    required this.tiles,
    this.isSystem = false,
    this.protected = false,
    this.l10nKey,
    this.customLabel,
  });

  _RepMenuSectionState copy() => _RepMenuSectionState(
        id: id,
        tiles: tiles.map((t) => t.copy()).toList(),
        isSystem: isSystem,
        protected: protected,
        l10nKey: l10nKey,
        customLabel: customLabel,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'l10nKey': l10nKey,
        'customLabel': customLabel,
        'isSystem': isSystem,
        'tiles': tiles.map((e) => e.toJson()).toList(),
        'protected': protected,
      };

  static _RepMenuSectionState fromJson(Map<String, Object?> raw) {
    final tiles = (raw['tiles'] as List?)?.whereType<Map>().map((e) => e.cast<String, Object?>()).toList();
    final legacyTitle = (raw['title'] ?? '').toString();
    final migrated = _RepDashboardPageState._migrateLegacySystemCategory(legacyTitle);
    final id = (raw['id'] ?? '').toString();
    final l10nKey = (raw['l10nKey'] ?? '').toString();
    final customLabel = (raw['customLabel'] ?? '').toString();
    final isSystem = raw['isSystem'] == true || migrated != null;
    final effectiveId = id.isNotEmpty
        ? id
        : migrated?.id ?? _RepDashboardPageState._slugForCategoryLabel(legacyTitle, fallback: customLabel);
    final systemConfig = isSystem ? _RepDashboardPageState._systemCategoryById(effectiveId) : null;
    final effectiveL10nKey = migrated?.l10nKey ?? (l10nKey.isEmpty ? null : l10nKey) ?? systemConfig?.l10nKey;
    return _RepMenuSectionState(
      id: effectiveId,
      l10nKey: effectiveL10nKey,
      customLabel: migrated != null
          ? null
          : isSystem
              ? null
              : (customLabel.isNotEmpty ? customLabel : legacyTitle),
      isSystem: isSystem,
      protected: raw['protected'] == true || (migrated?.protected ?? false) || (systemConfig?.protected ?? false) || isSystem,
      tiles: tiles == null ? <_RepMenuTileState>[] : tiles.map(_RepMenuTileState.fromJson).toList(),
    );
  }
}

class _RepMenuTileDescriptor {
  final String id;
  final Color color;
  final IconData icon;
  const _RepMenuTileDescriptor({required this.id, required this.color, required this.icon});
}

class _SystemCategoryConfig {
  final String id;
  final String l10nKey;
  final bool protected;
  const _SystemCategoryConfig({required this.id, required this.l10nKey, this.protected = true});
}

class _RepDraggedTile {
  final String tileId;
  final int sectionIndex;
  const _RepDraggedTile({required this.tileId, required this.sectionIndex});
}

class _RepDraggedSection {
  final int sectionIndex;
  const _RepDraggedSection({required this.sectionIndex});
}

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

  final TextEditingController _customerSearchCtrl = TextEditingController();
  String _customerSearch = '';
  
  /// Reklamationen (aus Backend)
  List<Map<String, dynamic>> _complaints = [];

  /// Early-Warning-Infos
  List<RepEarlyWarning> _warnings = const [];
  bool _warningsLoading = false;
  String? _warningError;

  // Downloads (Admin-gesteuert)
  List<RepDownloadItem> _downloads = const [];
  bool _downloadsLoading = false;
  String? _downloadsErr;
  String _downloadSearch = '';
  String _downloadBadgeFilter = 'all';
  _DownloadsView _downloadView = _DownloadsView.grid;
  final TextEditingController _downloadSearchCtrl = TextEditingController();

  bool _loading = true;
  String? _err;

  // alter Filter bleibt intern für _filteredComplaints
  _RepFilter _filter = _RepFilter.all;

  // neue Menü-/Seitenlogik
  _RepView _view = _RepView.menu;
  final GlobalKey<RepSupportContactFormState> _supportFormKey =
      GlobalKey<RepSupportContactFormState>();

  // Firmenfilter (Dropdown) – gilt für „Alle Reklamationen“ und „Offene Reklamationen“
  String? _selectedCompany;
  bool _showClosedAll = false;
  String _decisionFilter = '';
  String _statusFilter = '';

  // Filter für Reklamationsliste (z. B. aus Early-Warning)
  List<String> _complaintArticleFilter = const [];
  String _complaintCustomerFilter = '';

  // "NEU"-Badges: lokal gemerkte "schon gesehen" Kunden (E-Mails als Key)
  static const _seenKey = 'rep_seen_customers_v1';
  final Set<String> _seenCustomers = <String>{};

  // Dashboard-Layout
  static const _menuStoragePrefix = 'rep_menu_layout_v2_';
  final Map<String, _RepMenuTileDescriptor> _tileDescriptors = const {
    'earlyWarning': _RepMenuTileDescriptor(id: 'earlyWarning', color: Colors.orange, icon: Icons.warning_amber_outlined),
    'open': _RepMenuTileDescriptor(id: 'open', color: Colors.red, icon: Icons.report_gmailerrorred_outlined),
    'all': _RepMenuTileDescriptor(id: 'all', color: Colors.indigo, icon: Icons.all_inbox_outlined),
    'customers': _RepMenuTileDescriptor(id: 'customers', color: Colors.teal, icon: Icons.apartment_outlined),
    'account': _RepMenuTileDescriptor(id: 'account', color: Colors.blueGrey, icon: Icons.person_outline),
    'support': _RepMenuTileDescriptor(id: 'support', color: Colors.deepOrange, icon: Icons.support_agent_outlined),
    'downloads': _RepMenuTileDescriptor(id: 'downloads', color: Colors.deepPurple, icon: Icons.download_outlined),
    'wiki': _RepMenuTileDescriptor(id: 'wiki', color: Colors.green, icon: Icons.menu_book_outlined),
  };

  static const List<_SystemCategoryConfig> _systemCategories = [
    _SystemCategoryConfig(id: 'claims', l10nKey: 'rep_dash_cat_claims'),
    _SystemCategoryConfig(id: 'customers', l10nKey: 'rep_dash_cat_customers'),
    _SystemCategoryConfig(id: 'docs', l10nKey: 'rep_dash_cat_docs'),
  ];

  static const Map<String, String> _legacySystemCategoryLabels = {
    'reklamationen': 'claims',
    'claims': 'claims',
    'réclamations': 'claims',
    'reclamaciones': 'claims',
    'reclami': 'claims',
    'kunden & support': 'customers',
    'customers & support': 'customers',
    'clientes y soporte': 'customers',
    'clients et support': 'customers',
    'clienti e supporto': 'customers',
    'wissen & dokumente': 'docs',
    'knowledge & documents': 'docs',
    'conocimiento y documentos': 'docs',
    'connaissances et documents': 'docs',
    'conoscenza e documenti': 'docs',
  };

  static _SystemCategoryConfig? _systemCategoryById(String id) {
    for (final c in _systemCategories) {
      if (c.id == id) return c;
    }
    return null;
  }

  static _SystemCategoryConfig? _migrateLegacySystemCategory(String legacyTitle) {
    final normalized = _normalizeLabel(legacyTitle);
    final systemId = _legacySystemCategoryLabels[normalized];
    if (systemId == null) return null;
    return _systemCategoryById(systemId);
  }

  static String _normalizeLabel(String value) => value.trim().toLowerCase();

  static String _slugForCategoryLabel(String label, {String? fallback}) {
    final source = (label.isNotEmpty ? label : (fallback ?? '')).trim();
    if (source.isEmpty) return 'category_${DateTime.now().millisecondsSinceEpoch}';
    final sanitized = source
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return sanitized.isEmpty ? 'category_${DateTime.now().millisecondsSinceEpoch}' : sanitized;
  }

  static bool _isValidSection(_RepMenuSectionState section) {
    if (section.isSystem) {
      return (section.l10nKey ?? '').trim().isNotEmpty;
    }
    return (section.customLabel ?? '').trim().isNotEmpty;
  }
  List<_RepMenuSectionState> _menuSections = [];
  bool _menuEditMode = false;
  List<_RepMenuSectionState>? _menuBackup;
  bool _menuLayoutLoaded = false;
  
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

  String get _menuStorageKey {
    final id = (_me?['id'] ?? _me?['email'] ?? 'default').toString();
    return '$_menuStoragePrefix$id';
  }

  List<_RepMenuSectionState> _defaultMenuSections() {
    return [
      _RepMenuSectionState(
        id: 'claims',
        l10nKey: 'rep_dash_cat_claims',
        isSystem: true,
        protected: true,
        tiles: [
          _RepMenuTileState(id: 'earlyWarning', size: _RepMenuTileSize.large),
          _RepMenuTileState(id: 'open', size: _RepMenuTileSize.medium),
          _RepMenuTileState(id: 'all', size: _RepMenuTileSize.medium),
        ],
      ),
      _RepMenuSectionState(
        id: 'customers',
        l10nKey: 'rep_dash_cat_customers',
        isSystem: true,
        protected: true,
        tiles: [
          _RepMenuTileState(id: 'customers', size: _RepMenuTileSize.medium),
          _RepMenuTileState(id: 'support', size: _RepMenuTileSize.medium),
          _RepMenuTileState(id: 'account', size: _RepMenuTileSize.small),
        ],
      ),
      _RepMenuSectionState(
        id: 'docs',
        l10nKey: 'rep_dash_cat_docs',
        isSystem: true,
        protected: true,
        tiles: [
          _RepMenuTileState(id: 'downloads', size: _RepMenuTileSize.medium),
          _RepMenuTileState(id: 'wiki', size: _RepMenuTileSize.medium),
        ],
      ),
    ];
  }

  void _initMenuLayout() {
    if (_menuLayoutLoaded) return;
    _menuLayoutLoaded = true;
    final defaults = _defaultMenuSections();
    final loaded = _loadMenuLayout(defaults: defaults);
    setState(() => _menuSections = loaded);
  }

  List<_RepMenuSectionState> _loadMenuLayout({required List<_RepMenuSectionState> defaults}) {
    final raw = html.window.localStorage[_menuStorageKey];
    final known = _tileDescriptors.keys.toSet();
    if (raw == null) return defaults.map((e) => e.copy()).toList();

    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List) return defaults.map((e) => e.copy()).toList();

      final sections = <_RepMenuSectionState>[];
      final used = <String>{};

      for (final entry in parsed) {
        if (entry is! Map) continue;
        final section = _RepMenuSectionState.fromJson(entry.cast<String, Object?>());
        if (!_isValidSection(section)) continue;
        section.tiles = section.tiles.where((t) => known.contains(t.id)).toList();
        used.addAll(section.tiles.map((e) => e.id));
        sections.add(section);
      }

      for (final def in defaults) {
        final existing = sections.firstWhere(
          (s) => s.id == def.id,
          orElse: () => _RepMenuSectionState(id: '', tiles: []),
        );
        if (existing.id.isNotEmpty) {
          for (final tile in def.tiles) {
            if (used.contains(tile.id)) continue;
            existing.tiles.add(tile.copy());
            used.add(tile.id);
          }
          continue;
        }

        final copy = def.copy();
        sections.add(copy);
        used.addAll(copy.tiles.map((e) => e.id));
      }

      for (final id in known) {
        final already = used.contains(id);
        if (already) continue;
        final target = sections.isNotEmpty ? sections.first : null;
        if (target != null) {
          target.tiles.add(_RepMenuTileState(id: id));
        }
      }

      return sections.isEmpty ? defaults.map((e) => e.copy()).toList() : sections;
    } catch (_) {
      return defaults.map((e) => e.copy()).toList();
    }
  }

  void _persistMenuLayout() {
    try {
      html.window.localStorage[_menuStorageKey] = jsonEncode(
        _menuSections.map((s) => s.toJson()).toList(),
      );
    } catch (_) {}
  }

  void _resetMenuLayout() {
    setState(() {
      _menuSections = _defaultMenuSections();
      _menuEditMode = false;
    });
    _persistMenuLayout();
  }

  void _enterMenuEditMode() {
    setState(() {
      _menuBackup = _menuSections.map((e) => e.copy()).toList();
      _menuEditMode = true;
    });
  }

  void _cancelMenuEdit() {
    setState(() {
      if (_menuBackup != null) {
        _menuSections = _menuBackup!.map((e) => e.copy()).toList();
      }
      _menuEditMode = false;
    });
  }

  void _saveMenuEdit() {
    setState(() => _menuEditMode = false);
    _persistMenuLayout();
  }

  void _addMenuCategory() async {
    final titleCtrl = TextEditingController();
    final created = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Neue Kategorie'),
          content: TextField(
            controller: titleCtrl,
            decoration: const InputDecoration(labelText: 'Titel'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                Navigator.of(context).pop(title);
              },
              child: const Text('Hinzufügen'),
            ),
          ],
        );
      },
    );

    if (created == null || created.trim().isEmpty) return;

    var id = _slugForCategoryLabel(created.trim());
    if (_menuSections.any((s) => s.id == id)) {
      id = '${id}_${DateTime.now().millisecondsSinceEpoch}';
    }

    setState(() {
      _menuSections = [
        ..._menuSections,
        _RepMenuSectionState(id: id, customLabel: created.trim(), tiles: []),
      ];
    });
    _persistMenuLayout();
  }

  void _handleTileDrop(_RepDraggedTile data, int targetSection, int insertIndex) {
    if (targetSection < 0 || targetSection >= _menuSections.length) return;
    setState(() {
      if (data.sectionIndex < 0 || data.sectionIndex >= _menuSections.length) return;
      final fromSection = _menuSections[data.sectionIndex];
      final tileIndex = fromSection.tiles.indexWhere((t) => t.id == data.tileId);
      if (tileIndex == -1) return;
      final moving = fromSection.tiles.removeAt(tileIndex);

      final isSameSection = data.sectionIndex == targetSection;
      var targetIndex = insertIndex;
      if (isSameSection && insertIndex > tileIndex) targetIndex -= 1;

      final dest = _menuSections[targetSection];
      targetIndex = targetIndex.clamp(0, dest.tiles.length);
      dest.tiles.insert(targetIndex, moving);
    });
    _persistMenuLayout();
  }

  void _handleSectionDrop(_RepDraggedSection data, int targetIndex) {
    if (targetIndex < 0 || targetIndex > _menuSections.length) return;
    if (data.sectionIndex < 0 || data.sectionIndex >= _menuSections.length) return;
    setState(() {
      final moving = _menuSections.removeAt(data.sectionIndex);
      var insertIndex = targetIndex;
      if (targetIndex > data.sectionIndex) insertIndex -= 1;
      insertIndex = insertIndex.clamp(0, _menuSections.length);
      _menuSections.insert(insertIndex, moving);
    });
    _persistMenuLayout();
  }

  void _updateTileSize(String id, _RepMenuTileSize size) {
    setState(() {
      for (final section in _menuSections) {
        for (final tile in section.tiles) {
          if (tile.id == id) tile.size = size;
        }
      }
    });
    _persistMenuLayout();
  }

  void _toggleTileVisibility(String id, bool visible) {
    setState(() {
      _ensureTilePresent(id);
      for (final section in _menuSections) {
        for (final tile in section.tiles) {
          if (tile.id == id) tile.visible = visible;
        }
      }
    });
    _persistMenuLayout();
  }

  void _ensureTilePresent(String id) {
    if (!_tileDescriptors.containsKey(id)) return;
    for (final section in _menuSections) {
      if (section.tiles.any((t) => t.id == id)) return;
    }
    if (_menuSections.isEmpty) {
      _menuSections = _defaultMenuSections();
    }
    _menuSections.first.tiles.add(_RepMenuTileState(id: id));
  }

  List<_RepMenuTileState> _hiddenTiles() {
    final list = <_RepMenuTileState>[];
    for (final s in _menuSections) {
      list.addAll(s.tiles.where((t) => !t.visible));
    }
    return list;
  }

  Future<void> _openTileVisibilityDialog() async {
    final descriptors = _tileDescriptors.values.toList();
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) {
        final selected = {
          for (final section in _menuSections)
            for (final tile in section.tiles)
              if (tile.visible) tile.id,
        };
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Kacheln ein- oder ausblenden'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: descriptors.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final desc = descriptors[index];
                  final checked = selected.contains(desc.id);
                  return CheckboxListTile(
                    value: checked,
                    onChanged: (value) {
                      setDialogState(() {
                        if (value == true) {
                          selected.add(desc.id);
                        } else {
                          selected.remove(desc.id);
                        }
                      });
                    },
                    title: Text(_tileTitle(context, desc.id)),
                    secondary: Icon(desc.icon, color: desc.color),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(selected),
                child: const Text('Übernehmen'),
              ),
            ],
          );
        });
      },
    );

    if (result == null) return;

    for (final id in _tileDescriptors.keys) {
      _toggleTileVisibility(id, result.contains(id));
    }
  }

  String _tileTitle(BuildContext context, String id) {
    final t = context.t;
    switch (id) {
      case 'earlyWarning':
        return t.repMenuEarlyWarningTitle;
      case 'open':
        return t.rep_menu_open_title;
      case 'all':
        return t.rep_menu_all_title;
      case 'customers':
        return t.rep_menu_customers_title;
      case 'account':
        return t.rep_menu_account_title;
      case 'support':
        return t.rep_menu_support_title;
      case 'downloads':
        return t.rep_downloads_title;
      case 'wiki':
        return t.repwiki;
    }
    return id;
  }

  String _tileSubtitle(BuildContext context, String id) {
    final t = context.t;
    switch (id) {
      case 'earlyWarning':
        return t.repMenuEarlyWarningSubtitle;
      case 'open':
        return t.rep_menu_open_subtitle;
      case 'all':
        return t.rep_menu_all_subtitle;
      case 'customers':
        return t.rep_menu_customers_subtitle;
      case 'account':
        return t.rep_menu_account_subtitle;
      case 'support':
        return t.rep_menu_support_subtitle;
      case 'downloads':
        return t.rep_menu_downloads_subtitle;
      case 'wiki':
        return t.customer_knowledge;
    }
    return '';
  }

  int? _tileCount(String id, int allCount, int openCount) {
    switch (id) {
      case 'earlyWarning':
        return _warningsLoading ? null : _warnings.length;
      case 'open':
        return openCount;
      case 'all':
        return allCount;
      case 'customers':
        return _customers.length;
      case 'downloads':
        final downloadBadgeCount = _downloads.where((d) => d.badge.isNotEmpty).length;
        return downloadBadgeCount > 0 ? downloadBadgeCount : _downloads.length;
      default:
        return null;
    }
  }

  double _tileScale(_RepMenuTileSize size) {
    switch (size) {
      case _RepMenuTileSize.small:
        return 0.9;
      case _RepMenuTileSize.medium:
        return 1.05;
      case _RepMenuTileSize.large:
        return 1.3;
    }
  }

  Size _tileBoxSize(_RepMenuTileSize size, double baseWidth, double baseHeight) {
    final factor = _tileScale(size);
    return Size(baseWidth * factor, baseHeight * factor);
  }

  Widget _buildMenuTile(String id, bool compact, double scale, {
    required VoidCallback onTap,
    required int allCount,
    required int openCount,
    bool isPreview = false,
  }) {
    final desc = _tileDescriptors[id];
    if (desc == null) return const SizedBox.shrink();
    return _MenuCard(
      color: desc.color,
      icon: desc.icon,
      title: _tileTitle(context, id),
      subtitle: _tileSubtitle(context, id),
      count: _tileCount(id, allCount, openCount),
      compact: compact,
      scale: scale,
      onTap: _menuEditMode || isPreview ? () {} : onTap,
    );
  }

  void _handleTileAction(String id) async {
    if (!await _confirmLeaveCurrentView()) return;
    if (!mounted) return;
    setState(() {
      switch (id) {
        case 'earlyWarning':
          _view = _RepView.earlyWarning;
          break;
        case 'open':
          _filter = _RepFilter.open;
          _view = _RepView.open;
          break;
        case 'all':
          _view = _RepView.all;
          break;
        case 'customers':
          _view = _RepView.customers;
          break;
        case 'account':
          _view = _RepView.account;
          break;
        case 'support':
          _view = _RepView.support;
          break;
        case 'downloads':
          _view = _RepView.downloads;
          break;
        case 'wiki':
          _view = _RepView.wiki;
          break;
      }
    });
  }

  Future<bool> _confirmLeaveCurrentView() async {
    if (_view == _RepView.support) {
      final form = _supportFormKey.currentState;
      if (form != null) {
        final ok = await form.confirmLeave();
        if (!ok) return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _customerSearchCtrl.dispose();
    _downloadSearchCtrl.dispose();
    super.dispose();
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
      _warningsLoading = true;
      _warningError = null;
    });

    try {
      // Sicherstellen, dass repToken gültig ist
      await widget.api.ensureRepSession();

      final me   = await widget.api.repMe();
      final comp = await widget.api.repComplaints();
      final warningsRaw = await widget.api.repEarlyWarnings();

      if (mounted) {
        final meLang = (me['lang'] ?? '').toString().trim();
        if (isSupportedLangCode(meLang)) {
          final normalized = normalizeLangCode(meLang);
          final prefs = AppPrefsScope.of(context);
          final current = prefs.locale?.languageCode.toLowerCase() ?? '';
          if (current != normalized) {
            await prefs.setLang(normalized);
          }
        }
      }

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
            'repNote': s(c['repNote']),
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
            'repNote': '',
          });
        }
      }

      List<RepEarlyWarning> warnings = _warnings;
      String? warningErr;
      try {
        warnings = warningsRaw
            .whereType<Map<String, dynamic>>()
            .map((e) => RepEarlyWarning.fromJson(e))
            .toList(growable: false);
      } catch (e) {
        warningErr = e.toString();
      }

      List<RepDownloadItem> downloads = _downloads;
      String? downloadsErr;
      try {
        setState(() {
          _downloadsLoading = true;
          _downloadsErr = null;
        });
        downloads = await widget.api.repDownloads();
      } catch (e) {
        downloadsErr = e.toString();
      }

      if (!mounted) return;
      setState(() {
        _me = me;
        _customers  = customers;
        _complaints = comp;
        _warnings = warnings;
        _warningsLoading = false;
        _warningError = warningErr;
        _downloads = downloads;
        _downloadsErr = downloadsErr;
        _downloadsLoading = false;
      });
      _initMenuLayout();

    } catch (e) {
      final handled = await _handleUnauthorized(e);
      if (!mounted) return;
      if (handled) return;
      setState(() {
        _err = '$e';
        _warningsLoading = false;
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _warningsLoading = false;
      });
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

  Future<void> _createCustomerDialog() async {
    final t = context.t;
    final formKey = GlobalKey<FormState>();

    final companyCtrl    = TextEditingController();
    final firstNameCtrl  = TextEditingController();
    final lastNameCtrl   = TextEditingController();
    final emailCtrl      = TextEditingController();
    final streetCtrl     = TextEditingController();
    final zipCtrl        = TextEditingController();
    final cityCtrl       = TextEditingController();
    final phoneCtrl      = TextEditingController();
    final passwordCtrl   = TextEditingController();
    final password2Ctrl  = TextEditingController();

    Country? selectedCountry = kCountries.firstWhere(
      (c) => c.code == 'DE',
      orElse: () => kCountries.first,
    );

    String lang = 'de';
    String? locErr;
    bool saving = false;
    var passwordMode = _RepPasswordMode.manual;

    String mapError(String code) {
      switch (code) {
        case 'password_admin_secret':
          return t.rep_create_customer_password_admin_secret ?? code;
        default:
          return code;
      }
    }

    bool emailValid(String value) {
      final v = value.trim();
      if (v.isEmpty) return false;
      return v.contains('@') && v.contains('.');
    }

    List<DropdownMenuItem<String>> langItems() => [
          DropdownMenuItem(value: 'de', child: Text(t.langNameDE)),
          DropdownMenuItem(value: 'en', child: Text(t.langNameEN)),
          DropdownMenuItem(value: 'fr', child: Text(t.langNameFR)),
          DropdownMenuItem(value: 'it', child: Text(t.langNameIT)),
          DropdownMenuItem(value: 'es', child: Text(t.langNameES)),
        ];

    bool? result;

    try {
      result = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> submit() async {
              final form = formKey.currentState;
              if (form == null) return;
              if (!form.validate()) return;
              setLocal(() {
                locErr = null;
                saving = true;
              });

              final bool useGeneratedPassword = passwordMode == _RepPasswordMode.generated;

              final Map<String, dynamic> payload = {
                'company'    : companyCtrl.text.trim(),
                'contact'    : '${firstNameCtrl.text.trim()} ${lastNameCtrl.text.trim()}'.trim(),
                'firstName'  : firstNameCtrl.text.trim(),
                'lastName'   : lastNameCtrl.text.trim(),
                'email'      : emailCtrl.text.trim(),
                'street'     : streetCtrl.text.trim(),
                'zip'        : zipCtrl.text.trim(),
                'city'       : cityCtrl.text.trim(),
                'country'    : selectedCountry?.label(ctx) ?? '',
                'countryCode': selectedCountry?.code ?? '',
                'phone'      : phoneCtrl.text.trim(),
                'lang'       : lang,
                'passwordMode': useGeneratedPassword ? 'generated' : 'manual',
              };

              if (!useGeneratedPassword) {
                payload['password'] = passwordCtrl.text;
              }

              payload.removeWhere((key, value) => value is String && value.trim().isEmpty);

              try {
                await widget.api.ensureRepSession();
                await widget.api.repCreateCustomer(payload);
                if (Navigator.of(ctx).canPop()) {
                  Navigator.of(ctx).pop(true);
                }
              } catch (e) {
                setLocal(() {
                  saving = false;
                  if (e is ApiError) {
                    locErr = mapError(e.message);
                  } else {
                    locErr = '$e';
                  }
                });
              }
            }

            String? requiredValidator(String? value) {
              if (value == null || value.trim().isEmpty) {
                return t.required_fields;
              }
              return null;
            }

            return AlertDialog(
              title: Text(t.rep_create_customer_title ?? t.rep_create_customer ?? t.addCustomer),
              content: Form(
                key: formKey,
                child: SizedBox(
                  width: 520,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: companyCtrl,
                          decoration: InputDecoration(labelText: t.company_plain),
                          autofillHints: const [AutofillHints.organizationName],
                          validator: requiredValidator,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: firstNameCtrl,
                                decoration: InputDecoration(labelText: t.first_name),
                                textInputAction: TextInputAction.next,
                                validator: requiredValidator,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: lastNameCtrl,
                                decoration: InputDecoration(labelText: t.last_name),
                                textInputAction: TextInputAction.next,
                                validator: requiredValidator,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: emailCtrl,
                          decoration: InputDecoration(labelText: t.customerMail),
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            final v = value?.trim() ?? '';
                            if (v.isEmpty) return t.required_fields;
                            if (!emailValid(v)) return t.email_invalid;
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: streetCtrl,
                          decoration: InputDecoration(labelText: t.street),
                          textInputAction: TextInputAction.next,
                          validator: requiredValidator,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: zipCtrl,
                                decoration: InputDecoration(labelText: t.zip),
                                textInputAction: TextInputAction.next,
                                validator: requiredValidator,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: cityCtrl,
                                decoration: InputDecoration(labelText: t.city),
                                textInputAction: TextInputAction.next,
                                validator: requiredValidator,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<Country>(
                          value: selectedCountry,
                          decoration: InputDecoration(labelText: t.country),
                          isExpanded: true,
                          items: kCountries
                              .map(
                                (c) => DropdownMenuItem<Country>(
                                  value: c,
                                  child: Text(c.label(ctx)),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setLocal(() => selectedCountry = value),
                          validator: (value) => value == null ? t.required_fields : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: phoneCtrl,
                          decoration: InputDecoration(labelText: t.phone),
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: lang,
                          decoration: InputDecoration(labelText: t.langMenuTooltip),
                          items: langItems(),
                          onChanged: (v) => setLocal(() => lang = v ?? 'de'),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          t.rep_create_customer_password_mode_label ?? t.password,
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        RadioListTile<_RepPasswordMode>(
                          value: _RepPasswordMode.manual,
                          groupValue: passwordMode,
                          onChanged: saving
                              ? null
                              : (value) => setLocal(() => passwordMode = value ?? _RepPasswordMode.manual),
                          title: Text(t.rep_create_customer_password_mode_manual ?? t.password),
                          subtitle: Text(t.rep_create_customer_password_mode_manual_hint ?? ''),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                        RadioListTile<_RepPasswordMode>(
                          value: _RepPasswordMode.generated,
                          groupValue: passwordMode,
                          onChanged: saving
                              ? null
                              : (value) => setLocal(() => passwordMode = value ?? _RepPasswordMode.manual),
                          title: Text(t.rep_create_customer_password_mode_generated ?? ''),
                          subtitle: Text(t.rep_create_customer_password_mode_generated_hint ?? ''),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                        if (passwordMode == _RepPasswordMode.manual) ...[
                          const SizedBox(height: 12),
                          PasswordField(
                            controller: passwordCtrl,
                            decoration: InputDecoration(labelText: t.password),
                            textInputAction: TextInputAction.next,
                            validator: (value) {
                              final v = value ?? '';
                              if (v.trim().isEmpty) return t.password_required;
                              if (v.length < 8) return t.password_min_length;
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          PasswordField(
                            controller: password2Ctrl,
                            decoration: InputDecoration(labelText: t.password_repeat),
                            textInputAction: TextInputAction.done,
                            validator: (value) {
                              if (value == null || value.isEmpty) return t.password_required;
                              if (value != passwordCtrl.text) return t.password_mismatch;
                              return null;
                            },
                          ),
                        ],
                        if (locErr != null) ...[
                          const SizedBox(height: 12),
                          Text(locErr!, style: const TextStyle(color: Colors.red)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                if (saving)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(ctx).pop(false),
                  child: Text(t.close),
                ),
                ElevatedButton.icon(
                  onPressed: saving ? null : submit,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(t.save),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      companyCtrl.dispose();
      firstNameCtrl.dispose();
      lastNameCtrl.dispose();
      emailCtrl.dispose();
      streetCtrl.dispose();
      zipCtrl.dispose();
      cityCtrl.dispose();
      phoneCtrl.dispose();
      passwordCtrl.dispose();
      password2Ctrl.dispose();
    }

    if (result == true) {
      await _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.rep_create_customer_success ?? t.saved)),
      );
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
    final t = context.t;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title: Text(t.logoutTitle),
            content: Text(t.logoutConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: Text(t.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogCtx, true),
                child: Text(t.logout),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    await widget.api.repLogout();
    try { html.window.localStorage.remove('dfs_mode'); } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (Route<dynamic> r) => false);
  }

  // ---- Status-Logik (wie bisher) ----
  bool _isClosed(Map<String, dynamic> c) {
    final s = int.tryParse((c['status'] ?? '').toString()) ?? 0;
    final dec = (c['decision'] ?? '').toString();
    return s == 5 || dec == 'rejected';
  }

  bool _isRejected(Map<String, dynamic> c) {
    final dec = (c['decision'] ?? '').toString();
    return dec == 'rejected';
  }

  bool _matchesDecisionFilter(Map<String, dynamic> c) {
    final dec = (c['decision'] ?? '').toString().trim();
    final filter = _decisionFilter.trim();
    if (filter.isEmpty) return true;
    if (filter == 'pending') return dec.isEmpty;
    return dec == filter;
  }

  bool _matchesStatusFilter(Map<String, dynamic> c) {
    final filter = _statusFilter.trim();
    if (filter.isEmpty) return true;
    final code = int.tryParse(filter);
    if (code == null) return true;
    final status = int.tryParse((c['status'] ?? '').toString()) ?? 0;
    return status == code;
  }

  List<DropdownMenuItem<String>> _decisionFilterItems(AppLocalizations t) {
    return [
      DropdownMenuItem(value: '', child: Text(t.allDecisions ?? 'Alle Entscheidungen')),
      DropdownMenuItem(value: 'pending', child: Text(t.decision_pending ?? 'Entscheidung offen')),
      DropdownMenuItem(value: 'accepted', child: Text(t.decision_accepted)),
      DropdownMenuItem(value: 'rejected', child: Text(t.decision_rejected)),
    ];
  }

  List<DropdownMenuItem<String>> _statusFilterItems(AppLocalizations t) {
    return [
      DropdownMenuItem(value: '', child: Text(t.allStatus ?? 'Alle Stati')),
      DropdownMenuItem(value: '1', child: Text(t.status_sent)),
      DropdownMenuItem(value: '2', child: Text(t.status_in_progress)),
      DropdownMenuItem(value: '3', child: Text(t.status_question)),
      DropdownMenuItem(value: '4', child: Text(t.status_rework)),
      DropdownMenuItem(value: '5', child: Text(t.status_closed)),
    ];
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
            .where((c) => (int.tryParse((c['status'] ?? '').toString()) ?? 0) == 5)
            .toList(growable: false);
    }
  }

  static const List<String> _articleKeys = [
    'article',
    'article_no',
    'articleNo',
    'articleNumber',
    'article_name',
    'product',
    'productName',
    'artikel',
    'artikelnummer',
  ];

  String _articleFromComplaint(Map<String, dynamic> c) {
    String pick(Map<dynamic, dynamic>? source) {
      if (source == null) return '';
      for (final key in _articleKeys) {
        if (source.containsKey(key)) {
          final v = (source[key] ?? '').toString().trim();
          if (v.isNotEmpty) return v;
        }
      }
      return '';
    }

    final payload = c['payload'];
    final product = payload is Map ? payload['product'] as Map<dynamic, dynamic>? : null;
    for (final src in [c, payload is Map ? payload as Map<dynamic, dynamic> : null, product]) {
      final v = pick(src);
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  bool _matchesWarningFilters(Map<String, dynamic> c) {
    if (_complaintArticleFilter.isNotEmpty) {
      final normalized = _complaintArticleFilter.map((e) => e.toLowerCase()).toSet();
      final article = _articleFromComplaint(c).toLowerCase();
      if (article.isEmpty || !normalized.contains(article)) return false;
    }
    if (_complaintCustomerFilter.trim().isNotEmpty) {
      final target = _complaintCustomerFilter.trim().toLowerCase();
      final email = (c['customerEmail'] ?? c['email'] ?? '').toString().toLowerCase();
      if (email.isEmpty || !email.contains(target)) return false;
    }
    return true;
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
    final finishedCount = _complaints.where((c) => (int.tryParse((c['status'] ?? '').toString()) ?? 0) == 5).length;
    final title = switch (_view) {
      _RepView.menu      => t.rep_dashboard,
      _RepView.earlyWarning => t.repEarlyWarningTitle,
      _RepView.open      => t.complaintsMyCustomer,
      _RepView.all       => t.rep_menu_all_title,
      _RepView.customers => t.myCustomers,
      _RepView.support   => t.rep_support_contact_title,
      _RepView.account   => t.profilePW,
      _RepView.wiki      => t.repwiki,
      _RepView.downloads => t.rep_downloads_title,
    };

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _err != null
            ? Center(child: Text(_err!, style: const TextStyle(color: Colors.red)))
            : switch (_view) {
                _RepView.menu      => _buildMenu(allCount, openCount, rejectedCount, finishedCount),
                _RepView.earlyWarning => _buildEarlyWarningView(),
                _RepView.open      => _scrollWrap(_buildOpenComplaints()),
                _RepView.all       => _scrollWrap(_buildAllComplaints()),
                _RepView.customers => _scrollWrap(_buildCustomersCard()),
                _RepView.support   => _scrollWrap(_buildSupportContactCard()),
                _RepView.account   => _scrollWrap(_buildAccountCard()),
                _RepView.wiki      => RepWikiListPage(api: widget.api),
                _RepView.downloads => _scrollWrap(_buildDownloadsView()),
              };

    final canGoBack = _view != _RepView.menu;

    return WillPopScope(
      onWillPop: () async {
        if (canGoBack) {
          final ok = await _confirmLeaveCurrentView();
          if (!ok) return false;
          if (mounted) {
            setState(() => _view = _RepView.menu);
          }
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
                  onPressed: () async {
                    if (!await _confirmLeaveCurrentView()) return;
                    if (!mounted) return;
                    setState(() => _view = _RepView.menu);
                  },
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
  Widget _buildMenu(int allCount, int openCount, int _rejectedCount, int _finishedCount) {
    return LayoutBuilder(builder: (ctx, c) {
      final width = c.maxWidth;
      final isPhone = width < 640;
      final isTablet = width < 1180;
      final baseWidth = isPhone
          ? 170.0
          : isTablet
              ? 210.0
              : 240.0;
      final aspect = isPhone ? 0.95 : isTablet ? 1.04 : 1.1;
      final baseHeight = baseWidth / aspect;
      final spacing = isPhone ? 14.0 : 20.0;
      final runSpacing = isPhone ? 18.0 : 26.0;
      final compact = isPhone;
      final sections = _menuSections.isEmpty ? _defaultMenuSections() : _menuSections;
      final hidden = _hiddenTiles();

      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Vertreter-Dashboard',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  if (_menuEditMode)
                    ...[
                      OutlinedButton.icon(
                        onPressed: _cancelMenuEdit,
                        icon: const Icon(Icons.close_outlined),
                        label: const Text('Abbrechen'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: _saveMenuEdit,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Speichern'),
                      ),
                    ]
                  else
                    FilledButton.icon(
                      onPressed: _enterMenuEditMode,
                      icon: const Icon(Icons.dashboard_customize_outlined),
                      label: const Text('Dashboard anpassen'),
                    ),
                ],
              ),
            ),
          ),
          if (_menuEditMode)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _addMenuCategory,
                      icon: const Icon(Icons.add_box_outlined),
                      label: const Text('Kategorie hinzufügen'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _openTileVisibilityDialog,
                      icon: const Icon(Icons.checklist_rtl),
                      label: const Text('Kacheln auswählen'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _resetMenuLayout,
                      icon: const Icon(Icons.refresh_outlined),
                      label: const Text('Standardlayout wiederherstellen'),
                    ),
                  ],
                ),
              ),
            ),
          if (_menuEditMode) _buildSectionDropZone(index: 0),
          for (var i = 0; i < sections.length; i++) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                child: _buildSectionHeader(sections[i], i),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, i == sections.length - 1 ? 24 : 10),
                child: _buildSectionGrid(
                  section: sections[i],
                  sectionIndex: i,
                  baseWidth: baseWidth,
                  baseHeight: baseHeight,
                  spacing: spacing,
                  runSpacing: runSpacing,
                  compact: compact,
                  allCount: allCount,
                  openCount: openCount,
                ),
              ),
            ),
            if (_menuEditMode) _buildSectionDropZone(index: i + 1),
          ],
          if (_menuEditMode && hidden.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                child: _buildHiddenTilesBanner(hidden, baseWidth, baseHeight, spacing, compact, allCount, openCount),
              ),
            ),
        ],
      );
    });
  }

  String _sectionLabel(_RepMenuSectionState section) {
    if (section.isSystem && section.l10nKey != null) {
      switch (section.l10nKey) {
        case 'rep_dash_cat_claims':
          return context.t.repDashCatClaims ?? 'Reklamationen';
        case 'rep_dash_cat_customers':
          return context.t.repDashCatCustomers ?? 'Kunden & Support';
        case 'rep_dash_cat_docs':
          return context.t.repDashCatDocs ?? 'Wissen & Dokumente';
      }
    }
    return section.customLabel?.trim().isNotEmpty == true
        ? section.customLabel!.trim()
        : (section.l10nKey ?? section.id);
  }

  Widget _buildSectionHeader(_RepMenuSectionState section, int index) {
    final theme = Theme.of(context);
    final label = _sectionLabel(section);
    return Row(
      children: [
        if (_menuEditMode)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: LongPressDraggable<_RepDraggedSection>(
              data: _RepDraggedSection(sectionIndex: index),
              feedback: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(label, style: theme.textTheme.titleMedium),
                ),
              ),
              child: const Icon(Icons.drag_indicator, color: Colors.grey),
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Container(height: 2, width: 48, color: theme.colorScheme.primary.withOpacity(0.35)),
            ],
          ),
        ),
        if (_menuEditMode)
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Kategorie umbenennen',
                icon: const Icon(Icons.edit_outlined),
                onPressed: section.protected ? null : () => _renameSection(section),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: 'Kategorie löschen',
                icon: const Icon(Icons.delete_outline),
                onPressed: section.protected ? null : () => _removeSection(index),
              ),
            ],
          ),
      ],
    );
  }

  void _renameSection(_RepMenuSectionState section) async {
    final ctrl = TextEditingController(text: _sectionLabel(section));
    final updated = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Kategorie umbenennen'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Titel'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () {
                final v = ctrl.text.trim();
                if (v.isEmpty) return;
                Navigator.of(context).pop(v);
              },
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    );
    if (updated == null) return;
    setState(() {
      section.customLabel = updated.trim();
      section.l10nKey = section.isSystem ? section.l10nKey : null;
    });
    _persistMenuLayout();
  }

  void _removeSection(int index) {
    if (index < 0 || index >= _menuSections.length) return;
    final section = _menuSections[index];
    if (section.protected) return;
    setState(() {
      final target = index > 0 ? _menuSections[index - 1] : (_menuSections.length > 1 ? _menuSections[1] : null);
      if (target != null) {
        target.tiles.addAll(section.tiles);
      }
      _menuSections.removeAt(index);
    });
    _persistMenuLayout();
  }

  Widget _buildSectionGrid({
    required _RepMenuSectionState section,
    required int sectionIndex,
    required double baseWidth,
    required double baseHeight,
    required double spacing,
    required double runSpacing,
    required bool compact,
    required int allCount,
    required int openCount,
  }) {
    final visibleTiles = section.tiles.where((t) => _menuEditMode || t.visible).toList();
    if (visibleTiles.isEmpty && !_menuEditMode) {
      return const SizedBox.shrink();
    }

    final children = <Widget>[];

    if (_menuEditMode) {
      children.add(_buildTileDropTarget(
        sectionIndex: sectionIndex,
        insertIndex: 0,
        size: _tileBoxSize(_RepMenuTileSize.medium, baseWidth, baseHeight),
        spacing: spacing,
      ));
    }

    for (var i = 0; i < visibleTiles.length; i++) {
      final tile = visibleTiles[i];
      children.add(_buildDraggableTile(
        tile: tile,
        sectionIndex: sectionIndex,
        tileIndex: i,
        baseWidth: baseWidth,
        baseHeight: baseHeight,
        spacing: spacing,
        compact: compact,
        allCount: allCount,
        openCount: openCount,
      ));
      if (_menuEditMode) {
        children.add(_buildTileDropTarget(
          sectionIndex: sectionIndex,
          insertIndex: i + 1,
          size: _tileBoxSize(tile.size, baseWidth, baseHeight),
          spacing: spacing,
        ));
      }
    }

    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      children: children,
    );
  }

  Widget _buildTileDropTarget({
    required int sectionIndex,
    required int insertIndex,
    required Size size,
    required double spacing,
  }) {
    return DragTarget<_RepDraggedTile>(
      onWillAccept: (_) => true,
      onAccept: (data) => _handleTileDrop(data, sectionIndex, insertIndex),
      builder: (context, candidate, _) {
        final highlight = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: size.width,
          height: size.height,
          margin: EdgeInsets.only(right: spacing / 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: highlight ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
              width: highlight ? 2.4 : 1.2,
            ),
            color: highlight ? Theme.of(context).colorScheme.primary.withOpacity(0.08) : null,
          ),
          child: Center(
            child: Icon(Icons.open_with_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        );
      },
    );
  }

  Widget _buildDraggableTile({
    required _RepMenuTileState tile,
    required int sectionIndex,
    required int tileIndex,
    required double baseWidth,
    required double baseHeight,
    required double spacing,
    required bool compact,
    required int allCount,
    required int openCount,
  }) {
    final size = _tileBoxSize(tile.size, baseWidth, baseHeight);
    final scale = _tileScale(tile.size);
    final card = SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        children: [
          Positioned.fill(
            child: _buildMenuTile(
              tile.id,
              compact,
              scale,
              allCount: allCount,
              openCount: openCount,
              onTap: () => _handleTileAction(tile.id),
            ),
          ),
          if (_menuEditMode)
            Positioned(
              top: 10,
              right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    height: 38,
                    child: DropdownButton<_RepMenuTileSize>(
                      value: tile.size,
                      underline: const SizedBox.shrink(),
                      onChanged: (v) {
                        if (v != null) _updateTileSize(tile.id, v);
                      },
                      items: _RepMenuTileSize.values
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                switch (s) {
                                  _RepMenuTileSize.small => 'Klein',
                                  _RepMenuTileSize.medium => 'Standard',
                                  _RepMenuTileSize.large => 'Groß',
                                },
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  IconButton.filledTonal(
                    tooltip: tile.visible ? 'Kachel ausblenden' : 'Kachel einblenden',
                    icon: Icon(tile.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => _toggleTileVisibility(tile.id, !tile.visible),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    if (!_menuEditMode) return card;

    return LongPressDraggable<_RepDraggedTile>(
      data: _RepDraggedTile(tileId: tile.id, sectionIndex: sectionIndex),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: _buildMenuTile(
            tile.id,
            compact,
            scale,
            allCount: allCount,
            openCount: openCount,
            isPreview: true,
            onTap: () {},
          ),
        ),
      ),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      child: DragTarget<_RepDraggedTile>(
        onWillAccept: (_) => true,
        onAccept: (data) => _handleTileDrop(data, sectionIndex, tileIndex),
        builder: (context, candidate, _) {
          final highlight = candidate.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: highlight ? Theme.of(context).colorScheme.primary : Colors.transparent,
                width: highlight ? 2 : 0,
              ),
            ),
            child: card,
          );
        },
      ),
    );
  }

  SliverToBoxAdapter _buildSectionDropZone({required int index}) {
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: DragTarget<_RepDraggedSection>(
        onWillAccept: (_) => true,
        onAccept: (data) => _handleSectionDrop(data, index),
        builder: (context, candidate, rejected) {
          final highlight = candidate.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            height: 46,
            decoration: BoxDecoration(
              color: highlight ? theme.colorScheme.primary.withOpacity(0.08) : theme.colorScheme.surfaceVariant.withOpacity(0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: highlight ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                width: highlight ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.swap_vert, color: highlight ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  'Kategorie hier ablegen',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: highlight ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
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

  Widget _buildHiddenTilesBanner(List<_RepMenuTileState> hidden, double baseWidth, double baseHeight, double spacing, bool compact, int allCount, int openCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.archive_outlined),
            const SizedBox(width: 8),
            Text('Ausgeblendete Kacheln', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: hidden
              .map(
                (t) => SizedBox(
                  width: _tileBoxSize(t.size, baseWidth, baseHeight).width,
                  height: _tileBoxSize(t.size, baseWidth, baseHeight).height,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _buildMenuTile(
                          t.id,
                          compact,
                          _tileScale(t.size),
                          allCount: allCount,
                          openCount: openCount,
                          isPreview: true,
                          onTap: () {},
                        ),
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: IconButton.filled(
                          tooltip: 'Einblenden',
                          icon: const Icon(Icons.visibility_outlined),
                          onPressed: () => _toggleTileVisibility(t.id, true),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Color _levelColor(String level, ColorScheme cs) {
    switch (level) {
      case 'critical':
        return Colors.red.shade600;
      case 'warn':
        return Colors.orange.shade600;
      default:
        return cs.primary;
    }
  }

  String _levelLabel(AppLocalizations t, String level) {
    switch (level) {
      case 'critical':
        return t.repEarlyWarningLevelCritical;
      case 'warn':
        return t.repEarlyWarningLevelWarn;
      default:
        return t.repEarlyWarningLevelInfo;
    }
  }

  void _openProductsForWarning(RepEarlyWarning warning) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RepProductListPage(
          articleNumbers: warning.articleNumbers,
          productGroup: warning.productGroup,
          title: warning.productGroup ?? context.t.repEarlyWarningProductsTitle,
        ),
      ),
    );
  }

  void _openComplaintsForWarning(RepEarlyWarning warning) {
    setState(() {
      _complaintArticleFilter = warning.articleNumbers;
      _complaintCustomerFilter = warning.customerEmail ?? '';
      _filter = _RepFilter.all;
      _view = _RepView.all;
    });
  }

  Widget _buildTrendBar(AppLocalizations t, RepEarlyWarning warning) {
    final cs = Theme.of(context).colorScheme;
    final maxCount = math.max(warning.recentCount, warning.previousCount);
    if (maxCount == 0) return const SizedBox.shrink();
    final recentWidth = warning.recentCount / maxCount;
    final prevWidth = warning.previousCount / maxCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.repEarlyWarningTrendTitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.repEarlyWarningRecentLabel(warning.recentCount)),
                  const SizedBox(height: 4),
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: recentWidth.clamp(0, 1).toDouble(),
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.repEarlyWarningPreviousLabel(warning.previousCount)),
                  const SizedBox(height: 4),
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: cs.secondary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: prevWidth.clamp(0, 1).toDouble(),
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.secondary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openWarningDetails(RepEarlyWarning warning) async {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final levelColor = _levelColor(warning.level, cs);
        return AlertDialog(
          title: Text(warning.title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_outlined, color: levelColor),
                    const SizedBox(width: 8),
                    Text(
                      _levelLabel(t, warning.level),
                      style: TextStyle(color: levelColor, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(warning.description),
                if ((warning.productGroup ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Chip(label: Text(warning.productGroup!)),
                ],
                const SizedBox(height: 12),
                _buildTrendBar(t, warning),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (warning.articleNumbers.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        children: warning.articleNumbers
                            .map((a) => Chip(label: Text('${t.repEarlyWarningArticleLabel}: $a')))
                            .toList(),
                      ),
                    if ((warning.customerEmail ?? '').isNotEmpty)
                      Chip(label: Text('${t.repEarlyWarningCustomerLabel}: ${warning.customerEmail}')),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                _openProductsForWarning(warning);
              },
              icon: const Icon(Icons.list_alt_outlined),
              label: Text(t.repEarlyWarningOpenProducts),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                _openComplaintsForWarning(warning);
              },
              icon: const Icon(Icons.assignment_outlined),
              label: Text(t.repEarlyWarningOpenComplaints),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(t.close),
            ),
          ],
        );
      },
    );
  }

  Widget _warningCard(RepEarlyWarning warning, bool compact) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    final levelColor = _levelColor(warning.level, cs);

    return InkWell(
      onTap: () => _openWarningDetails(warning),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: levelColor.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _levelLabel(t, warning.level),
                      style: TextStyle(color: levelColor, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.trending_up, color: levelColor),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                warning.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(warning.description),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if ((warning.productGroup ?? '').isNotEmpty)
                    Chip(label: Text(warning.productGroup!)),
                  if ((warning.customerEmail ?? '').isNotEmpty)
                    Chip(label: Text('${t.repEarlyWarningCustomerLabel}: ${warning.customerEmail}')),
                  if (warning.articleNumbers.isNotEmpty)
                    ...warning.articleNumbers.map(
                      (a) => Chip(label: Text('${t.repEarlyWarningArticleLabel}: $a')),
                    ),
                ],
              ),
              const Spacer(),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _openWarningDetails(warning),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(t.repEarlyWarningDetails),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEarlyWarningView() {
    final t = context.t;
    if (_warningsLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    }
    if (_warningError != null) {
      return Center(child: Text(_warningError!, style: const TextStyle(color: Colors.red)));
    }
    if (_warnings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.celebration_outlined, size: 42),
            const SizedBox(height: 8),
            Text(t.repEarlyWarningEmpty, textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isPhone = width < 640;
        final crossAxisCount = width >= 1300
            ? 3
            : width >= 900
                ? 2
                : 1;
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 18,
            crossAxisSpacing: 18,
            childAspectRatio: isPhone ? 0.95 : 1.2,
          ),
          itemCount: _warnings.length,
          itemBuilder: (_, i) => _warningCard(_warnings[i], isPhone),
        );
      },
    );
  }

  Widget _buildSupportContactCard() {
    String s(Object? v) => (v ?? '').toString().trim();

    final firstName = s(_me?['firstName']);
    final lastName  = s(_me?['lastName']);
    final email     = s(_me?['email']);
    final region    = s(_me?['region']);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: RepSupportContactForm(
          key: _supportFormKey,
          api: widget.api,
          repFirstName: firstName,
          repLastName: lastName,
          repEmail: email,
          repRegion: region,
          onCancel: () {
            if (mounted) {
              setState(() => _view = _RepView.menu);
            }
          },
          onSent: () {
            if (mounted) {
              setState(() => _view = _RepView.menu);
            }
          },
        ),
      ),
    );
  }

  RepDownloadItem _clearDownloadBadge(RepDownloadItem item) {
    return RepDownloadItem(
      id: item.id,
      title: item.title,
      description: item.description,
      category: item.category,
      badge: '',
      downloadUrl: item.downloadUrl,
      fileName: item.fileName,
      mime: item.mime,
      size: item.size,
      updatedAt: item.updatedAt,
      version: item.version,
      active: item.active,
    );
  }

  Future<void> _openDownload(RepDownloadItem item) async {
    await widget.api.repMarkDownloadSeen(item.id);
    if (!mounted) return;
    setState(() {
      _downloads = _downloads
          .map((d) => d.id == item.id ? _clearDownloadBadge(d) : d)
          .toList(growable: false);
    });
    html.window.open(item.downloadUrl, '_blank');
  }

  String _formatDownloadSize(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size > 900 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size >= 10 || unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  String _formatDownloadDate(int ts) {
    if (ts <= 0) return '—';
    return DateFormat('dd.MM.yyyy').format(DateTime.fromMillisecondsSinceEpoch(ts));
  }

  List<RepDownloadItem> _filteredDownloads() {
    List<RepDownloadItem> list = _downloads;
    if (_downloadSearch.trim().isNotEmpty) {
      final q = _downloadSearch.trim().toLowerCase();
      list = list.where((d) {
        return d.title.toLowerCase().contains(q) ||
            d.description.toLowerCase().contains(q) ||
            d.category.toLowerCase().contains(q);
      }).toList();
    }
    if (_downloadBadgeFilter != 'all') {
      list = list.where((d) {
        if (_downloadBadgeFilter == 'none') return d.badge.isEmpty;
        return d.badge == _downloadBadgeFilter;
      }).toList();
    }
    return list;
  }

  List<MapEntry<String, List<RepDownloadItem>>> _groupDownloadsByCategory(List<RepDownloadItem> list) {
    final map = <String, List<RepDownloadItem>>{};
    for (final item in list) {
      final key = item.category.trim().isEmpty ? '__uncategorized' : item.category.trim();
      map.putIfAbsent(key, () => []).add(item);
    }
    final orderedKeys = <String>[];
    for (final name in kDefaultDownloadCategories) {
      if (map.containsKey(name)) orderedKeys.add(name);
    }
    final remaining = map.keys
        .where((k) => k != '__uncategorized' && !orderedKeys.contains(k))
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    orderedKeys.addAll(remaining);
    if (map.containsKey('__uncategorized')) orderedKeys.add('__uncategorized');
    return orderedKeys.map((k) => MapEntry(k, map[k]!)).toList();
  }

  Widget _buildDownloadListRow(AppLocalizations t, RepDownloadItem item, bool isPhone) {
    final badgeLabel = item.badge == 'change'
        ? t.rep_downloads_change
        : item.badge == 'new'
            ? t.rep_downloads_new
            : '';

    final accent = badgeLabel.isNotEmpty ? (item.badge == 'change' ? Colors.amber : Colors.blue) : Colors.teal;

    final badge = badgeLabel.isNotEmpty
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fiber_manual_record, size: 9, color: accent.shade700),
                const SizedBox(width: 3),
                Text(badgeLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: -0.1)),
              ],
            ),
          )
        : null;

    final metaTextStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade400);

    if (isPhone) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor.withOpacity(0.4),
          border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.18))),
        ),
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
                        item.title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            item.description,
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (badge != null)
                        Padding(padding: const EdgeInsets.only(top: 5), child: badge),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _openDownload(item),
                  icon: const Icon(Icons.download_outlined, size: 22),
                  tooltip: t.download,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: Text(item.category.isEmpty ? '—' : item.category, style: Theme.of(context).textTheme.bodySmall)),
                const SizedBox(width: 10),
                Text(_formatDownloadSize(item.size), style: metaTextStyle),
                const SizedBox(width: 10),
                Text(_formatDownloadDate(item.updatedAt), style: metaTextStyle),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(0.4),
        border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.18))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      badge,
                    ],
                  ],
                ),
                if (item.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      item.description,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(item.category.isEmpty ? '—' : item.category, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            flex: 2,
            child: Text(_formatDownloadSize(item.size), style: metaTextStyle),
          ),
          Expanded(
            flex: 2,
            child: Text(_formatDownloadDate(item.updatedAt), style: metaTextStyle),
          ),
          IconButton(
            onPressed: () => _openDownload(item),
            icon: const Icon(Icons.download_outlined, size: 22),
            tooltip: t.download,
          ),
        ],
      ),
    );
  }

  Widget _downloadCard(AppLocalizations t, RepDownloadItem item, bool isPhone) {
    final badgeLabel = item.badge == 'change'
        ? t.rep_downloads_change
        : item.badge == 'new'
            ? t.rep_downloads_new
            : '';
    final accent = badgeLabel.isNotEmpty ? (item.badge == 'change' ? Colors.amber : Colors.blue) : Colors.teal;

    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDownload(item),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.insert_drive_file_outlined, color: accent.shade700, size: 20),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 15.5),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'v${item.version} · ${_formatDownloadSize(item.size)}',
                          style: const TextStyle(fontSize: 11.5, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  if (badgeLabel.isNotEmpty)
                    Chip(
                      label: Text(badgeLabel),
                      avatar: Icon(Icons.fiber_manual_record, size: 12, color: accent.shade700),
                      backgroundColor: accent.withOpacity(0.12),
                      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                      labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      shape: StadiumBorder(side: BorderSide(color: accent.shade200)),
                    ),
                ],
              ),
              if (item.description.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  item.description,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 5,
                children: [
                  if (item.category.isNotEmpty)
                    Chip(
                      label: Text(item.category),
                      avatar: const Icon(Icons.folder_open, size: 14),
                      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                      labelStyle: const TextStyle(fontSize: 11.5),
                    ),
                  Chip(
                    label: Text('${t.rep_downloads_size}: ${_formatDownloadSize(item.size)}'),
                    avatar: const Icon(Icons.sd_storage_outlined, size: 14),
                    visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                    labelStyle: const TextStyle(fontSize: 11.5),
                  ),
                  Chip(
                    label: Text('${t.rep_downloads_last_updated}: ${_formatDownloadDate(item.updatedAt)}'),
                    avatar: const Icon(Icons.schedule_outlined, size: 14),
                    visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                    labelStyle: const TextStyle(fontSize: 11.5),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => _openDownload(item),
                  icon: const Icon(Icons.download_outlined),
                  label: Text(t.download),
                  style: FilledButton.styleFrom(
                    minimumSize: Size(isPhone ? double.infinity : 0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadsView() {
    final t = context.t;
    if (_downloadsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_downloadsErr != null) {
      return Center(
        child: Text(
          _downloadsErr!,
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
    if (_downloads.isEmpty) {
      return Center(child: Text(t.rep_downloads_empty));
    }

    final filtered = _filteredDownloads();
    final grouped = _groupDownloadsByCategory(filtered);
    final width = MediaQuery.of(context).size.width;
    final isPhone = width < 720;
    final cardWidth = isPhone ? width - 36 : 280.0;
    final minCardWidth = isPhone ? width - 36 : 210.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.download_outlined, color: Theme.of(context).colorScheme.primary, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.rep_downloads_title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                              t.rep_downloads_intro,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _downloadSearchCtrl,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      labelText: t.rep_downloads_search_placeholder,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onChanged: (v) => setState(() => _downloadSearch = v),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      ChoiceChip(
                        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                        label: Text(t.rep_downloads_filter_badge_all),
                        selected: _downloadBadgeFilter == 'all',
                        onSelected: (_) => setState(() => _downloadBadgeFilter = 'all'),
                      ),
                      ChoiceChip(
                        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                        label: Text(t.rep_downloads_filter_badge_new),
                        selected: _downloadBadgeFilter == 'new',
                        onSelected: (_) => setState(() => _downloadBadgeFilter = 'new'),
                      ),
                      ChoiceChip(
                        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                        label: Text(t.rep_downloads_filter_badge_change),
                        selected: _downloadBadgeFilter == 'change',
                        onSelected: (_) => setState(() => _downloadBadgeFilter = 'change'),
                      ),
                      ChoiceChip(
                        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                        label: Text(t.rep_downloads_filter_badge_none),
                        selected: _downloadBadgeFilter == 'none',
                        onSelected: (_) => setState(() => _downloadBadgeFilter = 'none'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ToggleButtons(
                      isSelected: [
                        _downloadView == _DownloadsView.grid,
                        _downloadView == _DownloadsView.list,
                      ],
                      borderRadius: BorderRadius.circular(10),
                      constraints: const BoxConstraints(minHeight: 32, minWidth: 100),
                      onPressed: (index) {
                        setState(() {
                          _downloadView = index == 0 ? _DownloadsView.grid : _DownloadsView.list;
                        });
                      },
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.grid_view_rounded, size: 18),
                            const SizedBox(width: 6),
                            Text(t.rep_downloads_view_grid),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.view_list_rounded, size: 18),
                            const SizedBox(width: 6),
                            Text(t.rep_downloads_view_list),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (filtered.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text(t.rep_downloads_empty),
              ),
            )
          else
            ...grouped.map((entry) {
              final label = entry.key == '__uncategorized' ? t.rep_downloads_uncategorized : entry.key;
              final items = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(width: 6),
                        Chip(
                          label: Text('${items.length}'),
                          visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          backgroundColor: Colors.grey.withOpacity(0.12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (_downloadView == _DownloadsView.grid)
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: items
                            .map(
                              (item) => ConstrainedBox(
                                constraints: BoxConstraints(minWidth: minCardWidth, maxWidth: cardWidth),
                                child: _downloadCard(t, item, isPhone),
                              ),
                            )
                            .toList(),
                      )
                    else
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              color: Theme.of(context).colorScheme.surface.withOpacity(0.65),
                              padding: EdgeInsets.symmetric(horizontal: isPhone ? 12 : 12, vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(flex: 5, child: Text(t.rep_downloads_column_title, style: Theme.of(context).textTheme.labelLarge)),
                                  if (!isPhone) ...[
                                    Expanded(flex: 3, child: Text(t.rep_downloads_column_category, style: Theme.of(context).textTheme.labelLarge)),
                                    Expanded(flex: 2, child: Text(t.rep_downloads_column_size, style: Theme.of(context).textTheme.labelLarge)),
                                    Expanded(flex: 2, child: Text(t.rep_downloads_column_date, style: Theme.of(context).textTheme.labelLarge)),
                                    const SizedBox(width: 36),
                                  ],
                                  if (isPhone) Icon(Icons.download_outlined, color: Colors.grey.shade500, size: 18),
                                ],
                              ),
                            ),
                            ...items.map((item) => _buildDownloadListRow(t, item, isPhone)),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
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

    items = items.where(_matchesDecisionFilter).toList(growable: false);
    items = items.where(_matchesStatusFilter).toList(growable: false);

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
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
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
                    decoration: InputDecoration(
                      labelText: t.rep_filter_company_label,
                      prefixIcon: const Icon(Icons.apartment_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _decisionFilter,
                    items: _decisionFilterItems(t),
                    onChanged: (v) => setState(() => _decisionFilter = v ?? ''),
                    decoration: InputDecoration(
                      labelText: t.rep_filter_decision_label ?? 'Entscheidung filtern',
                      prefixIcon: const Icon(Icons.how_to_vote_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _statusFilter,
                    items: _statusFilterItems(t),
                    onChanged: (v) => setState(() => _statusFilter = v ?? ''),
                    decoration: InputDecoration(
                      labelText: t.rep_filter_status_label ?? 'Status filtern',
                      prefixIcon: const Icon(Icons.flag_outlined),
                    ),
                  ),
                ],
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
    final hasStatusFilter = _statusFilter.trim().isNotEmpty;

    if (!_showClosedAll && !hasStatusFilter) {
      list = list.where((c) => !_isClosed(c)).toList();
    }
    if ((_selectedCompany ?? '').isNotEmpty) {
      list = list.where((c) {
        final em = (c['customerEmail'] ?? c['email'] ?? '').toString().toLowerCase();
        final co = (_emailToCompany[em] ?? '');
        return co == _selectedCompany;
      }).toList();
    }

    list = list.where(_matchesDecisionFilter).toList();
    list = list.where(_matchesStatusFilter).toList();
    list = list.where(_matchesWarningFilters).toList();

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
                    decoration: InputDecoration(
                      labelText: t.rep_filter_company_label,
                      prefixIcon: const Icon(Icons.apartment_outlined),
                    ),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    value: _decisionFilter,
                    items: _decisionFilterItems(t),
                    onChanged: (v) => setState(() => _decisionFilter = v ?? ''),
                    decoration: InputDecoration(
                      labelText: t.rep_filter_decision_label ?? 'Entscheidung filtern',
                      prefixIcon: const Icon(Icons.how_to_vote_outlined),
                    ),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    value: _statusFilter,
                    items: _statusFilterItems(t),
                    onChanged: (v) => setState(() => _statusFilter = v ?? ''),
                    decoration: InputDecoration(
                      labelText: t.rep_filter_status_label ?? 'Status filtern',
                      prefixIcon: const Icon(Icons.flag_outlined),
                    ),
                  ),
                ),
                FilterChip(
                  label: Text(t.rep_filter_show_closed),
                  selected: _showClosedAll,
                  onSelected: (v) => setState(() => _showClosedAll = v),
                ),
                if (_complaintArticleFilter.isNotEmpty)
                  InputChip(
                    label: Text(t.repEarlyWarningArticleFilter(_complaintArticleFilter.join(', '))),
                    onDeleted: () => setState(() => _complaintArticleFilter = const []),
                  ),
                if (_complaintCustomerFilter.trim().isNotEmpty)
                  InputChip(
                    label: Text(t.repEarlyWarningCustomerFilter(_complaintCustomerFilter)),
                    onDeleted: () => setState(() => _complaintCustomerFilter = ''),
                  ),
                if (_complaintArticleFilter.isNotEmpty || _complaintCustomerFilter.trim().isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _complaintArticleFilter = const [];
                        _complaintCustomerFilter = '';
                      });
                    },
                    icon: const Icon(Icons.filter_alt_off_outlined),
                    label: Text(t.repEarlyWarningClearFilters),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Liste
        _Card(
          title: t.rep_menu_all_title,
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
    final query = _customerSearch.trim().toLowerCase();

    bool matches(Map<String, Object?> c) {
      if (query.isEmpty) return true;
      bool containsValue(String key) =>
          ((c[key] ?? '').toString().toLowerCase()).contains(query);
      return containsValue('company') ||
          containsValue('name') ||
          containsValue('email') ||
          containsValue('customerNo');
    }

    final filtered = _customers.where(matches).toList(growable: false);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const buttonPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 12);
    const buttonTextStyle = TextStyle(fontWeight: FontWeight.w600);
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

    Widget buildList() {
      if (_customers.isEmpty) {
        return Text(t.noAddCustomer);
      }
      if (filtered.isEmpty) {
        return Text(t.noDataFound ?? 'Keine Daten gefunden.');
      }
      return ListView.separated(
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        itemBuilder: (_, i) {
          final c = filtered[i];
          final email = (c['email'] ?? '').toString();
          final isNew = !_seenCustomers.contains(email.toLowerCase());
          final hasNote = ((c['repNote'] ?? '').toString().trim().isNotEmpty);

          final tile = InkWell(
            onTap: () {
              _markCustomerSeen(email);
              _showCustomerDetails(c);
            },
            child: ListTile(
              dense: true,
              visualDensity: const VisualDensity(vertical: -2),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              leading: const Icon(Icons.apartment_outlined),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      (() {
                        final comp = (c['company'] ?? '').toString();
                        final nm = (c['name'] ?? '').toString();
                        final em = email;
                        if (comp.isNotEmpty) return comp;
                        if (nm.isNotEmpty) return nm;
                        return em;
                      })(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isNew) const SizedBox(width: 8),
                  if (isNew) const _PulseNewBadge(),
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
                style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.1),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasNote)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.sticky_note_2_outlined,
                        color: theme.colorScheme.primary,
                      ),
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

          return _FadeInOnce(
            delayMs: 35 * i,
            child: tile,
          );
        },
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemCount: filtered.length,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Card(
          title: t.myCustomers,
          actions: [
            ElevatedButton.icon(
              onPressed: _createCustomerDialog,
              icon: const Icon(Icons.add_business),
              label: Text(t.rep_create_customer ?? t.addCustomer),
              style: ElevatedButton.styleFrom(
                padding: buttonPadding,
                shape: buttonShape,
                textStyle: buttonTextStyle,
              ),
            ),
            OutlinedButton.icon(
              onPressed: _assignCustomerDialog,
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(t.addCustomer),
              style: OutlinedButton.styleFrom(
                padding: buttonPadding,
                shape: buttonShape,
                textStyle: buttonTextStyle,
                foregroundColor: cs.primary,
                side: BorderSide(color: cs.primary.withOpacity(0.5)),
              ),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _customerSearchCtrl,
                onChanged: (value) => setState(() => _customerSearch = value),
                decoration: InputDecoration(
                  hintText: t.search,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              buildList(),
            ],
          ),
        ),
      ],
    );
  }
  
  // ---- Seite: Account – ohne Doppeltitel/Untertitel + getrennte PW-Änderung ----
  Widget _buildAccountCard() {
    final t = context.t;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final labelProfile   = t.profile_edit ?? 'Profil bearbeiten';
    final labelPassword  = t.password_change ?? 'Passwort ändern';
    final profileHint    = t.profile_edit_hint ?? labelProfile;
    final passwordHint   = t.password_change_hint ?? labelPassword;

    String s(Object? v) => (v ?? '').toString().trim();

    final data = _me ?? const <String, dynamic>{};
    final firstName = s(data['firstName']);
    final lastName  = s(data['lastName']);
    final email     = s(data['email']);
    final region    = s(data['region']);
    final langRaw   = s(data['lang']);
    final normalizedLang = normalizeLangCode(langRaw.isEmpty ? 'de' : langRaw);
    final langDisplay = langNameFor(t, normalizedLang);
    final customerCount = _customers.length;

    final displayName = [firstName, lastName].where((e) => e.isNotEmpty).join(' ').trim();
    final headline = displayName.isEmpty ? (email.isNotEmpty ? email : t.profile_edit ?? 'Profil') : displayName;

    Widget _actionTile({
      required IconData icon,
      required String label,
      required String description,
      required Color color,
      required VoidCallback onTap,
    }) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withOpacity(0.16), cs.surfaceVariant.withOpacity(.45)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(.35)),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(.22),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
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
                Icon(Icons.chevron_right, color: cs.onSurface.withOpacity(.65)),
              ],
            ),
          ),
        ),
      );
    }

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
            final baseError = (t.error ?? 'Fehler').toString();
            if (oldPw.isEmpty || n1.isEmpty || n2.isEmpty) {
              err = '$baseError: Bitte alle Felder ausfüllen';
              (ctx as Element).markNeedsBuild();
              return;
            }
            if (n1 != n2) {
              err = '$baseError: Passwörter stimmen nicht überein';
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
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PasswordField(
                  controller: oldCtrl,
                  decoration: InputDecoration(labelText: t.oldPassword),
                ),
                const SizedBox(height: 8),
                PasswordField(
                  controller: new1Ctrl,
                  decoration: InputDecoration(
                    labelText: t.newPassword,
                    helperText: t.password_requirements,
                  ),
                ),
                const SizedBox(height: 8),
                PasswordField(
                  controller: new2Ctrl,
                  decoration: InputDecoration(
                    labelText: t.newPasswordRepeat,
                    helperText: t.password_requirements,
                  ),
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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Card(
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: cs.primaryContainer,
                      child: Icon(
                        Icons.person_outline,
                        size: 34,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            headline,
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (email.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              email,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    if (region.isNotEmpty)
                      _AccountInfoChip(
                        icon: Icons.public,
                        label: t.region,
                        value: region,
                      ),
                    _AccountInfoChip(
                      icon: Icons.people_outline,
                      label: t.myCustomers,
                      value: '$customerCount',
                    ),
                    _AccountInfoChip(
                      icon: Icons.language_outlined,
                      label: t.catalog_select_language,
                      value: langDisplay,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                _actionTile(
                  icon: Icons.manage_accounts_outlined,
                  label: labelProfile,
                  description: profileHint,
                  color: cs.primary,
                  onTap: _openProfile,
                ),
                const SizedBox(height: 16),
                _actionTile(
                  icon: Icons.lock_reset_outlined,
                  label: labelPassword,
                  description: passwordHint,
                  color: cs.tertiary,
                  onTap: _openPasswordChange,
                ),
              ],
            ),
          ),
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
    final currentNote = s(c['repNote']);

    final noteCtrl = TextEditingController(text: currentNote);
    bool saving = false;
    String? feedback;
    bool feedbackError = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> saveNote() async {
            if (saving) return;
            setDialogState(() {
              saving = true;
              feedback = null;
            });
            try {
              final saved = await widget.api.repUpdateCustomerNote(
                email: email,
                note: noteCtrl.text,
              );
              if (!mounted) return;
              setState(() => c['repNote'] = saved);
              setDialogState(() {
                saving = false;
                feedback = context.t.rep_note_saved;
                feedbackError = false;
              });
              if (mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(context.t.rep_note_saved)));
              }
            } catch (_) {
              if (!mounted) return;
              setDialogState(() {
                saving = false;
                feedback = context.t.rep_note_error;
                feedbackError = true;
              });
            }
          }

          return AlertDialog(
            title: Text(company.isNotEmpty ? company : (name.isNotEmpty ? name : email)),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (name.isNotEmpty) Text(name),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      SelectableText(email),
                    ],
                    const SizedBox(height: 8),
                    if (address.isNotEmpty) Text(address),
                    if (zip.isNotEmpty || city.isNotEmpty)
                      Text('${zip.isNotEmpty ? '$zip ' : ''}$city'.trim()),
                    if (country.isNotEmpty) Text(country),
                    if (phone.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Tel.: $phone'),
                    ],
                    if (customerNo.isNotEmpty) Text('Kundennr.: $customerNo'),
                    if (vatId.isNotEmpty) Text('USt-Id.: $vatId'),
                    const Divider(height: 24),
                    Text(context.t.rep_note_label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 5,
                      minLines: 3,
                      maxLength: 2000,
                      decoration: InputDecoration(
                        hintText: context.t.rep_note_placeholder,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    if (feedback != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          feedback!,
                          style: TextStyle(
                            color: feedbackError ? Colors.red : Colors.green,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(context.t.close)),
              FilledButton.icon(
                onPressed: saving ? null : saveNote,
                icon: saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: Text(context.t.rep_note_save),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() => noteCtrl.dispose());
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: fsTitle)),
                ),
                if (actions != null)
                  Flexible(
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: actions!,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

/// Menü-Kachel (angelehnt an Admin-Kacheln)
class _MenuCard extends StatefulWidget {
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
  State<_MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends State<_MenuCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final accent = widget.color;
    final baseSurface = isDark
        ? Color.alphaBlend(Colors.white.withOpacity(0.06), cs.surface)
        : cs.surface;
    final bgA = _blend(baseSurface, accent, isDark ? 0.12 : 0.07);
    final bgB = _blend(baseSurface, accent, isDark ? 0.06 : 0.03);
    final borderColor = isDark
        ? cs.outlineVariant.withOpacity(0.32)
        : cs.outlineVariant.withOpacity(0.22);

    final iconColor = isDark ? _blend(accent, cs.onSurface, 0.25) : accent;
    final titleColor = cs.onSurface;
    final subtitleColor = cs.onSurfaceVariant;
    final badgeBg = accent;
    final badgeFg = _bestOnColor(badgeBg);

    final lift = _hovering ? -7.0 : 0.0;
    final hoverScale = _hovering ? 1.018 : 1.0;
    final elevation = _hovering ? 12.0 : 3.5;

    final baseRadius = widget.compact ? 16.0 : 18.0;
    final radius = baseRadius * widget.scale;
    final paddingV = (widget.compact ? 18.0 : 22.0) * widget.scale;
    final paddingH = (widget.compact ? 14.0 : 20.0) * widget.scale;
    final spacing = (widget.compact ? 12.0 : 16.0) * widget.scale;
    final iconSize = (widget.compact ? 44.0 : 58.0) * widget.scale;
    final badgePadH = (widget.compact ? 7.5 : 9.5) * widget.scale;
    final badgePadV = (widget.compact ? 3.0 : 3.5) * widget.scale;
    final titleSize = (widget.compact ? 15.0 : 16.5) * widget.scale;
    final subtitleSize = (widget.compact ? 12.0 : 13.0) * widget.scale;

    final borderRadius = BorderRadius.circular(radius);
    final subtitle = widget.subtitle.trim();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        transform: Matrix4.identity()
          ..translate(0.0, lift)
          ..scale(hoverScale),
        child: Material(
          color: Colors.transparent,
          elevation: elevation,
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [bgA, bgB],
                ),
                borderRadius: borderRadius,
                border: Border.all(color: borderColor),
              ),
              padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
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
                            padding: EdgeInsets.symmetric(
                              horizontal: badgePadH,
                              vertical: badgePadV,
                            ),
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
                                fontSize: widget.compact ? 12 : 13,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: spacing),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                      fontSize: titleSize,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    SizedBox(height: spacing * 0.65),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: subtitleSize,
                        height: 1.2,
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

Color _blend(Color base, Color top, double t) {
  return Color.alphaBlend(top.withOpacity(t.clamp(0, 1)), base);
}

Color _bestOnColor(Color c) {
  final brightness = ThemeData.estimateBrightnessForColor(c);
  return brightness == Brightness.dark ? Colors.white : Colors.black;
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

  String? _resolveProductArea(AppLocalizations t, String? segment, String? productType) {
    final candidates = <String?>[segment, productType];
    for (final raw in candidates) {
      final value = (raw ?? '').trim().toLowerCase();
      if (value.isEmpty) continue;

      if (value.contains('zahnarzt') || value.contains('zahnmedizin')) {
        return t.product_area_medical ?? 'Medizinprodukt';
      }
      if (value.contains('dentist') || value == (t.segment_dentist ?? '').toLowerCase()) {
        return t.product_area_medical ?? 'Medizinprodukt';
      }
      if (value.contains('dentallabor') || value.contains('zahntechnik')) {
        return t.product_area_lab ?? 'Laborprodukt';
      }
      if (value.contains('lab') || value == (t.segment_lab ?? '').toLowerCase()) {
        return t.product_area_lab ?? 'Laborprodukt';
      }
    }
    return null;
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

    final resolvedProductArea = _resolveProductArea(t, segment, productType);
    final normalizedSegment = segment?.trim();
    final displayProductArea =
        resolvedProductArea ?? ((normalizedSegment == null || normalizedSegment.isEmpty) ? null : normalizedSegment);

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
                    if (displayProductArea != null && displayProductArea.isNotEmpty)
                      _InfoCapsule('${t.product_area_label ?? 'Produktbereich'}: $displayProductArea'),
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
                    productArea: resolvedProductArea ?? segment,
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
    Widget kv(String label, String? value, {int? maxLines = 2}) {
      final v = (value ?? '').trim();
      if (v.isEmpty) return const SizedBox.shrink();

      const labelStyle = TextStyle(fontWeight: FontWeight.w600);

      return LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final valueWidget = Text(
            v,
            softWrap: true,
            maxLines: compact ? null : maxLines,
          );

          if (compact) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: labelStyle),
                  const SizedBox(height: 4),
                  valueWidget,
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 190, child: Text(label, style: labelStyle)),
                const SizedBox(width: 12),
                Expanded(child: valueWidget),
              ],
            ),
          );
        },
      );
    }

    Widget kvPair(String label1, String? value1, String label2, String? value2) {
      final hasA = (value1 ?? '').trim().isNotEmpty;
      final hasB = (value2 ?? '').trim().isNotEmpty;
      if (!hasA && !hasB) return const SizedBox.shrink();

      return LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasA) kv(label1, value1),
                if (hasB) kv(label2, value2),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasA) Expanded(child: kv(label1, value1)),
              if (hasA && hasB) const SizedBox(width: 20),
              if (hasB) Expanded(child: kv(label2, value2)),
            ],
          );
        },
      );
    }

    final t = context.t;
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

          kv(t.product_area_label ?? 'Produktbereich', productArea),
          kv('Segment', segment),
          kv('Produkttyp', productType),
          kv('Artikelnummer', articleNo),

          kvPair('Charge / LOT', batch, 'Seriennummer', serial),

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

class _AccountInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _AccountInfoChip({
    required this.icon,
    required this.label,
    required this.value,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bg = cs.surfaceVariant.withOpacity(theme.brightness == Brightness.dark ? 0.35 : 0.7);
    final on = cs.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: on),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: on.withOpacity(0.75),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              Text(
                value.isEmpty ? '-' : value,
                style: theme.textTheme.bodyMedium?.copyWith(color: on, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
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
    final decisionLabel = _localizedDecisionLabel(context);
    final decisionColor = _decisionColor(context);
    final statusLabel = _localizedStatusLabel(context);
    final statusColor = _statusColor(context);

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _chip(context.t.decision ?? 'Entscheidung', decisionLabel, decisionColor),
        _chip(context.t.status ?? 'Status', statusLabel, statusColor),
      ],
    );
  }

  String _localizedStatusLabel(BuildContext context) {
    final t = context.t;
    final raw = status.trim();
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      if (raw.isEmpty) return t.status_unknown;
      return raw;
    }

    switch (parsed) {
      case 1: return t.status_sent;
      case 2: return t.status_in_progress;
      case 3: return t.status_question;
      case 4: return t.status_rework;
      case 5: return t.status_closed;
      default: return t.status_unknown;
    }
  }

  String _localizedDecisionLabel(BuildContext context) {
    final t = context.t;
    final v = decision.trim().toLowerCase();
    if (v == 'accepted') return t.decision_accepted;
    if (v == 'rejected') return t.decision_rejected;
    return t.decision_pending ?? 'Entscheidung offen';
  }

  Color _decisionColor(BuildContext context) {
    final v = decision.trim().toLowerCase();
    if (v == 'accepted') return Colors.green;
    if (v == 'rejected') return Colors.red;
    return Colors.grey;
  }

  Color _statusColor(BuildContext context) {
    final parsed = int.tryParse(status.trim());
    if (closed) return Colors.grey;
    switch (parsed) {
      case 1: return Colors.blue;
      case 2: return Colors.amber.shade800;
      case 3: return Colors.orange;
      case 4: return Colors.amber.shade600;
      case 5: return Colors.green;
      default: return Theme.of(context).colorScheme.primary;
    }
  }

  Widget _chip(String prefix, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$prefix: $label',
        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
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
