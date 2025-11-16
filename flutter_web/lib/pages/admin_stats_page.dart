// lib/pages/admin_stats_page.dart
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/client.dart';
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
              Expanded(child: _CountrySection(total: total, countries: countries)),
              const SizedBox(width: 24),
              Expanded(child: _RepSection(reps: reps)),
            ],
          ),
        ] else ...[
          _CountrySection(total: total, countries: countries),
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
                  getTitlesWidget: (value, meta) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        value.toInt().toString(),
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall,
                      ),
                    );
                  },
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
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
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
  const _CountrySection({required this.total, required this.countries});

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
  const _SectionCard({required this.title, required this.icon, required this.child});

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
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
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
