import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dfs_mobile/web_compat/html_stub.dart'
  if (dart.library.html) 'package:dfs_mobile/web_compat/html_web.dart' as html;
import '../l10n/app_localizations.dart';

class LegalPrivacyPage extends StatelessWidget {
  const LegalPrivacyPage({super.key});

  void _openLink(String url) {
    try {
      html.window.open(url, '_blank');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    TextSpan linkSpan(String text, String url) => TextSpan(
          text: text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.primary,
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.w600,
          ),
          recognizer: TapGestureRecognizer()..onTap = () => _openLink(url),
        );

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header / Einleitung
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.privacy_tip_rounded,
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
                    t.legal_privacy_heading,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.legal_privacy_intro ??
                        'Nachfolgend finden Sie die Datenschutzhinweise zur Nutzung der DFS Complaint App.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.75),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),
        Divider(color: colorScheme.outlineVariant.withOpacity(0.6)),
        const SizedBox(height: 12),

        // 0. Vorbemerkung mit Link
        _sectionHeader(
          theme,
          index: '0.',
          title: t.legal_privacy_0_title,
        ),
        const SizedBox(height: 4),
        _sectionBox(
          theme,
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              children: [
                TextSpan(text: t.legal_privacy_0_text_prefix),
                linkSpan(
                  'dfs-diamon.de/de/datenschutz',
                  'https://dfs-diamon.de/de/datenschutz',
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 1. Verantwortlicher
        _simpleSection(
          theme,
          index: '1.',
          title: t.legal_privacy_1_title,
          text: t.legal_privacy_1_text,
        ),

        // 2. Datenschutzbeauftragter
        _simpleSection(
          theme,
          index: '2.',
          title: t.legal_privacy_2_title,
          text: t.legal_privacy_2_text,
        ),

        // 3. Datenarten mit Unterpunkten 3.1–3.5
        _sectionHeader(
          theme,
          index: '3.',
          title: t.legal_privacy_3_title,
        ),
        const SizedBox(height: 6),
        if (t.legal_privacy_3_1_title.isNotEmpty)
          _subSection(
            theme,
            subIndex: '3.1',
            title: t.legal_privacy_3_1_title,
            text: t.legal_privacy_3_1_text,
          ),
        if (t.legal_privacy_3_2_title.isNotEmpty)
          _subSection(
            theme,
            subIndex: '3.2',
            title: t.legal_privacy_3_2_title,
            text: t.legal_privacy_3_2_text,
          ),
        if (t.legal_privacy_3_3_title.isNotEmpty)
          _subSection(
            theme,
            subIndex: '3.3',
            title: t.legal_privacy_3_3_title,
            text: t.legal_privacy_3_3_text,
          ),
        if (t.legal_privacy_3_4_title.isNotEmpty)
          _subSection(
            theme,
            subIndex: '3.4',
            title: t.legal_privacy_3_4_title,
            text: t.legal_privacy_3_4_text,
          ),
        if (t.legal_privacy_3_5_title.isNotEmpty)
          _subSection(
            theme,
            subIndex: '3.5',
            title: t.legal_privacy_3_5_title,
            text: t.legal_privacy_3_5_text,
          ),
        const SizedBox(height: 14),

        // 4. Zwecke
        _simpleSection(
          theme,
          index: '4.',
          title: t.legal_privacy_4_title,
          text: t.legal_privacy_4_text,
        ),

        // 5. Rechtsgrundlagen
        _simpleSection(
          theme,
          index: '5.',
          title: t.legal_privacy_5_title,
          text: t.legal_privacy_5_text,
        ),

        // 6. Hosting / AV mit Unterpunkten 6.1–6.4
        _sectionHeader(
          theme,
          index: '6.',
          title: t.legal_privacy_6_title,
        ),
        const SizedBox(height: 6),
        if (t.legal_privacy_6_1_title.isNotEmpty)
          _subSection(
            theme,
            subIndex: '6.1',
            title: t.legal_privacy_6_1_title,
            text: t.legal_privacy_6_1_text,
          ),
        if (t.legal_privacy_6_2_title.isNotEmpty)
          _subSection(
            theme,
            subIndex: '6.2',
            title: t.legal_privacy_6_2_title,
            text: t.legal_privacy_6_2_text,
          ),
        if (t.legal_privacy_6_3_title.isNotEmpty)
          _subSection(
            theme,
            subIndex: '6.3',
            title: t.legal_privacy_6_3_title,
            text: t.legal_privacy_6_3_text,
          ),
        if (t.legal_privacy_6_4_title.isNotEmpty)
          _subSection(
            theme,
            subIndex: '6.4',
            title: t.legal_privacy_6_4_title,
            text: t.legal_privacy_6_4_text,
          ),
        const SizedBox(height: 14),

        // 7. Verarbeitung innerhalb der EU (inkl. TLS-Hinweis im Text)
        _simpleSection(
          theme,
          index: '7.',
          title: t.legal_privacy_7_title,
          text: t.legal_privacy_7_text,
        ),

        // 8. Cookies / Local Storage
        _simpleSection(
          theme,
          index: '8.',
          title: t.legal_privacy_8_title,
          text: t.legal_privacy_8_text,
        ),

        // 9. Uploads und Anhänge
        _simpleSection(
          theme,
          index: '9.',
          title: t.legal_privacy_9_title,
          text: t.legal_privacy_9_text,
        ),

        // 10. E-Mail-Kommunikation
        _simpleSection(
          theme,
          index: '10.',
          title: t.legal_privacy_10_title,
          text: t.legal_privacy_10_text,
        ),

        // 11. Löschfristen mit Unterpunkten 11.1–11.4
        _sectionHeader(
          theme,
          index: '11.',
          title: t.legal_privacy_11_title,
        ),
        const SizedBox(height: 6),
        if (t.legal_privacy_11_1_title.isNotEmpty)
          _subSection(
            theme,
            subIndex: '11.1',
            title: t.legal_privacy_11_1_title,
            text: t.legal_privacy_11_1_text,
          ),
        if (t.legal_privacy_11_2_title.isNotEmpty)
          _subSection(
            theme,
            subIndex: '11.2',
            title: t.legal_privacy_11_2_title,
            text: t.legal_privacy_11_2_text,
          ),
        if (t.legal_privacy_11_3_title.isNotEmpty)
          _subSection(
            theme,
            subIndex: '11.3',
            title: t.legal_privacy_11_3_title,
            text: t.legal_privacy_11_3_text,
          ),
        if (t.legal_privacy_11_4_title.isNotEmpty)
          _subSection(
            theme,
            subIndex: '11.4',
            title: t.legal_privacy_11_4_title,
            text: t.legal_privacy_11_4_text,
          ),
        const SizedBox(height: 14),

        // 12. Weitergabe an Dritte
        _simpleSection(
          theme,
          index: '12.',
          title: t.legal_privacy_12_title,
          text: t.legal_privacy_12_text,
        ),

        // 13. Automatisierte Entscheidungen / Profiling
        _simpleSection(
          theme,
          index: '13.',
          title: t.legal_privacy_13_title,
          text: t.legal_privacy_13_text,
        ),

        // 14. Rechte der betroffenen Personen
        _simpleSection(
          theme,
          index: '14.',
          title: t.legal_privacy_14_title,
          text: t.legal_privacy_14_text,
        ),

        // 15. Beschwerderecht
        _simpleSection(
          theme,
          index: '15.',
          title: t.legal_privacy_15_title,
          text: t.legal_privacy_15_text,
        ),

        // 16. Änderungen
        _simpleSection(
          theme,
          index: '16.',
          title: t.legal_privacy_16_title,
          text: t.legal_privacy_16_text,
        ),

        const SizedBox(height: 12),
        Divider(color: colorScheme.outlineVariant.withOpacity(0.6)),
        const SizedBox(height: 10),

        // Link zur Website-Datenschutzerklärung + Stand
        Row(
          children: [
            Icon(Icons.link_rounded, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyMedium,
                  children: [
                    TextSpan(text: '${t.legal_privacy_link_label} '),
                    linkSpan(
                      'dfs-diamon.de/de/datenschutz',
                      'https://dfs-diamon.de/de/datenschutz',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${t.legal_privacy_stand_prefix} November 2025',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(t.legal_privacy_title),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: DefaultTextStyle(
            style: (theme.textTheme.bodyMedium ??
                    const TextStyle(fontSize: 13))
                .copyWith(
              fontSize: 13.5, // nicht zu groß, aber gut lesbar
              height: 1.5,
            ),
            child: kIsWeb ? SelectionArea(child: content) : content,
          ),
        ),
      ),
    );
  }

  // ---------- Layout-Helfer ----------

  Widget _sectionHeader(
    ThemeData theme, {
    required String index,
    required String title,
  }) {
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: colorScheme.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            index,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionBox(ThemeData theme, {required Widget child}) {
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: child,
    );
  }

  Widget _simpleSection(
    ThemeData theme, {
    required String index,
    required String title,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(theme, index: index, title: title),
          const SizedBox(height: 4),
          _sectionBox(
            theme,
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _subSection(
    ThemeData theme, {
    required String subIndex,
    required String title,
    required String text,
  }) {
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subIndex,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceVariant.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text(
                    text,
                    style:
                        theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
