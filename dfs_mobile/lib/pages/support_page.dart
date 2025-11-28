// lib/pages/support_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dfs_mobile/web_compat/html_stub.dart'
  if (dart.library.html) 'package:dfs_mobile/web_compat/html_web.dart' as html;
import '../widgets/legal_footer.dart';

class SupportPage extends StatefulWidget {
  final ApiClient api;
  const SupportPage({super.key, required this.api});
  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  final _msg = TextEditingController();
  String _cat = 'general'; // stabile Codes fürs Backend
  bool _consent = false;
  bool _busy = false;

  // Stabile Kategorien (werden lokalisiert dargestellt)
  static const _cats = <String>[
    'general',
    'complaint',
    'technical',
    'account',
    'privacy',
    'feedback',
    'improve',
  ];

  String _catLabel(AppLocalizations t, String code) {
    switch (code) {
      case 'general':   return t.supportCatGeneral;
      case 'complaint': return t.supportCatComplaintIssue;
      case 'technical': return t.supportCatTechnical;
      case 'account':   return t.supportCatAccount;
      case 'privacy':   return t.supportCatPrivacy;
      case 'feedback':  return t.supportCatFeedback;
      case 'improve':   return t.supportCatSuggestion;
      default:          return code;
    }
  }

  // ---- Einheitlicher Datenschutz-Opener (In-App mit Fallback) ----
  void _openPrivacyPage(BuildContext context) {
    try {
      Navigator.of(context).pushNamed('/legal/privacy');
    } catch (_) {
      try { html.window.open('https://dfs-diamon.de/de/datenschutz', '_blank'); } catch (_) {}
    }
  }

  // Mappt UI-Codes auf vom Backend akzeptierte Kategorien
  String _mapCategoryForApi(String code) {
    switch (code) {
      case 'general':
      case 'complaint':
      case 'technical':
      case 'account':
      case 'privacy':
      case 'feedback':
      case 'improve':
        return code;
      default:
        return 'other';       // robuste Absicherung
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: t.back,
        ),
        title: Text(t.supportTitle),
      ),
      body: Container(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.2),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.primaryContainer.withOpacity(0.9),
                        Theme.of(context).colorScheme.secondaryContainer,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer
                                  .withOpacity(0.08),
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Icon(
                              Icons.support_agent,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.supportTitle,
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  t.supportCatSuggestion,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer
                                            .withOpacity(0.85),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            avatar: const Icon(Icons.timer, size: 18),
                            label: Text(t.supportCatTechnical),
                          ),
                          Chip(
                            avatar: const Icon(Icons.lock_person, size: 18),
                            label: Text(t.supportCatPrivacy),
                          ),
                          Chip(
                            avatar: const Icon(Icons.feedback_outlined, size: 18),
                            label: Text(t.supportCatFeedback),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.yourMessage,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _cat,
                          items: _cats
                              .map((c) => DropdownMenuItem<String>(
                                    value: c,
                                    child: Text(_catLabel(t, c)),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _cat = v ?? 'general'),
                          decoration: InputDecoration(
                            labelText: t.category,
                            filled: true,
                            fillColor:
                                Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.35),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _msg,
                          minLines: 6,
                          maxLines: 16,
                          decoration: InputDecoration(
                            labelText: t.yourMessage,
                            filled: true,
                            fillColor:
                                Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.35),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox.adaptive(
                              value: _consent,
                              onChanged: (v) => setState(() => _consent = v ?? false),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Pflichttext (unverändert aus L10n)
                                  Text(t.supportConsentText),

                                  // Interner Link zur Datenschutz-Seite (mit gleichem Icon wie in register_page)
                                  const SizedBox(height: 4),
                                  InkWell(
                                    onTap: () => _openPrivacyPage(context),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.privacy_tip_outlined, size: 18),
                                        const SizedBox(width: 6),
                                        Text(
                                          t.privacy_view,
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.primary,
                                            decoration: TextDecoration.underline,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                icon: const Icon(Icons.send),
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        if (_msg.text.trim().isEmpty) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(t.message_required)),
                                          );
                                          return;
                                        }
                                        if (!_consent) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(t.privacy_required)),
                                          );
                                          return;
                                        }
                                        setState(() => _busy = true);
                                        try {
                                          await widget.api.sendSupport(
                                            category: _mapCategoryForApi(_cat),
                                            message: _msg.text.trim(),
                                            consent: true,
                                          );
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(t.message_sent)),
                                          );
                                          Navigator.of(context).pop();
                                        } catch (e) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('${t.error}: $e')),
                                            );
                                          }
                                        } finally {
                                          if (mounted) setState(() => _busy = false);
                                        }
                                      },
                                child: _busy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : Text(t.send),
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(t.cancel),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: LegalFooter(api: widget.api),
    );
  }
}
