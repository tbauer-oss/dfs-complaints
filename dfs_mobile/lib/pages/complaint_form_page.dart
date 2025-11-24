// lib/pages/complaint_form_page.dart
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../data/knowledge_base_data.dart';
import '../models/complaint_attachment.dart';
import '../utils/attachment_preview.dart';
import 'knowledge_base_page.dart';
import 'complaint_summary_page.dart';

enum _AttachmentSource { camera, gallery, files }

class _WizardStep {
  final String id;
  final IconData icon;
  final String title;
  final String hint;
  const _WizardStep({required this.id, required this.icon, required this.title, required this.hint});
}

// KEIN dart:html mehr nötig

extension _L10nX on BuildContext {
  AppLocalizations get t => AppLocalizations.of(this)!;
}

class ComplaintFormPage extends StatefulWidget {
  final ApiClient api;
  final bool wizardMode;
  const ComplaintFormPage({super.key, required this.api, this.wizardMode = false});
  @override
  State<ComplaintFormPage> createState() => _ComplaintFormPageState();
}

class _ComplaintFormPageState extends State<ComplaintFormPage> {
  static const _uploadLimit = 8 * 1024 * 1024;
  static const _helpPrefKey = 'dfs_complaint_help_collapsed';
  static const _keywordHints = {
    'gebrochen': ['bruch', 'gebroch', 'sturz', 'verbieg', 'unbrauchbar'],
    'abgebrochen': ['bruch', 'gebroch', 'sturz', 'verbieg'],
    'verbogen': ['verbieg', 'krumm', 'unwucht'],
    'heiss': ['heiß', 'hitze', 'ueberhitz', 'überhitz'],
    'heiß': ['heiss', 'hitze', 'ueberhitz', 'überhitz'],
    'vibration': ['vibri', 'unwucht'],
    'vibriert': ['vibration', 'unwucht'],
    'korrosion': ['rost', 'korro', 'verfärb', 'fleck'],
    'rost': ['korro', 'verfärb'],
  };
  String segment = 'Zahnmedizin';
  final article = TextEditingController();
  final batch = TextEditingController();
  final qty = TextEditingController();
  final expiry = TextEditingController();
  final desc = TextEditingController();
  String applied = 'Nein';
  String injury = 'Nein';
  final injuryDesc = TextEditingController();
  String returned = 'Nein';
  String handling = 'Ersatz';
  bool privacy = false;

  // Wichtig: exakt dieser Record-Typ (Name, Bytes, Mime)
  List<({String name, List<int> bytes, String mime, String? preview})> files = [];

  String? info;
  String? err;
  bool busy = false;

  Map<String, dynamic>? _account;
  bool _helpCollapsed = false;

  bool _dirty = false;
  final List<TextEditingController> _ctrls = [];
  KnowledgeItem? _autoHelpItem;
  final ScrollController _scrollCtrl = ScrollController();
  int _wizardStep = 0;
  final Map<String, GlobalKey> _sectionKeys = {
    'segment': GlobalKey(),
    'product': GlobalKey(),
    'patient': GlobalKey(),
    'attachments': GlobalKey(),
    'resolution': GlobalKey(),
    'privacy': GlobalKey(),
  };

  void _markDirty() { if (!_dirty) setState(() => _dirty = true); }

  void _handleDescriptionChanged() {
    _markDirty();
    _updateAutoHelp();
  }

  @override
  void dispose() {
    for (final c in _ctrls) { c.removeListener(_markDirty); }
    desc.removeListener(_handleDescriptionChanged);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _updateAutoHelp() {
    final t = context.t;
    final query = desc.text.toLowerCase().trim();
    if (query.length < 12) {
      if (_autoHelpItem != null) setState(() => _autoHelpItem = null);
      return;
    }

    final tokens = query
        .split(RegExp(r'[^a-zA-ZäöüÄÖÜß0-9]+'))
        .map((w) => w.trim())
        .where((w) => w.length >= 3)
        .toList();

    KnowledgeItem? best;
    var bestScore = 0;

    for (final item in knowledgeItems) {
      final content = '${item.question(t)} ${item.answer(t)}'.toLowerCase();
      var score = 0;

      if (content.contains(query)) score += 6;

      for (final token in tokens) {
        final variants = <String>{token};
        final extra = _keywordHints[token];
        if (extra != null) variants.addAll(extra);
        for (final needle in variants) {
          if (needle.isEmpty) continue;
          if (content.contains(needle)) score += 2;
        }
      }

      if (score == 0) continue;
      if (score > bestScore) {
        best = item;
        bestScore = score;
      }
    }

    setState(() => _autoHelpItem = bestScore >= 2 ? best : null);
  }

  List<_WizardStep> _buildWizardSteps(AppLocalizations t, {required bool isDentist}) {
    return [
      _WizardStep(id: 'segment', icon: Icons.flag_outlined, title: t.complaint_wizard_step_overview, hint: t.segment),
      _WizardStep(id: 'product', icon: Icons.shopping_bag_outlined, title: t.complaint_wizard_step_product, hint: t.article),
      if (isDentist)
        _WizardStep(
          id: 'patient',
          icon: Icons.favorite_outline,
          title: t.complaint_wizard_step_patient,
          hint: t.applied_to_patient,
        ),
      _WizardStep(
        id: 'attachments',
        icon: Icons.photo_library_outlined,
        title: t.complaint_wizard_step_attachments,
        hint: t.attachments_title,
      ),
      _WizardStep(
        id: 'resolution',
        icon: Icons.handshake_outlined,
        title: t.complaint_wizard_step_confirmation,
        hint: t.returned_question,
      ),
      _WizardStep(
        id: 'privacy',
        icon: Icons.privacy_tip_outlined,
        title: t.privacy_view,
        hint: t.complaint_wizard_step_finish,
      ),
    ];
  }

  Future<void> _scrollToSection(String id) async {
    final ctx = _sectionKeys[id]?.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.05,
    );
  }

  Future<void> _goToStep(List<_WizardStep> steps, int index) async {
    if (index < 0 || index >= steps.length) return;
    setState(() => _wizardStep = index);
    await _scrollToSection(steps[index].id);
  }

  Widget _wizardAnchor(String id, Widget child) {
    return KeyedSubtree(key: _sectionKeys[id], child: child);
  }

  void _removeAttachmentAt(int index) {
    setState(() {
      final next = List.of(files)..removeAt(index);
      files = next;
      _dirty = true;
    });
  }

  Future<bool> _confirmLeaveIfDirty() async {
    if (!_dirty) return true;
    final t = context.t;
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t.unsavedChangesTitle),
        content: Text(t.unsavedChangesText),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: Text(t.leave)),
        ],
      ),
    );
    return res == true;
  }

  Future<void> _handleBack() async { if (await _confirmLeaveIfDirty()) Navigator.of(context).pop(); }
  Future<void> _handleCancel() async => _handleBack();

  @override
  void initState() {
    super.initState();
    _ctrls.addAll([article, batch, qty, expiry, injuryDesc]);
    for (final c in _ctrls) { c.addListener(_markDirty); }
    desc.addListener(_handleDescriptionChanged);
    _loadAccount();
    _loadHelpPref();
  }

  Future<void> pickFiles() async {
    if (kIsWeb) {
      await _pickWithFilePicker();
      return;
    }

    final source = await _selectAttachmentSource();
    if (source == null) return;

    switch (source) {
      case _AttachmentSource.camera:
        await _pickFromCamera();
        break;
      case _AttachmentSource.gallery:
        await _pickFromGallery();
        break;
      case _AttachmentSource.files:
        await _pickWithFilePicker();
        break;
    }
  }

  Future<_AttachmentSource?> _selectAttachmentSource() {
    final t = context.t;
    return showModalBottomSheet<_AttachmentSource>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(t.attachment_source_camera),
              onTap: () => Navigator.pop(context, _AttachmentSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(t.attachment_source_gallery),
              onTap: () => Navigator.pop(context, _AttachmentSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_outlined),
              title: Text(t.attachment_source_files),
              onTap: () => Navigator.pop(context, _AttachmentSource.files),
            ),
          ],
        ),
      ),
    );
  }

  String _guessMime(String name) {
    final parts = name.split('.');
    final ext = parts.length > 1 ? parts.last.toLowerCase() : '';
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
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  Future<({List<int> bytes, String mime})> _compressImage(List<int> data, String mime) async {
    try {
      final image = img.decodeImage(Uint8List.fromList(data));
      if (image == null) return (bytes: data, mime: mime);

      final maxSide = 1800;
      final needsResize = image.width > maxSide || image.height > maxSide;
      final resized = needsResize
          ? img.copyResize(
              image,
              width: (image.width > image.height ? maxSide : null),
              height: (image.height >= image.width ? maxSide : null),
              interpolation: img.Interpolation.cubic,
            )
          : image;
      final compressed = img.encodeJpg(resized, quality: 85);
      return (bytes: compressed, mime: 'image/jpeg');
    } catch (_) {
      return (bytes: data, mime: mime);
    }
  }

  Future<void> _applySelection(List<({String name, List<int> bytes, String mime})> selected) async {
    if (selected.isEmpty) return;
    final t = context.t;

    int totalBytes = 0;
    final next = <({String name, List<int> bytes, String mime, String? preview})>[];

    for (final file in selected) {
      List<int> bytes = file.bytes;
      String mime = file.mime;

      if (mime.startsWith('image/')) {
        final compressed = await _compressImage(bytes, mime);
        bytes = compressed.bytes;
        mime = compressed.mime;
      }

      totalBytes += bytes.length;
      if (totalBytes > _uploadLimit) {
        if (mounted) setState(() => err = t.images_too_large);
        return;
      }

      final preview = createAttachmentPreview(bytes, mime);
      next.add((name: file.name, bytes: bytes, mime: mime, preview: preview));
    }

    if (!mounted) return;
    setState(() {
      files = next;
      err = null;
      _dirty = true;
    });
  }

  Future<void> _pickWithFilePicker() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (res == null) return;

    final selected = res.files
        .where((f) => f.bytes != null && f.bytes!.isNotEmpty)
        .map((f) => (
              name: f.name,
              bytes: List<int>.from(f.bytes!),
              mime: _guessMime(f.name),
            ))
        .toList();

    await _applySelection(selected);
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final result = await picker.pickMultiImage();
    if (result.isEmpty) return;

    final selected = <({String name, List<int> bytes, String mime})>[];
    for (final file in result) {
      final bytes = await file.readAsBytes();
      selected.add((name: file.name, bytes: bytes, mime: _guessMime(file.name)));
    }

    await _applySelection(selected);
  }

  Future<void> _pickFromCamera() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.camera, requestFullMetadata: false);
    if (photo == null) return;

    final bytes = await photo.readAsBytes();
    await _applySelection([
      (name: photo.name, bytes: bytes, mime: _guessMime(photo.name)),
    ]);
  }

  // -----------------------------
  // Hilfsfunktionen für dein Flow
  // -----------------------------
  void _resetForm() {
    final t = context.t;
    final optDentist = t.segment_dentist;
    final optNo = t.no;
    final optReturnedNo = t.no;
    final optHandlingRep = t.handling_replacement;

    setState(() {
      segment = optDentist;           // Standard: Zahnarzt
      article.clear();
      batch.clear();
      qty.clear();
      expiry.clear();
      desc.clear();
      applied = optNo;
      injury = optNo;
      injuryDesc.clear();
      returned = optReturnedNo;
      handling = optHandlingRep;
      privacy = false;
      files = [];
      err = null;
      info = null;
      _dirty = false;
      _autoHelpItem = null;
      _wizardStep = 0;
    });
  }

  Future<void> _loadAccount() async {
    try {
      final data = await widget.api.accountGet();
      if (!mounted) return;
      setState(() => _account = data);
    } catch (_) {
      // optional: still usable without Accountdaten
    }
  }

  Future<void> _loadHelpPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final collapsed = prefs.getBool(_helpPrefKey) ?? false;
      if (!mounted) return;
      setState(() => _helpCollapsed = collapsed);
    } catch (_) {}
  }

  Future<void> _persistHelpPref(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_helpPrefKey, value);
    } catch (_) {}
  }

  void _toggleHelpBox() {
    final next = !_helpCollapsed;
    setState(() => _helpCollapsed = next);
    _persistHelpPref(next);
  }

  void _openHelpLink() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => KnowledgeBasePage(api: widget.api),
    ));
  }

  List<String> _splitAnswer(String raw) {
    return raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => line.replaceFirst(RegExp(r'^[•\-\u2022]\s*'), ''))
        .toList();
  }

  void _openSuggestedAnswer(KnowledgeItem item) {
    final t = context.t;
    final answers = _splitAnswer(item.answer(t));
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final bottomPadding = MediaQuery.of(ctx).viewPadding.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, bottomPadding + 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.psychology_outlined, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t.complaint_auto_help_title,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  knowledgeCategoryLabel(item.category, t),
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  item.question(t),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                ...answers.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 3),
                          child: Icon(Icons.check_circle_outline, size: 16),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(a, style: const TextStyle(height: 1.35))),
                      ],
                    ),
                  ),
                ),
                if (answers.isEmpty)
                  Text(item.answer(t), style: const TextStyle(height: 1.4)),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _openHelpLink();
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: Text(t.complaint_help_link),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAutoHelpCard({required bool compact}) {
    final suggestion = _autoHelpItem;
    if (suggestion == null) return const SizedBox.shrink();

    final t = context.t;
    final theme = Theme.of(context);
    final answers = _splitAnswer(suggestion.answer(t));
    final preview = answers.isNotEmpty ? answers.first : null;

    return Card(
      color: theme.colorScheme.secondaryContainer.withOpacity(0.72),
      elevation: 0,
      margin: EdgeInsets.only(top: compact ? 4 : 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(compact ? 12 : 14)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, compact ? 10 : 12, 12, compact ? 12 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology_alt_outlined, color: theme.colorScheme.primary),
                SizedBox(width: compact ? 8 : 10),
                Expanded(
                  child: Text(
                    t.complaint_auto_help_title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSecondaryContainer,
                      fontSize: compact ? 13.5 : 14,
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Chip(
                visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                label: Text(
                  knowledgeCategoryLabel(suggestion.category, t),
                  style: const TextStyle(fontSize: 11),
                ),
                avatar: Icon(Icons.folder_open, size: 18, color: theme.colorScheme.primary),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            SizedBox(height: compact ? 4 : 6),
            Text(
              t.complaint_auto_help_intro,
              style: TextStyle(
                color: theme.colorScheme.onSecondaryContainer.withOpacity(0.9),
                fontSize: compact ? 12.5 : 13,
              ),
            ),
            SizedBox(height: compact ? 6 : 8),
            Text(
              suggestion.question(t),
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: compact ? 13.5 : 14),
            ),
            if (preview != null) ...[
              SizedBox(height: compact ? 4 : 6),
              Text(
                preview,
                maxLines: compact ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(height: 1.35),
              ),
            ],
            SizedBox(height: compact ? 8 : 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14, vertical: compact ? 8 : 10),
                  minimumSize: Size(compact ? 0 : 40, 0),
                  textStyle: TextStyle(fontSize: compact ? 12.5 : 13.5),
                ),
                onPressed: () => _openSuggestedAnswer(suggestion),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: Text(t.complaint_auto_help_button),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<ComplaintAttachment> _currentAttachments() {
    return files
        .map((f) => ComplaintAttachment(
              name: f.name,
              bytes: Uint8List.fromList(f.bytes),
              mime: f.mime,
            ))
        .toList(growable: false);
  }

  Future<void> _showSummary(String ticket, Map<String, dynamic> payload) async {
    final accountSnapshot = _account == null ? null : Map<String, dynamic>.from(_account!);
    final result = await Navigator.of(context).push<ComplaintSummaryResult>(
      MaterialPageRoute(
        builder: (_) => ComplaintSummaryPage(
          ticket: ticket,
          createdAt: DateTime.now(),
          payload: Map<String, dynamic>.from(payload),
          account: accountSnapshot,
          attachments: _currentAttachments(),
        ),
      ),
    );

    if (!mounted) return;
    if (result == ComplaintSummaryResult.newComplaint) {
      _resetForm();
    } else {
      await _navigateToDashboard();
    }
  }

  Future<void> _navigateToDashboard() async {
    if (!mounted) return;
    try {
      // Falls du eine benannte Route hast:
      Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (r) => false);
    } catch (_) {
      // Fallback: so weit wie möglich zurück
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  // -----------------------------
  // UI-Helfer (nur Darstellung)
  // -----------------------------
  InputDecoration _dec(BuildContext ctx, String label, {String? hint, required bool compact}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(ctx).colorScheme.outlineVariant),
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: compact ? 10 : 12,
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required List<Widget> children,
    required bool compact,
  }) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(compact ? 12 : 16)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, compact ? 12 : 14, 14, compact ? 14 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20),
                SizedBox(width: compact ? 6 : 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: compact ? 15 : 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 10 : 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _wizardReview({required bool compact, required AppLocalizations t}) {
    final theme = Theme.of(context);
    final entries = <String, String>{
      t.segment: segment,
      t.article: article.text.trim(),
      t.batch: batch.text.trim(),
      t.qty: qty.text.trim(),
      t.expiry: expiry.text.trim(),
      if (segment == t.segment_dentist) t.applied_to_patient: applied,
      if (segment == t.segment_dentist) t.injury_question: injury,
      t.returned_question: returned,
      t.handling: handling,
    };

    return Card(
      margin: EdgeInsets.only(top: compact ? 8 : 10),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fact_check_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(t.complaint_wizard_step_finish, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in entries.entries)
                  if (entry.value.isNotEmpty)
                    Chip(
                      label: Text('${entry.key}: ${entry.value}'),
                      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 6 : 8),
                    ),
              ],
            ),
            const SizedBox(height: 10),
            Text(desc.text.trim().isEmpty ? t.problem_desc : desc.text.trim()),
            if (files.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in files)
                    Chip(
                      avatar: const Icon(Icons.insert_drive_file_outlined),
                      label: Text(entry.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _banner({required bool isError, required String text}) {
    final color = isError ? Colors.red : Colors.green;
    final bg = isError ? Colors.red.withOpacity(.06) : Colors.green.withOpacity(.06);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(.25))),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _buildWizardCard({required List<_WizardStep> steps, required AppLocalizations t, required bool compact}) {
    if (steps.isEmpty) return const SizedBox.shrink();
    final active = _wizardStep.clamp(0, steps.length - 1);
    if (active != _wizardStep) _wizardStep = active;

    final theme = Theme.of(context);
    final subtleBg = theme.colorScheme.surfaceContainerHighest;

    Widget stepChip(int index, _WizardStep step) {
      final selected = index == active;
      return ChoiceChip(
        selected: selected,
        onSelected: (_) => _goToStep(steps, index),
        labelPadding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 6 : 8),
        avatar: CircleAvatar(
          radius: 12,
          backgroundColor: selected ? theme.colorScheme.primary : theme.colorScheme.primary.withOpacity(.15),
          child: Icon(step.icon, size: 15, color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.primary),
        ),
        label: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${index + 1}. ${step.title}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: compact ? 13 : 13.5)),
            const SizedBox(height: 2),
            Text(step.hint, style: TextStyle(fontSize: compact ? 11.5 : 12, color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.symmetric(vertical: compact ? 8 : 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(compact ? 12 : 16)),
      color: subtleBg,
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 12 : 14, compact ? 12 : 14, compact ? 12 : 14, compact ? 12 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_outlined, color: theme.colorScheme.primary),
                SizedBox(width: compact ? 8 : 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.complaint_wizard_title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: compact ? 15 : 16)),
                      const SizedBox(height: 4),
                      Text(
                        t.complaint_wizard_subtitle,
                        style: TextStyle(fontSize: compact ? 12.5 : 13, color: theme.colorScheme.onSurfaceVariant, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final entry in steps.asMap().entries) stepChip(entry.key, entry.value)],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.complaint_wizard_hint,
                    style: TextStyle(fontSize: compact ? 12 : 12.5, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: active > 0 ? () => _goToStep(steps, active - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                  label: Text(t.complaint_wizard_prev),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: active < steps.length - 1
                      ? () => _goToStep(steps, active + 1)
                      : () => _goToStep(steps, steps.length - 1),
                  icon: Icon(active < steps.length - 1 ? Icons.navigate_next : Icons.check_circle_outline),
                  label: Text(active < steps.length - 1 ? t.complaint_wizard_next : t.complaint_wizard_done),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final width = MediaQuery.of(context).size.width;
    final compact = width < 420;
    final optDentist = t.segment_dentist, optLab = t.segment_lab;
    final optYes = t.yes, optNo = t.no;
    final optReturnedYes = t.yes, optReturnedNo = t.no;
    final optHandlingRep = t.handling_replacement, optHandlingCredit = t.handling_credit, optHandlingRework = t.handling_rework;

    if (segment != optDentist && segment != optLab) segment = optDentist;
    if (applied != optYes && applied != optNo) applied = optNo;
    if (injury != optYes && injury != optNo) injury = optNo;
    if (returned != optReturnedYes && returned != optReturnedNo) returned = optReturnedNo;
    if (![optHandlingRep, optHandlingCredit, optHandlingRework].contains(handling)) handling = optHandlingRep;

    final isDentist = segment == optDentist;
    final needInjuryDesc = isDentist && applied == optYes && injury == optYes;

    final wizardSteps = widget.wizardMode
        ? _buildWizardSteps(t, isDentist: isDentist)
        : const <_WizardStep>[];
    final activeWizardIndex = widget.wizardMode && wizardSteps.isNotEmpty
        ? _wizardStep.clamp(0, wizardSteps.length - 1)
        : 0;
    final isWizardFinalStep = widget.wizardMode && wizardSteps.isNotEmpty && activeWizardIndex == wizardSteps.length - 1;

    final body = SingleChildScrollView(
      controller: _scrollCtrl,
      padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 12, compact ? 12 : 16, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: compact ? 640 : 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Kopfinfo (rein visuell)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(compact ? 12 : 16)),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(14, compact ? 12 : 14, 14, compact ? 12 : 14),
                  child: Row(
                    children: [
                      const Icon(Icons.report_gmailerrorred_outlined),
                      SizedBox(width: compact ? 8 : 10),
                      Expanded(
                        child: Text(
                          t.reportComplaint,
                          style: TextStyle(fontSize: compact ? 17 : 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (widget.wizardMode)
                _buildWizardCard(steps: wizardSteps, t: t, compact: compact),

              _buildHelpBox(compact: compact),

              Builder(builder: (context) {
                final sections = <({String id, Widget widget})>[];

                sections.add(
                  (id: 'segment', widget: _wizardAnchor('segment', _section(
                    icon: Icons.person_outline,
                    title: t.segment,
                    compact: compact,
                    children: [
                      DropdownButtonFormField<String>(
                        value: segment,
                        items: [
                          DropdownMenuItem(value: optDentist, child: Text(optDentist)),
                          DropdownMenuItem(value: optLab, child: Text(optLab)),
                        ],
                        onChanged: (v) => setState(() { segment = v ?? optDentist; _dirty = true; }),
                        decoration: _dec(context, t.segment, compact: compact),
                      ),
                    ],
                  ))),
                );

                sections.add(
                  (id: 'product', widget: _wizardAnchor('product', _section(
                    icon: Icons.build_outlined,
                    title: t.article,
                    compact: compact,
                    children: [
                      TextField(controller: article, decoration: _dec(context, t.article, compact: compact)),
                      const SizedBox(height: 10),
                      TextField(
                        controller: batch,
                        decoration: _dec(context, isDentist ? '${t.batch} *' : t.batch, hint: isDentist ? t.batch : null, compact: compact),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: TextField(controller: qty, decoration: _dec(context, t.qty, compact: compact))),
                        SizedBox(width: compact ? 8 : 10),
                        Expanded(child: TextField(controller: expiry, decoration: _dec(context, t.expiry, compact: compact))),
                      ]),
                      const SizedBox(height: 10),
                      TextField(
                        controller: desc,
                        maxLines: 4,
                        decoration: _dec(context, t.problem_desc, compact: compact),
                      ),
                      const SizedBox(height: 4),
                      _buildAutoHelpCard(compact: compact),
                    ],
                  ))),
                );

                if (isDentist) {
                  sections.add(
                    (id: 'patient', widget: _wizardAnchor('patient', _section(
                      icon: Icons.healing_outlined,
                      title: t.applied_to_patient,
                      compact: compact,
                      children: [
                        DropdownButtonFormField<String>(
                          value: applied,
                          items: [
                            DropdownMenuItem(value: optYes, child: Text(optYes)),
                            DropdownMenuItem(value: optNo, child: Text(optNo)),
                          ],
                          onChanged: (v) => setState(() { applied = v ?? optNo; _dirty = true; }),
                          decoration: _dec(context, t.applied_to_patient, compact: compact),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: injury,
                          items: [
                            DropdownMenuItem(value: optYes, child: Text(optYes)),
                            DropdownMenuItem(value: optNo, child: Text(optNo)),
                          ],
                          onChanged: (v) => setState(() { injury = v ?? optNo; _dirty = true; }),
                          decoration: _dec(context, t.injury_question, compact: compact),
                        ),
                        if (needInjuryDesc) ...[
                          const SizedBox(height: 10),
                          TextField(controller: injuryDesc, maxLines: 3, decoration: _dec(context, t.injury_desc, compact: compact)),
                        ],
                      ],
                    ))),
                  );
                }

                sections.add(
                  (id: 'attachments', widget: _wizardAnchor('attachments', _section(
                    icon: Icons.photo_library_outlined,
                    title: t.attachments_title,
                    compact: compact,
                    children: [
                      OutlinedButton.icon(
                        onPressed: pickFiles,
                        icon: const Icon(Icons.upload),
                        label: Text(files.isEmpty ? t.add_attachment : t.images_selected(files.length)),
                      ),
                      if (files.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final entry in files.asMap().entries)
                              Chip(
                                label: Text(
                                  entry.value.name,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                avatar: const Icon(Icons.insert_drive_file_outlined),
                                deleteIcon: const Icon(Icons.close),
                                onDeleted: () => _removeAttachmentAt(entry.key),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ))),
                );

                sections.add(
                  (id: 'resolution', widget: _wizardAnchor('resolution', _section(
                    icon: Icons.local_shipping_outlined,
                    title: t.returned_question,
                    compact: compact,
                    children: [
                      DropdownButtonFormField<String>(
                        value: returned,
                        items: [
                          DropdownMenuItem(value: optReturnedYes, child: Text(optReturnedYes)),
                          DropdownMenuItem(value: optReturnedNo, child: Text(optReturnedNo)),
                        ],
                        onChanged: (v) => setState(() { returned = v ?? optReturnedNo; _dirty = true; }),
                        decoration: _dec(context, t.returned_question, compact: compact),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: handling,
                        items: [
                          DropdownMenuItem(value: optHandlingRep, child: Text(optHandlingRep)),
                          DropdownMenuItem(value: optHandlingCredit, child: Text(optHandlingCredit)),
                          DropdownMenuItem(value: optHandlingRework, child: Text(optHandlingRework)),
                        ],
                        onChanged: (v) => setState(() { handling = v ?? optHandlingRep; _dirty = true; }),
                        decoration: _dec(context, t.handling, compact: compact),
                      ),
                    ],
                  ))),
                );

                sections.add(
                  (id: 'privacy', widget: _wizardAnchor('privacy', _section(
                    icon: Icons.privacy_tip_outlined,
                    title: t.privacy_view,
                    compact: compact,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: privacy,
                            onChanged: (v) => setState(() { privacy = v ?? false; _dirty = true; }),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.privacy_agree),
                                const SizedBox(height: 4),
                                InkWell(
                                  onTap: () => Navigator.of(context).pushNamed('/legal/privacy'),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.privacy_tip_outlined, size: 18),
                                      const SizedBox(width: 6),
                                      Text(
                                        t.privacy_view,
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.primary,
                                          decoration: TextDecoration.underline,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ))),
                );

                final filtered = !widget.wizardMode || wizardSteps.isEmpty
                    ? sections
                    : sections.where((s) => s.id == wizardSteps[activeWizardIndex].id).toList();

                return Column(
                  children: [
                    for (final section in filtered) section.widget,
                    if (isWizardFinalStep)
                      _wizardReview(compact: compact, t: t),
                  ],
                );
              }),

              if (err != null) _banner(isError: true, text: err!),
              if (info != null) _banner(isError: false, text: info!),

              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 12,
                  children: [
                    OutlinedButton(onPressed: _handleCancel, child: Text(t.cancel)),
                    ElevatedButton.icon(
                      onPressed: busy || (widget.wizardMode && !isWizardFinalStep)
                          ? null
                          : () async {
                        setState(() { busy = true; err = null; info = null; });

                        // Validierung
                        if (!privacy) { setState(() { err = t.privacy_required; busy = false; }); return; }
                        if (article.text.trim().isEmpty || desc.text.trim().isEmpty) {
                          setState(() { err = t.required_fields; busy = false; }); return;
                        }
                        if (isDentist && batch.text.trim().isEmpty) {
                          setState(() { err = t.batch; busy = false; }); return;
                        }

                        // Payload
                        final payload = <String, dynamic>{
                          'segment': segment == optDentist ? 'Zahnmedizin': 'Dentallabor',
                          'article': article.text.trim(),
                          'batch': batch.text.trim(),
                          'qty': qty.text.trim(),
                          'expiry': expiry.text.trim(),
                          'desc': desc.text.trim(),
                          'applied': isDentist ? (applied == optYes ? 'Ja' : 'Nein') : '',
                          'injury': isDentist ? (injury == optYes ? 'Ja' : 'Nein') : '',
                          'injuryDesc': isDentist ? injuryDesc.text.trim() : '',
                          'returned': (returned == optReturnedYes ? 'Ja' : 'Nein'),
                          'handling': handling == optHandlingRep ? 'Ersatz' : (handling == optHandlingCredit ? 'Gutschrift' : 'Nacharbeit'),
                          'privacy': 'true',
                        };

                        try {
                          final res = await widget.api.complaintCreate(payload, files);
                          final ticket = (res?['ticket'] ?? '').toString();

                          if (ticket.isEmpty) {
                            setState(() { busy = false; err = t.send_failed; });
                          } else {
                            setState(() { busy = false; _dirty = false; info = null; });
                            await _showSummary(ticket, payload);
                          }
                        } catch (e) {
                          setState(() {
                            busy = false;
                            err = t.network_cors_error(e.toString());
                          });
                        }
                      },
                      icon: busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_outlined),
                      label: Text(t.send),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return WillPopScope(
      onWillPop: () async => _confirmLeaveIfDirty(),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(t.reportComplaint),
          leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: t.back, onPressed: _handleBack),
          actions: [ TextButton(onPressed: _handleCancel, child: Text(t.cancel)) ],
        ),
        body: body,
      ),
    );
  }

  Widget _buildHelpBox({required bool compact}) {
    final t = context.t;
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSecondaryContainer.withOpacity(0.92);
    final subtleBg = theme.colorScheme.secondaryContainer.withOpacity(0.55);

    return Card(
      color: subtleBg,
      margin: const EdgeInsets.symmetric(vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(compact ? 12 : 16)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, compact ? 10 : 12, 12, compact ? 12 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology_alt_outlined, color: theme.colorScheme.primary),
                SizedBox(width: compact ? 8 : 10),
                Expanded(
                  child: Text(
                    t.complaint_help_title,
                    style: TextStyle(fontWeight: FontWeight.w700, color: textColor, fontSize: compact ? 13.5 : 14),
                  ),
                ),
                IconButton(
                  tooltip: _helpCollapsed ? t.complaint_help_expand : t.complaint_help_collapse,
                  onPressed: _toggleHelpBox,
                  icon: Icon(_helpCollapsed ? Icons.expand_more : Icons.expand_less, color: textColor),
                ),
              ],
            ),
            if (!_helpCollapsed) ...[
              SizedBox(height: compact ? 4 : 6),
              Text(
                t.complaint_help_body,
                style: TextStyle(color: textColor, height: 1.35, fontSize: compact ? 12.5 : 13),
              ),
              SizedBox(height: compact ? 8 : 10),
              Wrap(
                spacing: compact ? 6 : 8,
                runSpacing: compact ? 4 : 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(Icons.auto_stories_outlined, size: 20, color: theme.colorScheme.primary),
                  Text(
                    t.complaint_help_hint,
                    style: TextStyle(color: textColor, fontSize: compact ? 12 : 12.5, height: 1.3),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: compact ? 7 : 8),
                      textStyle: TextStyle(fontSize: compact ? 12.5 : 13),
                    ),
                    onPressed: _openHelpLink,
                    icon: const Icon(Icons.library_books_outlined),
                    label: Text(t.complaint_help_link),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
