import 'package:flutter/material.dart';
import 'dart:html' as html;

import '../api/client.dart';
import '../models/td.dart';

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
  String? _error;
  Map<String, dynamic>? _readiness;
  TdApplicabilityBundle? _applicability;

  static const List<String> _linkTypes = ['Document', 'ExternalLink', 'GSPR', 'FMEA', 'CAPA', 'Supplier', 'Training', 'Report', 'Change'];

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

  String _gapDe(String gap) {
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
      case 'Supplier':
        return 'Lieferant';
      case 'Training':
        return 'Schulung';
      case 'Report':
        return 'Bericht';
      case 'Change':
        return 'Änderung';
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

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 8, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await widget.api.fetchTdFiles();
      final selected = list.isNotEmpty ? (_selected == null ? list.first : list.firstWhere((e) => e.id == _selected!.id, orElse: () => list.first)) : null;
      List<TdSection> sections = const [];
      List<TdChangeRequest> changes = const [];
      List<TdArtifactLink> links = const [];
      Map<String, dynamic>? readiness;
      TdApplicabilityBundle? applicability;
      if (selected != null) {
        sections = await widget.api.fetchTdSections(selected.id);
        changes = await widget.api.fetchTdChanges(selected.id);
        links = await widget.api.fetchTdLinks(selected.id);
        readiness = await widget.api.fetchTdReadiness(selected.id);
        applicability = await widget.api.fetchTdApplicability(selected.id);
      }
      setState(() {
        _items = list;
        _selected = selected;
        _sections = sections;
        _changes = changes;
        _links = links;
        _readiness = readiness;
        _applicability = applicability;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    return Row(children: [
      SizedBox(width: 340, child: Card(child: Column(children: [if (widget.canEdit) Padding(padding: const EdgeInsets.all(8), child: FilledButton.icon(onPressed: _openCreateTdWizard, icon: const Icon(Icons.add), label: const Text('Create TD'))), Expanded(child: ListView(children: _items.map((td) => ListTile(title: Text('${td.code} · ${td.title}', maxLines: 2, overflow: TextOverflow.ellipsis), subtitle: Text('Punkte ${td.summary.complianceScore}'), selected: _selected?.id == td.id, onTap: () { setState(() => _selected = td); _load(); },)).toList()))]))),
      const SizedBox(width: 12),
      Expanded(child: Card(child: Column(children: [
        TabBar(controller: _tabs, isScrollable: true, tabs: const [Tab(text: 'Übersicht'), Tab(text: 'Struktur'), Tab(text: 'Applicability'), Tab(text: 'Links'), Tab(text: 'Änderungsmanagement'), Tab(text: 'Heatmap'), Tab(text: 'Benannte-Stelle-Export'), Tab(text: 'Kalender')]),
        Expanded(child: TabBarView(controller: _tabs, children: [_dashboardTab(), _structureTab(), _applicabilityTab(), _linksTab(), _changesTab(), _heatmapTab(), _exportTab(), _calendarTab()])),
      ]))),
    ]);
  }

  Widget _dashboardTab() {
    final td = _selected;
    if (td == null) return const Center(child: Text('Keine TD ausgewählt'));
    final gaps = (_readiness?['gaps'] as List?)?.map((e) => '$e').toList() ?? const [];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(td.title, style: Theme.of(context).textTheme.titleLarge),
      Text('Reifegrad: ${_readinessDe((_readiness?['readinessStatus'] ?? td.summary.readinessStatus).toString())}'),
      Text('Compliance-Score: ${_readiness?['complianceScore'] ?? td.summary.complianceScore}'),
      ...gaps.map((g) => ListTile(leading: const Icon(Icons.error_outline), title: Text(_gapDe(g)))),
    ]);
  }

  Widget _structureTab() => ListView(
        padding: const EdgeInsets.all(12),
        children: _sections
            .map((s) => Card(
                  child: ListTile(
                    title: Text(_sectionNameDe(s)),
                    subtitle: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Text('${s.templateKey} · Links ${s.linkCount ?? 0}'),
                        if (s.completion != null) Chip(label: Text('Completion ${s.completion}%')),
                        if (s.queryTotal != null) Chip(label: Text('Queries ${s.queryTotal}')),
                      ],
                    ),
                    trailing: Wrap(spacing: 8, children: [if (s.applicability != null) _applicabilityChip(s.applicability!.state), Chip(label: Text(_statusDe(s.status)))]),
                    onTap: () async {
                      if (_selected == null) return;
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TdSectionDetailPage(api: widget.api, td: _selected!, sectionId: s.id, canEdit: widget.canEdit)));
                      _load();
                    },
                  ),
                ))
            .toList(),
      );


  Chip _applicabilityChip(String state) {
    final map = {
      'MANDATORY': 'Mandatory',
      'OPTIONAL': 'Optional',
      'CONDITIONAL': 'Conditional',
      'NOT_APPLICABLE': 'N/A',
    };
    return Chip(label: Text(map[state] ?? state));
  }

  Future<void> _openCreateTdWizard() async {
    final codeCtl = TextEditingController();
    final titleCtl = TextEditingController();
    final groupCtl = TextEditingController();
    final classCtl = TextEditingController(text: 'IIa');
    final ruleCtl = TextEditingController(text: 'Rule 5.4');
    TdApplicabilityProfile profile = const TdApplicabilityProfile(profileType: 'ROTARY_REUSABLE_NONSTERILE', isReusable: true, isSterile: false, packagingType: 'BULK_NONSTERILE', classificationRule: 'Rule 5.4', hasSoftware: false, notes: null);
    final ok = await showDialog<bool>(context: context, builder: (_) => StatefulBuilder(builder: (_, setS) => AlertDialog(
      title: const Text('Create TD Wizard'),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: codeCtl, decoration: const InputDecoration(labelText: 'TD code')),
        TextField(controller: titleCtl, decoration: const InputDecoration(labelText: 'Title')),
        TextField(controller: groupCtl, decoration: const InputDecoration(labelText: 'Product group')),
        TextField(controller: classCtl, decoration: const InputDecoration(labelText: 'Classification')),
        TextField(controller: ruleCtl, decoration: const InputDecoration(labelText: 'Rule')),
        DropdownButtonFormField<String>(value: profile.profileType, items: const ['ROTARY_REUSABLE_NONSTERILE','ROTARY_REUSABLE_SURGICAL','DENTAL_ALLOYS','SOFTWARE_DEVICE'].map((e)=>DropdownMenuItem(value:e, child: Text(e))).toList(), onChanged: (v){ if(v==null) return; setS((){ profile = TdApplicabilityProfile(profileType: v, isReusable: profile.isReusable, isSterile: profile.isSterile, packagingType: profile.packagingType, classificationRule: profile.classificationRule, hasSoftware: profile.hasSoftware, notes: profile.notes);});}),
        SwitchListTile(value: profile.isReusable, onChanged: (v)=>setS(()=>profile = TdApplicabilityProfile(profileType: profile.profileType, isReusable: v, isSterile: profile.isSterile, packagingType: profile.packagingType, classificationRule: profile.classificationRule, hasSoftware: profile.hasSoftware, notes: profile.notes)), title: const Text('Reusable')),
        SwitchListTile(value: profile.isSterile, onChanged: (v)=>setS(()=>profile = TdApplicabilityProfile(profileType: profile.profileType, isReusable: profile.isReusable, isSterile: v, packagingType: profile.packagingType, classificationRule: profile.classificationRule, hasSoftware: profile.hasSoftware, notes: profile.notes)), title: const Text('Sterile')),
        SwitchListTile(value: profile.hasSoftware, onChanged: (v)=>setS(()=>profile = TdApplicabilityProfile(profileType: profile.profileType, isReusable: profile.isReusable, isSterile: profile.isSterile, packagingType: profile.packagingType, classificationRule: profile.classificationRule, hasSoftware: v, notes: profile.notes)), title: const Text('Has software')),
        DropdownButtonFormField<String>(value: profile.packagingType, items: const ['BULK_NONSTERILE','UNIT_NONSTERILE','STERILE_BARRIER_SYSTEM','TRANSPORT_VALIDATED'].map((e)=>DropdownMenuItem(value:e, child: Text(e))).toList(), onChanged: (v){ if(v==null) return; setS(()=>profile = TdApplicabilityProfile(profileType: profile.profileType, isReusable: profile.isReusable, isSterile: profile.isSterile, packagingType: v, classificationRule: profile.classificationRule, hasSoftware: profile.hasSoftware, notes: profile.notes));}),
      ]))),
      actions: [TextButton(onPressed: ()=>Navigator.pop(context,false), child: const Text('Cancel')), FilledButton(onPressed: ()=>Navigator.pop(context,true), child: const Text('Create'))],
    )));
    if (ok == true) {
      await widget.api.createTdFile(code: codeCtl.text.trim(), title: titleCtl.text.trim(), productGroup: groupCtl.text.trim(), classification: classCtl.text.trim(), rule: ruleCtl.text.trim(), applicabilityProfile: profile);
      _load();
    }
  }

  Widget _applicabilityTab() {
    final selected = _selected;
    final bundle = _applicability;
    if (selected == null || bundle == null) return const Center(child: Text('No applicability data'));
    final profile = bundle.profile;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 12, runSpacing: 12, children: [
        Chip(label: Text('Profile: ${profile.profileType}')),
        Chip(label: Text('Reusable: ${profile.isReusable}')),
        Chip(label: Text('Sterile: ${profile.isSterile}')),
        Chip(label: Text('Packaging: ${profile.packagingType}')),
        Chip(label: Text('Software: ${profile.hasSoftware}')),
      ]))),
      Wrap(spacing: 8, children: [
        FilledButton(onPressed: widget.canEdit ? () async { await widget.api.regenerateTdApplicability(selected.id); await _load(); } : null, child: const Text('Regenerate applicability')),
      ]),
      const SizedBox(height: 12),
      ...bundle.results.where((r) => r.queryKey == null).map((r) {
        final sectionName = _sections.where((s) => s.id == r.sectionId).map((s) => s.name).cast<String?>().firstWhere((e) => e != null, orElse: () => 'Section') ?? 'Section';
        return ListTile(title: Text(sectionName), trailing: _applicabilityChip(r.state), subtitle: Text(r.conditionSummary ?? ''));
      }),
    ]);
  }

  Widget _linksTab() {
    return Column(children: [
      Align(alignment: Alignment.centerRight, child: Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(onPressed: widget.canEdit ? () => _openAddLinkDialog() : null, icon: const Icon(Icons.add_link), label: const Text('TD-Link hinzufügen')),
      )),
      Expanded(child: ListView(children: _links.map((l) => ListTile(title: Text(l.label), subtitle: Text('${_linkTypeDe(l.type)} · ${l.sectionId ?? 'TD'}'), trailing: widget.canEdit ? IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { await widget.api.deleteTdLink(l.id); _load(); }) : null)).toList())),
    ]);
  }

  Future<void> _openAddLinkDialog({String? sectionId, String? presetType}) async {
    if (_selected == null) return;
    final type = ValueNotifier<String>(presetType ?? 'Document');
    final labelCtl = TextEditingController();
    final refCtl = TextEditingController();
    final urlCtl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Link hinzufügen'),
      content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [
        ValueListenableBuilder<String>(valueListenable: type, builder: (_, v, __) => DropdownButtonFormField<String>(value: v, items: _linkTypes.map((e)=>DropdownMenuItem(value: e, child: Text(_linkTypeDe(e)))).toList(), onChanged: widget.canEdit ? (x){ if (x != null) type.value = x; } : null)),
        TextField(controller: labelCtl, decoration: const InputDecoration(labelText: 'Bezeichnung')),
        TextField(controller: refCtl, decoration: const InputDecoration(labelText: 'Referenz-ID')),
        TextField(controller: urlCtl, decoration: const InputDecoration(labelText: 'URL')),
      ])),
      actions: [TextButton(onPressed: ()=>Navigator.pop(context,false), child: const Text('Abbrechen')), FilledButton(onPressed: ()=>Navigator.pop(context,true), child: const Text('Speichern'))],
    ));
    if (ok == true) {
      await widget.api.createTdLink(_selected!.id, {'sectionId': sectionId, 'type': type.value, 'label': labelCtl.text.trim(), 'refId': refCtl.text.trim(), 'url': urlCtl.text.trim().isEmpty ? null : urlCtl.text.trim()});
      _load();
    }
  }

  Widget _changesTab() => Column(children: [
    Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(onPressed: widget.canEdit ? _createChange : null, icon: const Icon(Icons.add), label: const Text('Änderungsantrag erstellen')))),
    Expanded(child: ListView(children: _changes.map((c) => ListTile(title: Text(c.title), subtitle: Text('${_changeTypeDe(c.changeType)} · ${_severityDe(c.severity)}'), trailing: Chip(label: Text(c.status)), onTap: () async {
      final detail = await widget.api.fetchTdChange(c.id);
      if (!mounted) return;
      showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => _ChangeDetailSheet(change: detail, canEdit: widget.canEdit, api: widget.api));
    })).toList())),
  ]);

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
      'MANDATORY': 'Mandatory',
      'OPTIONAL': 'Optional',
      'CONDITIONAL': 'Conditional',
      'NOT_APPLICABLE': 'N/A',
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

  @override
  Widget build(BuildContext context) {
    if (_loading || _section == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final section = _section!;
    final complete = _queries.where((q) => q.status == 'Complete' || q.status == 'NotApplicable').length;
    final completion = _queries.isEmpty ? 0 : ((complete / _queries.length) * 100).round();
    if (_queries.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(section.name)),
        body: const Center(child: Text('Keine Queries verfügbar. Bitte Bootstrap erneut ausführen.')),
      );
    }
    return DefaultTabController(
      length: _queries.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(section.name),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(84),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  Chip(label: Text('Status: ${_statusDe(section.status)}')),
                  Chip(label: Text('Vollständigkeit: $completion%')),
                  ..._queries.expand((q) => q.template.suggestedLinkTypes).toSet().take(5).map((type) => ActionChip(label: Text(type), onPressed: () {})),
                ]),
                const SizedBox(height: 8),
                TabBar(isScrollable: true, tabs: _queries.map((q) => Tab(text: q.template.title)).toList()),
              ]),
            ),
          ),
        ),
        body: TabBarView(children: _queries.map(_queryTab).toList()),
      ),
    );
  }

  Widget _queryTab(TdQueryAnswer query) {
    final answerCtl = TextEditingController(text: query.answerMarkdown);
    final rationaleCtl = TextEditingController(text: query.rationaleMarkdown);
    final ownerCtl = TextEditingController(text: query.ownerUserId ?? '');
    final dueCtl = TextEditingController(text: query.dueAt ?? '');
    final isMandatoryByApplicability = query.applicability == null ? query.template.mandatory : (query.applicability!.state == 'MANDATORY' || (query.applicability!.state == 'CONDITIONAL' && query.applicability!.isConditionMet == true));
    final canMarkComplete = query.links.isNotEmpty || !isMandatoryByApplicability;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(query.template.description))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [if (query.applicability != null) _applicabilityChip(query.applicability!.state), ...query.template.tags.map((e) => Chip(label: Text(e)))]),
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
            SizedBox(width: 320, child: TextField(controller: ownerCtl, decoration: const InputDecoration(labelText: 'Owner'))),
            SizedBox(width: 320, child: TextField(controller: dueCtl, decoration: const InputDecoration(labelText: 'Due date (ISO)'))),
          ],
        ),
        const SizedBox(height: 8),
        TextField(controller: answerCtl, minLines: 4, maxLines: 8, decoration: const InputDecoration(labelText: 'Assessment answer (Markdown)')),
        const SizedBox(height: 8),
        TextField(controller: rationaleCtl, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'Rationale')),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ...query.links.map((l) => InputChip(label: Text('${l.type}: ${l.label}'), onDeleted: widget.canEdit ? () async { await widget.api.deleteTdQueryLink(l.id); _load(); } : null)),
          if (widget.canEdit)
            FilledButton.icon(onPressed: () async {
              await widget.api.createTdQueryLink(query.id, {'type': 'Document', 'label': query.template.title, 'refId': query.template.templateKey});
              _load();
            }, icon: const Icon(Icons.add_link), label: const Text('Add link')),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: () {}, child: const Text('Open GSPR')),
          OutlinedButton(onPressed: () {}, child: const Text('Open FMEA')),
          OutlinedButton(onPressed: () {}, child: const Text('Open CAPA')),
          OutlinedButton(onPressed: () {}, child: const Text('Open Change Control')),
          OutlinedButton(onPressed: () {}, child: const Text('Open Complaints')),
          OutlinedButton(onPressed: () {}, child: const Text('Open Supplier')),
          OutlinedButton(onPressed: () {}, child: const Text('Open Training')),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(
            onPressed: widget.canEdit
                ? () async {
                    await widget.api.updateTdQuery(query.id, {
                      'answerMarkdown': answerCtl.text,
                      'rationaleMarkdown': rationaleCtl.text,
                      'ownerUserId': ownerCtl.text.trim().isEmpty ? null : ownerCtl.text.trim(),
                      'dueAt': dueCtl.text.trim().isEmpty ? null : dueCtl.text.trim(),
                    });
                    _load();
                  }
                : null,
            child: const Text('Save query'),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: (widget.canEdit && canMarkComplete) ? () async { await widget.api.updateTdQuery(query.id, {'status': 'Complete'}); _load(); } : null,
            child: const Text('Mark complete'),
          ),
          if (!canMarkComplete) const Chip(label: Text('Missing evidence/link')),
        ]),
      ],
    );
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
