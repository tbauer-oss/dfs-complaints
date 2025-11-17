// lib/pages/admin_stats_page.dart
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:country_flags/country_flags.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 860;
                  final mapPanel = _CountryMapPanel(countries: sorted);
                  final listPanel = _CountryListPanel(total: total, countries: sorted);
                  if (isWide) {
                    return Row(
                      children: [
                        Expanded(flex: 5, child: listPanel),
                        const SizedBox(width: 20),
                        Expanded(flex: 6, child: mapPanel),
                      ],
                    );
                  }
                  final mapHeight = math.max(constraints.maxHeight * 0.45, 260.0);
                  return Column(
                    children: [
                      SizedBox(height: mapHeight, child: mapPanel),
                      const SizedBox(height: 16),
                      Expanded(child: listPanel),
                    ],
                  );
                },
              ),
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

class _CountryMapPanel extends StatelessWidget {
  final List<_CountryBucket> countries;
  const _CountryMapPanel({required this.countries});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Globale Übersicht',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Pins markieren Länder mit eingegangenen Reklamationen.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Expanded(child: _WorldMapWithPins(countries: countries)),
          ],
        ),
      ),
    );
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

class _WorldMapWithPins extends StatelessWidget {
  final List<_CountryBucket> countries;
  const _WorldMapWithPins({required this.countries});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pins = countries
        .map((bucket) {
          final code = CountryGeography.resolveCode(bucket.country);
          if (code == null) return null;
          final position = CountryGeography.normalizedPositionFor(code);
          if (position == null) return null;
          return _CountryPinData(
            code: code,
            label: CountryGeography.labelForCode(code),
            count: bucket.count,
            normalized: position,
          );
        })
        .whereType<_CountryPinData>()
        .toList();
    if (pins.isEmpty) {
      return const Center(child: Text('Keine lokalisierbaren Daten verfügbar.'));
    }
    final maxCount = pins.fold<int>(0, (value, pin) => math.max(value, pin.count));
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final baseColor = theme.colorScheme.primary;
        final accent = theme.colorScheme.tertiary;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [
                baseColor.withOpacity(0.07),
                accent.withOpacity(0.12),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _WorldMapPainter(
                      landColor: theme.colorScheme.surface,
                      strokeColor: theme.colorScheme.outline.withOpacity(0.4),
                    ),
                  ),
                ),
                for (final pin in pins)
                  _MapPin(
                    pin: pin,
                    maxCount: maxCount,
                    width: width,
                    height: height,
                    baseColor: baseColor,
                    accent: accent,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MapPin extends StatelessWidget {
  final _CountryPinData pin;
  final int maxCount;
  final double width;
  final double height;
  final Color baseColor;
  final Color accent;
  const _MapPin({
    required this.pin,
    required this.maxCount,
    required this.width,
    required this.height,
    required this.baseColor,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = maxCount == 0 ? 0.0 : pin.count / maxCount;
    final size = (ui.lerpDouble(10, 26, ratio.clamp(0.0, 1.0)) ?? 12).toDouble();
    final color = Color.lerp(baseColor, accent, ratio.clamp(0.0, 1.0)) ?? baseColor;
    final x = (pin.normalized.dx.clamp(0.0, 1.0)) * width;
    final y = (pin.normalized.dy.clamp(0.0, 1.0)) * height;
    return Positioned(
      left: (x - size / 2).clamp(0.0, math.max(width - size, 0)),
      top: (y - size).clamp(0.0, math.max(height - size, 0)),
      child: Tooltip(
        message: '${pin.label}: ${pin.count}',
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.45),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorldMapPainter extends CustomPainter {
  final Color landColor;
  final Color strokeColor;
  const _WorldMapPainter({required this.landColor, required this.strokeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = landColor.withOpacity(0.95);
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = strokeColor;
    for (final shape in _kWorldMapShapes) {
      if (shape.isEmpty) continue;
      final path = Path();
      for (var i = 0; i < shape.length; i++) {
        final point = Offset(shape[i].dx * size.width, shape[i].dy * size.height);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WorldMapPainter oldDelegate) {
    return oldDelegate.landColor != landColor || oldDelegate.strokeColor != strokeColor;
  }
}

class _CountryPinData {
  final String code;
  final String label;
  final int count;
  final Offset normalized;
  const _CountryPinData({
    required this.code,
    required this.label,
    required this.count,
    required this.normalized,
  });
}

const List<List<Offset>> _kWorldMapShapes = [
  [
    Offset(0.02, 0.2),
    Offset(0.14, 0.08),
    Offset(0.26, 0.05),
    Offset(0.36, 0.18),
    Offset(0.34, 0.26),
    Offset(0.28, 0.32),
    Offset(0.18, 0.34),
    Offset(0.08, 0.28),
  ],
  [
    Offset(0.32, 0.36),
    Offset(0.38, 0.48),
    Offset(0.42, 0.66),
    Offset(0.36, 0.88),
    Offset(0.28, 0.72),
    Offset(0.28, 0.52),
  ],
  [
    Offset(0.42, 0.16),
    Offset(0.56, 0.1),
    Offset(0.65, 0.12),
    Offset(0.7, 0.2),
    Offset(0.66, 0.26),
    Offset(0.56, 0.28),
    Offset(0.48, 0.24),
  ],
  [
    Offset(0.62, 0.18),
    Offset(0.86, 0.14),
    Offset(0.97, 0.26),
    Offset(0.94, 0.38),
    Offset(0.78, 0.4),
    Offset(0.68, 0.3),
  ],
  [
    Offset(0.48, 0.32),
    Offset(0.6, 0.34),
    Offset(0.66, 0.52),
    Offset(0.6, 0.78),
    Offset(0.48, 0.64),
    Offset(0.44, 0.44),
  ],
  [
    Offset(0.76, 0.56),
    Offset(0.92, 0.6),
    Offset(0.94, 0.76),
    Offset(0.84, 0.84),
    Offset(0.74, 0.7),
  ],
  [
    Offset(0.22, 0.04),
    Offset(0.28, 0.02),
    Offset(0.34, 0.05),
    Offset(0.3, 0.12),
    Offset(0.22, 0.1),
  ],
];

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
