import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';

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
  List<({String name, List<int> bytes, String mime})> files = [];
  String? info;
  String? err;
  bool busy = false;

  Future<void> pickFiles(AppLocalizations t) async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (res == null) return;

    final sum = res.files.fold<int>(0, (s, f) => s + (f.bytes?.length ?? 0));
    if (sum > 8 * 1024 * 1024) {
      setState(() => err = t.images_too_large);
      return;
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
        default:
          return 'application/octet-stream';
      }
    }

    setState(() {
      files = res.files.map((f) {
        final name = f.name;
        final bytes = List<int>.from(f.bytes ?? const []);
        final mime = _guessMime(name);
        return (name: name, bytes: bytes, mime: mime);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isDentist = segment == t.segment_dentist;
    final needInjuryDesc = isDentist && applied == t.yes && injury == t.yes;

    // Lokalisierte Texte
    final optDentist = t.segment_dentist;
    final optLab = t.segment_lab;
    final optYes = t.yes;
    final optNo = t.no;
    final optReturnedYes = t.yes;
    final optReturnedNo = t.no;
    final optHandlingRep = t.handling_replacement;
    final optHandlingCredit = t.handling_credit;
    final optHandlingRework = t.handling_rework;

    if (segment != optDentist && segment != optLab) segment = optDentist;
    if (applied != optYes && applied != optNo) applied = optNo;
    if (injury != optYes && injury != optNo) injury = optNo;
    if (returned != optReturnedYes && returned != optReturnedNo) returned = optReturnedNo;
    if (![optHandlingRep, optHandlingCredit, optHandlingRework].contains(handling)) handling = optHandlingRep;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField(
                value: segment,
                items: [
                  DropdownMenuItem(value: optDentist, child: Text(optDentist)),
                  DropdownMenuItem(value: optLab, child: Text(optLab)),
                ],
                onChanged: (v) => setState(() => segment = v as String),
                decoration: InputDecoration(labelText: t.segment),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: article,
                decoration: InputDecoration(
                  labelText: t.article,
                  border: const OutlineInputBorder(),
                ),
              ),
              // ----- Charge (immer sichtbar, nur bei Zahnarzt Pflicht) -----
              const SizedBox(height: 8),
              TextField(
                controller: batch,
                decoration: InputDecoration(
                  labelText: isDentist ? '${t.batch} *' : t.batch,
                  border: const OutlineInputBorder(),
                ),
              ),
              // --------------------------------------------------------------
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: qty,
                      decoration: InputDecoration(
                        labelText: t.qty,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: expiry,
                      decoration: InputDecoration(
                        labelText: t.expiry,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: desc,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: t.problem_desc,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (isDentist) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField(
                  value: applied,
                  items: [
                    DropdownMenuItem(value: optYes, child: Text(optYes)),
                    DropdownMenuItem(value: optNo, child: Text(optNo)),
                  ],
                  onChanged: (v) => setState(() => applied = v as String),
                  decoration: InputDecoration(labelText: t.applied_to_patient),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField(
                  value: injury,
                  items: [
                    DropdownMenuItem(value: optYes, child: Text(optYes)),
                    DropdownMenuItem(value: optNo, child: Text(optNo)),
                  ],
                  onChanged: (v) => setState(() => injury = v as String),
                  decoration: InputDecoration(labelText: t.injury_question),
                ),
                if (needInjuryDesc) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: injuryDesc,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: t.injury_desc,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ]
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => pickFiles(t),
                icon: const Icon(Icons.upload),
                label: Text(files.isEmpty ? t.add_images : t.images_selected(files.length)),
              ),
              const Divider(height: 24),
              DropdownButtonFormField(
                value: returned,
                items: [
                  DropdownMenuItem(value: optReturnedYes, child: Text(optReturnedYes)),
                  DropdownMenuItem(value: optReturnedNo, child: Text(optReturnedNo)),
                ],
                onChanged: (v) => setState(() => returned = v as String),
                decoration: InputDecoration(labelText: t.returned_question),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField(
                value: handling,
                items: [
                  DropdownMenuItem(value: optHandlingRep, child: Text(optHandlingRep)),
                  DropdownMenuItem(value: optHandlingCredit, child: Text(optHandlingCredit)),
                  DropdownMenuItem(value: optHandlingRework, child: Text(optHandlingRework)),
                ],
                onChanged: (v) => setState(() => handling = v as String),
                decoration: InputDecoration(labelText: t.handling),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(value: privacy, onChanged: (v) => setState(() => privacy = v ?? false)),
                  Expanded(child: Text(t.privacy_agree)),
                ],
              ),
              if (err != null) Text(err!, style: const TextStyle(color: Colors.red)),
              if (info != null) Text(info!, style: const TextStyle(color: Colors.green)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        err = null;
                        info = null;

                        if (!privacy) {
                          err = t.privacy_required;
                          setState(() => busy = false);
                          return;
                        }
                        if (article.text.isEmpty || desc.text.isEmpty) {
                          err = t.required_fields;
                          setState(() => busy = false);
                          return;
                        }
                        // Charge nur bei Zahnarzt Pflicht
                        if (isDentist && batch.text.isEmpty) {
                          err = t.batch;
                          setState(() => busy = false);
                          return;
                        }

                        final res = await widget.api.submitComplaint({
                          'segment': segment == optDentist ? 'Zahnarzt' : 'Zahntechnik',
                          'article': article.text,
                          'batch': batch.text,
                          'qty': qty.text,
                          'expiry': expiry.text,
                          'desc': desc.text,
                          'applied': isDentist ? (applied == optYes ? 'Ja' : 'Nein') : '',
                          'injury': isDentist ? (injury == optYes ? 'Ja' : 'Nein') : '',
                          'injuryDesc': isDentist ? injuryDesc.text : '',
                          'returned': (returned == optReturnedYes ? 'Ja' : 'Nein'),
                          'handling': handling == optHandlingRep
                              ? 'Ersatz'
                              : (handling == optHandlingCredit ? 'Gutschrift' : 'Nacharbeit'),
                          'privacy': 'true'
                        }, files);

                        setState(() => busy = false);
                        if (res == null) {
                          err = t.send_failed;
                        } else {
                          info = t.sent_ticket(res['ticket']);
                        }
                        setState(() {});
                      },
                child: busy ? const CircularProgressIndicator() : Text(t.send),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
