import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

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
        elevation: 0,
      ),
      backgroundColor: colorScheme.surfaceVariant.withOpacity(0.25),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 18,
                    spreadRadius: 1,
                    offset: const Offset(0, 12),
                    color: Colors.black.withOpacity(0.06),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 26),
                  child: DefaultTextStyle(
                    style: (theme.textTheme.bodyMedium ??
                            const TextStyle(fontSize: 14))
                        .copyWith(
                      fontSize: 14,
                      height: 1.5,
                    ),
                    child: SelectionArea(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header / Kopfbereich
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color:
                                      colorScheme.primary.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  Icons.apartment_rounded,
                                  color: colorScheme.primary,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'DFS-Diamon GmbH',
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
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

                          const SizedBox(height: 18),
                          Divider(
                            color:
                                colorScheme.outlineVariant.withOpacity(0.6),
                          ),
                          const SizedBox(height: 14),

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
      padding: const EdgeInsets.only(bottom: 16),
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
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SelectableText(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
