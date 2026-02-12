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

  static const List<String> _linkTypes = ['Document', 'ExternalLink', 'GSPR', 'FMEA', 'CAPA', 'Supplier', 'Training', 'Report'];

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
      SizedBox(width: 340, child: Card(child: ListView(children: _items.map((td) => ListTile(title: Text('${td.code} · ${td.title}', maxLines: 2, overflow: TextOverflow.ellipsis), subtitle: Text('Punkte ${td.summary.complianceScore}'), selected: _selected?.id == td.id, onTap: () { setState(() => _selected = td); _load(); },)).toList()))),
      const SizedBox(width: 12),
      Expanded(child: Card(child: Column(children: [
        TabBar(controller: _tabs, isScrollable: true, tabs: const [Tab(text: 'Übersicht'), Tab(text: 'Struktur'), Tab(text: 'Links'), Tab(text: 'Änderungsmanagement'), Tab(text: 'Heatmap'), Tab(text: 'Benannte-Stelle-Export'), Tab(text: 'Kalender')]),
        Expanded(child: TabBarView(controller: _tabs, children: [_dashboardTab(), _structureTab(), _linksTab(), _changesTab(), _heatmapTab(), _exportTab(), _calendarTab()])),
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

  Widget _structureTab() => ListView(children: _sections.map((s) => ListTile(
    title: Text(_sectionNameDe(s)),
    subtitle: Text('${s.templateKey} · Links ${s.linkCount ?? 0}'),
    trailing: Chip(label: Text(_statusDe(s.status))),
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

class _TdSectionDetailPageState extends State<TdSectionDetailPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  TdSection? _section;
  List<TdArtifactLink> _links = const [];
  bool _saving = false;
  final _summaryCtl = TextEditingController();
  final Map<String, TextEditingController> _fields = {};

  static const Map<String, String> _reportTypeDe = {
    'PMS_REPORT': 'PMS-Bericht',
    'PSUR': 'PSUR',
    'PMCF': 'PMCF',
  };

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
      case 'GSPR':
        return 'GSPR';
      case 'FMEA':
        return 'FMEA';
      case 'CAPA':
        return 'CAPA';
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
    return Scaffold(appBar: AppBar(title: Text(_sectionNameDe(s)), actions: [if (widget.canEdit) FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 16,height: 16,child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Speichern'))]), body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 12, runSpacing: 12, children: [
        SizedBox(width: 220, child: DropdownButtonFormField<String>(value: s.status, items: const ['NotStarted','InProgress','Complete','Blocked','NotApplicable'].map((e)=>DropdownMenuItem(value: e, child: Text(_statusDe(e)))).toList(), onChanged: widget.canEdit ? (v) async { await widget.api.patchTdSection(s.id, {'status': v}); _load(); } : null)),
        SizedBox(width: 260, child: TextFormField(initialValue: s.ownerUserId, decoration: const InputDecoration(labelText: 'Verantwortliche Person'), onFieldSubmitted: widget.canEdit ? (v) async { await widget.api.patchTdSection(s.id, {'ownerUserId': v}); } : null)),
      ])),
      TabBar(controller: _tabs, tabs: const [Tab(text: 'Inhalt'), Tab(text: 'Links'), Tab(text: 'Historie')]),
      Expanded(child: TabBarView(controller: _tabs, children: [_contentTab(s), _linksTab(s), ListView(children: [ListTile(title: const Text('Aktualisiert von'), subtitle: Text(s.content?.updatedByUserId ?? '-')), ListTile(title: const Text('Aktualisiert am'), subtitle: Text(s.content?.updatedAt ?? '-'))])])),
    ]));
  }

  Widget _contentTab(TdSection s) {
    final fields = _sectionFields(s.templateKey);
    return ListView(padding: const EdgeInsets.all(12), children: [
      TextField(controller: _summaryCtl, minLines: 4, maxLines: 8, readOnly: !widget.canEdit, decoration: const InputDecoration(labelText: 'Zusammenfassung (Markdown)')),
      const SizedBox(height: 8),
      ...fields.map((field) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _buildFieldInput(field),
      )),
      if (s.templateKey == 'ANNEX_II_D') Wrap(spacing: 8, children: [OutlinedButton(onPressed: () {}, child: const Text('GSPR-Modul für diese TD öffnen')), FilledButton(onPressed: widget.canEdit ? () => _addLinkPreset('GSPR') : null, child: const Text('Vorhandene GSPR-Bewertung verknüpfen'))]),
      if (s.templateKey == 'ANNEX_II_E') Wrap(spacing: 8, children: [OutlinedButton(onPressed: () {}, child: const Text('FMEA-Modul öffnen')), FilledButton(onPressed: widget.canEdit ? () => _addLinkPreset('FMEA') : null, child: const Text('Vorhandene FMEA verknüpfen'))]),
    ]);
  }

  Widget _buildFieldInput(_TdFieldSpec field) {
    if (field.key == 'reportType') {
      final current = (_fields[field.key]?.text ?? '').trim();
      final value = _reportTypeDe.containsKey(current) ? current : 'PMS_REPORT';
      return DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(labelText: field.label),
        items: _reportTypeDe.entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value))).toList(),
        onChanged: widget.canEdit
            ? (v) {
                if (v == null) return;
                _fields.putIfAbsent(field.key, () => TextEditingController()).text = v;
              }
            : null,
      );
    }
    return TextField(
      controller: _fields.putIfAbsent(field.key, () => TextEditingController()),
      minLines: 1,
      maxLines: 5,
      readOnly: !widget.canEdit,
      decoration: InputDecoration(labelText: field.label),
    );
  }

  Widget _linksTab(TdSection s) => Column(children: [
    Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(onPressed: widget.canEdit ? ()=>_addLinkPreset(null) : null, icon: const Icon(Icons.add), label: const Text('Link hinzufügen')))),
    Expanded(child: ListView(children: _links.map((l) => ListTile(title: Text(l.label), subtitle: Text('${_linkTypeDe(l.type)} · ${l.url ?? l.refId ?? '-'}'), trailing: widget.canEdit ? IconButton(icon: const Icon(Icons.delete), onPressed: () async { await widget.api.deleteTdLink(l.id); _load(); }) : null)).toList())),
  ]);

  Future<void> _addLinkPreset(String? type) async {
    final labelCtl = TextEditingController();
    final refCtl = TextEditingController();
    final urlCtl = TextEditingController();
    String localType = type ?? 'Document';
    final ok = await showDialog<bool>(context: context, builder: (_) => StatefulBuilder(builder: (_, setS) => AlertDialog(
      title: const Text('Link hinzufügen'),
      content: SizedBox(width: 500, child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: localType, items: const ['Document','ExternalLink','GSPR','FMEA','CAPA','Supplier','Training','Report'].map((e)=>DropdownMenuItem(value:e, child: Text(_linkTypeDe(e)))).toList(), onChanged: (v)=>setS(()=>localType=v??'Document')),
        TextField(controller: labelCtl, decoration: const InputDecoration(labelText: 'Bezeichnung')),
        TextField(controller: refCtl, decoration: const InputDecoration(labelText: 'Referenz-ID')),
        TextField(controller: urlCtl, decoration: const InputDecoration(labelText: 'URL')),
      ])),
      actions: [TextButton(onPressed: ()=>Navigator.pop(context,false), child: const Text('Abbrechen')), FilledButton(onPressed: ()=>Navigator.pop(context,true), child: const Text('Speichern'))],
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert')));
      _load();
    } finally { if (mounted) setState(() => _saving = false); }
  }

  List<_TdFieldSpec> _sectionFields(String templateKey) {
    switch (templateKey) {
      case 'ANNEX_II_A':
        return const [
          _TdFieldSpec('intendedPurpose', 'MDR Anhang II 1.1a – Zweckbestimmung'),
          _TdFieldSpec('deviceDescription', 'MDR Anhang II 1.1b – Produktspezifikation und Beschreibung'),
          _TdFieldSpec('variantsAccessories', 'MDR Anhang II 1.1c – Varianten und Zubehör'),
          _TdFieldSpec('udiBasic', 'MDR Anhang II 1.1d – UDI-Basis-DI'),
          _TdFieldSpec('classification', 'MDR Anhang II 1.1e – Risikoklasse'),
          _TdFieldSpec('rule', 'MDR Anhang II 1.1e – Klassifizierungsregel (Anhang VIII)'),
          _TdFieldSpec('principlesOfOperation', 'MDR Anhang II 1.1f – Funktionsprinzipien'),
          _TdFieldSpec('references', 'MDR Anhang II 1.1g – Referenz auf Vorgänger-/ähnliche Generationen'),
        ];
      case 'ANNEX_II_B':
        return const [
          _TdFieldSpec('labelingRefs', 'MDR Anhang II 2.1 – Kennzeichnung (Label)'),
          _TdFieldSpec('ifuRefs', 'MDR Anhang II 2.2 – Gebrauchsanweisung (IFU)'),
          _TdFieldSpec('symbolsRefs', 'MDR Anhang II 2.3 – Symbole/Erklärungen'),
          _TdFieldSpec('translationsNotes', 'MDR Anhang II 2.4 – Sprachversionen und Länderbezug'),
        ];
      case 'ANNEX_II_C':
        return const [
          _TdFieldSpec('manufacturingSites', 'MDR Anhang II 3.1 – Herstellungsstandorte'),
          _TdFieldSpec('keyProcesses', 'MDR Anhang II 3.2 – Herstellungsverfahren'),
          _TdFieldSpec('criticalProcessControls', 'MDR Anhang II 3.3 – Kritische Prozesslenkung'),
          _TdFieldSpec('subcontractorsRefs', 'MDR Anhang II 3.4 – Wichtige Lieferanten/Unterauftragnehmer'),
        ];
      case 'ANNEX_II_E':
        return const [
          _TdFieldSpec('riskManagementSummary', 'MDR Anhang II 5.1 – Zusammenfassung Risikomanagement'),
          _TdFieldSpec('fmeaRefs', 'MDR Anhang II 5.2 – Verweise auf Risikoanalysen/FMEA'),
          _TdFieldSpec('benefitRiskConclusion', 'MDR Anhang II 5.3 – Nutzen-Risiko-Bewertung'),
        ];
      case 'ANNEX_II_F':
        return const [
          _TdFieldSpec('standardsApplied', 'MDR Anhang II 6.1 – Angewandte Normen und Spezifikationen'),
          _TdFieldSpec('biocompatibilityRefs', 'MDR Anhang II 6.2 – Biokompatibilität'),
          _TdFieldSpec('cleaningSterilizationRefs', 'MDR Anhang II 6.3 – Reinigung, Desinfektion, Sterilisation'),
          _TdFieldSpec('performanceTestingRefs', 'MDR Anhang II 6.4 – Präklinische/klinische Leistungsdaten'),
          _TdFieldSpec('softwareValidationRefs', 'MDR Anhang II 6.5 – Software-Verifizierung/-Validierung'),
        ];
      case 'ANNEX_III_G':
        return const [
          _TdFieldSpec('pmsPlanSummary', 'MDR Anhang III 1.1 – PMS-Plan (Zusammenfassung)'),
          _TdFieldSpec('pmsPlanRefs', 'MDR Anhang III 1.2 – PMS-Plan (Referenzen)'),
          _TdFieldSpec('pmsMethods', 'MDR Anhang III 1.3 – PMS-Methoden und Datenquellen'),
        ];
      case 'ANNEX_III_H':
        return const [
          _TdFieldSpec('reportType', 'MDR Anhang III 2.1 – Berichtstyp (PMS-Bericht/PSUR/PMCF)'),
          _TdFieldSpec('reportingPeriod', 'MDR Anhang III 2.2 – Berichtszeitraum'),
          _TdFieldSpec('keyFindings', 'MDR Anhang III 2.3 – Zentrale Ergebnisse'),
          _TdFieldSpec('actionsConclusions', 'MDR Anhang III 2.4 – Maßnahmen und Schlussfolgerungen'),
          _TdFieldSpec('reportRefs', 'MDR Anhang III 2.5 – Berichtsnachweise/Referenzen'),
        ];
      default: return const [];
    }
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
