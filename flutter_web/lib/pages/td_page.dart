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

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 7, vsync: this);
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
      if (selected != null) {
        sections = await widget.api.fetchTdSections(selected.id);
        changes = await widget.api.fetchTdChanges(selected.id);
        links = await widget.api.fetchTdLinks(selected.id);
        readiness = await widget.api.fetchTdReadiness(selected.id);
      }
      setState(() {
        _items = list;
        _selected = selected;
        _sections = sections;
        _changes = changes;
        _links = links;
        _readiness = readiness;
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
      SizedBox(width: 340, child: Card(child: ListView(children: _items.map((td) => ListTile(title: Text('${td.code} · ${td.title}', maxLines: 2, overflow: TextOverflow.ellipsis), subtitle: Text('Score ${td.summary.complianceScore}'), selected: _selected?.id == td.id, onTap: () { setState(() => _selected = td); _load(); },)).toList()))),
      const SizedBox(width: 12),
      Expanded(child: Card(child: Column(children: [
        TabBar(controller: _tabs, isScrollable: true, tabs: const [Tab(text: 'Dashboard'), Tab(text: 'Structure'), Tab(text: 'Links'), Tab(text: 'Change Control'), Tab(text: 'Heatmap'), Tab(text: 'NB Export'), Tab(text: 'Calendar')]),
        Expanded(child: TabBarView(controller: _tabs, children: [_dashboardTab(), _structureTab(), _linksTab(), _changesTab(), _heatmapTab(), _exportTab(), _calendarTab()])),
      ]))),
    ]);
  }

  Widget _dashboardTab() {
    final td = _selected;
    if (td == null) return const Center(child: Text('No TD selected'));
    final gaps = (_readiness?['gaps'] as List?)?.map((e) => '$e').toList() ?? const [];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(td.title, style: Theme.of(context).textTheme.titleLarge),
      Text('Readiness: ${_readiness?['readinessStatus'] ?? td.summary.readinessStatus}'),
      Text('Compliance score: ${_readiness?['complianceScore'] ?? td.summary.complianceScore}'),
      ...gaps.map((g) => ListTile(leading: const Icon(Icons.error_outline), title: Text(g))),
    ]);
  }

  Widget _structureTab() => ListView(children: _sections.map((s) => ListTile(
    title: Text(s.name),
    subtitle: Text('${s.templateKey} · links ${s.linkCount ?? 0}'),
    trailing: Chip(label: Text(s.status)),
    onTap: () async {
      if (_selected == null) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TdSectionDetailPage(api: widget.api, td: _selected!, sectionId: s.id, canEdit: widget.canEdit)));
      _load();
    },
  )).toList());

  Widget _linksTab() {
    return Column(children: [
      Align(alignment: Alignment.centerRight, child: Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(onPressed: widget.canEdit ? () => _openAddLinkDialog() : null, icon: const Icon(Icons.add_link), label: const Text('Add TD Link')),
      )),
      Expanded(child: ListView(children: _links.map((l) => ListTile(title: Text(l.label), subtitle: Text('${l.type} · ${l.sectionId ?? 'TD'}'), trailing: widget.canEdit ? IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { await widget.api.deleteTdLink(l.id); _load(); }) : null)).toList())),
    ]);
  }

  Future<void> _openAddLinkDialog({String? sectionId, String? presetType}) async {
    if (_selected == null) return;
    final type = ValueNotifier<String>(presetType ?? 'Document');
    final labelCtl = TextEditingController();
    final refCtl = TextEditingController();
    final urlCtl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Add link'),
      content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [
        ValueListenableBuilder<String>(valueListenable: type, builder: (_, v, __) => DropdownButtonFormField<String>(value: v, items: const ['Document','ExternalLink','GSPR','FMEA','CAPA','Supplier','Training','Report'].map((e)=>DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: widget.canEdit ? (x){ if (x != null) type.value = x; } : null)),
        TextField(controller: labelCtl, decoration: const InputDecoration(labelText: 'Label')),
        TextField(controller: refCtl, decoration: const InputDecoration(labelText: 'Reference ID')),
        TextField(controller: urlCtl, decoration: const InputDecoration(labelText: 'URL')),
      ])),
      actions: [TextButton(onPressed: ()=>Navigator.pop(context,false), child: const Text('Cancel')), FilledButton(onPressed: ()=>Navigator.pop(context,true), child: const Text('Save'))],
    ));
    if (ok == true) {
      await widget.api.createTdLink(_selected!.id, {'sectionId': sectionId, 'type': type.value, 'label': labelCtl.text.trim(), 'refId': refCtl.text.trim(), 'url': urlCtl.text.trim().isEmpty ? null : urlCtl.text.trim()});
      _load();
    }
  }

  Widget _changesTab() => Column(children: [
    Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(onPressed: widget.canEdit ? _createChange : null, icon: const Icon(Icons.add), label: const Text('Create change request')))),
    Expanded(child: ListView(children: _changes.map((c) => ListTile(title: Text(c.title), subtitle: Text('${c.changeType} · ${c.severity}'), trailing: Chip(label: Text(c.status)), onTap: () async {
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
      title: const Text('Create change request'),
      content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
        DropdownButtonFormField<String>(value: type, items: const ['Material','Supplier','LabelingIFU','Other'].map((e)=>DropdownMenuItem(value:e, child: Text(e))).toList(), onChanged: (v)=>setS(()=>type=v??'Other')),
        DropdownButtonFormField<String>(value: severity, items: const ['Low','Medium','High','Critical'].map((e)=>DropdownMenuItem(value:e, child: Text(e))).toList(), onChanged: (v)=>setS(()=>severity=v??'Medium')),
        TextField(controller: desc, decoration: const InputDecoration(labelText: 'Description'), minLines: 2, maxLines: 5),
      ])),
      actions: [TextButton(onPressed: ()=>Navigator.pop(context,false), child: const Text('Cancel')), FilledButton(onPressed: ()=>Navigator.pop(context,true), child: const Text('Create'))],
    )));
    if (ok == true) {
      await widget.api.createTdChange(_selected!.id, {'title': title.text.trim(), 'description': desc.text.trim(), 'changeType': type, 'severity': severity});
      _load();
    }
  }

  Widget _heatmapTab() => ListView(children: [for (final s in _sections) ListTile(title: Text(s.status), subtitle: Text(s.name))]);

  Widget _exportTab() => Center(child: FilledButton.icon(onPressed: _selected == null ? null : () async {
    final resp = await widget.api.exportTdNbPackage(_selected!.id);
    final url = resp['downloadUrl']?.toString();
    if (url != null && url.isNotEmpty) html.window.open(url, '_blank');
  }, icon: const Icon(Icons.picture_as_pdf), label: const Text('Generate NB package')));

  Widget _calendarTab() => ListView(children: _sections.map((s) => ListTile(title: Text(s.name), subtitle: Text(s.nextReviewAt ?? 'not set'))).toList());
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

class _TdSectionDetailPageState extends State<TdSectionDetailPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  TdSection? _section;
  List<TdArtifactLink> _links = const [];
  bool _saving = false;
  final _summaryCtl = TextEditingController();
  final Map<String, TextEditingController> _fields = {};

  @override
  void initState() { super.initState(); _tabs = TabController(length: 3, vsync: this); _load(); }

  Future<void> _load() async {
    final map = await widget.api.fetchTdSectionDetail(widget.sectionId);
    final s = TdSection.fromJson(map);
    final links = await widget.api.fetchTdLinks(widget.td.id, sectionId: widget.sectionId);
    _summaryCtl.text = s.content?.summaryMarkdown ?? '';
    _fields.clear();
    (s.content?.contentJson ?? const <String,dynamic>{}).forEach((k,v){ _fields[k] = TextEditingController(text: v is List ? v.join('\n') : '$v'); });
    setState(() { _section = s; _links = links; });
  }

  @override
  Widget build(BuildContext context) {
    final s = _section;
    if (s == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(appBar: AppBar(title: Text(s.name), actions: [if (widget.canEdit) FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 16,height: 16,child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'))]), body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 12, runSpacing: 12, children: [
        SizedBox(width: 220, child: DropdownButtonFormField<String>(value: s.status, items: const ['NotStarted','InProgress','Complete','Blocked','NotApplicable'].map((e)=>DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: widget.canEdit ? (v) async { await widget.api.patchTdSection(s.id, {'status': v}); _load(); } : null)),
        SizedBox(width: 260, child: TextFormField(initialValue: s.ownerUserId, decoration: const InputDecoration(labelText: 'Owner user'), onFieldSubmitted: widget.canEdit ? (v) async { await widget.api.patchTdSection(s.id, {'ownerUserId': v}); } : null)),
      ])),
      TabBar(controller: _tabs, tabs: const [Tab(text: 'Content'), Tab(text: 'Links'), Tab(text: 'History')]),
      Expanded(child: TabBarView(controller: _tabs, children: [_contentTab(s), _linksTab(s), ListView(children: [ListTile(title: const Text('Updated by'), subtitle: Text(s.content?.updatedByUserId ?? '-')), ListTile(title: const Text('Updated at'), subtitle: Text(s.content?.updatedAt ?? '-'))])])),
    ]));
  }

  Widget _contentTab(TdSection s) {
    final keys = _sectionFieldKeys(s.templateKey);
    return ListView(padding: const EdgeInsets.all(12), children: [
      TextField(controller: _summaryCtl, minLines: 4, maxLines: 8, readOnly: !widget.canEdit, decoration: const InputDecoration(labelText: 'Summary (Markdown)')),
      const SizedBox(height: 8),
      ...keys.map((key) => Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: _fields.putIfAbsent(key, () => TextEditingController()), minLines: 1, maxLines: 5, readOnly: !widget.canEdit, decoration: InputDecoration(labelText: key)))),
      if (s.templateKey == 'ANNEX_II_D') Wrap(spacing: 8, children: [OutlinedButton(onPressed: () {}, child: const Text('Open GSPR module for this TD')), FilledButton(onPressed: widget.canEdit ? () => _addLinkPreset('GSPR') : null, child: const Text('Link existing GSPR assessment'))]),
      if (s.templateKey == 'ANNEX_II_E') Wrap(spacing: 8, children: [OutlinedButton(onPressed: () {}, child: const Text('Open FMEA module')), FilledButton(onPressed: widget.canEdit ? () => _addLinkPreset('FMEA') : null, child: const Text('Link existing FMEA'))]),
    ]);
  }

  Widget _linksTab(TdSection s) => Column(children: [
    Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(onPressed: widget.canEdit ? ()=>_addLinkPreset(null) : null, icon: const Icon(Icons.add), label: const Text('Add link')))),
    Expanded(child: ListView(children: _links.map((l) => ListTile(title: Text(l.label), subtitle: Text('${l.type} · ${l.url ?? l.refId ?? '-'}'), trailing: widget.canEdit ? IconButton(icon: const Icon(Icons.delete), onPressed: () async { await widget.api.deleteTdLink(l.id); _load(); }) : null)).toList())),
  ]);

  Future<void> _addLinkPreset(String? type) async {
    final labelCtl = TextEditingController();
    final refCtl = TextEditingController();
    final urlCtl = TextEditingController();
    String localType = type ?? 'Document';
    final ok = await showDialog<bool>(context: context, builder: (_) => StatefulBuilder(builder: (_, setS) => AlertDialog(
      title: const Text('Add link'),
      content: SizedBox(width: 500, child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: localType, items: const ['Document','ExternalLink','GSPR','FMEA','CAPA','Supplier','Training','Report'].map((e)=>DropdownMenuItem(value:e, child: Text(e))).toList(), onChanged: (v)=>setS(()=>localType=v??'Document')),
        TextField(controller: labelCtl, decoration: const InputDecoration(labelText: 'Label')),
        TextField(controller: refCtl, decoration: const InputDecoration(labelText: 'Reference ID')),
        TextField(controller: urlCtl, decoration: const InputDecoration(labelText: 'URL')),
      ])),
      actions: [TextButton(onPressed: ()=>Navigator.pop(context,false), child: const Text('Cancel')), FilledButton(onPressed: ()=>Navigator.pop(context,true), child: const Text('Save'))],
    )));
    if (ok == true) {
      await widget.api.createTdLink(widget.td.id, {'sectionId': widget.sectionId, 'type': localType, 'label': labelCtl.text.trim(), 'refId': refCtl.text.trim(), 'url': urlCtl.text.trim().isEmpty ? null : urlCtl.text.trim()});
      _load();
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final content = <String, dynamic>{};
      _fields.forEach((k,v){ final txt=v.text.trim(); content[k]= txt.contains('\n') ? txt.split('\n').where((e)=>e.trim().isNotEmpty).toList() : txt; });
      await widget.api.putTdSectionContent(widget.sectionId, summaryMarkdown: _summaryCtl.text, contentJson: content);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
      _load();
    } finally { if (mounted) setState(() => _saving = false); }
  }

  List<String> _sectionFieldKeys(String templateKey) {
    switch (templateKey) {
      case 'ANNEX_II_A': return ['intendedPurpose','deviceDescription','variantsAccessories','udiBasic','classification','rule','principlesOfOperation','references'];
      case 'ANNEX_II_B': return ['labelingRefs','ifuRefs','symbolsRefs','translationsNotes'];
      case 'ANNEX_II_C': return ['manufacturingSites','keyProcesses','criticalProcessControls','subcontractorsRefs'];
      case 'ANNEX_II_E': return ['riskManagementSummary','fmeaRefs','benefitRiskConclusion'];
      case 'ANNEX_II_F': return ['standardsApplied','biocompatibilityRefs','cleaningSterilizationRefs','performanceTestingRefs','softwareValidationRefs'];
      case 'ANNEX_III_G': return ['pmsPlanSummary','pmsPlanRefs','pmsMethods'];
      case 'ANNEX_III_H': return ['reportType','reportingPeriod','keyFindings','actionsConclusions','reportRefs'];
      default: return const [];
    }
  }
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
        Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: widget.canEdit ? () async { await widget.api.runTdImpactAnalyzer(_change.id); final detail = await widget.api.fetchTdChange(_change.id); setState(() => _change = detail);} : null, child: const Text('Analyze impact'))),
        Flexible(child: ListView(shrinkWrap: true, children: _change.impactItems.map((i) => CheckboxListTile(value: i.status == 'Done', onChanged: widget.canEdit ? (v) async { await widget.api.patchTdImpact(i.id, status: v == true ? 'Done' : 'Open'); final detail = await widget.api.fetchTdChange(_change.id); setState(() => _change = detail);} : null, title: Text(i.impactType), subtitle: Text(i.requiredAction))).toList())),
      ]),
    ));
  }
}
