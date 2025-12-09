import 'dart:typed_data';

import 'package:flutter/gestures.dart';

import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../api/client.dart';

class ComplaintListItem {
  final String internalNumber;
  final String systemId;
  final String customer;
  final String customerNumber;
  final String region;
  final String productFile;
  final String productGroup;
  final String articleNumber;
  final String articleName;
  final String lotNumber;
  final String complaintType;
  final String complaintReason;
  final String receivedAt;
  final String closedAt;
  final String status;
  final bool goodwill;
  final String departments;
  final String assignee;
  final String salesCode;
  final String orderNumber;
  final String invoiceNumber;
  final String internalAssessment;
  final String suspectedCause;
  final String immediateActions;
  final String correctiveActions;
  final bool recurrence;
  final String severity;
  final String notes;
  final DateTime? receivedDate;
  final DateTime? closedDate;

  ComplaintListItem({
    required this.internalNumber,
    required this.systemId,
    required this.customer,
    required this.customerNumber,
    required this.region,
    required this.productFile,
    required this.productGroup,
    required this.articleNumber,
    required this.articleName,
    required this.lotNumber,
    required this.complaintType,
    required this.complaintReason,
    required this.receivedAt,
    required this.closedAt,
    required this.status,
    required this.goodwill,
    required this.departments,
    required this.assignee,
    required this.salesCode,
    required this.orderNumber,
    required this.invoiceNumber,
    required this.internalAssessment,
    required this.suspectedCause,
    required this.immediateActions,
    required this.correctiveActions,
    required this.recurrence,
    required this.severity,
    required this.notes,
    this.receivedDate,
    this.closedDate,
  });
}

class ComplaintFilterModel {
  final Set<String> statuses;
  final String productGroup;
  final String customer;
  final String department;
  final bool? goodwill;
  final DateTimeRange? dateRange;

  const ComplaintFilterModel({
    this.statuses = const {},
    this.productGroup = '',
    this.customer = '',
    this.department = '',
    this.goodwill,
    this.dateRange,
  });

  ComplaintFilterModel copyWith({
    Set<String>? statuses,
    String? productGroup,
    String? customer,
    String? department,
    bool? goodwill,
    bool goodwillSet = false,
    DateTimeRange? dateRange,
    bool clearDate = false,
  }) {
    return ComplaintFilterModel(
      statuses: statuses ?? this.statuses,
      productGroup: productGroup ?? this.productGroup,
      customer: customer ?? this.customer,
      department: department ?? this.department,
      goodwill: goodwillSet ? goodwill : this.goodwill,
      dateRange: clearDate ? null : (dateRange ?? this.dateRange),
    );
  }
}

class ComplaintListPage extends StatefulWidget {
  final ApiClient api;
  final List<ComplaintListItem> complaints;
  final String? Function(String email)? customerLookup;

  const ComplaintListPage({
    super.key,
    required this.api,
    required this.complaints,
    this.customerLookup,
  });

  @override
  State<ComplaintListPage> createState() => _ComplaintListPageState();
}

class _ComplaintListPageState extends State<ComplaintListPage> {
  final _searchCtrl = TextEditingController();
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalHeaderController = ScrollController();
  final ScrollController _horizontalBodyController = ScrollController();
  bool _isSyncingHorizontal = false;
  ComplaintFilterModel _filters = const ComplaintFilterModel();
  String _sortColumn = 'receivedAt';
  bool _sortAscending = false;
  bool _filtersExpanded = false;
  late List<String> _columnOrder;
  late Set<String> _visibleColumns;
  Uint8List? _logoBytes;

  static const List<(String, String)> _columnDefs = [
    ('Interne Reklamationsnummer', 'internalNumber'),
    ('Interne System-ID', 'systemId'),
    ('Kunde', 'customer'),
    ('Kundennummer', 'customerNumber'),
    ('Land / Region', 'region'),
    ('Produktakte (MDR-TD)', 'productFile'),
    ('Produktgruppe', 'productGroup'),
    ('Artikelnummer', 'articleNumber'),
    ('Artikelbezeichnung', 'articleName'),
    ('Charge / LOT', 'lotNumber'),
    ('Reklamationsart', 'complaintType'),
    ('Reklamationsgrund', 'complaintReason'),
    ('Eingangsdatum', 'receivedAt'),
    ('Abschlussdatum', 'closedAt'),
    ('Status', 'status'),
    ('Kulanz-Flag', 'goodwill'),
    ('Betroffene interne Abteilungen', 'departments'),
    ('Verantwortlicher Bearbeiter (intern)', 'assignee'),
    ('Vertrieb / Sales-Kürzel', 'salesCode'),
    ('Auftragsnummer', 'orderNumber'),
    ('Rechnungsnummer', 'invoiceNumber'),
    ('Interne Bewertung', 'internalAssessment'),
    ('Vermutete Ursache', 'suspectedCause'),
    ('Sofortmaßnahmen', 'immediateActions'),
    ('Korrekturmaßnahmen / CAPA', 'correctiveActions'),
    ('Wiederauftreten', 'recurrence'),
    ('Kritikalität / Schweregrad', 'severity'),
    ('Notizen / Bemerkungen', 'notes'),
  ];

  @override
  void initState() {
    super.initState();
    _columnOrder = _columnDefs.map((c) => c.$2).toList();
    _visibleColumns = _columnDefs.map((c) => c.$2).toSet();
    _horizontalHeaderController.addListener(_syncHorizontalFromHeader);
    _horizontalBodyController.addListener(_syncHorizontalFromBody);
    _loadLogo();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _verticalController.dispose();
    _horizontalHeaderController.dispose();
    _horizontalBodyController.dispose();
    super.dispose();
  }

  void _syncHorizontalFromHeader() {
    if (!_horizontalBodyController.hasClients || _isSyncingHorizontal) return;
    _isSyncingHorizontal = true;
    _horizontalBodyController.jumpTo(
      _horizontalHeaderController.offset.clamp(
        0,
        _horizontalBodyController.position.maxScrollExtent,
      ),
    );
    _isSyncingHorizontal = false;
  }

  void _syncHorizontalFromBody() {
    if (!_horizontalHeaderController.hasClients || _isSyncingHorizontal) return;
    _isSyncingHorizontal = true;
    _horizontalHeaderController.jumpTo(
      _horizontalBodyController.offset.clamp(
        0,
        _horizontalHeaderController.position.maxScrollExtent,
      ),
    );
    _isSyncingHorizontal = false;
  }

  Future<void> _loadLogo() async {
    try {
      final data = await rootBundle.load('assets/dfs_logo.png');
      setState(() => _logoBytes = data.buffer.asUint8List());
    } catch (_) {}
  }

  String _firstVisibleColumn(Set<String> visible) {
    return _columnOrder.firstWhere(visible.contains);
  }

  List<String> get _orderedVisibleColumns =>
      _columnOrder.where((key) => _visibleColumns.contains(key)).toList();

  String _labelForColumn(String key) {
    return _columnDefs.firstWhere((c) => c.$2 == key).$1;
  }

  void _setColumnVisibility(String columnKey, bool visible) {
    final next = {..._visibleColumns};
    if (!visible && next.length == 1) return;

    if (visible) {
      next.add(columnKey);
    } else {
      next.remove(columnKey);
    }

    _visibleColumns = next;
    if (!_visibleColumns.contains(_sortColumn)) {
      _sortColumn = _firstVisibleColumn(_visibleColumns);
      _sortAscending = false;
    }
  }

  void _toggleColumnVisibility(String columnKey) {
    setState(() => _setColumnVisibility(columnKey, !_visibleColumns.contains(columnKey)));
  }

  Future<void> _openColumnPicker() async {
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Spalten auswählen'),
          content: SizedBox(
            width: 360,
            height: 420,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: true),
              child: StatefulBuilder(
                builder: (context, setInnerState) {
                  return ReorderableListView(
                    buildDefaultDragHandles: false,
                    onReorder: (oldIndex, newIndex) {
                      if (newIndex > oldIndex) newIndex -= 1;
                      setState(() {
                        final item = _columnOrder.removeAt(oldIndex);
                        _columnOrder.insert(newIndex, item);
                      });
                      setInnerState(() {});
                    },
                    children: [
                      for (final entry in _columnOrder.indexed)
                        ListTile(
                          key: ValueKey(entry.$2),
                          dense: true,
                          leading: Checkbox(
                            value: _visibleColumns.contains(entry.$2),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _setColumnVisibility(entry.$2, value));
                              setInnerState(() {});
                            },
                          ),
                          title: ReorderableDelayedDragStartListener(
                            index: entry.$1,
                            child: Text(
                              _labelForColumn(entry.$2),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          trailing: ReorderableDragStartListener(
                            index: entry.$1,
                            child: const Icon(Icons.drag_indicator),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fertig'),
            ),
          ],
        );
      },
    );
  }

  List<ComplaintListItem> get _filteredItems {
    final query = _searchCtrl.text.trim().toLowerCase();
    return widget.complaints.where((c) {
      bool matchesQuery() {
        if (query.isEmpty) return true;
        return [
          c.internalNumber,
          c.systemId,
          c.customer,
          c.customerNumber,
          c.productGroup,
          c.productFile,
          c.articleNumber,
          c.articleName,
          c.lotNumber,
          c.complaintType,
          c.complaintReason,
          c.status,
          c.assignee,
          c.salesCode,
          c.orderNumber,
          c.invoiceNumber,
          c.internalAssessment,
          c.suspectedCause,
          c.immediateActions,
          c.correctiveActions,
          c.notes,
        ].any((field) => field.toLowerCase().contains(query));
      }

      final statusMatch = _filters.statuses.isEmpty || _filters.statuses.contains(c.status);
      final productMatch = _filters.productGroup.isEmpty || c.productGroup == _filters.productGroup;
      final customerMatch = _filters.customer.isEmpty || c.customer == _filters.customer;
      final departmentMatch = _filters.department.isEmpty || c.departments.split(', ').contains(_filters.department);
      final goodwillMatch = _filters.goodwill == null || c.goodwill == _filters.goodwill;
      final dateMatch = _filters.dateRange == null
          ? true
          : (c.receivedDate != null &&
              !c.receivedDate!.isBefore(_filters.dateRange!.start) &&
              !c.receivedDate!.isAfter(_filters.dateRange!.end));

      return matchesQuery() && statusMatch && productMatch && customerMatch && departmentMatch && goodwillMatch && dateMatch;
    }).sorted((a, b) => _compareItems(a, b));
  }

  int _compareItems(ComplaintListItem a, ComplaintListItem b) {
    int compare(String valueA, String valueB) => _sortAscending ? valueA.compareTo(valueB) : valueB.compareTo(valueA);
    switch (_sortColumn) {
      case 'customer':
        return compare(a.customer, b.customer);
      case 'status':
        return compare(a.status, b.status);
      case 'receivedAt':
        final aDate = a.receivedDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.receivedDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        return _sortAscending ? aDate.compareTo(bDate) : bDate.compareTo(aDate);
      default:
        return compare(a.systemId, b.systemId);
    }
  }

  Map<String, int> _statusDistribution(List<ComplaintListItem> items) {
    final dist = <String, int>{};
    for (final item in items) {
      dist[item.status] = (dist[item.status] ?? 0) + 1;
    }
    return dist;
  }

  Widget _buildKpiCards(ThemeData theme, List<ComplaintListItem> items) {
    final cs = theme.colorScheme;

    if (items.isEmpty) {
      return Row(
        children: [
          Expanded(
            child: Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: cs.primary.withOpacity(.12),
                      foregroundColor: cs.primary,
                      child: const Icon(Icons.info_outline, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Keine Reklamationen gefunden',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final total = items.length;
    final open = items.where((c) => c.status.toLowerCase().contains('offen')).length;
    final closed = items.where((c) => c.status.toLowerCase().contains('abgeschlossen')).length;
    final goodwill = items.where((c) => c.goodwill).length;
    final avgDuration = items
        .where((c) => c.receivedDate != null && c.closedDate != null)
        .map((c) => c.closedDate!.difference(c.receivedDate!).inDays)
        .toList();
    final avg = avgDuration.isEmpty ? 0 : avgDuration.reduce((a, b) => a + b) / avgDuration.length;

    Widget kpi(String title, String value, IconData icon, Color color) => Expanded(
          child: Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: color.withOpacity(.12),
                    foregroundColor: color,
                    child: Icon(icon, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 2),
                      Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );

    final chartData = _statusDistribution(items);
    final sections = chartData.entries.mapIndexed((i, e) {
      final colors = [cs.primary, cs.secondary, cs.tertiary, cs.error, cs.outline];
      return PieChartSectionData(
        value: e.value.toDouble(),
        color: colors[i % colors.length],
        title: e.key,
        radius: 28,
        titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      );
    }).toList();

    return Row(
      children: [
        kpi('Anzahl Reklamationen', '$total', Icons.list_alt_outlined, cs.primary),
        kpi('Offen', '$open', Icons.mark_email_unread_outlined, cs.secondary),
        kpi('Abgeschlossen', '$closed', Icons.verified_outlined, cs.tertiary),
        kpi('Kulanzfälle', '$goodwill', Icons.handshake_outlined, cs.error),
        Expanded(
          child: Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Durchschnittliche Bearbeitungszeit',
                    style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${avg.toStringAsFixed(1)} Tage',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 78,
                    child: PieChart(
                      PieChartData(
                        sections: sections,
                        centerSpaceRadius: 18,
                        sectionsSpace: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      currentDate: now,
    );
    if (result != null) {
      setState(() => _filters = _filters.copyWith(dateRange: result));
    }
  }

  Widget _buildFilters(List<ComplaintListItem> items) {
    final theme = Theme.of(context);
    final statuses = items.map((e) => e.status).toSet().toList()..sort();
    final productGroups = items.map((e) => e.productGroup).where((e) => e.isNotEmpty).toSet().toList()..sort();
    final customers = items.map((e) => e.customer).where((e) => e.isNotEmpty).toSet().toList()..sort();
    final departments = items
        .expand((e) => e.departments.split(', ').where((d) => d.trim().isNotEmpty))
        .toSet()
        .toList()
      ..sort();

    const denseDecoration = InputDecoration(
      isDense: true,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );

    Widget summaryChip(String label) {
      return Chip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }

    final summary = <Widget>[];
    if (_filters.statuses.isNotEmpty) {
      summary.add(summaryChip('Status: ${_filters.statuses.join(', ')}'));
    }
    if (_filters.productGroup.isNotEmpty) {
      summary.add(summaryChip('Produktgruppe: ${_filters.productGroup}'));
    }
    if (_filters.customer.isNotEmpty) {
      summary.add(summaryChip('Kunde: ${_filters.customer}'));
    }
    if (_filters.department.isNotEmpty) {
      summary.add(summaryChip('Abteilung: ${_filters.department}'));
    }
    if (_filters.goodwill != null) {
      summary.add(summaryChip('Kulanz: ${_filters.goodwill! ? 'Ja' : 'Nein'}'));
    }
    if (_filters.dateRange != null) {
      summary.add(summaryChip(
          'Datum: ${DateFormat.yMd().format(_filters.dateRange!.start)} – ${DateFormat.yMd().format(_filters.dateRange!.end)}'));
    }

    final buttonStyle = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      minimumSize: const Size(0, 38),
      visualDensity: VisualDensity.compact,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    labelText: 'Globale Suche',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _searchCtrl.clear()),
                      tooltip: 'Suche zurücksetzen',
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => setState(() => _filtersExpanded = !_filtersExpanded),
              icon: Icon(_filtersExpanded ? Icons.expand_less : Icons.filter_list),
              label: Text(_filtersExpanded ? 'Filter ausblenden' : 'Filter anzeigen'),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: _openColumnPicker,
              icon: Icon(Icons.view_column_outlined, color: theme.colorScheme.primary),
              label: const Text('Spalten'),
              style: buttonStyle,
            ),
          ],
        ),
        const SizedBox(height: 6),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _filtersExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 220,
                child: InputDecorator(
                  decoration: denseDecoration.copyWith(labelText: 'Status (Mehrfachauswahl)'),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: statuses
                        .map((s) => FilterChip(
                              label: Text(s),
                              visualDensity: VisualDensity.compact,
                              labelStyle: const TextStyle(fontSize: 12),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              selected: _filters.statuses.contains(s),
                              onSelected: (sel) {
                                final set = {..._filters.statuses};
                                sel ? set.add(s) : set.remove(s);
                                setState(() => _filters = _filters.copyWith(statuses: set));
                              },
                            ))
                        .toList(),
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: _filters.productGroup.isEmpty ? null : _filters.productGroup,
                  items: [const DropdownMenuItem(value: '', child: Text('Alle Produktgruppen')),
                    ...productGroups.map((p) => DropdownMenuItem(value: p, child: Text(p))),
                  ],
                  onChanged: (v) => setState(() => _filters = _filters.copyWith(productGroup: v ?? '')),
                  decoration: denseDecoration.copyWith(labelText: 'Produktgruppe'),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: _filters.customer.isEmpty ? null : _filters.customer,
                  items: [const DropdownMenuItem(value: '', child: Text('Alle Kunden')),
                    ...customers.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                  ],
                  onChanged: (v) => setState(() => _filters = _filters.copyWith(customer: v ?? '')),
                  decoration: denseDecoration.copyWith(labelText: 'Kunde'),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: _filters.department.isEmpty ? null : _filters.department,
                  items: [const DropdownMenuItem(value: '', child: Text('Alle Abteilungen')),
                    ...departments.map((d) => DropdownMenuItem(value: d, child: Text(d))),
                  ],
                  onChanged: (v) => setState(() => _filters = _filters.copyWith(department: v ?? '')),
                  decoration: denseDecoration.copyWith(labelText: 'Betroffene Abteilung'),
                ),
              ),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<bool>(
                  value: _filters.goodwill,
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Kulanz: alle')),
                    DropdownMenuItem(value: true, child: Text('Kulanz: Ja')),
                    DropdownMenuItem(value: false, child: Text('Kulanz: Nein')),
                  ],
                  onChanged: (v) => setState(() => _filters = _filters.copyWith(goodwill: v, goodwillSet: true)),
                  decoration: denseDecoration.copyWith(labelText: 'Kulanz'),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickDateRange,
                icon: const Icon(Icons.date_range_outlined),
                style: buttonStyle,
                label: Text(_filters.dateRange == null
                    ? 'Datum Von–Bis'
                    : '${DateFormat.yMd().format(_filters.dateRange!.start)} – ${DateFormat.yMd().format(_filters.dateRange!.end)}'),
              ),
              if (_filters.dateRange != null)
                TextButton(
                  onPressed: () => setState(() => _filters = _filters.copyWith(clearDate: true)),
                  child: const Text('Datumsfilter entfernen'),
                ),
            ],
          ),
          secondChild: Align(
            alignment: Alignment.centerLeft,
            child: summary.isEmpty
                ? const Text('Keine weiteren Filter aktiv')
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: summary,
                  ),
          ),
        ),
      ],
    );
  }

  List<DataColumn> _buildColumns() {
    return _orderedVisibleColumns
        .map((key) => DataColumn(
              label: Text(_labelForColumn(key), style: const TextStyle(fontWeight: FontWeight.w700)),
              onSort: (i, asc) => setState(() {
                _sortColumn = key;
                _sortAscending = asc;
              }),
            ))
        .toList();
  }

  int? get _sortColumnIndex {
    final visible = _orderedVisibleColumns;
    final idx = visible.indexWhere((c) => c == _sortColumn);
    return idx >= 0 ? idx : null;
  }

  DataCell _cell(String value, {double width = 160}) {
    return DataCell(Tooltip(
      message: value,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Text(value, overflow: TextOverflow.ellipsis, maxLines: 2),
      ),
    ));
  }

  List<DataRow> _buildRows(List<ComplaintListItem> items) {
    return items.mapIndexed((i, c) {
      final cells = <String, DataCell>{
        'internalNumber': _cell(c.internalNumber),
        'systemId': _cell(c.systemId),
        'customer': _cell(c.customer),
        'customerNumber': _cell(c.customerNumber),
        'region': _cell(c.region),
        'productGroup': _cell(c.productGroup),
        'articleNumber': _cell(c.articleNumber),
        'articleName': _cell(c.articleName),
        'lotNumber': _cell(c.lotNumber),
        'complaintType': _cell(c.complaintType),
        'complaintReason': _cell(c.complaintReason, width: 220),
        'receivedAt': _cell(c.receivedAt),
        'closedAt': _cell(c.closedAt),
        'status': _cell(c.status),
        'goodwill': _cell(c.goodwill ? 'Ja' : 'Nein'),
        'departments': _cell(c.departments, width: 200),
        'assignee': _cell(c.assignee),
        'salesCode': _cell(c.salesCode),
        'orderNumber': _cell(c.orderNumber),
        'invoiceNumber': _cell(c.invoiceNumber),
        'internalAssessment': _cell(c.internalAssessment, width: 220),
        'suspectedCause': _cell(c.suspectedCause, width: 220),
        'immediateActions': _cell(c.immediateActions, width: 200),
        'correctiveActions': _cell(c.correctiveActions, width: 220),
        'recurrence': _cell(c.recurrence ? 'Ja' : 'Nein'),
        'severity': _cell(c.severity),
        'notes': _cell(c.notes, width: 240),
      };
      return DataRow.byIndex(index: i, cells: [
        ..._orderedVisibleColumns.map((key) => cells[key]!),
      ]);
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
        child: DataTable(
          sortAscending: _sortAscending,
          sortColumnIndex: _sortColumnIndex,
          columns: _buildColumns(),
          rows: const [],
          headingRowColor: MaterialStateProperty.all(theme.colorScheme.surfaceVariant),
          dataRowMinHeight: 0,
          dataRowMaxHeight: 0,
          headingRowHeight: 54,
          dividerThickness: 0.4,
        ),
      ),
    );
  }

  Widget _buildDataTableBody(List<ComplaintListItem> items) {
    return DataTable(
      sortAscending: _sortAscending,
      sortColumnIndex: _sortColumnIndex,
      columns: _buildColumns(),
      rows: _buildRows(items),
      headingRowHeight: 0,
      dataRowMinHeight: 52,
      dividerThickness: 0.4,
    );
  }

  Future<void> _exportPdf(List<ComplaintListItem> items) async {
    final doc = pw.Document();
    final date = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now());
    pw.ImageProvider? logo;
    if (_logoBytes != null) {
      logo = pw.MemoryImage(_logoBytes!);
    }

    final headers = [
      'Interne Nr.',
      'System-ID',
      'Kunde',
      'Status',
      'Produktakte',
      'Produktgruppe',
      'Artikel',
      'Eingang',
      'Abschluss',
      'Kulanz',
    ];

    final data = items
        .map((c) => [
              c.internalNumber,
              c.systemId,
              c.customer,
              c.status,
              c.productFile,
              c.productGroup,
              c.articleNumber,
              c.receivedAt,
              c.closedAt,
              c.goodwill ? 'Ja' : 'Nein',
            ])
        .toList();

    doc.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logo != null) pw.Container(width: 90, height: 40, child: pw.Image(logo)),
              pw.Spacer(),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text('Reklamationsübersicht (Admin)', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.Text(date, style: const pw.TextStyle(fontSize: 10)),
              ]),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Table.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: PdfColors.blueGrey800),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
            data: [headers, ...data],
          ),
        ],
      ),
    );

    await Printing.sharePdf(bytes: await doc.save(), filename: 'reklamationsliste.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _filteredItems;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reklamationsliste'),
        actions: [
          ElevatedButton.icon(
            onPressed: () => _exportPdf(items),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Aktuelle Ansicht als PDF exportieren'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildFilters(widget.complaints),
            const SizedBox(height: 12),
            _buildKpiCards(theme, items),
            const SizedBox(height: 12),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: const {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                  },
                ),
                child: Column(
                  children: [
                    _buildDataTableHeader(theme),
                    const Divider(height: 1),
                    Expanded(
                      child: Scrollbar(
                        controller: _verticalController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _verticalController,
                          scrollDirection: Axis.vertical,
                          child: Scrollbar(
                            controller: _horizontalBodyController,
                            thumbVisibility: true,
                            notificationPredicate: (notif) => notif.metrics.axis == Axis.horizontal,
                            child: SingleChildScrollView(
                              controller: _horizontalBodyController,
                              scrollDirection: Axis.horizontal,
                              child: _buildDataTableBody(items),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
