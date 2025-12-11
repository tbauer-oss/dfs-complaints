import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:typed_data';

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
  static const _fallbackMdrOptions = <String>[
    'MDR-TD1 - rot. Dentalinstrumente',
    'MDR-TD2 - Knochenfräser',
    'MDR-TD3 - Dentalpolierer',
    'MDR-TD4 - PreciCut',
    'MDR-TD5 - Dentallegierungen',
  ];

  bool _loadingList = false;
  bool _saving = false;
  String? _error;
  List<FmeaRecord> _fmeas = const [];
  FmeaRecord? _selected;
  List<Map<String, dynamic>> _links = const [];
  bool _loadingLinks = false;
  bool _onlyUnlinked = false;
  List<String> _productGroups = const [];
  List<PortalUserSummary> _portalUsers = const [];
  List<Complaint> _complaints = const [];
  List<CapaReport> _capas = const [];
  bool _loadingRefs = false;
  final _productService = DfsProductService();

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

  List<String> get _mdrOptions {
    final merged = {..._fallbackMdrOptions, ..._productGroupOptions};
    return merged.toList()..sort();
  }

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
      setState(() {
        _portalUsers = users;
        _complaints = complaints;
        _capas = capas;
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
      setState(() => _selected = refreshed);
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
        return theme.colorScheme.outline;
    }
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
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: theme.colorScheme.outlineVariant)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Kopfdaten', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
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
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    value: _productGroupOptions.contains(_productGroupCtrl.text.trim())
                        ? _productGroupCtrl.text.trim()
                        : null,
                    decoration: const InputDecoration(labelText: 'Produktgruppe'),
                    items: {
                      ..._productGroupOptions,
                      if (_productGroupCtrl.text.trim().isNotEmpty) _productGroupCtrl.text.trim(),
                    }
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: _readOnly
                        ? null
                        : (val) => setState(() => _productGroupCtrl.text = val ?? ''),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _medicalProductCtrl,
                    decoration: const InputDecoration(labelText: 'Medizinprodukt'),
                    readOnly: _readOnly,
                  ),
                ),
                SizedBox(
                  width: 220,
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
                        : (val) => setState(() => _moderatorCtrl.text = val ?? ''),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _revisionCtrl,
                    decoration: const InputDecoration(labelText: 'Revision'),
                    keyboardType: TextInputType.number,
                    readOnly: _readOnly,
                  ),
                ),
              ],
            ),
            spacing,
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                FilterChip(
                  label: const Text('PRRC-Freigabe erteilt'),
                  selected: _prrcApproved,
                  onSelected: _readOnly
                      ? null
                      : (v) {
                          setState(() => _prrcApproved = v);
                          if (v && _prrcDate == null) _prrcDate = DateTime.now();
                        },
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
      ),
    );
  }

  Widget _buildRiskTable() {
    final theme = Theme.of(context);
    final risks = _selected?.risks ?? const [];
    if (risks.isEmpty) {
      return Center(
        child: Text('Keine Risiken erfasst', style: theme.textTheme.bodyMedium),
      );
    }

    const columnWidths = [110.0, 180.0, 220.0, 150.0, 160.0, 220.0, 140.0];
    final minWidth = columnWidths.reduce((a, b) => a + b);

    Widget headerCell(String label, double width) => SizedBox(
          width: width,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        );

    Widget cell(Widget child, double width) => SizedBox(
          width: width,
          child: child,
        );

    Widget riskRow(FmeaRiskEntry r) {
      final color = _riskColor(r.riskLevel, theme);
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cell(Text(r.riskNumber), columnWidths[0]),
            cell(Text(r.category.isEmpty ? '—' : r.category), columnWidths[1]),
            cell(Text(r.hazard.isEmpty ? '—' : r.hazard), columnWidths[2]),
            cell(
              Text(r.riskScore != null ? '${r.severity ?? '-'}×${r.occurrence ?? '-'}' : '—'),
              columnWidths[3],
            ),
            cell(
              Row(
                children: [
                  CircleAvatar(radius: 6, backgroundColor: color),
                  const SizedBox(width: 6),
                  Text(r.riskLevel?.toUpperCase() ?? 'n/a'),
                ],
              ),
              columnWidths[4],
            ),
            cell(
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (r.linkedComplaints.isNotEmpty)
                    Chip(label: Text('Reklamationen: ${r.linkedComplaints.length}')),
                  if (r.linkedCapas.isNotEmpty) Chip(label: Text('CAPA: ${r.linkedCapas.length}')),
                  Chip(
                    backgroundColor:
                        r.residualRiskOk ? Colors.green.shade100 : theme.colorScheme.errorContainer,
                    label: Text(r.residualRiskOk ? 'Restrisiko ok' : 'Restrisiko kritisch'),
                  ),
                  if (r.newHazard)
                    Chip(
                      backgroundColor: theme.colorScheme.errorContainer,
                      label: const Text('Neue Gefährdung'),
                    ),
                ],
              ),
              columnWidths[5],
            ),
            cell(
              Row(
                children: [
                  IconButton(
                    tooltip: 'Bearbeiten',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: _readOnly ? null : () => _updateRisk(r),
                  ),
                  IconButton(
                    tooltip: 'Löschen',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _readOnly ? null : () => _deleteRisk(r),
                  ),
                ],
              ),
              columnWidths[6],
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final bodyHeight = math.max(0.0, constraints.maxHeight - 56);
        return Scrollbar(
          controller: _riskHorizontal,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _riskHorizontal,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minWidth),
              child: Column(
                children: [
                  Container(
                    color: theme.colorScheme.surfaceVariant,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: Row(
                      children: [
                        headerCell('Risiko-Nr.', columnWidths[0]),
                        headerCell('Kategorie', columnWidths[1]),
                        headerCell('Gefährdung', columnWidths[2]),
                        headerCell('S×A', columnWidths[3]),
                        headerCell('Einstufung', columnWidths[4]),
                        headerCell('Links / Status', columnWidths[5]),
                        headerCell('Aktionen', columnWidths[6]),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  SizedBox(
                    height: bodyHeight,
                    child: Scrollbar(
                      controller: _riskVertical,
                      thumbVisibility: true,
                      child: GestureDetector(
                        onPanUpdate: _panRiskTable,
                        child: SingleChildScrollView(
                          controller: _riskVertical,
                          child: Column(
                            children: risks.map(riskRow).toList(),
                          ),
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

  Widget _buildRiskTab(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Risiken', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Chip(label: Text('${_selected?.risks.length ?? 0} Einträge')),
            const Spacer(),
            if (widget.canEdit)
              FilledButton.icon(
                onPressed: _saving ? null : _addRisk,
                icon: const Icon(Icons.add_outlined),
                label: const Text('Risiko hinzufügen'),
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
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _buildRiskTable(),
            ),
          ),
        ),
      ],
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
                      final badgeColor = _riskColor(row['riskLevel'] as String?, theme);
                      return ListTile(
                        leading: CircleAvatar(backgroundColor: badgeColor, radius: 10),
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

  Future<FmeaRiskEntry?> _openRiskDialog({FmeaRiskEntry? existing}) async {
    final catCtrl = TextEditingController(text: existing?.category ?? '');
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
          return AlertDialog(
            title: Text(existing == null ? 'Risiko hinzufügen' : 'Risiko bearbeiten'),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: catCtrl,
                      decoration: const InputDecoration(labelText: 'Kategorie'),
                    ),
                    TextField(
                      controller: hazardCtrl,
                      decoration: const InputDecoration(labelText: 'Gefährdung'),
                    ),
                    TextField(
                      controller: situationCtrl,
                      decoration: const InputDecoration(labelText: 'Gefährdungssituation'),
                    ),
                    TextField(
                      controller: harmCtrl,
                      decoration: const InputDecoration(labelText: 'Schaden'),
                    ),
                    TextField(
                      controller: causeCtrl,
                      decoration: const InputDecoration(labelText: 'Ursachen'),
                    ),
                    TextField(
                      controller: areaCtrl,
                      decoration: const InputDecoration(labelText: 'Gefährdeter Bereich / Beteiligte'),
                    ),
                    TextField(
                      controller: processCtrl,
                      decoration: const InputDecoration(labelText: 'Prozessbezug'),
                    ),
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
                    TextField(
                      controller: proposedCtrl,
                      decoration: const InputDecoration(labelText: 'Vorgeschlagene Maßnahme'),
                    ),
                    TextField(
                      controller: actionCtrl,
                      decoration: const InputDecoration(labelText: 'Getroffene Maßnahme'),
                    ),
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
                    TextField(
                      controller: documentsCtrl,
                      decoration: const InputDecoration(labelText: 'Nachweise / Dokumente (Links/IDs)'),
                    ),
                    TextField(
                      controller: benefitCtrl,
                      decoration: const InputDecoration(labelText: 'Risiko-Nutzen-Analyse'),
                      maxLines: 2,
                    ),
                    CheckboxListTile(
                      value: newHazard,
                      onChanged: (v) => setStateDialog(() => newHazard = v ?? false),
                      title: const Text('Neue Gefährdung?'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    CheckboxListTile(
                      value: residualOk,
                      onChanged: (v) => setStateDialog(() => residualOk = v ?? true),
                      title: const Text('Restrisiko beherrschbar?'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
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
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Abbrechen')),
              FilledButton(
                onPressed: () {
                  Navigator.pop(
                    ctx,
                    FmeaRiskEntry(
                      id: existing?.id ?? '',
                      riskNumber: existing?.riskNumber ?? '',
                      category: catCtrl.text.trim(),
                      hazard: hazardCtrl.text.trim(),
                      hazardSituation: situationCtrl.text.trim(),
                      harm: harmCtrl.text.trim(),
                      causes: causeCtrl.text.trim(),
                      affectedArea: areaCtrl.text.trim(),
                      processReference: processCtrl.text.trim(),
                      severity: severity,
                      occurrence: occurrence,
                      severityAfter: severityAfter,
                      occurrenceAfter: occurrenceAfter,
                      proposedAction: proposedCtrl.text.trim(),
                      actionTaken: actionCtrl.text.trim(),
                      documents: documentsCtrl.text.trim(),
                      riskBenefitAnalysis: benefitCtrl.text.trim(),
                      newHazard: newHazard,
                      residualRiskOk: residualOk,
                      linkedComplaints: linkedComplaints,
                      linkedCapas: linkedCapas,
                    ),
                  );
                },
                child: const Text('Speichern'),
              ),
            ],
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
    return res;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('FMEA', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              Chip(label: Text('${_fmeas.length} Dateien')),
              const Spacer(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ),
              if (widget.canEdit)
                FilledButton.icon(
                  onPressed: _saving ? null : _createFmea,
                  icon: const Icon(Icons.add_outlined),
                  label: const Text('Neue FMEA'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 320,
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(Icons.assignment_outlined),
                              const SizedBox(width: 8),
                              Text('FMEAs', style: theme.textTheme.titleMedium),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Aktualisieren',
                                onPressed: _loadingList ? null : _loadFmeas,
                                icon: const Icon(Icons.refresh_outlined),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: _loadingList
                              ? const Center(child: CircularProgressIndicator())
                              : ListView.builder(
                                  itemCount: _fmeas.length,
                                  itemBuilder: (ctx, idx) {
                                    final f = _fmeas[idx];
                                    final selected = _selected?.id == f.id;
                                    return ListTile(
                                      selected: selected,
                                      onTap: () {
                                        setState(() => _setSelection(f));
                                      },
                                      title: Text(f.mdrTd.isNotEmpty ? f.mdrTd : f.title),
                                      subtitle: Text(
                                        'Revision ${f.revision.isEmpty ? '–' : f.revision} · ${f.updatedAt != null ? _dateFmt.format(f.updatedAt!) : 'ohne Datum'}',
                                      ),
                                      trailing: CircleAvatar(
                                        radius: 12,
                                        backgroundColor: theme.colorScheme.primaryContainer,
                                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                                        child: Text('${f.risks.length}'),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _selected == null
                      ? Center(
                          child: Text(
                            'Keine FMEA ausgewählt',
                            style: theme.textTheme.bodyLarge,
                          ),
                        )
                      : DefaultTabController(
                          length: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildHeaderForm(),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TabBar(
                                      tabs: const [
                                        Tab(text: 'Risiken'),
                                        Tab(text: 'Verknüpfungen'),
                                      ],
                                      labelColor: theme.colorScheme.primary,
                                      unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  IconButton(
                                    tooltip: 'PDF exportieren',
                                    onPressed: _saving ? null : _exportPdf,
                                    icon: const Icon(Icons.picture_as_pdf_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Excel/CSV exportieren',
                                    onPressed: _saving ? null : _exportCsv,
                                    icon: const Icon(Icons.table_view_outlined),
                                  ),
                                  if (widget.canEdit)
                                    TextButton.icon(
                                      onPressed: _saving ? null : _deleteSelected,
                                      icon: const Icon(Icons.delete_outline),
                                      label: const Text('FMEA löschen'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: TabBarView(
                                  children: [
                                    _buildRiskTab(theme),
                                    _buildLinksTab(theme),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
