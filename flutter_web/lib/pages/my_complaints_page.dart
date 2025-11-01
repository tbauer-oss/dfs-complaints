// lib/pages/my_complaints_page.dart
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _busy = true; _err = null; });
    try {
      final list = await widget.api.complaintList();
      // Neueste zuerst (nach updatedAt, dann createdAt)
      list.sort((a, b) {
        final ma = (a.updatedAt.millisecondsSinceEpoch > 0
                ? a.updatedAt.millisecondsSinceEpoch
                : a.createdAt.millisecondsSinceEpoch) ??
            0;
        final mb = (b.updatedAt.millisecondsSinceEpoch > 0
                ? b.updatedAt.millisecondsSinceEpoch
                : b.createdAt.millisecondsSinceEpoch) ??
            0;
        return mb.compareTo(ma);
      });
      setState(() => _items = list);
    } catch (e) {
      final msg = '$e';
      setState(() => _err = msg);
      if (mounted && msg.contains('401')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sitzung ungültig. Bitte neu anmelden.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fmt(DateTime dt) => dt.toLocal().toString();

  // Neutrale Status-Texte – vermeiden fehlende L10n-Keys
  String _statusText(int s, String? decision) {
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

  bool _canShowReport(Complaint c) {
    final link = c.reportLink;
    if (link == null || link.isEmpty) return false;
    if (c.status == 6) return true;                           // abgeschlossen
    if (c.status == 4 && c.decision == 'rejected') return true; // abgelehnt
    return false;
  }

  void _logoutAndLeave() {
    widget.api.logout();
    // Versuchen zur Start-/Loginseite zurückzukehren
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else {
      // Fallback: Seite neu laden (Web)
      html.window.location.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Zurück',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Meine Reklamationen'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Aktualisieren',
            onPressed: _busy ? null : _load,
          ),
          // Abmelden-Button (Kundenbereich)
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Abmelden',
            onPressed: _logoutAndLeave,
          ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _err != null
              ? Center(child: Text(_err!))
              : _items.isEmpty
                  ? Center(child: Text(t.none_complaints)) // vorhandener Key
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final c = _items[i];
                          final statusText = _statusText(c.status, c.decision);
                          final statusColor = _statusColor(c.status, c.decision);
                          final showReport = _canShowReport(c);

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            title: Text(
                              c.ticket,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Erstellt: ${_fmt(c.createdAt)}'),
                                if (c.updatedAt.millisecondsSinceEpoch > 0)
                                  Text('Aktualisiert: ${_fmt(c.updatedAt)}'),
                                if (showReport) ...[
                                  const SizedBox(height: 6),
                                  InkWell(
                                    onTap: () {
                                      final link = c.reportLink!;
                                      html.window.open(link, '_blank');
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
                                color: statusColor.withOpacity(0.12),
                                border: Border.all(color: statusColor, width: 1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
