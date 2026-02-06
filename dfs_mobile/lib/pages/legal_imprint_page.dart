import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class LegalImprintPage extends StatelessWidget {
  const LegalImprintPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.imprint_title),
        centerTitle: true,
      ),
      backgroundColor: colorScheme.surfaceVariant.withOpacity(0.25),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 14,
                      spreadRadius: 1,
                      offset: const Offset(0, 8),
                      color: Colors.black.withOpacity(0.06),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                    child: DefaultTextStyle(
                      style: (theme.textTheme.bodyMedium ??
                              const TextStyle(fontSize: 13))
                          .copyWith(
                        fontSize: 13.5,
                        height: 1.5,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header / Kopfbereich
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color:
                                      colorScheme.primary.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.apartment_rounded,
                                  color: colorScheme.primary,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'DFS-Diamon GmbH',
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      t.imprint_subtitle ??
                                          'Impressum und Anbieterkennzeichnung für die DFS Complaint App.',
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: colorScheme.onSurface
                                            .withOpacity(0.75),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),
                          Divider(
                            color:
                                colorScheme.outlineVariant.withOpacity(0.6),
                          ),
                          const SizedBox(height: 12),

                          // Sektionen
                          _section(
                            context,
                            icon: Icons.info_outline_rounded,
                            title: t.imprint_publisher_title,
                            body: t.imprint_publisher_body,
                          ),
                          _section(
                            context,
                            icon: Icons.article_outlined,
                            title: t.imprint_register_title,
                            body: t.imprint_register_body,
                          ),
                          _section(
                            context,
                            icon: Icons.gavel_outlined,
                            title: t.imprint_disclaimer_title,
                            body: t.imprint_disclaimer_body,
                          ),
                          _section(
                            context,
                            icon: Icons.copyright_outlined,
                            title: t.imprint_copyright_title,
                            body: t.imprint_copyright_body,
                          ),
                          _section(
                            context,
                            icon: Icons.public_outlined,
                            title: t.imprint_odr_title,
                            body: t.imprint_odr_body,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant.withOpacity(0.20),
              borderRadius: BorderRadius.circular(10),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: SelectableText(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
