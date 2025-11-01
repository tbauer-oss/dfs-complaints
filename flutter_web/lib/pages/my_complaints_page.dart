// lib/pages/my_complaints_page.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/client.dart';
import '../models/complaint.dart';

class MyComplaintsPage extends StatefulWidget {
  final ApiClient api;
  const MyComplaintsPage({super.key, required this.api});
  @override
  State<MyComplaintsPage> createState() => _MyComplaintsPageState();
}

class _MyComplaintsPageState extends State<MyComplaintsPage> {
  List<Complaint> items = <Complaint>[];
  bool busy = false;
  String? err;

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final list = await widget.api.complaintList();
      list.sort((a, b) => (b.updatedAt.millisecondsSinceEpoch)
          .compareTo(a.updatedAt.millisecondsSinceEpoch));
      items = list;
      err = null;
    } catch (e) {
      err = '$e';
      items = <Complaint>[];
    } finally {
      setState(() => busy = false);
    }
  }

  String _statusText(int? s, String? decision) {
    switch (s) {
      case 1: return 'gesendet';
      case 2: return 'in Bearbeitung';
      case 3: return 'Rückfrage erforderlich';
      case 4: return decision == 'rejected' ? 'abgelehnt' : (decision == 'accepted' ? 'angenommen' : 'Entscheidung');
      case 5: return 'in Nacharbeit';
      case 6: return 'abgeschlossen';
      default: return 'unbekannt';
    }
  }

  Color _statusColor(int? s, String? decision) {
    switch (s) {
      case 1: return Colors.blue;
      case 2: return Colors.yellow.shade700;
      case 3: return Colors.orange;
      case 4: return decision == 'rejected' ? Colors.red : (decision == 'accepted' ? Colors.lightGreen : Colors.grey);
      case 5: return Colors.amber;
      case 6: return Colors.green;
      default: return Colors.grey;
    }
  }

  bool _canShowReport(Complaint c) {
    if (c.reportLink == null || c.reportLink!.isEmpty) return false;
    if (c.status == 6) return true;
    if (c.status == 4 && c.decision == 'rejected') return true;
    return false;
  }

  String _fmtDate(DateTime dt) => dt.toLocal().toString();

  Future<void> _openReport(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bericht konnte nicht geöffnet werden.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
        title: const Text('Meine Reklamationen'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: busy ? null : load),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Schließen')),
        ],
      ),
      body: Builder(
        builder: (_) {
          if (busy) return const Center(child: CircularProgressIndicator());
          if (err != null) return Center(child: Text(err!));
          if (items.isEmpty) return const Center(child: Text('Keine Reklamationen vorhanden.'));

          return RefreshIndicator(
            onRefresh: load,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final c = items[i];
                final badgeText  = _statusText(c.status, c.decision);
                final badgeColor = _statusColor(c.status, c.decision);
                final showReport = _canShowReport(c);

                final article = c.articleLabel; // aus optionalem payload

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  title: Text(article.isNotEmpty ? '${c.ticket} – $article' : c.ticket, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Erstellt: ${_fmtDate(c.createdAt)}'),
                      Text('Aktualisiert: ${_fmtDate(c.updatedAt)}'),
                      if (showReport) ...[
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () => _openReport(c.reportLink!),
                          child: const Text('Reklamationsbericht öffnen', style: TextStyle(decoration: TextDecoration.underline)),
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
                    child: Text(badgeText, style: TextStyle(color: badgeColor, fontWeight: FontWeight.w600)),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
