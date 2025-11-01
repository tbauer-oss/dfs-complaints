// lib/widgets/status_badge.dart
import 'package:flutter/material.dart';

Color _statusColor(int s, {String? decision}) {
  switch (s) {
    case 1: return Colors.blue;           // gesendet
    case 2: return Colors.yellow.shade700;// in Bearbeitung
    case 3: return Colors.orange;         // Rückfrage
    case 4:
      if (decision == 'rejected') return Colors.red;
      if (decision == 'accepted') return Colors.lightGreen;
      return Colors.grey;
    case 5: return Colors.amber;          // Nacharbeit
    case 6: return Colors.green;          // abgeschlossen
    default: return Colors.grey;
  }
}

String _statusText(int s, {String? decision}) {
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

class StatusBadge extends StatelessWidget {
  final int status;
  final String? decision;
  const StatusBadge({super.key, required this.status, this.decision});

  @override
  Widget build(BuildContext context) {
    final c = _statusColor(status, decision: decision);
    final t = _statusText(status, decision: decision);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        border: Border.all(color: c, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w600)),
    );
  }
}
