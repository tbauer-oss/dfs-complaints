// lib/pages/complaint_form_page.dart
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/client.dart';
import '../l10n/app_localizations.dart';
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

class ComplaintFormPage extends StatefulWidget {
  final ApiClient api;
  const ComplaintFormPage({super.key, required this.api});
  @override
  State<ComplaintFormPage> createState() => _ComplaintFormPageState();
}

class _ComplaintFormPageState extends State<ComplaintFormPage> {
  static const _helpPrefKey = 'dfs_complaint_help_collapsed';
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

  String? info;
  String? err;
  bool busy = false;

  Map<String, dynamic>? _account;
  bool _helpCollapsed = false;

  bool _dirty = false;
  final List<TextEditingController> _ctrls = [];

  void _markDirty() { if (!_dirty) setState(() => _dirty = true); }

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
    _ctrls.addAll([article, batch, qty, expiry, desc, injuryDesc]);
    for (final c in _ctrls) { c.addListener(_markDirty); }
    _loadAccount();
    _loadHelpPref();
  }

  @override
  void dispose() {
    for (final c in _ctrls) { c.removeListener(_markDirty); }
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
      builder: (_) => const KnowledgeBasePage(),
    ));
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

    final body = SingleChildScrollView(
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

              _buildHelpBox(),

              // Sektion: Allgemein
              _section(
                icon: Icons.person_outline,
                title: t.segment,
                children: [
                  DropdownButtonFormField<String>(
                    value: segment,
                    items: [
                      DropdownMenuItem(value: optDentist, child: Text(optDentist)),
                      DropdownMenuItem(value: optLab, child: Text(optLab)),
                    ],
                    onChanged: (v) => setState(() { segment = v ?? optDentist; _dirty = true; } ),
                    decoration: _dec(context, t.segment),
                  ),
                ],
              ),

              // Sektion: Produktdetails
              _section(
                icon: Icons.build_outlined,
                title: t.article,
                children: [
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
                ],
              ),

              // Sektion: Patientenbezug (nur Zahnarzt)
              if (isDentist)
                _section(
                  icon: Icons.healing_outlined,
                  title: t.applied_to_patient,
                  children: [
                    DropdownButtonFormField<String>(
                      value: applied,
                      items: [
                        DropdownMenuItem(value: optYes, child: Text(optYes)),
                        DropdownMenuItem(value: optNo, child: Text(optNo)),
                      ],
                      onChanged: (v) => setState(() { applied = v ?? optNo; _dirty = true; } ),
                      decoration: _dec(context, t.applied_to_patient),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: injury,
                      items: [
                        DropdownMenuItem(value: optYes, child: Text(optYes)),
                        DropdownMenuItem(value: optNo, child: Text(optNo)),
                      ],
                      onChanged: (v) => setState(() { injury = v ?? optNo; _dirty = true; } ),
                      decoration: _dec(context, t.injury_question),
                    ),
                    if (needInjuryDesc) ...[
                      const SizedBox(height: 10),
                      TextField(controller: injuryDesc, maxLines: 3, decoration: _dec(context, t.injury_desc)),
                    ],
                  ],
                ),

              // Sektion: Bilder / Anhänge
              _section(
                icon: Icons.photo_library_outlined,
                title: t.attachments_title,
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
                ],
              ),

              // Sektion: Rücksendung & Wunsch
              _section(
                icon: Icons.local_shipping_outlined,
                title: t.returned_question,
                children: [
                  DropdownButtonFormField<String>(
                    value: returned,
                    items: [
                      DropdownMenuItem(value: optReturnedYes, child: Text(optReturnedYes)),
                      DropdownMenuItem(value: optReturnedNo, child: Text(optReturnedNo)),
                    ],
                    onChanged: (v) => setState(() { returned = v ?? optReturnedNo; _dirty = true; } ),
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
                    onChanged: (v) => setState(() { handling = v ?? optHandlingRep; _dirty = true; } ),
                    decoration: _dec(context, t.handling),
                  ),
                ],
              ),

              // Sektion: Datenschutz
              _section(
                icon: Icons.privacy_tip_outlined,
                title: t.privacy_view,
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
                      onPressed: busy ? null : () async {
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
