// lib/pages/support_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../web_compat/html_stub.dart'
  if (dart.library.html) '../web_compat/html_web.dart' as html;
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
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.18),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
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
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(14),
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
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 4),
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
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _QuickCategoryButton(
                            icon: Icons.build_circle_outlined,
                            label: t.supportCatTechnical,
                            onTap: () => setState(() => _cat = 'technical'),
                            selected: _cat == 'technical',
                          ),
                          _QuickCategoryButton(
                            icon: Icons.lock_person,
                            label: t.supportCatPrivacy,
                            onTap: () => setState(() => _cat = 'privacy'),
                            selected: _cat == 'privacy',
                          ),
                          _QuickCategoryButton(
                            icon: Icons.feedback_outlined,
                            label: t.supportCatFeedback,
                            onTap: () => setState(() => _cat = 'feedback'),
                            selected: _cat == 'feedback',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.yourMessage,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: _cat,
                          items: _cats
                              .map((c) => DropdownMenuItem<String>(
                                    value: c,
                                    child: Text(_catLabel(t, c)),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _cat = v ?? 'general'),
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: t.category,
                            isDense: true,
                            filled: true,
                            fillColor:
                                Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.35),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _msg,
                          minLines: 6,
                          maxLines: 16,
                          decoration: InputDecoration(
                            labelText: t.yourMessage,
                            isDense: true,
                            filled: true,
                            fillColor:
                                Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.35),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
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
                        const SizedBox(height: 12),
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
                                label: _busy
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

class _QuickCategoryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  const _QuickCategoryButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = selected
        ? theme.colorScheme.secondaryContainer
        : theme.colorScheme.surfaceVariant.withOpacity(0.35);
    final fg = selected
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? theme.colorScheme.secondary.withOpacity(0.5)
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
