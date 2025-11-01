// lib/pages/my_complaints_page.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
  List<Complaint> _items = [];
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final list = await widget.api.complaintList();
      // Neueste zuerst: zuerst updatedAt, fallback createdAt
      list.sort((a, b) {
        final ma = b.updatedAt.millisecondsSinceEpoch.compareTo(
            a.updatedAt.millisecondsSinceEpoch);
        if (ma != 0) return ma;
        return b.createdAt.millisecondsSinceEpoch
            .compareTo(a.createdAt.millisecondsSinceEpoch);
      });
      setState(() => _items = list);
    } catch (e) {
      setState(() {
        _items = [];
        _err = '$e';
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  // ---------- Status-Darstellung ----------
  String _statusText(int s, String? decision) {
    switch (s) {
      case 1:
        return 'gesendet';
      case 2:
        return 'in Bearbeitung';
      case 3:
        return 'Rückfrage erforderlich';
      case 4:
        if (decision == 'rejected') return 'abgelehnt';
        if (decision == 'accepted') return 'angenommen';
        return 'Entscheidung';
      case 5:
        return 'in Nacharbeit';
      case 6:
        return 'abgeschlossen';
      default:
        return 'unbekannt';
    }
  }

  Color _statusColor(int s, String? decision) {
    switch (s) {
      case 1:
        return Colors.blue; // gesendet
      case 2:
        return Colors.amber.shade700; // in Bearbeitung
      case 3:
        return Colors.orange; // Rückfrage
      case 4:
        if (decision == 'rejected') return Colors.red;
        if (decision == 'accepted') return Colors.lightGreen;
        return Colors.grey;
      case 5:
        return Colors.amber; // Nacharbeit
      case 6:
        return Colors.green; // abgeschlossen
      default:
        return Colors.grey;
    }
  }

  bool _canShowReport(Complaint c) {
    final link = c.reportLink;
    if (link == null || link.isEmpty) return false;
    if (c.status == 6) return true; // abgeschlossen
    if (c.status == 4 && c.decision == 'rejected') return true; // abgelehnt => abgeschlossen (rot)
    return false;
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '';
    final d = dt.toLocal();
    // knapp & robust; gerne später mit intl schöner formatieren
    return '${d.year.toString().padLeft(4, '0')}-'
           '${d.month.toString().padLeft(2, '0')}-'
           '${d.day.toString().padLeft(2, '0')} '
           '${d.hour.toString().padLeft(2, '0')}:'
           '${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    if (_busy) return const Center(child: CircularProgressIndicator());
    if (_err != null) return Center(child: Text(_err!));
    if (_items.isEmpty) return Center(child: Text(t.none_complaints));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final c = _items[i];

          final article =
              (c.payload?['article'] ?? c.payload?['Artikel'] ?? '').toString();
          final title = article.isNotEmpty ? '${c.ticket} – $article' : c.ticket;

          final badgeText = _statusText(c.status, c.decision);
          final badgeColor = _statusColor(c.status, c.decision);
          final showReport = _canShowReport(c);

          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Erstellt: ${_fmtDate(c.createdAt)}'),
                if (showReport) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final link = c.reportLink!;
                      final uri = Uri.tryParse(link);
                      if (uri != null) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    child: const Text(
                      'Reklamationsbericht öffnen',
                      style: TextStyle(
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.12),
                border: Border.all(color: badgeColor, width: 1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                badgeText,
                style: TextStyle(color: badgeColor, fontWeight: FontWeight.w600),
              ),
            ),
          );
        },
      ),
    );
  }
}
