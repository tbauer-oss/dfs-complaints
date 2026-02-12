import 'package:flutter/material.dart';

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
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 7, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.api.fetchTdFiles();
      TdFile? selected = list.isNotEmpty ? list.first : null;
      List<TdSection> sections = const [];
      List<TdChangeRequest> changes = const [];
      if (selected != null) {
        final detail = await widget.api.fetchTdDetail(selected.id);
        sections = ((detail['sections'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => TdSection.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false);
        changes = await widget.api.fetchTdChanges(selected.id);
      }
      setState(() {
        _items = list;
        _selected = selected;
        _sections = sections;
        _changes = changes;
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createTd() async {
    final codeCtl = TextEditingController(text: 'MDR-TD${_items.length + 1}');
    final titleCtl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final okPressed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create TD from Template'),
        content: Form(
          key: formKey,
          child: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(controller: codeCtl, decoration: const InputDecoration(labelText: 'TD code'), validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
                const SizedBox(height: 12),
                TextFormField(controller: titleCtl, decoration: const InputDecoration(labelText: 'Title'), validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (formKey.currentState?.validate() != true) return;
            Navigator.of(context).pop(true);
          }, child: const Text('Create')),
        ],
      ),
    );
    if (okPressed != true) return;

    setState(() => _busy = true);
    try {
      final created = await widget.api.createTdFile(code: codeCtl.text.trim(), title: titleCtl.text.trim());
      await _load();
      if (!mounted) return;
      setState(() => _selected = _items.firstWhere((e) => e.id == created.id, orElse: () => _items.first));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(onPressed: widget.canEdit && !_busy ? _createTd : null, icon: const Icon(Icons.add), label: const Text('Create TD')),
            OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Refresh')),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 360,
                child: Card(
                  child: ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, idx) {
                      final td = _items[idx];
                      final selectedRow = selected?.id == td.id;
                      return ListTile(
                        selected: selectedRow,
                        title: Text('${td.code} · ${td.title}', maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text('Score ${td.summary.complianceScore} · ${td.summary.readinessStatus}'),
                        trailing: Chip(label: Text(td.summary.readinessStatus)),
                        onTap: () async {
                          final detail = await widget.api.fetchTdDetail(td.id);
                          final sections = ((detail['sections'] as List?) ?? const [])
                              .whereType<Map>()
                              .map((e) => TdSection.fromJson(e.cast<String, dynamic>()))
                              .toList(growable: false);
                          final changes = await widget.api.fetchTdChanges(td.id);
                          setState(() {
                            _selected = td;
                            _sections = sections;
                            _changes = changes;
                          });
                        },
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Card(
                  child: Column(
                    children: [
                      TabBar(
                        controller: _tabs,
                        isScrollable: true,
                        tabs: const [
                          Tab(text: 'Dashboard'),
                          Tab(text: 'Structure'),
                          Tab(text: 'Links'),
                          Tab(text: 'Change Control'),
                          Tab(text: 'Heatmap'),
                          Tab(text: 'NB Export'),
                          Tab(text: 'Calendar'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabs,
                          children: [
                            _dashboardTab(selected),
                            _structureTab(),
                            const Center(child: Text('Artifact linking available via API endpoints.')),
                            _changesTab(),
                            _heatmapTab(),
                            _exportTab(),
                            _calendarTab(selected),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dashboardTab(TdFile? td) {
    if (td == null) return const Center(child: Text('No TD available.'));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(td.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Compliance score: ${td.summary.complianceScore}'),
        Text('Readiness: ${td.summary.readinessStatus}'),
        Text('Overdue reviews: ${td.summary.overdueReviews}'),
        const Divider(),
        ...td.summary.reasons.map((r) => ListTile(leading: const Icon(Icons.warning_amber_rounded), title: Text(r))),
      ],
    );
  }

  Widget _structureTab() => ListView(
        children: _sections
            .map((s) => ListTile(
                  title: Text(s.name),
                  subtitle: Text('${s.templateKey} · ${s.ownerUserId ?? 'Unassigned'}'),
                  trailing: Chip(label: Text(s.status)),
                ))
            .toList(growable: false),
      );

  Widget _changesTab() => ListView(
        children: _changes
            .map((c) => ListTile(
                  title: Text(c.title),
                  subtitle: Text('${c.changeType} · ${c.severity}'),
                  trailing: Chip(label: Text(c.status)),
                ))
            .toList(growable: false),
      );

  Widget _heatmapTab() {
    final groups = <String, int>{};
    for (final section in _sections) {
      groups.update(section.status, (v) => v + 1, ifAbsent: () => 1);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Open gaps by section (table view)'),
        const SizedBox(height: 8),
        ...groups.entries.map((e) => ListTile(title: Text(e.key), trailing: Text('${e.value}'))),
        const Divider(),
        const Text('Complaints trend vs TD'),
        const ListTile(title: Text('Trend endpoint prepared in readiness summary.')),
      ],
    );
  }

  Widget _exportTab() => Center(
        child: FilledButton.icon(
          onPressed: _selected == null
              ? null
              : () async {
                  final resp = await widget.api.exportTdNbPackage(_selected!.id);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('NB package status: ${resp['status'] ?? 'n/a'}')),
                  );
                },
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('Generate NB package'),
        ),
      );

  Widget _calendarTab(TdFile? td) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (td != null) ListTile(title: const Text('TD next review'), subtitle: Text(td.rule ?? 'not set')),
          ..._sections.map((s) => ListTile(
                title: Text(s.name),
                subtitle: Text('Next review: ${s.nextReviewAt ?? 'not set'}'),
              )),
        ],
      );
}
