import 'package:flutter/material.dart';

import '../api/client.dart';
import '../models/wiki_category.dart';

class AdminWikiCategoriesPage extends StatefulWidget {
  final ApiClient api;
  const AdminWikiCategoriesPage({super.key, required this.api});

  @override
  State<AdminWikiCategoriesPage> createState() => _AdminWikiCategoriesPageState();
}

class _AdminWikiCategoriesPageState extends State<AdminWikiCategoriesPage> {
  bool _loading = true;
  String? _err;
  String _statusFilter = 'alle';
  List<WikiCategory> _categories = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final cats = await widget.api.adminFetchWikiCategories(
        status: _statusFilter == 'alle' ? null : _statusFilter,
      );
      if (!mounted) return;
      setState(() => _categories = cats);
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(WikiCategory cat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kategorie löschen?'),
        content: Text('Soll "${cat.name}" wirklich gelöscht werden?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.adminDeleteWikiCategory(cat.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kategorie "${cat.name}" gelöscht')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  Future<void> _openForm({WikiCategory? cat}) async {
    final nameCtrl = TextEditingController(text: cat?.name ?? '');
    final descCtrl = TextEditingController(text: cat?.description ?? '');
    final iconCtrl = TextEditingController(text: cat?.icon ?? 'info');
    final orderCtrl = TextEditingController(text: cat?.sortOrder.toString() ?? '0');
    bool isActive = cat?.isActive ?? true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(cat == null ? 'Kategorie anlegen' : 'Kategorie bearbeiten'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Beschreibung'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: iconCtrl,
                  decoration: const InputDecoration(labelText: 'Icon (z. B. info, warning)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: orderCtrl,
                  decoration: const InputDecoration(labelText: 'Sortierreihenfolge'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: isActive,
                  onChanged: (v) => setState(() => isActive = v ?? false),
                  title: const Text('Aktiv'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Speichern')),
        ],
      ),
    );

    if (result == true) {
      try {
        await widget.api.adminSaveWikiCategory({
          'name': nameCtrl.text.trim(),
          'description': descCtrl.text.trim(),
          'icon': iconCtrl.text.trim(),
          'sortOrder': int.tryParse(orderCtrl.text.trim()).orZero,
          'isActive': isActive,
        }, id: cat?.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(cat == null ? 'Kategorie erstellt' : 'Kategorie aktualisiert')),
        );
        _load();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    }

    nameCtrl.dispose();
    descCtrl.dispose();
    iconCtrl.dispose();
    orderCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, cons) {
        final isCompact = cons.maxWidth < 840;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.category_outlined),
                        const SizedBox(width: 8),
                        Text('Kategorien verwalten', style: theme.textTheme.titleLarge),
                      ],
                    ),
                    SizedBox(
                      width: isCompact ? 180 : 220,
                      child: DropdownButtonFormField<String>(
                        value: _statusFilter,
                        decoration: const InputDecoration(labelText: 'Status'),
                        onChanged: (v) {
                          setState(() => _statusFilter = v ?? 'alle');
                          _load();
                        },
                        items: const [
                          DropdownMenuItem(value: 'alle', child: Text('Alle')),
                          DropdownMenuItem(value: 'active', child: Text('Aktiv')),
                          DropdownMenuItem(value: 'inactive', child: Text('Inaktiv')),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Aktualisieren',
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh),
                    ),
                    FilledButton.icon(
                      onPressed: _loading ? null : () => _openForm(),
                      icon: const Icon(Icons.add),
                      label: const Text('Neu'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_loading) const LinearProgressIndicator(),
                if (_err != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(_err!, style: TextStyle(color: cs.error)),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: cons.maxWidth - 32),
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Name')),
                              DataColumn(label: Text('Beschreibung')),
                              DataColumn(label: Text('Icon')),
                              DataColumn(label: Text('Sortierung')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Aktionen')),
                            ],
                            rows: _categories
                                .map(
                                  (c) => DataRow(cells: [
                                    DataCell(Text(c.name)),
                                    DataCell(Text(c.description.length > 60
                                        ? '${c.description.substring(0, 57)}...'
                                        : c.description)),
                                    DataCell(Row(
                                      children: [
                                        Icon(Icons.circle, size: 14, color: cs.primary),
                                        const SizedBox(width: 6),
                                        Text(c.icon),
                                      ],
                                    )),
                                    DataCell(Text(c.sortOrder.toString())),
                                    DataCell(Chip(
                                      label: Text(c.isActive ? 'Aktiv' : 'Inaktiv'),
                                      backgroundColor: c.isActive
                                          ? cs.primaryContainer
                                          : cs.surfaceVariant,
                                    )),
                                    DataCell(Row(
                                      children: [
                                        IconButton(
                                          tooltip: 'Bearbeiten',
                                          icon: const Icon(Icons.edit_outlined),
                                          onPressed: () => _openForm(cat: c),
                                        ),
                                        IconButton(
                                          tooltip: 'Löschen',
                                          icon: const Icon(Icons.delete_outline),
                                          onPressed: () => _delete(c),
                                        ),
                                      ],
                                    )),
                                  ]),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

extension on int? {
  int get orZero => this ?? 0;
}
