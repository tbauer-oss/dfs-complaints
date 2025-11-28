// lib/widgets/status_badge.dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

Color _statusColor(int s, {String? decision}) {
  switch (s) {
    case 1: return Colors.blue;            // submitted
    case 2: return Colors.yellow.shade700; // in progress
    case 3: return Colors.orange;          // inquiry
    case 4: return Colors.amber;           // rework
    case 5: return Colors.green;           // done
    default: return Colors.grey;
  }
}

class StatusBadge extends StatelessWidget {
  final int status;          // 1..6
  final String? decision;    // 'accepted' | 'rejected' | null

  const StatusBadge({super.key, required this.status, this.decision});

  String _statusText(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    switch (status) {
      case 1: return t.statusSubmitted;                 // gesendet
      case 2: return t.statusInProgress;                // in Bearbeitung
      case 3: return t.statusInquiryRequired;           // Rückfrage erforderlich
      case 4: return t.statusRework;                    // in Nacharbeit
      case 5: return t.statusClosed;                    // abgeschlossen
      default: return t.statusUnknown;                  // unbekannt
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _statusColor(status, decision: decision);
    final label = _statusText(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        border: Border.all(color: c, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600)),
    );
  }
}
