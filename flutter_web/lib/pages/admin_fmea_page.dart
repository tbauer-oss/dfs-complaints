import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/client.dart';
import '../models/fmea.dart';

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

  final _mdrTdCtrl = TextEditingController();
  final _productGroupCtrl = TextEditingController();
  final _medicalProductCtrl = TextEditingController();
  final _moderatorCtrl = TextEditingController();
  final _revisionCtrl = TextEditingController();
  final _prrcNameCtrl = TextEditingController();
  bool _prrcApproved = false;
  DateTime? _prrcDate;

  bool get _readOnly => !widget.canEdit;

  @override
  void initState() {
    super.initState();
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

  void _setSelection(FmeaRecord? record) {
    setState(() {
      _selected = record;
      _mdrTdCtrl.text = record?.mdrTd ?? '';
      _productGroupCtrl.text = record?.productGroup ?? '';
      _medicalProductCtrl.text = record?.medicalProduct ?? '';
      _moderatorCtrl.text = record?.moderator ?? '';
      _revisionCtrl.text = record?.revision ?? '';
      _prrcNameCtrl.text = record?.prrcName ?? '';
      _prrcApproved = record?.prrcApproved ?? false;
      _prrcDate = record?.prrcDate;
    });
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
        revision: _revisionCtrl.text.trim(),
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
    final mdrTdCtrl = TextEditingController();
    final productCtrl = TextEditingController();
    final moderatorCtrl = TextEditingController();
    final revisionCtrl = TextEditingController(text: 'A');

    final result = await showDialog<FmeaRecord?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Neue FMEA anlegen'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: mdrTdCtrl,
                decoration: const InputDecoration(labelText: 'MDR-TD / Medizinprodukt'),
              ),
              TextField(
                controller: productCtrl,
                decoration: const InputDecoration(labelText: 'Produktgruppe'),
              ),
              TextField(
                controller: moderatorCtrl,
                decoration: const InputDecoration(labelText: 'FMEA-Moderator'),
              ),
              TextField(
                controller: revisionCtrl,
                decoration: const InputDecoration(labelText: 'Revision'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () {
              final title = mdrTdCtrl.text.trim();
              if (title.isEmpty) return;
              Navigator.pop(
                ctx,
                FmeaRecord(
                  id: '',
                  title: title,
                  mdrTd: title,
                  productGroup: productCtrl.text.trim(),
                  medicalProduct: productCtrl.text.trim(),
                  moderator: moderatorCtrl.text.trim(),
                  revision: revisionCtrl.text.trim(),
                ),
              );
            },
            child: const Text('Anlegen'),
          ),
        ],
      ),
    );

    mdrTdCtrl.dispose();
    productCtrl.dispose();
    moderatorCtrl.dispose();
    revisionCtrl.dispose();
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
                  child: TextField(
                    controller: _mdrTdCtrl,
                    decoration: const InputDecoration(labelText: 'MDR-TD / Medizinprodukt'),
                    readOnly: _readOnly,
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _productGroupCtrl,
                    decoration: const InputDecoration(labelText: 'Produktgruppe'),
                    readOnly: _readOnly,
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
                  child: TextField(
                    controller: _moderatorCtrl,
                    decoration: const InputDecoration(labelText: 'FMEA-Moderator'),
                    readOnly: _readOnly,
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _revisionCtrl,
                    decoration: const InputDecoration(labelText: 'Revision'),
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
                  child: TextField(
                    controller: _prrcNameCtrl,
                    decoration: const InputDecoration(labelText: 'PRRC-Name'),
                    readOnly: _readOnly,
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Risiko-Nr.')),
          DataColumn(label: Text('Kategorie')),
          DataColumn(label: Text('Gefährdung')),
          DataColumn(label: Text('S×A')),
          DataColumn(label: Text('Einstufung')),
          DataColumn(label: Text('Links / Status')),
          DataColumn(label: Text('Maßnahmen')),
          DataColumn(label: Text('Aktionen')),
        ],
        rows: risks.map((r) {
          final color = _riskColor(r.riskLevel, theme);
          return DataRow(cells: [
            DataCell(Text(r.riskNumber)),
            DataCell(Text(r.category.isEmpty ? '—' : r.category)),
            DataCell(Text(r.hazard.isEmpty ? '—' : r.hazard)),
            DataCell(Text(r.riskScore != null ? '${r.severity ?? '-'}×${r.occurrence ?? '-'}' : '—')),
            DataCell(Row(
              children: [
                CircleAvatar(radius: 6, backgroundColor: color),
                const SizedBox(width: 6),
                Text(r.riskLevel?.toUpperCase() ?? 'n/a'),
              ],
            )),
            DataCell(Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (r.linkedComplaints.isNotEmpty)
                  Chip(label: Text('Reklamationen: ${r.linkedComplaints.length}')),
                if (r.linkedCapas.isNotEmpty) Chip(label: Text('CAPA: ${r.linkedCapas.length}')),
                Chip(
                  backgroundColor: r.residualRiskOk ? Colors.green.shade100 : theme.colorScheme.errorContainer,
                  label: Text(r.residualRiskOk ? 'Restrisiko ok' : 'Restrisiko kritisch'),
                ),
                if (r.newHazard)
                  Chip(
                    backgroundColor: theme.colorScheme.errorContainer,
                    label: const Text('Neue Gefährdung'),
                  ),
              ],
            )),
            DataCell(Text((r.proposedAction.isNotEmpty ? r.proposedAction : r.actionTaken).isEmpty
                ? '—'
                : (r.proposedAction.isNotEmpty ? r.proposedAction : r.actionTaken))),
            DataCell(Row(
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
            )),
          ]);
        }).toList(),
      ),
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
    final linkedComplaintsCtrl = TextEditingController(text: (existing?.linkedComplaints ?? []).join(', '));
    final linkedCapasCtrl = TextEditingController(text: (existing?.linkedCapas ?? []).join(', '));
    int? severity = existing?.severity;
    int? occurrence = existing?.occurrence;
    int? severityAfter = existing?.severityAfter;
    int? occurrenceAfter = existing?.occurrenceAfter;
    bool newHazard = existing?.newHazard ?? false;
    bool residualOk = existing?.residualRiskOk ?? true;

    final res = await showDialog<FmeaRiskEntry?>(
      context: context,
      builder: (ctx) => AlertDialog(
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
                        onChanged: (val) => severity = val,
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
                        onChanged: (val) => occurrence = val,
                      ),
                    ),
                  ],
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
                        onChanged: (val) => severityAfter = val,
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
                        onChanged: (val) => occurrenceAfter = val,
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
                  onChanged: (v) => setState(() => newHazard = v ?? false),
                  title: const Text('Neue Gefährdung?'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  value: residualOk,
                  onChanged: (v) => setState(() => residualOk = v ?? true),
                  title: const Text('Restrisiko beherrschbar?'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                TextField(
                  controller: linkedComplaintsCtrl,
                  decoration: const InputDecoration(labelText: 'Verknüpfte Reklamations-Tickets (Komma-getrennt)'),
                ),
                TextField(
                  controller: linkedCapasCtrl,
                  decoration: const InputDecoration(labelText: 'Verknüpfte CAPA/8D-IDs (Komma-getrennt)'),
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
                  linkedComplaints: linkedComplaintsCtrl.text
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList(),
                  linkedCapas: linkedCapasCtrl.text
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList(),
                ),
              );
            },
            child: const Text('Speichern'),
          ),
        ],
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
    linkedComplaintsCtrl.dispose();
    linkedCapasCtrl.dispose();
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
