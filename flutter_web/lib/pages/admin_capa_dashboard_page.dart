import 'package:flutter/material.dart';

import '../api/client.dart';
import '../models/capa_report.dart';
import 'capa_detail_page.dart';

class AdminCapaDashboardPage extends StatefulWidget {
  final ApiClient api;
  final bool canWrite;
  const AdminCapaDashboardPage({super.key, required this.api, this.canWrite = false});

  @override
  State<AdminCapaDashboardPage> createState() => _AdminCapaDashboardPageState();
}

class _AdminCapaDashboardPageState extends State<AdminCapaDashboardPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {};
  List<CapaReport> _allCapas = const [];
  bool _loadingCapas = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.adminCapaDashboard();
      if (!mounted) return;
      setState(() {
        _data = data;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _ensureCapasLoaded() async {
    if (_loadingCapas || _allCapas.isNotEmpty) return;
    setState(() => _loadingCapas = true);
    try {
      final list = await widget.api.adminCapas();
      if (!mounted) return;
      setState(() => _allCapas = list);
    } catch (_) {
      // silently ignore; selection will fallback
    } finally {
      if (!mounted) return;
      setState(() => _loadingCapas = false);
    }
  }

  List<_CriticalCapa> get _criticalCapas {
    final list = _data['criticalCapas'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => _CriticalCapa.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return const [];
  }

  List<_DepartmentStat> get _departmentStats {
    final list = _data['byDepartment'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => _DepartmentStat.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return const [];
  }

  Widget _kpiCard({required String label, required String value, Color? color, IconData? icon}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (icon != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (color ?? cs.primary).withOpacity(.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color ?? cs.primary),
              ),
            if (icon != null) const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 6),
                Text(value, style: theme.textTheme.headlineSmall?.copyWith(color: color ?? cs.primary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _departmentCard() {
    final stats = _departmentStats;
    if (stats.isEmpty) {
      return const Center(child: Text('Keine offenen CAPAs mit Abteilung vorhanden.'));
    }
    final maxCount = stats.map((s) => s.openCount).fold<int>(0, (a, b) => b > a ? b : a);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final stat in stats)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(stat.department, style: const TextStyle(fontWeight: FontWeight.w600))),
                    const SizedBox(width: 12),
                    Text('${stat.openCount}')
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: maxCount == 0 ? 0 : stat.openCount / maxCount,
                  minHeight: 8,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _openCapaDetail(_CriticalCapa capa) async {
    await _ensureCapasLoaded();
    final match = _allCapas.firstWhere(
      (c) => c.id == capa.id || c.capaNumber == capa.capaNumber,
      orElse: () => CapaReport(),
    );
    if (!mounted) return;
    if (match.id.isEmpty && match.capaNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CAPA konnte nicht geladen werden.')),
      );
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CapaDetailPage(
        api: widget.api,
        initialReport: match,
        canWrite: widget.canWrite,
      ),
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalOpen = _data['totalOpen'] ?? 0;
    final overdue = _data['overdue'] ?? 0;
    final dueSoon = _data['dueSoon'] ?? 0;
    final avgDuration = _data['avgDurationDays'] ?? 0;
    final recurrenceCount = _data['recurrenceCount'] ?? 0;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Erneut laden'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Expanded(
                child: Text(
                  'CAPA-Dashboard',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(width: 260, child: _kpiCard(label: 'Offene CAPAs', value: '$totalOpen', icon: Icons.assignment_turned_in_outlined, color: cs.primary)),
              SizedBox(
                width: 260,
                child: _kpiCard(
                  label: 'Überfällig',
                  value: '$overdue',
                  icon: Icons.error_outline,
                  color: cs.error,
                ),
              ),
              SizedBox(
                width: 260,
                child: _kpiCard(
                  label: 'Frist < 7 Tage',
                  value: '$dueSoon',
                  icon: Icons.schedule,
                  color: cs.tertiary,
                ),
              ),
              SizedBox(
                width: 260,
                child: _kpiCard(
                  label: 'Ø Durchlaufzeit (Tage)',
                  value: avgDuration is num ? avgDuration.toStringAsFixed(1) : '$avgDuration',
                  icon: Icons.speed,
                  color: cs.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Wiederkehrende CAPAs: $recurrenceCount', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Offene CAPAs pro Abteilung',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  _departmentCard(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kritische CAPAs',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  _criticalCapas.isEmpty
                      ? const Text('Keine kritischen CAPAs vorhanden.')
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('CAPA-ID')),
                              DataColumn(label: Text('Titel')),
                              DataColumn(label: Text('Abteilung')),
                              DataColumn(label: Text('Fällig')),
                              DataColumn(label: Text('Status')),
                            ],
                            rows: _criticalCapas.map((c) {
                              final due = c.dueDate != null
                                  ? DateTime.fromMillisecondsSinceEpoch(c.dueDate!).toIso8601String().substring(0, 10)
                                  : '—';
                              return DataRow(
                                cells: [
                                  DataCell(Text(c.capaNumber.isNotEmpty ? c.capaNumber : c.id)),
                                  DataCell(Text(c.title.isEmpty ? '—' : c.title)),
                                  DataCell(Text(c.department.isEmpty ? '—' : c.department)),
                                  DataCell(Text(due)),
                                  DataCell(Text(c.status.isEmpty ? '—' : c.status)),
                                ],
                                onSelectChanged: (_) => _openCapaDetail(c),
                              );
                            }).toList(),
                          ),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CriticalCapa {
  final String id;
  final String capaNumber;
  final String title;
  final String department;
  final String status;
  final int? dueDate;

  _CriticalCapa({
    required this.id,
    required this.capaNumber,
    required this.title,
    required this.department,
    required this.status,
    this.dueDate,
  });

  factory _CriticalCapa.fromJson(Map<String, dynamic> json) => _CriticalCapa(
        id: (json['id'] ?? '').toString(),
        capaNumber: (json['capaNumber'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        department: (json['department'] ?? '').toString(),
        status: (json['status'] ?? '').toString(),
        dueDate: json['dueDate'] is num ? (json['dueDate'] as num).toInt() : int.tryParse('${json['dueDate']}'),
      );
}

class _DepartmentStat {
  final String department;
  final int openCount;

  const _DepartmentStat({required this.department, required this.openCount});

  factory _DepartmentStat.fromJson(Map<String, dynamic> json) => _DepartmentStat(
        department: (json['department'] ?? '').toString(),
        openCount: (json['openCount'] is num) ? (json['openCount'] as num).toInt() : int.tryParse('${json['openCount']}') ?? 0,
      );
}
