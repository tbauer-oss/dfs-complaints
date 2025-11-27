import 'package:flutter/material.dart';

import '../api/client.dart';
import '../models/wiki_category.dart';

class AdminWikiCategoriesPage extends StatefulWidget {
  final ApiClient api;
  final VoidCallback? onBack;
  const AdminWikiCategoriesPage({super.key, required this.api, this.onBack});

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
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
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
                    onChanged: (v) => setModalState(() => isActive = v ?? false),
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
          elevation: 4,
          shadowColor: cs.shadow.withOpacity(.12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [cs.primaryContainer, cs.surface],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.primary.withOpacity(.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                            child: const Icon(Icons.category_rounded),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Kategorien verwalten',
                                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 4),
                                Text('Strukturierte Übersicht, moderne Filterleiste und klare Status-Badges.',
                                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (widget.onBack != null)
                                OutlinedButton.icon(
                                  onPressed: widget.onBack,
                                  icon: const Icon(Icons.arrow_back),
                                  label: const Text('Zurück zur Übersicht'),
                                ),
                              FilledButton.icon(
                                onPressed: _loading ? null : () => _openForm(),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Neu'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant.withOpacity(.7)),
                  ),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.filter_alt_outlined, color: cs.primary),
                          const SizedBox(width: 8),
                          Text('Status-Filter',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
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
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_loading) const LinearProgressIndicator(minHeight: 3),
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
                          child: DataTableTheme(
                            data: DataTableThemeData(
                              headingRowColor: WidgetStatePropertyAll(cs.surfaceContainerHigh),
                              headingTextStyle:
                                  theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: .2),
                              dataRowColor: WidgetStateProperty.resolveWith(
                                (states) => states.contains(WidgetState.hovered)
                                    ? cs.surfaceContainerHighest
                                    : cs.surface,
                              ),
                              dividerThickness: 0.5,
                              horizontalMargin: 14,
                              columnSpacing: 18,
                            ),
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
                                      DataCell(Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700))),
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
                                        backgroundColor:
                                            c.isActive ? cs.primaryContainer : cs.surfaceVariant,
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
