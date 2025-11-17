// lib/pages/admin_stats_page.dart
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:country_flags/country_flags.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
    final decisions = _parseDecisionBuckets();
    final resolvedOpen = open ?? _calcOpenFallback(decisions, total);
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
    final baseColor = theme.colorScheme.primary;
    final accent = theme.colorScheme.secondary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final radius = math.min(32.0, math.max(16.0, width * 0.04));
        final borderColor = theme.colorScheme.onSurface.withOpacity(0.05);
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.surfaceVariant.withOpacity(0.75),
                theme.colorScheme.surface.withOpacity(0.95),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withOpacity(0.08),
                blurRadius: 32,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _WorldMapPainter(
                      oceanStart: theme.colorScheme.primary.withOpacity(0.25),
                      oceanEnd: theme.colorScheme.primary.withOpacity(0.05),
                      landColor: theme.colorScheme.surface,
                      strokeColor: theme.colorScheme.outline.withOpacity(0.6),
                      gridColor: theme.colorScheme.onSurface.withOpacity(0.08),
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
    final headSize = (ui.lerpDouble(12, 30, ratio.clamp(0.0, 1.0)) ?? 16).toDouble();
    final color = Color.lerp(baseColor, accent, ratio.clamp(0.0, 1.0)) ?? baseColor;
    final x = (pin.normalized.dx.clamp(0.0, 1.0)) * width;
    final y = (pin.normalized.dy.clamp(0.0, 1.0)) * height;
    final markerHeight = headSize * 1.45;
    final tailHeight = headSize * 0.45;
    final left = (x - headSize / 2).clamp(0.0, math.max(width - headSize, 0));
    final top = (y - markerHeight).clamp(0.0, math.max(height - markerHeight, 0));
    return Positioned(
      left: left,
      top: top,
      child: Tooltip(
        message: '${pin.label}: ${pin.count}',
        child: SizedBox(
          width: headSize,
          height: markerHeight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: headSize,
                height: headSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withOpacity(0.95),
                      color,
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.7),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.45),
                      blurRadius: 12,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
              ),
              SizedBox(height: math.max(4, headSize * 0.12)),
              Container(
                width: math.max(2, headSize * 0.2),
                height: tailHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(
                    colors: [
                      color,
                      color.withOpacity(0.0),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorldMapPainter extends CustomPainter {
  final Color oceanStart;
  final Color oceanEnd;
  final Color landColor;
  final Color strokeColor;
  final Color gridColor;
  const _WorldMapPainter({
    required this.oceanStart,
    required this.oceanEnd,
    required this.landColor,
    required this.strokeColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final oceanPaint = Paint()
      ..shader = LinearGradient(
        colors: [oceanStart, oceanEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    canvas.drawRect(rect, oceanPaint);

    final gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const lines = 6;
    for (var i = 1; i < lines; i++) {
      final dx = rect.left + rect.width * i / lines;
      final dy = rect.top + rect.height * i / lines;
      canvas.drawLine(Offset(dx, rect.top), Offset(dx, rect.bottom), gridPaint);
      canvas.drawLine(Offset(rect.left, dy), Offset(rect.right, dy), gridPaint);
    }

    final glowPaint = Paint()
      ..color = landColor.withOpacity(0.35)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 18);
    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          landColor.withOpacity(0.95),
          landColor.withOpacity(0.75),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomRight,
      ).createShader(rect);
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = strokeColor;

    for (final polygon in _kWorldMapPolygons) {
      if (polygon.isEmpty) continue;
      final path = _buildSmoothPath(polygon, size);
      canvas.drawPath(path, glowPaint);
      canvas.drawShadow(path, Colors.black.withOpacity(0.15), 12, false);
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    }
  }

  Path _buildSmoothPath(List<Offset> polygon, Size size) {
    if (polygon.length == 1) {
      final point = Offset(polygon.first.dx * size.width, polygon.first.dy * size.height);
      return Path()..addOval(Rect.fromCircle(center: point, radius: size.shortestSide * 0.01));
    }
    final scaled = [
      for (final point in polygon)
        Offset(point.dx * size.width, point.dy * size.height),
    ];
    final path = Path();
    final start = _midPoint(scaled.last, scaled.first);
    path.moveTo(start.dx, start.dy);
    for (var i = 0; i < scaled.length; i++) {
      final current = scaled[i];
      final next = scaled[(i + 1) % scaled.length];
      final mid = _midPoint(current, next);
      path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
    }
    path.close();
    return path;
  }

  Offset _midPoint(Offset a, Offset b) => Offset(
        (a.dx + b.dx) / 2,
        (a.dy + b.dy) / 2,
      );

  @override
  bool shouldRepaint(covariant _WorldMapPainter oldDelegate) {
    return oldDelegate.oceanStart != oceanStart ||
        oldDelegate.oceanEnd != oceanEnd ||
        oldDelegate.landColor != landColor ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.gridColor != gridColor;
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

const List<List<Offset>> _kWorldMapPolygons = [
  [
    Offset(0.015, 0.34),
    Offset(0.04, 0.24),
    Offset(0.07, 0.16),
    Offset(0.12, 0.12),
    Offset(0.2, 0.11),
    Offset(0.27, 0.16),
    Offset(0.31, 0.23),
    Offset(0.34, 0.32),
    Offset(0.33, 0.4),
    Offset(0.29, 0.46),
    Offset(0.24, 0.48),
    Offset(0.18, 0.52),
    Offset(0.13, 0.48),
    Offset(0.09, 0.41),
    Offset(0.06, 0.37),
  ],
  [
    Offset(0.32, 0.07),
    Offset(0.35, 0.03),
    Offset(0.4, 0.02),
    Offset(0.45, 0.05),
    Offset(0.44, 0.1),
    Offset(0.4, 0.13),
    Offset(0.35, 0.11),
  ],
  [
    Offset(0.31, 0.39),
    Offset(0.35, 0.47),
    Offset(0.38, 0.6),
    Offset(0.35, 0.74),
    Offset(0.31, 0.86),
    Offset(0.27, 0.78),
    Offset(0.27, 0.58),
  ],
  [
    Offset(0.37, 0.2),
    Offset(0.42, 0.12),
    Offset(0.5, 0.1),
    Offset(0.58, 0.12),
    Offset(0.64, 0.16),
    Offset(0.71, 0.16),
    Offset(0.77, 0.19),
    Offset(0.84, 0.23),
    Offset(0.92, 0.3),
    Offset(0.95, 0.36),
    Offset(0.92, 0.44),
    Offset(0.86, 0.48),
    Offset(0.81, 0.52),
    Offset(0.74, 0.51),
    Offset(0.67, 0.46),
    Offset(0.6, 0.42),
    Offset(0.54, 0.36),
    Offset(0.48, 0.32),
    Offset(0.42, 0.3),
    Offset(0.38, 0.26),
  ],
  [
    Offset(0.46, 0.28),
    Offset(0.5, 0.36),
    Offset(0.54, 0.46),
    Offset(0.56, 0.6),
    Offset(0.53, 0.7),
    Offset(0.48, 0.78),
    Offset(0.42, 0.64),
    Offset(0.4, 0.5),
  ],
  [
    Offset(0.57, 0.34),
    Offset(0.61, 0.37),
    Offset(0.65, 0.4),
    Offset(0.63, 0.48),
    Offset(0.59, 0.46),
    Offset(0.56, 0.4),
  ],
  [
    Offset(0.62, 0.44),
    Offset(0.68, 0.46),
    Offset(0.7, 0.5),
    Offset(0.66, 0.55),
    Offset(0.61, 0.53),
  ],
  [
    Offset(0.69, 0.54),
    Offset(0.76, 0.52),
    Offset(0.83, 0.54),
    Offset(0.84, 0.58),
    Offset(0.79, 0.61),
    Offset(0.73, 0.6),
  ],
  [
    Offset(0.73, 0.62),
    Offset(0.78, 0.59),
    Offset(0.86, 0.62),
    Offset(0.9, 0.7),
    Offset(0.84, 0.8),
    Offset(0.75, 0.74),
  ],
  [
    Offset(0.84, 0.3),
    Offset(0.88, 0.34),
    Offset(0.86, 0.4),
    Offset(0.82, 0.36),
  ],
  [
    Offset(0.79, 0.44),
    Offset(0.82, 0.46),
    Offset(0.8, 0.51),
    Offset(0.77, 0.5),
  ],
  [
    Offset(0.43, 0.21),
    Offset(0.45, 0.17),
    Offset(0.47, 0.21),
    Offset(0.45, 0.24),
  ],
  [
    Offset(0.37, 0.16),
    Offset(0.39, 0.14),
    Offset(0.41, 0.16),
    Offset(0.39, 0.18),
  ],
  [
    Offset(0.84, 0.7),
    Offset(0.88, 0.74),
    Offset(0.86, 0.82),
    Offset(0.82, 0.78),
  ],
  [
    Offset(0.12, 0.9),
    Offset(0.3, 0.94),
    Offset(0.5, 0.96),
    Offset(0.7, 0.94),
    Offset(0.88, 0.9),
    Offset(0.86, 0.98),
    Offset(0.14, 0.98),
  ],
  [
    Offset(0.63, 0.56),
    Offset(0.66, 0.58),
    Offset(0.64, 0.62),
    Offset(0.61, 0.6),
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
