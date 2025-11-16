// lib/pages/complaint_form_page.dart
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../models/complaint_attachment.dart';
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
  String segment = 'Zahnarzt';
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
  List<({String name, List<int> bytes, String mime})> files = [];

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

  Future<void> pickFiles() async {
    final t = context.t;
    final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (res == null) return;

    final sum = res.files.fold<int>(0, (s, f) => s + (f.bytes?.length ?? 0));
    if (sum > 8 * 1024 * 1024) { setState(() => err = t.images_too_large); return; }

    String _guessMime(String name) {
      final ext = name.split('.').last.toLowerCase();
      switch (ext) {
        case 'jpg':
        case 'jpeg': return 'image/jpeg';
        case 'png': return 'image/png';
        case 'gif': return 'image/gif';
        case 'webp': return 'image/webp';
        default: return 'application/octet-stream';
      }
    }

    setState(() {
      files = res.files.map((f) {
        final name = f.name;
        final bytes = List<int>.from(f.bytes ?? const []);
        final mime = _guessMime(name);
        return (name: name, bytes: bytes, mime: mime); // Record, kein Map!
      }).toList();
      _dirty = true;
    });
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

  Future<void> _openHelpLink() async {
    final raw = context.t.complaint_help_url;
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.t.complaint_help_error)));
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.t.complaint_help_error)));
    }
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
                title: t.add_images,
                children: [
                  OutlinedButton.icon(
                    onPressed: pickFiles,
                    icon: const Icon(Icons.upload),
                    label: Text(files.isEmpty ? t.add_images : t.images_selected(files.length)),
                  ),
                  if (files.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final f in files)
                          Chip(
                            label: Text(
                              f.name,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            avatar: const Icon(Icons.insert_drive_file_outlined),
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
                          'segment': segment == optDentist ? 'Zahnarzt' : 'Zahntechnik',
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

  Widget _buildHelpBox() {
    final t = context.t;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    t.complaint_help_title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: _helpCollapsed ? t.complaint_help_expand : t.complaint_help_collapse,
                  onPressed: _toggleHelpBox,
                  icon: Icon(_helpCollapsed ? Icons.expand_more : Icons.expand_less),
                ),
              ],
            ),
            if (!_helpCollapsed) ...[
              const SizedBox(height: 8),
              Text(t.complaint_help_body),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _openHelpLink,
                icon: const Icon(Icons.open_in_new),
                label: Text(t.complaint_help_link),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
