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
        return 'other'; // robuste Absicherung
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
              _DiagnosticsWizardCard(
                onStart: () => _openWizard(t),
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
                                category: _mapCategoryForApi(_cat),  // << geändert
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

  Future<void> _openWizard(AppLocalizations t) async {
    final summary = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _DiagnosticsWizardDialog(t: t),
        ),
      ),
    );

    if (summary == null || summary.trim().isEmpty) return;

    setState(() {
      if (_cat == 'general') _cat = 'complaint';
      final existing = _msg.text.trim();
      _msg.text = existing.isEmpty ? summary : '$existing\n\n$summary';
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.supportWizardPrefillNotice)),
      );
    }
  }
}

class _DiagnosticsWizardCard extends StatelessWidget {
  final VoidCallback onStart;
  const _DiagnosticsWizardCard({required this.onStart});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology_alt_outlined, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.supportWizardCardTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.supportWizardCardDescription,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: onStart,
                  child: Text(t.supportWizardStart),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticsWizardDialog extends StatefulWidget {
  final AppLocalizations t;
  const _DiagnosticsWizardDialog({required this.t});

  @override
  State<_DiagnosticsWizardDialog> createState() => _DiagnosticsWizardDialogState();
}

class _DiagnosticsWizardDialogState extends State<_DiagnosticsWizardDialog> {
  final _product = TextEditingController();
  final _batch = TextEditingController();
  final _incident = TextEditingController();
  final _context = TextEditingController();
  final _injuryDetails = TextEditingController();
  final _additional = TextEditingController();
  int _step = 0;
  bool _injury = false;
  String _injuredWho = 'patient';
  bool _photo = false;
  String? _validation;

  @override
  void dispose() {
    _product.dispose();
    _batch.dispose();
    _incident.dispose();
    _context.dispose();
    _injuryDetails.dispose();
    _additional.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (!_validateStep()) return;
    final steps = _buildSteps();
    if (_step >= steps.length - 1) {
      _finish();
      return;
    }
    setState(() => _step += 1);
  }

  void _prevStep() {
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _step -= 1);
  }

  bool _validateStep() {
    String? message;
    switch (_step) {
      case 0:
        if (_product.text.trim().isEmpty) message = widget.t.required_fields;
        break;
      case 1:
        if (_batch.text.trim().isEmpty) message = widget.t.required_fields;
        break;
      case 2:
        if (_incident.text.trim().isEmpty) message = widget.t.required_fields;
        break;
      case 4:
        if (_injury && _injuryDetails.text.trim().isEmpty) message = widget.t.required_fields;
        break;
      default:
        break;
    }

    setState(() => _validation = message);
    return message == null;
  }

  String _summaryText() {
    final t = widget.t;
    final buffer = StringBuffer(t.supportWizardSummaryTitle);
    buffer.write('\n- ${t.supportWizardProduct}: ${_product.text.trim()}');
    buffer.write('\n- ${t.supportWizardBatch}: ${_batch.text.trim()}');
    buffer.write('\n- ${t.supportWizardWhat}: ${_incident.text.trim()}');
    if (_context.text.trim().isNotEmpty) {
      buffer.write('\n- ${t.supportWizardWhere}: ${_context.text.trim()}');
    }
    buffer.write('\n- ${t.supportWizardInjury}: ${_injury ? t.supportWizardYes : t.supportWizardNo}');
    if (_injury) {
      buffer.write('\n  · ${t.supportWizardInjuredWho}: ${_injuredLabel()}');
      buffer.write('\n  · ${t.supportWizardInjuryType}: ${_injuryDetails.text.trim()}');
    }
    buffer.write('\n- ${t.supportWizardPhoto}: ${_photo ? t.supportWizardPhotoNote : t.supportWizardNo}');
    if (_additional.text.trim().isNotEmpty) {
      buffer.write('\n- ${t.supportWizardAdditional}: ${_additional.text.trim()}');
    }
    return buffer.toString();
  }

  String _injuredLabel() {
    final t = widget.t;
    switch (_injuredWho) {
      case 'patient':
        return t.supportWizardInjuredPatient;
      case 'user':
        return t.supportWizardInjuredUser;
      case 'provider':
        return t.supportWizardInjuredProvider;
      default:
        return _injuredWho;
    }
  }

  void _finish() {
    if (!_validateStep()) return;
    Navigator.of(context).pop(_summaryText());
  }

  List<Step> _buildSteps() {
    final t = widget.t;
    return [
      Step(
        title: Text(t.supportWizardProduct),
        state: _step > 0 ? StepState.complete : StepState.indexed,
        isActive: _step >= 0,
        content: TextField(
          controller: _product,
          decoration: InputDecoration(
            labelText: t.supportWizardProduct,
            hintText: t.product_type,
          ),
        ),
      ),
      Step(
        title: Text(t.supportWizardBatch),
        state: _step > 1 ? StepState.complete : StepState.indexed,
        isActive: _step >= 1,
        content: TextField(
          controller: _batch,
          decoration: InputDecoration(
            labelText: t.supportWizardBatch,
            hintText: 'LOT / Charge',
          ),
        ),
      ),
      Step(
        title: Text(t.supportWizardWhat),
        state: _step > 2 ? StepState.complete : StepState.indexed,
        isActive: _step >= 2,
        content: TextField(
          controller: _incident,
          minLines: 3,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: t.supportWizardWhat,
            hintText: t.supportWizardWhatHint,
          ),
        ),
      ),
      Step(
        title: Text(t.supportWizardWhere),
        state: _step > 3 ? StepState.complete : StepState.indexed,
        isActive: _step >= 3,
        content: TextField(
          controller: _context,
          minLines: 2,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: t.supportWizardWhere,
            hintText: t.supportWizardContextHint,
          ),
        ),
      ),
      Step(
        title: Text(t.supportWizardInjury),
        state: _step > 4 ? StepState.complete : StepState.indexed,
        isActive: _step >= 4,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              value: _injury,
              title: Text(t.supportWizardInjury),
              onChanged: (v) => setState(() => _injury = v),
            ),
            if (_injury) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  t.supportWizardInjuredWho,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              RadioListTile<String>(
                value: 'patient',
                groupValue: _injuredWho,
                onChanged: (v) => setState(() => _injuredWho = v ?? 'patient'),
                title: Text(t.supportWizardInjuredPatient),
              ),
              RadioListTile<String>(
                value: 'user',
                groupValue: _injuredWho,
                onChanged: (v) => setState(() => _injuredWho = v ?? 'user'),
                title: Text(t.supportWizardInjuredUser),
              ),
              RadioListTile<String>(
                value: 'provider',
                groupValue: _injuredWho,
                onChanged: (v) => setState(() => _injuredWho = v ?? 'provider'),
                title: Text(t.supportWizardInjuredProvider),
              ),
              TextField(
                controller: _injuryDetails,
                minLines: 2,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: t.supportWizardInjuryType,
                ),
              ),
            ],
          ],
        ),
      ),
      Step(
        title: Text(t.supportWizardPhoto),
        state: _step > 5 ? StepState.complete : StepState.indexed,
        isActive: _step >= 5,
        content: CheckboxListTile(
          value: _photo,
          onChanged: (v) => setState(() => _photo = v ?? false),
          title: Text(t.supportWizardPhotoNote),
        ),
      ),
      Step(
        title: Text(t.supportWizardAdditional),
        state: _step > 6 ? StepState.complete : StepState.indexed,
        isActive: _step >= 6,
        content: TextField(
          controller: _additional,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: t.supportWizardAdditional,
          ),
        ),
      ),
      Step(
        title: Text(t.supportWizardSummaryTitle),
        state: _step > 7 ? StepState.complete : StepState.indexed,
        isActive: _step >= 7,
        content: _SummaryPreview(summary: _summaryText()),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final steps = _buildSteps();
    final t = widget.t;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t.supportWizardCardTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 520,
            child: Stepper(
              currentStep: _step,
              type: StepperType.vertical,
              controlsBuilder: (ctx, _) {
                final isLast = _step == steps.length - 1;
                return Row(
                  children: [
                    FilledButton(
                      onPressed: _nextStep,
                      child: Text(isLast ? t.supportWizardFinish : t.continueLabel),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _prevStep,
                      child: Text(_step == 0 ? t.cancel : t.back),
                    ),
                  ],
                );
              },
              onStepContinue: _nextStep,
              onStepCancel: _prevStep,
              onStepTapped: (i) => setState(() => _step = i),
              steps: steps,
            ),
          ),
          if (_validation != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _validation!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryPreview extends StatelessWidget {
  final String summary;
  const _SummaryPreview({required this.summary});

  @override
  Widget build(BuildContext context) {
    final lines = summary.split('\n').where((line) => line.trim().isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(line),
          ),
      ],
    );
  }
}
