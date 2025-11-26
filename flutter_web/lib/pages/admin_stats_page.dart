// lib/pages/admin_stats_page.dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:country_flags/country_flags.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:file_saver/file_saver.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../api/client.dart';
import '../data/country_geography.dart';
import '../widgets/legal_footer.dart';

class AdminStatsPage extends StatefulWidget {
  final ApiClient api;
  const AdminStatsPage({super.key, required this.api});

  @override
  State<AdminStatsPage> createState() => _AdminStatsPageState();
}

class _AdminStatsPageState extends State<AdminStatsPage> {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;
  DateTimeRange? _range;
  DateTime? _manualFrom;
  DateTime? _manualTo;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
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
    final total = (_stats?['total'] as num?)?.toInt() ?? 0;
    final open = (_stats?['open'] as num?)?.toInt();
    final decisions = _parseDecisionBuckets();
    final resolvedOpen = open ?? _calcOpenFallback(decisions, total);
    final months = _parseMonthBuckets();
    final countries = _parseCountryBuckets();
    final reps = _parseRepBuckets();
    final products = _parseProductBuckets();
    final lots = _parseLotBuckets();
    final customers = _parseCustomerBuckets();
    final timeStats = _parseTimeToCloseStats();
    final weekdays = _parseWeekdayBuckets();
    final hours = _parseHourBuckets();
    final audit = _parseAuditEntries();

    final isWide = maxWidth > 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRangeHeader(theme, audit),
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
                child: _CountrySection(
                  total: total,
                  countries: countries,
                  onViewDetails: () => _showCountryDetails(countries, total),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(child: _RepSection(reps: reps)),
            ],
          ),
        ] else ...[
          _CountrySection(
            total: total,
            countries: countries,
            onViewDetails: () => _showCountryDetails(countries, total),
          ),
          const SizedBox(height: 24),
          _RepSection(reps: reps),
        ],
        const SizedBox(height: 24),
        if (isWide) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _CustomerRankingSection(customers: customers, total: total)),
              const SizedBox(width: 24),
              Expanded(child: _TimeToCloseSection(stats: timeStats)),
            ],
          ),
        ] else ...[
          _CustomerRankingSection(customers: customers, total: total),
          const SizedBox(height: 24),
          _TimeToCloseSection(stats: timeStats),
        ],
        const SizedBox(height: 24),
        if (isWide) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TopListSection(
                  title: 'Top-Produkte (nach Reklamationen)',
                  icon: Icons.inventory_2_outlined,
                  buckets: products,
                  total: total,
                  emptyMessage: 'Keine Produktdaten verfügbar',
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _TopListSection(
                  title: 'Top-LOTs',
                  icon: Icons.qr_code_2_outlined,
                  buckets: lots,
                  total: total,
                  emptyMessage: 'Keine LOT-Daten verfügbar',
                ),
              ),
            ],
          ),
        ] else ...[
          _TopListSection(
            title: 'Top-Produkte (nach Reklamationen)',
            icon: Icons.inventory_2_outlined,
            buckets: products,
            total: total,
            emptyMessage: 'Keine Produktdaten verfügbar',
          ),
          const SizedBox(height: 24),
          _TopListSection(
            title: 'Top-LOTs',
            icon: Icons.qr_code_2_outlined,
            buckets: lots,
            total: total,
            emptyMessage: 'Keine LOT-Daten verfügbar',
          ),
        ],
        const SizedBox(height: 24),
        _LoadPatternSection(weekdays: weekdays, hours: hours),
        const SizedBox(height: 24),
        const _CustomKpiBuilderPanel(),
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
    final raw = (_stats?['audit'] as List?) ?? const [];
    final out = <_AuditEntry>[];
    for (final entry in raw) {
      if (entry is Map) {
        out.add(_AuditEntry.fromJson(entry.cast<String, dynamic>()));
      }
    }
    return out;
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

  const _TopListSection({
    required this.buckets,
    required this.total,
    required this.title,
    required this.icon,
    required this.emptyMessage,
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

class _CustomKpiBuilderPanel extends StatefulWidget {
  const _CustomKpiBuilderPanel();

  @override
  State<_CustomKpiBuilderPanel> createState() => _CustomKpiBuilderPanelState();
}

class _CustomKpiBuilderPanelState extends State<_CustomKpiBuilderPanel> {
  final _nameController = TextEditingController(text: 'Reklamationsquote');
  final _formulaController = TextEditingController(text: 'complaints / sales * 100');
  final _manualSalesController = TextEditingController();
  final _engine = _FormulaEngine();
  final Set<String> _selectedFields = {'complaints', 'sales'};
  final List<_CustomKpiDefinition> _definitions = [];

  String _dimension = 'Land';
  _KpiChartType _chartType = _KpiChartType.bar;
  _KpiTimeframe _timeframe = _KpiTimeframe.last12Months;
  String _region = 'Alle Regionen';
  String _productGroup = 'Alle Produktgruppen';
  bool _pinToDashboard = true;
  bool _publishLive = true;
  _CustomKpiDefinition? _activeDefinition;

  @override
  void dispose() {
    _nameController.dispose();
    _formulaController.dispose();
    _manualSalesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draftDefinition = _CustomKpiDefinition(
      name: _nameController.text.trim().isEmpty
          ? 'Unbenannter KPI'
          : _nameController.text.trim(),
      formula: _formulaController.text.trim(),
      fields: Set.of(_selectedFields),
      dimension: _dimension,
      chartType: _chartType,
      timeframe: _timeframe,
      region: _region,
      productGroup: _productGroup,
      pinned: _pinToDashboard,
      status: _publishLive ? _KpiStatus.live : _KpiStatus.draft,
      version: _nextVersionForName(_nameController.text.trim()),
      updatedAt: DateTime.now(),
    );

    final previewPoints = _buildPreviewPoints(draftDefinition);

    return _SectionCard(
      title: 'Custom KPI Builder',
      icon: Icons.auto_graph_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Beliebige KPIs kombinieren, validieren und als Widgets oder Exporte bereitstellen.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _buildFieldSelector(theme),
          const SizedBox(height: 12),
          _buildFormulaEditor(theme),
          const SizedBox(height: 12),
          _buildFilters(theme),
          const SizedBox(height: 12),
          _buildActions(theme, previewPoints),
          const SizedBox(height: 12),
          _KpiPreviewBoard(
            definition: draftDefinition,
            points: previewPoints,
            activeDefinition: _activeDefinition,
          ),
          const SizedBox(height: 12),
          if (_definitions.isNotEmpty) _buildSavedDefinitions(theme),
        ],
      ),
    );
  }

  Widget _buildFieldSelector(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Datenfelder',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _availableFields.map((field) {
            final selected = _selectedFields.contains(field.key);
            return FilterChip(
              label: Text(field.label),
              tooltip: field.description,
              selected: selected,
              onSelected: (value) {
                setState(() {
                  if (value) {
                    _selectedFields.add(field.key);
                  } else {
                    _selectedFields.remove(field.key);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildFormulaEditor(ThemeData theme) {
    final manualSales = _manualSalesValue();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Formel & Darstellung',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'KPI-Name',
                  hintText: 'z. B. Reklamationsquote',
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<_KpiChartType>(
              value: _chartType,
              onChanged: (value) => setState(() => _chartType = value ?? _chartType),
              items: const [
                DropdownMenuItem(value: _KpiChartType.bar, child: Text('Bar')),
                DropdownMenuItem(value: _KpiChartType.line, child: Text('Line')),
                DropdownMenuItem(value: _KpiChartType.pie, child: Text('Pie')),
                DropdownMenuItem(value: _KpiChartType.heatmap, child: Text('Heatmap')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _formulaController,
          decoration: const InputDecoration(
            labelText: 'Formel',
            hintText: 'complaints / sales * 100',
            prefixIcon: Icon(Icons.functions_outlined),
            helperText: 'Felder: complaints, sales, revenue, units, returns',
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _formulaSuggestions.map((suggestion) {
              return ActionChip(
                avatar: const Icon(Icons.lightbulb_outline, size: 18),
                label: Text(suggestion.name),
                tooltip: suggestion.description,
                onPressed: () {
                  setState(() {
                    _nameController.text = suggestion.name;
                    _formulaController.text = suggestion.formula;
                    _selectedFields
                      ..clear()
                      ..addAll(suggestion.fields);
                  });
                },
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _manualSalesController,
          decoration: InputDecoration(
            labelText: 'Eigene Verkäufe (optional)',
            hintText: 'z. B. 1250',
            prefixIcon: const Icon(Icons.edit_outlined),
            helperText: 'Überschreibt die sales-Variable in der Formel mit einem eigenen Wert.',
            suffixIcon: manualSales != null
                ? Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Chip(
                      label: Text('${manualSales.toStringAsFixed(0)}'),
                      avatar: const Icon(Icons.check_circle_outline, size: 16),
                    ),
                  )
                : null,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          children: [
            DropdownButton<String>(
              value: _dimension,
              onChanged: (value) => setState(() => _dimension = value ?? _dimension),
              items: const [
                DropdownMenuItem(value: 'Land', child: Text('Land')),
                DropdownMenuItem(value: 'Produktgruppe', child: Text('Produktgruppe')),
                DropdownMenuItem(value: 'Kunde', child: Text('Kunde')),
                DropdownMenuItem(value: 'Monat', child: Text('Zeitraum (Monat)')),
              ],
            ),
            FilterChip(
              label: const Text('Dashboard-Widget'),
              selected: _pinToDashboard,
              onSelected: (value) => setState(() => _pinToDashboard = value),
            ),
            FilterChip(
              label: const Text('Veröffentlichen (Live)'),
              selected: _publishLive,
              onSelected: (value) => setState(() => _publishLive = value),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilters(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Filter & Parameter',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            DropdownButton<_KpiTimeframe>(
              value: _timeframe,
              onChanged: (value) => setState(() => _timeframe = value ?? _timeframe),
              items: const [
                DropdownMenuItem(
                  value: _KpiTimeframe.last30Days,
                  child: Text('Letzte 30 Tage'),
                ),
                DropdownMenuItem(
                  value: _KpiTimeframe.last90Days,
                  child: Text('Letzte 90 Tage'),
                ),
                DropdownMenuItem(
                  value: _KpiTimeframe.last12Months,
                  child: Text('Letzte 12 Monate'),
                ),
                DropdownMenuItem(
                  value: _KpiTimeframe.all,
                  child: Text('Alle Daten'),
                ),
              ],
            ),
            DropdownButton<String>(
              value: _region,
              onChanged: (value) => setState(() => _region = value ?? _region),
              items: const [
                DropdownMenuItem(value: 'Alle Regionen', child: Text('Alle Regionen')),
                DropdownMenuItem(value: 'EU', child: Text('Europa')),
                DropdownMenuItem(value: 'NA', child: Text('Nordamerika')),
                DropdownMenuItem(value: 'MEA', child: Text('Nahost/Afrika')),
              ],
            ),
            DropdownButton<String>(
              value: _productGroup,
              onChanged: (value) => setState(() => _productGroup = value ?? _productGroup),
              items: const [
                DropdownMenuItem(value: 'Alle Produktgruppen', child: Text('Alle Produktgruppen')),
                DropdownMenuItem(value: 'Sensorik', child: Text('Sensorik')),
                DropdownMenuItem(value: 'Steuerung', child: Text('Steuerung')),
                DropdownMenuItem(value: 'Sicherheit', child: Text('Sicherheit')),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActions(ThemeData theme, List<_KpiPreviewPoint> previewPoints) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.spaceBetween,
      children: [
        FilledButton.icon(
          icon: const Icon(Icons.save_outlined),
          onPressed: () {
            final error = _engine.validate(_formulaController.text.trim(), _selectedFields);
            if (error != null) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('Formel ungültig: $error')));
              return;
            }
            setState(() {
              final def = _CustomKpiDefinition(
                name: _nameController.text.trim().isEmpty
                    ? 'Unbenannter KPI'
                    : _nameController.text.trim(),
                formula: _formulaController.text.trim(),
                fields: Set.of(_selectedFields),
                dimension: _dimension,
                chartType: _chartType,
                timeframe: _timeframe,
                region: _region,
                productGroup: _productGroup,
                pinned: _pinToDashboard,
                status: _publishLive ? _KpiStatus.live : _KpiStatus.draft,
                version: _nextVersionForName(_nameController.text.trim()),
                updatedAt: DateTime.now(),
              );
              _definitions.removeWhere((d) => d.name == def.name);
              _definitions.add(def);
              _activeDefinition = def;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('KPI gespeichert & bereitgestellt.')),
            );
          },
          label: const Text('Speichern & Versionieren'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.table_view_outlined),
          onPressed: previewPoints.isEmpty ? null : () => _exportCsv(previewPoints),
          label: const Text('Export CSV'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.picture_as_pdf_outlined),
          onPressed: previewPoints.isEmpty ? null : () => _exportPdf(previewPoints),
          label: const Text('Export PDF'),
        ),
      ],
    );
  }

  Widget _buildSavedDefinitions(ThemeData theme) {
    final sorted = List.of(_definitions)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 28),
        Text(
          'Gespeicherte KPIs',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ...sorted.map((def) {
          final isActive = _activeDefinition?.name == def.name;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              title: Text('${def.name} · v${def.version} (${def.status.label})'),
              subtitle: Text(
                '${def.dimension}, ${def.chartType.label} · zuletzt aktualisiert ${DateFormat('dd.MM.yyyy – HH:mm').format(def.updatedAt)}',
              ),
              trailing: Wrap(
                spacing: 8,
                children: [
                  if (isActive)
                    Chip(
                      label: const Text('Live'),
                      backgroundColor: theme.colorScheme.primaryContainer,
                    ),
                  IconButton(
                    tooltip: 'Laden',
                    icon: const Icon(Icons.play_circle_outline),
                    onPressed: () {
                      setState(() {
                        _nameController.text = def.name;
                        _formulaController.text = def.formula;
                        _selectedFields
                          ..clear()
                          ..addAll(def.fields);
                        _dimension = def.dimension;
                        _chartType = def.chartType;
                        _timeframe = def.timeframe;
                        _region = def.region;
                        _productGroup = def.productGroup;
                        _pinToDashboard = def.pinned;
                        _publishLive = def.status == _KpiStatus.live;
                        _activeDefinition = def;
                      });
                    },
                  ),
                  IconButton(
                    tooltip: 'Löschen',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      setState(() {
                        _definitions.removeWhere((d) => d.name == def.name);
                        if (_activeDefinition?.name == def.name) {
                          _activeDefinition = null;
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  int _nextVersionForName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) return 1;
    final existing = _definitions.where((d) => d.name == normalized);
    if (existing.isEmpty) return 1;
    return existing.map((e) => e.version).fold<int>(1, (p, c) => math.max(p, c + 1));
  }

  List<_KpiPreviewPoint> _buildPreviewPoints(_CustomKpiDefinition def) {
    final records = _filteredRecords();
    final grouped = <String, _KpiAccumulator>{};
    final manualSales = _manualSalesValue();

    for (final record in records) {
      final label = _dimensionLabel(record, def.dimension);
      final acc = grouped.putIfAbsent(label, () => _KpiAccumulator());
      acc.add(record);
    }

    final List<_KpiPreviewPoint> points = [];
    grouped.forEach((label, acc) {
      final variables = acc.toVariableMap();
      if (manualSales != null) {
        variables['sales'] = manualSales;
      }
      final value = _engine.evaluate(def.formula, variables, def.fields);
      points.add(_KpiPreviewPoint(label: label, value: value));
    });

    points.sort((a, b) => b.value.compareTo(a.value));
    return points;
  }

  double? _manualSalesValue() {
    final raw = _manualSalesController.text.trim();
    if (raw.isEmpty) return null;
    final normalized = raw.replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  List<_SampleKpiRecord> _filteredRecords() {
    final now = DateTime.now();
    final List<_SampleKpiRecord> filtered = [];

    for (final record in _sampleKpiRecords) {
      if (_region != 'Alle Regionen' && record.region != _region) continue;
      if (_productGroup != 'Alle Produktgruppen' && record.productGroup != _productGroup) continue;

      final inRange = switch (_timeframe) {
        _KpiTimeframe.last30Days => record.date.isAfter(now.subtract(const Duration(days: 30))),
        _KpiTimeframe.last90Days => record.date.isAfter(now.subtract(const Duration(days: 90))),
        _KpiTimeframe.last12Months => record.date.isAfter(now.subtract(const Duration(days: 365))),
        _KpiTimeframe.all => true,
      };

      if (inRange) filtered.add(record);
    }

    return filtered;
  }

  String _dimensionLabel(_SampleKpiRecord record, String dimension) {
    switch (dimension) {
      case 'Produktgruppe':
        return record.productGroup;
      case 'Kunde':
        return record.customer;
      case 'Monat':
        return DateFormat('MMM yy', 'de').format(record.date);
      case 'Land':
      default:
        return record.country;
    }
  }

  Future<void> _exportCsv(List<_KpiPreviewPoint> points) async {
    final buffer = StringBuffer('Label;Wert\n');
    for (final p in points) {
      buffer.writeln('${p.label};${p.value.toStringAsFixed(2)}');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CSV in Zwischenablage kopiert.')),
    );
  }

  Future<void> _exportPdf(List<_KpiPreviewPoint> points) async {
    final buffer = StringBuffer('KPI Snapshot – ${DateFormat('dd.MM.yyyy').format(DateTime.now())}\n');
    for (final p in points) {
      buffer.writeln('${p.label.padRight(18)} ${p.value.toStringAsFixed(2)}');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PDF-Snapshot in Zwischenablage kopiert.')),
    );
  }

  static const _availableFields = [
    _KpiField(
      key: 'complaints',
      label: 'Reklamationen',
      description: 'Anzahl Reklamationen im Zeitraum',
    ),
    _KpiField(
      key: 'sales',
      label: 'Verkäufe',
      description: 'Verkäufe (Stück)',
    ),
    _KpiField(
      key: 'revenue',
      label: 'Umsatz',
      description: 'Umsatz in EUR',
    ),
    _KpiField(
      key: 'units',
      label: 'Ausgelieferte Einheiten',
      description: 'Gesamtmenge ausgelieferter Produkte',
    ),
    _KpiField(
      key: 'returns',
      label: 'Retouren',
      description: 'Anzahl Retouren / Rücksendungen',
    ),
  ];

  static const _formulaSuggestions = [
    _FormulaSuggestion(
      name: 'Reklamationsquote %',
      formula: 'complaints / sales * 100',
      fields: {'complaints', 'sales'},
      description: 'Reklamationen geteilt durch Verkäufe – prozentuale Quote.',
    ),
    _FormulaSuggestion(
      name: 'Retourenquote %',
      formula: 'returns / sales * 100',
      fields: {'returns', 'sales'},
      description: 'Anteil Retouren an den Verkäufen.',
    ),
    _FormulaSuggestion(
      name: 'Umsatz pro Einheit',
      formula: 'revenue / units',
      fields: {'revenue', 'units'},
      description: 'Durchschnittlicher Umsatz pro ausgelieferter Einheit.',
    ),
    _FormulaSuggestion(
      name: 'Reklamationen pro Kunde',
      formula: 'complaints / 1000',
      fields: {'complaints'},
      description: 'Absolute Reklamationen skaliert auf 1.000 Kundenbasis.',
    ),
  ];
}

class _KpiPreviewBoard extends StatelessWidget {
  final _CustomKpiDefinition definition;
  final List<_KpiPreviewPoint> points;
  final _CustomKpiDefinition? activeDefinition;
  const _KpiPreviewBoard({
    required this.definition,
    required this.points,
    required this.activeDefinition,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.visibility_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Live-Vorschau (${points.length} Gruppen) · ${definition.dimension} · ${definition.chartType.label}',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (activeDefinition != null)
              Chip(
                label: Text('Aktiv: ${activeDefinition!.name}'),
                backgroundColor: theme.colorScheme.primaryContainer,
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (points.isEmpty)
          const _EmptyPlaceholder(
            message: 'Keine Daten im ausgewählten Filterbereich. Filter anpassen oder Formel prüfen.',
          )
        else
          _KpiChart(points: points, chartType: definition.chartType),
        const SizedBox(height: 12),
        if (points.isNotEmpty) _KpiTable(points: points),
      ],
    );
  }
}

class _KpiChart extends StatelessWidget {
  final List<_KpiPreviewPoint> points;
  final _KpiChartType chartType;
  const _KpiChart({required this.points, required this.chartType});

  @override
  Widget build(BuildContext context) {
    switch (chartType) {
      case _KpiChartType.bar:
        return _KpiBarChart(points: points);
      case _KpiChartType.line:
        return _KpiLineChart(points: points);
      case _KpiChartType.pie:
        return _KpiPieChart(points: points);
      case _KpiChartType.heatmap:
        return _KpiHeatmap(points: points);
    }
  }
}

class _KpiBarChart extends StatelessWidget {
  final List<_KpiPreviewPoint> points;
  const _KpiBarChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final double maxY =
        points.fold<double>(0, (p, c) => math.max(p, c.value)).clamp(1, double.infinity).toDouble();
    final groups = points.asMap().entries.map((entry) {
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
            toY: entry.value.value,
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

    return SizedBox(
      height: 260,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 42),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      points[idx].label,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (value) => FlLine(
              color: theme.dividerColor.withOpacity(0.2),
              strokeWidth: 1,
            ),
          ),
          barGroups: groups,
          borderData: FlBorderData(show: false),
          maxY: maxY,
        ),
      ),
    );
  }
}

class _KpiLineChart extends StatelessWidget {
  final List<_KpiPreviewPoint> points;
  const _KpiLineChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spots = points.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.value))
        .toList();
    return SizedBox(
      height: 260,
      child: LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: theme.colorScheme.primary,
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: theme.colorScheme.primary.withOpacity(0.12),
              ),
            ),
          ],
          gridData: FlGridData(show: true),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 42)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(points[idx].label, style: Theme.of(context).textTheme.bodySmall),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }
}

class _KpiPieChart extends StatelessWidget {
  final List<_KpiPreviewPoint> points;
  const _KpiPieChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final double total =
        points.fold<double>(0, (p, c) => p + c.value).clamp(1, double.infinity).toDouble();
    return SizedBox(
      height: 260,
      child: PieChart(
        PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 36,
          sections: points.map((p) {
            final percent = p.value / total * 100;
            return PieChartSectionData(
              value: p.value,
              title: '${percent.toStringAsFixed(1)}%',
              color: Colors.primaries[points.indexOf(p) % Colors.primaries.length],
              radius: 60,
              titleStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _KpiHeatmap extends StatelessWidget {
  final List<_KpiPreviewPoint> points;
  const _KpiHeatmap({required this.points});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final double maxValue = points
        .fold<double>(0, (p, c) => math.max(p, c.value))
        .clamp(1, double.infinity)
        .toDouble();
    final minValue = points.fold<double>(maxValue, (p, c) => math.min(p, c.value));
    final range = maxValue - minValue;

    double intensity(double value) {
      if (range == 0) return 0.6;
      return 0.2 + ((value - minValue) / range) * 0.8;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth ~/ 180 + 1;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: points.asMap().entries.map((entry) {
            final value = entry.value.value;
            final color = theme.colorScheme.primary.withOpacity(intensity(value));
            final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
            return Container(
              width: width,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.value.label, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white)),
                  const SizedBox(height: 6),
                  Text(entry.value.value.toStringAsFixed(2),
                      style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _KpiTable extends StatelessWidget {
  final List<_KpiPreviewPoint> points;
  const _KpiTable({required this.points});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.table_chart_outlined),
                const SizedBox(width: 8),
                Text('Tabellarische Ausgabe', style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const Divider(height: 16),
            ...points.map((p) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(p.label)),
                    Text(p.value.toStringAsFixed(2)),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}

class _KpiPreviewPoint {
  final String label;
  final double value;
  const _KpiPreviewPoint({required this.label, required this.value});
}

class _KpiField {
  final String key;
  final String label;
  final String description;
  const _KpiField({required this.key, required this.label, required this.description});
}

class _FormulaSuggestion {
  final String name;
  final String formula;
  final Set<String> fields;
  final String description;

  const _FormulaSuggestion({
    required this.name,
    required this.formula,
    required this.fields,
    required this.description,
  });
}

class _CustomKpiDefinition {
  final String name;
  final String formula;
  final Set<String> fields;
  final String dimension;
  final _KpiChartType chartType;
  final _KpiTimeframe timeframe;
  final String region;
  final String productGroup;
  final bool pinned;
  final _KpiStatus status;
  final int version;
  final DateTime updatedAt;

  _CustomKpiDefinition({
    required this.name,
    required this.formula,
    required this.fields,
    required this.dimension,
    required this.chartType,
    required this.timeframe,
    required this.region,
    required this.productGroup,
    required this.pinned,
    required this.status,
    required this.version,
    required this.updatedAt,
  });
}

enum _KpiChartType { bar, line, pie, heatmap }

extension on _KpiChartType {
  String get label {
    switch (this) {
      case _KpiChartType.bar:
        return 'Bar';
      case _KpiChartType.line:
        return 'Line';
      case _KpiChartType.pie:
        return 'Pie';
      case _KpiChartType.heatmap:
        return 'Heatmap';
    }
  }
}

enum _KpiTimeframe { last30Days, last90Days, last12Months, all }

enum _KpiStatus { draft, live }

extension on _KpiStatus {
  String get label => this == _KpiStatus.live ? 'Live' : 'Entwurf';
}

class _KpiAccumulator {
  double complaints = 0;
  double sales = 0;
  double revenue = 0;
  double units = 0;
  double returns = 0;

  void add(_SampleKpiRecord record) {
    complaints += record.complaints;
    sales += record.sales;
    revenue += record.revenue;
    units += record.units;
    returns += record.returns;
  }

  Map<String, double> toVariableMap() => {
        'complaints': complaints,
        'sales': sales,
        'revenue': revenue,
        'units': units,
        'returns': returns,
      };
}

class _SampleKpiRecord {
  final DateTime date;
  final String country;
  final String productGroup;
  final String customer;
  final String region;
  final double complaints;
  final double sales;
  final double revenue;
  final double units;
  final double returns;

  const _SampleKpiRecord({
    required this.date,
    required this.country,
    required this.productGroup,
    required this.customer,
    required this.region,
    required this.complaints,
    required this.sales,
    required this.revenue,
    required this.units,
    required this.returns,
  });
}

class _FormulaEngine {
  String? validate(String formula, Set<String> fields) {
    if (formula.trim().isEmpty) return 'Formel darf nicht leer sein';
    for (final field in fields) {
      if (!formula.contains(field)) {
        return 'Feld "$field" fehlt in der Formel';
      }
    }
    return null;
  }

  double evaluate(String formula, Map<String, double> variables, Set<String> fields) {
    var expr = formula;
    for (final field in fields) {
      final value = variables[field] ?? 0;
      expr = expr.replaceAll(field, value.toString());
    }
    try {
      return _safeEval(expr);
    } catch (_) {
      return 0;
    }
  }

  double _safeEval(String expr) {
    final tokens = expr.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    double result = double.tryParse(tokens.first) ?? 0;
    for (var i = 1; i < tokens.length - 1; i += 2) {
      final op = tokens[i];
      final value = double.tryParse(tokens[i + 1]) ?? 0;
      switch (op) {
        case '+':
          result += value;
          break;
        case '-':
          result -= value;
          break;
        case '*':
          result *= value;
          break;
        case '/':
          result = value == 0 ? 0 : result / value;
          break;
      }
    }
    return result;
  }
}

List<_SampleKpiRecord> _buildSampleKpiRecords() {
  final now = DateTime.now();
  DateTime m(int monthsAgo, int day) => DateTime(now.year, now.month - monthsAgo, day);

  return [
    _SampleKpiRecord(
      date: m(11, 15),
      country: 'Deutschland',
      productGroup: 'Sensorik',
      customer: 'ACME GmbH',
      region: 'EU',
      complaints: 24,
      sales: 1200,
      revenue: 240000,
      units: 1500,
      returns: 12,
    ),
    _SampleKpiRecord(
      date: m(10, 10),
      country: 'Frankreich',
      productGroup: 'Sensorik',
      customer: 'Securité SARL',
      region: 'EU',
      complaints: 18,
      sales: 980,
      revenue: 186000,
      units: 1200,
      returns: 10,
    ),
    _SampleKpiRecord(
      date: m(9, 5),
      country: 'USA',
      productGroup: 'Steuerung',
      customer: 'Northwind Inc.',
      region: 'NA',
      complaints: 32,
      sales: 1500,
      revenue: 310000,
      units: 1800,
      returns: 16,
    ),
    _SampleKpiRecord(
      date: m(9, 28),
      country: 'Kanada',
      productGroup: 'Steuerung',
      customer: 'Maple Automation',
      region: 'NA',
      complaints: 14,
      sales: 620,
      revenue: 118000,
      units: 800,
      returns: 6,
    ),
    _SampleKpiRecord(
      date: m(8, 12),
      country: 'VAE',
      productGroup: 'Sicherheit',
      customer: 'SafeTech MEA',
      region: 'MEA',
      complaints: 8,
      sales: 420,
      revenue: 95000,
      units: 540,
      returns: 3,
    ),
    _SampleKpiRecord(
      date: m(8, 25),
      country: 'Südafrika',
      productGroup: 'Sicherheit',
      customer: 'Cape Industries',
      region: 'MEA',
      complaints: 10,
      sales: 380,
      revenue: 82000,
      units: 460,
      returns: 4,
    ),
    _SampleKpiRecord(
      date: m(7, 3),
      country: 'Deutschland',
      productGroup: 'Sensorik',
      customer: 'ACME GmbH',
      region: 'EU',
      complaints: 12,
      sales: 700,
      revenue: 160000,
      units: 900,
      returns: 8,
    ),
    _SampleKpiRecord(
      date: m(7, 18),
      country: 'Frankreich',
      productGroup: 'Sensorik',
      customer: 'Securité SARL',
      region: 'EU',
      complaints: 9,
      sales: 540,
      revenue: 120000,
      units: 660,
      returns: 5,
    ),
    _SampleKpiRecord(
      date: m(6, 2),
      country: 'USA',
      productGroup: 'Steuerung',
      customer: 'Northwind Inc.',
      region: 'NA',
      complaints: 22,
      sales: 1100,
      revenue: 240000,
      units: 1400,
      returns: 11,
    ),
    _SampleKpiRecord(
      date: m(6, 20),
      country: 'Kanada',
      productGroup: 'Steuerung',
      customer: 'Maple Automation',
      region: 'NA',
      complaints: 11,
      sales: 500,
      revenue: 105000,
      units: 620,
      returns: 5,
    ),
    _SampleKpiRecord(
      date: m(5, 7),
      country: 'VAE',
      productGroup: 'Sicherheit',
      customer: 'SafeTech MEA',
      region: 'MEA',
      complaints: 6,
      sales: 390,
      revenue: 88000,
      units: 500,
      returns: 2,
    ),
    _SampleKpiRecord(
      date: m(5, 19),
      country: 'Südafrika',
      productGroup: 'Sicherheit',
      customer: 'Cape Industries',
      region: 'MEA',
      complaints: 7,
      sales: 340,
      revenue: 76000,
      units: 430,
      returns: 3,
    ),
  ];
}

final _sampleKpiRecords = _buildSampleKpiRecords();

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

    return _AuditEntry(
      ticket: (json['ticket'] ?? '').toString(),
      createdAt: _ts(json['createdAt']),
      customer: (json['customer'] ?? '').toString(),
      customerEmail: _optional(json['customerEmail']),
      customerNumber: _optional(json['customerNumber']),
      country: (json['country'] ?? '').toString(),
      article: _optional(json['article']),
      segment: _optional(json['segment']),
      statusLabel: (json['statusLabel'] ?? '').toString(),
      decisionLabel: (json['decisionLabel'] ?? '').toString(),
      repName: _optional(json['repName']),
      repEmail: _optional(json['repEmail']),
    );
  }
}
