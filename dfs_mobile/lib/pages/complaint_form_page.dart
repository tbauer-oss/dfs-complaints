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
  final ValueNotifier<bool> _busyNotifier = ValueNotifier(false);

  Map<String, dynamic>? _account;
  bool _helpCollapsed = true;

  bool _dirty = false;
  final List<TextEditingController> _ctrls = [];
  KnowledgeItem? _autoHelpItem;
  final ScrollController _scrollCtrl = ScrollController();
  int _wizardStep = 0;
  bool _wizardOpened = false;
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
    _busyNotifier.dispose();
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
      _WizardStep(
        id: 'intro',
        icon: Icons.celebration_outlined,
        title: t.complaint_wizard_title,
        hint: t.complaint_wizard_subtitle,
      ),
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

  Future<void> _showAttachment(({String name, List<int> bytes, String mime, String? preview}) file) async {
    final isImage = file.mime.toLowerCase().startsWith('image/');
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(file.name, overflow: TextOverflow.ellipsis),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
          child: isImage
              ? InteractiveViewer(
                  child: Image.memory(
                    Uint8List.fromList(file.bytes),
                    fit: BoxFit.contain,
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.insert_drive_file_outlined, size: 48),
                    const SizedBox(height: 12),
                    Text(file.mime, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(context.t.attachments_file_unknown, textAlign: TextAlign.center),
                  ],
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.t.close)),
        ],
      ),
    );
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
      if (!mounted) return;
      setState(() => _helpCollapsed = true);
      await prefs.setBool(_helpPrefKey, true);
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

  Future<void> _submitComplaint({VoidCallback? onSuccess}) async {
    final t = context.t;
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

    setState(() { busy = true; err = null; info = null; });
    _busyNotifier.value = true;

    if (!privacy) { setState(() { err = t.privacy_required; busy = false; }); _busyNotifier.value = false; return; }
    if (article.text.trim().isEmpty || desc.text.trim().isEmpty) {
      setState(() { err = t.required_fields; busy = false; }); _busyNotifier.value = false; return;
    }
    if (isDentist && batch.text.trim().isEmpty) {
      setState(() { err = t.batch; busy = false; }); _busyNotifier.value = false; return;
    }

    final payload = <String, dynamic>{
      'segment': segment == optDentist ? 'Zahnmedizin' : 'Dentallabor',
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
        _busyNotifier.value = false;
      } else {
        setState(() { busy = false; _dirty = false; info = null; });
        _busyNotifier.value = false;
        onSuccess?.call();
        await _showSummary(ticket, payload);
      }
    } catch (e) {
      setState(() {
        busy = false;
        err = t.network_cors_error(e.toString());
      });
      _busyNotifier.value = false;
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

  List<({String id, Widget widget})> _buildSections({
    required bool compact,
    required AppLocalizations t,
    required bool isDentist,
    required bool needInjuryDesc,
    required bool anchored,
    required String optDentist,
    required String optLab,
    required String optYes,
    required String optNo,
    required String optReturnedYes,
    required String optReturnedNo,
    required String optHandlingRep,
    required String optHandlingCredit,
    required String optHandlingRework,
  }) {
    Widget wrap(String id, Widget child) => anchored ? _wizardAnchor(id, child) : child;

    final sections = <({String id, Widget widget})>[];

    sections.add(
      (id: 'segment', widget: wrap('segment', _section(
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
      (id: 'product', widget: wrap('product', _section(
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
        (id: 'patient', widget: wrap('patient', _section(
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
      (id: 'attachments', widget: wrap('attachments', _section(
        icon: Icons.photo_library_outlined,
        title: t.attachments_title,
        compact: compact,
        children: [
          Text(t.attachments_too_large),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < files.length; i++) ...[
                Material(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _showAttachment(files[i]),
                    child: Container(
                      width: 140,
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.insert_drive_file_outlined),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(files[i].name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                              IconButton(onPressed: () => _removeAttachmentAt(i), icon: const Icon(Icons.close, size: 18)),
                            ],
                          ),
                          if (files[i].preview != null) ...[
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(Uint8List.fromList(files[i].bytes), height: 70, width: double.infinity, fit: BoxFit.cover),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              FilledButton.icon(
                onPressed: pickFiles,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(t.add_attachment),
              ),
            ],
          ),
        ],
      ))),
    );

    sections.add(
      (id: 'resolution', widget: wrap('resolution', _section(
        icon: Icons.handshake_outlined,
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
      (id: 'privacy', widget: wrap('privacy', _section(
        icon: Icons.privacy_tip_outlined,
        title: t.privacy_view,
        compact: compact,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(value: privacy, onChanged: (v) => setState(() { privacy = v ?? false; _dirty = true; })),
              const SizedBox(width: 8),
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

    return sections;
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

  Widget _buildWizardCard({
    required List<_WizardStep> steps,
    required AppLocalizations t,
    required bool compact,
    required VoidCallback onOpenWizard,
  }) {
    if (steps.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final realSteps = steps.where((s) => s.id != 'intro').toList(growable: false);

    return Card(
      elevation: 0,
      margin: EdgeInsets.symmetric(vertical: compact ? 8 : 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(compact ? 12 : 16)),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 12 : 14, compact ? 12 : 14, compact ? 12 : 14, compact ? 12 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: 0, minHeight: compact ? 6 : 8),
            ),
            const SizedBox(height: 10),
            Text(
              t.complaint_wizard_hint,
              style: TextStyle(fontSize: compact ? 12 : 12.5, color: theme.colorScheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final step in realSteps)
                  Chip(
                    avatar: Icon(step.icon, size: 18),
                    label: Text(step.title),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onOpenWizard,
                icon: const Icon(Icons.play_circle_outline),
                label: Text(t.complaintWizardTile),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWizardLaunchButton({
    required bool compact,
    required AppLocalizations t,
    required VoidCallback onTap,
  }) {
    final radius = BorderRadius.circular(compact ? 14 : 16);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: EdgeInsets.only(top: compact ? 8 : 12, bottom: compact ? 2 : 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF9D4EDD), Color(0xFFB388FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.18),
            blurRadius: 12,
            offset: const Offset(-4, -4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 420;

              Widget buildCta({required bool fullWidth}) {
                final button = DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 12 : 14,
                      vertical: compact ? 8 : 10,
                    ),
                    child: Row(
                      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                        SizedBox(width: 6),
                        Text(
                          t.complaint_assist,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                );

                return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
              }

              return Stack(
                children: [
                  Positioned(
                    right: -30,
                    top: -30,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 420),
                      width: compact ? 140 : 160,
                      height: compact ? 140 : 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Colors.white.withOpacity(0.22), Colors.white.withOpacity(0.01)],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: -40,
                    bottom: -40,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 420),
                      width: compact ? 160 : 190,
                      height: compact ? 160 : 190,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Colors.white.withOpacity(0.16), Colors.white.withOpacity(0.0)],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(0.22),
                              Colors.white.withOpacity(0.05),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            stops: const [0.0, 0.55],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 14 : 18,
                      vertical: compact ? 14 : 18,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.18),
                                    blurRadius: 10,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 26),
                            ),
                            SizedBox(width: compact ? 12 : 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.complaintWizardTile,
                                    style: textTheme.titleMedium?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.1,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    t.complaint_wizard_hint,
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: Colors.white.withOpacity(0.92),
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isNarrow) ...[
                              SizedBox(width: compact ? 10 : 14),
                              buildCta(fullWidth: false),
                            ],
                          ],
                        ),
                        if (isNarrow) ...[
                          const SizedBox(height: 14),
                          buildCta(fullWidth: true),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openWizardFlow({
    required List<_WizardStep> steps,
    required AppLocalizations t,
    required List<({String id, Widget widget})> sections,
  }) async {
    if (steps.isEmpty) return;

    final sectionLookup = {for (final entry in sections) entry.id: entry.widget};

    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ComplaintWizardOverlay(
          steps: steps,
          sectionLookup: sectionLookup,
          review: null,
          busyListenable: _busyNotifier,
          onSubmit: () => _submitComplaint(onSuccess: () => Navigator.of(context).pop()),
          t: t,
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

    final wizardSteps = _buildWizardSteps(t, isDentist: isDentist);

    final sections = _buildSections(
      compact: compact,
      t: t,
      isDentist: isDentist,
      needInjuryDesc: needInjuryDesc,
      anchored: true,
      optDentist: optDentist,
      optLab: optLab,
      optYes: optYes,
      optNo: optNo,
      optReturnedYes: optReturnedYes,
      optReturnedNo: optReturnedNo,
      optHandlingRep: optHandlingRep,
      optHandlingCredit: optHandlingCredit,
      optHandlingRework: optHandlingRework,
    );

    final wizardSections = _buildSections(
      compact: compact,
      t: t,
      isDentist: isDentist,
      needInjuryDesc: needInjuryDesc,
      anchored: false,
      optDentist: optDentist,
      optLab: optLab,
      optYes: optYes,
      optNo: optNo,
      optReturnedYes: optReturnedYes,
      optReturnedNo: optReturnedNo,
      optHandlingRep: optHandlingRep,
      optHandlingCredit: optHandlingCredit,
      optHandlingRework: optHandlingRework,
    );

    if (widget.wizardMode && !_wizardOpened && wizardSteps.isNotEmpty) {
      _wizardOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openWizardFlow(steps: wizardSteps, t: t, sections: wizardSections);
      });
    }

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
                _buildWizardCard(
                  steps: wizardSteps,
                  t: t,
                  compact: compact,
                  onOpenWizard: () => _openWizardFlow(steps: wizardSteps, t: t, sections: wizardSections),
                ),

              if (wizardSteps.isNotEmpty)
                _buildWizardLaunchButton(
                  compact: compact,
                  t: t,
                  onTap: () => _openWizardFlow(steps: wizardSteps, t: t, sections: wizardSections),
                ),

              _buildHelpBox(compact: compact),

              Column(
                children: [
                  for (final section in sections) section.widget,
                ],
              ),

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
                      onPressed: busy ? null : () => _submitComplaint(),
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

class _ComplaintWizardOverlay extends StatefulWidget {
  final List<_WizardStep> steps;
  final Map<String, Widget> sectionLookup;
  final Widget? review;
  final ValueListenable<bool> busyListenable;
  final Future<void> Function() onSubmit;
  final AppLocalizations t;
  const _ComplaintWizardOverlay({
    required this.steps,
    required this.sectionLookup,
    this.review,
    required this.busyListenable,
    required this.onSubmit,
    required this.t,
    super.key,
  });

  @override
  State<_ComplaintWizardOverlay> createState() => _ComplaintWizardOverlayState();
}

class _ComplaintWizardOverlayState extends State<_ComplaintWizardOverlay> {
  late final PageController _pageCtrl;
  int _active = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    final next = index.clamp(0, widget.steps.length - 1);
    setState(() => _active = next);
    _pageCtrl.animateToPage(next, duration: const Duration(milliseconds: 240), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final theme = Theme.of(context);
    final step = widget.steps[_active];
    final totalWithoutIntro = (widget.steps.length - 1).clamp(0, widget.steps.length - 1);
    final completed = _active.clamp(0, totalWithoutIntro);
    final progress = totalWithoutIntro == 0 ? 0.0 : completed / totalWithoutIntro;
    final isIntro = step.id == 'intro';
    final isLast = _active == widget.steps.length - 1;

    Widget buildPage(_WizardStep s) {
      if (s.id == 'intro') {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.emoji_objects_outlined, size: 72, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  t.complaintWizardTile,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  t.complaint_wizard_subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant, height: 1.35),
                ),
                const SizedBox(height: 14),
                Text(
                  t.complaint_wizard_hint,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant, height: 1.35),
                ),
              ],
            ),
          ),
        );
      }

      final content = widget.sectionLookup[s.id];
      final children = <Widget>[if (content != null) content];
      if (s.id == 'privacy' && widget.review != null) {
        children.addAll([const SizedBox(height: 12), widget.review!]);
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(children: children),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: t.back, onPressed: () => Navigator.of(context).pop()),
        title: Text(t.complaintWizardTile),
        actions: [IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close))],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('$completed/$totalWithoutIntro', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Icon(step.icon, size: 18, color: theme.colorScheme.primary),
                        Text(step.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (step.hint.isNotEmpty)
                          Text(
                            step.hint,
                            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _active = i),
                children: [for (final s in widget.steps) buildPage(s)],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
              child: ValueListenableBuilder<bool>(
                valueListenable: widget.busyListenable,
                builder: (_, busy, __) {
                  final primaryLabel = isLast ? t.send : (isIntro ? t.complaint_wizard_next : t.complaint_wizard_next);
                  return Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: (busy || isIntro || _active == 0) ? null : () => _goTo(_active - 1),
                        icon: const Icon(Icons.chevron_left),
                        label: Text(t.complaint_wizard_prev),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: busy
                              ? null
                              : (isLast
                                  ? widget.onSubmit
                                  : () => _goTo(_active + 1)),
                          icon: busy
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : Icon(isLast ? Icons.send_outlined : Icons.navigate_next),
                          label: Text(primaryLabel),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
