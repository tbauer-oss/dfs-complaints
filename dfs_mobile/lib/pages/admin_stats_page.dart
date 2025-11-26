// lib/pages/admin_stats_page.dart
import 'dart:math' as math;

import 'package:country_flags/country_flags.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:dfs_mobile/api/client.dart';
import 'package:dfs_mobile/data/country_geography.dart';
import 'package:dfs_mobile/widgets/legal_footer.dart';

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
    final statuses = _parseStatusBuckets();
    final resolvedOpen = open ?? _calcOpenFallback(statuses, total);
    final months = _parseMonthBuckets();
    final countries = _parseCountryBuckets();
    final reps = _parseRepBuckets();
    final products = _parseProductBuckets();
    final lots = _parseLotBuckets();

    final isWide = maxWidth > 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRangeHeader(theme),
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
              Expanded(child: _StatusSection(statuses: statuses, total: total)),
            ],
          ),
        ] else ...[
          _MonthlyChart(data: months),
          const SizedBox(height: 24),
          _StatusSection(statuses: statuses, total: total),
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
        const _CustomKpiBuilderPanel(),
      ],
    );
  }

  Widget _buildRangeHeader(ThemeData theme) {
    final df = DateFormat('dd.MM.yyyy');
    final rangeLabel = _range == null
        ? 'Letzte 12 Monate'
        : '${df.format(_range!.start)} – ${df.format(_range!.end)}';
    return Row(
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
        FilledButton.tonalIcon(
          onPressed: _loading ? null : _pickRange,
          icon: const Icon(Icons.filter_list_outlined),
          label: const Text('Zeitraum wählen'),
        ),
      ],
    );
  }

  List<_StatusBucket> _parseStatusBuckets() {
    final raw = (_stats?['byStatus'] as List?) ?? const [];
    final out = <_StatusBucket>[];
    for (final entry in raw) {
      if (entry is Map) {
        final status = (entry['status'] as num?)?.toInt();
        final count = (entry['count'] as num?)?.toInt() ?? 0;
        if (status != null) {
          out.add(_StatusBucket(status: status, count: count));
        }
      }
    }
    out.sort((a, b) => a.status.compareTo(b.status));
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
        final country = (entry['country'] ?? '').toString();
        final count = (entry['count'] as num?)?.toInt() ?? 0;
        if (country.isNotEmpty) {
          out.add(_CountryBucket(country: country, count: count));
        }
      }
    }
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

  int _calcOpenFallback(List<_StatusBucket> statuses, int total) {
    final closed = statuses
        .firstWhere((s) => s.status == 6, orElse: () => const _StatusBucket(status: 6, count: 0))
        .count;
    return math.max(total - closed, 0);
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

    final yLabels = _buildYAxisLabels(maxY, interval, theme.textTheme.bodySmall);
    final bottomLabels = _buildBottomLabels(data, theme.textTheme.bodySmall);

    return _SectionCard(
      title: 'Reklamationen pro Monat',
      icon: Icons.bar_chart_outlined,
      child: SizedBox(
        height: 280,
        child: Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  yLabels,
                  const SizedBox(width: 12),
                  Expanded(
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
                        titlesData: const FlTitlesData(
                          topTitles:
                              AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles:
                              AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          leftTitles:
                              AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles:
                              AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            bottomLabels,
          ],
        ),
      ),
    );
  }

  Widget _buildYAxisLabels(double maxY, double interval, TextStyle? style) {
    final ticks = <int>[];
    double current = 0;
    while (current <= maxY) {
      ticks.add(current.round());
      current += interval;
    }
    if (ticks.isEmpty || ticks.last != maxY.round()) {
      ticks.add(maxY.round());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: ticks.reversed
          .map(
            (value) => Text(
              value.toString(),
              style: style,
            ),
          )
          .toList(),
    );
  }

  Widget _buildBottomLabels(
    List<_MonthBucket> data,
    TextStyle? style,
  ) {
    return Row(
      children: data
          .map<Widget>(
            (bucket) => Expanded(
              child: Text(
                bucket.label,
                textAlign: TextAlign.center,
                style: style,
              ),
            ),
          )
          .toList(),
    );
  }
}

class _StatusSection extends StatelessWidget {
  final List<_StatusBucket> statuses;
  final int total;
  const _StatusSection({required this.statuses, required this.total});

  Color _colorForStatus(ThemeData theme, int index) {
    final palette = [
      theme.colorScheme.primary,
      theme.colorScheme.secondary,
      Colors.orange,
      Colors.teal,
      Colors.indigo,
      Colors.pink,
    ];
    return palette[index % palette.length];
  }

  String _label(int status) {
    const labels = {
      1: 'Eingegangen',
      2: 'In Bearbeitung',
      3: 'Rückfrage',
      4: 'Entscheidung',
      5: 'In Nacharbeit',
      6: 'Abgeschlossen',
    };
    return labels[status] ?? 'Status $status';
  }

  @override
  Widget build(BuildContext context) {
    if (statuses.isEmpty) {
      return const _SectionCard(
        title: 'Statusverteilung',
        icon: Icons.donut_large_outlined,
        child: _EmptyPlaceholder(message: 'Keine Statusdaten vorhanden'),
      );
    }
    final theme = Theme.of(context);
    return _SectionCard(
      title: 'Statusverteilung',
      icon: Icons.donut_large_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < statuses.length; i++) ...[
            _StatusRow(
              bucket: statuses[i],
              total: total,
              color: _colorForStatus(theme, i),
              label: _label(statuses[i].status),
            ),
            if (i != statuses.length - 1) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final _StatusBucket bucket;
  final int total;
  final Color color;
  final String label;
  const _StatusRow({
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
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                child: Text(
                  bucket.abbreviation,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
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
                  final code = CountryGeography.resolveCode(bucket.country);
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
      theme: const ImageTheme(
        width: 38,
        height: 28,
        shape: RoundedRectangle(6),
      ),
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
    final theme = Theme.of(context);
    final formatter = NumberFormat.decimalPercentPattern(locale: 'de', decimalDigits: 1);
    final top = buckets.take(10).toList(growable: false);
    return _SectionCard(
      title: title,
      icon: icon,
      child: Column(
        children: [
          for (var i = 0; i < top.length; i++) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.secondary.withOpacity(0.12),
                child: Text('${i + 1}'),
              ),
              title: Text(top[i].label),
              subtitle: total == 0 ? null : Text(formatter.format(top[i].count / total)),
              trailing: Text('${top[i].count}'),
            ),
            if (i != top.length - 1) const Divider(height: 1),
          ],
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

class _StatusBucket {
  final int status;
  final int count;
  const _StatusBucket({required this.status, required this.count});
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

class _CountryBucket {
  final String country;
  final int count;
  _CountryBucket({required this.country, required this.count});

  String get abbreviation {
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

class _TopBucket {
  final String label;
  final int count;
  const _TopBucket({required this.label, required this.count});
}

class _CustomKpiBuilderPanel extends StatefulWidget {
  const _CustomKpiBuilderPanel();

  @override
  State<_CustomKpiBuilderPanel> createState() => _CustomKpiBuilderPanelState();
}

class _CustomKpiBuilderPanelState extends State<_CustomKpiBuilderPanel> {
  final _nameController = TextEditingController(text: 'Reklamationsquote');
  final _formulaController = TextEditingController(text: 'complaints / sales * 100');
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

    for (final record in records) {
      final label = _dimensionLabel(record, def.dimension);
      final acc = grouped.putIfAbsent(label, () => _KpiAccumulator());
      acc.add(record);
    }

    final List<_KpiPreviewPoint> points = [];
    grouped.forEach((label, acc) {
      final variables = acc.toVariableMap();
      final value = _engine.evaluate(def.formula, variables, def.fields);
      points.add(_KpiPreviewPoint(label: label, value: value));
    });

    points.sort((a, b) => b.value.compareTo(a.value));
    return points;
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
    final maxY = points.fold<double>(0, (p, c) => math.max(p, c.value)).clamp(1, double.infinity);
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
    final total = points.fold<double>(0, (p, c) => p + c.value).clamp(1, double.infinity);
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
              color: _pieColorForLabel(p.label, theme),
              radius: 80,
              title: '${percent.toStringAsFixed(1)}%\n${p.label}',
              titleStyle: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold),
            );
          }).toList(),
        ),
      ),
    );
  }

  Color _pieColorForLabel(String label, ThemeData theme) {
    final hash = label.codeUnits.fold<int>(0, (p, c) => p + c);
    final hue = (hash * 37) % 360;
    return HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.55).toColor();
  }
}

class _KpiHeatmap extends StatelessWidget {
  final List<_KpiPreviewPoint> points;
  const _KpiHeatmap({required this.points});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = points.fold<double>(0, (p, c) => math.max(p, c.value)).clamp(1, double.infinity);
    return SizedBox(
      height: 260,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: points.length,
        itemBuilder: (context, index) {
          final point = points[index];
          final intensity = (point.value / max).clamp(0.0, 1.0);
          final color = Color.lerp(
            theme.colorScheme.surfaceVariant,
            theme.colorScheme.primary,
            intensity,
          );
          return Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(point.label, style: theme.textTheme.labelMedium),
                const Spacer(),
                Text(point.value.toStringAsFixed(2),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _KpiTable extends StatelessWidget {
  final List<_KpiPreviewPoint> points;
  const _KpiTable({required this.points});

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00', 'de');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Segment', style: Theme.of(context).textTheme.labelLarge),
                ),
                Text('Wert', style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 8),
            ...points.map((p) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(p.label)),
                      Text(formatter.format(p.value)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
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

  const _CustomKpiDefinition({
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

  Map<String, double> toVariableMap() {
    return {
      'complaints': complaints,
      'sales': sales,
      'revenue': revenue,
      'units': units,
      'returns': returns,
    };
  }
}

class _SampleKpiRecord {
  final String country;
  final String region;
  final String productGroup;
  final String customer;
  final DateTime date;
  final double complaints;
  final double sales;
  final double revenue;
  final double units;
  final double returns;

  const _SampleKpiRecord({
    required this.country,
    required this.region,
    required this.productGroup,
    required this.customer,
    required this.date,
    required this.complaints,
    required this.sales,
    required this.revenue,
    required this.units,
    required this.returns,
  });
}

const _sampleKpiRecords = [
  _SampleKpiRecord(
    country: 'DE',
    region: 'EU',
    productGroup: 'Sensorik',
    customer: 'AutoSys GmbH',
    date: DateTime(2024, 11, 12),
    complaints: 18,
    sales: 480,
    revenue: 72000,
    units: 520,
    returns: 6,
  ),
  _SampleKpiRecord(
    country: 'FR',
    region: 'EU',
    productGroup: 'Sensorik',
    customer: 'Fournier SA',
    date: DateTime(2024, 12, 2),
    complaints: 9,
    sales: 320,
    revenue: 51000,
    units: 340,
    returns: 4,
  ),
  _SampleKpiRecord(
    country: 'US',
    region: 'NA',
    productGroup: 'Steuerung',
    customer: 'NorthTech',
    date: DateTime(2025, 1, 16),
    complaints: 22,
    sales: 610,
    revenue: 91000,
    units: 690,
    returns: 11,
  ),
  _SampleKpiRecord(
    country: 'CA',
    region: 'NA',
    productGroup: 'Steuerung',
    customer: 'Apex Dynamics',
    date: DateTime(2025, 2, 1),
    complaints: 7,
    sales: 210,
    revenue: 36000,
    units: 230,
    returns: 3,
  ),
  _SampleKpiRecord(
    country: 'AE',
    region: 'MEA',
    productGroup: 'Sicherheit',
    customer: 'Gulf Secure',
    date: DateTime(2025, 3, 11),
    complaints: 11,
    sales: 260,
    revenue: 44000,
    units: 280,
    returns: 4,
  ),
  _SampleKpiRecord(
    country: 'DE',
    region: 'EU',
    productGroup: 'Sicherheit',
    customer: 'Meyer Industrie',
    date: DateTime(2025, 4, 4),
    complaints: 5,
    sales: 180,
    revenue: 32000,
    units: 200,
    returns: 2,
  ),
  _SampleKpiRecord(
    country: 'PL',
    region: 'EU',
    productGroup: 'Sensorik',
    customer: 'Baltic Machines',
    date: DateTime(2025, 5, 9),
    complaints: 6,
    sales: 240,
    revenue: 37000,
    units: 255,
    returns: 2,
  ),
  _SampleKpiRecord(
    country: 'US',
    region: 'NA',
    productGroup: 'Sensorik',
    customer: 'West Coast Labs',
    date: DateTime(2025, 5, 21),
    complaints: 14,
    sales: 420,
    revenue: 68000,
    units: 450,
    returns: 5,
  ),
  _SampleKpiRecord(
    country: 'ES',
    region: 'EU',
    productGroup: 'Steuerung',
    customer: 'Iberia Automation',
    date: DateTime(2025, 6, 2),
    complaints: 4,
    sales: 170,
    revenue: 25000,
    units: 185,
    returns: 1,
  ),
  _SampleKpiRecord(
    country: 'ZA',
    region: 'MEA',
    productGroup: 'Sicherheit',
    customer: 'Cape Robotics',
    date: DateTime(2025, 6, 18),
    complaints: 8,
    sales: 195,
    revenue: 30000,
    units: 215,
    returns: 2,
  ),
  _SampleKpiRecord(
    country: 'DE',
    region: 'EU',
    productGroup: 'Steuerung',
    customer: 'Hahn AG',
    date: DateTime(2025, 7, 5),
    complaints: 12,
    sales: 340,
    revenue: 56000,
    units: 365,
    returns: 6,
  ),
  _SampleKpiRecord(
    country: 'US',
    region: 'NA',
    productGroup: 'Sicherheit',
    customer: 'Eagle Defense',
    date: DateTime(2025, 7, 11),
    complaints: 10,
    sales: 305,
    revenue: 52000,
    units: 330,
    returns: 3,
  ),
];

class _FormulaEngine {
  final _tokenizer = RegExp(r'[A-Za-z_][A-Za-z0-9_]*|\d+(?:\.\d+)?|[()+\-*/]');

  double evaluate(String expression, Map<String, double> variables, Set<String> allowedFields) {
    final error = validate(expression, allowedFields);
    if (error != null) throw FormatException(error);
    final tokens = _tokenizer
        .allMatches(expression.replaceAll(' ', ''))
        .map((m) => m.group(0)!)
        .toList();
    final rpn = _toRpn(tokens);
    return _evalRpn(rpn, variables);
  }

  String? validate(String expression, Set<String> allowedFields) {
    if (expression.trim().isEmpty) return 'Formel fehlt';
    final tokens = _tokenizer
        .allMatches(expression.replaceAll(' ', ''))
        .map((m) => m.group(0)!)
        .toList();
    for (final token in tokens) {
      if (_isIdentifier(token) &&
          !allowedFields.contains(token) &&
          !_numericFields.contains(token)) {
        return 'Unbekanntes Feld "$token"';
      }
    }
    return null;
  }

  bool _isIdentifier(String token) => RegExp(r'^[A-Za-z_]').hasMatch(token);

  List<String> _toRpn(List<String> tokens) {
    final output = <String>[];
    final stack = <String>[];
    final precedence = {'+': 1, '-': 1, '*': 2, '/': 2};

    for (final token in tokens) {
      if (_isIdentifier(token) || double.tryParse(token) != null) {
        output.add(token);
      } else if (token == '(') {
        stack.add(token);
      } else if (token == ')') {
        while (stack.isNotEmpty && stack.last != '(') {
          output.add(stack.removeLast());
        }
        if (stack.isNotEmpty && stack.last == '(') stack.removeLast();
      } else {
        while (stack.isNotEmpty && precedence[stack.last] != null &&
            precedence[stack.last]! >= (precedence[token] ?? 0)) {
          output.add(stack.removeLast());
        }
        stack.add(token);
      }
    }
    output.addAll(stack.reversed);
    return output;
  }

  double _evalRpn(List<String> rpn, Map<String, double> variables) {
    final stack = <double>[];
    for (final token in rpn) {
      final number = double.tryParse(token);
      if (number != null) {
        stack.add(number);
        continue;
      }
      if (_isIdentifier(token)) {
        final value = variables[token] ?? 0;
        stack.add(value);
        continue;
      }
      if (stack.length < 2) throw const FormatException('Ungültige Formel');
      final b = stack.removeLast();
      final a = stack.removeLast();
      switch (token) {
        case '+':
          stack.add(a + b);
          break;
        case '-':
          stack.add(a - b);
          break;
        case '*':
          stack.add(a * b);
          break;
        case '/':
          stack.add(b == 0 ? double.nan : a / b);
          break;
        default:
          throw FormatException('Operator $token nicht unterstützt');
      }
    }
    return stack.isEmpty ? 0 : stack.single;
  }

  static const _numericFields = {'0', '1', '2', '3', '4', '5', '6', '7', '8', '9'};
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
