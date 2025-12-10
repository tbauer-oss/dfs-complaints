import 'package:flutter/material.dart';
import '../api/client.dart';
import '../models/capa_report.dart';
import '../widgets/empty_state.dart';
import 'capa_detail_page.dart';

class CapaOverviewPage extends StatefulWidget {
  final ApiClient api;
  final bool canWrite;
  const CapaOverviewPage({super.key, required this.api, this.canWrite = false});

  @override
  State<CapaOverviewPage> createState() => _CapaOverviewPageState();
}

class _CapaOverviewPageState extends State<CapaOverviewPage> {
  bool _loading = false;
  String? _error;
  List<CapaReport> _reports = const [];
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
      final list = await widget.api.adminCapas();
      setState(() => _reports = list);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  List<CapaReport> get _filtered {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return _reports;
    return _reports.where((c) {
      bool contains(String? v) => (v ?? '').toLowerCase().contains(query);
      return contains(c.capaNumber) ||
          contains(c.title) ||
          contains(c.responsibleUserId) ||
          contains(c.complaintId) ||
          contains(c.sections.problem);
    }).toList();
  }

  Map<String, int> get _stats {
    final open = _reports.where((c) => c.status == 'open').length;
    final closed = _reports.where((c) => c.status == 'closed').length;
    final linked = _reports.where((c) => c.complaintId.isNotEmpty).length;
    final recent = _reports
        .where((c) => DateTime.now().difference(c.createdAt).inDays <= 30)
        .length;
    return {
      'open': open,
      'closed': closed,
      'linked': linked,
      'recent': recent,
    };
  }

  void _openEditor([CapaReport? report]) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CapaDetailPage(
        api: widget.api,
        canWrite: widget.canWrite,
        initialReport: report,
      ),
    ));
    _load();
  }

  Future<void> _confirmDelete(CapaReport report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CAPA löschen'),
        content: Text('Soll die CAPA ${report.effectiveNumber.isEmpty ? report.id : report.effectiveNumber} wirklich gelöscht werden?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Löschen')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deletingId = report.id);
    try {
      await widget.api.adminDeleteCapa(report.id);
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

  DataRow _row(CapaReport report) {
    final theme = Theme.of(context);
    return DataRow(
      cells: [
        DataCell(Text(report.effectiveNumber.isEmpty ? '—' : report.effectiveNumber)),
        DataCell(Text(report.title.isEmpty ? '—' : report.title)),
        DataCell(Text(report.status)),
        DataCell(Text(report.responsibleUserId.isEmpty ? '—' : report.responsibleUserId)),
        DataCell(Text(report.createdAt.toLocal().toIso8601String().substring(0, 10))),
        DataCell(Text(report.complaintId.isEmpty ? '—' : report.complaintId)),
        if (widget.canWrite)
          DataCell(
            IconButton(
              icon: _deletingId == report.id
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.delete_outline),
              onPressed: _deletingId == null ? () => _confirmDelete(report) : null,
              tooltip: 'CAPA löschen',
            ),
          ),
      ],
      onSelectChanged: (_) => _openEditor(report),
      color: MaterialStateProperty.resolveWith((states) {
        if (report.status == 'closed') return theme.colorScheme.surfaceVariant.withOpacity(.3);
        if (report.status == 'inProgress') return theme.colorScheme.primaryContainer.withOpacity(.25);
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
                    Text('CAPA / 8D-Reports', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('Corrective and Preventive Actions', style: TextStyle(fontSize: 16)),
                  ],
                ),
              ),
              if (widget.canWrite)
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Neue CAPA / 8D anlegen'),
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
              _kpiTile(label: 'Mit Reklamation', value: _stats['linked'].toString(), color: cs.secondary),
              _kpiTile(label: 'Letzte 30 Tage', value: _stats['recent'].toString(), color: cs.primary),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Suchen (CAPA-Nr., Titel, Status)',
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
                : _reports.isEmpty
                    ? const EmptyState(message: 'Keine CAPA-Reports vorhanden')
                    : Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: [
                              const DataColumn(label: Text('CAPA-Nr.')),
                              const DataColumn(label: Text('Titel')),
                              const DataColumn(label: Text('Status')),
                              const DataColumn(label: Text('Verantwortlicher')),
                              const DataColumn(label: Text('Erstellt am')),
                              const DataColumn(label: Text('Reklamation')),
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
