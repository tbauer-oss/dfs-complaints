// lib/pages/my_complaints_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:dfs_mobile/web_compat/html_stub.dart'
  if (dart.library.html) 'package:dfs_mobile/web_compat/html_web.dart' as html;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../models/complaint.dart';
import '../l10n/app_localizations.dart';
import '../utils/attachment_preview.dart';
import '../widgets/legal_footer.dart';

const _kComplaintMail = 'complaint@dfs-diamon.de';

class MyComplaintsPage extends StatefulWidget {
  final ApiClient api;
  const MyComplaintsPage({super.key, required this.api});

  @override
  State<MyComplaintsPage> createState() => _MyComplaintsPageState();
}

enum _SortBy { updated, created }

class _MyComplaintsPageState extends State<MyComplaintsPage> {
  bool _busy = false;
  bool _loading = false;
  bool _uploading = false;
  String? _err;
  List<Complaint> _items = const [];
  List<Complaint> _allItems = const [];
  MyRep? _myRep;

  String? _filterTicket;
  String? _filterInternalNo;
  int? _filterStatus;
  String? _filterDecision;

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
        _loading = true;
        _err = null;
      });
    }
    try {
      final raw = await widget.api.myComplaintsDetailed();
      final list = raw.map(Complaint.fromJson).toList(growable: false);
      if (!mounted) return;
      setState(() => _allItems = list);
      _refreshFilteredItems();
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
      if (!silent) setState(() { _busy = false; _loading = false; });
    }
  }

  void _refreshFilteredItems() {
    final filtered = _applyFilters(List<Complaint>.from(_allItems));
    _applySort(filtered);
    if (mounted) setState(() => _items = filtered);
  }

  List<Complaint> _applyFilters(List<Complaint> list) {
    return list.where((c) {
      final ticket = (c.ticket).trim();
      final internal = (c.internalNo ?? '').trim();
      final decision = (c.decision ?? '').trim();

      if ((_filterTicket ?? '').isNotEmpty && ticket != _filterTicket) return false;
      if ((_filterInternalNo ?? '').isNotEmpty && internal != _filterInternalNo) return false;
      if (_filterStatus != null && c.status != _filterStatus) return false;
      if ((_filterDecision ?? '').isNotEmpty && decision != _filterDecision) return false;
      return true;
    }).toList(growable: false);
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
    }
  }

  List<String> _optionsFrom(Iterable<String> values) {
    final set = <String>{};
    for (final v in values) {
      final trimmed = v.trim();
      if (trimmed.isNotEmpty) set.add(trimmed);
    }
    final list = set.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  List<int> _statusOptions(List<Complaint> list) {
    final set = <int>{};
    for (final c in list) {
      set.add(c.status);
    }
    final out = set.toList()..sort();
    return out;
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

  // Lokalisierte Status-Texte
  String _statusTextLocalized(AppLocalizations t, int s) {
    switch (s) {
      case 1: return t.status_sent;
      case 2: return t.status_in_progress;
      case 3: return t.status_question;
      case 4: return t.status_rework;
      case 5: return t.status_closed;
      default: return t.status_unknown;
    }
  }

  Color _statusColor(int s) {
    switch (s) {
      case 1: return Colors.blue;
      case 2: return Colors.amber.shade800;
      case 3: return Colors.orange;
      case 4: return Colors.amber.shade600;
      case 5: return Colors.green;
      default: return Colors.grey;
    }
  }

  String _decisionText(AppLocalizations t, String? decision) {
    final normalized = (decision ?? '').trim();
    if (normalized == 'accepted') return t.decision_accepted;
    if (normalized == 'rejected') return t.decision_rejected;
    return t.decision_pending ?? 'Entscheidung offen';
  }

  Color _decisionColor(String? decision) {
    final normalized = (decision ?? '').trim();
    if (normalized == 'accepted') return Colors.green.shade600;
    if (normalized == 'rejected') return Colors.red.shade600;
    return Colors.grey.shade600;
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
    final selected = <({String name, List<int> bytes, String mime, String? preview})>[];

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
      final mime = _guessMime(file.name);
      selected.add((
        name: file.name,
        bytes: List<int>.from(data),
        mime: mime,
        preview: createAttachmentPreview(data, mime),
      ));
    }

    if (selected.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.attachments_error)),
      );
      return;
    }

    setState(() { _busy = true; _uploading = true; });
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
      if (mounted) setState(() { _busy = false; _uploading = false; });
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
              });
              _refreshFilteredItems();
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

          // Filter
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _FilterBar(
              tickets: _optionsFrom(_allItems.map((c) => (c.ticket).trim())),
              internalNos:
                  _optionsFrom(_allItems.map((c) => (c.internalNo ?? '').trim())),
              statuses: _statusOptions(_allItems),
              decisions: _optionsFrom(_allItems.map((c) => (c.decision ?? '').trim())),
              selectedTicket: _filterTicket,
              selectedInternal: _filterInternalNo,
              selectedStatus: _filterStatus,
              selectedDecision: _filterDecision,
              statusLabel: (s) => _statusTextLocalized(t, s),
              decisionLabel: (d) => _decisionText(t, d),
              onChanged: (
                  {String? ticket, String? internal, int? status, String? decision}) {
                setState(() {
                  _filterTicket = ticket;
                  _filterInternalNo = internal;
                  _filterStatus = status;
                  _filterDecision = decision;
                });
                _refreshFilteredItems();
              },
            ),
          ),

          if (_uploading)
            const LinearProgressIndicator(minHeight: 4),

          // Liste der Reklamationen
          Expanded(
            child: _loading
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
                                final statusText = _statusTextLocalized(t, c.status);
                                final statusColor = _statusColor(c.status);
                                final decisionText = _decisionText(t, c.decision);
                                final decisionColor = _decisionColor(c.decision);
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
                                  spacing: 10,
                                  runSpacing: 6,
                                  children: [
                                    attachmentsButton,
                                    contactButton,
                                  ],
                                );

                                final statusWrap = Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _StatusPill(text: decisionText, color: decisionColor),
                                    _StatusPill(text: statusText, color: statusColor),
                                  ],
                                );

                                final metaWrap = Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
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
                                  ],
                                );

                                final headerInfo = Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    statusWrap,
                                    if (metaWrap.children.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      metaWrap,
                                    ],
                                  ],
                                );

                                final headerLine = LayoutBuilder(
                                  builder: (context, constraints) {
                                    final isCompact = constraints.maxWidth < 620;
                                    final actions = ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth:
                                            isCompact ? constraints.maxWidth : 340,
                                      ),
                                      child: actionButtons,
                                    );

                                    if (isCompact) {
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          headerInfo,
                                          const SizedBox(height: 10),
                                          actions,
                                        ],
                                      );
                                    }

                                    return Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: headerInfo),
                                        const SizedBox(width: 12),
                                        actions,
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
                                            child: LayoutBuilder(
                                              builder: (context, constraints) {
                                                final ticketText = ConstrainedBox(
                                                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                                                  child: Text(
                                                    ticket.isEmpty ? '—' : ticket,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style:
                                                        const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                                  ),
                                                );

                                                if (!hasInternalNo) return ticketText;

                                                return Wrap(
                                                  spacing: 8,
                                                  runSpacing: 6,
                                                  crossAxisAlignment: WrapCrossAlignment.center,
                                                  children: [
                                                    ticketText,
                                                    _internalNoPill(t, internalNo),
                                                  ],
                                                );
                                              },
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
                                                _AttachmentPreviewTile(
                                                  upload: upload,
                                                  formatBytes: _formatBytes,
                                                  formatDate: _fmt,
                                                  fallbackName: t.attachments_file_unknown,
                                                ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.tag, size: 13),
          const SizedBox(width: 3),
          Text(
            '${t.internal_no_label}: $value',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final List<String> tickets;
  final List<String> internalNos;
  final List<int> statuses;
  final List<String> decisions;
  final String? selectedTicket;
  final String? selectedInternal;
  final int? selectedStatus;
  final String? selectedDecision;
  final void Function({String? ticket, String? internal, int? status, String? decision})
      onChanged;
  final String Function(int status) statusLabel;
  final String Function(String? decision) decisionLabel;

  const _FilterBar({
    required this.tickets,
    required this.internalNos,
    required this.statuses,
    required this.decisions,
    required this.selectedTicket,
    required this.selectedInternal,
    required this.selectedStatus,
    required this.selectedDecision,
    required this.onChanged,
    required this.statusLabel,
    required this.decisionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    Widget buildDropdown<T>({
      required String label,
      required T? value,
      required List<DropdownMenuItem<T?>> items,
      required void Function(T?) onChanged,
      required double width,
    }) {
      return SizedBox(
        width: width,
        child: DropdownButtonFormField<T?>(
          value: value,
          isDense: true,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          items: items,
          onChanged: onChanged,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final compact = maxWidth < 520;
        final fieldWidth = compact
            ? maxWidth
            : math.min<double>(280, (maxWidth - 12) / 2);

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: compact ? WrapAlignment.start : WrapAlignment.spaceBetween,
          children: [
            buildDropdown<String>(
              label: t.ticket,
              value: selectedTicket,
              width: fieldWidth,
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(t.rep_overview_all)),
                ...tickets.map((v) => DropdownMenuItem<String?>(value: v, child: Text(v))),
              ],
              onChanged: (v) =>
                  onChanged(ticket: v, internal: selectedInternal, status: selectedStatus, decision: selectedDecision),
            ),
            buildDropdown<String>(
              label: t.internal_no_label,
              value: selectedInternal,
              width: fieldWidth,
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(t.rep_overview_all)),
                ...internalNos.map((v) => DropdownMenuItem<String?>(value: v, child: Text(v))),
              ],
              onChanged: (v) =>
                  onChanged(ticket: selectedTicket, internal: v, status: selectedStatus, decision: selectedDecision),
            ),
            buildDropdown<int>(
              label: t.status,
              value: selectedStatus,
              width: fieldWidth,
              items: [
                DropdownMenuItem<int?>(value: null, child: Text(t.allStatus)),
                ...statuses.map((v) => DropdownMenuItem<int?>(value: v, child: Text(statusLabel(v)))),
              ],
              onChanged: (v) =>
                  onChanged(ticket: selectedTicket, internal: selectedInternal, status: v, decision: selectedDecision),
            ),
            buildDropdown<String>(
              label: t.decision,
              value: selectedDecision,
              width: fieldWidth,
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(t.allDecisions)),
                ...decisions.map((v) => DropdownMenuItem<String?>(value: v, child: Text(decisionLabel(v)))),
              ],
              onChanged: (v) =>
                  onChanged(ticket: selectedTicket, internal: selectedInternal, status: selectedStatus, decision: v),
            ),
          ],
        );
      },
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

class _AttachmentPreviewTile extends StatefulWidget {
  final ComplaintUpload upload;
  final String Function(int size) formatBytes;
  final String Function(DateTime date) formatDate;
  final String fallbackName;

  const _AttachmentPreviewTile({
    required this.upload,
    required this.formatBytes,
    required this.formatDate,
    required this.fallbackName,
  });

  @override
  State<_AttachmentPreviewTile> createState() => _AttachmentPreviewTileState();
}

class _AttachmentPreviewTileState extends State<_AttachmentPreviewTile> {
  bool _expanded = false;
  Uint8List? _previewBytes;
  ImageProvider<Object>? _previewProvider;

  bool get _hasPreview => _previewProvider != null;

  @override
  void initState() {
    super.initState();
    _previewProvider = _createPreviewProvider(widget.upload);
  }

  @override
  void didUpdateWidget(covariant _AttachmentPreviewTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.upload.preview != widget.upload.preview ||
        oldWidget.upload.url != widget.upload.url ||
        oldWidget.upload.downloadUrl != widget.upload.downloadUrl) {
      final next = _createPreviewProvider(widget.upload);
      setState(() {
        _previewProvider = next;
        if (!_hasPreview) _expanded = false;
      });
    }
  }

  ImageProvider<Object>? _createPreviewProvider(ComplaintUpload upload) {
    _previewBytes = null;
    final preview = upload.preview;
    if (preview != null && preview.isNotEmpty && upload.isImage) {
      try {
        _previewBytes = base64Decode(preview);
        return MemoryImage(_previewBytes!);
      } catch (_) {
        _previewBytes = null;
      }
    }
    final remote = upload.imageUrl;
    if (remote != null && remote.isNotEmpty) {
      return NetworkImage(remote);
    }
    return null;
  }

  void _toggle() {
    if (!_hasPreview) return;
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final upload = widget.upload;
    final theme = Theme.of(context);
    final name = upload.name.trim().isEmpty ? widget.fallbackName : upload.name.trim();
    final meta = <String>[];
    if (upload.size > 0) meta.add(widget.formatBytes(upload.size));
    if (upload.uploadedAt != null) meta.add(widget.formatDate(upload.uploadedAt!.toLocal()));
    const double previewWidth = 220;
    const double previewHeight = 165;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _hasPreview ? _toggle : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _hasPreview && _expanded ? Icons.image_outlined : Icons.attachment_outlined,
                  size: 18,
                  color: _hasPreview ? theme.colorScheme.primary : null,
                ),
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
                if (_hasPreview)
                  Icon(
                    _expanded ? Icons.expand_less : Icons.visibility_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
          ),
          if (_hasPreview && _expanded)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    color: theme.colorScheme.surfaceVariant,
                  ),
                  width: previewWidth,
                  height: previewHeight,
                  child: Image(image: _previewProvider!, fit: BoxFit.cover),
                ),
              ),
            ),
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
