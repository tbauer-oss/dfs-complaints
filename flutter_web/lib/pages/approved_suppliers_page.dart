import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/client.dart';
import '../models/supplier_evaluation.dart';
import '../utils/app_error_mapper.dart';

class ApprovedSuppliersPage extends StatefulWidget {
  final ApiClient api;
  final bool canWrite;
  final VoidCallback onOpenSupplierEvaluation;
  final ValueChanged<String> onOpenSupplierEvaluationFor;

  const ApprovedSuppliersPage({
    super.key,
    required this.api,
    required this.canWrite,
    required this.onOpenSupplierEvaluation,
    required this.onOpenSupplierEvaluationFor,
  });

  @override
  State<ApprovedSuppliersPage> createState() => _ApprovedSuppliersPageState();
}

class _ApprovedSuppliersPageState extends State<ApprovedSuppliersPage> {
  bool _loading = true;
  String? _error;
  List<ApprovedSupplier> _suppliers = const [];
  String _search = '';
  bool _auditView = false;
  bool _filterOverdue = false;
  bool _filterWithoutEvaluation = false;
  bool _filterCritical = false;
  int _year = DateTime.now().year;
  ApprovedSupplier? _selected;
  SupplierAnnualEvaluation? _selectedEvaluation;
  bool _detailLoading = false;
  bool _savingNote = false;
  final _noteController = TextEditingController();

  int? _sortIndex;
  bool _sortAsc = true;

  final _horizontalHeaderController = ScrollController();
  final _horizontalBodyController = ScrollController();
  final _verticalBodyController = ScrollController();
  final _detailScrollController = ScrollController();

  static const double _supplierWidth = 260;
  static const double _supplierNoWidth = 140;
  static const double _criticalWidth = 110;
  static const double _statusWidth = 200;
  static const double _scoreWidth = 120;
  static const double _yearWidth = 120;
  static const double _evalStatusWidth = 140;
  static const double _lastEvalWidth = 180;
  static const double _nextEvalWidth = 170;
  static const double _auditBasisWidth = 260;
  static const double _decisionWidth = 200;
  static const double _evidenceWidth = 260;
  static const double _actionsWidth = 140;

  double get _tableMinWidth => _auditView ? 1880 : 1600;

  @override
  void initState() {
    super.initState();
    _horizontalBodyController.addListener(_syncHeaderScroll);
    _loadSuppliers();
  }

  @override
  void dispose() {
    _horizontalBodyController.removeListener(_syncHeaderScroll);
    _horizontalBodyController.dispose();
    _horizontalHeaderController.dispose();
    _verticalBodyController.dispose();
    _detailScrollController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _syncHeaderScroll() {
    if (_horizontalHeaderController.hasClients) {
      _horizontalHeaderController.jumpTo(_horizontalBodyController.offset);
    }
  }

  Future<void> _loadSuppliers({bool keepSelection = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.api.adminApprovedSuppliers(year: _year);
      setState(() {
        _suppliers = list;
        _loading = false;
      });
      if (list.isNotEmpty) {
        if (keepSelection && _selected != null) {
          final matched = list.firstWhere(
            (s) => s.supplierId == _selected!.supplierId,
            orElse: () => list.first,
          );
          _selectSupplier(matched);
        } else {
          _selectSupplier(list.first);
        }
      } else {
        setState(() => _selected = null);
      }
    } catch (err) {
      final mapped = AppErrorMapper.map(err);
      setState(() {
        _error = mapped.message.isNotEmpty ? mapped.message : mapped.title;
        _loading = false;
      });
    }
  }

  Future<void> _selectSupplier(ApprovedSupplier supplier) async {
    setState(() {
      _selected = supplier;
      _selectedEvaluation = null;
      _detailLoading = true;
      _noteController.text = supplier.adminNote;
    });
    try {
      final evals = await widget.api.adminSupplierEvaluations(supplierId: supplier.supplierId);
      final selected = _pickEvaluationForSupplier(evals, supplier.evaluationYearUsed);
      setState(() {
        _selectedEvaluation = selected;
        _detailLoading = false;
      });
    } catch (_) {
      setState(() => _detailLoading = false);
    }
  }

  SupplierAnnualEvaluation? _pickEvaluationForSupplier(List<SupplierAnnualEvaluation> evals, int? year) {
    if (evals.isEmpty) return null;
    if (year != null) {
      final matches = evals.where((e) => e.evalYear == year && e.archivedAt == null).toList();
      if (matches.isNotEmpty) {
        return matches.firstWhere(
          (e) => e.status.toLowerCase() == 'final',
          orElse: () => matches.first,
        );
      }
    }
    return evals.firstWhere(
      (e) => e.status.toLowerCase() == 'final',
      orElse: () => evals.first,
    );
  }

  List<ApprovedSupplier> get _filteredSuppliers {
    final query = _search.trim().toLowerCase();
    final today = DateTime.now();
    return _suppliers.where((supplier) {
      if (query.isNotEmpty) {
        final haystack = '${supplier.name} ${supplier.supplierNo}'.toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      if (_filterCritical && !supplier.isCritical) return false;
      if (_filterWithoutEvaluation && supplier.evaluationState == 'none') return false;
      if (_filterOverdue) {
        if (supplier.nextDueDate == null) return false;
        final due = DateTime.tryParse(supplier.nextDueDate!);
        if (due == null || !due.isBefore(today)) return false;
      }
      return true;
    }).toList();
  }

  int _columnIndex(String key) {
    final columns = _auditView
        ? [
            'name',
            'number',
            'critical',
            'status',
            'score',
            'year',
            'state',
            'lastFinalized',
            'nextDue',
            'auditBasis',
            'decision',
            'evidence',
            'actions',
          ]
        : [
            'name',
            'number',
            'critical',
            'status',
            'score',
            'lastFinalized',
            'nextDue',
            'decision',
            'evidence',
            'actions',
          ];
    return columns.indexOf(key).clamp(0, columns.length - 1);
  }

  void _sortBy<T>(String key, Comparable<T> Function(ApprovedSupplier supplier) getField) {
    final index = _columnIndex(key);
    setState(() {
      if (_sortIndex == index) {
        _sortAsc = !_sortAsc;
      } else {
        _sortIndex = index;
        _sortAsc = true;
      }
      final sorted = [..._suppliers]..sort((a, b) {
          final aValue = getField(a);
          final bValue = getField(b);
          final cmp = Comparable.compare(aValue, bValue);
          return _sortAsc ? cmp : -cmp;
        });
      _suppliers = sorted;
    });
  }

  bool _isOverdue(ApprovedSupplier supplier) {
    if (supplier.nextDueDate == null) return false;
    final due = DateTime.tryParse(supplier.nextDueDate!);
    if (due == null) return false;
    return due.isBefore(DateTime.now());
  }

  Color _statusColor(String? statusClass, ColorScheme cs) {
    switch (statusClass) {
      case 'A':
        return const Color(0xFF2E7D32);
      case 'B':
        return const Color(0xFF1565C0);
      case 'C':
        return const Color(0xFFF9A825);
      case 'D':
        return const Color(0xFFC62828);
      default:
        return cs.outlineVariant;
    }
  }

  String _statusLabel(ApprovedSupplier supplier) {
    if (supplier.evaluationState == 'none') return 'Kein Status';
    return supplier.statusClass ?? '—';
  }

  String _scoreLabel(ApprovedSupplier supplier) {
    if (supplier.score == null) return '—';
    return supplier.score!.toStringAsFixed(2);
  }

  String _trendLabel(ApprovedSupplier supplier) {
    if (supplier.scoreTrend == null) return '';
    final diff = supplier.scoreTrend!;
    final arrow = diff < 0 ? '↓' : (diff > 0 ? '↑' : '→');
    return '$arrow ${diff.abs().toStringAsFixed(2)}';
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '—';
    return DateFormat('dd.MM.yyyy').format(parsed);
  }

  Future<void> _exportCsv(List<ApprovedSupplier> items) async {
    final headers = [
      'Lieferant',
      'Lieferanten-Nr.',
      'Kritisch',
      'Statusklasse',
      'Score',
      'Bewertungsjahr',
      'Status',
      'Entscheidung',
      'Letzte Finalisierung',
    ];
    final buffer = StringBuffer('${headers.join(';')}\n');
    for (final supplier in items) {
      buffer.writeln([
        supplier.name,
        supplier.supplierNo,
        supplier.isCritical ? 'Ja' : 'Nein',
        supplier.statusClass ?? '—',
        supplier.score?.toStringAsFixed(2) ?? '—',
        supplier.evaluationYearUsed?.toString() ?? '—',
        supplier.evaluationState,
        supplier.decisionText,
        _formatDate(supplier.lastFinalizedAt),
      ].map((v) => '"${v.toString().replaceAll('"', '""')}"').join(';'));
    }
    _downloadBytes(Uint8List.fromList(buffer.toString().codeUnits), 'zugelassene_lieferanten.csv', 'text/csv');
  }

  void _downloadBytes(Uint8List bytes, String filename, String mime) {
    final blob = html.Blob([bytes], mime);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)..download = filename;
    anchor.click();
    html.Url.revokeObjectUrl(url);
  }

  Future<void> _recomputeSupplier(ApprovedSupplier supplier) async {
    try {
      final updated = await widget.api.adminRecomputeApprovedSupplier(
        supplierId: supplier.supplierId,
        year: supplier.evaluationYearUsed ?? _year,
      );
      _updateSupplier(updated);
    } catch (err) {
      _showSnack(AppErrorMapper.map(err).title);
    }
  }

  void _updateSupplier(ApprovedSupplier updated) {
    setState(() {
      final idx = _suppliers.indexWhere((s) => s.supplierId == updated.supplierId);
      if (idx != -1) {
        final list = [..._suppliers];
        list[idx] = updated;
        _suppliers = list;
      }
      if (_selected?.supplierId == updated.supplierId) {
        _selected = updated;
        _noteController.text = updated.adminNote;
      }
    });
  }

  Future<void> _saveNote() async {
    final supplier = _selected;
    if (supplier == null) return;
    setState(() => _savingNote = true);
    try {
      final updated = await widget.api.adminRecomputeApprovedSupplier(
        supplierId: supplier.supplierId,
        year: supplier.evaluationYearUsed ?? _year,
        adminNote: _noteController.text.trim(),
      );
      _updateSupplier(updated);
      _showSnack('Notiz gespeichert.');
    } catch (err) {
      _showSnack(AppErrorMapper.map(err).title);
    } finally {
      if (mounted) setState(() => _savingNote = false);
    }
  }

  Future<void> _markReviewed() async {
    final supplier = _selected;
    if (supplier == null) return;
    try {
      final updated = await widget.api.adminRecomputeApprovedSupplier(
        supplierId: supplier.supplierId,
        year: supplier.evaluationYearUsed ?? _year,
        reviewedByPurchasing: true,
      );
      _updateSupplier(updated);
      _showSnack('Review dokumentiert.');
    } catch (err) {
      _showSnack(AppErrorMapper.map(err).title);
    }
  }

  Future<void> _downloadLetter({required String type}) async {
    final supplier = _selected;
    if (supplier == null) return;
    try {
      final bytes = await widget.api.adminSupplierReportPdf(
        supplierId: supplier.supplierId,
        year: supplier.evaluationYearUsed ?? _year,
        type: type,
      );
      final filename = type == 'letter'
          ? 'lieferantenbrief_${supplier.supplierNo}_${supplier.evaluationYearUsed ?? _year}.pdf'
          : 'lieferantenbewertung_${supplier.supplierNo}_${supplier.evaluationYearUsed ?? _year}.pdf';
      _downloadBytes(bytes, filename, 'application/pdf');
    } catch (err) {
      _showSnack(AppErrorMapper.map(err).title);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  List<int> _yearOptions() {
    final now = DateTime.now().year;
    final years = <int>{now, _year};
    for (final supplier in _suppliers) {
      if (supplier.evaluationYearUsed != null) years.add(supplier.evaluationYearUsed!);
    }
    for (int y = now - 3; y <= now + 1; y++) {
      years.add(y);
    }
    final list = years.toList()..sort();
    return list.reversed.toList();
  }

  Widget _statusBadge(ApprovedSupplier supplier, ThemeData theme) {
    final cs = theme.colorScheme;
    final color = _statusColor(supplier.statusClass, cs);
    final label = _statusLabel(supplier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  Widget _criticalBadge(ApprovedSupplier supplier, ThemeData theme) {
    if (!supplier.isCritical) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Kritisch',
        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onErrorContainer),
      ),
    );
  }

  List<DataColumn> _buildColumns(ThemeData theme) {
    final help = Tooltip(
      message:
          'Status basiert auf dokumentierter Lieferantenbewertung gem. ISO 13485, Abschnitt Beschaffung/Lenkung externer Prozesse.',
      child: Icon(Icons.help_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
    );
    final columns = <DataColumn>[
      DataColumn(
        label: SizedBox(
          width: _supplierWidth,
          child: Row(
            children: [
              const Expanded(child: Text('Lieferant', overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              help,
            ],
          ),
        ),
        onSort: (_, __) => _sortBy('name', (s) => s.name.toLowerCase()),
      ),
      DataColumn(
        label: const SizedBox(width: _supplierNoWidth, child: Text('Lieferanten-Nr.')),
        onSort: (_, __) => _sortBy('number', (s) => s.supplierNo.toLowerCase()),
      ),
      const DataColumn(label: SizedBox(width: _criticalWidth, child: Text('Kritisch'))),
      DataColumn(
        label: const SizedBox(width: _statusWidth, child: Text('Statusklasse')),
        onSort: (_, __) => _sortBy('status', (s) => s.statusClass ?? ''),
      ),
      DataColumn(
        numeric: true,
        label: const SizedBox(width: _scoreWidth, child: Text('Score')),
        onSort: (_, __) => _sortBy('score', (s) => s.score ?? 999),
      ),
      DataColumn(
        label: const SizedBox(width: _lastEvalWidth, child: Text('Letzte Jahresbewertung')),
        onSort: (_, __) => _sortBy('lastFinalized', (s) => s.lastFinalizedAt ?? ''),
      ),
      DataColumn(
        label: const SizedBox(width: _nextEvalWidth, child: Text('Nächste Bewertung')),
        onSort: (_, __) => _sortBy('nextDue', (s) => s.nextDueDate ?? ''),
      ),
      DataColumn(
        label: const SizedBox(width: _decisionWidth, child: Text('Entscheidung')),
        onSort: (_, __) => _sortBy('decision', (s) => s.decisionText.toLowerCase()),
      ),
      const DataColumn(label: SizedBox(width: _evidenceWidth, child: Text('Evidenz'))),
      const DataColumn(label: SizedBox(width: _actionsWidth, child: Text('Aktionen'))),
    ];

    if (_auditView) {
      columns.insertAll(5, [
        const DataColumn(label: SizedBox(width: _yearWidth, child: Text('Bewertungsjahr'))),
        const DataColumn(label: SizedBox(width: _evalStatusWidth, child: Text('Status'))),
      ]);
      columns.insert(9, const DataColumn(label: SizedBox(width: _auditBasisWidth, child: Text('Audit-Basis'))));
    }

    return columns;
  }

  Widget _textCell(String value, double width, {int maxLines = 1, TextAlign? align}) {
    final text = Text(
      value,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
    );
    return SizedBox(
      width: width,
      child: Tooltip(message: value, child: text),
    );
  }

  Widget _rowCell(Widget child, double width, {Alignment alignment = Alignment.centerLeft}) {
    return SizedBox(width: width, child: Align(alignment: alignment, child: child));
  }

  List<DataRow> _buildRows(List<ApprovedSupplier> items, ThemeData theme) {
    return items.map((supplier) {
      final overdue = _isOverdue(supplier);
      final draft = supplier.evaluationState == 'draft';
      final yearLabel = supplier.evaluationYearUsed?.toString() ?? '—';
      final statusLabel = supplier.evaluationState == 'none' ? 'unvollständig' : supplier.evaluationState;
      final auditBasis = supplier.score == null
          ? 'Keine Jahresbewertung'
          : 'Score ${_scoreLabel(supplier)} (Jahresbewertung $yearLabel, ${supplier.counts.perfCasesIncluded} Einträge berücksichtigt)';
      final evidence =
          '${supplier.counts.perfCasesIncluded} Fälle • ${supplier.counts.complaints} Reklamationen • ${supplier.counts.capas} CAPAs • ${supplier.counts.escalations} Eskalationen';
      return DataRow(
        selected: _selected?.supplierId == supplier.supplierId,
        onSelectChanged: (_) => _selectSupplier(supplier),
        cells: [
          DataCell(_textCell(supplier.name, _supplierWidth, maxLines: 2)),
          DataCell(_textCell(supplier.supplierNo.isEmpty ? '—' : supplier.supplierNo, _supplierNoWidth)),
          DataCell(_rowCell(_criticalBadge(supplier, theme), _criticalWidth)),
          DataCell(_rowCell(
            Row(
              children: [
                _statusBadge(supplier, theme),
                if (draft)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Chip(
                      label: const Text('ENTWURF'),
                      labelStyle: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                      backgroundColor: theme.colorScheme.secondaryContainer,
                    ),
                  ),
              ],
            ),
            _statusWidth,
          )),
          DataCell(_rowCell(
            Row(
              children: [
                Text(_scoreLabel(supplier)),
                if (_trendLabel(supplier).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      _trendLabel(supplier),
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
              ],
            ),
            _scoreWidth,
          )),
          if (_auditView) DataCell(_textCell(yearLabel, _yearWidth)),
          if (_auditView) DataCell(_textCell(statusLabel, _evalStatusWidth)),
          DataCell(_textCell(
            supplier.evaluationYearUsed == null
                ? _formatDate(supplier.lastFinalizedAt)
                : '${supplier.evaluationYearUsed} · ${_formatDate(supplier.lastFinalizedAt)}',
            _lastEvalWidth,
          )),
          DataCell(_rowCell(
            Row(
              children: [
                Text(_formatDate(supplier.nextDueDate)),
                if (overdue)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Chip(
                      label: const Text('überfällig'),
                      labelStyle: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onErrorContainer),
                      backgroundColor: theme.colorScheme.errorContainer,
                    ),
                  ),
              ],
            ),
            _nextEvalWidth,
          )),
          if (_auditView) DataCell(_textCell(auditBasis, _auditBasisWidth, maxLines: 2)),
          DataCell(_textCell(supplier.decisionText.isEmpty ? '—' : supplier.decisionText, _decisionWidth, maxLines: 2)),
          DataCell(_textCell(evidence, _evidenceWidth, maxLines: 2)),
          DataCell(
            _rowCell(
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'details':
                      _selectSupplier(supplier);
                      break;
                    case 'evaluation':
                      widget.onOpenSupplierEvaluationFor(supplier.supplierId);
                      break;
                    case 'recompute':
                      _recomputeSupplier(supplier);
                      break;
                    case 'review':
                      _selectSupplier(supplier);
                      _markReviewed();
                      break;
                    case 'letter':
                      _selectSupplier(supplier);
                      _downloadLetter(type: 'letter');
                      break;
                    case 'report':
                      _selectSupplier(supplier);
                      _downloadLetter(type: 'summary');
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'details', child: Text('Details anzeigen')),
                  const PopupMenuItem(value: 'evaluation', child: Text('Zur Lieferantenbewertung')),
                  const PopupMenuItem(value: 'recompute', child: Text('Status neu berechnen')),
                  const PopupMenuItem(value: 'review', child: Text('Als geprüft markieren')),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'letter', child: Text('Lieferantenbrief (PDF)')),
                  const PopupMenuItem(value: 'report', child: Text('Bewertungsreport (PDF)')),
                ],
              ),
              _actionsWidth,
              alignment: Alignment.centerLeft,
            ),
          ),
        ],
      );
    }).toList();
  }

  Widget _buildDataTableHeader(ThemeData theme) {
    return Scrollbar(
      controller: _horizontalHeaderController,
      thumbVisibility: true,
      notificationPredicate: (notif) => notif.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _horizontalHeaderController,
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: _tableMinWidth),
          child: DataTable(
            sortAscending: _sortAsc,
            sortColumnIndex: _sortIndex,
            columns: _buildColumns(theme),
            rows: const [],
            headingRowColor: MaterialStateProperty.all(theme.colorScheme.surfaceVariant),
            dataRowMinHeight: 0,
            dataRowMaxHeight: 0,
            headingRowHeight: 48,
            dividerThickness: 0.4,
          ),
        ),
      ),
    );
  }

  Widget _buildDataTableBody(List<ApprovedSupplier> items, ThemeData theme) {
    return DataTable(
      sortAscending: _sortAsc,
      sortColumnIndex: _sortIndex,
      columns: _buildColumns(theme),
      rows: _buildRows(items, theme),
      headingRowHeight: 0,
      dataRowMinHeight: 52,
      dividerThickness: 0.4,
      dataRowColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) {
          return theme.colorScheme.primaryContainer.withOpacity(0.45);
        }
        if (states.contains(MaterialState.hovered)) {
          return theme.colorScheme.surfaceVariant.withOpacity(0.45);
        }
        return null;
      }),
    );
  }

  Widget _buildToolbar(ThemeData theme) {
    final cs = theme.colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Suche',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _search = value),
          ),
        ),
        FilterChip(
          label: const Text('Überfällig'),
          selected: _filterOverdue,
          onSelected: (value) => setState(() => _filterOverdue = value),
        ),
        FilterChip(
          label: const Text('Ohne Bewertung'),
          selected: _filterWithoutEvaluation,
          onSelected: (value) => setState(() => _filterWithoutEvaluation = value),
        ),
        FilterChip(
          label: const Text('Kritisch'),
          selected: _filterCritical,
          onSelected: (value) => setState(() => _filterCritical = value),
        ),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: _year,
          items: _yearOptions()
              .map((year) => DropdownMenuItem(value: year, child: Text(year.toString())))
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _year = value);
            _loadSuppliers();
          },
        ),
        OutlinedButton.icon(
          onPressed: _loading ? null : () => _exportCsv(_filteredSuppliers),
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('Export CSV'),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: _auditView,
              onChanged: (value) => setState(() => _auditView = value),
            ),
            Text('Audit view', style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
        OutlinedButton.icon(
          onPressed: widget.onOpenSupplierEvaluation,
          icon: const Icon(Icons.verified_outlined),
          label: const Text('Zur Lieferantenbewertung'),
        ),
      ],
    );
  }

  Widget _buildDetailPanel(ThemeData theme) {
    final supplier = _selected;
    if (supplier == null) {
      return SingleChildScrollView(
        controller: _detailScrollController,
        padding: const EdgeInsets.all(24),
        child: Text(
          'Wählen Sie einen Lieferanten, um Details anzuzeigen.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    final evaluation = _selectedEvaluation;
    final aggregates = evaluation?.aggregates ?? const {};
    final criteria = aggregates['criterionAverages'] is List ? aggregates['criterionAverages'] as List : const [];
    final includedEntries = aggregates['includedEntries'] ?? aggregates['includedCount'] ?? supplier.counts.perfCasesIncluded;
    final totalEntries = aggregates['totalEntries'] ?? supplier.counts.perfCasesIncluded;
    final statusExplanation = supplier.statusClass == null
        ? 'Kein Status verfügbar.'
        : 'Status ${supplier.statusClass} basiert auf Score ${_scoreLabel(supplier)} und Entscheidungslogik.';

    return SingleChildScrollView(
      controller: _detailScrollController,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(supplier.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ),
              _criticalBadge(supplier, theme),
            ],
          ),
          const SizedBox(height: 8),
          _statusBadge(supplier, theme),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => widget.onOpenSupplierEvaluationFor(supplier.supplierId),
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Zur Lieferantenbewertung'),
              ),
              FilledButton.icon(
                onPressed: () => _recomputeSupplier(supplier),
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Status neu berechnen'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _detailCard(
            theme,
            title: 'Evaluation Snapshot',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow('Jahresscore', _scoreLabel(supplier)),
                _detailRow('Bewertungsjahr', supplier.evaluationYearUsed?.toString() ?? '—'),
                _detailRow('Bewertungsstatus', supplier.evaluationState == 'draft' ? 'Entwurf' : supplier.evaluationState),
                _detailRow('Einträge (inkl./gesamt)', '$includedEntries / $totalEntries'),
                _detailRow('Entscheidung', supplier.decisionText.isEmpty ? '—' : supplier.decisionText),
                const SizedBox(height: 8),
                Text(statusExplanation, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                if (criteria.isNotEmpty)
                  Table(
                    columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1)},
                    children: [
                      for (final entry in criteria.take(6))
                        if (entry is Map)
                          TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Text('${entry['label'] ?? ''}'),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Text('${entry['average'] ?? '—'}'),
                              ),
                            ],
                          ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _detailCard(
            theme,
            title: 'Audit log / Änderungen',
            child: _detailLoading
                ? const LinearProgressIndicator()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detailRow('Letzte Änderung', _formatHistoryDate(supplier.lastChange['at'])),
                      _detailRow('Geändert von', supplier.lastChange['actor']?.toString() ?? '—'),
                      _detailRow('Hinweis', supplier.lastChange['note']?.toString() ?? '—'),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          _detailCard(
            theme,
            title: 'Dokumente',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _downloadLetter(type: 'letter'),
                      icon: const Icon(Icons.mail_outline),
                      label: const Text('Lieferantenbrief (DE/EN)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _downloadLetter(type: 'summary'),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Bewertungsreport PDF'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Zuletzt generierte Dokumente: keine Einträge',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _detailCard(
            theme,
            title: 'Notizen / intern',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _noteController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Interne Notiz',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _savingNote ? null : _saveNote,
                      icon: _savingNote
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_outlined),
                      label: const Text('Notiz speichern'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: supplier.reviewedAt != null,
                  onChanged: supplier.reviewedAt != null ? null : (_) => _markReviewed(),
                  title: const Text('Reviewed by Purchasing'),
                  subtitle: Text(
                    supplier.reviewedAt == null
                        ? 'Noch nicht geprüft'
                        : 'Geprüft am ${DateFormat('dd.MM.yyyy').format(DateTime.fromMillisecondsSinceEpoch(supplier.reviewedAt!))}',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatHistoryDate(dynamic value) {
    if (value == null) return '—';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed != null) return DateFormat('dd.MM.yyyy HH:mm').format(parsed);
    if (value is num) {
      return DateFormat('dd.MM.yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(value.toInt()));
    }
    return '—';
  }

  Widget _detailCard(ThemeData theme, {required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _filteredSuppliers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Zugelassene Lieferanten',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Audit-sichere Übersicht auf Basis der Lieferantenbewertung. Status, Evidenz und Termine werden live abgeleitet.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        _buildToolbar(theme),
        const SizedBox(height: 16),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
                      ),
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _error != null
                              ? Center(child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)))
                              : items.isEmpty
                                  ? Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Text(
                                          'Keine Lieferanten gefunden. Prüfen Sie die Filter oder legen Sie eine Lieferantenbewertung an.',
                                          style:
                                              theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    )
                                  : Column(
                                      children: [
                                        _buildDataTableHeader(theme),
                                        Expanded(
                                          child: Scrollbar(
                                            controller: _verticalBodyController,
                                            thumbVisibility: true,
                                            notificationPredicate: (notif) => notif.metrics.axis == Axis.vertical,
                                            child: SingleChildScrollView(
                                              controller: _verticalBodyController,
                                              child: Scrollbar(
                                                controller: _horizontalBodyController,
                                                thumbVisibility: true,
                                                notificationPredicate: (notif) => notif.metrics.axis == Axis.horizontal,
                                                child: SingleChildScrollView(
                                                  controller: _horizontalBodyController,
                                                  scrollDirection: Axis.horizontal,
                                                  child: ConstrainedBox(
                                                    constraints: BoxConstraints(minWidth: _tableMinWidth),
                                                    child: _buildDataTableBody(items, theme),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
                      ),
                      child: Scrollbar(
                        controller: _detailScrollController,
                        thumbVisibility: true,
                        child: _buildDetailPanel(theme),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }
}
