// lib/pages/my_complaints_page.dart
import 'dart:async';
import 'dart:html' as html; // nur Web – für Link-Öffnen & mailto
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../models/complaint.dart';
import '../l10n/app_localizations.dart';
import '../widgets/legal_footer.dart';

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
      // Nutzt neuen Detail-Endpunkt (JWT), liefert volle Felder
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
        // Status: 1..6 – bei gleicher Zahl nach Updated sortieren
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
    // kompakt & lokal
    final l = dt.toLocal();
    String two(int x) => x < 10 ? '0$x' : '$x';
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  // Lokalisierte Status-Texte
  String _statusTextLocalized(AppLocalizations t, int s, String? decision) {
    switch (s) {
      case 1:
        return t.status_sent;
      case 2:
        return t.status_in_progress;
      case 3:
        return t.status_question;
      case 4:
        if (decision == 'rejected') return t.status_rejected;
        if (decision == 'accepted') return t.status_accepted;
        return t.status_decision;
      case 5:
        return t.status_rework;
      case 6:
        return t.status_closed;
      default:
        return t.status_unknown;
    }
  }

  Color _statusColor(int s, String? decision) {
    switch (s) {
      case 1:
        return Colors.blue;
      case 2:
        return Colors.amber.shade800;
      case 3:
        return Colors.orange;
      case 4:
        return decision == 'rejected'
            ? Colors.red
            : (decision == 'accepted' ? Colors.lightGreen : Colors.grey);
      case 5:
        return Colors.amber;
      case 6:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // Report-Link ist für Kunden sichtbar, wenn gesetzt (unabhängig vom Status)
  bool _canOpenReportLink(Complaint c) {
    final link = (c.reportLink ?? '').trim();
    return link.isNotEmpty;
  }

  // Segment hübsch: Zahnarzt/Zahntechnik (lokalisiert)
  String _segmentLabel(AppLocalizations t, String raw) {
    final v = (raw).trim().toLowerCase();
    if (v == 'zahnarzt' || v == t.segment_dentist.toLowerCase()) return t.segment_dentist;
    if (v == 'zahntechnik' || v == t.segment_lab.toLowerCase()) return t.segment_lab;
    return raw; // fallback (zeigt Original)
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    // Name/E-Mail/Region des Vertreters (robust; kein displayName nötig)
    final repName = _myRep == null
        ? ''
        : '${(_myRep!.firstName).trim()} ${(_myRep!.lastName).trim()}'.trim();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: t.back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(t.my_complaints_title),
        actions: [
          // Sortierleiste in der AppBar (kompakt)
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
                width: 18,
                height: 18,
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
          // Hinweis-Banner mit Vertreter (falls vorhanden)
          if (_myRep != null)
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

                    // Name + Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.rep_banner_title(repName.isEmpty ? '—' : repName),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text([
                            if (_myRep!.email.isNotEmpty) _myRep!.email,
                            if (_myRep!.region.isNotEmpty) _myRep!.region,
                          ].join(' • ')),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // E-Mail Button (mailto)
                    Tooltip(
                      message: t.rep_email_tooltip,
                      child: TextButton.icon(
                        onPressed: () {
                          final subject = Uri.encodeComponent(t.mail_subject_rep);
                          final mailto = 'mailto:${_myRep!.email}?subject=$subject';
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

          // Der Body in moderner Kartenliste mit Aufklappdetails
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

                                // Status & Farben
                                final statusText = _statusTextLocalized(t, c.status, c.decision);
                                final statusColor = _statusColor(c.status, c.decision);

                                // Pflicht-Summary: Segment + Artikel
                                final p = c.payload ?? const <String, dynamic>{};
                                final segRaw = (p['segment'] ?? '').toString();
                                final seg = segRaw.isNotEmpty ? _segmentLabel(t, segRaw) : '';
                                final art = (p['article'] ?? '').toString();

                                final canOpenReport = _canOpenReportLink(c);
                                final reportLink = (c.reportLink ?? '').trim();

                                return _ComplaintCard(
                                  c: c,
                                  statusText: statusText,
                                  statusColor: statusColor,
                                  seg: seg,
                                  art: art,
                                  reportLink: canOpenReport ? reportLink : null,
                                  created: _fmt(c.createdAt),
                                  updated: (c.updatedAt.millisecondsSinceEpoch > 0) ? _fmt(c.updatedAt) : null,
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

// =======================
//   K a r t e  (modern)
// =======================
class _ComplaintCard extends StatefulWidget {
  final Complaint c;
  final String statusText;
  final Color statusColor;
  final String seg;   // Produktgruppe (Segment)
  final String art;   // Artikel
  final String? reportLink;
  final String created;
  final String? updated;

  const _ComplaintCard({
    required this.c,
    required this.statusText,
    required this.statusColor,
    required this.seg,
    required this.art,
    required this.created,
    this.updated,
    this.reportLink,
    super.key,
  });

  @override
  State<_ComplaintCard> createState() => _ComplaintCardState();
}

class _ComplaintCardState extends State<_ComplaintCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final decision = (widget.c.decision ?? '').trim().toLowerCase();

    // Entscheidungs-Chip (optional, nur wenn gesetzt)
    Widget? decisionChip;
    if (decision.isNotEmpty) {
      final ok = decision == 'accepted';
      final col = ok ? Colors.green : Colors.red;
      final txt = ok ? t.decision_accepted : t.decision_rejected;
      decisionChip = _ChipOutlined(text: '${t.decision}: $txt', color: col);
    }

    // Seitenakzent (Status-Farbe) + moderne Karte
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 10, offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // farbige Statusleiste (sofort sichtbar)
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: widget.statusColor,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              ),
            ),
            // Inhalt
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  children: [
                    // Kopfzeile (Ticket, Status, Entscheidung, Expand)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(Icons.description_outlined, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.c.ticket.isEmpty ? '(ohne Ticket)' : widget.c.ticket,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _ChipOutlined(text: '${t.status}: ${widget.statusText}', color: widget.statusColor),
                        if (decisionChip != null) ...[
                          const SizedBox(width: 6),
                          decisionChip,
                        ],
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: _expanded ? t.close : t.details,
                          onPressed: () => setState(() => _expanded = !_expanded),
                          icon: AnimatedRotation(
                            turns: _expanded ? .5 : 0,
                            duration: const Duration(milliseconds: 160),
                            child: const Icon(Icons.expand_more),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Pflichtinfos (Segment & Artikel) – immer sichtbar
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: [
                        if (widget.seg.isNotEmpty)
                          _InfoChip(icon: Icons.category_outlined, label: t.segment, value: widget.seg),
                        if (widget.art.isNotEmpty)
                          _InfoChip(icon: Icons.handyman_outlined, label: t.articleNo, value: widget.art),
                        if ((widget.c.internalNo ?? '').toString().isNotEmpty)
                          _InfoChip(icon: Icons.tag, label: t.internal_no_label, value: widget.c.internalNo!),
                      ],
                    ),

                    // Aufklappbereich (weitere Details)
                    AnimatedCrossFade(
                      firstChild: const SizedBox.shrink(),
                      secondChild: _ExpandedDetails(
                        c: widget.c,
                        created: widget.created,
                        updated: widget.updated,
                        reportLink: widget.reportLink,
                      ),
                      crossFadeState:
                          _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 180),
                      sizeCurve: Curves.easeOut,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------- Aufklapp-Inhalt (Details) --------
class _ExpandedDetails extends StatelessWidget {
  final Complaint c;
  final String created;
  final String? updated;
  final String? reportLink;

  const _ExpandedDetails({
    required this.c,
    required this.created,
    this.updated,
    this.reportLink,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final payload = c.payload ?? const <String, dynamic>{};

    Widget row(String l, String v, {IconData? icon}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 170,
            child: Text(l, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(v.isEmpty ? '—' : v)),
        ],
      ),
    );

    final desc   = (payload['desc'] ?? '').toString();
    final batch  = (payload['batch'] ?? '').toString();
    final qty    = (payload['qty'] ?? '').toString();
    final expiry = (payload['expiry'] ?? '').toString();
    final returned = (payload['returned'] ?? '').toString();
    final handling = (payload['handling'] ?? '').toString();
    final applied  = (payload['applied'] ?? '').toString();
    final injury   = (payload['injury'] ?? '').toString();
    final injuryDesc = (payload['injuryDesc'] ?? '').toString();
    final customerName = (payload['customerName'] ?? '').toString();
    final country = (payload['country'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Zeit-Infos
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              _InfoChip(icon: Icons.add_circle_outline, label: t.created, value: created),
              if (updated != null)
                _InfoChip(icon: Icons.update, label: t.updated, value: updated!),
            ],
          ),
          const SizedBox(height: 10),

          // Detailblöcke als “Cards in Card”
          Wrap(
            runSpacing: 8,
            children: [
              row(t.description, desc, icon: Icons.notes_outlined),
              if (batch.isNotEmpty || qty.isNotEmpty || expiry.isNotEmpty)
                row(
                  t.article,
                  [
                    if (batch.isNotEmpty) '${t.batch}: $batch',
                    if (qty.isNotEmpty)   '${t.quantity}: $qty',
                    if (expiry.isNotEmpty) '${t.expiry}: $expiry',
                  ].join('   •   '),
                  icon: Icons.inventory_2_outlined,
                ),
              if (returned.isNotEmpty) row(t.returned, returned, icon: Icons.local_shipping_outlined),
              if (handling.isNotEmpty) row(t.handling, handling, icon: Icons.build_circle_outlined),
              if (applied.isNotEmpty)  row(t.applied, applied, icon: Icons.playlist_add_check_outlined),
              if (injury.isNotEmpty)   row(t.injury, injury, icon: Icons.health_and_safety_outlined),
              if (injuryDesc.trim().isNotEmpty) row(t.injury_desc, injuryDesc, icon: Icons.description_outlined),
              if (customerName.isNotEmpty) row(t.customer_label, customerName, icon: Icons.person_outline),
              if (country.isNotEmpty)      row(t.country_label, country, icon: Icons.public_outlined),
            ],
          ),

          const SizedBox(height: 12),

          // Aktionen
          Row(
            children: [
              if ((reportLink ?? '').isNotEmpty)
                TextButton.icon(
                  onPressed: () => html.window.open(reportLink!, '_blank'),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(t.report_open),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  await showDialog(
                    context: context,
                    builder: (_) => _MyComplaintDetailsDialog(c: c),
                  );
                },
                icon: const Icon(Icons.info_outline),
                label: Text(t.details),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- Details-Dialog (Kundenbereich) ----
// WICHTIG: Top-Level (außerhalb der State-Klasse)!
class _MyComplaintDetailsDialog extends StatelessWidget {
  final Complaint c;
  const _MyComplaintDetailsDialog({required this.c});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final Map<String, dynamic> payload = c.payload ?? const <String, dynamic>{};

    String _fmtLocal(DateTime dt) {
      final l = dt.toLocal();
      String two(int x) => x < 10 ? '0$x' : '$x';
      return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
    }

    String _segLabel(String raw) {
      final v = raw.trim().toLowerCase();
      if (v == 'zahnarzt' || v == t.segment_dentist.toLowerCase()) return t.segment_dentist;
      if (v == 'zahntechnik' || v == t.segment_lab.toLowerCase()) return t.segment_lab;
      return raw;
    }

    Widget row(String l, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 170,
                child: Text(l, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Expanded(child: Text(v.isEmpty ? '—' : v)),
            ],
          ),
        );

    return AlertDialog(
      title: Text('${t.details} – ${c.ticket}'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (payload.isEmpty) ...[
                Text(t.no_details),
              ] else ...[
                if ((payload['segment'] ?? '').toString().isNotEmpty)
                  row(t.segment, _segLabel((payload['segment'] ?? '').toString())),
                row(t.article, (payload['article'] ?? '').toString()),
                row(t.batch, (payload['batch'] ?? '').toString()),
                row(t.quantity, (payload['qty'] ?? '').toString()),
                row(t.expiry, (payload['expiry'] ?? '').toString()),
                row(t.description, (payload['desc'] ?? '').toString()),
                if ((payload['returned'] ?? '').toString().isNotEmpty)
                  row(t.returned, (payload['returned'] ?? '').toString()),
                if ((payload['handling'] ?? '').toString().isNotEmpty)
                  row(t.handling, (payload['handling'] ?? '').toString()),
                if ((payload['applied'] ?? '').toString().isNotEmpty)
                  row(t.applied, (payload['applied'] ?? '').toString()),
                if ((payload['injury'] ?? '').toString().isNotEmpty)
                  row(t.injury, (payload['injury'] ?? '').toString()),
                if ((payload['injuryDesc'] ?? '').toString().trim().isNotEmpty)
                  row(t.injury_desc, (payload['injuryDesc'] ?? '').toString()),
                if ((payload['customerName'] ?? '').toString().isNotEmpty)
                  row(t.customer_label, (payload['customerName'] ?? '').toString()),
                if ((payload['country'] ?? '').toString().isNotEmpty)
                  row(t.country_label, (payload['country'] ?? '').toString()),
              ],
              const SizedBox(height: 8),
              // Timestamps unten zusammengefasst
              row(t.created, _fmtLocal(c.createdAt)),
              if (c.updatedAt.millisecondsSinceEpoch > 0)
                row(t.updated, _fmtLocal(c.updatedAt)),
              if ((c.internalNo ?? '').toString().isNotEmpty)
                row(t.internal_no_label, c.internalNo!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.close)),
      ],
    );
  }
}

// ------------------- kleine UI-Helfer -------------------

class _ChipOutlined extends StatelessWidget {
  final String text;
  final Color color;
  const _ChipOutlined({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoChip({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
