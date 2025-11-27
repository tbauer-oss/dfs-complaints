// lib/pages/admin_downloads_page.dart
import 'dart:convert';
import 'dart:html' as html;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/client.dart';
import '../data/download_categories.dart';
import '../models/download_category.dart';
import '../models/rep_download_item.dart';

class AdminDownloadsPage extends StatefulWidget {
  final ApiClient api;
  const AdminDownloadsPage({super.key, required this.api});

  @override
  State<AdminDownloadsPage> createState() => _AdminDownloadsPageState();
}

class _AdminDownloadsPageState extends State<AdminDownloadsPage> {
  bool _loading = false;
  bool _saving = false;
  String? _err;
  List<RepDownloadItem> _items = const [];
  List<DownloadCategory> _categories = const [];

  // Filters & sorting
  String _search = '';
  String _filterCategory = '';
  String _statusFilter = 'all';
  String _badgeFilter = 'all';
  String _sortBy = 'updated_desc';

  // Form
  final _searchCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  String _badge = '';
  bool _active = true;
  RepDownloadItem? _editing;
  Map<String, dynamic>? _filePayload;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _err = null;
      });
    }
    try {
      final downloads = await widget.api.adminDownloads();
      final categories = await widget.api.adminDownloadCategories();
      if (mounted) {
        setState(() {
          _items = downloads;
          _categories = categories;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _resetForm() {
    _editing = null;
    _titleCtrl.clear();
    _descCtrl.clear();
    _categoryCtrl.clear();
    _badge = '';
    _active = true;
    _filePayload = null;
  }

  void _editItem(RepDownloadItem item) {
    setState(() {
      _editing = item;
      _titleCtrl.text = item.title;
      _descCtrl.text = item.description;
      _categoryCtrl.text = item.category;
      _badge = item.badge;
      _active = item.active;
      _filePayload = null;
    });
  }

  String _guessMime(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: false, withData: true);
    if (res == null || res.files.isEmpty) return;
    final file = res.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datei konnte nicht gelesen werden.')),
      );
      return;
    }

    final mime = _guessMime(file.name);
    setState(() {
      _filePayload = {
        'name': file.name,
        'mime': mime,
        'bytes': base64Encode(bytes),
        'size': bytes.length,
      };
    });
  }

  Future<void> _save() async {
    final formValid = _formKey.currentState?.validate() ?? false;
    if (!formValid) return;
    if (_editing == null && _filePayload == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte eine Datei hochladen.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.api.adminSaveDownload(
        id: _editing?.id,
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        category: _categoryCtrl.text.trim(),
        badge: _badge,
        active: _active,
        file: _filePayload,
      );
      if (mounted) {
        _resetForm();
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_editing == null ? 'Dokument angelegt.' : 'Dokument aktualisiert.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download löschen?'),
        content: const Text('Das Dokument wird aus dem Vertreterbereich entfernt.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.adminDeleteDownload(id);
      await _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
      );
    }
  }

  Future<void> _createCategoryDialog() async {
    final ctrl = TextEditingController();
    final form = GlobalKey<FormState>();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kategorie anlegen'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name der Kategorie',
              hintText: 'z. B. Kataloge',
            ),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Bitte einen Namen eingeben' : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () {
              if (form.currentState?.validate() ?? false) {
                Navigator.of(ctx).pop(ctrl.text.trim());
              }
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      final cats = await widget.api.adminAddDownloadCategory(name.trim());
      if (mounted) setState(() => _categories = cats);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kategorie konnte nicht angelegt werden: $e')),
      );
    }
  }

  Future<void> _deleteCategory(DownloadCategory category) async {
    final hasDocs = category.count > 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kategorie löschen?'),
        content: Text(
          hasDocs
              ? 'Diese Kategorie enthält noch Dokumente. Kategorie und alle enthaltenen Dokumente wirklich löschen?'
              : 'Kategorie wirklich löschen?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: hasDocs ? Colors.red.shade700 : null),
            child: Text(hasDocs ? 'Ja, löschen' : 'Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final cats = await widget.api.adminDeleteDownloadCategory(category.name, force: hasDocs);
      if (mounted) setState(() => _categories = cats);
      if (hasDocs) await _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kategorie konnte nicht gelöscht werden: $e')),
      );
    }
  }

  List<DownloadCategory> get _allCategories {
    final existing = _categories.map((c) => c.name.trim()).where((c) => c.isNotEmpty).toSet();
    final counts = <String, int>{};
    for (final item in _items) {
      if (item.category.trim().isEmpty) continue;
      existing.add(item.category.trim());
      counts[item.category.trim()] = (counts[item.category.trim()] ?? 0) + 1;
    }

    final ordered = <String>[];
    for (final name in kDefaultDownloadCategories) {
      if (existing.contains(name)) ordered.add(name);
    }
    final remaining = existing.difference(ordered.toSet()).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    ordered.addAll(remaining);

    return ordered
        .map(
          (name) {
            final fromApi = _categories.firstWhere(
              (c) => c.name.toLowerCase() == name.toLowerCase(),
              orElse: () => DownloadCategory(name: name, count: 0),
            );
            final count = counts[name] ?? fromApi.count;
            return DownloadCategory(name: name, count: count);
          },
        )
        .toList();
  }

  List<RepDownloadItem> get _filteredItems {
    List<RepDownloadItem> list = _items;
    if (_search.trim().isNotEmpty) {
      final q = _search.trim().toLowerCase();
      list = list.where((i) {
        return i.title.toLowerCase().contains(q) ||
            i.description.toLowerCase().contains(q) ||
            i.category.toLowerCase().contains(q);
      }).toList();
    }
    if (_filterCategory.isNotEmpty) {
      list = list.where((i) => i.category.toLowerCase() == _filterCategory.toLowerCase()).toList();
    }
    if (_statusFilter != 'all') {
      list = list.where((i) => _statusFilter == 'active' ? i.active : !i.active).toList();
    }
    if (_badgeFilter != 'all') {
      list = list.where((i) {
        if (_badgeFilter == 'none') return i.badge.isEmpty;
        return i.badge == _badgeFilter;
      }).toList();
    }

    int compareByTitle(RepDownloadItem a, RepDownloadItem b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());
    int compareByCategory(RepDownloadItem a, RepDownloadItem b) => a.category.toLowerCase().compareTo(b.category.toLowerCase());

    switch (_sortBy) {
      case 'title_asc':
        list.sort(compareByTitle);
        break;
      case 'title_desc':
        list.sort((a, b) => compareByTitle(b, a));
        break;
      case 'category':
        list.sort(compareByCategory);
        break;
      default:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    return list;
  }

  String _formatDate(int ts) {
    if (ts <= 0) return '—';
    return DateFormat('dd.MM.yyyy – HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ts));
  }

  String _formatSize(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size > 900 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size >= 10 || unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  Widget _buildStatusChip(bool active) {
    return Chip(
      label: Text(active ? 'Aktiv' : 'Inaktiv'),
      avatar: Icon(active ? Icons.check_circle : Icons.pause_circle_filled, size: 18, color: active ? Colors.green : Colors.grey),
      backgroundColor: active ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.12),
      shape: StadiumBorder(side: BorderSide(color: active ? Colors.green.shade200 : Colors.grey.shade300)),
    );
  }

  Widget _buildBadgeChip(String badge) {
    if (badge.isEmpty) return const SizedBox.shrink();
    final label = badge == 'change' ? 'Change' : 'New';
    final color = badge == 'change' ? Colors.amber : Colors.blue;
    return Chip(
      label: Text(label),
      avatar: Icon(Icons.fiber_manual_record, size: 14, color: color.shade700),
      backgroundColor: color.withOpacity(0.12),
      shape: StadiumBorder(side: BorderSide(color: color.shade200)),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final totalActive = _items.where((i) => i.active).length;
    final totalInactive = _items.length - totalActive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.cloud_upload_outlined, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Downloads für Vertreter', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'Hochladen, kuratieren und gezielt freischalten – ohne die bestehende Logik anzutasten.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.7)),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metricCard('Dokumente', _items.length.toString(), Icons.folder_open),
            _metricCard('Aktiv', totalActive.toString(), Icons.check_circle_outline, accent: Colors.green),
            _metricCard('Inaktiv', totalInactive.toString(), Icons.pause_circle_outline, accent: Colors.amber),
            _metricCard('Kategorien', _allCategories.length.toString(), Icons.category_outlined, accent: Colors.indigo),
          ],
        ),
      ],
    );
  }

  Widget _metricCard(String label, String value, IconData icon, {Color? accent}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            blurRadius: 12,
            spreadRadius: -2,
            color: Colors.black.withOpacity(0.04),
          ),
        ],
        border: Border.all(color: theme.dividerColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent ?? theme.colorScheme.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.hintColor)),
              Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune_outlined),
                const SizedBox(width: 8),
                Text('Filter & Sortierung', style: theme.textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _search = '';
                      _searchCtrl.clear();
                      _filterCategory = '';
                      _statusFilter = 'all';
                      _badgeFilter = 'all';
                      _sortBy = 'updated_desc';
                    });
                  },
                  icon: const Icon(Icons.restart_alt_outlined),
                  label: const Text('Zurücksetzen'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (ctx, cons) {
                final isNarrow = cons.maxWidth < 720;
                final children = [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Suche',
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Titel, Beschreibung oder Kategorie',
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      value: _filterCategory.isEmpty ? null : _filterCategory,
                      decoration: const InputDecoration(labelText: 'Kategorie'),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Alle Kategorien')),
                        ..._allCategories
                            .map((c) => DropdownMenuItem(value: c.name, child: Text(c.name)))
                            .toList(),
                      ],
                      onChanged: (v) => setState(() => _filterCategory = v ?? ''),
                    ),
                  ),
                ];
                return isNarrow
                    ? Column(
                        children: [
                          children[0],
                          const SizedBox(height: 12),
                          children[2],
                        ],
                      )
                    : Row(children: children);
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    value: _statusFilter,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Alle')),
                      DropdownMenuItem(value: 'active', child: Text('Aktiv')),
                      DropdownMenuItem(value: 'inactive', child: Text('Inaktiv')),
                    ],
                    onChanged: (v) => setState(() => _statusFilter = v ?? 'all'),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    value: _badgeFilter,
                    decoration: const InputDecoration(labelText: 'Badge'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Alle')),
                      DropdownMenuItem(value: 'new', child: Text('New')),
                      DropdownMenuItem(value: 'change', child: Text('Change')),
                      DropdownMenuItem(value: 'none', child: Text('Ohne Badge')),
                    ],
                    onChanged: (v) => setState(() => _badgeFilter = v ?? 'all'),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    value: _sortBy,
                    decoration: const InputDecoration(labelText: 'Sortierung'),
                    items: const [
                      DropdownMenuItem(value: 'updated_desc', child: Text('Neuste zuerst')),
                      DropdownMenuItem(value: 'title_asc', child: Text('Titel A–Z')),
                      DropdownMenuItem(value: 'title_desc', child: Text('Titel Z–A')),
                      DropdownMenuItem(value: 'category', child: Text('Kategorie')),
                    ],
                    onChanged: (v) => setState(() => _sortBy = v ?? 'updated_desc'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _editing == null ? 'Neues Dokument' : 'Dokument bearbeiten',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (_editing != null)
                    TextButton.icon(
                      onPressed: _saving ? null : () => setState(_resetForm),
                      icon: const Icon(Icons.add_outlined),
                      label: const Text('Neu anlegen'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (ctx, cons) {
                  final isNarrow = cons.maxWidth < 680;
                  final fields = [
                    Expanded(
                      child: TextFormField(
                        controller: _titleCtrl,
                        decoration: const InputDecoration(labelText: 'Titel', prefixIcon: Icon(Icons.title_outlined)),
                        validator: (v) => (v ?? '').trim().isEmpty ? 'Titel wird benötigt' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _categoryCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Kategorie',
                          hintText: 'z. B. Kataloge',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                      ),
                    ),
                  ];
                  return isNarrow
                      ? Column(children: [fields[0], const SizedBox(height: 12), fields[2]])
                      : Row(children: fields);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Beschreibung',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.short_text_outlined),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<String>(
                      value: _badge.isEmpty ? null : _badge,
                      decoration: const InputDecoration(labelText: 'Markierung'),
                      items: const [
                        DropdownMenuItem(value: 'new', child: Text('New')),
                        DropdownMenuItem(value: 'change', child: Text('Change')),
                      ],
                      onChanged: (v) => setState(() => _badge = v ?? ''),
                      hint: const Text('Keine Markierung'),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: SwitchListTile.adaptive(
                      value: _active,
                      onChanged: (v) => setState(() => _active = v),
                      title: const Text('Aktiv'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _pickFile,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(_filePayload == null ? 'Datei wählen' : 'Datei ersetzt'),
                  ),
                  if (_filePayload != null)
                    Chip(
                      label: Text('${_filePayload?['name'] ?? ''} · ${_formatSize(_filePayload?['size'] ?? 0)}'),
                      avatar: const Icon(Icons.attachment_outlined, size: 18),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_editing == null ? 'Anlegen' : 'Aktualisieren'),
                  ),
                  const SizedBox(width: 12),
                  if (_editing != null)
                    TextButton.icon(
                      onPressed: _saving ? null : () => _delete(_editing!.id),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Löschen'),
                      style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryManager() {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.category_outlined),
                const SizedBox(width: 8),
                Text('Kategorien', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _createCategoryDialog,
                  icon: const Icon(Icons.add_outlined),
                  label: const Text('Kategorie hinzufügen'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allCategories.map((cat) {
                return Chip(
                  label: Text('${cat.name} (${cat.count})'),
                  deleteIcon: const Icon(Icons.delete_outline),
                  onDeleted: () => _deleteCategory(cat),
                  backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    }
    if (_err != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(_err!, style: const TextStyle(color: Colors.red)),
      );
    }
    if (_filteredItems.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Keine Dokumente angelegt.'),
      );
    }

    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.table_chart_outlined),
                const SizedBox(width: 8),
                Text('Dokumentenübersicht', style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'Neu laden',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _load(silent: true),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 960),
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Titel')),
                  DataColumn(label: Text('Kategorie')),
                  DataColumn(label: Text('Badge')),
                  DataColumn(label: Text('Version')),
                  DataColumn(label: Text('Aktualisiert')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Aktionen')),
                ],
                rows: _filteredItems.map((item) {
                  return DataRow(cells: [
                    DataCell(Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (item.description.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(item.description, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Datei: ${item.fileName}', style: const TextStyle(fontSize: 12, color: Colors.black45)),
                        ),
                      ],
                    )),
                    DataCell(item.category.isNotEmpty ? Text(item.category) : const Text('–')),
                    DataCell(_buildBadgeChip(item.badge)),
                    DataCell(Text('v${item.version}')),
                    DataCell(Text(_formatDate(item.updatedAt))),
                    DataCell(_buildStatusChip(item.active)),
                    DataCell(Row(
                      children: [
                        IconButton(
                          tooltip: 'Öffnen',
                          icon: const Icon(Icons.open_in_new_outlined),
                          onPressed: () => html.window.open(item.downloadUrl, '_blank'),
                        ),
                        IconButton(
                          tooltip: 'Bearbeiten',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _editItem(item),
                        ),
                      ],
                    )),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildFilters(),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (ctx, cons) {
                final isWide = cons.maxWidth > 1180;
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: _buildForm()),
                      const SizedBox(width: 16),
                      Expanded(child: _buildCategoryManager()),
                    ],
                  );
                }
                return Column(
                  children: [
                    _buildForm(),
                    const SizedBox(height: 12),
                    _buildCategoryManager(),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _buildList(),
          ],
        ),
      ),
    );
  }
}
