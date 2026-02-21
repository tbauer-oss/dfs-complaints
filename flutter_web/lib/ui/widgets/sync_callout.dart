import 'package:flutter/material.dart';

enum SyncCalloutKind { info, warning, success, error }

class SyncCallout extends StatelessWidget {
  final SyncCalloutKind kind;
  final String message;
  final Widget? action;

  const SyncCallout({super.key, required this.kind, required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg, icon) = switch (kind) {
      SyncCalloutKind.success => (scheme.primaryContainer, scheme.onPrimaryContainer, Icons.check_circle_outline),
      SyncCalloutKind.warning => (scheme.tertiaryContainer, scheme.onTertiaryContainer, Icons.warning_amber_rounded),
      SyncCalloutKind.error => (scheme.errorContainer, scheme.onErrorContainer, Icons.error_outline),
      SyncCalloutKind.info => (scheme.secondaryContainer, scheme.onSecondaryContainer, Icons.info_outline),
    };

    return Container(
      decoration: BoxDecoration(color: bg.withOpacity(0.6), borderRadius: BorderRadius.circular(10), border: Border.all(color: fg.withOpacity(0.18))),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        Icon(icon, size: 18, color: fg),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: fg))),
        if (action != null) action!,
      ]),
    );
  }
}
