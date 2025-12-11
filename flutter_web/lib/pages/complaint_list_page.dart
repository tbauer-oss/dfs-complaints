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
  final String segment;
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
  final String prrcClassification;
  final String prrcComment;
  final String internalAssessment;
  final String suspectedCause;
  final String immediateActions;
  final String correctiveActions;
  final bool recurrence;
  final String severity;
  final String notes;
  final DateTime? receivedDate;
  final DateTime? closedDate;
  final bool hasPrrcDecision;
  final bool salesCompleted;

  ComplaintListItem({
    required this.internalNumber,
    required this.systemId,
    required this.customer,
    required this.customerNumber,
    required this.region,
    required this.productFile,
    required this.productGroup,
    required this.segment,
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
    required this.prrcClassification,
    required this.prrcComment,
    required this.internalAssessment,
    required this.suspectedCause,
    required this.immediateActions,
    required this.correctiveActions,
    required this.recurrence,
    required this.severity,
    required this.notes,
    required this.hasPrrcDecision,
    required this.salesCompleted,
    this.receivedDate,
    this.closedDate,
  });

  ComplaintListItem copyWith({
    String? immediateActions,
    String? correctiveActions,
    String? prrcClassification,
    String? prrcComment,
    bool? hasPrrcDecision,
    bool? salesCompleted,
    String? segment,
  }) {
    return ComplaintListItem(
      internalNumber: internalNumber,
      systemId: systemId,
      customer: customer,
      customerNumber: customerNumber,
      region: region,
      productFile: productFile,
      productGroup: productGroup,
      segment: segment ?? this.segment,
      articleNumber: articleNumber,
      articleName: articleName,
      lotNumber: lotNumber,
      complaintType: complaintType,
      complaintReason: complaintReason,
      receivedAt: receivedAt,
      closedAt: closedAt,
      status: status,
      goodwill: goodwill,
      departments: departments,
      assignee: assignee,
      salesCode: salesCode,
      orderNumber: orderNumber,
      invoiceNumber: invoiceNumber,
      prrcClassification: prrcClassification ?? this.prrcClassification,
      prrcComment: prrcComment ?? this.prrcComment,
      internalAssessment: internalAssessment,
      suspectedCause: suspectedCause,
      immediateActions: immediateActions ?? this.immediateActions,
      correctiveActions: correctiveActions ?? this.correctiveActions,
      recurrence: recurrence,
      severity: severity,
      notes: notes,
      hasPrrcDecision: hasPrrcDecision ?? this.hasPrrcDecision,
      salesCompleted: salesCompleted ?? this.salesCompleted,
      receivedDate: receivedDate,
      closedDate: closedDate,
    );
  }
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
  final String? errorMessage;
  final bool isLoading;
  final VoidCallback? onReload;
  final Future<ComplaintListItem?> Function(
          String ticket, String? immediateActions, String? correctiveActions)?
      onInlineUpdateActions;
  final Future<ComplaintListItem?> Function(String ticket, String classification, {String? comment})?
      onUpdatePrrcClassification;
  final bool showPrrcColumn;
  final bool prrcReadOnly;

  const ComplaintListPage({
    super.key,
    required this.api,
    required this.complaints,
    this.customerLookup,
    this.errorMessage,
    this.isLoading = false,
    this.onReload,
    this.onInlineUpdateActions,
    this.onUpdatePrrcClassification,
    this.showPrrcColumn = false,
    this.prrcReadOnly = false,
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
  late List<ComplaintListItem> _items;
  final Set<String> _savingPrrcTickets = {};

  static const Map<String, double> _columnWidths = {
    'internalNumber': 140,
    'systemId': 140,
    'customer': 180,
    'customerNumber': 140,
    'region': 140,
    'productFile': 180,
    'productGroup': 160,
    'articleNumber': 150,
    'articleName': 200,
    'lotNumber': 140,
    'complaintType': 180,
    'complaintReason': 220,
    'receivedAt': 140,
    'closedAt': 140,
    'status': 140,
    'goodwill': 120,
    'departments': 220,
    'assignee': 180,
    'salesCode': 140,
    'orderNumber': 150,
    'invoiceNumber': 150,
    'prrcClassification': 140,
    'prrcComment': 240,
    'internalAssessment': 220,
    'suspectedCause': 220,
    'immediateActions': 200,
    'correctiveActions': 220,
    'recurrence': 140,
    'severity': 160,
    'notes': 240,
  };

  static const Map<String, String> _pdfColumnGroups = {
    'internalNumber': 'Reklamationsdaten',
    'systemId': 'Reklamationsdaten',
    'customer': 'Vertrieb / Kunde',
    'customerNumber': 'Vertrieb / Kunde',
    'region': 'Vertrieb / Kunde',
    'productFile': 'Produktdaten',
    'productGroup': 'Produktdaten',
    'articleNumber': 'Produktdaten',
    'articleName': 'Produktdaten',
    'lotNumber': 'Produktdaten',
    'complaintType': 'Reklamationsdaten',
    'complaintReason': 'Reklamationsdaten',
    'receivedAt': 'Reklamationsdaten',
    'closedAt': 'Reklamationsdaten',
    'status': 'Reklamationsdaten',
    'goodwill': 'Reklamationsdaten',
    'departments': 'Reklamationsdaten',
    'assignee': 'Vertrieb / Kunde',
    'salesCode': 'Vertrieb / Kunde',
    'orderNumber': 'Vertrieb / Kunde',
    'invoiceNumber': 'Vertrieb / Kunde',
    'prrcClassification': 'PRRC / Bewertung',
    'prrcComment': 'PRRC / Bewertung',
    'internalAssessment': 'PRRC / Bewertung',
    'suspectedCause': 'CAPA / Maßnahmen',
    'immediateActions': 'CAPA / Maßnahmen',
    'correctiveActions': 'CAPA / Maßnahmen',
    'recurrence': 'Reklamationsdaten',
    'severity': 'PRRC / Bewertung',
    'notes': 'CAPA / Maßnahmen',
  };

  static const List<String> _prrcOptions = ['N/A', 'Sub', 'A', 'B', 'C', 'D'];

  static const List<(String, String)> _baseColumnDefs = [
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
    ('PRRC-Bewertung', 'prrcClassification'),
    ('PRRC-Kommentar', 'prrcComment'),
    ('Interne Bewertung', 'internalAssessment'),
    ('Vermutete Ursache', 'suspectedCause'),
    ('Sofortmaßnahmen', 'immediateActions'),
    ('Korrekturmaßnahmen / CAPA', 'correctiveActions'),
    ('Wiederauftreten', 'recurrence'),
    ('Kritikalität / Schweregrad', 'severity'),
    ('Notizen / Bemerkungen', 'notes'),
  ];

  List<(String, String)> get _columnDefs => widget.showPrrcColumn
      ? _baseColumnDefs
      : _baseColumnDefs
          .where((c) => !['prrcClassification', 'prrcComment'].contains(c.$2))
          .toList();

  @override
  void initState() {
    super.initState();
    _columnOrder = _columnDefs.map((c) => c.$2).toList();
    _visibleColumns = _columnDefs.map((c) => c.$2).toSet();
    _items = List.of(widget.complaints);
    _horizontalHeaderController.addListener(_syncHorizontalFromHeader);
    _horizontalBodyController.addListener(_syncHorizontalFromBody);
    _loadLogo();
  }

  @override
  void didUpdateWidget(covariant ComplaintListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!const ListEquality().equals(widget.complaints, oldWidget.complaints)) {
      _items = List.of(widget.complaints);
    }
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

  String _wrapHeaderLabel(String label) {
    const overrides = {
      'Interne Reklamationsnummer': 'Interne\nReklamationsnummer',
      'Interne System-ID': 'Interne\nSystem-ID',
      'Verantwortlicher Bearbeiter (intern)': 'Verantwortlicher\nBearbeiter (intern)',
      'Kritikalität / Schweregrad': 'Kritikalität /\nSchweregrad',
      'Produktakte (MDR-TD)': 'Produktakte\n(MDR-TD)',
      'Vertrieb / Sales-Kürzel': 'Vertrieb /\nSales-Kürzel',
      'Betroffene interne Abteilungen': 'Betroffene interne\nAbteilungen',
      'Interne Bewertung': 'Interne\nBewertung',
      'Korrekturmaßnahmen / CAPA': 'Korrekturmaßnahmen /\nCAPA',
    };

    if (overrides.containsKey(label)) return overrides[label]!;
    if (label.contains(' / ')) return label.replaceFirst(' / ', ' /\n');

    final parts = label.split(' ');
    if (parts.length <= 1) return label;

    final mid = (parts.length / 2).floor();
    return '${parts.sublist(0, mid).join(' ')}\n${parts.sublist(mid).join(' ')}';
  }

  pw.TableColumnWidth _pdfColumnWidth(String key) {
    final baseWidth = _columnWidths[key] ?? 150;
    final flex = (baseWidth / 110).clamp(0.7, 2.2) as double;
    return pw.FlexColumnWidth(flex);
  }

  String _firstVisibleColumn(Set<String> visible) {
    return _columnOrder.firstWhere(visible.contains);
  }

  List<String> get _orderedVisibleColumns =>
      _columnOrder.where((key) => _visibleColumns.contains(key)).toList();

  double _columnWidth(String key) => _columnWidths[key] ?? 160;

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
    return _items.where((c) {
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
          c.prrcClassification,
          c.prrcComment,
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
      case 'prrcClassification':
        return compare(a.prrcClassification, b.prrcClassification);
      case 'prrcComment':
        return compare(a.prrcComment, b.prrcComment);
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
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );

    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );

    Widget labeledField({required String label, required Widget child}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: labelStyle),
          const SizedBox(height: 4),
          child,
        ],
      );
    }

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
                child: labeledField(
                  label: 'Status (Mehrfachauswahl)',
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
              ),
              SizedBox(
                width: 180,
                child: labeledField(
                  label: 'Produktgruppe',
                  child: DropdownButtonFormField<String>(
                    value: _filters.productGroup.isEmpty ? null : _filters.productGroup,
                    items: [const DropdownMenuItem(value: '', child: Text('Alle Produktgruppen')),
                      ...productGroups.map((p) => DropdownMenuItem(value: p, child: Text(p))),
                    ],
                    onChanged: (v) => setState(() => _filters = _filters.copyWith(productGroup: v ?? '')),
                    decoration: denseDecoration.copyWith(hintText: 'Alle Produktgruppen'),
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: labeledField(
                  label: 'Kunde',
                  child: DropdownButtonFormField<String>(
                    value: _filters.customer.isEmpty ? null : _filters.customer,
                    items: [const DropdownMenuItem(value: '', child: Text('Alle Kunden')),
                      ...customers.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                    ],
                    onChanged: (v) => setState(() => _filters = _filters.copyWith(customer: v ?? '')),
                    decoration: denseDecoration.copyWith(hintText: 'Alle Kunden'),
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: labeledField(
                  label: 'Betroffene Abteilung',
                  child: DropdownButtonFormField<String>(
                    value: _filters.department.isEmpty ? null : _filters.department,
                    items: [const DropdownMenuItem(value: '', child: Text('Alle Abteilungen')),
                      ...departments.map((d) => DropdownMenuItem(value: d, child: Text(d))),
                    ],
                    onChanged: (v) => setState(() => _filters = _filters.copyWith(department: v ?? '')),
                    decoration: denseDecoration.copyWith(hintText: 'Alle Abteilungen'),
                  ),
                ),
              ),
              SizedBox(
                width: 150,
                child: labeledField(
                  label: 'Kulanz',
                  child: DropdownButtonFormField<bool>(
                    value: _filters.goodwill,
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Kulanz: alle')),
                      DropdownMenuItem(value: true, child: Text('Kulanz: Ja')),
                      DropdownMenuItem(value: false, child: Text('Kulanz: Nein')),
                    ],
                    onChanged: (v) => setState(() => _filters = _filters.copyWith(goodwill: v, goodwillSet: true)),
                    decoration: denseDecoration.copyWith(hintText: 'Kulanz: alle'),
                  ),
                ),
              ),
              labeledField(
                label: 'Datum Von–Bis',
                child: OutlinedButton.icon(
                  onPressed: _pickDateRange,
                  icon: const Icon(Icons.date_range_outlined),
                  style: buttonStyle,
                  label: Text(_filters.dateRange == null
                      ? 'Zeitspanne wählen'
                      : '${DateFormat.yMd().format(_filters.dateRange!.start)} – ${DateFormat.yMd().format(_filters.dateRange!.end)}'),
                ),
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
              label: ConstrainedBox(
                constraints: BoxConstraints(minWidth: _columnWidth(key), maxWidth: _columnWidth(key)),
                child: Text(
                  _labelForColumn(key),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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

  DataCell _cellFor(String key, String value) {
    final width = _columnWidth(key);
    return DataCell(Tooltip(
      message: value,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Text(value, overflow: TextOverflow.ellipsis, maxLines: 2),
      ),
    ));
  }

  DataCell _prrcCell(ComplaintListItem item) {
    final width = _columnWidth('prrcClassification');
    final display = item.prrcClassification.isEmpty ? '—' : item.prrcClassification;
    final prrcEditable = widget.onUpdatePrrcClassification != null && !widget.prrcReadOnly;

    if (!prrcEditable) {
      final disabledStyle = widget.prrcReadOnly
          ? TextStyle(color: Theme.of(context).disabledColor)
          : null;
      return DataCell(
        Tooltip(
          message: display,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: Text(
              display,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: disabledStyle,
            ),
          ),
        ),
      );
    }

    final isSaving = _savingPrrcTickets.contains(item.systemId);
    return DataCell(
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: display == '—' ? 'N/A' : display,
                items: _prrcOptions
                    .map((opt) => DropdownMenuItem<String>(
                          value: opt,
                          child: Text(opt),
                        ))
                    .toList(),
                onChanged: isSaving ? null : (value) {
                  if (value != null) _handlePrrcChange(item, value);
                },
              ),
            ),
            if (isSaving)
              const Positioned(
                right: 0,
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<DataRow> _buildRows(List<ComplaintListItem> items) {
    return items.mapIndexed((i, c) {
      final rowColor = _rowBackgroundColor(c);
      final cells = <String, DataCell>{
        'internalNumber': _cellFor('internalNumber', c.internalNumber),
        'systemId': _cellFor('systemId', c.systemId),
        'customer': _cellFor('customer', c.customer),
        'customerNumber': _cellFor('customerNumber', c.customerNumber),
        'region': _cellFor('region', c.region),
        'productFile': _cellFor('productFile', c.productFile),
        'productGroup': _cellFor('productGroup', c.productGroup),
        'articleNumber': _cellFor('articleNumber', c.articleNumber),
        'articleName': _cellFor('articleName', c.articleName),
        'lotNumber': _cellFor('lotNumber', c.lotNumber),
        'complaintType': _cellFor('complaintType', c.complaintType),
        'complaintReason': _cellFor('complaintReason', c.complaintReason),
        'receivedAt': _cellFor('receivedAt', c.receivedAt),
        'closedAt': _cellFor('closedAt', c.closedAt),
        'status': _cellFor('status', c.status),
        'goodwill': _cellFor('goodwill', c.goodwill ? 'Ja' : 'Nein'),
        'departments': _cellFor('departments', c.departments),
        'assignee': _cellFor('assignee', c.assignee),
        'salesCode': _cellFor('salesCode', c.salesCode),
        'orderNumber': _cellFor('orderNumber', c.orderNumber),
        'invoiceNumber': _cellFor('invoiceNumber', c.invoiceNumber),
        'prrcClassification': _prrcCell(c),
        'prrcComment': _cellFor('prrcComment', c.prrcComment.isEmpty ? '—' : c.prrcComment),
        'internalAssessment': _cellFor('internalAssessment', c.internalAssessment),
        'suspectedCause': _cellFor('suspectedCause', c.suspectedCause),
        'immediateActions': _actionCell('immediateActions', c.immediateActions),
        'correctiveActions': _actionCell('correctiveActions', c.correctiveActions),
        'recurrence': _cellFor('recurrence', c.recurrence ? 'Ja' : 'Nein'),
        'severity': _cellFor('severity', c.severity),
        'notes': _cellFor('notes', c.notes),
      };
      return DataRow.byIndex(
        index: i,
        color: rowColor != null ? MaterialStateProperty.all(rowColor) : null,
        cells: [
          ..._orderedVisibleColumns.map((key) => cells[key]!),
        ],
      );
    }).toList();
  }

  Color? _rowBackgroundColor(ComplaintListItem item) {
    final normalizedProductFile = item.productFile.trim().toLowerCase();
    final normalizedSegment = item.segment.trim().toLowerCase();
    final normalizedGroup = item.productGroup.trim().toLowerCase();
    final productFileLooksDental = normalizedProductFile.contains('dental');
    final isDentalProduct = normalizedSegment == 'zahnmedizin' ||
        normalizedSegment == 'zahnarzt' ||
        normalizedGroup.contains('zahnmedizin') ||
        productFileLooksDental;
    if (!isDentalProduct) return null;

    final isDentalLabPlaceholder =
        normalizedProductFile.isEmpty ||
            normalizedProductFile == '-' ||
            normalizedProductFile.contains('dental lab');
    final hasMdrAssignment =
        normalizedProductFile.startsWith('mdr-td') && !isDentalLabPlaceholder;
    final isClosed = item.status.trim().toLowerCase() == 'abgeschlossen';
    final redHighlight = Colors.redAccent.withOpacity(0.16);
    final amberHighlight = Colors.amberAccent.withOpacity(0.16);
    final greenHighlight = Colors.lightGreenAccent.withOpacity(0.16);

    if (!hasMdrAssignment) {
      return isClosed ? (item.salesCompleted ? greenHighlight : null) : amberHighlight;
    }

    if (!item.hasPrrcDecision) {
      return redHighlight;
    }

    if (!isClosed) {
      return amberHighlight;
    }

    if (item.salesCompleted && isClosed) {
      return greenHighlight;
    }

    return null;
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

  DataCell _actionCell(String key, String value) {
    final display = value.trim().isEmpty ? '—' : value;
    return _cellFor(key, display);
  }

  Map<String, String> _pdfValuesForItem(ComplaintListItem item) {
    final values = <String, String>{
      'internalNumber': item.internalNumber,
      'systemId': item.systemId,
      'customer': item.customer,
      'customerNumber': item.customerNumber,
      'region': item.region,
      'productFile': item.productFile,
      'productGroup': item.productGroup,
      'articleNumber': item.articleNumber,
      'articleName': item.articleName,
      'lotNumber': item.lotNumber,
      'complaintType': item.complaintType,
      'complaintReason': item.complaintReason,
      'receivedAt': item.receivedAt,
      'closedAt': item.closedAt,
      'status': item.status,
      'departments': item.departments,
      'assignee': item.assignee,
      'salesCode': item.salesCode,
      'orderNumber': item.orderNumber,
      'invoiceNumber': item.invoiceNumber,
      'internalAssessment': item.internalAssessment,
      'suspectedCause': item.suspectedCause,
      'immediateActions': item.immediateActions,
      'correctiveActions': item.correctiveActions,
      'severity': item.severity,
      'notes': item.notes,
    };

    String displayValue(String value) => value.trim().isEmpty ? '—' : value.trim();

    values['goodwill'] = item.goodwill ? 'Ja' : 'Nein';
    values['prrcClassification'] = displayValue(item.prrcClassification);
    values['prrcComment'] = displayValue(item.prrcComment);
    values['recurrence'] = item.recurrence ? 'Ja' : 'Nein';

    return values.map((key, value) => MapEntry(key, displayValue(value)));
  }

  Future<void> _handlePrrcChange(ComplaintListItem item, String classification) async {
    if (widget.onUpdatePrrcClassification == null) return;
    setState(() => _savingPrrcTickets.add(item.systemId));
    try {
      final updated =
          await widget.onUpdatePrrcClassification!(item.systemId, classification.trim());
      setState(() {
        final idx = _items.indexWhere((c) => c.systemId == item.systemId);
        if (idx != -1) {
          _items[idx] = item.copyWith(prrcClassification: classification);
        }
      });
      if (updated != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PRRC-Bewertung gespeichert.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler bei PRRC-Update: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPrrcTickets.remove(item.systemId));
    }
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
    final now = DateTime.now();
    final date = DateFormat('dd.MM.yyyy HH:mm').format(now);
    final version = DateFormat('dd.MM.yyyy').format(now);
    pw.ImageProvider? logo;
    if (_logoBytes != null) {
      logo = pw.MemoryImage(_logoBytes!);
    }

    final columns = _columnDefs.map((c) => c.$2).toList();
    final headers = _columnDefs.map((c) => c.$1).toList();
    final rows = items
        .map((item) {
          final values = _pdfValuesForItem(item);
          return columns.map((key) => values[key] ?? '—').toList();
        })
        .toList();

    final baseColumnWidths = <int, pw.TableColumnWidth>{
      for (var i = 0; i < columns.length; i++) i: _pdfColumnWidth(columns[i]),
    };

    final columnFlexes = <double>[
      for (final column in columns)
        (_pdfColumnWidth(column) as pw.FlexColumnWidth).flex,
    ];

    pw.Widget _groupHeaderRow() {
      final groupCells = <pw.Widget>[];
      String? currentLabel;
      double span = 0;

      void pushGroupCell() {
        if (currentLabel == null || span == 0) return;
        final flex = (span * 1000).round().clamp(1, 1000000);
        groupCells.add(
          pw.Expanded(
            flex: flex,
            child: pw.Container(
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFF1F3A54),
                border: pw.Border(
                  left: const pw.BorderSide(color: PdfColors.blueGrey700, width: 0.6),
                  right: const pw.BorderSide(color: PdfColors.blueGrey700, width: 0.6),
                  top: const pw.BorderSide(color: PdfColors.blueGrey700, width: 0.6),
                  bottom: const pw.BorderSide(color: PdfColors.blueGrey700, width: 0.6),
                ),
              ),
              child: pw.Text(
                currentLabel!,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8,
                ),
              ),
            ),
          ),
        );
      }

      for (var i = 0; i < columns.length; i++) {
        final column = columns[i];
        final label = _pdfColumnGroups[column] ?? 'Weitere';
        final flex = columnFlexes[i];

        if (currentLabel == label) {
          span += flex;
        } else {
          pushGroupCell();
          currentLabel = label;
          span = flex;
        }
      }

      pushGroupCell();

      return pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border(
            left: const pw.BorderSide(color: PdfColors.blueGrey700, width: 0.6),
            right: const pw.BorderSide(color: PdfColors.blueGrey700, width: 0.6),
            top: const pw.BorderSide(color: PdfColors.blueGrey700, width: 0.6),
          ),
        ),
        child: pw.Row(children: groupCells),
      );
    }

    pw.Widget _columnHeaderRow() {
      final headerCells = <pw.Widget>[];
      for (var i = 0; i < columns.length; i++) {
        headerCells.add(
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF284765)),
            alignment: pw.Alignment.center,
            child: pw.Text(
              _wrapHeaderLabel(headers[i]),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 8,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        );
      }

      return pw.Table(
        columnWidths: baseColumnWidths,
        border: pw.TableBorder(
          bottom: pw.BorderSide(color: PdfColors.blueGrey700, width: 0.6),
          left: const pw.BorderSide(color: PdfColors.blueGrey700, width: 0.6),
          right: const pw.BorderSide(color: PdfColors.blueGrey700, width: 0.6),
          horizontalInside: const pw.BorderSide(color: PdfColors.blueGrey700, width: 0.6),
        ),
        children: [pw.TableRow(children: headerCells)],
      );
    }

    pw.Widget _buildBodyTable() {
      final dataRows = <pw.TableRow>[];
      for (var rowIdx = 0; rowIdx < rows.length; rowIdx++) {
        final row = rows[rowIdx];
        final cells = <pw.Widget>[];
        for (var colIdx = 0; colIdx < row.length; colIdx++) {
          cells.add(
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              alignment: pw.Alignment.centerLeft,
              decoration: pw.BoxDecoration(
                color: rowIdx.isOdd ? PdfColors.grey200 : PdfColors.white,
                border: pw.Border(
                  left: const pw.BorderSide(color: PdfColors.blueGrey400, width: 0.35),
                  right: const pw.BorderSide(color: PdfColors.blueGrey400, width: 0.35),
                  top: rowIdx == 0
                      ? const pw.BorderSide(color: PdfColors.blueGrey400, width: 0.35)
                      : pw.BorderSide.none,
                  bottom: const pw.BorderSide(color: PdfColors.blueGrey400, width: 0.35),
                ),
              ),
              child: pw.Text(
                row[colIdx],
                style: const pw.TextStyle(fontSize: 7.5),
              ),
            ),
          );
        }
        dataRows.add(pw.TableRow(children: cells));
      }

      return pw.Table(
        columnWidths: baseColumnWidths,
        border: pw.TableBorder(
          left: const pw.BorderSide(color: PdfColors.blueGrey700, width: 0.6),
          right: const pw.BorderSide(color: PdfColors.blueGrey700, width: 0.6),
          top: pw.BorderSide.none,
        ),
        children: dataRows,
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(24, 32, 24, 36),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logo != null) pw.Container(width: 86, height: 32, child: pw.Image(logo)),
                pw.SizedBox(width: 10),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Reklamationsübersicht (Admin)',
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(date, style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                pw.Spacer(),
                pw.Text('DFS-DIAMON GmbH', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.SizedBox(height: 10),
            _groupHeaderRow(),
            _columnHeaderRow(),
          ],
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Reklamationsübersicht (Quality Management)',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Row(
                children: [
                  pw.Text(
                    'Seite ${context.pageNumber} von ${context.pagesCount}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Text('Export vom $version', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
            ],
          ),
        ),
        build: (ctx) => [_buildBodyTable()],
      ),
    );

    await Printing.sharePdf(bytes: await doc.save(), filename: 'reklamationsliste.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _filteredItems;

    if (widget.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (widget.errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Reklamationsliste'),
          actions: [
            if (widget.onReload != null)
              IconButton(
                tooltip: 'Neu laden',
                onPressed: widget.onReload,
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text('Fehler beim Laden der Reklamationsliste', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  widget.errorMessage!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              if (widget.onReload != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ElevatedButton.icon(
                    onPressed: widget.onReload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Erneut versuchen'),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (widget.complaints.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Reklamationsliste'),
          actions: [
            if (widget.onReload != null)
              IconButton(
                tooltip: 'Neu laden',
                onPressed: widget.onReload,
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text('Keine Reklamationen gefunden', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Bitte Daten neu laden oder Filter anpassen.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (widget.onReload != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ElevatedButton.icon(
                    onPressed: widget.onReload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Neu laden'),
                  ),
                ),
            ],
          ),
        ),
      );
    }

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
