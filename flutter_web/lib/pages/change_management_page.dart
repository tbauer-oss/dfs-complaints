import 'package:flutter/material.dart';
import '../api/client.dart';
import '../models/change_management.dart';
import '../widgets/date_field.dart';
import '../widgets/empty_state.dart';

class ChangeManagementOverviewPage extends StatefulWidget {
  final ApiClient api;
  final bool canWrite;
  const ChangeManagementOverviewPage({super.key, required this.api, this.canWrite = false});

  @override
  State<ChangeManagementOverviewPage> createState() => _ChangeManagementOverviewPageState();
}

class _ChangeManagementOverviewPageState extends State<ChangeManagementOverviewPage> {
  bool _loading = false;
  String? _error;
  List<ChangeManagementRecord> _records = const [];
  String _search = '';
  String? _deletingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.api.adminChanges();
      setState(() => _records = list);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  List<ChangeManagementRecord> get _filtered {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return _records;
    return _records.where((c) {
      bool contains(String? v) => (v ?? '').toLowerCase().contains(query);
      return contains(c.changeId) ||
          contains(c.title) ||
          contains(c.initiator) ||
          contains(c.status) ||
          contains(c.changeType);
    }).toList();
  }

  Map<String, int> get _stats {
    final open = _records.where((c) => c.status == 'open').length;
    final closed = _records.where((c) => c.status == 'closed').length;
    final escalated = _records
        .where((c) => c.furtherAnalysis == 'yes' || c.decision == 'furtherEvaluation')
        .length;
    return {
      'open': open,
      'closed': closed,
      'escalated': escalated,
      'total': _records.length,
    };
  }

  void _openEditor([ChangeManagementRecord? record]) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChangeManagementDetailPage(
        api: widget.api,
        canWrite: widget.canWrite,
        initialRecord: record ?? const ChangeManagementRecord(),
      ),
    ));
    _load();
  }

  Future<void> _confirmDelete(ChangeManagementRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change löschen'),
        content: Text('Soll der Change ${record.changeId.isEmpty ? record.id : record.changeId} wirklich gelöscht werden?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Löschen')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deletingId = record.id);
    try {
      await widget.api.adminDeleteChange(record.id);
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _deletingId = null);
    }
  }

  Widget _kpiTile({required String label, required String value, Color? color}) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Text(value, style: theme.textTheme.headlineSmall?.copyWith(color: color ?? theme.colorScheme.primary)),
          ],
        ),
      ),
    );
  }

  DataRow _row(ChangeManagementRecord record) {
    final theme = Theme.of(context);
    return DataRow(
      cells: [
        DataCell(Text(record.changeId.isEmpty ? '—' : record.changeId)),
        DataCell(Text(record.title.isEmpty ? '—' : record.title)),
        DataCell(Text(_statusLabel(record.status))),
        DataCell(Text(_typeLabel(record.changeType))),
        DataCell(Text(record.initiator.isEmpty ? '—' : record.initiator)),
        DataCell(Text(record.createdAt == null ? '—' : _formatDate(record.createdAt!))),
        DataCell(Text(record.furtherAnalysis == 'yes' || record.decision == 'furtherEvaluation' ? 'Ja' : 'Nein')),
        if (widget.canWrite)
          DataCell(
            IconButton(
              icon: _deletingId == record.id
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.delete_outline),
              onPressed: _deletingId == null ? () => _confirmDelete(record) : null,
              tooltip: 'Change löschen',
            ),
          ),
      ],
      onSelectChanged: (_) => _openEditor(record),
      color: MaterialStateProperty.resolveWith((states) {
        if (record.status == 'closed') return theme.colorScheme.surfaceVariant.withOpacity(.3);
        if (record.status == 'inProgress') return theme.colorScheme.primaryContainer.withOpacity(.25);
        return null;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Change Management', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('Change Control für kontrollierte Änderungen', style: TextStyle(fontSize: 16)),
                  ],
                ),
              ),
              if (widget.canWrite)
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Neuen Change anlegen'),
                  onPressed: _loading ? null : () => _openEditor(),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _kpiTile(label: 'Offen', value: _stats['open'].toString()),
              _kpiTile(label: 'Abgeschlossen', value: _stats['closed'].toString(), color: cs.tertiary),
              _kpiTile(label: 'Eskalationen', value: _stats['escalated'].toString(), color: cs.error),
              _kpiTile(label: 'Gesamt', value: _stats['total'].toString(), color: cs.secondary),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Suchen (Change-ID, Titel, Initiator)',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _records.isEmpty
                    ? const EmptyState(message: 'Keine Change-Records vorhanden')
                    : Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: [
                              const DataColumn(label: Text('Change-ID')),
                              const DataColumn(label: Text('Titel')),
                              const DataColumn(label: Text('Status')),
                              const DataColumn(label: Text('Art')),
                              const DataColumn(label: Text('Initiator')),
                              const DataColumn(label: Text('Erfasst am')),
                              const DataColumn(label: Text('Eskalation')),
                              if (widget.canWrite) const DataColumn(label: Text('Aktionen')),
                            ],
                            rows: _filtered.map(_row).toList(),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class ChangeManagementDetailPage extends StatefulWidget {
  final ApiClient api;
  final bool canWrite;
  final ChangeManagementRecord initialRecord;
  const ChangeManagementDetailPage({
    super.key,
    required this.api,
    required this.canWrite,
    required this.initialRecord,
  });

  @override
  State<ChangeManagementDetailPage> createState() => _ChangeManagementDetailPageState();
}

class _ChangeManagementDetailPageState extends State<ChangeManagementDetailPage> {
  bool _saving = false;
  String? _error;
  late ChangeManagementRecord _record;

  static const Map<String, String> _typeLabels = {
    'process': 'Prozess',
    'document': 'Dokument',
    'product': 'Produkt',
    'system': 'System / Organisation',
    'other': 'Sonstiges',
  };

  static const Map<String, String> _safetyLabels = {
    'none': 'Keine Sicherheitsrelevanz festgestellt',
    'potential': 'Potenziell sicherheitsrelevant',
  };

  static const Map<String, String> _riskLabels = {
    'none': 'Keine',
    'increased': 'Erhöht',
  };

  static const Map<String, String> _analysisLabels = {
    'no': 'Nein',
    'yes': 'Ja → Eskalation erforderlich',
  };

  static const Map<String, String> _decisionLabels = {
    'approved': 'Änderung freigegeben',
    'approvedWithConditions': 'Änderung freigegeben mit Auflagen',
    'furtherEvaluation': 'Weiterführende Bewertung erforderlich',
  };

  static const Map<String, String> _statusLabels = {
    'open': 'Offen',
    'inProgress': 'In Umsetzung',
    'closed': 'Abgeschlossen',
  };

  static const List<String> _documentOptions = ['SOP', 'AA', 'WI', 'TD'];
  static const List<String> _processOptions = ['QM', 'Produktion', 'Logistik', 'Vertrieb', 'IT', 'Sonstiges'];
  static const Map<String, String> _triggerLabels = {
    'audit': 'Audit-Feststellung',
    'complaint': 'Reklamation',
    'capa': 'CAPA',
    'management': 'Managemententscheidung',
    'regulatory': 'Gesetzliche / normative Änderung',
  };

  @override
  void initState() {
    super.initState();
    _record = widget.initialRecord;
  }

  Future<void> _save() async {
    final errors = _validate();
    if (errors.isNotEmpty) {
      setState(() => _error = errors.join('\n'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = _record.id.isEmpty
          ? await widget.api.adminSaveChange(_record)
          : await widget.api.adminUpdateChange(_record);
      if (!mounted) return;
      setState(() => _record = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Change gespeichert.')),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<String> _validate() {
    final errors = <String>[];
    if (_record.title.trim().isEmpty) errors.add('Titel ist erforderlich.');
    if (_record.description.trim().isEmpty) errors.add('Beschreibung ist erforderlich.');
    if (_record.justification.trim().isEmpty) errors.add('Begründung ist erforderlich.');
    if (_record.changeType.trim().isEmpty) errors.add('Art der Änderung ist erforderlich.');
    if (_record.furtherAnalysis == 'yes') {
      if (_record.decision != 'furtherEvaluation') {
        errors.add('Bei „weiterführender Analyse“ muss die Entscheidung auf „Weiterführende Bewertung erforderlich“ stehen.');
      }
      if (_record.followUps.isEmpty) {
        errors.add('Bei „weiterführender Analyse“ sind Folgeprozesse auszuwählen.');
      }
    }
    if (_record.decision == 'furtherEvaluation' && _record.followUps.isEmpty) {
      errors.add('Bei „Weiterführende Bewertung erforderlich“ sind Folgeprozesse auszuwählen.');
    }
    if (_record.status != 'open') {
      if (_record.implementationOwner.trim().isEmpty) errors.add('Verantwortlicher für Umsetzung ist erforderlich.');
      if (_record.plannedDate == null) errors.add('Geplantes Umsetzungsdatum ist erforderlich.');
    }
    if (_record.status == 'closed') {
      if (_record.implementedAt == null) errors.add('Umsetzungsdatum ist erforderlich.');
      if (!_record.implemented) errors.add('Änderung muss als umgesetzt bestätigt sein.');
    }
    return errors;
  }

  Widget _sectionHeader(String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  Widget _cardNotice({required IconData icon, required String title, required String text, Color? color}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (color ?? cs.primaryContainer).withOpacity(.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (color ?? cs.primary).withOpacity(.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color ?? cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(text),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required Map<String, String> items,
    required ValueChanged<String?> onChanged,
    bool requiredField = false,
    bool enabled = true,
  }) {
    return DropdownButtonFormField<String>(
      value: items.containsKey(value) ? value : null,
      decoration: InputDecoration(
        labelText: requiredField ? '$label *' : label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: items.entries
          .map((entry) => DropdownMenuItem<String>(
                value: entry.key,
                child: Text(entry.value),
              ))
          .toList(),
      onChanged: enabled ? onChanged : null,
    );
  }

  Widget _chipGroup({
    required String label,
    required List<String> options,
    required List<String> selected,
    required ValueChanged<List<String>> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((opt) {
            final isSelected = selected.contains(opt);
            return FilterChip(
              label: Text(opt),
              selected: isSelected,
              onSelected: widget.canWrite
                  ? (value) {
                      final next = [...selected];
                      if (value) {
                        if (!next.contains(opt)) next.add(opt);
                      } else {
                        next.remove(opt);
                      }
                      onChanged(next);
                    }
                  : null,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _auditRow(String label, String value) {
    return Row(
      children: [
        SizedBox(width: 160, child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
        Expanded(child: Text(value.isEmpty ? '—' : value)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shouldWarnSafety = _record.changeType == 'product' && _record.safetyRelevance == 'potential';
    final hasTd = _record.affectedDocuments.contains('TD');
    final requiresEscalation = _record.furtherAnalysis == 'yes' || _record.decision == 'furtherEvaluation';

    return Scaffold(
      appBar: AppBar(
        title: Text(_record.changeId.isEmpty ? 'Neuer Change' : 'Change ${_record.changeId}'),
        actions: [
          if (widget.canWrite)
            TextButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Speichern'),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardNotice(
              icon: Icons.info_outline,
              title: 'Bewusste Abgrenzung',
              text:
                  'Das Change Management dient der kontrollierten Bewertung von Änderungen. Bei sicherheitsrelevanten oder komplexen Sachverhalten sind CAPA, FMEA und PRRC-Verfahren anzuwenden.',
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: cs.error)),
              ),
            _sectionHeader('1) Änderung erfassen', subtitle: 'Pflichtfelder sind mit * markiert.'),
            Wrap(
              runSpacing: 12,
              spacing: 12,
              children: [
                SizedBox(
                  width: 260,
                  child: TextFormField(
                    initialValue: _record.changeId,
                    decoration: const InputDecoration(
                      labelText: 'Change-ID',
                      hintText: 'wird automatisch generiert',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    readOnly: true,
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: TextFormField(
                    initialValue: _record.initiator,
                    decoration: const InputDecoration(
                      labelText: 'Initiator',
                      hintText: 'wird automatisch gesetzt',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    readOnly: true,
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: TextFormField(
                    initialValue: _record.createdAt == null ? '' : _formatDate(_record.createdAt!),
                    decoration: const InputDecoration(
                      labelText: 'Datum der Erfassung',
                      hintText: 'wird automatisch gesetzt',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    readOnly: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _record.title,
              decoration: const InputDecoration(
                labelText: 'Titel der Änderung *',
                border: OutlineInputBorder(),
              ),
              enabled: widget.canWrite,
              onChanged: (v) => setState(() => _record = _record.copyWith(title: v)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _record.description,
              decoration: const InputDecoration(
                labelText: 'Beschreibung: Was ändert sich konkret? *',
                border: OutlineInputBorder(),
              ),
              enabled: widget.canWrite,
              minLines: 2,
              maxLines: 4,
              onChanged: (v) => setState(() => _record = _record.copyWith(description: v)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _record.justification,
              decoration: const InputDecoration(
                labelText: 'Begründung: Warum ist die Änderung erforderlich? *',
                border: OutlineInputBorder(),
              ),
              enabled: widget.canWrite,
              minLines: 2,
              maxLines: 4,
              onChanged: (v) => setState(() => _record = _record.copyWith(justification: v)),
            ),
            const SizedBox(height: 12),
            _dropdown(
              label: 'Art der Änderung',
              value: _record.changeType,
              items: _typeLabels,
              requiredField: true,
              enabled: widget.canWrite,
              onChanged: (v) => setState(() => _record = _record.copyWith(changeType: v ?? 'other')),
            ),
            const SizedBox(height: 16),
            _sectionHeader('Optionale Referenzen'),
            _chipGroup(
              label: 'Betroffene Dokumente',
              options: _documentOptions,
              selected: _record.affectedDocuments,
              onChanged: (list) => setState(() => _record = _record.copyWith(affectedDocuments: list)),
            ),
            const SizedBox(height: 12),
            _chipGroup(
              label: 'Betroffene Prozesse',
              options: _processOptions,
              selected: _record.affectedProcesses,
              onChanged: (list) => setState(() => _record = _record.copyWith(affectedProcesses: list)),
            ),
            const SizedBox(height: 12),
            _dropdown(
              label: 'Auslöser',
              value: _record.trigger,
              items: _triggerLabels,
              enabled: widget.canWrite,
              onChanged: (v) => setState(() => _record = _record.copyWith(trigger: v ?? '')),
            ),
            if (hasTd)
              _cardNotice(
                icon: Icons.description_outlined,
                title: 'MDR-Hinweis',
                text: 'Auswirkung auf MDR-Technische Dokumentation prüfen.',
                color: cs.secondary,
              ),
            _sectionHeader('2) Bewertung (risikobasiert, strukturiert)'),
            Wrap(
              runSpacing: 12,
              spacing: 12,
              children: [
                SizedBox(
                  width: 320,
                  child: _dropdown(
                    label: 'Einfluss auf Produkt',
                    value: _record.productImpact,
                    items: {
                      'none': 'Nein',
                      'low': 'Ja (gering)',
                      'relevant': 'Ja (relevant)',
                    },
                    enabled: widget.canWrite,
                    onChanged: (v) => setState(() => _record = _record.copyWith(productImpact: v ?? 'none')),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: _dropdown(
                    label: 'Einfluss auf Dokumentation',
                    value: _record.documentationImpact,
                    items: {
                      'none': 'Nein',
                      'editorial': 'Redaktionell',
                      'content': 'Inhaltlich',
                    },
                    enabled: widget.canWrite,
                    onChanged: (v) => setState(() => _record = _record.copyWith(documentationImpact: v ?? 'none')),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: _dropdown(
                    label: 'Einfluss auf Prozesse',
                    value: _record.processImpact,
                    items: {
                      'none': 'Nein',
                      'yes': 'Ja',
                    },
                    enabled: widget.canWrite,
                    onChanged: (v) => setState(() => _record = _record.copyWith(processImpact: v ?? 'none')),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: _dropdown(
                    label: 'Einfluss auf regulatorische Konformität',
                    value: _record.regulatoryImpact,
                    items: {
                      'none': 'Nein',
                      'yes': 'Ja (MDR / ISO / Kunde)',
                    },
                    enabled: widget.canWrite,
                    onChanged: (v) => setState(() => _record = _record.copyWith(regulatoryImpact: v ?? 'none')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              runSpacing: 12,
              spacing: 12,
              children: [
                SizedBox(
                  width: 420,
                  child: _dropdown(
                    label: 'Sicherheitsrelevanz',
                    value: _record.safetyRelevance,
                    items: _safetyLabels,
                    enabled: widget.canWrite,
                    onChanged: (v) => setState(() => _record = _record.copyWith(safetyRelevance: v ?? 'none')),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: _dropdown(
                    label: 'Risikoänderung gegenüber Bestand',
                    value: _record.riskChange,
                    items: _riskLabels,
                    enabled: widget.canWrite,
                    onChanged: (v) => setState(() => _record = _record.copyWith(riskChange: v ?? 'none')),
                  ),
                ),
                SizedBox(
                  width: 360,
                  child: _dropdown(
                    label: 'Bedarf an weiterführender Analyse',
                    value: _record.furtherAnalysis,
                    items: _analysisLabels,
                    enabled: widget.canWrite,
                    onChanged: (v) {
                      final next = v ?? 'no';
                      final nextDecision = next == 'yes' ? 'furtherEvaluation' : _record.decision;
                      setState(() => _record = _record.copyWith(furtherAnalysis: next, decision: nextDecision));
                    },
                  ),
                ),
              ],
            ),
            if (shouldWarnSafety)
              _cardNotice(
                icon: Icons.warning_amber_rounded,
                title: 'Sicherheitsrelevanz prüfen',
                text: 'Diese Änderung kann sicherheitsrelevant sein – PRRC-/FMEA-Bewertung prüfen.',
                color: cs.error,
              ),
            _sectionHeader('3) Entscheidung'),
            _dropdown(
              label: 'Entscheidung',
              value: _record.decision,
              items: _decisionLabels,
              enabled: widget.canWrite && _record.furtherAnalysis != 'yes',
              requiredField: true,
              onChanged: (v) => setState(() => _record = _record.copyWith(decision: v ?? '')),
            ),
            const SizedBox(height: 12),
            Text('Folgeaktivität bei weiterführender Bewertung', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _followUpCheckbox('prrc', 'PRRC-Bewertung erforderlich'),
                _followUpCheckbox('fmea', 'FMEA-Anpassung erforderlich'),
                _followUpCheckbox('capa', 'CAPA anlegen'),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _record.followUpLink,
              decoration: const InputDecoration(
                labelText: 'Verknüpfung zur Folgeaktivität (ID + Status)',
                border: OutlineInputBorder(),
              ),
              enabled: widget.canWrite,
              onChanged: (v) => setState(() => _record = _record.copyWith(followUpLink: v)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _record.decisionNote,
              decoration: const InputDecoration(
                labelText: 'Hinweistext / Auflagen',
                border: OutlineInputBorder(),
              ),
              enabled: widget.canWrite,
              minLines: 2,
              maxLines: 4,
              onChanged: (v) => setState(() => _record = _record.copyWith(decisionNote: v)),
            ),
            if (requiresEscalation)
              _cardNotice(
                icon: Icons.assignment_turned_in_outlined,
                title: 'Change Management abgeschlossen – Übergabe an Folgeprozess',
                text: 'Die weiterführende Bewertung wird im ausgewählten Folgeprozess dokumentiert.',
                color: cs.primary,
              ),
            _sectionHeader('4) Umsetzung & Abschluss'),
            Wrap(
              runSpacing: 12,
              spacing: 12,
              children: [
                SizedBox(
                  width: 320,
                  child: TextFormField(
                    initialValue: _record.implementationOwner,
                    decoration: const InputDecoration(
                      labelText: 'Verantwortlicher für Umsetzung *',
                      border: OutlineInputBorder(),
                    ),
                    enabled: widget.canWrite,
                    onChanged: (v) => setState(() => _record = _record.copyWith(implementationOwner: v)),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: IgnorePointer(
                    ignoring: !widget.canWrite,
                    child: DateField(
                      label: 'Geplantes Umsetzungsdatum *',
                      value: _record.plannedDate,
                      requiredField: true,
                      onChanged: (v) => setState(() => _record = _record.copyWith(plannedDate: v)),
                    ),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: IgnorePointer(
                    ignoring: !widget.canWrite,
                    child: DateField(
                      label: 'Umsetzung erfolgt am',
                      value: _record.implementedAt,
                      onChanged: (v) => setState(() => _record = _record.copyWith(implementedAt: v)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                CheckboxListTile(
                  value: _record.implemented,
                  onChanged: widget.canWrite ? (v) => setState(() => _record = _record.copyWith(implemented: v ?? false)) : null,
                  title: const Text('Änderung umgesetzt'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  value: _record.documentsUpdated,
                  onChanged: widget.canWrite ? (v) => setState(() => _record = _record.copyWith(documentsUpdated: v ?? false)) : null,
                  title: const Text('Betroffene Dokumente aktualisiert'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _dropdown(
              label: 'Status',
              value: _record.status,
              items: _statusLabels,
              enabled: widget.canWrite,
              onChanged: (v) => setState(() => _record = _record.copyWith(status: v ?? 'open')),
            ),
            _sectionHeader('5) Historie & Audit-Trail'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _auditRow('Initiator', _record.initiator),
                    const SizedBox(height: 8),
                    _auditRow('Bewerter', _record.evaluator),
                    const SizedBox(height: 8),
                    _auditRow('Entscheider', _record.decisionBy),
                    const SizedBox(height: 8),
                    _auditRow('Umsetzung', _record.implementationBy),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_record.history.isEmpty)
              const EmptyState(message: 'Noch keine Historie vorhanden')
            else
              Card(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _record.history.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final entry = _record.history[idx];
                    final fields = entry.fields.isNotEmpty ? ' (${entry.fields.join(', ')})' : '';
                    final timestamp = entry.at == null ? '—' : _formatDateTime(entry.at!);
                    return ListTile(
                      leading: const Icon(Icons.history),
                      title: Text('${_historyLabel(entry.action)}$fields'),
                      subtitle: Text('${entry.actor.isEmpty ? '—' : entry.actor} · $timestamp'),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: widget.canWrite
          ? Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Speichern'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Zurück'),
                  ),
                  if (_saving) ...[
                    const SizedBox(width: 12),
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ],
              ),
            )
          : null,
    );
  }

  Widget _followUpCheckbox(String key, String label) {
    final selected = _record.followUps.contains(key);
    return SizedBox(
      width: 280,
      child: CheckboxListTile(
        value: selected,
        onChanged: widget.canWrite
            ? (v) {
                final next = [..._record.followUps];
                if (v == true && !next.contains(key)) next.add(key);
                if (v != true && next.contains(key)) next.remove(key);
                setState(() => _record = _record.copyWith(followUps: next));
              }
            : null,
        title: Text(label),
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }

  String _historyLabel(String action) {
    switch (action) {
      case 'created':
        return 'Erstellung';
      case 'assessment':
        return 'Bewertung';
      case 'decision':
        return 'Entscheidung';
      case 'implementation':
        return 'Umsetzung';
      case 'status':
        return 'Statuswechsel';
      default:
        return action;
    }
  }
}

String _statusLabel(String value) {
  switch (value) {
    case 'open':
      return 'Offen';
    case 'inProgress':
      return 'In Umsetzung';
    case 'closed':
      return 'Abgeschlossen';
    default:
      return value.isEmpty ? '—' : value;
  }
}

String _typeLabel(String value) {
  switch (value) {
    case 'process':
      return 'Prozess';
    case 'document':
      return 'Dokument';
    case 'product':
      return 'Produkt';
    case 'system':
      return 'System / Organisation';
    case 'other':
      return 'Sonstiges';
    default:
      return value.isEmpty ? '—' : value;
  }
}

String _formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _formatDateTime(DateTime date) {
  final d = _formatDate(date);
  final h = date.hour.toString().padLeft(2, '0');
  final m = date.minute.toString().padLeft(2, '0');
  return '$d $h:$m';
}
