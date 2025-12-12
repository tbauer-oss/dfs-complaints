import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/client.dart';
import '../models/capa_report.dart';
import '../models/complaint.dart';
import '../models/dfs_product.dart';
import '../models/fmea.dart';
import '../models/portal_user.dart';
import '../services/dfs_product_service.dart';

class AdminFmeaPage extends StatefulWidget {
  final ApiClient api;
  final bool canEdit;
  const AdminFmeaPage({super.key, required this.api, required this.canEdit});

  @override
  State<AdminFmeaPage> createState() => _AdminFmeaPageState();
}

class _AdminFmeaPageState extends State<AdminFmeaPage> {
  final _dateFmt = DateFormat('dd.MM.yyyy');
  bool _loadingList = false;
  bool _saving = false;
  String? _error;
  List<FmeaRecord> _fmeas = const [];
  FmeaRecord? _selected;
  List<Map<String, dynamic>> _links = const [];
  bool _loadingLinks = false;
  bool _onlyUnlinked = false;
  List<String> _mdrTdOptions = const [];
  List<String> _productGroups = const [];
  List<PortalUserSummary> _portalUsers = const [];
  List<Complaint> _complaints = const [];
  List<CapaReport> _capas = const [];
  bool _loadingRefs = false;
  final _productService = DfsProductService();
  final _searchCtrl = TextEditingController();
  final _fmeaSearchCtrl = TextEditingController();
  String _selectedCategory = 'all';
  final _activeFilters = <String>{};

  FmeaRiskEntry? _selectedRiskEntry;
  bool _showAfterValues = true;

  final _mdrTdCtrl = TextEditingController();
  final _productGroupCtrl = TextEditingController();
  final _medicalProductCtrl = TextEditingController();
  final _moderatorCtrl = TextEditingController();
  final _revisionCtrl = TextEditingController();
  final _prrcNameCtrl = TextEditingController();
  bool _prrcApproved = false;
  DateTime? _prrcDate;

  final _riskHorizontal = ScrollController();
  final _riskVertical = ScrollController();

  bool get _readOnly => !widget.canEdit;

  List<String> get _mdrOptions => _mdrTdOptions;

  List<String> get _productGroupOptions {
    return _productGroups;
  }

  List<PortalUserSummary> get _superusers =>
      _portalUsers.where((u) => u.role == 'superuser').toList(growable: false);

  List<PortalUserSummary> get _prrcUsers =>
      _portalUsers.where((u) => u.isPrrc).toList(growable: false);

  @override
  void initState() {
    super.initState();
    _loadReferenceData();
    _loadFmeas();
    _loadLinks();
  }

  @override
  void dispose() {
    _mdrTdCtrl.dispose();
    _productGroupCtrl.dispose();
    _medicalProductCtrl.dispose();
    _moderatorCtrl.dispose();
    _revisionCtrl.dispose();
    _prrcNameCtrl.dispose();
    _searchCtrl.dispose();
    _fmeaSearchCtrl.dispose();
    _riskHorizontal.dispose();
    _riskVertical.dispose();
    super.dispose();
  }

  Future<void> _loadFmeas() async {
    setState(() {
      _loadingList = true;
      _error = null;
    });
    try {
      final list = await widget.api.adminFmeas();
      FmeaRecord? selected = _selected;
      if (selected != null) {
        selected = list.firstWhere(
          (f) => f.id == selected!.id,
          orElse: () => selected!,
        );
      }
      selected ??= list.isNotEmpty ? list.first : null;
      _setSelection(selected);
      setState(() => _fmeas = list);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loadingList = false);
    }
  }

  Future<void> _loadLinks() async {
    setState(() => _loadingLinks = true);
    try {
      final links = await widget.api.adminFmeaLinks();
      setState(() => _links = links);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loadingLinks = false);
    }
  }

  Future<void> _loadReferenceData() async {
    setState(() {
      _loadingRefs = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.fetchPortalUsers(),
        widget.api.adminComplaints(details: true),
        widget.api.adminCapas(),
        _productService.loadProducts(),
      ]);
      final users = results[0] as List<PortalUserSummary>;
      final complaints = results[1] as List<Complaint>;
      final capas = results[2] as List<CapaReport>;
      final products = results[3] as List<DfsProduct>;
      final groups = {
        ...products.map((p) => p.productGroup.trim()).where((g) => g.isNotEmpty),
      };
      final mdrTd = {
        ...products
            .map((p) => p.tdNumberAndName.trim())
            .where((v) => v.startsWith('MDR-TD') && v.isNotEmpty),
      };
      setState(() {
        _portalUsers = users;
        _complaints = complaints;
        _capas = capas;
        _mdrTdOptions = mdrTd.toList()..sort();
        _productGroups = groups.toList()..sort();
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loadingRefs = false);
    }
  }

  void _setSelection(FmeaRecord? record) {
    setState(() {
      _selected = record;
      _selectedRiskEntry = null;
      _headerExpanded = false;
      _mdrTdCtrl.text = record?.mdrTd ?? '';
      _productGroupCtrl.text = record?.productGroup ?? '';
      _medicalProductCtrl.text = record?.medicalProduct ?? '';
      _moderatorCtrl.text = record?.moderator ?? '';
      _revisionCtrl.text = _normalizedRevision(record?.revision ?? '');
      _prrcNameCtrl.text = record?.prrcName ?? '';
      _prrcApproved = record?.prrcApproved ?? false;
      _prrcDate = record?.prrcDate;
    });
  }

  String _normalizedRevision(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed <= 0) return '1';
    return parsed.toString();
  }

  Future<void> _createFmea() async {
    final created = await _openNewFmeaDialog();
    if (created == null) return;
    setState(() => _saving = true);
    try {
      final saved = await widget.api.adminCreateFmea(created);
      await _loadFmeas();
      _setSelection(saved);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _saveHeader() async {
    if (_selected == null) return;
    setState(() => _saving = true);
    try {
      final updated = _selected!.copyWith(
        mdrTd: _mdrTdCtrl.text.trim(),
        productGroup: _productGroupCtrl.text.trim(),
        medicalProduct: _medicalProductCtrl.text.trim(),
        moderator: _moderatorCtrl.text.trim(),
        revision: _normalizedRevision(_revisionCtrl.text),
        prrcName: _prrcNameCtrl.text.trim(),
        prrcApproved: _prrcApproved,
        prrcDate: _prrcDate,
        title: _mdrTdCtrl.text.trim().isNotEmpty ? _mdrTdCtrl.text.trim() : _selected!.title,
      );
      final saved = await widget.api.adminUpdateFmea(updated);
      _setSelection(saved);
      await _loadFmeas();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _deleteSelected() async {
    final current = _selected;
    if (current == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('FMEA löschen?'),
        content: Text('Soll die FMEA "${current.mdrTd}" wirklich gelöscht werden?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    try {
      await widget.api.adminDeleteFmea(current.id);
      _setSelection(null);
      await _loadFmeas();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _saving = false);
    }
  }

  void _downloadBytes(Uint8List bytes, String filename, String mime) {
    final blob = html.Blob([bytes], mime);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)..download = filename;
    anchor.click();
    html.Url.revokeObjectUrl(url);
  }

  Future<void> _exportPdf() async {
    if (_selected == null) return;
    setState(() => _saving = true);
    try {
      final bytes = await widget.api.adminFmeaPdf(_selected!.id);
      _downloadBytes(bytes, 'fmea_${_selected!.mdrTd}.pdf', 'application/pdf');
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _exportCsv() async {
    if (_selected == null) return;
    setState(() => _saving = true);
    try {
      final csv = await widget.api.adminFmeaCsv(_selected!.id);
      final bytes = Uint8List.fromList(csv.codeUnits);
      _downloadBytes(bytes, 'fmea_${_selected!.mdrTd}.csv', 'text/csv');
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<FmeaRecord?> _openNewFmeaDialog() async {
    String mdrTdValue = _mdrOptions.contains(_mdrTdCtrl.text.trim()) ? _mdrTdCtrl.text.trim() : '';
    String productValue = _productGroupOptions.contains(_productGroupCtrl.text.trim())
        ? _productGroupCtrl.text.trim()
        : '';
    String moderatorValue = _superusers.any((u) => u.email == _moderatorCtrl.text.trim())
        ? _moderatorCtrl.text.trim()
        : '';
    String revisionValue = '1';

    final result = await showDialog<FmeaRecord?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Neue FMEA anlegen'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: mdrTdValue.isNotEmpty ? mdrTdValue : null,
                  decoration: const InputDecoration(labelText: 'MDR-TD / Medizinprodukt'),
                  items: _mdrOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (val) => setStateDialog(() => mdrTdValue = val ?? ''),
                ),
                DropdownButtonFormField<String>(
                  value: productValue.isNotEmpty ? productValue : null,
                  decoration: const InputDecoration(labelText: 'Produktgruppe'),
                  items: _productGroupOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (val) => setStateDialog(() => productValue = val ?? ''),
                ),
                DropdownButtonFormField<String>(
                  value: moderatorValue.isNotEmpty ? moderatorValue : null,
                  decoration: const InputDecoration(labelText: 'FMEA-Moderator'),
                  items: _superusers
                      .map(
                        (u) => DropdownMenuItem(value: u.email, child: Text('${u.label} (${u.email})')),
                      )
                      .toList(),
                  onChanged: (val) => setStateDialog(() => moderatorValue = val ?? ''),
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Revision'),
                  keyboardType: TextInputType.number,
                  initialValue: revisionValue,
                  onChanged: (val) => revisionValue = _normalizedRevision(val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () {
                final title = mdrTdValue.trim();
                if (title.isEmpty) return;
                Navigator.pop(
                  ctx,
                  FmeaRecord(
                    id: '',
                    title: title,
                    mdrTd: title,
                    productGroup: productValue.trim(),
                    medicalProduct: title,
                    moderator: moderatorValue.trim(),
                    revision: _normalizedRevision(revisionValue),
                  ),
                );
              },
              child: const Text('Anlegen'),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  Future<void> _addRisk() async {
    if (_selected == null) return;
    final newRisk = await _openRiskDialog();
    if (newRisk == null) return;
    setState(() => _saving = true);
    try {
      await widget.api.adminAddFmeaRisk(fmeaId: _selected!.id, risk: newRisk);
      await _reloadSelected();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _updateRisk(FmeaRiskEntry risk) async {
    if (_selected == null) return;
    final updated = await _openRiskDialog(existing: risk);
    if (updated == null) return;
    setState(() => _saving = true);
    try {
      await widget.api.adminUpdateFmeaRisk(fmeaId: _selected!.id, riskId: risk.id, risk: updated);
      await _reloadSelected();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _deleteRisk(FmeaRiskEntry risk) async {
    if (_selected == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Risiko löschen?'),
        content: Text('Risiko ${risk.riskNumber} entfernen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    try {
      await widget.api.adminDeleteFmeaRisk(fmeaId: _selected!.id, riskId: risk.id);
      await _reloadSelected();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _reloadSelected() async {
    if (_selected == null) return;
    try {
      final refreshed = await widget.api.adminFetchFmea(_selected!.id);
      setState(() {
        _selected = refreshed;
        _selectedRiskEntry = null;
        _syncSelectedRisk();
      });
      await _loadFmeas();
      await _loadLinks();
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Color _riskColor(String? level, ThemeData theme) {
    switch (level) {
      case 'red':
        return theme.colorScheme.error;
      case 'yellow':
        return Colors.orange.shade700;
      case 'green':
        return Colors.green.shade700;
      default:
        return theme.colorScheme.outlineVariant;
    }
  }

  (Color baseColor, String label, IconData icon) _riskPresentation(
    String? level,
    ThemeData theme,
  ) {
    switch (level) {
      case 'red':
        return (
          _riskColor(level, theme),
          'Nicht akzeptabel',
          Icons.error_outline,
        );
      case 'yellow':
        return (
          _riskColor(level, theme),
          'Maßnahmen prüfen',
          Icons.warning_amber_rounded,
        );
      case 'green':
        return (
          _riskColor(level, theme),
          'Akzeptabel',
          Icons.check_circle_outline,
        );
      default:
        return (_riskColor(level, theme), 'Offen', Icons.help_outline);
    }
  }

  int? _riskScore(int? severity, int? occurrence) {
    if (severity == null || occurrence == null) return null;
    return severity * occurrence;
  }

  String? _riskLevelFromScore(int? score) {
    if (score == null) return null;
    if (score >= 15) return 'red';
    if (score >= 8) return 'yellow';
    return 'green';
  }

  String? _riskLevelFromValues(int? severity, int? occurrence) {
    return _riskLevelFromScore(_riskScore(severity, occurrence));
  }

  List<FmeaRiskEntry> get _currentRisks => _selected?.risks ?? const [];

  List<String> get _categoryOptions {
    final categories = _currentRisks
        .map((r) => r.category.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['all', 'uncategorized', ...categories];
  }

  List<FmeaRiskEntry> get _filteredRisks {
    final query = _searchCtrl.text.trim().toLowerCase();
    return _currentRisks.where((r) {
      if (_selectedCategory == 'uncategorized' && r.category.trim().isNotEmpty) return false;
      if (_selectedCategory != 'all' &&
          _selectedCategory != 'uncategorized' &&
          r.category.trim() != _selectedCategory) {
        return false;
      }

      final preLevels = ['pre:red', 'pre:yellow', 'pre:green'];
      final postLevels = ['post:red', 'post:yellow', 'post:green'];

      for (final key in preLevels) {
        if (_activeFilters.contains(key) && r.riskLevel != key.split(':').last) return false;
      }
      for (final key in postLevels) {
        if (_activeFilters.contains(key) && r.riskLevelAfter != key.split(':').last) return false;
      }

      if (_activeFilters.contains('newHazard') && !r.newHazard) return false;
      if (_activeFilters.contains('residualBad') && r.residualRiskOk) return false;
      if (_activeFilters.contains('missingDocs')) {
        final missingRatingAfter = r.severityAfter == null || r.occurrenceAfter == null;
        final missingDocs = r.documents.trim().isEmpty;
        if (!missingDocs && !missingRatingAfter) return false;
      }
      if (_activeFilters.contains('linkedComplaint') && r.linkedComplaints.isEmpty) return false;
      if (_activeFilters.contains('linkedCapa') && r.linkedCapas.isEmpty) return false;

      if (query.isEmpty) return true;
      final searchable = [
        r.hazard,
        r.hazardSituation,
        r.harm,
        r.causes,
        r.proposedAction,
        r.actionTaken,
        r.riskBenefitAnalysis,
      ].join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();
  }

  void _syncSelectedRisk() {
    final visible = _filteredRisks;
    if (visible.isEmpty) {
      _selectedRiskEntry = null;
      return;
    }
    if (_selectedRiskEntry == null || !visible.any((r) => r.id == _selectedRiskEntry!.id)) {
      _selectedRiskEntry = visible.first;
    }
  }

  Map<String, int> _countByLevel(List<FmeaRiskEntry> risks, {required bool after}) {
    final counts = {'red': 0, 'yellow': 0, 'green': 0};
    for (final r in risks) {
      final level = after ? r.riskLevelAfter : r.riskLevel;
      if (level != null && counts.containsKey(level)) counts[level] = counts[level]! + 1;
    }
    return counts;
  }

  int get _improvedRisks {
    return _currentRisks.where((r) {
      final before = r.riskLevel;
      final after = r.riskLevelAfter;
      if (before == null || after == null) return false;
      const order = {'red': 3, 'yellow': 2, 'green': 1};
      return (order[after] ?? 0) < (order[before] ?? 0);
    }).length;
  }

  List<Map<String, dynamic>> get _categoryStats {
    final stats = <String, Map<String, dynamic>>{};
    for (final r in _currentRisks) {
      final key = r.category.trim().isEmpty ? 'Ohne Kategorie' : r.category.trim();
      stats.putIfAbsent(key, () => {
            'total': 0,
            'pre': {'red': 0, 'yellow': 0, 'green': 0},
            'post': {'red': 0, 'yellow': 0, 'green': 0},
            'open': 0,
          });
      stats[key]!['total'] = (stats[key]!['total'] as int) + 1;
      if (r.riskLevel != null && (stats[key]!['pre'] as Map).containsKey(r.riskLevel)) {
        (stats[key]!['pre'] as Map)[r.riskLevel] = ((stats[key]!['pre'] as Map)[r.riskLevel] as int) + 1;
      }
      if (r.riskLevelAfter != null && (stats[key]!['post'] as Map).containsKey(r.riskLevelAfter)) {
        (stats[key]!['post'] as Map)[r.riskLevelAfter] =
            ((stats[key]!['post'] as Map)[r.riskLevelAfter] as int) + 1;
      }
      if (!r.residualRiskOk || r.newHazard) {
        stats[key]!['open'] = (stats[key]!['open'] as int) + 1;
      }
    }
    final list = stats.entries
        .map((e) => {
              'category': e.key,
              'total': e.value['total'] as int,
              'pre': Map<String, int>.from(e.value['pre'] as Map),
              'post': Map<String, int>.from(e.value['post'] as Map),
              'open': e.value['open'] as int,
            })
        .toList();
    list.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));
    return list;
  }

  Widget _riskBadge(String? level, ThemeData theme) {
    final (color, label, icon) = _riskPresentation(level, theme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Future<List<String>?> _openMultiSelectDialog({
    required String title,
    required List<String> options,
    required List<String> selected,
    String Function(String value)? labelBuilder,
  }) async {
    final available = {...options, ...selected}.toList()..sort();
    final chosen = {...selected};
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: available.length,
              itemBuilder: (ctx, idx) {
                final value = available[idx];
                final checked = chosen.contains(value);
                final label = labelBuilder?.call(value) ?? value;
                return CheckboxListTile(
                  value: checked,
                  onChanged: (v) => setStateDialog(() {
                    if (v == true) {
                      chosen.add(value);
                    } else {
                      chosen.remove(value);
                    }
                  }),
                  title: Text(label),
                  controlAffinity: ListTileControlAffinity.leading,
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(ctx, chosen.toList()), child: const Text('Übernehmen')),
          ],
        ),
      ),
    );
  }

  void _panRiskTable(DragUpdateDetails details) {
    if (_riskHorizontal.hasClients) {
      final maxX = _riskHorizontal.position.maxScrollExtent;
      final targetX = math.max(0, math.min(maxX, _riskHorizontal.offset - details.delta.dx));
      _riskHorizontal.jumpTo(targetX.toDouble());
    }
    if (_riskVertical.hasClients) {
      final maxY = _riskVertical.position.maxScrollExtent;
      final targetY = math.max(0, math.min(maxY, _riskVertical.offset - details.delta.dy));
      _riskVertical.jumpTo(targetY.toDouble());
    }
  }

  Widget _buildHeaderForm() {
    final theme = Theme.of(context);
    final spacing = const SizedBox(height: 12);
    final summaryChips = [
      if (_mdrTdCtrl.text.trim().isNotEmpty)
        Chip(
          label: Text(_mdrTdCtrl.text.trim()),
          visualDensity: VisualDensity.compact,
        ),
      if (_revisionCtrl.text.trim().isNotEmpty)
        Chip(
          label: Text('Revision ${_revisionCtrl.text.trim()}'),
          visualDensity: VisualDensity.compact,
        ),
      if (_moderatorCtrl.text.trim().isNotEmpty)
        Chip(
          label: Text('Moderator: ${_moderatorCtrl.text.trim()}'),
          visualDensity: VisualDensity.compact,
        ),
    ];
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: theme.colorScheme.outlineVariant)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kopfdaten', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 12),
                if (!_headerExpanded && summaryChips.isNotEmpty)
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: summaryChips,
                    ),
                  ),
                if (_headerExpanded) const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _headerExpanded = !_headerExpanded),
                  icon: Icon(_headerExpanded ? Icons.unfold_less : Icons.unfold_more),
                  label: Text(_headerExpanded ? 'Einklappen' : 'Einblenden'),
                ),
              ],
            ),
            AnimatedCrossFade(
              crossFadeState: _headerExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 200),
              firstChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  spacing,
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 260,
                        child: DropdownButtonFormField<String>(
                          value: _mdrOptions.contains(_mdrTdCtrl.text.trim()) ? _mdrTdCtrl.text.trim() : null,
                          decoration: const InputDecoration(labelText: 'MDR-TD / Medizinprodukt'),
                          items: {
                            ..._mdrOptions,
                            if (_mdrTdCtrl.text.trim().isNotEmpty) _mdrTdCtrl.text.trim(),
                          }
                              .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                              .toList(),
                          onChanged: _readOnly
                              ? null
                              : (val) {
                                  setState(() {
                                    _mdrTdCtrl.text = val ?? '';
                                    if ((_medicalProductCtrl.text).isEmpty) {
                                      _medicalProductCtrl.text = val ?? '';
                                    }
                                  });
                                },
                        ),
                      ),
                      SizedBox(
                        width: 240,
                        child: DropdownButtonFormField<String>(
                          value: _productGroupOptions.contains(_productGroupCtrl.text.trim()) ? _productGroupCtrl.text.trim() : null,
                          decoration: const InputDecoration(labelText: 'Produktgruppe'),
                          items: {
                            ..._productGroupOptions,
                            if (_productGroupCtrl.text.trim().isNotEmpty) _productGroupCtrl.text.trim(),
                          }
                              .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                              .toList(),
                          onChanged: _readOnly ? null : (val) => setState(() => _productGroupCtrl.text = val ?? ''),
                        ),
                      ),
                      SizedBox(
                        width: 260,
                        child: TextFormField(
                          controller: _medicalProductCtrl,
                          decoration: const InputDecoration(labelText: 'Medizinprodukt'),
                          readOnly: _readOnly,
                        ),
                      ),
                      SizedBox(
                        width: 200,
                        child: TextFormField(
                          controller: _moderatorCtrl,
                          decoration: const InputDecoration(labelText: 'FMEA-Moderator'),
                          readOnly: _readOnly,
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: TextFormField(
                          controller: _revisionCtrl,
                          decoration: const InputDecoration(labelText: 'Revision'),
                          readOnly: _readOnly,
                          onChanged: (v) => setState(() => _revisionCtrl.text = _normalizedRevision(v)),
                        ),
                      ),
                      if (!_readOnly)
                        FilledButton.icon(
                          onPressed: _saving ? null : _saveHeader,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Kopfdaten speichern'),
                        ),
                    ],
                  ),
                  spacing,
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 250,
                        child: DropdownButtonFormField<String>(
                          value: _superusers.any((u) => u.email == _moderatorCtrl.text.trim())
                              ? _moderatorCtrl.text.trim()
                              : null,
                          decoration: const InputDecoration(labelText: 'FMEA-Moderator'),
                          items: _superusers
                              .map((u) => DropdownMenuItem(
                                    value: u.email,
                                    child: Text('${u.label} (${u.email})'),
                                  ))
                              .toList(),
                          onChanged: _readOnly
                              ? null
                              : (val) => setState(() {
                                    _moderatorCtrl.text = val ?? '';
                                  }),
                        ),
                      ),
                      SizedBox(
                        width: 240,
                        child: CheckboxListTile(
                          value: _prrcApproved,
                          onChanged: _readOnly
                              ? null
                              : (val) => setState(() {
                                    _prrcApproved = val ?? false;
                                    if (val == true && _prrcDate == null) {
                                      _prrcDate = DateTime.now();
                                    }
                                  }),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('PRRC bestätigt'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      SizedBox(
                        width: 240,
                        child: DropdownButtonFormField<String>(
                          value: _prrcUsers.any((u) => u.email == _prrcNameCtrl.text.trim())
                              ? _prrcNameCtrl.text.trim()
                              : null,
                          decoration: const InputDecoration(labelText: 'PRRC-Name'),
                          items: _prrcUsers
                              .map((u) => DropdownMenuItem(
                                    value: u.email,
                                    child: Text('${u.label} (${u.email})'),
                                  ))
                              .toList(),
                          onChanged: _readOnly
                              ? null
                              : (val) => setState(() => _prrcNameCtrl.text = val ?? ''),
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: InkWell(
                          onTap: _readOnly
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _prrcDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) setState(() => _prrcDate = picked);
                                },
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'PRRC-Datum'),
                            child: Text(_prrcDate == null ? '—' : _dateFmt.format(_prrcDate!)),
                          ),
                        ),
                      ),
                      if (!_readOnly)
                        TextButton.icon(
                          onPressed: () => setState(() => _prrcDate = null),
                          icon: const Icon(Icons.clear),
                          label: const Text('Datum leeren'),
                        ),
                    ],
                  ),
                  spacing,
                  if (!_readOnly)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _saveHeader,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Kopfdaten speichern'),
                      ),
                    ),
                ],
              ),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    summaryChips.isEmpty ? 'Keine Kopfdaten hinterlegt' : 'Kopfdaten eingeklappt',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab(ThemeData theme) {
    final risks = _currentRisks;
    final pre = _countByLevel(risks, after: false);
    final post = _countByLevel(risks, after: true);
    final openResidual = risks.where((r) => !r.residualRiskOk).toList();
    final newHazards = risks.where((r) => r.newHazard).toList();
    final missingEvidence = risks
        .where((r) => r.documents.trim().isEmpty || r.severityAfter == null || r.occurrenceAfter == null)
        .toList();
    final missingSa = risks.where((r) => r.severityAfter == null || r.occurrenceAfter == null).toList();
    final categories = _categoryStats;

    Widget statChip(String label, int value, Color color) => Chip(
          label: Text(label),
          avatar: CircleAvatar(
            backgroundColor: color,
            foregroundColor: theme.colorScheme.onPrimary,
            child: Text('$value'),
          ),
        );

    Widget blockTitle(String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(text, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        );

    Widget quickLink(String label, IconData icon, int tab) => OutlinedButton.icon(
          onPressed: () => DefaultTabController.of(context)?.animateTo(tab),
          icon: Icon(icon),
          label: Text(label),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _KpiCard(
                title: 'Risiken gesamt',
                value: '${risks.length}',
                icon: Icons.list_alt_outlined,
                color: theme.colorScheme.primary,
              ),
              _KpiCard(
                title: 'PRRC-Status',
                value: _selected?.prrcApproved == true ? 'Freigegeben' : 'Offen',
                subtitle: _selected?.prrcName ?? '–',
                icon: Icons.verified_user_outlined,
                color: _selected?.prrcApproved == true
                    ? Colors.green.shade700
                    : theme.colorScheme.outline,
              ),
              _KpiCard(
                title: 'Letzte Änderung',
                value: _selected?.updatedAt != null ? _dateFmt.format(_selected!.updatedAt!) : '–',
                icon: Icons.event_outlined,
                color: theme.colorScheme.primary,
              ),
              _KpiCard(
                title: 'Kategorien',
                value: '${_categoryOptions.where((c) => c != 'all').length}',
                icon: Icons.label_important_outline,
                color: Colors.teal,
              ),
            ],
          ),
          const SizedBox(height: 12),
          blockTitle('Statistiken'),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _RiskStatCard(title: 'Vor Maßnahmen', counts: pre, theme: theme),
              _RiskStatCard(title: 'Nach Maßnahmen', counts: post, theme: theme),
              _KpiCard(
                title: 'Verbesserte Risiken',
                value: '$_improvedRisks',
                icon: Icons.trending_down,
                color: Colors.indigo,
              ),
            ],
          ),
          const SizedBox(height: 12),
          blockTitle('Offene Punkte'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              statChip('Restrisiko nein', openResidual.length, theme.colorScheme.error),
              statChip('Neue Gefährdung', newHazards.length, Colors.orange.shade700),
              statChip('Nachweise fehlen', missingEvidence.length, theme.colorScheme.primary),
              statChip('S(n)/A(n) fehlen', missingSa.length, theme.colorScheme.outline),
            ],
          ),
          const SizedBox(height: 12),
          blockTitle('Risiken nach Kategorie'),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text('Kategorie', style: theme.textTheme.labelLarge)),
                      SizedBox(width: 80, child: Text('Anzahl', style: theme.textTheme.labelLarge)),
                      SizedBox(width: 220, child: Text('Vor Maßnahmen', style: theme.textTheme.labelLarge)),
                      SizedBox(width: 220, child: Text('Nach Maßnahmen', style: theme.textTheme.labelLarge)),
                      SizedBox(width: 120, child: Text('Offen', style: theme.textTheme.labelLarge)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ...categories.map(
                  (row) => ListTile(
                    dense: true,
                    title: Text(row['category'] as String),
                    trailing: Wrap(spacing: 12, children: [
                      SizedBox(width: 80, child: Text('${row['total']}', textAlign: TextAlign.right)),
                      SizedBox(
                        width: 220,
                        child: Wrap(spacing: 6, children: [
                          statChip('Rot ${row['pre']['red']}', row['pre']['red'] as int, theme.colorScheme.error),
                          statChip('Gelb ${row['pre']['yellow']}', row['pre']['yellow'] as int, Colors.orange.shade700),
                          statChip('Grün ${row['pre']['green']}', row['pre']['green'] as int, Colors.green.shade700),
                        ]),
                      ),
                      SizedBox(
                        width: 220,
                        child: Wrap(spacing: 6, children: [
                          statChip('Rot ${row['post']['red']}', row['post']['red'] as int, theme.colorScheme.error),
                          statChip('Gelb ${row['post']['yellow']}', row['post']['yellow'] as int, Colors.orange.shade700),
                          statChip('Grün ${row['post']['green']}', row['post']['green'] as int, Colors.green.shade700),
                        ]),
                      ),
                      SizedBox(
                        width: 120,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Chip(label: Text('${row['open']} offene')),
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          blockTitle('Schnellzugriff'),
          Wrap(
            spacing: 8,
            children: [
              quickLink('Zu Risiken', Icons.table_rows_outlined, 1),
              quickLink('Zu Verknüpfungen', Icons.link_outlined, 2),
              OutlinedButton.icon(onPressed: _exportPdf, icon: const Icon(Icons.picture_as_pdf), label: const Text('PDF Export')),
              OutlinedButton.icon(onPressed: _exportCsv, icon: const Icon(Icons.table_chart_outlined), label: const Text('Excel Export')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRiskTab(ThemeData theme, {required bool isDesktop}) {
    final categories = _categoryOptions;
    final visibleRisks = _filteredRisks;
    final selectedRisk = _selectedRiskEntry != null &&
            visibleRisks.any((r) => r.id == _selectedRiskEntry!.id)
        ? _selectedRiskEntry
        : (visibleRisks.isNotEmpty ? visibleRisks.first : null);

    Widget badgeRow(String label, String? level, int? severity, int? occurrence) {
      return Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(label, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
          _riskBadge(level, theme),
          Text('${severity ?? '-'}×${occurrence ?? '-'}', style: theme.textTheme.bodyMedium),
        ],
      );
    }

    Widget filterGroup(String title, List<Widget> children) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: children),
          ],
        ),
      );
    }

    Widget filterContent() {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Filter & Kategorien', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Kategorien (${_currentRisks.length})', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              SizedBox(
                height: 240,
                child: ListView.builder(
                  itemCount: categories.length,
                  itemBuilder: (ctx, idx) {
                    final cat = categories[idx];
                    final isSelected = _selectedCategory == cat;
                    final label = cat == 'all'
                        ? 'Alle'
                        : cat == 'uncategorized'
                            ? 'Ohne Kategorie'
                            : cat;
                    final count = _currentRisks
                        .where((r) => cat == 'all'
                            ? true
                            : cat == 'uncategorized'
                                ? r.category.trim().isEmpty
                                : r.category.trim() == cat)
                        .length;
                    return ListTile(
                      dense: true,
                      title: Text(label, style: theme.textTheme.bodyLarge),
                      trailing: Chip(label: Text('$count')),
                      selected: isSelected,
                      onTap: () => setState(() {
                        _selectedCategory = cat;
                        _syncSelectedRisk();
                      }),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              filterGroup('Einstufung VOR', [
                FilterChip(
                  label: const Text('Rot'),
                  selected: _activeFilters.contains('pre:red'),
                  onSelected: (v) => setState(() {
                    v ? _activeFilters.add('pre:red') : _activeFilters.remove('pre:red');
                    _syncSelectedRisk();
                  }),
                ),
                FilterChip(
                  label: const Text('Gelb'),
                  selected: _activeFilters.contains('pre:yellow'),
                  onSelected: (v) => setState(() {
                    v ? _activeFilters.add('pre:yellow') : _activeFilters.remove('pre:yellow');
                    _syncSelectedRisk();
                  }),
                ),
                FilterChip(
                  label: const Text('Grün'),
                  selected: _activeFilters.contains('pre:green'),
                  onSelected: (v) => setState(() {
                    v ? _activeFilters.add('pre:green') : _activeFilters.remove('pre:green');
                    _syncSelectedRisk();
                  }),
                ),
              ]),
              filterGroup('Einstufung NACH', [
                FilterChip(
                  label: const Text('Rot'),
                  selected: _activeFilters.contains('post:red'),
                  onSelected: (v) => setState(() {
                    v ? _activeFilters.add('post:red') : _activeFilters.remove('post:red');
                    _syncSelectedRisk();
                  }),
                ),
                FilterChip(
                  label: const Text('Gelb'),
                  selected: _activeFilters.contains('post:yellow'),
                  onSelected: (v) => setState(() {
                    v ? _activeFilters.add('post:yellow') : _activeFilters.remove('post:yellow');
                    _syncSelectedRisk();
                  }),
                ),
                FilterChip(
                  label: const Text('Grün'),
                  selected: _activeFilters.contains('post:green'),
                  onSelected: (v) => setState(() {
                    v ? _activeFilters.add('post:green') : _activeFilters.remove('post:green');
                    _syncSelectedRisk();
                  }),
                ),
              ]),
              filterGroup('Flags', [
                FilterChip(
                  label: const Text('Neue Gefährdung'),
                  selected: _activeFilters.contains('newHazard'),
                  onSelected: (v) => setState(() {
                    v ? _activeFilters.add('newHazard') : _activeFilters.remove('newHazard');
                    _syncSelectedRisk();
                  }),
                ),
                FilterChip(
                  label: const Text('Restrisiko nein'),
                  selected: _activeFilters.contains('residualBad'),
                  onSelected: (v) => setState(() {
                    v ? _activeFilters.add('residualBad') : _activeFilters.remove('residualBad');
                    _syncSelectedRisk();
                  }),
                ),
                FilterChip(
                  label: const Text('Nachweise fehlen'),
                  selected: _activeFilters.contains('missingDocs'),
                  onSelected: (v) => setState(() {
                    v ? _activeFilters.add('missingDocs') : _activeFilters.remove('missingDocs');
                    _syncSelectedRisk();
                  }),
                ),
              ]),
              filterGroup('Verknüpfungen', [
                FilterChip(
                  label: const Text('Reklamation verknüpft'),
                  selected: _activeFilters.contains('linkedComplaint'),
                  onSelected: (v) => setState(() {
                    v ? _activeFilters.add('linkedComplaint') : _activeFilters.remove('linkedComplaint');
                    _syncSelectedRisk();
                  }),
                ),
                FilterChip(
                  label: const Text('CAPA verknüpft'),
                  selected: _activeFilters.contains('linkedCapa'),
                  onSelected: (v) => setState(() {
                    v ? _activeFilters.add('linkedCapa') : _activeFilters.remove('linkedCapa');
                    _syncSelectedRisk();
                  }),
                ),
              ]),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _activeFilters.clear();
                    _selectedCategory = 'all';
                    _searchCtrl.clear();
                    _syncSelectedRisk();
                  }),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Filter zurücksetzen'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    List<Widget> activeFilterChips() {
      final chips = <Widget>[];
      if (_selectedCategory != 'all') {
        final label = _selectedCategory == 'uncategorized' ? 'Ohne Kategorie' : _selectedCategory;
        chips.add(InputChip(
          label: Text('Kategorie: $label'),
          onDeleted: () => setState(() {
            _selectedCategory = 'all';
            _syncSelectedRisk();
          }),
        ));
      }

      final mapping = {
        'pre:red': 'Vor Rot',
        'pre:yellow': 'Vor Gelb',
        'pre:green': 'Vor Grün',
        'post:red': 'Nach Rot',
        'post:yellow': 'Nach Gelb',
        'post:green': 'Nach Grün',
        'newHazard': 'Neue Gefährdung',
        'residualBad': 'Restrisiko nein',
        'missingDocs': 'Nachweise fehlen',
        'linkedComplaint': 'Reklamation verknüpft',
        'linkedCapa': 'CAPA verknüpft',
      };
      for (final key in _activeFilters) {
        chips.add(InputChip(
          label: Text(mapping[key] ?? key),
          onDeleted: () => setState(() {
            _activeFilters.remove(key);
            _syncSelectedRisk();
          }),
        ));
      }
      return chips;
    }

    void openFilterDrawer() {
      showDialog(
        context: context,
        builder: (ctx) => Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, minWidth: 360),
            child: Material(
              elevation: 12,
              color: theme.colorScheme.surface,
              child: SafeArea(child: filterContent()),
            ),
          ),
        ),
      );
    }

    Widget detailSection(String title, List<Widget> children) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      );
    }

    Widget detailPane() {
      if (selectedRisk == null) {
        return Center(
          child: Text('Wähle ein Risiko', style: theme.textTheme.bodyLarge),
        );
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Risiko ${selectedRisk.riskNumber}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _riskBadge(selectedRisk.riskLevelAfter ?? selectedRisk.riskLevel, theme),
                        Chip(label: Text(selectedRisk.category.isEmpty ? 'Ohne Kategorie' : selectedRisk.category)),
                        Chip(label: Text('S×A vor: ${selectedRisk.severity ?? '-'}×${selectedRisk.occurrence ?? '-'}')),
                        Chip(label: Text('S×A nach: ${selectedRisk.severityAfter ?? '-'}×${selectedRisk.occurrenceAfter ?? '-'}')),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _readOnly ? null : () => _updateRisk(selectedRisk),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Bearbeiten'),
                    ),
                    OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Duplizieren'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _readOnly ? null : () => _deleteRisk(selectedRisk),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Löschen'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            detailSection('Beschreibung', [
              _RiskDetailRow(label: 'Gefährdung', value: selectedRisk.hazard),
              _RiskDetailRow(label: 'Gefährdungssituation', value: selectedRisk.hazardSituation),
              _RiskDetailRow(label: 'Schaden', value: selectedRisk.harm),
              _RiskDetailRow(label: 'Ursachen', value: selectedRisk.causes),
            ]),
            detailSection('Bewertung vor Maßnahme & Maßnahmen', [
              badgeRow('Vor Maßnahme', selectedRisk.riskLevel, selectedRisk.severity, selectedRisk.occurrence),
              const SizedBox(height: 8),
              _RiskDetailRow(label: 'Maßnahmen (geplant)', value: selectedRisk.proposedAction),
              _RiskDetailRow(label: 'Maßnahmen (durchgeführt)', value: selectedRisk.actionTaken),
            ]),
            detailSection('Bewertung nach Maßnahme & Restrisiko', [
              badgeRow('Nach Maßnahme', selectedRisk.riskLevelAfter, selectedRisk.severityAfter, selectedRisk.occurrenceAfter),
              const SizedBox(height: 8),
              _RiskDetailRow(label: 'Restrisiko / neue Gefährdung', value: selectedRisk.newHazard ? 'Neue Gefährdung' : 'Keine neue Gefährdung'),
              _RiskDetailRow(label: 'RNA', value: selectedRisk.riskBenefitAnalysis),
            ]),
            detailSection('Nachweise & Dokumente', [
              _RiskDetailRow(label: 'Nachweise', value: selectedRisk.documents.isEmpty ? 'Keine Nachweise' : selectedRisk.documents),
            ]),
            detailSection('Verknüpfungen', [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text('Reklamationen: ${selectedRisk.linkedComplaints.length}')),
                  Chip(label: Text('CAPA: ${selectedRisk.linkedCapas.length}')),
                  if (!selectedRisk.residualRiskOk)
                    Chip(
                      label: const Text('Restrisiko kritisch'),
                      backgroundColor: theme.colorScheme.errorContainer,
                    ),
                  if (selectedRisk.newHazard)
                    Chip(
                      label: const Text('Neue Gefährdung'),
                      backgroundColor: theme.colorScheme.tertiaryContainer,
                    ),
                ],
              ),
            ]),
          ],
        ),
      );
    }

    Widget listPane() {
      if (visibleRisks.isEmpty) {
        return Center(
          child: Text('Keine Risiken gefunden', style: theme.textTheme.bodyLarge),
        );
      }

      return ListView.separated(
        itemCount: visibleRisks.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, idx) {
          final r = visibleRisks[idx];
          final active = selectedRisk?.id == r.id;
          final miniValue = _showAfterValues
              ? '${r.severityAfter ?? '-'}×${r.occurrenceAfter ?? '-'}'
              : '${r.severity ?? '-'}×${r.occurrence ?? '-'}';
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _selectedRiskEntry = r),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: active ? theme.colorScheme.primaryContainer.withOpacity(0.35) : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: active ? theme.colorScheme.primary : theme.colorScheme.outlineVariant),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        r.riskNumber,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          r.hazard.isEmpty ? 'Keine Gefährdung' : r.hazard,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _riskBadge(r.riskLevel, theme),
                          const SizedBox(height: 6),
                          _riskBadge(r.riskLevelAfter ?? r.riskLevel, theme),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(label: Text('Vor: ${r.severity ?? '-'}×${r.occurrence ?? '-'}')),
                      Chip(label: Text('Nach: ${r.severityAfter ?? '-'}×${r.occurrenceAfter ?? '-'}')),
                      Chip(label: Text('Aktiv: $miniValue')),
                      Chip(label: Text(r.category.isEmpty ? 'Ohne Kategorie' : r.category)),
                      if (r.linkedComplaints.isNotEmpty) Chip(label: Text('Reklamation ${r.linkedComplaints.length}')),
                      if (r.linkedCapas.isNotEmpty) Chip(label: Text('CAPA ${r.linkedCapas.length}')),
                      if (!r.residualRiskOk)
                        Chip(
                          label: const Text('Restrisiko nein'),
                          backgroundColor: theme.colorScheme.errorContainer,
                        ),
                      if (r.newHazard)
                        Chip(
                          label: const Text('Neue Gefährdung'),
                          backgroundColor: theme.colorScheme.tertiaryContainer,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    final workspace = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Risiken (${_currentRisks.length})', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Chip(label: Text('Gefiltert: ${visibleRisks.length}')),
            const Spacer(),
            ToggleButtons(
              borderRadius: BorderRadius.circular(10),
              isSelected: [!_showAfterValues, _showAfterValues],
              onPressed: (idx) => setState(() => _showAfterValues = idx == 1),
              children: const [
                Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Vor')),
                Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Nach')),
              ],
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 320,
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Risiken durchsuchen',
                  isDense: true,
                ),
                onChanged: (_) => setState(() => _syncSelectedRisk()),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: openFilterDrawer,
              icon: const Icon(Icons.tune),
              label: const Text('Filter & Kategorien'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (activeFilterChips().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: activeFilterChips(),
            ),
          ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 6,
                child: Card(
                  elevation: 0,
                  color: theme.colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: listPane(),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                flex: 4,
                child: Card(
                  elevation: 0,
                  color: theme.colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: detailPane(),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: isDesktop
          ? workspace
          : Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: openFilterDrawer,
                    icon: const Icon(Icons.tune),
                    label: const Text('Filter & Kategorien'),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(child: workspace),
              ],
            ),
    );
  }
  Widget _buildLinksTab(ThemeData theme) {
    final links = _links.where((l) => !_onlyUnlinked || ((l['linkedComplaints'] ?? []).isEmpty && (l['linkedCapas'] ?? []).isEmpty)).toList();
    return Column(
      children: [
        Row(
          children: [
            Text('Verknüpfungen', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Chip(label: Text('${links.length} Zeilen')),
            const Spacer(),
            FilterChip(
              label: const Text('Nur ohne Verknüpfung'),
              selected: _onlyUnlinked,
              onSelected: (v) => setState(() => _onlyUnlinked = v),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Verknüpfungen aktualisieren',
              onPressed: _loadingLinks ? null : _loadLinks,
              icon: const Icon(Icons.refresh_outlined),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: _loadingLinks
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: links.length,
                    itemBuilder: (ctx, idx) {
                      final row = links[idx];
                      final complaints = (row['linkedComplaints'] as List?)?.length ?? 0;
                      final capas = (row['linkedCapas'] as List?)?.length ?? 0;
                      return ListTile(
                        leading: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: _riskBadge(row['riskLevel'] as String?, theme),
                        ),
                        title: Text('${row['mdrTd'] ?? ''} · ${row['riskNumber'] ?? ''}'),
                        subtitle: Text(row['hazard']?.toString() ?? ''),
                        trailing: Wrap(spacing: 6, children: [
                          Chip(label: Text('Rek.: $complaints')),
                          Chip(label: Text('CAPA: $capas')),
                          if (row['newHazard'] == true) const Chip(label: Text('Neue Gefährdung')),
                          if (row['residualRiskOk'] == false)
                            Chip(
                              backgroundColor: theme.colorScheme.errorContainer,
                              label: const Text('Restrisiko prüfen'),
                            ),
                        ]),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  void _openHeaderDrawer() {
    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, minWidth: 420),
            child: Material(
              elevation: 12,
              color: theme.colorScheme.surface,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Kopfdaten', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: SingleChildScrollView(
                          child: _buildHeaderForm(),
                        ),
                      ),
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

  Future<FmeaRiskEntry?> _openRiskDialog({FmeaRiskEntry? existing}) async {
    final categoryOptions = {
      ...?_selected?.risks
          .map((r) => r.category.trim())
          .where((c) => c.isNotEmpty)
          .toSet(),
      if ((existing?.category ?? '').trim().isNotEmpty) existing!.category.trim(),
    }.toList()
      ..sort();

    String? selectedCategory = categoryOptions.contains(existing?.category)
        ? existing?.category
        : null;
    int currentStep = existing == null ? 0 : 1;
    final stepKeys = List.generate(5, (_) => GlobalKey<FormState>());
    final catCtrl = TextEditingController(text: existing?.category ?? '');
    final riskNumberCtrl = TextEditingController(text: existing?.riskNumber ?? '');
    final hazardCtrl = TextEditingController(text: existing?.hazard ?? '');
    final situationCtrl = TextEditingController(text: existing?.hazardSituation ?? '');
    final harmCtrl = TextEditingController(text: existing?.harm ?? '');
    final causeCtrl = TextEditingController(text: existing?.causes ?? '');
    final proposedCtrl = TextEditingController(text: existing?.proposedAction ?? '');
    final actionCtrl = TextEditingController(text: existing?.actionTaken ?? '');
    final documentsCtrl = TextEditingController(text: existing?.documents ?? '');
    final areaCtrl = TextEditingController(text: existing?.affectedArea ?? '');
    final processCtrl = TextEditingController(text: existing?.processReference ?? '');
    final benefitCtrl = TextEditingController(text: existing?.riskBenefitAnalysis ?? '');
    final linkedComplaints = List<String>.from(existing?.linkedComplaints ?? const []);
    final linkedCapas = List<String>.from(existing?.linkedCapas ?? const []);
    int? severity = existing?.severity;
    int? occurrence = existing?.occurrence;
    int? severityAfter = existing?.severityAfter;
    int? occurrenceAfter = existing?.occurrenceAfter;
    bool newHazard = existing?.newHazard ?? false;
    bool residualOk = existing?.residualRiskOk ?? true;
    final initialComplaints = List<String>.from(linkedComplaints);
    final initialCapas = List<String>.from(linkedCapas);
    final initialCategory = catCtrl.text;
    final initialRiskNumber = riskNumberCtrl.text;
    final initialHazard = hazardCtrl.text;
    final initialSituation = situationCtrl.text;
    final initialHarm = harmCtrl.text;
    final initialCauses = causeCtrl.text;
    final initialProposed = proposedCtrl.text;
    final initialAction = actionCtrl.text;
    final initialDocuments = documentsCtrl.text;
    final initialArea = areaCtrl.text;
    final initialProcess = processCtrl.text;
    final initialBenefit = benefitCtrl.text;
    final initialNewHazard = newHazard;
    final initialResidualOk = residualOk;
    final equalList = const ListEquality<String>();

    String? _required(String value) => value.trim().isEmpty ? 'Pflichtfeld' : null;

    bool _hasUnsavedChanges() {
      return catCtrl.text != initialCategory ||
          riskNumberCtrl.text != initialRiskNumber ||
          hazardCtrl.text != initialHazard ||
          situationCtrl.text != initialSituation ||
          harmCtrl.text != initialHarm ||
          causeCtrl.text != initialCauses ||
          proposedCtrl.text != initialProposed ||
          actionCtrl.text != initialAction ||
          documentsCtrl.text != initialDocuments ||
          areaCtrl.text != initialArea ||
          processCtrl.text != initialProcess ||
          benefitCtrl.text != initialBenefit ||
          newHazard != initialNewHazard ||
          residualOk != initialResidualOk ||
          severity != existing?.severity ||
          occurrence != existing?.occurrence ||
          severityAfter != existing?.severityAfter ||
          occurrenceAfter != existing?.occurrenceAfter ||
          !equalList.equals(linkedComplaints, initialComplaints) ||
          !equalList.equals(linkedCapas, initialCapas);
    }

    FmeaRiskEntry _buildResult() {
      return FmeaRiskEntry(
        id: existing?.id ?? '',
        riskNumber: (riskNumberCtrl.text.trim().isEmpty ? existing?.riskNumber : riskNumberCtrl.text.trim()) ?? '',
        category: catCtrl.text.trim(),
        hazard: hazardCtrl.text.trim(),
        hazardSituation: situationCtrl.text.trim(),
        harm: harmCtrl.text.trim(),
        causes: causeCtrl.text.trim(),
        affectedArea: areaCtrl.text.trim(),
        processReference: processCtrl.text.trim(),
        severity: severity,
        occurrence: occurrence,
        riskScore: _riskScore(severity, occurrence),
        riskLevel: _riskLevelFromValues(severity, occurrence),
        severityAfter: severityAfter,
        occurrenceAfter: occurrenceAfter,
        riskScoreAfter: _riskScore(severityAfter, occurrenceAfter),
        riskLevelAfter: _riskLevelFromValues(severityAfter, occurrenceAfter),
        proposedAction: proposedCtrl.text.trim(),
        actionTaken: actionCtrl.text.trim(),
        documents: documentsCtrl.text.trim(),
        riskBenefitAnalysis: benefitCtrl.text.trim(),
        newHazard: newHazard,
        residualRiskOk: residualOk,
        linkedComplaints: linkedComplaints,
        linkedCapas: linkedCapas,
      );
    }

    bool _validateStep(int index) {
      final form = stepKeys[index].currentState;
      if (form == null) return true;
      return form.validate();
    }

    bool _validateUntil(int index, void Function(void Function()) setStateDialog) {
      for (var i = 0; i <= index; i++) {
        if (!_validateStep(i)) {
          setStateDialog(() => currentStep = i);
          return false;
        }
      }
      return true;
    }

    Future<bool> _confirmAbort() async {
      if (!_hasUnsavedChanges()) return true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Änderungen verwerfen?'),
          content: const Text('Nicht gespeicherte Änderungen gehen verloren. Fortfahren?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Zurück')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Verwerfen')),
          ],
        ),
      );
      return discard == true;
    }

    final res = await showDialog<FmeaRiskEntry?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          final complaintLabels = {
            for (final c in _complaints) c.ticket: c.ticket,
          };
          final capaLabels = {
            for (final c in _capas)
              (c.id.isNotEmpty ? c.id : c.capaNumber): (c.capaNumber.isNotEmpty ? c.capaNumber : c.id),
          };
          final beforeScore = _riskScore(severity, occurrence) ?? existing?.riskScore;
          final beforeLevel = _riskLevelFromScore(_riskScore(severity, occurrence)) ?? existing?.riskLevel;
          final afterScore = _riskScore(severityAfter, occurrenceAfter) ?? existing?.riskScoreAfter;
          final afterLevel =
              _riskLevelFromScore(_riskScore(severityAfter, occurrenceAfter)) ?? existing?.riskLevelAfter;
          final steps = [
            Step(
              isActive: currentStep >= 0,
              state: currentStep > 0 ? StepState.complete : StepState.indexed,
              title: const Text('Basis'),
              content: Form(
                key: stepKeys[0],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (categoryOptions.isNotEmpty)
                      DropdownButtonFormField<String>(
                        value: selectedCategory,
                        decoration: const InputDecoration(labelText: 'Kategorie auswählen'),
                        items: categoryOptions
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c),
                                ))
                            .toList(),
                        onChanged: (val) {
                          setStateDialog(() {
                            selectedCategory = val;
                            catCtrl.text = val ?? '';
                          });
                        },
                      ),
                    TextFormField(
                      controller: catCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Kategorie eingeben',
                        helperText: 'Eigene Kategorie eingeben oder Auswahl oben nutzen',
                      ),
                      onChanged: (val) => setStateDialog(() {
                        selectedCategory = categoryOptions.contains(val) ? val : null;
                      }),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: riskNumberCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Risiko-Nr.',
                        helperText: 'Automatisch, wenn leer – manuell überschreibbar',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: processCtrl,
                      decoration: const InputDecoration(labelText: 'Prozessbezug'),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: areaCtrl,
                      decoration: const InputDecoration(labelText: 'Gefährdeter Bereich / Beteiligte'),
                    ),
                  ],
                ),
              ),
            ),
            Step(
              isActive: currentStep >= 1,
              state: currentStep > 1 ? StepState.complete : StepState.indexed,
              title: const Text('Risiko-Beschreibung'),
              content: Form(
                key: stepKeys[1],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: hazardCtrl,
                      minLines: 4,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Gefährdung',
                        alignLabelWithHint: true,
                      ),
                      onChanged: (_) => setStateDialog(() {}),
                      validator: (val) => _required(val ?? ''),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: situationCtrl,
                      minLines: 6,
                      maxLines: 12,
                      decoration: const InputDecoration(
                        labelText: 'Gefährdungssituation',
                        alignLabelWithHint: true,
                      ),
                      onChanged: (_) => setStateDialog(() {}),
                      validator: (val) => _required(val ?? ''),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: harmCtrl,
                      minLines: 4,
                      maxLines: 10,
                      decoration: const InputDecoration(
                        labelText: 'Schaden',
                        alignLabelWithHint: true,
                      ),
                      onChanged: (_) => setStateDialog(() {}),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: causeCtrl,
                      minLines: 4,
                      maxLines: 10,
                      decoration: const InputDecoration(
                        labelText: 'Ursachen',
                        alignLabelWithHint: true,
                      ),
                      onChanged: (_) => setStateDialog(() {}),
                    ),
                  ],
                ),
              ),
            ),
            Step(
              isActive: currentStep >= 2,
              state: currentStep > 2 ? StepState.complete : StepState.indexed,
              title: const Text('Bewertung'),
              content: Form(
                key: stepKeys[2],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: severity,
                            decoration: const InputDecoration(labelText: 'Schweregrad S'),
                            items: [1, 2, 3, 4, 5]
                                .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                                .toList(),
                            onChanged: (val) => setStateDialog(() => severity = val),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: occurrence,
                            decoration: const InputDecoration(labelText: 'Auftritt A'),
                            items: [1, 2, 3, 4, 5]
                                .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                                .toList(),
                            onChanged: (val) => setStateDialog(() => occurrence = val),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _riskBadge(beforeLevel, Theme.of(context)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            beforeScore != null
                                ? 'Score: $beforeScore (S×A) – Einstufung wird live berechnet.'
                                : 'Bitte S und A wählen, die Einstufung wird dann automatisch berechnet.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Step(
              isActive: currentStep >= 3,
              state: currentStep > 3 ? StepState.complete : StepState.indexed,
              title: const Text('Maßnahmen'),
              content: Form(
                key: stepKeys[3],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: proposedCtrl,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Vorgeschlagene Maßnahme',
                        alignLabelWithHint: true,
                      ),
                      onChanged: (_) => setStateDialog(() {}),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: actionCtrl,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Getroffene Maßnahme',
                        alignLabelWithHint: true,
                      ),
                      onChanged: (_) => setStateDialog(() {}),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: documentsCtrl,
                      minLines: 2,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Nachweise / Dokumente (Links/IDs)',
                        alignLabelWithHint: true,
                      ),
                      onChanged: (_) => setStateDialog(() {}),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: severityAfter,
                            decoration: const InputDecoration(labelText: 'Schweregrad S(n)'),
                            items: [1, 2, 3, 4, 5]
                                .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                                .toList(),
                            onChanged: (val) => setStateDialog(() => severityAfter = val),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: occurrenceAfter,
                            decoration: const InputDecoration(labelText: 'Auftritt A(n)'),
                            items: [1, 2, 3, 4, 5]
                                .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                                .toList(),
                            onChanged: (val) => setStateDialog(() => occurrenceAfter = val),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _riskBadge(afterLevel, Theme.of(context)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            afterScore != null
                                ? 'Score(n): $afterScore (S×A) – Einstufung wird live berechnet.'
                                : 'Bitte S(n) und A(n) wählen, die Einstufung wird dann automatisch berechnet.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: residualOk,
                      onChanged: (v) => setStateDialog(() => residualOk = v ?? true),
                      title: const Text('Restrisiko beherrschbar?'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    CheckboxListTile(
                      value: newHazard,
                      onChanged: (v) => setStateDialog(() => newHazard = v ?? false),
                      title: const Text('Neue Gefährdung?'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ),
              ),
            ),
            Step(
              isActive: currentStep >= 4,
              state: currentStep > 4 ? StepState.complete : StepState.indexed,
              title: const Text('Analyse & Links'),
              content: Form(
                key: stepKeys[4],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: benefitCtrl,
                      minLines: 4,
                      maxLines: 12,
                      decoration: const InputDecoration(
                        labelText: 'Risiko-Nutzen-Analyse',
                        alignLabelWithHint: true,
                      ),
                      onChanged: (_) => setStateDialog(() {}),
                    ),
                    const SizedBox(height: 10),
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Verknüpfte Reklamations-Tickets'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: linkedComplaints
                                .map((t) => Chip(
                                      label: Text(complaintLabels[t] ?? t),
                                      onDeleted: () => setStateDialog(() => linkedComplaints.remove(t)),
                                    ))
                                .toList(),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () async {
                                final updated = await _openMultiSelectDialog(
                                  title: 'Reklamationen auswählen',
                                  options: complaintLabels.keys.toList(),
                                  selected: linkedComplaints,
                                  labelBuilder: (v) => complaintLabels[v] ?? v,
                                );
                                if (updated != null) {
                                  setStateDialog(() {
                                    linkedComplaints
                                      ..clear()
                                      ..addAll(updated);
                                  });
                                }
                              },
                              icon: const Icon(Icons.link),
                              label: const Text('Tickets auswählen'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Verknüpfte CAPA/8D-IDs'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: linkedCapas
                                .map((id) => Chip(
                                      label: Text(capaLabels[id] ?? id),
                                      onDeleted: () => setStateDialog(() => linkedCapas.remove(id)),
                                    ))
                                .toList(),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () async {
                                final updated = await _openMultiSelectDialog(
                                  title: 'CAPA/8D auswählen',
                                  options: capaLabels.keys.toList(),
                                  selected: linkedCapas,
                                  labelBuilder: (v) => capaLabels[v] ?? v,
                                );
                                if (updated != null) {
                                  setStateDialog(() {
                                    linkedCapas
                                      ..clear()
                                      ..addAll(updated);
                                  });
                                }
                              },
                              icon: const Icon(Icons.link),
                              label: const Text('CAPA auswählen'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 0,
                      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Vorschau', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 6),
                            Text('Gefährdung: ${hazardCtrl.text.isEmpty ? '—' : hazardCtrl.text}'),
                            Text('Situation: ${situationCtrl.text.isEmpty ? '—' : situationCtrl.text}'),
                            Text('Maßnahmen: ${actionCtrl.text.isEmpty ? '—' : actionCtrl.text}'),
                            Text('Nachweise: ${documentsCtrl.text.isEmpty ? '—' : documentsCtrl.text}'),
                            Text('RNA: ${benefitCtrl.text.isEmpty ? '—' : benefitCtrl.text}'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ];

          void _nextStep() {
            if (!_validateStep(currentStep)) return;
            if (currentStep < steps.length - 1) {
              setStateDialog(() => currentStep += 1);
            }
          }

          Future<void> _saveDraft() async {
            if (!_validateUntil(currentStep, setStateDialog)) return;
            Navigator.pop(ctx, _buildResult());
          }

          Future<void> _finish() async {
            if (!_validateUntil(steps.length - 1, setStateDialog)) return;
            Navigator.pop(ctx, _buildResult());
          }

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final media = MediaQuery.of(context);
                final maxWidth = math.min(media.size.width * 0.95, 1200.0);
                final minWidth = math.min(media.size.width * 0.7, maxWidth);
                final maxHeight = media.size.height * 0.9;

                final isLast = currentStep == steps.length - 1;

          final theme = Theme.of(context);

          Widget stepIndicator(int idx, Step step) {
            final isCurrent = idx == currentStep;
            final isComplete = currentStep > idx;
            final bgColor = isCurrent
                ? theme.colorScheme.primaryContainer.withOpacity(0.9)
                : theme.colorScheme.surfaceVariant;
            final borderColor = isComplete
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant;
            final fgColor = isCurrent
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant;

            return InkWell(
              onTap: () {
                if (_validateUntil(idx, setStateDialog)) {
                  setStateDialog(() => currentStep = idx);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor:
                          isComplete ? theme.colorScheme.primary : theme.colorScheme.surface,
                      foregroundColor: isComplete
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                      child: isComplete
                          ? const Icon(Icons.check, size: 18)
                          : Text('${idx + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                    DefaultTextStyle.merge(
                      style: TextStyle(
                        color: fgColor,
                        fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                        overflow: TextOverflow.visible,
                      ),
                      child: step.title,
                    ),
                  ],
                ),
              ),
            );
          }

          Widget stepContentArea() {
            return AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: IndexedStack(
                index: currentStep,
                children: steps
                    .asMap()
                    .entries
                    .map(
                      (entry) => Visibility(
                        visible: entry.key == currentStep,
                        maintainState: true,
                        maintainAnimation: true,
                        maintainSize: true,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: entry.value.content,
                        ),
                      ),
                    )
                    .toList(),
              ),
            );
          }

                return ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: minWidth,
                    maxWidth: maxWidth,
                    maxHeight: maxHeight,
                  ),
                  child: SizedBox(
                    width: maxWidth,
                    height: maxHeight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                          child: Text(
                            existing == null ? 'Risiko hinzufügen' : 'Risiko bearbeiten',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: Scrollbar(
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: steps
                                        .asMap()
                                        .entries
                                        .map((entry) => stepIndicator(entry.key, entry.value))
                                        .toList(),
                                  ),
                                  const SizedBox(height: 12),
                                  stepContentArea(),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        SafeArea(
                          top: false,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).dialogBackgroundColor,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 8,
                                  offset: const Offset(0, -2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                TextButton(
                                  onPressed: () async {
                                    if (await _confirmAbort()) {
                                      Navigator.pop(ctx, null);
                                    }
                                  },
                                  child: const Text('Abbrechen'),
                                ),
                                const Spacer(),
                                if (currentStep > 0)
                                  OutlinedButton(
                                    onPressed: () => setStateDialog(() => currentStep -= 1),
                                    child: const Text('Zurück'),
                                  ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: _saveDraft,
                                  child: const Text('Zwischenspeichern'),
                                ),
                                const SizedBox(width: 8),
                                isLast
                                    ? FilledButton(onPressed: _finish, child: const Text('Speichern'))
                                    : FilledButton(onPressed: _nextStep, child: const Text('Weiter')),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );

    catCtrl.dispose();
    hazardCtrl.dispose();
    situationCtrl.dispose();
    harmCtrl.dispose();
    causeCtrl.dispose();
    proposedCtrl.dispose();
    actionCtrl.dispose();
    documentsCtrl.dispose();
    areaCtrl.dispose();
    processCtrl.dispose();
    benefitCtrl.dispose();
    riskNumberCtrl.dispose();
    return res;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1100;
        final compactTheme = theme.copyWith(
          textTheme: theme.textTheme.apply(fontSizeFactor: 1.12),
          chipTheme: theme.chipTheme.copyWith(labelPadding: const EdgeInsets.symmetric(horizontal: 10)),
          visualDensity: VisualDensity.standard,
        );

        final fmeaTitle = _selected == null
            ? 'Keine FMEA ausgewählt'
            : '${_selected!.mdrTd.isNotEmpty ? _selected!.mdrTd : _selected!.title} – Rev. ${_selected!.revision.isEmpty ? '1' : _selected!.revision}';

        return Theme(
          data: compactTheme,
          child: DefaultTabController(
            length: 3,
            initialIndex: 1,
            child: Scaffold(
              backgroundColor: theme.colorScheme.surface,
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(112),
                child: Material(
                  elevation: 2,
                  color: theme.colorScheme.surface,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Qualitätsmanagement > FMEA',
                                    style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    fmeaTitle,
                                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  if (_selected != null)
                                    Text(
                                      'Moderator: ${_selected!.moderator.isEmpty ? '—' : _selected!.moderator}',
                                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: DropdownButtonFormField<String>(
                                        value: _selected?.id,
                                        decoration: const InputDecoration(
                                          labelText: 'FMEA auswählen',
                                          isDense: true,
                                        ),
                                        items: _fmeas
                                            .map(
                                              (f) => DropdownMenuItem(
                                                value: f.id,
                                                child: Text(
                                                  f.mdrTd.isNotEmpty ? f.mdrTd : f.title,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (value) {
                                          final target = _fmeas.firstWhereOrNull((f) => f.id == value);
                                          if (target != null) {
                                            _setSelection(target);
                                            _syncSelectedRisk();
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: 'FMEA-Liste aktualisieren',
                                      onPressed: _loadingList ? null : _loadFmeas,
                                      icon: const Icon(Icons.refresh_outlined),
                                    ),
                                    if (widget.canEdit)
                                      IconButton(
                                        tooltip: 'Neue FMEA',
                                        onPressed: _saving ? null : _createFmea,
                                        icon: const Icon(Icons.add_circle_outline),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _selected == null || _saving ? null : _exportPdf,
                                    icon: const Icon(Icons.picture_as_pdf_outlined),
                                    label: const Text('PDF'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _selected == null || _saving ? null : _exportCsv,
                                    icon: const Icon(Icons.table_view_outlined),
                                    label: const Text('Excel'),
                                  ),
                                  if (widget.canEdit)
                                    OutlinedButton.icon(
                                      onPressed: _selected == null || _saving ? null : _deleteSelected,
                                      icon: const Icon(Icons.delete_outline),
                                      label: const Text('Löschen'),
                                    ),
                                  FilledButton.icon(
                                    onPressed: _selected == null || _saving ? null : _addRisk,
                                    icon: const Icon(Icons.add_outlined),
                                    label: const Text('+ Risiko'),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: _selected == null ? null : _openHeaderDrawer,
                                    icon: const Icon(Icons.info_outline),
                                    label: const Text('Kopfdaten'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TabBar(
                              isScrollable: true,
                              labelColor: theme.colorScheme.primary,
                              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                              indicatorColor: theme.colorScheme.primary,
                              labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                              tabs: const [
                                Tab(text: 'Übersicht'),
                                Tab(text: 'Risiken'),
                                Tab(text: 'Verknüpfungen'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              body: TabBarView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: _buildOverviewTab(theme),
                  ),
                  _buildRiskTab(theme, isDesktop: isDesktop),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: _buildLinksTab(theme),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 220,
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
                  style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: theme.textTheme.headlineMedium?.copyWith(color: theme.colorScheme.onSurface)),
          if (subtitle != null)
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _RiskStatCard extends StatelessWidget {
  final String title;
  final Map<String, int> counts;
  final ThemeData theme;

  const _RiskStatCard({required this.title, required this.counts, required this.theme});

  @override
  Widget build(BuildContext context) {
    Widget row(String label, int count, Color color) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 8, backgroundColor: color),
            const SizedBox(width: 6),
            Text('$label: $count'),
          ],
        );

    return Container(
      width: 240,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          row('Rot', counts['red'] ?? 0, theme.colorScheme.error),
          row('Gelb', counts['yellow'] ?? 0, Colors.orange.shade700),
          row('Grün', counts['green'] ?? 0, Colors.green.shade700),
        ],
      ),
    );
  }
}

class _RiskDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _RiskDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 220, child: Text(label, style: theme.textTheme.labelLarge)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
