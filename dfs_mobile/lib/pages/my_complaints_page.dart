// lib/pages/my_complaints_page.dart
import 'dart:async';
import 'package:dfs_mobile/web_compat/html_stub.dart'
  if (dart.library.html) 'package:dfs_mobile/web_compat/html_web.dart' as html;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../models/complaint.dart';
import '../l10n/app_localizations.dart';
import '../widgets/legal_footer.dart';

const _kComplaintMail = 'complaint@dfs-diamon.de';

class MyComplaintsPage extends StatefulWidget {
  final ApiClient api;
  const MyComplaintsPage({super.key, required this.api});

  @override
  State<MyComplaintsPage> createState() => _MyComplaintsPageState();
}

enum _SortBy { updated, created, status }

class _MyComplaintsPageState extends State<MyComplaintsPage> {
  bool _busy = false;
  String? _err;
  List<Complaint> _items = const [];
  MyRep? _myRep;

  Timer? _poll; // Auto-Refresh

  // ---- Sorting ----
  _SortBy _sortBy = _SortBy.updated;
  bool _asc = false; // default: neueste zuerst

  @override
  void initState() {
    super.initState();
    _load(); // initial
    widget.api.getMyRep().then((rep) {
      if (!mounted) return;
      setState(() => _myRep = rep);
    });
    // sanftes Polling alle 10s, ohne UI-Spinner
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _busy = true;
        _err = null;
      });
    }
    try {
      final raw = await widget.api.myComplaintsDetailed();
      final list = raw.map(Complaint.fromJson).toList(growable: false);
      _applySort(list);
      if (!mounted) return;
      setState(() => _items = list);
    } catch (e) {
      final msg = '$e';
      if (!mounted) return;
      setState(() => _err = msg);
      if (msg.contains('401')) {
        final t = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.session_invalid)),
        );
      }
    } finally {
      if (!mounted) return;
      if (!silent) setState(() => _busy = false);
    }
  }

  void _applySort(List<Complaint> list) {
    int cmpNum(int a, int b) => _asc ? a.compareTo(b) : b.compareTo(a);

    switch (_sortBy) {
      case _SortBy.updated:
        list.sort((a, b) {
          final ta = (a.updatedAt.millisecondsSinceEpoch > 0
              ? a.updatedAt.millisecondsSinceEpoch
              : a.createdAt.millisecondsSinceEpoch);
          final tb = (b.updatedAt.millisecondsSinceEpoch > 0
              ? b.updatedAt.millisecondsSinceEpoch
              : b.createdAt.millisecondsSinceEpoch);
          return cmpNum(ta, tb);
        });
        break;
      case _SortBy.created:
        list.sort((a, b) => cmpNum(
            a.createdAt.millisecondsSinceEpoch, b.createdAt.millisecondsSinceEpoch));
        break;
      case _SortBy.status:
        list.sort((a, b) {
          final s = _asc ? a.status.compareTo(b.status) : b.status.compareTo(a.status);
          if (s != 0) return s;
          final ta = (a.updatedAt.millisecondsSinceEpoch > 0
              ? a.updatedAt.millisecondsSinceEpoch
              : a.createdAt.millisecondsSinceEpoch);
          final tb = (b.updatedAt.millisecondsSinceEpoch > 0
              ? b.updatedAt.millisecondsSinceEpoch
              : b.createdAt.millisecondsSinceEpoch);
          return _asc ? ta.compareTo(tb) : tb.compareTo(ta);
        });
        break;
    }
  }

  String _fmt(DateTime dt) {
    final l = dt.toLocal();
    String two(int x) => x < 10 ? '0$x' : '$x';
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  String _formatBytes(int size) {
    if (size <= 0) return '0 B';
    const kb = 1024;
    const mb = kb * 1024;
    if (size >= mb) {
      final value = size / mb;
      return value >= 10 ? '${value.toStringAsFixed(0)} MB' : '${value.toStringAsFixed(1)} MB';
    }
    if (size >= kb) {
      final value = size / kb;
      return value >= 10 ? '${value.toStringAsFixed(0)} KB' : '${value.toStringAsFixed(1)} KB';
    }
    return '$size B';
  }

  Widget _attachmentRow(AppLocalizations t, ComplaintUpload upload) {
    final name = upload.name.trim().isEmpty ? t.attachments_file_unknown : upload.name.trim();
    final meta = <String>[];
    if (upload.size > 0) meta.add(_formatBytes(upload.size));
    if (upload.uploadedAt != null) meta.add(_fmt(upload.uploadedAt!.toLocal()));

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.attachment_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (meta.isNotEmpty)
                  Text(
                    meta.join(' • '),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Lokalisierte Status-Texte
  String _statusTextLocalized(AppLocalizations t, int s, String? decision) {
    switch (s) {
      case 1: return t.status_sent;
      case 2: return t.status_in_progress;
      case 3: return t.status_question;        // deine Keys
      case 4:
        if (decision == 'rejected') return t.status_rejected;
        if (decision == 'accepted') return t.status_accepted;
        return t.status_decision;
      case 5: return t.status_rework;
      case 6: return t.status_closed;
      default: return t.status_unknown;
    }
  }

  Color _statusColor(int s, String? decision) {
    switch (s) {
      case 1: return Colors.blue;
      case 2: return Colors.amber.shade800;
      case 3: return Colors.orange;
      case 4:
        return decision == 'rejected'
            ? Colors.red
            : (decision == 'accepted' ? Colors.lightGreen : Colors.grey);
      case 5: return Colors.amber;
      case 6: return Colors.green;
      default: return Colors.grey;
    }
  }

  bool _canOpenReportLink(Complaint c) {
    final link = (c.reportLink ?? '').trim();
    return link.isNotEmpty;
  }

  String _segmentLabel(AppLocalizations t, String raw) {
    final v = (raw).trim().toLowerCase();
    if (v == 'zahnarzt' || v == t.segment_dentist.toLowerCase()) return t.segment_dentist;
    if (v == 'zahntechnik' || v == t.segment_lab.toLowerCase()) return t.segment_lab;
    return raw;
  }

  // Produkttyp aus Payload möglichst robust herauslesen
  String _productTypeFromPayload(Map<String, dynamic> p) {
    String _s(String k) => (p[k] ?? '').toString().trim();
    final candidates = <String>[
      'productType','product_type','type','produktTyp','produkt_typ',
      'product','productName','product_name','product_group','productGroup','gruppe','group'
    ];
    for (final k in candidates) {
      final v = _s(k);
      if (v.isNotEmpty) return v;
    }
    return '';
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
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'mkv':
        return 'video/x-matroska';
      case 'mpg':
      case 'mpeg':
        return 'video/mpeg';
      case 'wmv':
        return 'video/x-ms-wmv';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _addAttachments(Complaint c) async {
    final t = AppLocalizations.of(context)!;
    final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (res == null || res.files.isEmpty) return;

    const limit = 8 * 1024 * 1024;
    int totalBytes = 0;
    final selected = <({String name, List<int> bytes, String mime})>[];

    for (final file in res.files) {
      final data = file.bytes;
      if (data == null || data.isEmpty) continue;
      totalBytes += data.length;
      if (totalBytes > limit) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.attachments_too_large)),
        );
        return;
      }
      selected.add((
        name: file.name,
        bytes: List<int>.from(data),
        mime: _guessMime(file.name),
      ));
    }

    if (selected.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.attachments_error)),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await widget.api.complaintUploadFiles(c.ticket, selected);
      await _load(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.attachments_success)),
      );
    } catch (e) {
      if (!mounted) return;
      final errMsg = (e is ApiError && (e.message).contains('too large'))
          ? t.attachments_too_large
          : t.attachments_error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errMsg)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openComplaintContactForm(Complaint c) async {
    final t = AppLocalizations.of(context)!;
    final initialSubject = t.complaint_contact_subject_prefill(c.ticket);

    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ComplaintContactDialog(
        api: widget.api,
        complaint: c,
        rep: _myRep,
        initialSubject: initialSubject,
      ),
    );

    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.rep_contact_sent)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    final repFirst = (_myRep?.firstName ?? '').trim();
    final repLast  = (_myRep?.lastName  ?? '').trim();
    final repEmail = (_myRep?.email     ?? '').trim();
    final repRegion= (_myRep?.region    ?? '').trim();
    final repName  = [repFirst, repLast].where((e) => e.isNotEmpty).join(' ').trim();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: t.back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(t.my_complaints_title),
        actions: [
          _SortControls(
            sortBy: _sortBy,
            asc: _asc,
            onChanged: (s, asc) {
              setState(() {
                _sortBy = s;
                _asc = asc;
                _applySort(_items);
              });
            },
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t.refresh,
            onPressed: _busy ? null : () => _load(silent: false),
          ),
        ],
      ),
      body: Column(
        children: [
          // Vertreter-Banner
          if (repName.isNotEmpty || repEmail.isNotEmpty || repRegion.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.08),
                  border: Border.all(color: Colors.blue, width: 1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.handshake_outlined, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.rep_banner_title(repName.isEmpty ? '—' : repName),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (repEmail.isNotEmpty)
                      Tooltip(
                        message: t.rep_email_tooltip,
                        child: TextButton.icon(
                          onPressed: () {
                            final subject = Uri.encodeComponent(t.mail_subject_rep);
                            final mailto = 'mailto:$repEmail?subject=$subject';
                            html.window.open(mailto, '_self');
                          },
                          icon: const Icon(Icons.email_outlined),
                          label: Text(t.rep_email_button),
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // Liste der Reklamationen
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : _err != null
                    ? Center(child: Text(_err!))
                    : _items.isEmpty
                        ? Center(child: Text(t.none_complaints))
                        : RefreshIndicator(
                            onRefresh: () => _load(silent: false),
                            child: ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final c = _items[i];
                                final ticket = (c.ticket).toString();
                                final statusText = _statusTextLocalized(t, c.status, c.decision);
                                final statusColor = _statusColor(c.status, c.decision);
                                final reportLink = (c.reportLink ?? '').trim();
                                final canOpenReport = _canOpenReportLink(c);

                                final p = c.payload ?? const <String, dynamic>{};
                                final segRaw = (p['segment'] ?? '').toString();
                                final seg = segRaw.isNotEmpty ? _segmentLabel(t, segRaw) : '';
                                final articleNo = (p['article'] ?? '').toString().trim();
                                final productType = _productTypeFromPayload(p);
                                final internalNo = (c.internalNo ?? '').trim();
                                final hasInternalNo = internalNo.isNotEmpty;

                                // HEADER: Status, Artikelnummer, Produkttyp sofort sichtbar
                                final attachmentsButton = TextButton.icon(
                                  onPressed: _busy ? null : () => _addAttachments(c),
                                  icon: const Icon(Icons.attach_file_outlined),
                                  label: Text(t.attachments_add),
                                );

                                final contactButton = TextButton.icon(
                                  onPressed:
                                      _busy ? null : () => _openComplaintContactForm(c),
                                  icon: const Icon(Icons.mail_outline),
                                  label: Text(t.complaint_contact_button),
                                );

                                final actionButtons = Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  alignment: WrapAlignment.end,
                                  children: [
                                    attachmentsButton,
                                    contactButton,
                                  ],
                                );

                                final infoWrap = Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _StatusPill(text: statusText, color: statusColor),
                                    if (articleNo.isNotEmpty)
                                      _KeyValuePill(
                                        icon: Icons.handyman_outlined,
                                        label: (t.articleNo ?? t.article),
                                        value: articleNo,
                                      ),
                                    if (productType.isNotEmpty)
                                      _KeyValuePill(
                                        icon: Icons.category_outlined,
                                        label: t.product_type ?? 'Produkttyp',
                                        value: productType,
                                      ),
                                    if ((c.decision ?? '').isNotEmpty)
                                      _StatusPill(
                                        text: (c.decision == 'accepted')
                                            ? t.decision_accepted
                                            : t.decision_rejected,
                                        color: (c.decision == 'accepted') ? Colors.green : Colors.red,
                                      ),
                                  ],
                                );

                                final headerLine = LayoutBuilder(
                                  builder: (context, constraints) {
                                    if (constraints.maxWidth < 520) {
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          infoWrap,
                                          const SizedBox(height: 8),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(maxWidth: 360),
                                              child: actionButtons,
                                            ),
                                          ),
                                        ],
                                      );
                                    }

                                    return Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: infoWrap),
                                        const SizedBox(width: 12),
                                        actionButtons,
                                      ],
                                    );
                                  },
                                );

                                // EXPANSION: alle Details
                                return Card(
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  child: Theme(
                                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                    child: ExpansionTile(
                                      tilePadding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                                      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                                      title: Row(
                                        children: [
                                          const Icon(Icons.description_outlined, size: 20),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    ticket.isEmpty ? '—' : ticket,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style:
                                                        const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                                  ),
                                                ),
                                                if (hasInternalNo)
                                                  Flexible(
                                                    flex: 0,
                                                    child: Padding(
                                                      padding: const EdgeInsets.only(left: 8),
                                                      child: _internalNoPill(t, internalNo),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: headerLine,
                                      ),
                                      children: [
                                        const SizedBox(height: 8),
                                        // Sektion: Basisdaten
                                        _DetailGroup(
                                          title: t.details,
                                          children: [
                                            _kv(t.segment, seg.isEmpty ? '—' : seg),
                                            _kv(t.article, articleNo.isEmpty ? '—' : articleNo),
                                            if (productType.isNotEmpty)
                                              _kv(t.product_type ?? 'Produkttyp', productType),
                                            if ((p['batch'] ?? '').toString().isNotEmpty)
                                              _kv(t.batch, (p['batch']).toString()),
                                            if ((p['qty'] ?? '').toString().isNotEmpty)
                                              _kv(t.quantity, (p['qty']).toString()),
                                            if ((p['expiry'] ?? '').toString().isNotEmpty)
                                              _kv(t.expiry, (p['expiry']).toString()),
                                            if ((p['desc'] ?? '').toString().isNotEmpty)
                                              _kv(t.description, (p['desc']).toString()),
                                          ],
                                        ),

                                        // Sektion: Rücksendung / Wunsch
                                        if ((p['returned'] ?? '').toString().isNotEmpty || (p['handling'] ?? '').toString().isNotEmpty)
                                          _DetailGroup(
                                            title: t.handling,
                                            children: [
                                              if ((p['returned'] ?? '').toString().isNotEmpty)
                                                _kv(t.returned ?? t.returned_question, (p['returned']).toString()),
                                              if ((p['handling'] ?? '').toString().isNotEmpty)
                                                _kv(t.handling, (p['handling']).toString()),
                                            ],
                                          ),

                                        // Sektion: Patientenbezug
                                        if ((p['applied'] ?? '').toString().isNotEmpty ||
                                            (p['injury'] ?? '').toString().isNotEmpty ||
                                            (p['injuryDesc'] ?? '').toString().trim().isNotEmpty)
                                          _DetailGroup(
                                            title: t.applied_to_patient,
                                            children: [
                                              if ((p['applied'] ?? '').toString().isNotEmpty)
                                                _kv(t.applied, (p['applied']).toString()),
                                              if ((p['injury'] ?? '').toString().isNotEmpty)
                                                _kv(t.injury, (p['injury']).toString()),
                                              if ((p['injuryDesc'] ?? '').toString().trim().isNotEmpty)
                                                _kv(t.injury_desc, (p['injuryDesc']).toString()),
                                            ],
                                          ),

                                        // Sektion: Kunde / Land
                                        if ((p['customerName'] ?? '').toString().isNotEmpty ||
                                            (p['country'] ?? '').toString().isNotEmpty)
                                          _DetailGroup(
                                            title: t.customer_label,
                                            children: [
                                              if ((p['customerName'] ?? '').toString().isNotEmpty)
                                                _kv(t.customer_label, (p['customerName']).toString()),
                                              if ((p['country'] ?? '').toString().isNotEmpty)
                                                _kv(t.country_label, (p['country']).toString()),
                                            ],
                                          ),

                                        // Zeiten & interne Nr.
                                        _DetailGroup(
                                          title: t.timestamps ?? 'Zeitstempel',
                                          children: [
                                            _kv(t.created, _fmt(c.createdAt)),
                                            if (c.updatedAt.millisecondsSinceEpoch > 0)
                                              _kv(t.updated, _fmt(c.updatedAt)),
                                            if ((c.internalNo ?? '').toString().isNotEmpty)
                                              _kv(t.internal_no_label, c.internalNo!),
                                          ],
                                        ),

                                        if (c.uploads.isNotEmpty)
                                          _DetailGroup(
                                            title: t.attachments_existing,
                                            children: [
                                              for (final upload in c.uploads)
                                                _attachmentRow(t, upload),
                                            ],
                                          ),

                                        // Aktionen
                                        if (canOpenReport)
                                          Row(
                                            children: [
                                              TextButton.icon(
                                                onPressed: () => html.window.open(reportLink, '_blank'),
                                                icon: const Icon(Icons.open_in_new),
                                                label: Text(t.report_open),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
      bottomNavigationBar: LegalFooter(api: widget.api),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            flex: 0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value.isEmpty ? '—' : value)),
        ],
      ),
    );
  }

  Widget _internalNoPill(AppLocalizations t, String value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.tag, size: 14),
          const SizedBox(width: 4),
          Text(
            '${t.internal_no_label}: $value',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Sortier-Steuerung (rechts in der AppBar) ----
class _SortControls extends StatelessWidget {
  final _SortBy sortBy;
  final bool asc;
  final void Function(_SortBy by, bool asc) onChanged;
  const _SortControls({
    required this.sortBy,
    required this.asc,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Row(
      children: [
        DropdownButton<_SortBy>(
          value: sortBy,
          underline: const SizedBox.shrink(),
          onChanged: (v) {
            if (v != null) onChanged(v, asc);
          },
          items: [
            DropdownMenuItem(value: _SortBy.updated, child: Text(t.updated)),
            DropdownMenuItem(value: _SortBy.created, child: Text(t.created)),
            DropdownMenuItem(value: _SortBy.status,  child: Text(t.status)),
          ],
        ),
        IconButton(
          tooltip: asc ? 'Aufsteigend' : 'Absteigend',
          onPressed: () => onChanged(sortBy, !asc),
          icon: Icon(asc ? Icons.arrow_upward : Icons.arrow_downward),
        ),
      ],
    );
  }
}

// ------------------- kleine UI-Helfer (darstellungs-only) -------------------

class _StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusPill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final safe = text.isEmpty ? '—' : text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        safe,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5),
      ),
    );
  }
}

class _KeyValuePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _KeyValuePill({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Flexible(child: Text(value, overflow: TextOverflow.ellipsis, maxLines: 1)),
        ],
      ),
    );
  }
}

class _DetailGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _DetailGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

class _ComplaintContactDialog extends StatefulWidget {
  final ApiClient api;
  final Complaint complaint;
  final MyRep? rep;
  final String initialSubject;
  const _ComplaintContactDialog({
    required this.api,
    required this.complaint,
    required this.rep,
    required this.initialSubject,
  });

  @override
  State<_ComplaintContactDialog> createState() => _ComplaintContactDialogState();
}

class _ComplaintContactDialogState extends State<_ComplaintContactDialog> {
  late final TextEditingController _subjectCtrl;
  final TextEditingController _messageCtrl = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _subjectCtrl = TextEditingController(text: widget.initialSubject);
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = AppLocalizations.of(context)!;
    final subject = _subjectCtrl.text.trim();
    final message = _messageCtrl.text.trim();

    if (subject.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.rep_contact_validation)),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      await widget.api.complaintContact(
        ticket: widget.complaint.ticket,
        subject: subject,
        message: message,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final errText = (e is ApiError && e.message.isNotEmpty)
          ? '${t.rep_contact_error} (${e.message})'
          : t.rep_contact_error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errText)),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final rep = widget.rep;
    final repEmail = (rep?.email ?? '').trim();
    final hasRep = repEmail.isNotEmpty;
    final displayName = (rep?.displayName ?? '').trim();
    final repName = displayName.isNotEmpty ? displayName : repEmail;

    final infoText = hasRep
        ? t.complaint_contact_intro_rep(repName, repEmail)
        : t.complaint_contact_intro_qm(_kComplaintMail);

    return AlertDialog(
      title: Text(t.complaint_contact_title(widget.complaint.ticket)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                infoText,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurface.withOpacity(.8)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _subjectCtrl,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: t.rep_contact_subject_label,
                  prefixIcon: const Icon(Icons.subject),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _messageCtrl,
                minLines: 5,
                maxLines: 10,
                decoration: InputDecoration(
                  labelText: t.rep_contact_message_label,
                  alignLabelWithHint: true,
                  prefixIcon: const Icon(Icons.message_outlined),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: Text(t.cancel),
        ),
        ElevatedButton.icon(
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_outlined),
          label: Text(t.send),
        ),
      ],
    );
  }
}
