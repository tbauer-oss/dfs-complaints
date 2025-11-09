// lib/pages/complaint_form_page.dart
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';

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
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                value: segment,
                items: [
                  DropdownMenuItem(value: optDentist, child: Text(optDentist)),
                  DropdownMenuItem(value: optLab, child: Text(optLab)),
                ],
                onChanged: (v) => setState(() { segment = v ?? optDentist; _dirty = true; } ),
                decoration: InputDecoration(labelText: t.segment),
              ),
              const SizedBox(height: 8),

              TextField(controller: article, decoration: InputDecoration(labelText: t.article, border: const OutlineInputBorder())),
              const SizedBox(height: 8),

              // Sternchen nur bei Zahnarzt
              TextField(
                controller: batch,
                decoration: InputDecoration(labelText: isDentist ? '${t.batch} *' : t.batch, border: const OutlineInputBorder())),
              const SizedBox(height: 8),

              Row(children: [
                Expanded(child: TextField(controller: qty, decoration: InputDecoration(labelText: t.qty, border: const OutlineInputBorder()))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: expiry, decoration: InputDecoration(labelText: t.expiry, border: const OutlineInputBorder()))),
              ]),
              const SizedBox(height: 8),

              TextField(controller: desc, maxLines: 4, decoration: InputDecoration(labelText: t.problem_desc, border: const OutlineInputBorder())),

              if (isDentist) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: applied,
                  items: [
                    DropdownMenuItem(value: optYes, child: Text(optYes)),
                    DropdownMenuItem(value: optNo, child: Text(optNo)),
                  ],
                  onChanged: (v) => setState(() { applied = v ?? optNo; _dirty = true; } ),
                  decoration: InputDecoration(labelText: t.applied_to_patient),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: injury,
                  items: [
                    DropdownMenuItem(value: optYes, child: Text(optYes)),
                    DropdownMenuItem(value: optNo, child: Text(optNo)),
                  ],
                  onChanged: (v) => setState(() { injury = v ?? optNo; _dirty = true; } ),
                  decoration: InputDecoration(labelText: t.injury_question),
                ),
                if (needInjuryDesc) ...[
                  const SizedBox(height: 8),
                  TextField(controller: injuryDesc, maxLines: 3, decoration: InputDecoration(labelText: t.injury_desc, border: const OutlineInputBorder())),
                ]
              ],

              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: pickFiles,
                icon: const Icon(Icons.upload),
                label: Text(files.isEmpty ? t.add_images : t.images_selected(files.length)),
              ),

              const Divider(height: 24),

              DropdownButtonFormField<String>(
                value: returned,
                items: [
                  DropdownMenuItem(value: optReturnedYes, child: Text(optReturnedYes)),
                  DropdownMenuItem(value: optReturnedNo, child: Text(optReturnedNo)),
                ],
                onChanged: (v) => setState(() { returned = v ?? optReturnedNo; _dirty = true; } ),
                decoration: InputDecoration(labelText: t.returned_question),
              ),
              const SizedBox(height: 8),

              DropdownButtonFormField<String>(
                value: handling,
                items: [
                  DropdownMenuItem(value: optHandlingRep, child: Text(optHandlingRep)),
                  DropdownMenuItem(value: optHandlingCredit, child: Text(optHandlingCredit)),
                  DropdownMenuItem(value: optHandlingRework, child: Text(optHandlingRework)),
                ],
                onChanged: (v) => setState(() { handling = v ?? optHandlingRep; _dirty = true; } ),
                decoration: InputDecoration(labelText: t.handling),
              ),

              const SizedBox(height: 8),
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
                        // Pflichttext – identisch zur Register-Seite
                        Text(t.privacy_agree),

                        // Interner Link zur LegalPrivacyPage (gleiches Icon & Style)
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

              if (err != null) Text(err!, style: const TextStyle(color: Colors.red)),
              if (info != null) Text(info!, style: const TextStyle(color: Colors.green)),

              const SizedBox(height: 12),
              Row(children: [
                ElevatedButton(
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
                        setState(() { busy = false; info = t.sent_ticket(ticket); _dirty = false; });
                      }
                    } catch (e) {
                      setState(() {
                        busy = false;
                        err = t.network_cors_error(e.toString());
                      });
                    }
                  },
                  child: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(t.send),
                ),
                const SizedBox(width: 12),
                OutlinedButton(onPressed: _handleCancel, child: Text(t.cancel)),
              ]),
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
        bottomNavigationBar: LegalFooter(api: widget.api),
      ),
    );
  }
}
