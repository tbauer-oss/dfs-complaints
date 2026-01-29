import 'package:flutter/material.dart';
import '../api/client.dart';
import 'admin_training_page.dart';
import 'training_admin_section.dart';

class TrainingAdminOverviewPage extends StatefulWidget {
  const TrainingAdminOverviewPage({
    super.key,
    required this.api,
    this.onSectionSelected,
  });

  final ApiClient api;
  final void Function(TrainingAdminSection section)? onSectionSelected;

  @override
  State<TrainingAdminOverviewPage> createState() => _TrainingAdminOverviewPageState();
}

class _TrainingAdminOverviewPageState extends State<TrainingAdminOverviewPage> {
  Map<String, dynamic> _metrics = const {};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMetrics();
  }

  Future<void> _loadMetrics() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.adminTrainingDashboardMetrics();
      if (!mounted) return;
      setState(() => _metrics = data);
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = '$err');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  int? _metricInt(String key) {
    final value = _metrics[key];
    if (value is num) return value.toInt();
    return null;
  }

  void _openSection(TrainingAdminSection section) {
    final handler = widget.onSectionSelected;
    if (handler != null) {
      handler(section);
    } else {
      Navigator.of(context).pushNamed(trainingAdminSectionPath(section));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final metricsEmpty = _metrics.isEmpty;
    final showSetupInfo = _error != null || (!_loading && metricsEmpty);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Schulungswesen', style: theme.textTheme.headlineSmall),
              const Spacer(),
              IconButton(
                onPressed: _loading ? null : _loadMetrics,
                tooltip: 'Aktualisieren',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Übersicht über Bedarfe, Programme, Schulungslisten und Wirksamkeitskontrollen.',
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (showSetupInfo) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Setup incomplete',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _error != null
                              ? 'Kennzahlen konnten nicht geladen werden. Bitte Schnittstelle prüfen.'
                              : 'Noch keine Kennzahlen verfügbar. Bitte Schulungsdaten hinterlegen.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text('Schnellzugriff', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _QuickLinkCard(
                icon: Icons.note_alt_outlined,
                title: 'Schulungsbedarf',
                subtitle: 'Bedarfe erfassen & freigeben',
                onTap: () => _openSection(TrainingAdminSection.needs),
              ),
              _QuickLinkCard(
                icon: Icons.event_note_outlined,
                title: 'Schulungsprogramm',
                subtitle: 'Programme planen & freigeben',
                onTap: () => _openSection(TrainingAdminSection.program),
              ),
              _QuickLinkCard(
                icon: Icons.school_outlined,
                title: 'Schulungslisten',
                subtitle: 'Teilnehmer & Termine',
                onTap: () => _openSection(TrainingAdminSection.list),
              ),
              _QuickLinkCard(
                icon: Icons.fact_check_outlined,
                title: 'Wirksamkeitskontrolle',
                subtitle: 'Wirksamkeit nachhalten',
                onTap: () => _openSection(TrainingAdminSection.effectiveness),
              ),
              _QuickLinkCard(
                icon: Icons.bar_chart_outlined,
                title: 'Archiv & Auswertungen',
                subtitle: 'Historie & Kennzahlen',
                onTap: () => _openSection(TrainingAdminSection.archive),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Kennzahlen', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricCard(
                label: 'Offene Bedarfe',
                value: _metricInt('openNeeds'),
                icon: Icons.note_alt_outlined,
              ),
              _MetricCard(
                label: 'Überfällige Checks',
                value: _metricInt('overdueEffectivenessChecks'),
                icon: Icons.fact_check_outlined,
              ),
              _MetricCard(
                label: 'Geplante Schulungen (Jahr)',
                value: _metricInt('plannedTrainingsThisYear'),
                icon: Icons.event_available_outlined,
              ),
              _MetricCard(
                label: 'Trainings diese Woche',
                value: _metricInt('trainingsThisWeek'),
                icon: Icons.calendar_today_outlined,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Nächste Schritte', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Bedarfe erfassen, Programme freigeben und Wirksamkeit dokumentieren. '
            'Nutzen Sie die Schnellzugriffe, um direkt in die jeweiligen Teilbereiche zu wechseln.',
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class TrainingNeedsPage extends StatelessWidget {
  const TrainingNeedsPage({super.key, required this.api, required this.canWrite, this.canDelete = false});

  final ApiClient api;
  final bool canWrite;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    return AdminTrainingPage(api: api, canWrite: canWrite, canDelete: canDelete, initialTab: 1);
  }
}

class TrainingProgramPage extends StatelessWidget {
  const TrainingProgramPage({super.key, required this.api, required this.canWrite, this.canDelete = false});

  final ApiClient api;
  final bool canWrite;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    return AdminTrainingPage(api: api, canWrite: canWrite, canDelete: canDelete, initialTab: 2);
  }
}

class TrainingListPage extends StatelessWidget {
  const TrainingListPage({super.key, required this.api, required this.canWrite, this.canDelete = false});

  final ApiClient api;
  final bool canWrite;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    return AdminTrainingPage(api: api, canWrite: canWrite, canDelete: canDelete, initialTab: 3);
  }
}

class TrainingArchivePage extends StatelessWidget {
  const TrainingArchivePage({super.key, required this.api, required this.canWrite, this.canDelete = false});

  final ApiClient api;
  final bool canWrite;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    return AdminTrainingPage(api: api, canWrite: canWrite, canDelete: canDelete, initialTab: 5);
  }
}

class TrainingEffectivenessPage extends StatelessWidget {
  const TrainingEffectivenessPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Wirksamkeitskontrolle', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Dieser Bereich ist vorbereitet, die Datenintegration fehlt jedoch noch.',
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Setup incomplete: Bitte Wirksamkeitskriterien und Datenquellen hinterlegen.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickLinkCard extends StatelessWidget {
  const _QuickLinkCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: cs.primaryContainer,
              foregroundColor: cs.primary,
              child: Icon(icon),
            ),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int? value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final display = value?.toString() ?? '—';
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.primary),
          const SizedBox(height: 10),
          Text(display, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
