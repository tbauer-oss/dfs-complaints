import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class LegalImprintPage extends StatelessWidget {
  const LegalImprintPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    Widget section(String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SelectableText(body, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(t.imprint_title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('DFS-Diamon GmbH', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            section(t.imprint_publisher_title, t.imprint_publisher_body),
            section(t.imprint_register_title, t.imprint_register_body),
            section(t.imprint_disclaimer_title, t.imprint_disclaimer_body),
            section(t.imprint_copyright_title, t.imprint_copyright_body),
            section(t.imprint_odr_title, t.imprint_odr_body),
          ],
        ),
      ),
    );
  }
}
