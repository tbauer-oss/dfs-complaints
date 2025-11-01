import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';

class MyComplaintsPage extends StatefulWidget {
  final ApiClient api;
  const MyComplaintsPage({super.key, required this.api});
  @override
  State<MyComplaintsPage> createState() => _MyComplaintsPageState();
}

class _MyComplaintsPageState extends State<MyComplaintsPage> {
  List<dynamic> items = [];
  bool busy = false;
  String? err;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      // NEU: singularer Endpoint + neues Client-API
      items = await widget.api.complaintList();
      err = null;
    } catch (e) {
      err = '$e';
      items = [];
    } finally {
      setState(() => busy = false);
    }
  }

  // ---------- Status Darstellung ----------
  String _statusText(int? s, String? decision) {
    switch (s) {
      case 1: return 'gesendet';
      case 2: return 'in Bearbeitung';
      case 3: return 'Rückfrage erforderlich';
      case 4:
        if (decision == 'rejected') return 'abgelehnt';
        if (decision == 'accepted') return 'angenommen';
        return 'Entscheidung';
      case 5: return 'in Nacharbeit';
      case 6: return 'abgeschlossen';
      default: return 'unbekannt';
    }
  }

  Color _statusColor(int? s, String? decision) {
    switch (s) {
      case 1: return Colors.blue;                  // gesendet
      case 2: return Colors.yellow.shade700;       // in Bearbeitung
      case 3: return Colors.orange;                // Rückfrage
      case 4:
        if (decision == 'rejected') return Colors.red;
        if (decision == 'accepted') return Colors.lightGreen;
        return Colors.grey;
      case 5: return Colors.amber;                 // Nacharbeit
      case 6: return Colors.green;                 // abgeschlossen
      default: return Colors.grey;
    }
  }

  bool _canShowReport(int? status, String? decision, String? link) {
    if (link == null || link.isEmpty) return false;
    if (status == 6) return true;                          // abgeschlossen
    if (status == 4 && decision == 'rejected') return true; // abgelehnt => rot, abgeschlossen
    return false;
  }

  String _fmtDate(int? ms) {
    if (ms == null || ms <= 0) return '';
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
      return dt.toString(); // bei Bedarf schöner formatieren
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    if (busy) return const Center(child: CircularProgressIndicator());
    if (err != null) return Center(child: Text(err!));
    if (items.isEmpty) return Center(child: Text(t.none_complaints));

    return RefreshIndicator(
      onRefresh: load,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          // Die API liefert Objekte mit Feldern:
          // ticket, status(1..6), decision('accepted'|'rejected'|null),
          // reportLink, createdAt, updatedAt, payload{article?...}
          final c = items[i] as Map<String, dynamic>;

          final ticket    = (c['ticket'] ?? '').toString();
          final status    = c['status'] is int ? c['status'] as int : int.tryParse('${c['status'] ?? ''}');
          final decision  = c['decision']?.toString();
          final report    = c['reportLink']?.toString();
          final createdAt = c['createdAt'] is int ? c['createdAt'] as int : int.tryParse('${c['createdAt'] ?? ''}');
          final payload   = (c['payload'] is Map) ? (c['payload'] as Map).cast<String, dynamic>() : <String, dynamic>{};
          final article   = (payload['article'] ?? payload['Artikel'] ?? '').toString();

          final badgeText  = _statusText(status, decision);
          final badgeColor = _statusColor(status, decision);
          final showReport = _canShowReport(status, decision, report);

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            title: Text(
              article.isNotEmpty ? '$ticket – $article' : ticket,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (createdAt != null) Text('Erstellt: ${_fmtDate(createdAt)}'),
                if (showReport) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final uri = Uri.parse(report!);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    child: const Text(
                      'Reklamationsbericht öffnen',
                      style: TextStyle(decoration: TextDecoration.underline),
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
