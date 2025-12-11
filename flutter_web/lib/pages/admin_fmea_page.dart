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

  Future<FmeaRiskEntry?> _openRiskDialog({FmeaRiskEntry? existing}) async {
    final catCtrl = TextEditingController(text: existing?.category ?? '');
    final hazardCtrl = TextEditingController(text: existing?.hazard ?? '');
    final situationCtrl = TextEditingController(text: existing?.hazardSituation ?? '');
    final harmCtrl = TextEditingController(text: existing?.harm ?? '');
    final causeCtrl = TextEditingController(text: existing?.causes ?? '');
    final proposedCtrl = TextEditingController(text: existing?.proposedAction ?? '');
    int? severity = existing?.severity;
    int? occurrence = existing?.occurrence;

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
                TextField(
                  controller: proposedCtrl,
                  decoration: const InputDecoration(labelText: 'Vorgeschlagene Maßnahme'),
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
                  severity: severity,
                  occurrence: occurrence,
                  proposedAction: proposedCtrl.text.trim(),
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
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildHeaderForm(),
                            const SizedBox(height: 12),
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
                                const SizedBox(width: 8),
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
