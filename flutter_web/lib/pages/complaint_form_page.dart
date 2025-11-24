// lib/pages/complaint_form_page.dart
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../data/knowledge_base_data.dart';
import '../models/complaint_attachment.dart';
import '../utils/attachment_preview.dart';
import '../utils/image_optimizer.dart';
import '../utils/upload_limits.dart';
import 'knowledge_base_page.dart';
import 'complaint_summary_page.dart';

// KEIN dart:html mehr nötig

extension _L10nX on BuildContext {
  AppLocalizations get t => AppLocalizations.of(this)!;
}

class _WizardStep {
  final String id;
  final IconData icon;
  final String title;
  final String hint;
  const _WizardStep({required this.id, required this.icon, required this.title, required this.hint});
}

enum _WizardDialogResult { previous, next, close }

class ComplaintFormPage extends StatefulWidget {
  final ApiClient api;
  final bool wizardMode;
  const ComplaintFormPage({super.key, required this.api, this.wizardMode = false});
  @override
  State<ComplaintFormPage> createState() => _ComplaintFormPageState();
}

class _ComplaintFormPageState extends State<ComplaintFormPage> {
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
  List<ComplaintFilePayload> files = [];

  final ScrollController _scrollCtrl = ScrollController();
  int _wizardStep = 0;
  final Set<String> _wizardVisited = {};
  final Map<String, GlobalKey> _sectionKeys = {
    'segment': GlobalKey(),
    'product': GlobalKey(),
    'patient': GlobalKey(),
    'attachments': GlobalKey(),
    'resolution': GlobalKey(),
    'privacy': GlobalKey(),
  };

  String? info;
  String? err;
  bool busy = false;

  Map<String, dynamic>? _account;
  bool _helpCollapsed = false;

  bool _dirty = false;
  final List<TextEditingController> _ctrls = [];
  KnowledgeItem? _autoHelpItem;

  void _markDirty() { if (!_dirty) setState(() => _dirty = true); }

  void _handleDescriptionChanged() {
    _markDirty();
    _updateAutoHelp();
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

  Widget _wizardAnchor(String id, Widget child) {
    return KeyedSubtree(key: _sectionKeys[id], child: child);
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

  @override
  void dispose() {
    for (final c in _ctrls) { c.removeListener(_markDirty); }
    desc.removeListener(_handleDescriptionChanged);
    _scrollCtrl.dispose();
    super.dispose();
  }

  int _estimateBase64(int byteLength) => estimateBase64Size(byteLength);

  Future<void> pickFiles() async {
    final t = context.t;
    final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (res == null || res.files.isEmpty) return;

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
        default:
          return 'application/octet-stream';
      }
    }

    final prepared = <ComplaintFilePayload>[];
    var totalBytes = 0;
    var totalPayload = 0;

    for (final f in res.files) {
      final data = f.bytes;
      if (data == null || data.isEmpty) continue;
      var name = f.name;
      var bytes = List<int>.from(data);
      var mime = _guessMime(name);

      if (kIsWeb) {
        final optimized = optimizeImageForUpload(bytes, mime, originalName: name);
        bytes = optimized.bytes;
        mime = optimized.mime;
        if ((optimized.suggestedName ?? '').isNotEmpty) {
          name = optimized.suggestedName!;
        }
        totalPayload += _estimateBase64(bytes.length);
        if (totalPayload > kWebUploadPayloadBudgetBytes) {
          setState(() {
            err = '${t.images_too_large} (Web-Limit 4MB)';
            info = null;
          });
          return;
        }
      } else {
        totalBytes += bytes.length;
        if (totalBytes > kMobileAttachmentLimitBytes) {
          setState(() {
            err = t.images_too_large;
            info = null;
          });
          return;
        }
      }

      final preview = createAttachmentPreview(bytes, mime);
      prepared.add((name: name, bytes: bytes, mime: mime, preview: preview));
    }

    if (prepared.isEmpty) return;

    setState(() {
      files = prepared;
      _dirty = true;
      err = null;
      info = null;
    });
  }

  Future<bool> _uploadAttachmentsAfterCreate(String ticket) async {
    if (!kIsWeb || files.isEmpty) return true;
    try {
      await sendInChunks(files, (chunk) async {
        await widget.api.complaintUploadFiles(ticket, chunk);
      });
      return true;
    } catch (_) {
      return false;
    }
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

  List<ComplaintAttachment> _currentAttachments() {
    return files
        .map((f) => ComplaintAttachment(
              name: f.name,
              bytes: Uint8List.fromList(f.bytes),
              mime: f.mime,
            ))
        .toList(growable: false);
  }

  Widget _buildAutoHelpCard() {
    final suggestion = _autoHelpItem;
    if (suggestion == null) return const SizedBox.shrink();

    final t = context.t;
    final theme = Theme.of(context);
    final answers = _splitAnswer(suggestion.answer(t));
    final preview = answers.isNotEmpty ? answers.first : null;

    return Card(
      color: theme.colorScheme.secondaryContainer.withOpacity(0.7),
      elevation: 0,
      margin: const EdgeInsets.only(top: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology_alt_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t.complaint_auto_help_title,
                    style: TextStyle(fontWeight: FontWeight.w700, color: theme.colorScheme.onSecondaryContainer),
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    knowledgeCategoryLabel(suggestion.category, t),
                    style: const TextStyle(fontSize: 12),
                  ),
                  avatar: Icon(Icons.folder_open, size: 18, color: theme.colorScheme.primary),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              t.complaint_auto_help_intro,
              style: TextStyle(color: theme.colorScheme.onSecondaryContainer.withOpacity(0.9)),
            ),
            const SizedBox(height: 8),
            Text(
              suggestion.question(t),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (preview != null) ...[
              const SizedBox(height: 6),
              Text(
                preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(height: 1.35),
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.comfortable),
                onPressed: () => _openSuggestedAnswer(suggestion),
                icon: const Icon(Icons.visibility_outlined),
                label: Text(t.complaint_auto_help_button),
              ),
            ),
          ],
        ),
      ),
    );
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
  InputDecoration _dec(BuildContext ctx, String label, {String? hint}) {
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  List<Widget> _segmentFields(AppLocalizations t) {
    final optDentist = t.segment_dentist, optLab = t.segment_lab;
    return [
      DropdownButtonFormField<String>(
        value: segment,
        items: [
          DropdownMenuItem(value: optDentist, child: Text(optDentist)),
          DropdownMenuItem(value: optLab, child: Text(optLab)),
        ],
        onChanged: (v) => setState(() {
          segment = v ?? optDentist;
          _dirty = true;
        }),
        decoration: _dec(context, t.segment),
      ),
    ];
  }

  List<Widget> _productFields(AppLocalizations t) {
    final isDentist = segment == t.segment_dentist;
    return [
      TextField(controller: article, decoration: _dec(context, t.article)),
      const SizedBox(height: 10),
      TextField(
        controller: batch,
        decoration: _dec(context, isDentist ? '${t.batch} *' : t.batch, hint: isDentist ? t.batch : null),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: TextField(controller: qty, decoration: _dec(context, t.qty))),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: expiry, decoration: _dec(context, t.expiry))),
      ]),
      const SizedBox(height: 10),
      TextField(
        controller: desc,
        maxLines: 4,
        decoration: _dec(context, t.problem_desc),
      ),
      const SizedBox(height: 4),
      _buildAutoHelpCard(),
    ];
  }

  List<Widget> _patientFields(AppLocalizations t) {
    final optYes = t.yes, optNo = t.no;
    final needInjuryDesc = applied == optYes && injury == optYes && segment == t.segment_dentist;
    if (segment != t.segment_dentist) return const [];

    return [
      DropdownButtonFormField<String>(
        value: applied,
        items: [
          DropdownMenuItem(value: optYes, child: Text(optYes)),
          DropdownMenuItem(value: optNo, child: Text(optNo)),
        ],
        onChanged: (v) => setState(() {
          applied = v ?? optNo;
          _dirty = true;
        }),
        decoration: _dec(context, t.applied_to_patient),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        value: injury,
        items: [
          DropdownMenuItem(value: optYes, child: Text(optYes)),
          DropdownMenuItem(value: optNo, child: Text(optNo)),
        ],
        onChanged: (v) => setState(() {
          injury = v ?? optNo;
          _dirty = true;
        }),
        decoration: _dec(context, t.injury_question),
      ),
      if (needInjuryDesc) ...[
        const SizedBox(height: 10),
        TextField(controller: injuryDesc, maxLines: 3, decoration: _dec(context, t.injury_desc)),
      ],
    ];
  }

  List<Widget> _attachmentFields(AppLocalizations t) {
    return [
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
            for (final f in files)
              InputChip(
                label: Text(
                  f.name,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                avatar: const Icon(Icons.insert_drive_file_outlined),
                onDeleted: () {
                  setState(() {
                    files = files.where((file) => file != f).toList();
                    _dirty = true;
                  });
                },
                deleteIcon: const Icon(Icons.close),
              ),
          ],
        ),
      ],
    ];
  }

  List<Widget> _resolutionFields(AppLocalizations t) {
    final optReturnedYes = t.yes, optReturnedNo = t.no;
    final optHandlingRep = t.handling_replacement, optHandlingCredit = t.handling_credit, optHandlingRework = t.handling_rework;

    return [
      DropdownButtonFormField<String>(
        value: returned,
        items: [
          DropdownMenuItem(value: optReturnedYes, child: Text(optReturnedYes)),
          DropdownMenuItem(value: optReturnedNo, child: Text(optReturnedNo)),
        ],
        onChanged: (v) => setState(() {
          returned = v ?? optReturnedNo;
          _dirty = true;
        }),
        decoration: _dec(context, t.returned_question),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        value: handling,
        items: [
          DropdownMenuItem(value: optHandlingRep, child: Text(optHandlingRep)),
          DropdownMenuItem(value: optHandlingCredit, child: Text(optHandlingCredit)),
          DropdownMenuItem(value: optHandlingRework, child: Text(optHandlingRework)),
        ],
        onChanged: (v) => setState(() {
          handling = v ?? optHandlingRep;
          _dirty = true;
        }),
        decoration: _dec(context, t.handling),
      ),
    ];
  }

  List<Widget> _privacyFields(AppLocalizations t) {
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: privacy,
            onChanged: (v) => setState(() {
              privacy = v ?? false;
              _dirty = true;
            }),
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
    ];
  }

  Widget _section({required IconData icon, required String title, required List<Widget> children}) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  List<Widget> _stepFieldsFor(String id, AppLocalizations t) {
    switch (id) {
      case 'segment':
        return _segmentFields(t);
      case 'product':
        return _productFields(t);
      case 'patient':
        return _patientFields(t);
      case 'attachments':
        return _attachmentFields(t);
      case 'resolution':
        return _resolutionFields(t);
      case 'privacy':
        return _privacyFields(t);
      default:
        return const [];
    }
  }

  bool _isStepComplete(String id, AppLocalizations t, {required bool isDentist, required bool needInjuryDesc}) {
    switch (id) {
      case 'segment':
        return segment.isNotEmpty;
      case 'product':
        final hasBasics = article.text.trim().isNotEmpty && desc.text.trim().isNotEmpty;
        return hasBasics && (!isDentist || batch.text.trim().isNotEmpty);
      case 'patient':
        if (!isDentist) return true;
        final hasBasics = applied.isNotEmpty && injury.isNotEmpty;
        return hasBasics && (!needInjuryDesc || injuryDesc.text.trim().isNotEmpty);
      case 'attachments':
        return files.isNotEmpty || _wizardVisited.contains('attachments');
      case 'resolution':
        return returned.isNotEmpty && handling.isNotEmpty;
      case 'privacy':
        return privacy;
      default:
        return false;
    }
  }

  Future<_WizardDialogResult?> _openWizardStepDialog(List<_WizardStep> steps, int index, AppLocalizations t) {
    final step = steps[index];
    _wizardVisited.add(step.id);
    final isFirst = index == 0;
    final isLast = index == steps.length - 1;

    return showDialog<_WizardDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820, minHeight: 420, maxHeight: 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(.12),
                        child: Icon(step.icon, color: Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${index + 1}/${steps.length} · ${step.title}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(step.hint, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: t.cancel,
                        onPressed: () => Navigator.of(ctx).pop(_WizardDialogResult.close),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(children: _stepFieldsFor(step.id, t)),
                          ),
                          if (step.id != 'privacy')
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                t.complaint_wizard_hint,
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: isFirst ? null : () => Navigator.of(ctx).pop(_WizardDialogResult.previous),
                        icon: const Icon(Icons.arrow_back),
                        label: Text(t.complaint_wizard_prev),
                      ),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(ctx).pop(
                          isLast ? _WizardDialogResult.close : _WizardDialogResult.next,
                        ),
                        icon: Icon(isLast ? Icons.check_circle_outline : Icons.arrow_forward),
                        label: Text(isLast ? t.complaint_wizard_done : t.complaint_wizard_next),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _runWizardFlow(List<_WizardStep> steps, int startIndex, AppLocalizations t) async {
    if (steps.isEmpty) return;
    var index = startIndex.clamp(0, steps.length - 1);

    while (mounted) {
      final action = await _openWizardStepDialog(steps, index, t);
      if (!mounted || action == null || action == _WizardDialogResult.close) break;

      if (action == _WizardDialogResult.next && index < steps.length - 1) {
        index++;
      } else if (action == _WizardDialogResult.previous && index > 0) {
        index--;
      } else {
        break;
      }
    }

    if (mounted) setState(() => _wizardStep = index);
  }

  Widget _wizardReview(AppLocalizations t) {
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
      margin: const EdgeInsets.only(top: 10),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                    Chip(label: Text('${entry.key}: ${entry.value}')),
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

  Widget _buildWizardCard({
    required List<_WizardStep> steps,
    required AppLocalizations t,
    required bool isDentist,
    required bool needInjuryDesc,
  }) {
    if (steps.isEmpty) return const SizedBox.shrink();

    final active = _wizardStep.clamp(0, steps.length - 1);
    if (active != _wizardStep) _wizardStep = active;
    final theme = Theme.of(context);
    final completed = steps.where((s) => _isStepComplete(s.id, t, isDentist: isDentist, needInjuryDesc: needInjuryDesc)).length;
    final progress = steps.isEmpty ? 0.0 : completed / steps.length;

    Widget stepTile(int index, _WizardStep step) {
      final done = _isStepComplete(step.id, t, isDentist: isDentist, needInjuryDesc: needInjuryDesc);
      return Card(
        elevation: 0,
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: ListTile(
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: done ? theme.colorScheme.primary.withOpacity(.16) : theme.colorScheme.surfaceTint.withOpacity(.12),
            child: Icon(done ? Icons.check_circle_outline : step.icon, color: done ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
          ),
          title: Text('${index + 1}. ${step.title}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(step.hint),
          trailing: Wrap(
            spacing: 8,
            children: [
              Chip(
                avatar: Icon(done ? Icons.auto_awesome : Icons.edit_outlined, size: 16, color: done ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
                label: Text(done ? t.complaint_wizard_done : t.complaint_wizard_next),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _runWizardFlow(steps, index, t),
                icon: const Icon(Icons.open_in_new),
                label: Text(done ? t.complaint_wizard_done : t.complaint_wizard_next),
              ),
            ],
          ),
          onTap: () => _runWizardFlow(steps, index, t),
        ),
      );
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: theme.colorScheme.primary.withOpacity(.12),
                  child: Icon(Icons.auto_fix_high_outlined, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.complaint_wizard_title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(t.complaint_wizard_subtitle, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _runWizardFlow(steps, active, t),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(t.complaint_wizard_next),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress, minHeight: 8, borderRadius: BorderRadius.circular(20)),
            const SizedBox(height: 8),
            Text('${completed}/${steps.length} ${t.complaint_wizard_step_finish}', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            ...List.generate(steps.length, (i) => stepTile(i, steps[i])),
            const SizedBox(height: 8),
            Text(t.complaint_wizard_hint, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
    final needInjuryDesc = isDentist && applied == optYes && injury == optYes;

    final wizardSteps = widget.wizardMode
        ? _buildWizardSteps(t, isDentist: isDentist)
        : const <_WizardStep>[];
    if (!isDentist) _wizardVisited.remove('patient');

    final body = SingleChildScrollView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Kopfinfo (rein visuell)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    children: [
                      const Icon(Icons.report_gmailerrorred_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t.reportComplaint,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (widget.wizardMode)
                _buildWizardCard(steps: wizardSteps, t: t, isDentist: isDentist, needInjuryDesc: needInjuryDesc),

              _buildHelpBox(),

              Builder(builder: (context) {
                final sections = <({String id, Widget widget})>[];

                sections.add(
                  (id: 'segment', widget: _wizardAnchor('segment', _section(
                    icon: Icons.person_outline,
                    title: t.segment,
                    children: _segmentFields(t),
                  ))),
                );

                sections.add(
                  (id: 'product', widget: _wizardAnchor('product', _section(
                    icon: Icons.build_outlined,
                    title: t.article,
                    children: _productFields(t),
                  ))),
                );

                if (isDentist) {
                  sections.add(
                    (id: 'patient', widget: _wizardAnchor('patient', _section(
                      icon: Icons.healing_outlined,
                      title: t.applied_to_patient,
                      children: _patientFields(t),
                    ))),
                  );
                }

                sections.add(
                  (id: 'attachments', widget: _wizardAnchor('attachments', _section(
                    icon: Icons.photo_library_outlined,
                    title: t.attachments_title,
                    children: _attachmentFields(t),
                  ))),
                );

                sections.add(
                  (id: 'resolution', widget: _wizardAnchor('resolution', _section(
                    icon: Icons.local_shipping_outlined,
                    title: t.returned_question,
                    children: _resolutionFields(t),
                  ))),
                );

                sections.add(
                  (id: 'privacy', widget: _wizardAnchor('privacy', _section(
                    icon: Icons.privacy_tip_outlined,
                    title: t.privacy_view,
                    children: _privacyFields(t),
                  ))),
                );

                return Column(
                  children: [
                    for (final section in sections) section.widget,
                    if (widget.wizardMode) _wizardReview(t),
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
                      onPressed: busy
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
                          final initialFiles = kIsWeb ? const <ComplaintFilePayload>[] : files;
                          final res = await widget.api.complaintCreate(payload, initialFiles);
                          final ticket = (res?['ticket'] ?? '').toString();

                          if (ticket.isEmpty) {
                            setState(() { busy = false; err = t.send_failed; });
                          } else {
                            if (kIsWeb && files.isNotEmpty) {
                              final uploadsOk = await _uploadAttachmentsAfterCreate(ticket);
                              if (!uploadsOk && mounted) {
                                final message = '${t.attachments_error} ${t.attachments_add}.';
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(content: Text(message)));
                              }
                            }

                            if (!mounted) return;
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

  Widget _buildHelpBox() {
    final t = context.t;
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSecondaryContainer.withOpacity(0.92);
    final subtleBg = theme.colorScheme.secondaryContainer.withOpacity(0.55);

    return Card(
      color: subtleBg,
      margin: const EdgeInsets.symmetric(vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology_alt_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t.complaint_help_title,
                    style: TextStyle(fontWeight: FontWeight.w700, color: textColor),
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
              const SizedBox(height: 6),
              Text(
                t.complaint_help_body,
                style: TextStyle(color: textColor, height: 1.35),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(Icons.auto_stories_outlined, size: 20, color: theme.colorScheme.primary),
                  Text(
                    t.complaint_help_hint,
                    style: TextStyle(color: textColor, fontSize: 12.5, height: 1.3),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
