// lib/widgets/pdf_view_stub.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';

/// Stub für Nicht-Web: öffnet die PDF extern und zeigt einen Hinweis.
class PdfInAppPage extends StatelessWidget {
  final String url;
  final String title;
  const PdfInAppPage({super.key, required this.url, required this.title});

  Future<void> _openExternal(BuildContext context) async {
    final t = AppLocalizations.of(context)!;
    final uri = Uri.tryParse(url);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.catalog_open_error)),
      );
      return;
    }

    final success = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.catalog_open_error)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.picture_as_pdf_outlined, size: 48),
              const SizedBox(height: 12),
              Text(
                t.catalog_viewer_unavailable,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _openExternal(context),
                icon: const Icon(Icons.open_in_new),
                label: Text(t.catalog_open_external),
              ),
              const SizedBox(height: 12),
              SelectableText(
                url,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
