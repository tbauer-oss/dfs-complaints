// lib/pages/my_complaints_page.dart
import 'dart:async';
import 'dart:html' as html; // nur Web – für Link-Öffnen
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../models/complaint.dart';
import '../l10n/app_localizations.dart';

class MyComplaintsPage extends StatefulWidget {
  final ApiClient api;
  const MyComplaintsPage({super.key, required this.api});

  @override
  State<MyComplaintsPage> createState() => _MyComplaintsPageState();
}

class _MyComplaintsPageState extends State<MyComplaintsPage> {
  bool _busy = false;
  String? _err;
  List<Complaint> _items = const [];

  Timer? _poll; // ← Auto-Refresh

  @override
  void initState() {
    super.initState();
    _load(); // initial
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
      // in dein Modell mappen (falls Complaint.fromJson existiert)
      final list = raw.map(Complaint.fromJson).toList(growable: false);

      // Neueste zuerst (nach updatedAt, dann createdAt)
      list.sort((a, b) {
        final ta = (a.updatedAt.millisecondsSinceEpoch > 0
            ? a.updatedAt.millisecondsSinceEpoch
            : a.createdAt.millisecondsSinceEpoch);
        final tb = (b.updatedAt.millisecondsSinceEpoch > 0
            ? b.updatedAt.millisecondsSinceEpoch
            : b.createdAt.millisecondsSinceEpoch);
        return tb.compareTo(ta);
      });

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

  String _fmt(DateTime dt) => dt.toLocal().toString();

  // Lokalisierte Status-Texte
  String _statusTextLocalized(AppLocalizations t, int s, String? decision) {
    switch (s) {
      case 1:
        return t.status_sent; // gesendet
      case 2:
        return t.status_in_progress; // in Bearbeitung
      case 3:
        return t.status_question; // Rückfrage erforderlich
      case 4:
        if (decision == 'rejected') return t.status_rejected; // abgelehnt
        if (decision == 'accepted') return t.status_accepted; // angenommen
        return t.status_decision; // Entscheidung
      case 5:
        return t.status_rework; // in Nacharbeit
      case 6:
        return t.status_closed; // abgeschlossen
      default:
        return t.status_unknown; // unbekannt
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

  // Entscheidung als Text (de/en-ready, mit robustem Fallback)
  String _decisionText(String? d) {
    switch ((d ?? '').trim().toLowerCase()) {
      case 'accepted':
        return 'Angenommen';
      case 'rejected':
        return 'Abgelehnt';
      default:
        return '—';
    }
  }

  Color _decisionColor(String? d) {
    switch ((d ?? '').trim().toLowerCase()) {
      case 'accepted':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // Kompaktes Chip-Widget für die Entscheidung
  Widget _decisionChip(String? decision) {
    final c = _decisionColor(decision);
    return Chip(
      label: Text('Entscheidung: ${_decisionText(decision)}'),
      backgroundColor: c.withOpacity(0.12),
      side: BorderSide(color: c, width: 1),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: t.back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(t.my_complaints_title),
        actions: [
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
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _err != null
              ? Center(child: Text(_err!))
              : _items.isEmpty
                  ? Center(child: Text(t.none_complaints))
                  : RefreshIndicator(
                      onRefresh: () => _load(silent: false),
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final c = _items[i];
                          final statusText =
                              _statusTextLocalized(t, c.status, c.decision);
                          final statusColor =
                              _statusColor(c.status, c.decision);
                          final reportLink = (c.reportLink ?? '').trim();
                          final canOpenReport = _canOpenReportLink(c);

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            title: Text(
                              c.ticket,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${t.created}: ${_fmt(c.createdAt)}'),
                                if (c.updatedAt.millisecondsSinceEpoch > 0)
                                  Text('${t.updated}: ${_fmt(c.updatedAt)}'),
                                if (canOpenReport) ...[
                                  const SizedBox(height: 6),
                                  TextButton.icon(
                                    onPressed: () =>
                                        html.window.open(reportLink, '_blank'),
                                    icon: const Icon(Icons.open_in_new),
                                    label: Text(t.report_open),
                                  ),
                                ],
                              ],
                            ),
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // Status-Badge („Status: …“)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.12),
                                    border: Border.all(color: statusColor, width: 1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${t.status}: $statusText',
                                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
                                  ),
                                ),

                                // Decision-Badge (nur wenn gesetzt)
                                if ((c.decision ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Builder(
                                    builder: (_) {
                                      final dec = c.decision!; // hier sicher, weil oben geprüft
                                      final decText = dec == 'accepted' ? t.decision_accepted : t.decision_rejected;
                                      final decColor = dec == 'accepted' ? Colors.green : Colors.red;
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: decColor.withOpacity(0.12),
                                          border: Border.all(color: decColor, width: 1),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '${t.decision}: $decText',
                                          style: TextStyle(color: decColor, fontWeight: FontWeight.w600),
                                        ),
                                      );
                                    },
                                  ),
                                ],,

                                // Details-Button
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
                          );
                        },
                      ),
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
    final payload = c.payload ?? const {};
    Widget row(String l, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  width: 160,
                  child: Text(l,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
              Expanded(child: Text(v.isEmpty ? '—' : v)),
            ],
          ),
        );

    return AlertDialog(
      title: Text('${t.details} – ${c.ticket}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (payload.isEmpty)
                Text(t.no_details) // lokalisierte Fallbackmeldung
              else ...[
                row(t.segment, (payload['segment'] ?? '').toString()),
                row(t.article, (payload['article'] ?? '').toString()),
                row(t.batch, (payload['batch'] ?? '').toString()),
                row(t.quantity, (payload['qty'] ?? '').toString()),
                row(t.expiry, (payload['expiry'] ?? '').toString()),
                row(t.description, (payload['desc'] ?? '').toString()),
              ],
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
