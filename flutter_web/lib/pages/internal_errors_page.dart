import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/internal_error_model.dart';
import '../services/internal_error_service.dart';
import 'internal_error_detail.dart';

class InternalErrorsPage extends StatefulWidget {
  final InternalErrorService service;
  final bool canWrite;
  final bool canOverrideCapa;
  final String? currentUser;

  const InternalErrorsPage({
    super.key,
    required this.service,
    required this.canWrite,
    required this.canOverrideCapa,
    this.currentUser,
  });

  @override
  State<InternalErrorsPage> createState() => _InternalErrorsPageState();
}

class _InternalErrorsPageState extends State<InternalErrorsPage> {
  late Future<List<InternalError>> _future;
  String _search = '';
  String _statusFilter = 'all';
  String _escalationFilter = 'all';
  String _capaFilter = 'all';
  int? _yearFilter;
  _SortOption _sortOption = _SortOption.dateDesc;

  @override
  void initState() {
    super.initState();
    _future = widget.service.fetchAll();
  }

  void _refresh() {
    setState(() {
      _future = widget.service.fetchAll();
    });
  }

  List<InternalError> _filtered(List<InternalError> entries) {
    var list = entries;
    final query = _search.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((e) {
        bool contains(String? value) => (value ?? '').toLowerCase().contains(query);
        return contains(e.errorCode) ||
            contains(e.description) ||
            contains(e.processArea) ||
            contains(e.responsiblePerson);
      }).toList();
    }
    if (_statusFilter != 'all') {
      list = list.where((e) => e.status == _statusFilter).toList();
    }
    if (_escalationFilter != 'all') {
      list = list.where((e) => e.escalation == _escalationFilter).toList();
    }
    if (_capaFilter != 'all') {
      list = list
          .where((e) => _capaFilter == 'required' ? e.capaRequired : !e.capaRequired)
          .toList();
    }
    if (_yearFilter != null) {
      list = list.where((e) => e.year == _yearFilter).toList();
    }
    list.sort((a, b) {
      switch (_sortOption) {
        case _SortOption.dateAsc:
          return a.createdAt.compareTo(b.createdAt);
        case _SortOption.dateDesc:
          return b.createdAt.compareTo(a.createdAt);
        case _SortOption.pointsAsc:
          return a.points.compareTo(b.points);
        case _SortOption.pointsDesc:
          return b.points.compareTo(a.points);
      }
    });
    return list;
  }

  Future<void> _openEditor([InternalError? entry]) async {
    final saved = await Navigator.of(context).push<InternalError>(
      MaterialPageRoute(
        builder: (_) => InternalErrorDetailPage(
          service: widget.service,
          initialError: entry,
          canWrite: widget.canWrite,
          canOverrideCapa: widget.canOverrideCapa,
          currentUser: widget.currentUser,
        ),
      ),
    );
    if (saved != null) {
      _refresh();
    }
  }

  _EscalationColors _escalationColors(String escalation, ColorScheme cs) {
    switch (escalation) {
      case 'B':
        return _EscalationColors(
          background: cs.tertiaryContainer,
          foreground: cs.onTertiaryContainer,
          border: cs.tertiary.withOpacity(0.6),
        );
      case 'C':
        return _EscalationColors(
          background: cs.errorContainer,
          foreground: cs.onErrorContainer,
          border: cs.error.withOpacity(0.6),
        );
      case 'D':
        return _EscalationColors(
          background: Color.alphaBlend(cs.error.withOpacity(0.22), cs.surface),
          foreground: cs.error,
          border: cs.error,
        );
      case 'A':
      default:
        return _EscalationColors(
          background: cs.secondaryContainer,
          foreground: cs.onSecondaryContainer,
          border: cs.secondary.withOpacity(0.6),
        );
    }
  }

  Widget _buildBadge(String value) {
    final theme = Theme.of(context);
    final colors = _escalationColors(value, theme.colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        value,
        style: theme.textTheme.labelMedium?.copyWith(
          color: colors.foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildLoadingState(TextTheme textTheme, ColorScheme cs) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                'Daten werden geladen…',
                style: textTheme.bodyMedium?.copyWith(color: cs.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(
    TextTheme textTheme,
    ColorScheme cs,
    Object error,
  ) {
    final message = error.toString().split('\n').first;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: cs.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Fehler beim Laden',
                    style: textTheme.titleMedium?.copyWith(color: cs.onSurface),
                  ),
                ),
                TextButton(onPressed: _refresh, child: const Text('Neu laden')),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(TextTheme textTheme, ColorScheme cs) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Keine internen Fehler erfasst', style: textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Legen Sie einen neuen Fehler an oder passen Sie die Filter an.',
              style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (widget.canWrite) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add),
                label: const Text('Neuen Fehler erfassen'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTable(List<InternalError> entries, ColorScheme cs, DateFormat dateFormatter) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 18,
          headingRowHeight: 48,
          dataRowMinHeight: 56,
          dataRowMaxHeight: 72,
          columns: const [
            DataColumn(label: Text('Fehlercode')),
            DataColumn(label: Text('Datum')),
            DataColumn(label: Text('Bereich/Prozess')),
            DataColumn(label: Text('Kurzbeschreibung')),
            DataColumn(label: Text('Punkte')),
            DataColumn(label: Text('Eskalation')),
            DataColumn(label: Text('CAPA')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Verantwortlich')),
            DataColumn(label: Text('Aktionen')),
          ],
          rows: entries.map((entry) {
            return DataRow(
              cells: [
                DataCell(Text(entry.errorCode.isEmpty ? '–' : entry.errorCode)),
                DataCell(Text(dateFormatter.format(entry.createdAt))),
                DataCell(Text(entry.processArea.isEmpty ? '–' : entry.processArea)),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Text(
                      entry.description,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
                DataCell(Text(entry.points.toString())),
                DataCell(_buildBadge(entry.escalation)),
                DataCell(
                  Icon(
                    entry.capaRequired
                        ? Icons.assignment_turned_in_outlined
                        : Icons.remove_circle_outline,
                    color: entry.capaRequired ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
                DataCell(Text(entry.status)),
                DataCell(Text(entry.responsiblePerson.isEmpty ? '–' : entry.responsiblePerson)),
                DataCell(
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Details anzeigen',
                        icon: const Icon(Icons.visibility_outlined),
                        onPressed: () => _openEditor(entry),
                      ),
                      if (widget.canWrite)
                        IconButton(
                          tooltip: 'Bearbeiten',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _openEditor(entry),
                        ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dateFormatter = DateFormat('dd.MM.yyyy');

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primaryContainer.withOpacity(theme.brightness == Brightness.dark ? 0.12 : 0.28),
            cs.surface,
            cs.surfaceVariant.withOpacity(0.2),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                          'Interne Fehlererfassung',
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Interne Fehler gemäß AA852 erfassen, bewerten und nachverfolgen.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface.withOpacity(0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Neu laden'),
                      ),
                      const SizedBox(width: 8),
                      if (widget.canWrite)
                        FilledButton.icon(
                          onPressed: () => _openEditor(),
                          icon: const Icon(Icons.add),
                          label: const Text('Neuer Fehler'),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: FutureBuilder<List<InternalError>>(
                  future: _future,
                  builder: (context, snapshot) {
                    final entries = snapshot.data ?? const <InternalError>[];
                    final filtered = _filtered(entries);
                    final years = entries.map((e) => e.year).toSet().toList()..sort();

                    return ListView(
                      children: [
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SizedBox(
                                  width: 260,
                                  child: TextField(
                                    decoration: const InputDecoration(
                                      labelText: 'Suche',
                                      hintText: 'Code, Text, Verantwortliche',
                                      prefixIcon: Icon(Icons.search),
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    onChanged: (value) => setState(() => _search = value),
                                  ),
                                ),
                                _FilterDropdown(
                                  label: 'Status',
                                  value: _statusFilter,
                                  items: const [
                                    DropdownMenuItem(value: 'all', child: Text('Alle Status')),
                                    DropdownMenuItem(value: 'Draft', child: Text('Draft')),
                                    DropdownMenuItem(value: 'Open', child: Text('Open')),
                                    DropdownMenuItem(value: 'In Progress', child: Text('In Progress')),
                                    DropdownMenuItem(value: 'Waiting Effectiveness', child: Text('Waiting Effectiveness')),
                                    DropdownMenuItem(value: 'Closed', child: Text('Closed')),
                                  ],
                                  onChanged: (value) => setState(() => _statusFilter = value ?? 'all'),
                                ),
                                _FilterDropdown(
                                  label: 'Eskalation',
                                  value: _escalationFilter,
                                  items: const [
                                    DropdownMenuItem(value: 'all', child: Text('Alle Stufen')),
                                    DropdownMenuItem(value: 'A', child: Text('A – niedrig')),
                                    DropdownMenuItem(value: 'B', child: Text('B – mittel')),
                                    DropdownMenuItem(value: 'C', child: Text('C – hoch')),
                                    DropdownMenuItem(value: 'D', child: Text('D – sehr hoch')),
                                  ],
                                  onChanged: (value) => setState(() => _escalationFilter = value ?? 'all'),
                                ),
                                _FilterDropdown(
                                  label: 'CAPA',
                                  value: _capaFilter,
                                  items: const [
                                    DropdownMenuItem(value: 'all', child: Text('Alle')),
                                    DropdownMenuItem(value: 'required', child: Text('CAPA erforderlich')),
                                    DropdownMenuItem(value: 'none', child: Text('Keine CAPA')),
                                  ],
                                  onChanged: (value) => setState(() => _capaFilter = value ?? 'all'),
                                ),
                                _FilterDropdown<int?>(
                                  label: 'Jahr',
                                  value: _yearFilter,
                                  items: [
                                    const DropdownMenuItem(value: null, child: Text('Alle Jahre')),
                                    ...years.map(
                                      (year) => DropdownMenuItem(value: year, child: Text(year.toString())),
                                    ),
                                  ],
                                  onChanged: (value) => setState(() => _yearFilter = value),
                                ),
                                _FilterDropdown(
                                  label: 'Sortierung',
                                  value: _sortOption.name,
                                  items: const [
                                    DropdownMenuItem(value: 'dateDesc', child: Text('Datum (neu zuerst)')),
                                    DropdownMenuItem(value: 'dateAsc', child: Text('Datum (alt zuerst)')),
                                    DropdownMenuItem(value: 'pointsDesc', child: Text('Punkte (hoch)')),
                                    DropdownMenuItem(value: 'pointsAsc', child: Text('Punkte (niedrig)')),
                                  ],
                                  onChanged: (value) {
                                    final option = _SortOption.values
                                        .firstWhere((e) => e.name == value, orElse: () => _sortOption);
                                    setState(() => _sortOption = option);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (snapshot.connectionState == ConnectionState.waiting)
                          _buildLoadingState(theme.textTheme, cs)
                        else if (snapshot.hasError)
                          _buildErrorState(theme.textTheme, cs, snapshot.error!)
                        else if (filtered.isEmpty)
                          _buildEmptyState(theme.textTheme, cs)
                        else
                          _buildTable(filtered, cs, dateFormatter),
                        const SizedBox(height: 12),
                        Text(
                          'Einträge: ${filtered.length} • Gesamt: ${entries.length}',
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SortOption { dateDesc, dateAsc, pointsDesc, pointsAsc }

class _FilterDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: DropdownButtonFormField<T>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

class _EscalationColors {
  final Color background;
  final Color foreground;
  final Color border;

  const _EscalationColors({
    required this.background,
    required this.foreground,
    required this.border,
  });
}
