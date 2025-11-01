import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../models/complaint.dart';

class MyComplaintsPage extends StatefulWidget {
  final ApiClient api;
  const MyComplaintsPage({super.key, required this.api});
  @override
  State<MyComplaintsPage> createState() => _MyComplaintsPageState();
}

class _MyComplaintsPageState extends State<MyComplaintsPage> {
  List<Complaint> items = [];
  bool busy = false;
  String? err;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() { busy = true; err = null; });
    try {
      final raw = await widget.api.complaintListRaw();
      items = raw.map((j) => Complaint.fromJson(j)).toList();
      // neueste zuerst
      items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      err = '$e';
      // KEIN logout() hier – nur Hinweis
      if (mounted && err!.contains('unauthorized')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sitzung prüfen: Bitte Seite neu laden oder erneut öffnen.')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ---------- Status ----------
  String _statusText(AppLocalizations t, int s, String? decision) {
    switch (s) {
      case 1: return t.status_sent;
      case 2: return t.status_inprogress;
      case 3: return t.status_question;
      case 4:
        if (decision == 'rejected') return t.status_rejected;
        if (decision == 'accepted') return t.status_accepted;
        return t.status_decision;
      case 5: return t.status_rework;
      case 6: return t.status_done;
      default: return t.status_unknown;
    }
  }

  Color _statusColor(int s, String? decision) {
    switch (s) {
      case 1: return Colors.blue;                // gesendet
      case 2: return Colors.orange;              // in Bearbeitung
      case 3: return Colors.amber;               // Rückfrage
      case 4:
        if (decision == 'rejected') return Colors.red;
        if (decision == 'accepted') return Colors.lightGreen;
        return Colors.grey;
      case 5: return Colors.deepOrange;          // Nacharbeit
      case 6: return Colors.green;               // abgeschlossen
      default: return Colors.grey;
    }
  }

  String _fmt(DateTime dt) => dt.toLocal().toString();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.my_complaints),
        automaticallyImplyLeading: true, // zeigt den Zurück-Pfeil
      ),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : err != null
              ? Center(child: Text(err!))
              : items.isEmpty
                  ? Center(child: Text(t.none_complaints))
                  : RefreshIndicator(
                      onRefresh: load,
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final c = items[i];
                          final badgeText  = _statusText(t, c.status, c.decision);
                          final badgeColor = _statusColor(c.status, c.decision);
                          final title = c.articleLabel.isNotEmpty
                              ? '${c.ticket} – ${c.articleLabel}'
                              : c.ticket;

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${t.created}: ${_fmt(c.createdAt)}'),
                                if (c.updatedAt.isAfter(c.createdAt))
                                  Text('${t.updated}: ${_fmt(c.updatedAt)}'),
                                if (c.reportLink != null && c.reportLink!.isNotEmpty && (c.status == 6 || (c.status == 4 && c.decision == 'rejected')))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      t.open_report_hint,
                                      style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                                    ),
                                  ),
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
                            onTap: () {
                              // optional: Detailansicht / Report öffnen
                              final link = c.reportLink;
                              if (link != null && link.isNotEmpty && (c.status == 6 || (c.status == 4 && c.decision == 'rejected'))) {
                                // Für Web genügt Navigation per Window:
                                // ignore: unsafe_html
                                html.window.open(link, '_blank');
                              }
                            },
                          );
                        },
                      ),
                    ),
    );
  }
}
