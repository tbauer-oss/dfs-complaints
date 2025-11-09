// lib/pages/support_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';
import 'dart:html' as html;
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                value: _cat,
                items: _cats
                    .map((c) => DropdownMenuItem<String>(
                          value: c,
                          child: Text(_catLabel(t, c)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _cat = v ?? 'general'),
                decoration: InputDecoration(labelText: t.category),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _msg,
                minLines: 6,
                maxLines: 16,
                decoration: InputDecoration(
                  labelText: t.yourMessage,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
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
                  FilledButton(
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
                                category: _cat,
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
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(t.cancel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: LegalFooter(api: widget.api),
    );
  }
}
