// lib/pages/admin_stats_page.dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:country_flags/country_flags.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_saver/file_saver.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../api/client.dart';
import '../data/country_geography.dart';
import '../models/dfs_product.dart';
import '../services/dfs_product_service.dart';
import '../widgets/legal_footer.dart';

class AdminStatsPage extends StatefulWidget {
  final ApiClient api;
  const AdminStatsPage({super.key, required this.api});

  @override
  State<AdminStatsPage> createState() => _AdminStatsPageState();
}

class _AdminStatsPageState extends State<AdminStatsPage> {
  final _productService = DfsProductService();
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;
  DateTimeRange? _range;
  DateTime? _manualFrom;
  DateTime? _manualTo;
  bool _exporting = false;
  List<DfsProduct> _products = const [];
  Map<String, DfsProduct> _productByArticle = const {};
  List<_EnrichedComplaint> _enrichedComplaints = const [];
  List<_EnrichedComplaint> _visibleComplaints = const [];
  String? _selectedMdrGroup;
  String? _selectedCountry;
  String? _selectedCustomer;
  String? _selectedProductGroup;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadStats();
  }

  Future<void> _loadStats({DateTime? from, DateTime? to}) async {
    final hasOverride = from != null || to != null;
    if (hasOverride) {
      _manualFrom = from;
      _manualTo = to;
    }
    final queryFrom = hasOverride ? from : _manualFrom;
    final queryTo = hasOverride ? to : _manualTo;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await widget.api.adminStats(from: queryFrom, to: queryTo);
      final parsedRange = _parseRange(data);
      if (!mounted) return;
      setState(() {
        _stats = data;
        _range = parsedRange;
        _loading = false;
      });
      _rebuildComplaints();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadProducts() async {
    try {
      final products = await _productService.loadProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _productByArticle = {
          for (final p in products)
            if (p.articleNumber.trim().isNotEmpty) p.articleNumber.trim(): p,
        };
      });
      _rebuildComplaints();
    } catch (_) {
      // We intentionally fail silently to avoid blocking the page when the
      // article catalog cannot be loaded (e.g. offline mode).
    }
  }

  DateTimeRange? _parseRange(Map<String, dynamic> data) {
    DateTime? parse(dynamic value) {
      if (value == null) return null;
      final s = value.toString().trim();
      if (s.isEmpty) return null;
      final parts = s.split('-');
      if (parts.length < 3) return null;
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y == null || m == null || d == null) return null;
      return DateTime(y, m, d);
    }

    final from = parse(data['from']);
    final to = parse(data['to']);
    if (from == null || to == null) return null;
    return DateTimeRange(start: from, end: to);
  }

  void _rebuildComplaints() {
    if (_stats == null) return;
    final audit = _parseAuditEntries();
    final enriched = audit.map((entry) {
      final product = _matchProduct(entry.article);
      final mdrGroup = _deriveMdrGroup(product, entry.article);
      final productGroup = _deriveProductGroup(product);
      final articleNumber = _extractArticleNumber(entry.article);
      final articleLabel = _deriveArticleLabel(entry, product, articleNumber);
      final effectiveCountry = entry.country.isEmpty ? 'Unbekannt' : entry.country;
      return _EnrichedComplaint(
        entry: entry,
        product: product,
        mdrGroup: mdrGroup,
        productGroup: productGroup,
        articleNumber: articleNumber,
        articleLabel: articleLabel,
        country: effectiveCountry,
        batch: entry.batch,
      );
    }).toList();

    setState(() {
      _enrichedComplaints = enriched;
    });
    _applyFilters();
  }

  void _applyFilters() {
    var filtered = List<_EnrichedComplaint>.from(_enrichedComplaints);
    if (_selectedMdrGroup != null && _selectedMdrGroup!.isNotEmpty) {
      filtered = filtered.where((c) => c.mdrGroup == _selectedMdrGroup).toList();
    }
    if (_selectedCountry != null && _selectedCountry!.isNotEmpty) {
      filtered = filtered.where((c) => c.country == _selectedCountry).toList();
    }
    if (_selectedCustomer != null && _selectedCustomer!.isNotEmpty) {
      filtered = filtered
          .where((c) => c.entry.customer.toLowerCase() == _selectedCustomer!.toLowerCase())
          .toList();
    }
    if (_selectedProductGroup != null && _selectedProductGroup!.isNotEmpty) {
      filtered = filtered.where((c) => c.productGroup == _selectedProductGroup).toList();
    }

    setState(() {
      _visibleComplaints = filtered;
    });
  }

  String _deriveMdrGroup(DfsProduct? product, String? rawArticle) {
    const fallback = 'unbekannt (ggf. Dentallabor)';

    String? fromArticle(String? article) {
      if (article == null || article.trim().isEmpty) return null;
      final upper = article.toUpperCase();
      final match = RegExp(r'MDR-TD\s*\d+').firstMatch(upper);
      if (match != null) {
        final label = article.substring(match.start).trim();
        if (label.isNotEmpty) return label;
        final code = match.group(0)!.replaceAll(RegExp(r'\s+'), '-');
        return code;
      }
      if (upper.contains('DENTAL')) return 'Dental Lab';
      return null;
    }

    if (product == null) {
      return fromArticle(rawArticle) ?? fallback;
    }

    final label = product.tdNumberAndName.trim();
    if (label.toUpperCase().startsWith('MDR-TD')) return label;

    final productGroup = product.productGroup.trim().toLowerCase();
    if (productGroup.contains('dental')) return 'Dental Lab';
    return 'Sonstiges';
  }

  String _deriveProductGroup(DfsProduct? product) {
    final fallback = 'Sonstige Produkte';
    if (product == null) return fallback;
    final label = product.productGroup.trim();
    return label.isEmpty ? fallback : label;
  }

  String _deriveArticleLabel(_AuditEntry entry, DfsProduct? product, String? articleNumber) {
    if (product != null) {
      final number = product.articleNumber.trim();
      final name = product.productName.trim();
      if (number.isNotEmpty && name.isNotEmpty) return '$number · $name';
      if (name.isNotEmpty) return name;
      if (number.isNotEmpty) return number;
    }
    if (articleNumber != null && articleNumber.isNotEmpty) return articleNumber;
    return entry.article ?? 'Unbekannt';
  }

  String? _extractArticleNumber(String? article) {
    if (article == null || article.trim().isEmpty) return null;
    final match = RegExp(r'\d{4,}').firstMatch(article);
    return match?.group(0);
  }

  DfsProduct? _matchProduct(String? article) {
    final articleNumber = _extractArticleNumber(article);
    if (articleNumber != null && _productByArticle.containsKey(articleNumber)) {
      return _productByArticle[articleNumber];
    }
    final normalized = (article ?? '').toLowerCase().trim();
    if (normalized.isEmpty) return null;
    try {
      return _products.firstWhere(
        (p) =>
            p.productName.toLowerCase() == normalized ||
            p.articleNumber.toLowerCase() == normalized,
      );
    } catch (_) {}

    try {
      return _products.firstWhere((p) => normalized.contains(p.articleNumber.toLowerCase()));
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final initialStart = _range?.start ?? now.subtract(const Duration(days: 365));
    final initialEnd = _range?.end ?? now;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      helpText: 'Zeitraum wählen',
      cancelText: 'Abbrechen',
      confirmText: 'Anwenden',
    );
    if (picked != null) {
      await _loadStats(from: picked.start, to: picked.end);
    }
  }

  Future<void> _exportAuditReport(List<_AuditEntry> audit) async {
    if (_stats == null || audit.isEmpty || _exporting) return;
    setState(() => _exporting = true);
    try {
      final pdfBytes = await _buildAuditPdf(
        audit: audit,
        customers: _parseCustomerBuckets(),
        timeStats: _parseTimeToCloseStats(),
      );
      final fileName = _auditFileName();
      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: pdfBytes,
        ext: 'pdf',
        mimeType: MimeType.pdf,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audit-PDF wurde heruntergeladen.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _auditFileName() {
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return 'dfs_audit_$ts';
  }

  Future<Uint8List> _buildAuditPdf({
    required List<_AuditEntry> audit,
    required List<_CustomerBucket> customers,
    required _TimeToCloseStats? timeStats,
  }) async {
    final df = DateFormat('dd.MM.yyyy HH:mm');
    final doc = pw.Document();
    final total = (_stats?['total'] as num?)?.toInt() ?? 0;
    final open = (_stats?['open'] as num?)?.toInt() ?? 0;
    final rangeLabel = _rangeLabelText();
    final topCustomers = customers.take(5).toList();

    pw.Widget buildKpi(String label, String value) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.SizedBox(height: 4),
            pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );
    }

    String formatDays(double? value) {
      if (value == null) return '—';
      return '${value.toStringAsFixed(1)} Tage';
    }

    String customerLabel(_AuditEntry entry) {
      final base = entry.customer.isNotEmpty ? entry.customer : (entry.customerEmail ?? '—');
      final number = entry.customerNumber;
      if (number != null && number.isNotEmpty) {
        return '$base (Kundennr. $number)';
      }
      return base;
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return [
            pw.Text('Statistik- & Audit-Report', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Zeitraum: $rangeLabel'),
            pw.SizedBox(height: 16),
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                buildKpi('Reklamationen', NumberFormat.decimalPattern('de').format(total)),
                buildKpi('Offen', NumberFormat.decimalPattern('de').format(open)),
                buildKpi('Durchschnittliche Laufzeit', formatDays(timeStats?.averageDays)),
                buildKpi('Median', formatDays(timeStats?.medianDays)),
                buildKpi('90%-Perzentil', formatDays(timeStats?.p90Days)),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Text('Top-Kunden (nach Anzahl Reklamationen)', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            if (topCustomers.isEmpty)
              pw.Text('Keine Kundendaten verfügbar.')
            else
              pw.Table.fromTextArray(
                headers: ['Rang', 'Kunde', 'Tickets', 'Quote'],
                data: [
                  for (var i = 0; i < topCustomers.length; i++)
                    [
                      '${i + 1}',
                      topCustomers[i].label,
                      '${topCustomers[i].count}',
                      total == 0
                          ? '—'
                          : NumberFormat.decimalPercentPattern(locale: 'de', decimalDigits: 1)
                              .format(topCustomers[i].count / total),
                    ],
                ],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                cellStyle: const pw.TextStyle(fontSize: 9),
              ),
            pw.SizedBox(height: 18),
            pw.Text('Tickets', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Table.fromTextArray(
              headers: ['Ticket', 'Datum', 'Kunde', 'Land', 'Artikel', 'Segment', 'Status', 'Entscheid', 'Vertreter'],
                data: [
                  for (final entry in audit)
                    [
                      entry.ticket,
                      df.format(entry.createdAt),
                      customerLabel(entry),
                      entry.country,
                      entry.article?.isNotEmpty == true ? entry.article! : '—',
                    entry.segment?.isNotEmpty == true ? entry.segment! : '—',
                    entry.statusLabel,
                    entry.decisionLabel,
                    entry.repName?.isNotEmpty == true
                        ? entry.repName!
                        : (entry.repEmail?.isNotEmpty == true ? entry.repEmail! : '—'),
                  ],
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.1),
                1: const pw.FlexColumnWidth(1.4),
                2: const pw.FlexColumnWidth(2.0),
                3: const pw.FlexColumnWidth(1.1),
                4: const pw.FlexColumnWidth(1.5),
                5: const pw.FlexColumnWidth(1.2),
                6: const pw.FlexColumnWidth(1.2),
                7: const pw.FlexColumnWidth(1.2),
                8: const pw.FlexColumnWidth(1.4),
              },
            ),
          ];
        },
      ),
    );

    return doc.save();
  }


  void _showCountryDetails(List<_CountryBucket> countries, int total) {
    if (countries.isEmpty || !mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => _CountryDetailsDialog(
        countries: countries,
        total: total,
      ),
    );
  }

  void _showMdrLotDetails(String mdrGroup) {
    final lots = _buildLotsForMdrGroup(mdrGroup, _visibleComplaints);
    final articleLots = _buildArticleLotsForMdrGroup(mdrGroup, _visibleComplaints);
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Häufig betroffene Chargen'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
            child: (lots.isEmpty && articleLots.isEmpty)
                ? const Text('Für diese MDR-TD-Gruppe liegen keine Chargenangaben vor.')
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('MDR-TD-Gruppe: $mdrGroup'),
                        const SizedBox(height: 8),
                        Text(
                          'Top-Chargen inklusive zugeordneter Produktgruppe gemäß Artikelliste.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Theme.of(context).colorScheme.outline),
                        ),
                        if (lots.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text('Chargen-Häufigkeiten',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: math.min(lots.length, 12),
                            separatorBuilder: (_, __) => const Divider(height: 12),
                            itemBuilder: (context, index) {
                              if (index >= lots.length) return const SizedBox.shrink();
                              final lot = lots[index];
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text('Charge ${lot.batch}'),
                                subtitle: Text('Produktgruppe: ${lot.productGroup}'),
                                trailing: Text('${lot.count}×'),
                              );
                            },
                          ),
                        ],
                        if (articleLots.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text('Artikelnummern & Chargen aus Reklamationen',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: math.min(articleLots.length, 20),
                            separatorBuilder: (_, __) => const Divider(height: 12),
                            itemBuilder: (context, index) {
                              if (index >= articleLots.length) return const SizedBox.shrink();
                              final lot = articleLots[index];
                              final article = lot.articleNumber ?? lot.articleLabel;
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text('Artikel $article · Charge ${lot.batch}'),
                                subtitle: Text('Produktgruppe: ${lot.productGroup}'),
                                trailing: Text('${lot.count}×'),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Schließen')),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistik & KPIs'),
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            onPressed: _loading ? null : () => _loadStats(),
            icon: const Icon(Icons.refresh_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_error != null) {
            return _ErrorState(
              message: _error!,
              onRetry: () => _loadStats(),
            );
          }
          if (_stats == null) {
            return const _ErrorState(
              message: 'Keine Daten verfügbar.',
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: _buildContent(theme, constraints.maxWidth),
          );
        },
      ),
      bottomNavigationBar: LegalFooter(api: widget.api),
    );
  }

  Widget _buildContent(ThemeData theme, double maxWidth) {
    final complaints = _visibleComplaints;
    final total = complaints.length;
    final resolvedOpen = complaints.where((c) => c.isOpen).length;
    final months = _buildMonthBuckets(complaints);
    final decisions = _buildDecisionBuckets(complaints);
    final countries = _buildCountryBuckets(complaints);
    final reps = _parseRepBuckets();
    final products = _buildArticleBuckets(complaints);
    final productGroups = _buildProductGroupBuckets(complaints);
    final mdrGroups = _buildMdrBuckets(complaints);
    final customers = _buildCustomerBuckets(complaints);
    final timeStats = _parseTimeToCloseStats();
    final weekdays = _parseWeekdayBuckets();
    final hours = _parseHourBuckets();
    final audit = _parseAuditEntries();

    final isWide = maxWidth > 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRangeHeader(theme, audit),
        const SizedBox(height: 16),
        _buildFilterPanel(),
        const SizedBox(height: 20),
        _KpiWrap(
          children: [
            _KpiCard(
              icon: Icons.query_stats,
              title: 'Reklamationen',
              value: _formatNumber(total),
              subtitle: 'im ausgewählten Zeitraum',
            ),
            _KpiCard(
              icon: Icons.pending_actions_outlined,
              title: 'Offen',
              value: _formatNumber(resolvedOpen),
              subtitle: 'noch nicht abgeschlossen',
              accentColor: theme.colorScheme.tertiary,
            ),
            _KpiCard(
              icon: Icons.public_outlined,
              title: 'Länder',
              value: countries.isEmpty ? '—' : _formatNumber(countries.length),
              subtitle: 'mit Reklamationen',
            ),
            _KpiCard(
              icon: Icons.badge_outlined,
              title: 'Vertreter',
              value: reps.isEmpty ? '—' : _formatNumber(reps.length),
              subtitle: 'mit Feedback',
            ),
          ],
        ),
        const SizedBox(height: 26),
        if (isWide) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _MonthlyChart(data: months)),
              const SizedBox(width: 24),
              Expanded(child: _DecisionSection(decisions: decisions, total: total)),
            ],
          ),
        ] else ...[
          _MonthlyChart(data: months),
          const SizedBox(height: 24),
          _DecisionSection(decisions: decisions, total: total),
        ],
        const SizedBox(height: 24),
        if (isWide) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TopListSection(
                  title: 'MDR-TD-Gruppen',
                  icon: Icons.balance_outlined,
                  buckets: mdrGroups,
                  total: total,
                  emptyMessage: 'Keine MDR-TD-Zuordnung verfügbar',
                  onTapBucket: (bucket) => _showMdrLotDetails(bucket.label),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _TopListSection(
                  title: 'Produktbereiche',
                  icon: Icons.category_outlined,
                  buckets: productGroups,
                  total: total,
                  emptyMessage: 'Keine Produktbereiche erkannt',
                ),
              ),
            ],
          ),
        ] else ...[
          _TopListSection(
            title: 'MDR-TD-Gruppen',
            icon: Icons.balance_outlined,
            buckets: mdrGroups,
            total: total,
            emptyMessage: 'Keine MDR-TD-Zuordnung verfügbar',
            onTapBucket: (bucket) => _showMdrLotDetails(bucket.label),
          ),
          const SizedBox(height: 24),
          _TopListSection(
            title: 'Produktbereiche',
            icon: Icons.category_outlined,
            buckets: productGroups,
            total: total,
            emptyMessage: 'Keine Produktbereiche erkannt',
          ),
        ],
        const SizedBox(height: 24),
        if (isWide) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TopListSection(
                  title: 'Artikel (Reklamationshäufigkeit)',
                  icon: Icons.inventory_2_outlined,
                  buckets: products,
                  total: total,
                  emptyMessage: 'Keine Artikelzuordnung verfügbar',
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _CountrySection(
                  total: total,
                  countries: countries,
                  onViewDetails: () => _showCountryDetails(countries, total),
                ),
              ),
            ],
          ),
        ] else ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopListSection(
                title: 'Artikel (Reklamationshäufigkeit)',
                icon: Icons.inventory_2_outlined,
                buckets: products,
                total: total,
                emptyMessage: 'Keine Artikelzuordnung verfügbar',
              ),
              const SizedBox(height: 24),
              _CountrySection(
                total: total,
                countries: countries,
                onViewDetails: () => _showCountryDetails(countries, total),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        if (isWide) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _CustomerRankingSection(customers: customers, total: total)),
              const SizedBox(width: 24),
              Expanded(child: _RepSection(reps: reps)),
            ],
          ),
        ] else ...[
          _CustomerRankingSection(customers: customers, total: total),
          const SizedBox(height: 24),
          _RepSection(reps: reps),
        ],
        const SizedBox(height: 24),
        _TimeToCloseSection(stats: timeStats),
        const SizedBox(height: 24),
        _LoadPatternSection(weekdays: weekdays, hours: hours),
      ],
    );
  }

  String _rangeLabelText() {
    final df = DateFormat('dd.MM.yyyy');
    if (_range == null) {
      return 'Letzte 12 Monate';
    }
    return '${df.format(_range!.start)} – ${df.format(_range!.end)}';
  }

  bool get _hasActiveFilters =>
      (_selectedMdrGroup?.isNotEmpty ?? false) ||
      (_selectedCountry?.isNotEmpty ?? false) ||
      (_selectedCustomer?.isNotEmpty ?? false) ||
      (_selectedProductGroup?.isNotEmpty ?? false);

  List<String> _availableMdrGroups() {
    final set = <String>{};
    for (final c in _enrichedComplaints) {
      if (c.mdrGroup.isNotEmpty) set.add(c.mdrGroup);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<String> _availableCountries() {
    final set = <String>{};
    for (final c in _enrichedComplaints) {
      if (c.country.isNotEmpty) set.add(c.country);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<String> _availableCustomers() {
    final set = <String>{};
    for (final c in _enrichedComplaints) {
      final name = c.entry.customer.trim();
      if (name.isNotEmpty) set.add(name);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<String> _availableProductGroups() {
    final set = <String>{};
    for (final c in _enrichedComplaints) {
      if (c.productGroup.isNotEmpty) set.add(c.productGroup);
    }
    final list = set.toList()..sort();
    return list;
  }

  void _resetFilters() {
    setState(() {
      _selectedMdrGroup = null;
      _selectedCountry = null;
      _selectedCustomer = null;
      _selectedProductGroup = null;
    });
    _applyFilters();
  }

  Widget _buildFilterPanel() {
    final mdrOptions = _availableMdrGroups();
    final countryOptions = _availableCountries();
    final customerOptions = _availableCustomers();
    final productGroupOptions = _availableProductGroups();

    return _SectionCard(
      title: 'Filter & Fokus',
      icon: Icons.tune_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _FilterDropdown(
                label: 'MDR-TD-Gruppe',
                value: _selectedMdrGroup,
                options: mdrOptions,
                onChanged: (value) {
                  setState(() => _selectedMdrGroup = value);
                  _applyFilters();
                },
              ),
              _FilterDropdown(
                label: 'Land',
                value: _selectedCountry,
                options: countryOptions,
                onChanged: (value) {
                  setState(() => _selectedCountry = value);
                  _applyFilters();
                },
              ),
              _FilterDropdown(
                label: 'Kunde',
                value: _selectedCustomer,
                options: customerOptions,
                onChanged: (value) {
                  setState(() => _selectedCustomer = value);
                  _applyFilters();
                },
              ),
              _FilterDropdown(
                label: 'Produktbereich',
                value: _selectedProductGroup,
                options: productGroupOptions,
                onChanged: (value) {
                  setState(() => _selectedProductGroup = value);
                  _applyFilters();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _hasActiveFilters ? _resetFilters : null,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Filter zurücksetzen'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeHeader(ThemeData theme, List<_AuditEntry> audit) {
    final rangeLabel = _rangeLabelText();
    final infoRow = Row(
      children: [
        Icon(Icons.calendar_month_outlined, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Zeitraum'),
              Text(
                rangeLabel,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );

    final actions = Wrap(
      spacing: 12,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        FilledButton.tonalIcon(
          onPressed: _loading ? null : _pickRange,
          icon: const Icon(Icons.filter_list_outlined),
          label: const Text('Zeitraum wählen'),
        ),
        FilledButton.icon(
          onPressed: (_loading || _exporting || audit.isEmpty) ? null : () => _exportAuditReport(audit),
          icon: _exporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf_outlined),
          label: Text(_exporting ? 'Export läuft…' : 'Audit-PDF'),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              infoRow,
              const SizedBox(height: 12),
              actions,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: infoRow),
            const SizedBox(width: 12),
            actions,
          ],
        );
      },
    );
  }

  List<_DecisionBucket> _buildDecisionBuckets(List<_EnrichedComplaint> complaints) {
    final map = <String, int>{};
    String normalize(String input) {
      final raw = input.toLowerCase();
      if (raw.contains('angenommen')) return 'accepted';
      if (raw.contains('abgelehnt')) return 'rejected';
      if (raw.contains('offen')) return 'pending';
      if (raw.contains('pending')) return 'pending';
      return input;
    }

    for (final c in complaints) {
      final key = normalize(c.entry.decisionLabel);
      map[key] = (map[key] ?? 0) + 1;
    }

    return map.entries
        .map((e) => _DecisionBucket(decision: e.key, count: e.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  List<_MonthBucket> _buildMonthBuckets(List<_EnrichedComplaint> complaints) {
    final map = <String, int>{};
    for (final c in complaints) {
      final date = c.entry.createdAt;
      final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
      map[key] = (map[key] ?? 0) + 1;
    }

    return map.entries
        .map((e) => _MonthBucket(key: e.key, count: e.value))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  List<_CountryBucket> _buildCountryBuckets(List<_EnrichedComplaint> complaints) {
    final map = <String, int>{};
    for (final c in complaints) {
      final key = c.country.isEmpty ? 'Unbekannt' : c.country;
      map[key] = (map[key] ?? 0) + 1;
    }
    return map.entries
        .map((e) => _CountryBucket(
              country: e.key,
              count: e.value,
              code: e.key.trim().length == 2 ? e.key.trim() : null,
            ))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  List<_TopBucket> _buildArticleBuckets(List<_EnrichedComplaint> complaints) {
    final map = <String, int>{};
    for (final c in complaints) {
      final key = c.articleLabel.trim();
      if (key.isEmpty) continue;
      map[key] = (map[key] ?? 0) + 1;
    }
    return _mapToTopBuckets(map);
  }

  List<_TopBucket> _buildProductGroupBuckets(List<_EnrichedComplaint> complaints) {
    final map = <String, int>{};
    for (final c in complaints) {
      final key = c.productGroup.trim();
      if (key.isEmpty) continue;
      map[key] = (map[key] ?? 0) + 1;
    }
    return _mapToTopBuckets(map);
  }

  List<_TopBucket> _buildMdrBuckets(List<_EnrichedComplaint> complaints) {
    final map = <String, int>{};
    for (final c in complaints) {
      final key = c.mdrGroup.trim();
      if (key.isEmpty) continue;
      map[key] = (map[key] ?? 0) + 1;
    }
    return _mapToTopBuckets(map);
  }

  List<_LotBucket> _buildLotsForMdrGroup(String mdrGroup, List<_EnrichedComplaint> complaints) {
    final map = <String, _LotAggregation>{};
    for (final c in complaints) {
      if (c.mdrGroup != mdrGroup) continue;
      final batch = c.batch?.trim();
      if (batch == null || batch.isEmpty) continue;
      final productGroup = c.productGroup.trim().isEmpty ? 'Sonstige Produkte' : c.productGroup.trim();
      final agg = map.putIfAbsent(batch, () => _LotAggregation());
      agg.count++;
      agg.productGroups[productGroup] = (agg.productGroups[productGroup] ?? 0) + 1;
    }

    return map.entries.map((entry) {
      final topProductGroup = entry.value.productGroups.entries.reduce((a, b) => b.value > a.value ? b : a).key;
      return _LotBucket(batch: entry.key, count: entry.value.count, productGroup: topProductGroup);
    }).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  List<_ArticleLotBucket> _buildArticleLotsForMdrGroup(
    String mdrGroup,
    List<_EnrichedComplaint> complaints,
  ) {
    final map = <String, _ArticleLotAggregation>{};
    for (final c in complaints) {
      if (c.mdrGroup != mdrGroup) continue;
      final batch = c.batch?.trim();
      if (batch == null || batch.isEmpty) continue;
      final articleNumber = c.articleNumber?.trim();
      final displayArticle = (articleNumber == null || articleNumber.isEmpty)
          ? c.articleLabel.trim()
          : articleNumber;
      if (displayArticle.isEmpty) continue;
      final productGroup = c.productGroup.trim().isEmpty ? 'Sonstige Produkte' : c.productGroup.trim();
      final key = '$displayArticle|$batch';
      final agg = map.putIfAbsent(key, () => _ArticleLotAggregation(articleNumber, c.articleLabel, batch));
      agg.count++;
      agg.productGroups[productGroup] = (agg.productGroups[productGroup] ?? 0) + 1;
    }

    return map.entries.map((entry) {
      final agg = entry.value;
      final topProductGroup = agg.productGroups.entries.reduce((a, b) => b.value > a.value ? b : a).key;
      return _ArticleLotBucket(
        articleNumber: agg.articleNumber,
        articleLabel: agg.articleLabel,
        batch: agg.batch,
        productGroup: topProductGroup,
        count: agg.count,
      );
    }).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  List<_TopBucket> _mapToTopBuckets(Map<String, int> map) {
    return map.entries
        .map((e) => _TopBucket(label: e.key, count: e.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  List<_CustomerBucket> _buildCustomerBuckets(List<_EnrichedComplaint> complaints) {
    final map = <String, _CustomerBucket>{};
    for (final c in complaints) {
      final key = c.entry.customer.trim();
      if (key.isEmpty) continue;
      final existing = map[key];
      if (existing == null) {
        map[key] = _CustomerBucket(
          label: key,
          count: 1,
          email: c.entry.customerEmail,
          customerNumber: c.entry.customerNumber,
        );
      } else {
        map[key] = _CustomerBucket(
          label: existing.label,
          count: existing.count + 1,
          email: existing.email ?? c.entry.customerEmail,
          customerNumber: existing.customerNumber ?? c.entry.customerNumber,
        );
      }
    }

    return map.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  List<_DecisionBucket> _parseDecisionBuckets() {
    final raw = (_stats?['byDecision'] as List?) ?? const [];
    final out = <_DecisionBucket>[];
    for (final entry in raw) {
      if (entry is Map) {
        final decision = (entry['decision'] ?? '').toString();
        final count = (entry['count'] as num?)?.toInt() ?? 0;
        out.add(_DecisionBucket(decision: decision, count: count));
      }
    }
    int rank(String decision) {
      switch (decision) {
        case 'pending':
        case '':
          return 0;
        case 'accepted':
          return 1;
        case 'rejected':
          return 2;
        default:
          return 3;
      }
    }
    out.sort((a, b) {
      final r = rank(a.decision) - rank(b.decision);
      if (r != 0) return r;
      return a.decision.compareTo(b.decision);
    });
    return out;
  }

  List<_MonthBucket> _parseMonthBuckets() {
    final raw = (_stats?['byMonth'] as List?) ?? const [];
    final out = <_MonthBucket>[];
    for (final entry in raw) {
      if (entry is Map) {
        final key = (entry['month'] ?? '').toString();
        final count = (entry['count'] as num?)?.toInt() ?? 0;
        out.add(_MonthBucket(key: key, count: count));
      }
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  List<_CountryBucket> _parseCountryBuckets() {
    final raw = (_stats?['byCountry'] as List?) ?? const [];
    final out = <_CountryBucket>[];
    for (final entry in raw) {
      if (entry is Map) {
        final country = (entry['country'] ?? '').toString().trim();
        final count = (entry['count'] as num?)?.toInt() ?? 0;
        final code = (entry['countryCode'] ?? '').toString().trim();
        if (country.isNotEmpty) {
          out.add(_CountryBucket(
            country: country,
            code: code.isEmpty ? null : code,
            count: count,
          ));
        }
      }
    }
    out.sort((a, b) => b.count.compareTo(a.count));
    return out;
  }

  List<_RepBucket> _parseRepBuckets() {
    final raw = (_stats?['byRep'] as List?) ?? const [];
    final out = <_RepBucket>[];
    for (final entry in raw) {
      if (entry is Map) {
        final repId = (entry['repId'] ?? '').toString();
        if (repId.isEmpty) continue;
        final count = (entry['count'] as num?)?.toInt() ?? 0;
        final repName = (entry['repName'] ?? '').toString().trim();
        final repEmail = (entry['repEmail'] ?? '').toString().trim();
        out.add(_RepBucket(
          repId: repId,
          repName: repName.isEmpty ? null : repName,
          repEmail: repEmail.isEmpty ? null : repEmail,
          count: count,
        ));
      }
    }
    return out;
  }

  List<_CustomerBucket> _parseCustomerBuckets() {
    final raw = (_stats?['byCustomer'] as List?) ?? const [];
    final out = <_CustomerBucket>[];
    for (final entry in raw) {
      if (entry is Map) {
        final label = (entry['label'] ?? entry['customer'] ?? '').toString().trim();
        if (label.isEmpty) continue;
        final count = (entry['count'] as num?)?.toInt() ?? 0;
        final email = (entry['email'] ?? '').toString().trim();
        final customerNumber = (entry['customerNumber'] ?? '').toString().trim();
        out.add(_CustomerBucket(
          label: label,
          count: count,
          email: email.isEmpty ? null : email,
          customerNumber: customerNumber.isEmpty ? null : customerNumber,
        ));
      }
    }
    out.sort((a, b) {
      final primary = b.count.compareTo(a.count);
      if (primary != 0) return primary;
      return a.label.compareTo(b.label);
    });
    return out;
  }

  List<_TopBucket> _parseProductBuckets() {
    final raw = (_stats?['topProducts'] as List?) ?? const [];
    final out = <_TopBucket>[];
    for (final entry in raw) {
      if (entry is Map) {
        final label = (entry['label'] ?? '').toString().trim();
        if (label.isEmpty) continue;
        final count = (entry['count'] as num?)?.toInt() ?? 0;
        out.add(_TopBucket(label: label, count: count));
      }
    }
    return out;
  }

  List<_TopBucket> _parseLotBuckets() {
    final raw = (_stats?['topLots'] as List?) ?? const [];
    final out = <_TopBucket>[];
    for (final entry in raw) {
      if (entry is Map) {
        final label = (entry['label'] ?? '').toString().trim();
        if (label.isEmpty) continue;
        final count = (entry['count'] as num?)?.toInt() ?? 0;
        out.add(_TopBucket(label: label, count: count));
      }
    }
    return out;
  }

  _TimeToCloseStats? _parseTimeToCloseStats() {
    final map = (_stats?['timeToClose'] as Map?)?.cast<String, dynamic>();
    if (map == null || map.isEmpty) return null;
    return _TimeToCloseStats.fromJson(map);
  }

  List<_WeekdayBucket> _parseWeekdayBuckets() {
    final raw = (_stats?['loadByWeekday'] as List?) ?? const [];
    final out = <_WeekdayBucket>[];
    for (final entry in raw) {
      if (entry is Map) {
        final weekday = (entry['weekday'] as num?)?.toInt();
        if (weekday == null) continue;
        final count = (entry['count'] as num?)?.toInt() ?? 0;
        out.add(_WeekdayBucket(weekday: weekday, count: count));
      }
    }
    return out;
  }

  List<_HourBucket> _parseHourBuckets() {
    final raw = (_stats?['loadByHour'] as List?) ?? const [];
    final out = <_HourBucket>[];
    for (final entry in raw) {
      if (entry is Map) {
        final hour = (entry['hour'] as num?)?.toInt();
        if (hour == null) continue;
        final count = (entry['count'] as num?)?.toInt() ?? 0;
        out.add(_HourBucket(hour: hour, count: count));
      }
    }
    return out;
  }

  List<_AuditEntry> _parseAuditEntries() {
    final rawComplaints = (_stats?['complaints'] as List?) ?? const [];
    final rawAudit = (_stats?['audit'] as List?) ?? const [];

    final out = <_AuditEntry>[];
    if (rawComplaints.isNotEmpty) {
      final auditByTicket = <String, _AuditEntry>{};
      for (final entry in rawAudit) {
        if (entry is Map) {
          final parsed = _AuditEntry.fromJson(entry.cast<String, dynamic>());
          auditByTicket[parsed.ticket] = parsed;
        }
      }

      final seenTickets = <String>{};
      for (final entry in rawComplaints) {
        if (entry is! Map) continue;
        final parsed = _AuditEntry.fromJson(entry.cast<String, dynamic>());
        final fallback = auditByTicket[parsed.ticket];
        final merged = fallback == null ? parsed : _mergeAuditEntries(primary: parsed, secondary: fallback);
        out.add(merged);
        seenTickets.add(parsed.ticket);
      }

      for (final entry in auditByTicket.values) {
        if (!seenTickets.contains(entry.ticket)) {
          out.add(entry);
        }
      }
    } else {
      for (final entry in rawAudit) {
        if (entry is Map) {
          out.add(_AuditEntry.fromJson(entry.cast<String, dynamic>()));
        }
      }
    }
    return out;
  }

  _AuditEntry _mergeAuditEntries({required _AuditEntry primary, required _AuditEntry secondary}) {
    String chooseNonEmpty(String first, String fallback) {
      return first.trim().isNotEmpty ? first : fallback;
    }

    String? chooseOptional(String? first, String? fallback) {
      final cleaned = first?.trim();
      if (cleaned != null && cleaned.isNotEmpty) return first;
      final cleanedFallback = fallback?.trim();
      if (cleanedFallback != null && cleanedFallback.isNotEmpty) return fallback;
      return null;
    }

    return _AuditEntry(
      ticket: primary.ticket.isNotEmpty ? primary.ticket : secondary.ticket,
      createdAt: primary.createdAt != DateTime.fromMillisecondsSinceEpoch(0)
          ? primary.createdAt
          : secondary.createdAt,
      customer: chooseNonEmpty(primary.customer, secondary.customer),
      customerEmail: chooseOptional(primary.customerEmail, secondary.customerEmail),
      customerNumber: chooseOptional(primary.customerNumber, secondary.customerNumber),
      country: chooseNonEmpty(primary.country, secondary.country),
      article: chooseOptional(primary.article, secondary.article),
      segment: chooseOptional(primary.segment, secondary.segment),
      statusLabel: chooseNonEmpty(primary.statusLabel, secondary.statusLabel),
      decisionLabel: chooseNonEmpty(primary.decisionLabel, secondary.decisionLabel),
      repName: chooseOptional(primary.repName, secondary.repName),
      repEmail: chooseOptional(primary.repEmail, secondary.repEmail),
      batch: chooseOptional(primary.batch, secondary.batch),
    );
  }

  int _calcOpenFallback(List<_DecisionBucket> decisions, int total) {
    final pending = decisions
        .firstWhere((d) => d.decision == 'pending', orElse: () => const _DecisionBucket(decision: 'pending', count: 0))
        .count;
    if (pending > 0) return pending;
    final decided = decisions.fold<int>(0, (sum, bucket) {
      if (bucket.decision == 'pending') return sum;
      return sum + bucket.count;
    });
    return math.max(total - decided, 0);
  }

  String _formatNumber(int value) {
    final formatter = NumberFormat.decimalPattern('de');
    return formatter.format(value);
  }
}

class _FilterDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveOptions = ['Alle', ...options];

    return SizedBox(
      width: 260,
      child: DropdownButtonFormField<String>(
        value: value ?? 'Alle',
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.45),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        items: effectiveOptions
            .map(
              (option) => DropdownMenuItem<String>(
                value: option,
                child: Text(option),
              ),
            )
            .toList(),
        onChanged: (selected) {
          if (selected == 'Alle') {
            onChanged(null);
          } else {
            onChanged(selected);
          }
        },
      ),
    );
  }
}

class _MonthlyChart extends StatelessWidget {
  final List<_MonthBucket> data;
  const _MonthlyChart({required this.data});

  double _interval(double maxValue) {
    if (maxValue <= 5) return 1;
    final raw = (maxValue / 4).ceilToDouble();
    return raw == 0 ? 1 : raw;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (data.isEmpty) {
      return const _SectionCard(
        title: 'Reklamationen pro Monat',
        icon: Icons.bar_chart_outlined,
        child: _EmptyPlaceholder(message: 'Keine Monatsdaten verfügbar'),
      );
    }
    final maxY = data.fold<int>(0, (prev, e) => math.max(prev, e.count)).toDouble();
    final interval = _interval(maxY);
    final groups = data.asMap().entries.map((entry) {
      final index = entry.key;
      final bucket = entry.value;
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: bucket.count.toDouble(),
            width: 16,
            borderRadius: BorderRadius.circular(6),
            color: theme.colorScheme.primary,
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: maxY,
              color: theme.colorScheme.primary.withOpacity(0.08),
            ),
          ),
        ],
      );
    }).toList();

    return _SectionCard(
      title: 'Reklamationen pro Monat',
      icon: Icons.bar_chart_outlined,
      child: SizedBox(
        height: 260,
        child: BarChart(
          BarChartData(
            barTouchData: BarTouchData(enabled: true),
            barGroups: groups,
            gridData: FlGridData(
              show: true,
              horizontalInterval: interval,
              getDrawingHorizontalLine: (value) => FlLine(
                color: theme.dividerColor.withOpacity(0.2),
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  interval: interval,
                  getTitlesWidget: (value, meta) => SideTitleWidget(
                    axisSide: meta.axisSide,
                    space: 6,
                    child: Text(
                      value.toInt().toString(),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= data.length) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      axisSide: meta.axisSide,
                      space: 8,
                      child: Text(
                        data[index].label,
                        style: theme.textTheme.bodySmall,
                      ),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
          ),
        ),
      ),
    );
  }
}

class _DecisionSection extends StatelessWidget {
  final List<_DecisionBucket> decisions;
  final int total;
  const _DecisionSection({required this.decisions, required this.total});

  String _label(String decision) {
    switch (decision) {
      case 'accepted':
        return 'Angenommen';
      case 'rejected':
        return 'Abgelehnt';
      case 'pending':
      case '':
        return 'Entscheidung offen';
      default:
        return decision;
    }
  }

  Color _color(ThemeData theme, String decision) {
    switch (decision) {
      case 'accepted':
        return Colors.green.shade700;
      case 'rejected':
        return Colors.red.shade700;
      case 'pending':
      case '':
        return theme.colorScheme.primary;
      default:
        return theme.colorScheme.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (decisions.isEmpty) {
      return const _SectionCard(
        title: 'Entscheidungen',
        icon: Icons.rule_folder_outlined,
        child: _EmptyPlaceholder(message: 'Keine Entscheidungsdaten vorhanden'),
      );
    }
    final theme = Theme.of(context);
    return _SectionCard(
      title: 'Entscheidungen',
      icon: Icons.rule_folder_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < decisions.length; i++) ...[
            _DecisionRow(
              bucket: decisions[i],
              total: total,
              color: _color(theme, decisions[i].decision),
              label: _label(decisions[i].decision),
            ),
            if (i != decisions.length - 1) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _DecisionRow extends StatelessWidget {
  final _DecisionBucket bucket;
  final int total;
  final Color color;
  final String label;
  const _DecisionRow({
    required this.bucket,
    required this.total,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final share = total > 0 ? bucket.count / total : 0.0;
    final percent = (share * 100).toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Text('$percent %'),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: share,
            minHeight: 10,
            backgroundColor: theme.colorScheme.surfaceVariant,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 4),
        Text('${bucket.count} Fälle', style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _CountrySection extends StatelessWidget {
  final int total;
  final List<_CountryBucket> countries;
  final VoidCallback? onViewDetails;
  const _CountrySection({
    required this.total,
    required this.countries,
    this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    if (countries.isEmpty) {
      return const _SectionCard(
        title: 'Länder',
        icon: Icons.public_outlined,
        child: _EmptyPlaceholder(message: 'Keine Länderzuordnung verfügbar'),
      );
    }
    final theme = Theme.of(context);
    final formatter = NumberFormat.decimalPercentPattern(locale: 'de', decimalDigits: 1);
    return _SectionCard(
      title: 'Länder',
      icon: Icons.public_outlined,
      trailing: onViewDetails == null
          ? null
          : TextButton.icon(
              onPressed: onViewDetails,
              icon: const Icon(Icons.open_in_new_outlined),
              label: const Text('Alle anzeigen'),
            ),
      child: Column(
        children: [
          for (final bucket in countries.take(8))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _CountryAvatar(
                code: bucket.code ?? CountryGeography.resolveCode(bucket.country),
                fallback: bucket.abbreviation,
              ),
              title: Text(bucket.country),
              subtitle: total == 0
                  ? null
                  : Text(formatter.format(bucket.count / total)),
              trailing: Text(bucket.count.toString()),
            ),
        ],
      ),
    );
  }
}

class _CountryDetailsDialog extends StatelessWidget {
  final int total;
  final List<_CountryBucket> countries;
  const _CountryDetailsDialog({required this.total, required this.countries});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = List<_CountryBucket>.from(countries)
      ..sort((a, b) {
        final diff = b.count - a.count;
        if (diff != 0) return diff;
        return a.country.compareTo(b.country);
      });
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              child: Row(
                children: [
                  Icon(Icons.public_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Länder mit Reklamationen',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Schließen',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _CountryListPanel(total: total, countries: sorted),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountryListPanel extends StatelessWidget {
  final int total;
  final List<_CountryBucket> countries;
  const _CountryListPanel({required this.total, required this.countries});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatter = NumberFormat.decimalPercentPattern(locale: 'de', decimalDigits: 1);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              'Alle Länder',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Scrollbar(
              thumbVisibility: true,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemBuilder: (context, index) {
                  final bucket = countries[index];
                  final code = bucket.code ?? CountryGeography.resolveCode(bucket.country);
                  final label = code == null
                      ? bucket.country
                      : CountryGeography.labelForCode(code);
                  final share = total == 0 ? null : formatter.format(bucket.count / total);
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    leading: _CountryAvatar(code: code, fallback: bucket.abbreviation),
                    title: Text(label),
                    subtitle: share == null ? null : Text(share),
                    trailing: Text(_formatNumber(bucket.count)),
                  );
                },
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemCount: countries.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(int value) {
    final formatter = NumberFormat.decimalPattern('de');
    return formatter.format(value);
  }
}

class _CountryAvatar extends StatelessWidget {
  final String? code;
  final String fallback;
  const _CountryAvatar({required this.code, required this.fallback});

  @override
  Widget build(BuildContext context) {
    if (code == null) {
      return CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
        child: Text(
          fallback,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      );
    }
    return CountryFlag.fromCountryCode(
      code!.toLowerCase(),
      height: 28,
      width: 38,
      borderRadius: 6,
    );
  }
}


class _RepSection extends StatelessWidget {
  final List<_RepBucket> reps;
  const _RepSection({required this.reps});

  @override
  Widget build(BuildContext context) {
    if (reps.isEmpty) {
      return const _SectionCard(
        title: 'Vertreter',
        icon: Icons.badge_outlined,
        child: _EmptyPlaceholder(message: 'Noch keine Vertreter-Rückmeldungen'),
      );
    }
    final theme = Theme.of(context);
    return _SectionCard(
      title: 'Vertreter',
      icon: Icons.badge_outlined,
      child: Column(
        children: [
          for (final rep in reps.take(8))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.secondary.withOpacity(0.12),
                child: Text(rep.initials),
              ),
              title: Text(rep.displayName),
              subtitle: rep.repEmail == null ? null : Text(rep.repEmail!),
              trailing: Text('${rep.count}'),
            ),
        ],
      ),
    );
  }
}

class _CustomerRankingSection extends StatelessWidget {
  final List<_CustomerBucket> customers;
  final int total;
  const _CustomerRankingSection({required this.customers, required this.total});

  @override
  Widget build(BuildContext context) {
    if (customers.isEmpty) {
      return const _SectionCard(
        title: 'Reklamationsquote pro Kunde',
        icon: Icons.workspace_premium_outlined,
        child: _EmptyPlaceholder(message: 'Keine Kundendaten verfügbar'),
      );
    }
    final top = customers.take(10).toList(growable: false);
    return _SectionCard(
      title: 'Reklamationsquote pro Kunde',
      icon: Icons.workspace_premium_outlined,
      child: Column(
        children: [
          for (var i = 0; i < top.length; i++) ...[
            _CustomerRankTile(
              rank: i + 1,
              bucket: top[i],
              share: total == 0 ? null : (top[i].count / total),
            ),
            if (i != top.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _CustomerRankTile extends StatelessWidget {
  final int rank;
  final _CustomerBucket bucket;
  final double? share;
  const _CustomerRankTile({required this.rank, required this.bucket, this.share});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasContact = bucket.email != null && bucket.email!.isNotEmpty;
    final shareLabel = (share == null)
        ? null
        : NumberFormat.decimalPercentPattern(locale: 'de', decimalDigits: 1).format(share);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primary.withOpacity(0.08),
              child: Text('$rank', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bucket.label,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (bucket.customerNumber != null)
                    Text('Kundennr.: ${bucket.customerNumber}', style: theme.textTheme.bodySmall),
                  if (hasContact)
                    Text(bucket.email!, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: share?.clamp(0.0, 1.0) ?? 0,
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.surfaceVariant,
                    valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${bucket.count}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                if (shareLabel != null)
                  Text(shareLabel, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _TopListSection extends StatelessWidget {
  final List<_TopBucket> buckets;
  final int total;
  final String title;
  final IconData icon;
  final String emptyMessage;
  final ValueChanged<_TopBucket>? onTapBucket;

  const _TopListSection({
    required this.buckets,
    required this.total,
    required this.title,
    required this.icon,
    required this.emptyMessage,
    this.onTapBucket,
  });

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) {
      return _SectionCard(
        title: title,
        icon: icon,
        child: _EmptyPlaceholder(message: emptyMessage),
      );
    }
    final top = buckets.take(10).toList(growable: false);
    return _SectionCard(
      title: title,
      icon: icon,
      child: Column(
        children: [
          for (var i = 0; i < top.length; i++) ...[
            if (onTapBucket != null)
              InkWell(
                onTap: () => onTapBucket!(top[i]),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _TopRankTile(rank: i + 1, bucket: top[i], total: total),
                ),
              )
            else
              _TopRankTile(rank: i + 1, bucket: top[i], total: total),
            if (i != top.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _TopRankTile extends StatelessWidget {
  final int rank;
  final _TopBucket bucket;
  final int total;
  const _TopRankTile({required this.rank, required this.bucket, required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final share = total > 0 ? bucket.count / total : null;
    final shareLabel = (share == null)
        ? null
        : NumberFormat.decimalPercentPattern(locale: 'de', decimalDigits: 1).format(share);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: theme.colorScheme.secondary.withOpacity(0.12),
          child: Text('$rank', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                bucket.label,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: share?.clamp(0.0, 1.0) ?? 0,
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceVariant,
                valueColor: AlwaysStoppedAnimation(theme.colorScheme.secondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${bucket.count}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            if (shareLabel != null)
              Text(shareLabel, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      ],
    );
  }
}

class _TimeToCloseSection extends StatelessWidget {
  final _TimeToCloseStats? stats;
  const _TimeToCloseSection({required this.stats});

  String _format(double? value) {
    if (value == null) return '—';
    return '${value.toStringAsFixed(1)} Tage';
  }

  @override
  Widget build(BuildContext context) {
    if (stats == null || stats!.sampleSize == 0) {
      return const _SectionCard(
        title: 'Laufzeitstatistik',
        icon: Icons.schedule_outlined,
        child: _EmptyPlaceholder(message: 'Noch keine abgeschlossenen Tickets im Zeitraum'),
      );
    }
    final stat = stats!;
    return _SectionCard(
      title: 'Laufzeitstatistik',
      icon: Icons.schedule_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _TimeMetric(label: 'Durchschnitt', value: _format(stat.averageDays)),
              _TimeMetric(label: 'Median', value: _format(stat.medianDays)),
              _TimeMetric(label: '90%-Perzentil', value: _format(stat.p90Days)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.timelapse, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Long Runner > ${stat.thresholdDays} Tagen: ${stat.longRunnerOpen}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Stichprobe: ${stat.sampleSize} Tickets', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _TimeMetric extends StatelessWidget {
  final String label;
  final String value;
  const _TimeMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: theme.colorScheme.surfaceVariant,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _LoadPatternSection extends StatelessWidget {
  final List<_WeekdayBucket> weekdays;
  final List<_HourBucket> hours;
  const _LoadPatternSection({required this.weekdays, required this.hours});

  bool get _hasData =>
      weekdays.any((b) => b.count > 0) ||
      hours.any((b) => b.count > 0);

  @override
  Widget build(BuildContext context) {
    if (!_hasData) {
      return const _SectionCard(
        title: 'Reklamationslast nach Zeitpunkt',
        icon: Icons.access_time,
        child: _EmptyPlaceholder(message: 'Keine zeitlichen Muster verfügbar'),
      );
    }
    return _SectionCard(
      title: 'Reklamationslast nach Zeitpunkt',
      icon: Icons.access_time,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 220, child: _WeekdayChart(data: weekdays)),
          const SizedBox(height: 24),
          SizedBox(height: 220, child: _HourChart(data: hours)),
        ],
      ),
    );
  }
}

class _WeekdayChart extends StatelessWidget {
  final List<_WeekdayBucket> data;
  const _WeekdayChart({required this.data});

  static const _order = [1, 2, 3, 4, 5, 6, 0];
  static const _labels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  List<_WeekdayBucket> _normalized() {
    final map = {for (final bucket in data) bucket.weekday: bucket.count};
    return List.generate(_order.length, (index) {
      final weekday = _order[index];
      return _WeekdayBucket(weekday: weekday, count: map[weekday] ?? 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = _normalized();
    final maxY = normalized.fold<int>(0, (prev, e) => math.max(prev, e.count)).toDouble();
    final normalizedMax = math.max(maxY, 1).toDouble();
    final interval = maxY <= 5 ? 1.0 : (maxY / 4).ceilToDouble();
    final groups = normalized.asMap().entries.map((entry) {
      final index = entry.key;
      final bucket = entry.value;
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: bucket.count.toDouble(),
            width: 16,
            borderRadius: BorderRadius.circular(6),
            color: theme.colorScheme.primary,
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: normalizedMax,
              color: theme.colorScheme.primary.withOpacity(0.08),
            ),
          ),
        ],
      );
    }).toList();

    return BarChart(
      BarChartData(
        barTouchData: BarTouchData(enabled: true),
        barGroups: groups,
        gridData: FlGridData(
          show: true,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (value) => FlLine(
            color: theme.dividerColor.withOpacity(0.2),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: interval,
              reservedSize: 32,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                axisSide: meta.axisSide,
                space: 6,
                child: Text(value.toInt().toString(), style: theme.textTheme.bodySmall),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= _labels.length) return const SizedBox.shrink();
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  space: 8,
                  child: Text(_labels[index], style: theme.textTheme.bodySmall),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _HourChart extends StatelessWidget {
  final List<_HourBucket> data;
  const _HourChart({required this.data});

  List<_HourBucket> _normalized() {
    final map = {for (final bucket in data) bucket.hour: bucket.count};
    return List.generate(24, (index) => _HourBucket(hour: index, count: map[index] ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = _normalized();
    final maxY = normalized.fold<int>(0, (prev, e) => math.max(prev, e.count)).toDouble();
    final normalizedMax = math.max(maxY, 1).toDouble();
    final interval = maxY <= 5 ? 1.0 : (maxY / 4).ceilToDouble();
    final spots = normalized
        .map((bucket) => FlSpot(bucket.hour.toDouble(), bucket.count.toDouble()))
        .toList();
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 23,
        minY: 0,
        maxY: normalizedMax,
        gridData: FlGridData(
          show: true,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (value) => FlLine(
            color: theme.dividerColor.withOpacity(0.2),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: interval,
              reservedSize: 32,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                axisSide: meta.axisSide,
                space: 6,
                child: Text(value.toInt().toString(), style: theme.textTheme.bodySmall),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final hour = value.toInt();
                if (hour % 4 != 0) return const SizedBox.shrink();
                final label = '${hour.toString().padLeft(2, '0')}h';
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  space: 6,
                  child: Text(label, style: theme.textTheme.bodySmall),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            barWidth: 3,
            color: theme.colorScheme.secondary,
            belowBarData: BarAreaData(
              show: true,
              color: theme.colorScheme.secondary.withOpacity(0.2),
            ),
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _KpiWrap extends StatelessWidget {
  final List<Widget> children;
  const _KpiWrap({required this.children});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 18,
      runSpacing: 18,
      children: children,
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color? accentColor;
  const _KpiCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accentColor ?? theme.colorScheme.primary;
    return SizedBox(
      width: 260,
      child: Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: color.withOpacity(0.12),
                child: Icon(icon, color: color),
              ),
              const SizedBox(height: 12),
              Text(subtitle, style: theme.textTheme.labelMedium),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(title, style: theme.textTheme.titleSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPlaceholder extends StatelessWidget {
  final String message;
  const _EmptyPlaceholder({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.insights_outlined, color: theme.colorScheme.outline),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const _ErrorState({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 48),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Erneut versuchen')),
          ],
        ],
      ),
    );
  }
}

class _EnrichedComplaint {
  final _AuditEntry entry;
  final DfsProduct? product;
  final String mdrGroup;
  final String productGroup;
  final String? articleNumber;
  final String articleLabel;
  final String country;
  final String? batch;

  _EnrichedComplaint({
    required this.entry,
    required this.product,
    required this.mdrGroup,
    required this.productGroup,
    required this.articleNumber,
    required this.articleLabel,
    required this.country,
    required this.batch,
  });

  bool get isOpen {
    final normalized = entry.statusLabel.toLowerCase();
    if (normalized.contains('abgeschlossen')) return false;
    if (normalized.contains('closed')) return false;
    return true;
  }
}

class _DecisionBucket {
  final String decision;
  final int count;
  const _DecisionBucket({required this.decision, required this.count});
}

class _MonthBucket {
  final String key;
  final int count;
  late final DateTime date;
  late final String label;

  _MonthBucket({required this.key, required this.count}) {
    final parts = key.split('-');
    DateTime parsed;
    if (parts.length >= 2) {
      final y = int.tryParse(parts[0]) ?? 1970;
      final m = int.tryParse(parts[1]) ?? 1;
      parsed = DateTime(y, m, 1);
    } else {
      parsed = DateTime(1970, 1, 1);
    }
    date = parsed;
    label = DateFormat('MMM yy', 'de').format(parsed);
  }
}

class _CustomerBucket {
  final String label;
  final int count;
  final String? email;
  final String? customerNumber;
  const _CustomerBucket({
    required this.label,
    required this.count,
    this.email,
    this.customerNumber,
  });
}

class _TopBucket {
  final String label;
  final int count;
  const _TopBucket({required this.label, required this.count});
}

class _LotBucket {
  final String batch;
  final int count;
  final String productGroup;

  const _LotBucket({required this.batch, required this.count, required this.productGroup});
}

class _ArticleLotBucket {
  final String? articleNumber;
  final String articleLabel;
  final String batch;
  final String productGroup;
  final int count;

  const _ArticleLotBucket({
    required this.articleNumber,
    required this.articleLabel,
    required this.batch,
    required this.productGroup,
    required this.count,
  });
}

class _LotAggregation {
  int count = 0;
  final Map<String, int> productGroups = {};
}

class _ArticleLotAggregation {
  final String? articleNumber;
  final String articleLabel;
  final String batch;
  int count = 0;
  final Map<String, int> productGroups = {};

  _ArticleLotAggregation(this.articleNumber, this.articleLabel, this.batch);
}

class _CountryBucket {
  final String country;
  final int count;
  final String? code;
  _CountryBucket({required this.country, this.code, required this.count});

  String get abbreviation {
    if (code != null && code!.trim().length == 2) return code!.toUpperCase();
    if (country.length == 2) return country.toUpperCase();
    final parts = country.trim().split(' ');
    if (parts.length == 1) return country.substring(0, math.min(2, country.length)).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _RepBucket {
  final String repId;
  final String? repName;
  final String? repEmail;
  final int count;
  const _RepBucket({
    required this.repId,
    required this.repName,
    required this.repEmail,
    required this.count,
  });

  String get displayName => repName ?? repId;
  String get initials {
    if (repName != null && repName!.trim().isNotEmpty) {
      final parts = repName!.trim().split(' ');
      if (parts.length == 1) {
        return parts.first.substring(0, math.min(2, parts.first.length)).toUpperCase();
      }
      return (parts.first[0] + parts.last[0]).toUpperCase();
    }
    return repId.substring(0, math.min(2, repId.length)).toUpperCase();
  }
}

class _TimeToCloseStats {
  final double? averageDays;
  final double? medianDays;
  final double? p90Days;
  final int sampleSize;
  final int longRunnerOpen;
  final int thresholdDays;

  const _TimeToCloseStats({
    required this.averageDays,
    required this.medianDays,
    required this.p90Days,
    required this.sampleSize,
    required this.longRunnerOpen,
    required this.thresholdDays,
  });

  factory _TimeToCloseStats.fromJson(Map<String, dynamic> json) {
    double? _double(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    int _int(dynamic value) {
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return _TimeToCloseStats(
      averageDays: _double(json['averageDays']),
      medianDays: _double(json['medianDays']),
      p90Days: _double(json['p90Days']),
      sampleSize: _int(json['sampleSize']),
      longRunnerOpen: _int(json['longRunnerOpen']),
      thresholdDays: _int(json['thresholdDays']),
    );
  }
}

class _WeekdayBucket {
  final int weekday;
  final int count;
  const _WeekdayBucket({required this.weekday, required this.count});
}

class _HourBucket {
  final int hour;
  final int count;
  const _HourBucket({required this.hour, required this.count});
}

class _AuditEntry {
  final String ticket;
  final DateTime createdAt;
  final String customer;
  final String? customerEmail;
  final String? customerNumber;
  final String country;
  final String? article;
  final String? segment;
  final String statusLabel;
  final String decisionLabel;
  final String? repName;
  final String? repEmail;
  final String? batch;

  _AuditEntry({
    required this.ticket,
    required this.createdAt,
    required this.customer,
    required this.customerEmail,
    required this.customerNumber,
    required this.country,
    required this.article,
    required this.segment,
    required this.statusLabel,
    required this.decisionLabel,
    required this.repName,
    required this.repEmail,
    required this.batch,
  });

  factory _AuditEntry.fromJson(Map<String, dynamic> json) {
    DateTime _ts(dynamic value) {
      if (value is num) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: false);
      }
      if (value is String) {
        final trimmed = value.trim();
        final parsedInt = int.tryParse(trimmed);
        if (parsedInt != null) {
          return DateTime.fromMillisecondsSinceEpoch(parsedInt, isUtc: false);
        }
        final parsed = DateTime.tryParse(trimmed);
        if (parsed != null) return parsed;
      }
      return DateTime.now();
    }

    String? _optional(dynamic value) {
      final s = (value ?? '').toString().trim();
      return s.isEmpty ? null : s;
    }

    final batch = _optional(json['batch']) ??
        _optional(json['batchNumber']) ??
        _optional(json['batch_number']) ??
        _optional(json['batch_no']) ??
        _optional(json['batchNo']) ??
        _optional(json['lot']) ??
        _optional(json['lotNumber']) ??
        _optional(json['lot_no']) ??
        _optional(json['lotNo']) ??
        _optional(json['lotId']) ??
        _optional(json['lot_id']) ??
        _optional(json['charge']) ??
        _optional(json['chargeNumber']) ??
        _optional(json['charge_number']) ??
        _optional(json['chargeNo']) ??
        _optional(json['charge_no']);

    final article = _optional(json['article']) ??
        _optional(json['articleNumber']) ??
        _optional(json['article_no']) ??
        _optional(json['articleNo']) ??
        _optional(json['articleNr']) ??
        _optional(json['article_nr']) ??
        _optional(json['itemNumber']) ??
        _optional(json['item_no']) ??
        _optional(json['itemNo']) ??
        _optional(json['item_nr']) ??
        _optional(json['productNumber']) ??
        _optional(json['product_no']) ??
        _optional(json['productNo']) ??
        _optional(json['article_id']);

    return _AuditEntry(
      ticket: (json['ticket'] ?? '').toString(),
      createdAt: _ts(json['createdAt']),
      customer: (json['customer'] ?? '').toString(),
      customerEmail: _optional(json['customerEmail']),
      customerNumber: _optional(json['customerNumber']),
      country: (json['country'] ?? '').toString(),
      article: article,
      segment: _optional(json['segment']),
      statusLabel: (json['statusLabel'] ?? '').toString(),
      decisionLabel: (json['decisionLabel'] ?? '').toString(),
      repName: _optional(json['repName']),
      repEmail: _optional(json['repEmail']),
      batch: batch,
    );
  }
}
