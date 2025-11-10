import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'web_compat/html_stub.dart'
  if (dart.library.html) 'web_compat/html_web.dart' as html;
import '../l10n/app_localizations.dart';

class LegalPrivacyPage extends StatelessWidget {
  const LegalPrivacyPage({super.key});

  void _openLink(String url) {
    try { html.window.open(url, '_blank'); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    TextSpan linkSpan(String text, String url) => TextSpan(
      text: text,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
      recognizer: TapGestureRecognizer()..onTap = () => _openLink(url),
    );

    return Scaffold(
      appBar: AppBar(title: Text(t.legal_privacy_title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: SingleChildScrollView(
              child: DefaultTextStyle(
                style: theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.legal_privacy_heading,
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),

                    Text(t.legal_privacy_0_title,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    RichText(text: TextSpan(
                      style: theme.textTheme.bodyMedium,
                      children: [
                        TextSpan(text: t.legal_privacy_0_text_prefix),
                        linkSpan('dfs-diamon.de/de/datenschutz', 'https://dfs-diamon.de/de/datenschutz'),
                        const TextSpan(text: '.'),
                      ],
                    )),
                    const SizedBox(height: 16),

                    _section(theme, t.legal_privacy_1_title, t.legal_privacy_1_text),
                    _section(theme, t.legal_privacy_2_title, t.legal_privacy_2_text),
                    _section(theme, t.legal_privacy_3_title, t.legal_privacy_3_text),
                    _section(theme, t.legal_privacy_4_title, t.legal_privacy_4_text),
                    _section(theme, t.legal_privacy_5_title, t.legal_privacy_5_text),
                    _section(theme, t.legal_privacy_6_title, t.legal_privacy_6_text),
                    _section(theme, t.legal_privacy_7_title, t.legal_privacy_7_text),
                    _section(theme, t.legal_privacy_8_title, t.legal_privacy_8_text),
                    _section(theme, t.legal_privacy_9_title, t.legal_privacy_9_text),
                    _section(theme, t.legal_privacy_10_title, t.legal_privacy_10_text),
                    _section(theme, t.legal_privacy_11_title, t.legal_privacy_11_text),
                    _section(theme, t.legal_privacy_12_title, t.legal_privacy_12_text),
                    _section(theme, t.legal_privacy_13_title, t.legal_privacy_13_text),
                    _section(theme, t.legal_privacy_14_title, t.legal_privacy_14_text),

                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Icon(Icons.link, size: 18),
                        const SizedBox(width: 8),
                        RichText(
                          text: TextSpan(
                            style: theme.textTheme.bodyMedium,
                            children: [
                              TextSpan(text: '${t.legal_privacy_link_label} '),
                              linkSpan('dfs-diamon.de/de/datenschutz', 'https://dfs-diamon.de/de/datenschutz'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('${t.legal_privacy_stand_prefix} November 2025',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(ThemeData theme, String title, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(text),
        ],
      ),
    );
  }
}
