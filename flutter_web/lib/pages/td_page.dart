import 'dart:async';

import 'package:flutter/material.dart';
import 'dart:html' as html;

import '../api/client.dart';
import '../models/td.dart';
import 'admin_page.dart';

class TdPage extends StatefulWidget {
  final ApiClient api;
  final bool canEdit;
  const TdPage({super.key, required this.api, required this.canEdit});

  @override
  State<TdPage> createState() => _TdPageState();
}

class _TdPageState extends State<TdPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<TdFile> _items = const [];
  TdFile? _selected;
  List<TdSection> _sections = const [];
  List<TdChangeRequest> _changes = const [];
  List<TdArtifactLink> _links = const [];
  bool _loading = true;
  bool _isLoadingSummary = false;
  bool _summaryFailureLogged = false;
  String? _error;
  Map<String, dynamic>? _readiness;
  TdApplicabilityBundle? _applicability;

  static const List<String> _linkTypes = ['Document', 'ExternalLink', 'GSPR', 'FMEA', 'CAPA', 'Supplier', 'Training', 'Report', 'Change'];
  static const List<String> _profileTypes = ['ROTARY_REUSABLE_NONSTERILE', 'ROTARY_REUSABLE_SURGICAL', 'DENTAL_ALLOYS', 'SOFTWARE_DEVICE'];
  static const List<String> _packagingTypes = ['BULK_NONSTERILE', 'UNIT_NONSTERILE', 'STERILE_BARRIER_SYSTEM', 'TRANSPORT_VALIDATED'];

  String _statusDe(String status) {
    switch (status) {
      case 'NotStarted':
        return 'Nicht gestartet';
      case 'InProgress':
        return 'In Bearbeitung';
      case 'Complete':
        return 'Abgeschlossen';
      case 'Blocked':
        return 'Blockiert';
      case 'NotApplicable':
        return 'Nicht zutreffend';
      default:
        return status;
    }
  }

  String _readinessDe(String status) {
    switch (status) {
      case 'Green':
        return 'Grün';
      case 'Yellow':
        return 'Gelb';
      case 'Red':
        return 'Rot';
      default:
        return status;
    }
  }

  Color _readinessColor(String status) {
    switch (status) {
      case 'Green':
        return const Color(0xFF22C55E);
      case 'Yellow':
        return const Color(0xFFF59E0B);
      case 'Red':
        return const Color(0xFFEF4444);
      default:
        return Colors.grey;
    }
  }

  int _completionPercent(TdFile td) {
    final raw = (_readiness?['complianceScore'] as num?)?.toInt() ?? td.summary.complianceScore;
    return raw.clamp(0, 100);
  }

  String _annexLabelDe(String key) {
    if (key.startsWith('ANNEX_II_')) {
      return 'Anhang II ${key.split('_').last}';
    }
    if (key.startsWith('ANNEX_III_')) {
      return 'Anhang III ${key.split('_').last}';
    }
    return key;
  }

  String _gapDe(String gap) {
    final mandatoryOpen = RegExp(r'^([A-Z_0-9]+): mandatory queries open \((\d+)\)$').firstMatch(gap);
    if (mandatoryOpen != null) {
      final annex = _annexLabelDe(mandatoryOpen.group(1)!);
      final count = mandatoryOpen.group(2)!;
      return '$annex: $count verpflichtende Abfragen offen.';
    }
    final missingLink = RegExp(r'^([A-Z_0-9]+): missing mandatory link (.+)$').firstMatch(gap);
    if (missingLink != null) {
      final annex = _annexLabelDe(missingLink.group(1)!);
      final linkType = missingLink.group(2)!;
      return '$annex: Pflichtverlinkung fehlt ($linkType).';
    }
    switch (gap) {
      case 'Missing mandatory link: one GSPR link in section D':
        return 'Pflichtverlinkung fehlt: mindestens ein GSPR-Link in Abschnitt D.';
      case 'Missing mandatory link: one FMEA link in section E':
        return 'Pflichtverlinkung fehlt: mindestens ein FMEA-Link in Abschnitt E.';
      case 'Missing mandatory link: one Verification/Report in sections G/H':
        return 'Pflichtverlinkung fehlt: mindestens ein Verifizierungs-/Berichtslink in Abschnitt G/H.';
      default:
        return gap;
    }
  }

  String _profileTypeDe(String value) {
    switch (value) {
      case 'ROTARY_REUSABLE_NONSTERILE':
        return 'Rotierend, wiederverwendbar, unsteril';
      case 'ROTARY_REUSABLE_SURGICAL':
        return 'Rotierend, wiederverwendbar, chirurgisch';
      case 'DENTAL_ALLOYS':
        return 'Dentallegierungen';
      case 'SOFTWARE_DEVICE':
        return 'Softwareprodukt';
      default:
        return value;
    }
  }

  String _packagingTypeDe(String value) {
    switch (value) {
      case 'BULK_NONSTERILE':
        return 'Bulk, unsteril';
      case 'UNIT_NONSTERILE':
        return 'Einzelverpackt, unsteril';
      case 'STERILE_BARRIER_SYSTEM':
        return 'Sterilbarrieresystem';
      case 'TRANSPORT_VALIDATED':
        return 'Transportvalidiert';
      default:
        return value;
    }
  }

  String _boolDe(bool value) => value ? 'Ja' : 'Nein';



  String _changeTypeDe(String type) {
    switch (type) {
      case 'Material':
        return 'Material';
      case 'Supplier':
        return 'Lieferant';
      case 'LabelingIFU':
        return 'Kennzeichnung/IFU';
      case 'Other':
        return 'Sonstiges';
      default:
        return type;
    }
  }

  String _severityDe(String severity) {
    switch (severity) {
      case 'Low':
        return 'Niedrig';
      case 'Medium':
        return 'Mittel';
      case 'High':
        return 'Hoch';
      case 'Critical':
        return 'Kritisch';
      default:
        return severity;
    }
  }

  String _linkTypeDe(String type) {
    switch (type) {
      case 'Document':
        return 'Dokument';
      case 'ExternalLink':
        return 'Externer Link';
      case 'GSPR':
        return 'GSPR';
      case 'FMEA':
        return 'FMEA';
      case 'CAPA':
        return 'CAPA';
      case 'Supplier':
        return 'Lieferant';
      case 'Training':
        return 'Schulung';
      case 'Report':
        return 'Bericht';
      case 'Change':
        return 'Änderung';
      case 'ComplaintMetric':
        return 'Reklamationskennzahl';
      default:
        return type;
    }
  }

  String _sectionNameDe(TdSection section) {
    switch (section.templateKey) {
      case 'ANNEX_II_A':
        return 'A. Produktbeschreibung und Spezifikation';
      case 'ANNEX_II_B':
        return 'B. Vom Hersteller bereitgestellte Informationen';
      case 'ANNEX_II_C':
        return 'C. Informationen zu Design und Herstellung';
      case 'ANNEX_II_D':
        return 'D. Allgemeine Sicherheits- und Leistungsanforderungen (GSPR)';
      case 'ANNEX_II_E':
        return 'E. Nutzen-Risiko und Risikomanagement';
      case 'ANNEX_II_F':
        return 'F. Produktverifizierung und -validierung';
      case 'ANNEX_III_G':
        return 'G. PMS-Plan';
      case 'ANNEX_III_H':
        return 'H. PMS-Bericht / PSUR / PMCF';
      default:
        return section.name;
    }
  }

  bool _structureLoaded = false;
  bool _isLoadingStructure = false;
  bool _linksLoaded = false;
  bool _changesLoaded = false;
  bool _applicabilityLoaded = false;
  bool _readinessLoaded = false;
  bool _isLoadingReadiness = false;
  bool _isLoadingApplicability = false;
  bool _isLoadingChanges = false;
  bool _isLoadingLinks = false;
  bool _overviewStageLoaded = false;
  bool _sectionsMetaStageLoaded = false;
  Map<String, dynamic> _overviewLight = const {};
  int? _sectionsNextCursor;
  final Map<String, TdSection> _sectionContentById = <String, TdSection>{};
  final Set<String> _sectionContentLoading = <String>{};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 8, vsync: this);
    _tabs.addListener(_handleTabChange);
    _load();
  }

  @override
  void dispose() {
    _tabs.removeListener(_handleTabChange);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _isLoadingSummary = true;
      _error = null;
    });

    try {
      final list = await widget.api.fetchTdSummary(timeout: const Duration(milliseconds: 1200), optional: true);
      final selected = list.isNotEmpty
          ? (_selected == null ? list.first : list.firstWhere((e) => e.id == _selected!.id, orElse: () => list.first))
          : null;

      if (!mounted) return;
      setState(() {
        _items = list;
        _selected = selected;
        _sections = const [];
        _changes = const [];
        _links = const [];
        _readiness = null;
        _applicability = null;
        _overviewLight = const {};
        _overviewStageLoaded = false;
        _sectionsMetaStageLoaded = false;
        _structureLoaded = false;
        _sectionsNextCursor = null;
        _sectionContentById.clear();
        _sectionContentLoading.clear();
        _linksLoaded = false;
        _changesLoaded = false;
        _applicabilityLoaded = false;
        _readinessLoaded = false;
      });

      if (selected != null) {
        unawaited(_loadStartupData(selected.id));
      }

      if (list.isEmpty) {
        unawaited(_refreshSummaryInBackground());
      }
    } catch (e) {
      if (!_summaryFailureLogged) {
        _summaryFailureLogged = true;
        debugPrint('[td] summary optional fetch failed: $e');
      }
      unawaited(_refreshSummaryInBackground());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _isLoadingSummary = false;
        });
      }
    }
  }

  void _handleTabChange() {
    if (_tabs.indexIsChanging) return;
    _ensureTabLoaded(_tabs.index);
  }

  Future<void> _loadStartupData(String tdId) async {
    unawaited(_loadStartupOverview(tdId));
    unawaited(_loadStartupSectionsMeta(tdId));
  }

  Future<void> _loadStartupOverview(String tdId) async {
    try {
      final overview = await widget.api.fetchTdOverview(tdId);
      if (!mounted) return;
      setState(() {
        _overviewLight = overview;
        _overviewStageLoaded = true;
      });
    } catch (e) {
      if (!_summaryFailureLogged) {
        _summaryFailureLogged = true;
        debugPrint('[td] startup overview failed: $e');
      }
    }
  }

  Future<void> _loadStartupSectionsMeta(String tdId) async {
    try {
      final page = await widget.api.fetchTdSectionsPaged(tdId, limit: 50, cursor: 0);
      if (!mounted) return;
      setState(() {
        _sections = page.$1;
        _sectionsNextCursor = page.$2;
        _structureLoaded = true;
        _sectionsMetaStageLoaded = true;
      });
    } catch (e) {
      if (!_summaryFailureLogged) {
        _summaryFailureLogged = true;
        debugPrint('[td] startup sections/meta failed: $e');
      }
    }
  }

  Future<void> _refreshSummaryInBackground() async {
    try {
      final list = await widget.api.fetchTdSummary();
      if (!mounted || list.isEmpty) return;
      final selected = _selected == null ? list.first : list.firstWhere((e) => e.id == _selected!.id, orElse: () => list.first);
      setState(() {
        _items = list;
        _selected = selected;
      });
      unawaited(_loadStartupData(selected.id));
    } catch (_) {
      // Optional background refresh.
    }
  }

  Future<void> _ensureTabLoaded(int tabIndex) async {
    final td = _selected;
    if (td == null) return;
    if (tabIndex == 1 && !_structureLoaded) {
      await _runHeavyOperation(
        key: 'structure',
        onRun: () async {
          final page = await widget.api.fetchTdSectionsPaged(td.id, limit: 50, cursor: 0);
          if (!mounted) return;
          setState(() {
            _sections = page.$1;
            _sectionsNextCursor = page.$2;
            _structureLoaded = true;
            _sectionsMetaStageLoaded = true;
          });
        },
      );
    }
    if (tabIndex == 2 && !_applicabilityLoaded) {
      await _runHeavyOperation(
        key: 'applicability',
        onRun: () async {
          final bundle = await widget.api.fetchTdApplicability(td.id);
          if (!mounted) return;
          setState(() {
            _applicability = bundle;
            _applicabilityLoaded = true;
          });
        },
      );
    }
    if (tabIndex == 3 && !_linksLoaded) {
      await _runHeavyOperation(
        key: 'links',
        onRun: () async {
          final links = await widget.api.fetchTdLinks(td.id);
          if (!mounted) return;
          setState(() {
            _links = links;
            _linksLoaded = true;
          });
        },
      );
    }
    if (tabIndex == 4 && !_changesLoaded) {
      await _runHeavyOperation(
        key: 'changes',
        onRun: () async {
          final changes = await widget.api.fetchTdChanges(td.id);
          if (!mounted) return;
          setState(() {
            _changes = changes;
            _changesLoaded = true;
          });
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!));
    return Row(children: [
      SizedBox(width: 340, child: Card(child: Column(children: [if (widget.canEdit) Padding(padding: const EdgeInsets.all(8), child: FilledButton.icon(onPressed: _openCreateTdWizard, icon: const Icon(Icons.add), label: const Text('TD erstellen'))), Expanded(child: _isLoadingSummary && _items.isEmpty ? ListView.builder(itemCount: 6, itemBuilder: (_, __) => const ListTile(title: Text('TD wird geladen...'), subtitle: LinearProgressIndicator())) : ListView(children: _items.map((td) => ListTile(title: Text(td.title, maxLines: 2, overflow: TextOverflow.ellipsis), subtitle: Text('Fortschritt ${_completionPercent(td)} %'), selected: _selected?.id == td.id, onTap: () async {
                            setState(() {
                              _selected = td;
                              _sections = const [];
                              _changes = const [];
                              _links = const [];
                              _readiness = null;
                              _applicability = null;
                              _overviewLight = const {};
                              _overviewStageLoaded = false;
                              _sectionsMetaStageLoaded = false;
                              _structureLoaded = false;
                              _sectionsNextCursor = null;
                              _sectionContentById.clear();
                              _sectionContentLoading.clear();
                              _linksLoaded = false;
                              _changesLoaded = false;
                              _applicabilityLoaded = false;
                              _readinessLoaded = false;
                            });
                            unawaited(_loadStartupData(td.id));
                            await _ensureTabLoaded(_tabs.index);
                          },)).toList()))]))),
      const SizedBox(width: 12),
      Expanded(child: Card(child: Column(children: [
        TabBar(controller: _tabs, isScrollable: true, onTap: (index) => _ensureTabLoaded(index), tabs: const [Tab(text: 'Übersicht'), Tab(text: 'Struktur'), Tab(text: 'Anwendbarkeit'), Tab(text: 'Links'), Tab(text: 'Änderungsmanagement'), Tab(text: 'Heatmap'), Tab(text: 'Benannte-Stelle-Export'), Tab(text: 'Kalender')]),
        Expanded(child: TabBarView(controller: _tabs, children: [_dashboardTab(), _structureTab(), _applicabilityTab(), _linksTab(), _changesTab(), _heatmapTab(), _exportTab(), _calendarTab()])),
      ]))),
    ]);
  }


  Future<void> _runHeavyOperation({required String key, required Future<void> Function() onRun}) async {
    final status = {
      'readiness': 'Readiness-Analyse läuft...',
      'applicability': 'Anwendbarkeit wird berechnet...',
      'changes': 'Change-Analyse läuft...',
      'structure': 'Struktur wird geladen (Abschnitte & Zähler)...',
      'links': 'Links werden geladen...',
    }[key] ?? 'Analyse wird durchgeführt...';
    final stages = {
      'readiness': const ['Übersicht', 'Struktur', 'Readiness', 'Finalisiere'],
      'applicability': const ['Profil laden', 'Regeln anwenden', 'Ergebnisse schreiben', 'Finalisiere'],
      'changes': const ['Daten laden', 'Klassifizieren', 'Validieren', 'Finalisiere'],
      'structure': const ['Übersicht', 'Sektionen laden', 'Metriken berechnen', 'Finalisiere'],
      'links': const ['Links laden', 'Validieren', 'Zuordnen', 'Finalisiere'],
    }[key] ?? const ['Initialisiere', 'Verarbeite', 'Validiere', 'Finalisiere'];
    final completeSignal = ValueNotifier<bool>(false);

    if (key == 'readiness' && _isLoadingReadiness) return;
    if (key == 'applicability' && _isLoadingApplicability) return;
    if (key == 'changes' && _isLoadingChanges) return;
    if (key == 'structure' && _isLoadingStructure) return;
    if (key == 'links' && _isLoadingLinks) return;

    setState(() {
      if (key == 'readiness') _isLoadingReadiness = true;
      if (key == 'applicability') _isLoadingApplicability = true;
      if (key == 'changes') _isLoadingChanges = true;
      if (key == 'structure') _isLoadingStructure = true;
      if (key == 'links') _isLoadingLinks = true;
    });

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TdHeavyProgressDialog(statusText: status, stages: stages, completed: completeSignal),
    );

    try {
      await onRun();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Analyse abgeschlossen')));
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Fehler bei Analyse'),
          content: Text('Die Analyse konnte nicht abgeschlossen werden.\n\n$e'),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );
    } finally {
      completeSignal.value = true;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      completeSignal.dispose();
      if (mounted) {
        setState(() {
          if (key == 'readiness') _isLoadingReadiness = false;
          if (key == 'applicability') _isLoadingApplicability = false;
          if (key == 'changes') _isLoadingChanges = false;
          if (key == 'structure') _isLoadingStructure = false;
          if (key == 'links') _isLoadingLinks = false;
        });
      }
    }
  }

  Future<void> _loadMoreSections() async {
    final td = _selected;
    final next = _sectionsNextCursor;
    if (td == null || next == null || _isLoadingStructure) return;
    setState(() => _isLoadingStructure = true);
    try {
      final page = await widget.api.fetchTdSectionsPaged(td.id, limit: 50, cursor: next);
      if (!mounted) return;
      setState(() {
        _sections = [..._sections, ...page.$1];
        _sectionsNextCursor = page.$2;
      });
    } finally {
      if (mounted) setState(() => _isLoadingStructure = false);
    }
  }

  Future<void> _loadReadiness() async {
    final td = _selected;
    if (td == null || _readinessLoaded) return;
    await _runHeavyOperation(
      key: 'readiness',
      onRun: () async {
        final readiness = await widget.api.fetchTdReadiness(td.id);
        if (!mounted) return;
        setState(() {
          _readiness = readiness;
          _readinessLoaded = true;
        });
      },
    );
  }


  Widget _dashboardTab() {
    final td = _selected;
    if (td == null) return const Center(child: Text('Keine TD ausgewählt. Die Liste wird im Hintergrund geladen.'));
    final startupDone = _overviewStageLoaded && _sectionsMetaStageLoaded;
    final readinessStatus = (_readiness?['readinessStatus'] ?? td.summary.readinessStatus).toString();
    final progressPercent = _completionPercent(td);
    final gaps = (_readiness?['gaps'] as List?)?.map((e) => '$e').toList() ?? const [];
    final sectionCount = (_overviewLight['section_count'] as num?)?.toInt() ?? 0;
    final answeredCount = (_overviewLight['answered_count'] as num?)?.toInt() ?? 0;
    final linkCount = (_overviewLight['link_count'] as num?)?.toInt() ?? 0;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (!startupDone)
        const Card(
          child: ListTile(
            title: Text('TD wird vorbereitet...'),
            subtitle: Text('Stufe 1: Übersicht laden · Stufe 2: Abschnitt-Metadaten laden'),
          ),
        ),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(colors: [Color(0xFFF8FAFF), Color(0xFFEEF4FF)]),
          border: Border.all(color: const Color(0xFFDCE6FF)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(td.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Wrap(spacing: 16, runSpacing: 12, children: [
            _trafficLightCard(readinessStatus),
            _progressCard(progressPercent),
            Chip(label: Text('Sektionen: $sectionCount')),
            Chip(label: Text('Beantwortet: $answeredCount')),
            Chip(label: Text('Links: $linkCount')),
          ]),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _isLoadingReadiness ? null : _loadReadiness,
            icon: _isLoadingReadiness ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.analytics_outlined),
            label: const Text('Readiness-Analyse starten'),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      ...gaps.map((g) => ListTile(leading: const Icon(Icons.error_outline), title: Text(_gapDe(g)))),
    ]);
  }

  Widget _trafficLightCard(String readinessStatus) {
    final activeColor = _readinessColor(readinessStatus);
    Widget light(Color color, bool active) => Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: active ? color : color.withOpacity(0.2),
            shape: BoxShape.circle,
            boxShadow: active ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 10, spreadRadius: 1)] : null,
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5EAF7)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Reifegrad'),
        const SizedBox(height: 6),
        Row(mainAxisSize: MainAxisSize.min, children: [
          light(const Color(0xFFEF4444), readinessStatus == 'Red'),
          const SizedBox(width: 8),
          light(const Color(0xFFF59E0B), readinessStatus == 'Yellow'),
          const SizedBox(width: 8),
          light(const Color(0xFF22C55E), readinessStatus == 'Green'),
        ]),
      ]),
    );
  }

  Widget _progressCard(int progressPercent) {
    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5EAF7)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('TD-Fortschritt: $progressPercent %', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 10,
            value: progressPercent / 100,
            backgroundColor: const Color(0xFFE7EDFF),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1D4ED8)),
          ),
        ),
      ]),
    );
  }

  Widget _structureTab() {
    if (!_structureLoaded) {
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: 6,
        itemBuilder: (_, __) => const Card(child: ListTile(title: Text('Abschnitt wird geladen...'), subtitle: LinearProgressIndicator())),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ..._sections.map((s) {
          final details = _sectionContentById[s.id];
          final detailSummary = details?.content?.summaryMarkdown ?? '';
          final isLoading = _sectionContentLoading.contains(s.id);
          return Card(
            child: ExpansionTile(
              title: Text(_sectionNameDe(s)),
              subtitle: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (s.completion != null) Chip(label: Text('Vollständigkeit ${s.completion}%')),
                ],
              ),
              trailing: Chip(label: Text(_statusDe(s.status))),
              onExpansionChanged: (expanded) {
                if (expanded) unawaited(_loadSectionContent(s.id));
              },
              children: [
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: LinearProgressIndicator(),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(detailSummary.isEmpty ? 'Keine Abschnittsinhalte vorhanden.' : detailSummary, maxLines: 4, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            if (_selected == null) return;
                            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TdSectionDetailPage(api: widget.api, td: _selected!, sectionId: s.id, canEdit: widget.canEdit)));
                            _load();
                          },
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Details öffnen'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
        if (_sectionsNextCursor != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: FilledButton.icon(
                onPressed: _isLoadingStructure ? null : _loadMoreSections,
                icon: _isLoadingStructure
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.expand_more),
                label: const Text('Mehr laden'),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _loadSectionContent(String sectionId) async {
    final td = _selected;
    if (td == null || _sectionContentById.containsKey(sectionId) || _sectionContentLoading.contains(sectionId)) return;
    setState(() => _sectionContentLoading.add(sectionId));
    try {
      final map = await widget.api.fetchTdSectionContent(td.id, sectionId);
      if (!mounted) return;
      setState(() => _sectionContentById[sectionId] = TdSection.fromJson(map));
    } catch (_) {
      // optional for preview
    } finally {
      if (mounted) {
        setState(() => _sectionContentLoading.remove(sectionId));
      }
    }
  }

  Chip _applicabilityChip(String state) {
    final map = {
      'MANDATORY': 'Verbindlich',
      'OPTIONAL': 'Optional',
      'CONDITIONAL': 'Bedingt',
      'NOT_APPLICABLE': 'Nicht zutreffend',
    };
    return Chip(label: Text(map[state] ?? state));
  }

  Future<void> _openCreateTdWizard() async {
    final codeCtl = TextEditingController();
    final titleCtl = TextEditingController();
    final groupCtl = TextEditingController();
    final classCtl = TextEditingController(text: 'IIa');
    final ruleCtl = TextEditingController(text: 'Regel 5.4');
    TdApplicabilityProfile profile = const TdApplicabilityProfile(profileType: 'ROTARY_REUSABLE_NONSTERILE', isReusable: true, isSterile: false, packagingType: 'BULK_NONSTERILE', classificationRule: 'Regel 5.4', hasSoftware: false, notes: null);
    final ok = await showDialog<bool>(context: context, builder: (_) => StatefulBuilder(builder: (_, setS) => AlertDialog(
      title: const Text('Assistent für TD-Erstellung'),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: codeCtl, decoration: const InputDecoration(labelText: 'TD-Code')),
        TextField(controller: titleCtl, decoration: const InputDecoration(labelText: 'Titel')),
        TextField(controller: groupCtl, decoration: const InputDecoration(labelText: 'Produktgruppe')),
        TextField(controller: classCtl, decoration: const InputDecoration(labelText: 'Klassifizierung')),
        TextField(controller: ruleCtl, decoration: const InputDecoration(labelText: 'Regel')),
        DropdownButtonFormField<String>(
          value: profile.profileType,
          decoration: const InputDecoration(labelText: 'Profiltyp'),
          items: _profileTypes.map((e) => DropdownMenuItem(value: e, child: Text(_profileTypeDe(e)))).toList(),
          onChanged: (v) {
            if (v == null) return;
            setS(() {
              profile = TdApplicabilityProfile(profileType: v, isReusable: profile.isReusable, isSterile: profile.isSterile, packagingType: profile.packagingType, classificationRule: profile.classificationRule, hasSoftware: profile.hasSoftware, notes: profile.notes);
            });
          },
        ),
        SwitchListTile(value: profile.isReusable, onChanged: (v)=>setS(()=>profile = TdApplicabilityProfile(profileType: profile.profileType, isReusable: v, isSterile: profile.isSterile, packagingType: profile.packagingType, classificationRule: profile.classificationRule, hasSoftware: profile.hasSoftware, notes: profile.notes)), title: const Text('Wiederverwendbar')),
        SwitchListTile(value: profile.isSterile, onChanged: (v)=>setS(()=>profile = TdApplicabilityProfile(profileType: profile.profileType, isReusable: profile.isReusable, isSterile: v, packagingType: profile.packagingType, classificationRule: profile.classificationRule, hasSoftware: profile.hasSoftware, notes: profile.notes)), title: const Text('Steril')),
        SwitchListTile(value: profile.hasSoftware, onChanged: (v)=>setS(()=>profile = TdApplicabilityProfile(profileType: profile.profileType, isReusable: profile.isReusable, isSterile: profile.isSterile, packagingType: profile.packagingType, classificationRule: profile.classificationRule, hasSoftware: v, notes: profile.notes)), title: const Text('Enthält Software')),
        DropdownButtonFormField<String>(
          value: profile.packagingType,
          decoration: const InputDecoration(labelText: 'Verpackungsart'),
          items: _packagingTypes.map((e) => DropdownMenuItem(value: e, child: Text(_packagingTypeDe(e)))).toList(),
          onChanged: (v) {
            if (v == null) return;
            setS(() => profile = TdApplicabilityProfile(profileType: profile.profileType, isReusable: profile.isReusable, isSterile: profile.isSterile, packagingType: v, classificationRule: profile.classificationRule, hasSoftware: profile.hasSoftware, notes: profile.notes));
          },
        ),
      ]))),
      actions: [TextButton(onPressed: ()=>Navigator.pop(context,false), child: const Text('Abbrechen')), FilledButton(onPressed: ()=>Navigator.pop(context,true), child: const Text('Erstellen'))],
    )));
    if (ok == true) {
      await widget.api.createTdFile(code: codeCtl.text.trim(), title: titleCtl.text.trim(), productGroup: groupCtl.text.trim(), classification: classCtl.text.trim(), rule: ruleCtl.text.trim(), applicabilityProfile: profile);
      _load();
    }
  }

  Future<void> _openEditTdMetadataDialog() async {
    final selected = _selected;
    final bundle = _applicability;
    if (selected == null || bundle == null) return;

    final codeCtl = TextEditingController(text: selected.code);
    final titleCtl = TextEditingController(text: selected.title);
    final groupCtl = TextEditingController(text: selected.productGroup ?? '');
    final classCtl = TextEditingController(text: selected.classification ?? '');
    final ruleCtl = TextEditingController(text: selected.rule ?? bundle.profile.classificationRule ?? '');
    TdApplicabilityProfile profile = bundle.profile;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, setS) => AlertDialog(
          title: const Text('Metadaten bearbeiten'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: codeCtl, enabled: false, decoration: const InputDecoration(labelText: 'TD-Code')),
                TextField(controller: titleCtl, decoration: const InputDecoration(labelText: 'Titel')),
                TextField(controller: groupCtl, decoration: const InputDecoration(labelText: 'Produktgruppe')),
                TextField(controller: classCtl, decoration: const InputDecoration(labelText: 'Klassifizierung')),
                TextField(controller: ruleCtl, decoration: const InputDecoration(labelText: 'Regel')),
                DropdownButtonFormField<String>(
                  value: profile.profileType,
                  decoration: const InputDecoration(labelText: 'Profiltyp'),
                  items: _profileTypes.map((e) => DropdownMenuItem(value: e, child: Text(_profileTypeDe(e)))).toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setS(() {
                      profile = TdApplicabilityProfile(profileType: v, isReusable: profile.isReusable, isSterile: profile.isSterile, packagingType: profile.packagingType, classificationRule: profile.classificationRule, hasSoftware: profile.hasSoftware, notes: profile.notes);
                    });
                  },
                ),
                SwitchListTile(value: profile.isReusable, onChanged: (v) => setS(() => profile = TdApplicabilityProfile(profileType: profile.profileType, isReusable: v, isSterile: profile.isSterile, packagingType: profile.packagingType, classificationRule: profile.classificationRule, hasSoftware: profile.hasSoftware, notes: profile.notes)), title: const Text('Wiederverwendbar')),
                SwitchListTile(value: profile.isSterile, onChanged: (v) => setS(() => profile = TdApplicabilityProfile(profileType: profile.profileType, isReusable: profile.isReusable, isSterile: v, packagingType: profile.packagingType, classificationRule: profile.classificationRule, hasSoftware: profile.hasSoftware, notes: profile.notes)), title: const Text('Steril')),
                SwitchListTile(value: profile.hasSoftware, onChanged: (v) => setS(() => profile = TdApplicabilityProfile(profileType: profile.profileType, isReusable: profile.isReusable, isSterile: profile.isSterile, packagingType: profile.packagingType, classificationRule: profile.classificationRule, hasSoftware: v, notes: profile.notes)), title: const Text('Enthält Software')),
                DropdownButtonFormField<String>(
                  value: profile.packagingType,
                  decoration: const InputDecoration(labelText: 'Verpackungsart'),
                  items: _packagingTypes.map((e) => DropdownMenuItem(value: e, child: Text(_packagingTypeDe(e)))).toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setS(() => profile = TdApplicabilityProfile(profileType: profile.profileType, isReusable: profile.isReusable, isSterile: profile.isSterile, packagingType: v, classificationRule: profile.classificationRule, hasSoftware: profile.hasSoftware, notes: profile.notes));
                  },
                ),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Speichern'))],
        ),
      ),
    );

    if (ok == true) {
      await widget.api.patchTdFile(selected.id, {
        'title': titleCtl.text.trim(),
        'productGroup': groupCtl.text.trim(),
        'classification': classCtl.text.trim(),
        'rule': ruleCtl.text.trim(),
      });
      await widget.api.saveTdApplicabilityProfile(
        selected.id,
        TdApplicabilityProfile(
          profileType: profile.profileType,
          isReusable: profile.isReusable,
          isSterile: profile.isSterile,
          packagingType: profile.packagingType,
          classificationRule: ruleCtl.text.trim(),
          hasSoftware: profile.hasSoftware,
          notes: profile.notes,
        ),
      );
      _load();
    }
  }

  Widget _applicabilityTab() {
    final selected = _selected;
    if (selected == null) return const Center(child: Text('Keine Anwendbarkeitsdaten'));
    if (_isLoadingApplicability && !_applicabilityLoaded) return const Center(child: CircularProgressIndicator());
    final bundle = _applicability;
    if (!_applicabilityLoaded || bundle == null) return const Center(child: Text('Keine Anwendbarkeitsdaten'));
    final profile = bundle.profile;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 12, runSpacing: 12, children: [
        Chip(label: Text('Profil: ${_profileTypeDe(profile.profileType)}')),
        Chip(label: Text('Wiederverwendbar: ${_boolDe(profile.isReusable)}')),
        Chip(label: Text('Steril: ${_boolDe(profile.isSterile)}')),
        Chip(label: Text('Verpackung: ${_packagingTypeDe(profile.packagingType)}')),
        Chip(label: Text('Software: ${_boolDe(profile.hasSoftware)}')),
      ]))),
      Wrap(spacing: 8, children: [
        FilledButton.icon(onPressed: widget.canEdit ? _openEditTdMetadataDialog : null, icon: const Icon(Icons.edit_outlined), label: const Text('Metadaten bearbeiten')),
        FilledButton(
          onPressed: (widget.canEdit && !_isLoadingApplicability)
              ? () async {
                  await _runHeavyOperation(
                    key: 'applicability',
                    onRun: () async {
                      final regenerated = await widget.api.regenerateTdApplicability(selected.id);
                      if (!mounted) return;
                      setState(() {
                        _applicability = regenerated;
                        _applicabilityLoaded = true;
                      });
                    },
                  );
                }
              : null,
          child: const Text('Anwendbarkeit neu berechnen'),
        ),
      ]),
      const SizedBox(height: 12),
      ...bundle.results.where((r) => r.queryKey == null).map((r) {
        final sectionName = _sections.where((s) => s.id == r.sectionId).map((s) => _sectionNameDe(s)).cast<String?>().firstWhere((e) => e != null, orElse: () => 'Abschnitt') ?? 'Abschnitt';
        return ListTile(title: Text(sectionName), trailing: _applicabilityChip(r.state), subtitle: Text(r.conditionSummary ?? ''));
      }),
    ]);
  }

  Widget _linksTab() {
    if (!_linksLoaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Align(alignment: Alignment.centerRight, child: Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(onPressed: widget.canEdit ? () => _openAddLinkDialog() : null, icon: const Icon(Icons.add_link), label: const Text('TD-Link hinzufügen')),
      )),
      Expanded(child: ListView(children: _links.map((l) => ListTile(
        title: Text(l.label),
        subtitle: Text('${_linkTypeDe(l.type)} · ${l.sectionId ?? 'TD'}'),
        trailing: widget.canEdit
            ? Wrap(spacing: 4, children: [
                IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Bearbeiten', onPressed: () => _openAddLinkDialog(existing: l)),
                IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Löschen', onPressed: () async { await widget.api.deleteTdLink(l.id); _load(); }),
              ])
            : null,
      )).toList())),
    ]);
  }

  Future<void> _openAddLinkDialog({String? sectionId, String? presetType, TdArtifactLink? existing}) async {
    if (_selected == null) return;
    final type = ValueNotifier<String>(existing?.type ?? presetType ?? 'Document');
    final labelCtl = TextEditingController(text: existing?.label ?? '');
    final refCtl = TextEditingController(text: existing?.refId ?? '');
    final urlCtl = TextEditingController(text: existing?.url ?? '');
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: Text(existing == null ? 'Link hinzufügen' : 'Link bearbeiten'),
      content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [
        ValueListenableBuilder<String>(valueListenable: type, builder: (_, v, __) => DropdownButtonFormField<String>(value: v, items: _linkTypes.map((e)=>DropdownMenuItem(value: e, child: Text(_linkTypeDe(e)))).toList(), onChanged: widget.canEdit ? (x){ if (x != null) type.value = x; } : null)),
        TextField(controller: labelCtl, decoration: const InputDecoration(labelText: 'Bezeichnung')),
        TextField(controller: refCtl, decoration: const InputDecoration(labelText: 'Referenz-ID')),
        TextField(controller: urlCtl, decoration: const InputDecoration(labelText: 'URL')),
      ])),
      actions: [TextButton(onPressed: ()=>Navigator.pop(context,false), child: const Text('Abbrechen')), FilledButton(onPressed: ()=>Navigator.pop(context,true), child: const Text('Speichern'))],
    ));
    if (ok == true) {
      if (existing != null) {
        await widget.api.deleteTdLink(existing.id);
      }
      await widget.api.createTdLink(_selected!.id, {'sectionId': existing?.sectionId ?? sectionId, 'type': type.value, 'label': labelCtl.text.trim(), 'refId': refCtl.text.trim(), 'url': urlCtl.text.trim().isEmpty ? null : urlCtl.text.trim()});
      _load();
    }
  }

  Widget _changesTab() {
    if (_isLoadingChanges && !_changesLoaded) return const Center(child: CircularProgressIndicator());
    if (!_changesLoaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
    Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(onPressed: widget.canEdit ? _createChange : null, icon: const Icon(Icons.add), label: const Text('Änderungsantrag erstellen')))),
    Expanded(child: ListView(children: _changes.map((c) => ListTile(
      title: Text(c.title),
      subtitle: Text('${_changeTypeDe(c.changeType)} · ${_severityDe(c.severity)}'),
      trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Chip(label: Text(c.status)),
        if (widget.canEdit) IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Bearbeiten', onPressed: () => _editChange(c)),
        if (widget.canEdit) IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Löschen', onPressed: () async { await widget.api.deleteTdChange(c.id); _load(); }),
      ]),
      onTap: () async {
        final detail = await widget.api.fetchTdChange(c.id);
        if (!mounted) return;
        showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => _ChangeDetailSheet(change: detail, canEdit: widget.canEdit, api: widget.api));
      },
    )).toList())),
  ]);
  }


  Future<void> _editChange(TdChangeRequest change) async {
    final title = TextEditingController(text: change.title);
    final desc = TextEditingController(text: change.description);
    String type = change.changeType;
    String severity = change.severity;
    final ok = await showDialog<bool>(context: context, builder: (_) => StatefulBuilder(builder: (_, setS) => AlertDialog(
      title: const Text('Änderungsantrag bearbeiten'),
      content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Titel')),
        DropdownButtonFormField<String>(value: type, items: const ['Material','Supplier','LabelingIFU','Other'].map((e)=>DropdownMenuItem(value:e, child: Text(_changeTypeDe(e)))).toList(), onChanged: (v)=>setS(()=>type=v??'Other')),
        DropdownButtonFormField<String>(value: severity, items: const ['Low','Medium','High','Critical'].map((e)=>DropdownMenuItem(value:e, child: Text(_severityDe(e)))).toList(), onChanged: (v)=>setS(()=>severity=v??'Medium')),
        TextField(controller: desc, decoration: const InputDecoration(labelText: 'Beschreibung'), minLines: 2, maxLines: 5),
      ])),
      actions: [TextButton(onPressed: ()=>Navigator.pop(context,false), child: const Text('Abbrechen')), FilledButton(onPressed: ()=>Navigator.pop(context,true), child: const Text('Speichern'))],
    )));
    if (ok == true) {
      await widget.api.patchTdChange(change.id, {'title': title.text.trim(), 'description': desc.text.trim(), 'changeType': type, 'severity': severity});
      _load();
    }
  }

  Future<void> _createChange() async {
    if (_selected == null) return;
    final title = TextEditingController();
    final desc = TextEditingController();
    String type = 'Material';
    String severity = 'Medium';
    final ok = await showDialog<bool>(context: context, builder: (_) => StatefulBuilder(builder: (_, setS) => AlertDialog(
      title: const Text('Änderungsantrag erstellen'),
      content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Titel')),
        DropdownButtonFormField<String>(value: type, items: const ['Material','Supplier','LabelingIFU','Other'].map((e)=>DropdownMenuItem(value:e, child: Text(_changeTypeDe(e)))).toList(), onChanged: (v)=>setS(()=>type=v??'Other')),
        DropdownButtonFormField<String>(value: severity, items: const ['Low','Medium','High','Critical'].map((e)=>DropdownMenuItem(value:e, child: Text(_severityDe(e)))).toList(), onChanged: (v)=>setS(()=>severity=v??'Medium')),
        TextField(controller: desc, decoration: const InputDecoration(labelText: 'Beschreibung'), minLines: 2, maxLines: 5),
      ])),
      actions: [TextButton(onPressed: ()=>Navigator.pop(context,false), child: const Text('Abbrechen')), FilledButton(onPressed: ()=>Navigator.pop(context,true), child: const Text('Erstellen'))],
    )));
    if (ok == true) {
      await widget.api.createTdChange(_selected!.id, {'title': title.text.trim(), 'description': desc.text.trim(), 'changeType': type, 'severity': severity});
      _load();
    }
  }

  Widget _heatmapTab() => ListView(children: [for (final s in _sections) ListTile(title: Text(_statusDe(s.status)), subtitle: Text(_sectionNameDe(s)))]);

  Widget _exportTab() => Center(child: FilledButton.icon(onPressed: _selected == null ? null : () async {
    final resp = await widget.api.exportTdNbPackage(_selected!.id);
    final url = resp['downloadUrl']?.toString();
    if (url != null && url.isNotEmpty) html.window.open(url, '_blank');
  }, icon: const Icon(Icons.picture_as_pdf), label: const Text('NB-Paket erzeugen')));

  Widget _calendarTab() => ListView(children: _sections.map((s) => ListTile(title: Text(_sectionNameDe(s)), subtitle: Text(s.nextReviewAt ?? 'nicht gesetzt'))).toList());
}


class TdHeavyProgressDialog extends StatefulWidget {
  final String statusText;
  final List<String> stages;
  final ValueNotifier<bool> completed;

  const TdHeavyProgressDialog({
    super.key,
    required this.statusText,
    required this.stages,
    required this.completed,
  });

  @override
  State<TdHeavyProgressDialog> createState() => _TdHeavyProgressDialogState();
}

class _TdHeavyProgressDialogState extends State<TdHeavyProgressDialog> {
  static const _tickDuration = Duration(milliseconds: 350);
  late final DateTime _startedAt;
  Timer? _ticker;
  double _progress = 0.08;
  bool _indeterminateFinalization = false;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    widget.completed.addListener(_onCompletedChanged);
    _ticker = Timer.periodic(_tickDuration, (_) {
      if (!mounted || widget.completed.value) return;
      setState(() {
        _progress = (_progress + 0.045).clamp(0.08, 0.85);
        final elapsed = DateTime.now().difference(_startedAt);
        if (_progress >= 0.85 && elapsed > const Duration(seconds: 2)) {
          _indeterminateFinalization = true;
        }
      });
    });
  }

  void _onCompletedChanged() {
    if (!mounted || !widget.completed.value) return;
    setState(() {
      _indeterminateFinalization = false;
      _progress = 1;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.completed.removeListener(_onCompletedChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentStage = widget.completed.value
        ? widget.stages.length
        : (_progress * (widget.stages.length - 1)).floor() + 1;

    return AlertDialog(
      title: const Text('Analyse läuft'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Schritt $currentStage/${widget.stages.length}: ${widget.stages[(currentStage - 1).clamp(0, widget.stages.length - 1)]}'),
            const SizedBox(height: 10),
            if (_indeterminateFinalization)
              const LinearProgressIndicator()
            else
              LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text(_indeterminateFinalization ? 'Finalisiere Daten… (bitte kurz warten)' : '${(_progress * 100).round()} %'),
            const SizedBox(height: 8),
            Text(widget.statusText),
            const SizedBox(height: 10),
            ...widget.stages.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final done = idx < currentStage;
              final active = idx == currentStage;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      done
                          ? Icons.check_circle
                          : (active ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                      size: 16,
                      color: done || active ? const Color(0xFF1D4ED8) : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text('${idx}/${widget.stages.length} ${entry.value}'),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class TdSectionDetailPage extends StatefulWidget {
  final ApiClient api;
  final TdFile td;
  final String sectionId;
  final bool canEdit;
  const TdSectionDetailPage({super.key, required this.api, required this.td, required this.sectionId, required this.canEdit});

  @override
  State<TdSectionDetailPage> createState() => _TdSectionDetailPageState();
}

class _TdSectionDetailPageState extends State<TdSectionDetailPage> with TickerProviderStateMixin {
  TdSection? _section;
  List<TdQueryAnswer> _queries = const [];
  bool _loading = true;

  Chip _applicabilityChip(String state) {
    final map = {
      'MANDATORY': 'Verbindlich',
      'OPTIONAL': 'Optional',
      'CONDITIONAL': 'Bedingt',
      'NOT_APPLICABLE': 'Nicht zutreffend',
    };
    return Chip(label: Text(map[state] ?? state));
  }

  String _statusDe(String status) {
    switch (status) {
      case 'NotStarted': return 'Nicht gestartet';
      case 'InProgress': return 'In Bearbeitung';
      case 'Complete': return 'Abgeschlossen';
      case 'Blocked': return 'Blockiert';
      case 'NotApplicable': return 'Nicht zutreffend';
      default: return status;
    }
  }


  String _sectionNameDe(TdSection section) {
    switch (section.templateKey) {
      case 'ANNEX_II_A':
        return 'A. Produktbeschreibung und Spezifikation';
      case 'ANNEX_II_B':
        return 'B. Vom Hersteller bereitgestellte Informationen';
      case 'ANNEX_II_C':
        return 'C. Informationen zu Design und Herstellung';
      case 'ANNEX_II_D':
        return 'D. Allgemeine Sicherheits- und Leistungsanforderungen (GSPR)';
      case 'ANNEX_II_E':
        return 'E. Nutzen-Risiko und Risikomanagement';
      case 'ANNEX_II_F':
        return 'F. Produktverifizierung und -validierung';
      case 'ANNEX_III_G':
        return 'G. PMS-Plan';
      case 'ANNEX_III_H':
        return 'H. PMS-Bericht / PSUR / PMCF';
      default:
        return section.name;
    }
  }

  static const Map<String, String> _queryTitleDeMap = {
    'ANNEX_II_A_1': 'Zweckbestimmung und klinischer Nutzen',
    'ANNEX_II_A_2': 'Produktbeschreibung, Materialien und Varianten',
    'ANNEX_II_A_3': 'UDI-DI- und Basic-UDI-DI-Zuordnung',
    'ANNEX_II_A_4': 'Klassifizierung und Begründung der Regelanwendung',
    'ANNEX_II_A_5': 'Funktionsprinzip und Leistungsansprüche',
    'ANNEX_II_A_6': 'Vorgängergenerationen / ähnliche Produkte',
    'ANNEX_II_B_1': 'Vollständigkeit der Kennzeichnung',
    'ANNEX_II_B_2': 'Vollständigkeit der IFU inkl. Aufbereitung',
    'ANNEX_II_B_3': 'Sprach- und Übersetzungskontrolle',
    'ANNEX_II_B_4': 'Rückverfolgbarkeit von Kennzeichnungs-/IFU-Revisionen',
    'ANNEX_II_B_5': 'Anwenderschulung und Kommunikation',
    'ANNEX_II_C_1': 'Überblick Herstellprozess',
    'ANNEX_II_C_2': 'Kritische Prozessparameter und Kontrollen',
    'ANNEX_II_C_3': 'Ausgelagerte Prozesse und Kontrollen',
    'ANNEX_II_C_4': 'Akzeptanzkriterien und Prüfpläne',
    'ANNEX_II_C_5': 'Änderungsmanagement und Designtransfer',
    'ANNEX_II_D_1': 'GSPR-Vollständigkeit und offene Lücken',
    'ANNEX_II_D_2': 'Nachweis-Mapping pro Anforderung',
    'ANNEX_II_D_3': 'Rationale für nicht zutreffende Anforderungen',
    'ANNEX_II_D_4': 'Normen-/CS-Mapping und Stand',
    'ANNEX_II_D_5': 'CAPA-/Abweichungsrückkopplung in GSPR',
    'ANNEX_II_E_1': 'Vollständigkeit der Risikomanagementakte',
    'ANNEX_II_E_2': 'Begründung der Nutzen-Risiko-Schlussfolgerung',
    'ANNEX_II_E_3': 'Restrisiken und IFU-Kommunikation',
    'ANNEX_II_E_4': 'Rückkopplung von Post-Market-Risiken',
    'ANNEX_II_F_1': 'Angewandte Normen und Common Specs',
    'ANNEX_II_F_2': 'Biokompatibilität / chemische Charakterisierung',
    'ANNEX_II_F_3': 'Validierung der Aufbereitung',
    'ANNEX_II_F_4': 'Nachweise zur Leistungsprüfung',
    'ANNEX_II_F_5': 'Validierung der Verpackung',
    'ANNEX_II_F_6': 'Softwarevalidierung (falls zutreffend)',
    'ANNEX_III_G_1': 'PMS-Plan: Umfang und Verantwortlichkeiten',
    'ANNEX_III_G_2': 'PMS-Datenquellen',
    'ANNEX_III_G_3': 'Signale, Schwellenwerte und Trigger',
    'ANNEX_III_G_4': 'Anwendbarkeit des PMCF-Plans',
    'ANNEX_III_H_1': 'Anwendbarer Berichtstyp und Begründung',
    'ANNEX_III_H_2': 'Berichtszeitraum und Kernergebnisse',
    'ANNEX_III_H_3': 'Trendanalyse und Reklamationsbezug',
    'ANNEX_III_H_4': 'Umgesetzte Maßnahmen und Verknüpfungen',
    'ANNEX_III_H_5': 'Schlussfolgerungen zu Nutzen-Risiko und GSPR',
  };

  static const Map<String, String> _queryDescriptionDeMap = {
    'ANNEX_II_A_1': 'Definieren Sie Zweckbestimmung und erwarteten klinischen Nutzen; stimmen Sie Aussagen mit klinischer Evidenz und verknüpften GSPR-Anforderungen ab.',
    'ANNEX_II_A_2': 'Beschreiben Sie Materialien, Geometrie, Varianten und Zubehör mit Verweisen auf Zeichnungen/Spezifikationen und risikorelevante Eigenschaften.',
    'ANNEX_II_A_3': 'Dokumentieren Sie die UDI-DI-/Basic-UDI-DI-Strategie und die Rückverfolgbarkeit zu Etiketten- und IFU-Versionen.',
    'ANNEX_II_A_4': 'Dokumentieren Sie die MDR-Klasse und die angewandte Klassifizierungsregel mit Begründung und Referenzen.',
    'ANNEX_II_A_5': 'Beschreiben Sie das Funktionsprinzip und zentrale Leistungsansprüche mit Verweisen auf Validierungsnachweise.',
    'ANNEX_II_A_6': 'Verweisen Sie auf Vorgängergenerationen oder ähnliche Produkte und fassen Sie die Relevanz für das aktuelle Nutzen-Risiko-Profil zusammen.',
    'ANNEX_II_B_1': 'Bestätigen Sie, dass die Kennzeichnung Symbole, Warnhinweise, UDI, Hersteller- und Rechtsangaben für Zielmärkte vollständig abdeckt.',
    'ANNEX_II_B_2': 'Bestätigen Sie, dass die IFU Zweckbestimmung, Kontraindikationen, Warnhinweise und ggf. Aufbereitungsanweisungen enthält.',
    'ANNEX_II_B_3': 'Dokumentieren Sie Sprachvarianten, Übersetzungsworkflow und Freigabekontrollen.',
    'ANNEX_II_B_4': 'Zeigen Sie die Synchronisierung zwischen Kennzeichnungs-/IFU-Revisionen und TD-/Änderungskontroll-Updates.',
    'ANNEX_II_B_5': 'Definieren Sie Schulungsbedarfe, Kommunikationskanäle und zugehörige Nachweise.',
    'ANNEX_II_C_1': 'Stellen Sie eine Prozessübersicht und Standortverantwortlichkeiten für Herstellung und Freigabe bereit.',
    'ANNEX_II_C_2': 'Definieren Sie kritische Prozessparameter, Kontrollen, Grenzen und Überwachungsansätze.',
    'ANNEX_II_C_3': 'Beschreiben Sie ausgelagerte Tätigkeiten sowie Qualifizierungs-/Auditkontrollen für externe Partner.',
    'ANNEX_II_C_4': 'Dokumentieren Sie Wareneingangs-, Inprozess- und Endprüfkriterien inklusive Stichprobenplänen.',
    'ANNEX_II_C_5': 'Erläutern Sie Designtransfer-Kontrollen und die Verknüpfung zum formalen Änderungsmanagement.',
    'ANNEX_II_D_1': 'Bewerten Sie den aktuellen GSPR-Erfüllungsgrad und listen Sie offene Anforderungen auf.',
    'ANNEX_II_D_2': 'Ordnen Sie jeder GSPR-Anforderung einen belastbaren Nachweis (Dokument/Bericht) zu.',
    'ANNEX_II_D_3': 'Begründen Sie nachvollziehbar, warum einzelne GSPR-Anforderungen nicht anwendbar sind.',
    'ANNEX_II_D_4': 'Dokumentieren Sie die Zuordnung zu harmonisierten Normen/Common Specifications und deren Umsetzungsstand.',
    'ANNEX_II_D_5': 'Beschreiben Sie, wie CAPA/Abweichungen in die GSPR-Bewertung zurückgespiegelt werden.',
    'ANNEX_II_E_1': 'Bestätigen Sie, dass die Risikomanagementakte vollständig und für den aktuellen Designstand aktuell ist.',
    'ANNEX_II_E_2': 'Dokumentieren Sie die Begründung der Nutzen-Risiko-Bewertung mit klinischer und PMS-Evidenz.',
    'ANNEX_II_E_3': 'Bestätigen Sie, dass Restrisiken akzeptabel sind und bei Bedarf in IFU/Kennzeichnung kommuniziert werden.',
    'ANNEX_II_E_4': 'Zeigen Sie, wie Post-Market-Signale in Risikomanagement und CAPA zurückgeführt werden.',
    'ANNEX_II_F_1': 'Listen Sie anwendbare Normen/Common Specifications und den aktuellen Konformitätsnachweis auf.',
    'ANNEX_II_F_2': 'Fassen Sie Biokompatibilitäts- und Chemie-Nachweise entsprechend dem Patientenkontakt zusammen.',
    'ANNEX_II_F_3': 'Geben Sie den Validierungsstand für Reinigung/Desinfektion/Sterilisation inkl. Referenzen an.',
    'ANNEX_II_F_4': 'Fassen Sie Bench-/Leistungsprüfungen zur Stützung der Zweckbestimmung zusammen.',
    'ANNEX_II_F_5': 'Fassen Sie Nachweise zur Verpackungsintegrität, Haltbarkeit und Transportvalidierung zusammen.',
    'ANNEX_II_F_6': 'Stellen Sie Software-Lifecycle- und Validierungsnachweise bereit oder begründen Sie die Nichtanwendbarkeit.',
    'ANNEX_III_G_1': 'Dokumentieren Sie Eigentümerschaft, Umfang und Verantwortlichkeiten des PMS-Plans.',
    'ANNEX_III_G_2': 'Listen Sie PMS-Datenquellen auf (Reklamationen, Trends, Literatur, Lieferantenfeedback).',
    'ANNEX_III_G_3': 'Definieren Sie Überwachungssignale, Schwellenwerte und Eskalationstrigger zu CAPA/Änderung/Vigilanz.',
    'ANNEX_III_G_4': 'Beschreiben Sie PMCF-Plan und Begründung, falls erforderlich; sonst die Nichtanwendbarkeit.',
    'ANNEX_III_H_1': 'Definieren Sie, ob PMS-Bericht oder PSUR gilt, inklusive Begründung.',
    'ANNEX_III_H_2': 'Erfassen Sie den Berichtszeitraum und die wichtigsten Post-Market-Erkenntnisse.',
    'ANNEX_III_H_3': 'Fassen Sie Trends zusammen und verknüpfen Sie relevante Reklamationskennzahlen für Risiko/Leistungsänderungen.',
    'ANNEX_III_H_4': 'Dokumentieren Sie resultierende Maßnahmen und deren Verknüpfung zu CAPA-/Änderungsdatensätzen.',
    'ANNEX_III_H_5': 'Bewerten Sie die Auswirkungen auf das Nutzen-Risiko-Profil und die GSPR-Konformität.',
  };

  String _queryTitleDe(TdQueryTemplate template) => _queryTitleDeMap[template.templateKey] ?? template.title;

  String _queryDescriptionDe(TdQueryTemplate template) => _queryDescriptionDeMap[template.templateKey] ?? template.description;


  String _linkTypeDe(String type) {
    switch (type) {
      case 'Document':
        return 'Dokument';
      case 'ExternalLink':
        return 'Externer Link';
      case 'GSPR':
        return 'GSPR';
      case 'FMEA':
        return 'FMEA';
      case 'CAPA':
        return 'CAPA';
      case 'Supplier':
        return 'Lieferant';
      case 'Training':
        return 'Schulung';
      case 'Report':
        return 'Bericht';
      case 'Change':
        return 'Änderung';
      case 'ComplaintMetric':
        return 'Reklamationskennzahl';
      default:
        return type;
    }
  }

  String _tagDe(String tag) {
    const map = {
      'Annex II': 'Anhang II',
      'Device description': 'Produktbeschreibung',
      'Clinical': 'Klinisch',
      'Variants': 'Varianten',
      'UDI': 'UDI',
      'Classification': 'Klassifizierung',
      'Performance': 'Leistung',
      'State of the art': 'Stand der Technik',
      'Labeling': 'Kennzeichnung',
      'IFU': 'Gebrauchsanweisung',
      'Translation': 'Übersetzung',
      'Traceability': 'Rückverfolgbarkeit',
      'Training': 'Schulung',
      'Manufacturing': 'Herstellung',
      'Process control': 'Prozesskontrolle',
      'Supplier': 'Lieferant',
      'Inspection': 'Prüfung',
      'Change control': 'Änderungskontrolle',
      'Risk': 'Risiko',
      'Benefit-risk': 'Nutzen-Risiko',
      'Residual risk': 'Restrisiko',
      'PMS': 'PMS',
      'Standards': 'Normen',
      'Biocompatibility': 'Biokompatibilität',
      'Reprocessing': 'Aufbereitung',
      'Packaging': 'Verpackung',
      'Software': 'Software',
      'Annex III': 'Anhang III',
      'Data sources': 'Datenquellen',
      'Signals': 'Signale',
      'PMCF': 'PMCF',
      'PSUR': 'PSUR',
      'Findings': 'Erkenntnisse',
      'Complaints': 'Reklamationen',
      'Actions': 'Maßnahmen',
      'Conclusion': 'Schlussfolgerung',
    };
    return map[tag] ?? tag;
  }

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final map = await widget.api.fetchTdSectionDetail(widget.sectionId);
    final section = TdSection.fromJson(map);
    await widget.api.bootstrapTdQueries(widget.td.id);
    final queries = await widget.api.fetchTdQueries(widget.td.id, sectionId: widget.sectionId);
    setState(() { _section = section; _queries = queries; _loading = false; });
  }

  void _openAdminView(AdminView view) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminPage(
          api: widget.api,
          portalProfile: widget.api.portalProfile,
          initialView: view,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _section == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final section = _section!;
    final complete = _queries.where((q) => q.status == 'Complete' || q.status == 'NotApplicable').length;
    final completion = _queries.isEmpty ? 0 : ((complete / _queries.length) * 100).round();
    if (_queries.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(_sectionNameDe(section))),
        body: const Center(child: Text('Keine Abfragen verfügbar. Bitte Bootstrap erneut ausführen.')),
      );
    }
    return DefaultTabController(
      length: _queries.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_sectionNameDe(section)),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(84),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  Chip(label: Text('Status: ${_statusDe(section.status)}')),
                  Chip(label: Text('Vollständigkeit: $completion%')),
                  ..._queries.expand((q) => q.template.suggestedLinkTypes).toSet().take(5).map((type) => ActionChip(label: Text(_linkTypeDe(type)), onPressed: () {})),
                ]),
                const SizedBox(height: 8),
                TabBar(isScrollable: true, tabs: _queries.map((q) => Tab(text: _queryTitleDe(q.template))).toList()),
              ]),
            ),
          ),
        ),
        body: TabBarView(children: _queries.map(_queryTab).toList()),
      ),
    );
  }

  Widget _queryTab(TdQueryAnswer query) {
    final ownerCtl = TextEditingController(text: query.ownerUserId ?? '');
    final dueCtl = TextEditingController(text: query.dueAt ?? '');
    final fieldControllers = <String, TextEditingController>{};
    final selectedSingles = <String, String?>{};
    for (final field in query.template.nodeTemplate.fields) {
      final value = query.fieldResponses[field.key];
      if (field.type == 'select_single') {
        selectedSingles[field.key] = value?.toString();
      } else {
        final text = value is List ? value.join(', ') : (value ?? '').toString();
        fieldControllers[field.key] = TextEditingController(text: text);
      }
    }

    final isMandatoryByApplicability = query.applicability == null
        ? query.template.mandatory
        : (query.applicability!.state == 'MANDATORY' || (query.applicability!.state == 'CONDITIONAL' && query.applicability!.isConditionMet == true));
    final canMarkComplete = !isMandatoryByApplicability || query.validation.canComplete;

    Future<void> saveQuery() async {
      final fieldResponses = <String, dynamic>{};
      for (final field in query.template.nodeTemplate.fields) {
        if (field.type == 'select_single') {
          fieldResponses[field.key] = selectedSingles[field.key] ?? '';
        } else {
          final raw = fieldControllers[field.key]?.text.trim() ?? '';
          if (field.type == 'select_multi') {
            fieldResponses[field.key] = raw.isEmpty ? <String>[] : raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
          } else {
            fieldResponses[field.key] = raw;
          }
        }
      }
      await widget.api.updateTdQuery(query.id, {
        'fieldResponses': fieldResponses,
        'answerMarkdown': (fieldResponses['justificationMd'] ?? fieldResponses['md_text_main'] ?? query.answerMarkdown).toString(),
        'rationaleMarkdown': (fieldResponses['md_text_rationale'] ?? query.rationaleMarkdown).toString(),
        'ownerUserId': ownerCtl.text.trim().isEmpty ? null : ownerCtl.text.trim(),
        'dueAt': dueCtl.text.trim().isEmpty ? null : dueCtl.text.trim(),
      });
      _load();
    }

    return StatefulBuilder(builder: (context, setLocal) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_queryDescriptionDe(query.template)))),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [if (query.applicability != null) _applicabilityChip(query.applicability!.state), ...query.template.tags.map((e) => Chip(label: Text(_tagDe(e))))]),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: query.status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: const ['NotStarted','InProgress','Complete','Blocked','NotApplicable'].map((e)=>DropdownMenuItem(value:e, child: Text(_statusDe(e)))).toList(),
            onChanged: widget.canEdit ? (v) async { await widget.api.updateTdQuery(query.id, {'status': v}); _load(); } : null,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(width: 320, child: TextField(controller: ownerCtl, decoration: const InputDecoration(labelText: 'Verantwortlich'))),
              SizedBox(width: 320, child: TextField(controller: dueCtl, decoration: const InputDecoration(labelText: 'Fälligkeitsdatum (ISO)'))),
            ],
          ),
          const SizedBox(height: 12),
          ...query.template.nodeTemplate.fields.map((field) {
            if (field.type == 'select_single') {
              final options = field.options.map((opt) {
                if (opt is Map) {
                  final m = opt.cast<String, dynamic>();
                  return DropdownMenuItem<String>(value: (m['value'] ?? '').toString(), child: Text((m['label'] ?? '').toString()));
                }
                return DropdownMenuItem<String>(value: opt.toString(), child: Text(opt.toString()));
              }).toList(growable: false);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DropdownButtonFormField<String>(
                  value: selectedSingles[field.key],
                  decoration: InputDecoration(labelText: field.label),
                  items: options,
                  onChanged: widget.canEdit ? (v) => setLocal(() => selectedSingles[field.key] = v) : null,
                ),
              );
            }
            final ctl = fieldControllers[field.key]!;
            final isLong = field.type == 'md_text' || field.type == 'generated_md';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: ctl,
                minLines: isLong ? 3 : 1,
                maxLines: isLong ? 8 : 1,
                decoration: InputDecoration(
                  labelText: field.label,
                  hintText: field.type == 'select_multi' ? 'Mehrere Werte kommasepariert eingeben' : null,
                ),
              ),
            );
          }),
          if (query.generatedMarkdown.isNotEmpty) ...[
            const SizedBox(height: 4),
            Card(child: Padding(padding: const EdgeInsets.all(12), child: Text('Auto-Vorschlag\n${query.generatedMarkdown}'))),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ...query.links.map((l) => InputChip(label: Text('${_linkTypeDe(l.type)}: ${l.label}${l.metaJson['auto'] == true ? ' (auto)' : ''}'), onDeleted: widget.canEdit ? () async { await widget.api.deleteTdQueryLink(l.id); _load(); } : null)),
            if (widget.canEdit)
              FilledButton.icon(onPressed: () async {
                await widget.api.createTdQueryLink(query.id, {'type': 'Document', 'label': _queryTitleDe(query.template), 'refId': query.template.templateKey});
                _load();
              }, icon: const Icon(Icons.add_link), label: const Text('Link hinzufügen')),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: () => _openAdminView(AdminView.gspr), child: const Text('GSPR öffnen')),
            OutlinedButton(onPressed: () => _openAdminView(AdminView.fmea), child: const Text('FMEA öffnen')),
            OutlinedButton(onPressed: () => _openAdminView(AdminView.capaDashboard), child: const Text('CAPA öffnen')),
            OutlinedButton(onPressed: () => _openAdminView(AdminView.changeManagement), child: const Text('Änderungskontrolle öffnen')),
            OutlinedButton(onPressed: () => _openAdminView(AdminView.all), child: const Text('Reklamationen öffnen')),
            OutlinedButton(onPressed: () => _openAdminView(AdminView.approvedSuppliers), child: const Text('Lieferanten öffnen')),
            OutlinedButton(onPressed: () => _openAdminView(AdminView.trainings), child: const Text('Schulungen öffnen')),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(onPressed: widget.canEdit ? saveQuery : null, child: const Text('Abfrage speichern')),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: (widget.canEdit && canMarkComplete) ? () async { await widget.api.updateTdQuery(query.id, {'status': 'Complete'}); _load(); } : null,
              child: const Text('Als abgeschlossen markieren'),
            ),
            if (!canMarkComplete) const Chip(label: Text('Nachweis/Link fehlt')),
          ]),
        ],
      );
    });
  }

}

class _TdFieldSpec {
  final String key;
  final String label;
  const _TdFieldSpec(this.key, this.label);
}

class _ChangeDetailSheet extends StatefulWidget {
  final TdChangeRequest change;
  final bool canEdit;
  final ApiClient api;
  const _ChangeDetailSheet({required this.change, required this.canEdit, required this.api});

  @override
  State<_ChangeDetailSheet> createState() => _ChangeDetailSheetState();
}

class _ChangeDetailSheetState extends State<_ChangeDetailSheet> {
  late TdChangeRequest _change;
  @override
  void initState() { super.initState(); _change = widget.change; }

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_change.title, style: Theme.of(context).textTheme.titleLarge),
        Text(_change.description),
        Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: widget.canEdit ? () async { await widget.api.runTdImpactAnalyzer(_change.id); final detail = await widget.api.fetchTdChange(_change.id); setState(() => _change = detail);} : null, child: const Text('Auswirkungen analysieren'))),
        Flexible(child: ListView(shrinkWrap: true, children: _change.impactItems.map((i) => CheckboxListTile(value: i.status == 'Done', onChanged: widget.canEdit ? (v) async { await widget.api.patchTdImpact(i.id, status: v == true ? 'Done' : 'Open'); final detail = await widget.api.fetchTdChange(_change.id); setState(() => _change = detail);} : null, title: Text(i.impactType), subtitle: Text(i.requiredAction))).toList())),
      ]),
    ));
  }
}
