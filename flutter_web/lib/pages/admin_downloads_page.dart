// lib/pages/admin_downloads_page.dart
import 'dart:convert';
import 'dart:html' as html;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../api/client.dart';
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

  // Form
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
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final list = await widget.api.adminDownloads();
      if (mounted) {
        setState(() {
          _items = list;
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
      _active = true;
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
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Titel wird benötigt.')),
      );
      return;
    }
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
      _resetForm();
      await _load();
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

  Widget _buildForm() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _editing == null ? 'Neues Dokument' : 'Dokument bearbeiten',
                    style: Theme.of(context).textTheme.titleMedium,
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
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Titel'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Beschreibung'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _categoryCtrl,
              decoration: const InputDecoration(labelText: 'Kategorie (optional)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
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
                const SizedBox(width: 16),
                SwitchListTile(
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                  title: const Text('Aktiv'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _saving ? null : _pickFile,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(_filePayload == null ? 'Datei wählen' : 'Datei ersetzt'),
                ),
                const SizedBox(width: 12),
                if (_filePayload != null)
                  Text(_filePayload?['name']?.toString() ?? ''),
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
                  TextButton(
                    onPressed: _saving ? null : () => _delete(_editing!.id),
                    child: const Text('Löschen'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_err != null) return Text(_err!, style: const TextStyle(color: Colors.red));
    if (_items.isEmpty) return const Text('Keine Dokumente angelegt.');
    return Column(
      children: _items
          .map(
            (item) => Card(
              child: ListTile(
                title: Text(item.title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.description.isNotEmpty) Text(item.description),
                    Row(
                      children: [
                        if (item.category.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Chip(label: Text(item.category)),
                          ),
                        if (item.badge.isNotEmpty)
                          Chip(
                            label: Text(item.badge == 'change' ? 'Change' : 'New'),
                            avatar: const Icon(Icons.fiber_manual_record, size: 14),
                          ),
                      ],
                    ),
                    Text('Version ${item.version}'),
                  ],
                ),
                trailing: Wrap(
                  spacing: 8,
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
                ),
              ),
            ),
          )
          .toList(),
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
            Row(
              children: [
                const Icon(Icons.download_outlined),
                const SizedBox(width: 8),
                Text(
                  'Downloads für Vertreter',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Dateien hochladen, verwalten und für Vertreter bereitstellen. New/Change-Badges werden automatisch verwaltet.'),
            const SizedBox(height: 12),
            _buildForm(),
            _buildList(),
          ],
        ),
      ),
    );
  }
}
