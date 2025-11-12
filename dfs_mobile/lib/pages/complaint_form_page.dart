// lib/pages/complaint_form_page.dart
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../widgets/dialog_content_scroll.dart';

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

class _ComplaintFormPageState extends State<ComplaintFormPage> with TickerProviderStateMixin {
  // --- State ---
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

  // --- Branding / Layout ---
  Color get _brand => Theme.of(context).colorScheme.primary; // DFS-Blau aus Theme
  final _radius = 16.0;

  void _markDirty() { if (!_dirty) setState(() => _dirty = true); }

  // ---------- Leave Protection ----------
  Future<bool> _confirmLeaveIfDirty() async {
    if (!_dirty) return true;
    final t = context.t;
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text(t.unsavedChangesTitle),
        content: DialogContentScroll(child: Text(t.unsavedChangesText)),
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

  // ---------- Files ----------
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
        return (name: name, bytes: bytes, mime: mime);
      }).toList();
      _dirty = true;
    });
  }

  // ---------- Flow Helpers ----------
  void _resetForm() {
    final t = context.t;
    final optDentist = t.segment_dentist;
    final optNo = t.no;
    final optReturnedNo = t.no;
    final optHandlingRep = t.handling_replacement;

    setState(() {
      segment = optDentist;
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

  Future<void> _navigateToDashboard() async {
    if (!mounted) return;
    try {
      Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (r) => false);
    } catch (_) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Future<bool> _askAddAnother(String ticket) async {
    final t = context.t;
    final theme = Theme.of(context);
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text(t.addAnother_title),
        content: DialogContentScroll(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(alignment: Alignment.centerLeft, child: Text(t.addAnother_body)),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.confirmation_number_outlined, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      t.sent_ticket(ticket),
                      style: theme.textTheme.bodyMedium,
                      softWrap: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.addAnother_no)),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: Text(t.addAnother_yes)),
        ],
      ),
    ).then((v) => v ?? false);
  }

  // ---------- UI Helpers ----------
  InputDecoration _dec(BuildContext ctx, String label, {String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      isDense: true,
      prefixIcon: icon != null ? Icon(icon) : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(ctx).colorScheme.outlineVariant),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _sectionTitle(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required IconData icon, required String title, List<Widget> children = const []}) {
    return Card(
      elevation: 1.5,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(icon, title),
            Divider(height: 16, thickness: .8, color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 8),
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
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(.25)),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _header() {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_brand, _brand.withOpacity(.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: cs.onPrimary.withOpacity(.15),
              child: Icon(Icons.medical_services_outlined, color: cs.onPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.reportComplaint,
                      style: TextStyle(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      )),
                  const SizedBox(height: 4),
                  Text(
                    t.privacy_agree, // kurzer seriöser Sub-Text (bestehender String)
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onPrimary.withOpacity(.9)),
                  ),
                ],
              ),
            ),
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

    final body = SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header (Gradient)
                _header(),

                // Sektion: Allgemein
                _sectionCard(
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
                      decoration: _dec(context, t.segment, icon: Icons.apartment_outlined),
                    ),
                  ],
                ),

                // Sektion: Produktdetails
                _sectionCard(
                  icon: Icons.build_outlined,
                  title: t.article,
                  children: [
                    TextField(controller: article, decoration: _dec(context, t.article, icon: Icons.inventory_2_outlined)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: batch,
                      decoration: _dec(context, isDentist ? '${t.batch} *' : t.batch, hint: isDentist ? t.batch : null, icon: Icons.qr_code_2_outlined),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: TextField(controller: qty, decoration: _dec(context, t.qty, icon: Icons.format_list_numbered))),
                      const SizedBox(width: 10),
                      Expanded(child: TextField(controller: expiry, decoration: _dec(context, t.expiry, icon: Icons.event_outlined))),
                    ]),
                    const SizedBox(height: 10),
                    TextField(
                      controller: desc,
                      maxLines: 4,
                      decoration: _dec(context, t.problem_desc, icon: Icons.description_outlined),
                    ),
                  ],
                ),

                // Sektion: Patientenbezug (nur Zahnarzt)
                if (isDentist)
                  _sectionCard(
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
                        decoration: _dec(context, t.applied_to_patient, icon: Icons.account_circle_outlined),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: injury,
                        items: [
                          DropdownMenuItem(value: optYes, child: Text(optYes)),
                          DropdownMenuItem(value: optNo, child: Text(optNo)),
                        ],
                        onChanged: (v) => setState(() { injury = v ?? optNo; _dirty = true; } ),
                        decoration: _dec(context, t.injury_question, icon: Icons.warning_amber_rounded),
                      ),
                      if (needInjuryDesc) ...[
                        const SizedBox(height: 10),
                        TextField(controller: injuryDesc, maxLines: 3, decoration: _dec(context, t.injury_desc, icon: Icons.notes_outlined)),
                      ],
                    ],
                  ),

                // Sektion: Bilder / Anhänge
                _sectionCard(
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
                              label: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 220),
                                child: Text(f.name, overflow: TextOverflow.ellipsis, maxLines: 1),
                              ),
                              avatar: const Icon(Icons.insert_drive_file_outlined),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),

                // Sektion: Rücksendung & Wunsch
                _sectionCard(
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
                      decoration: _dec(context, t.returned_question, icon: Icons.local_shipping_outlined),
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
                      decoration: _dec(context, t.handling, icon: Icons.handshake_outlined),
                    ),
                  ],
                ),

                // Sektion: Datenschutz
                _sectionCard(
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
                                  children: [
                                    const Icon(Icons.privacy_tip_outlined, size: 18),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        t.privacy_view,
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.primary,
                                          decoration: TextDecoration.underline,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        softWrap: true,
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
                    runSpacing: 8,
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
                          final isDentistLocal = segment == optDentist;
                          if (isDentistLocal && batch.text.trim().isEmpty) {
                            setState(() { err = t.batch; busy = false; }); return;
                          }

                          // Payload
                          final payload = <String, dynamic>{
                            'segment': isDentistLocal ? 'Zahnarzt' : 'Zahntechnik',
                            'article': article.text.trim(),
                            'batch': batch.text.trim(),
                            'qty': qty.text.trim(),
                            'expiry': expiry.text.trim(),
                            'desc': desc.text.trim(),
                            'applied': isDentistLocal ? (applied == optYes ? 'Ja' : 'Nein') : '',
                            'injury': isDentistLocal ? (injury == optYes ? 'Ja' : 'Nein') : '',
                            'injuryDesc': isDentistLocal ? injuryDesc.text.trim() : '',
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
                              final again = await _askAddAnother(ticket);
                              if (!mounted) return;
                              if (again) {
                                _resetForm();
                              } else {
                                await _navigateToDashboard();
                              }
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
}
