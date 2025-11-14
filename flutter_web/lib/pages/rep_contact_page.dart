import 'package:flutter/material.dart';

import '../api/client.dart';
import '../l10n/app_localizations.dart';

class RepContactPage extends StatefulWidget {
  final ApiClient api;
  final MyRep rep;
  final String? customerCompany;
  final String? customerEmail;

  const RepContactPage({
    super.key,
    required this.api,
    required this.rep,
    this.customerCompany,
    this.customerEmail,
  });

  @override
  State<RepContactPage> createState() => _RepContactPageState();
}

class _RepContactPageState extends State<RepContactPage> {
  final _firstName = TextEditingController();
  final _lastName  = TextEditingController();
  final _subject   = TextEditingController();
  final _message   = TextEditingController();

  bool _sending = false;
  bool _dirty   = false;

  @override
  void initState() {
    super.initState();
    for (final controller in [_firstName, _lastName, _subject, _message]) {
      controller.addListener(_onChanged);
    }
  }

  void _onChanged() {
    if (!_dirty &&
        (_firstName.text.isNotEmpty ||
         _lastName.text.isNotEmpty ||
         _subject.text.isNotEmpty ||
         _message.text.isNotEmpty)) {
      setState(() => _dirty = true);
    }
  }

  @override
  void dispose() {
    for (final controller in [_firstName, _lastName, _subject, _message]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<bool> _confirmLeaveIfDirty() async {
    if (!_dirty) return true;
    final t = AppLocalizations.of(context)!;
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.rep_contact_discard_title),
        content: Text(t.rep_contact_discard_text),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.no),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.yes),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  Future<void> _handleCancel() async {
    final ok = await _confirmLeaveIfDirty();
    if (ok && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleSend() async {
    final t = AppLocalizations.of(context)!;
    final subject = _subject.text.trim();
    final msg     = _message.text.trim();

    if (subject.isEmpty || msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.rep_contact_validation)),
      );
      return;
    }

    final repEmail = widget.rep.email.trim();
    if (repEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.rep_contact_no_rep_email)),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final company      = (widget.customerCompany ?? '').trim();
      final companyEmail = (widget.customerEmail ?? '').trim();

      final payload = <String, dynamic>{
        'repEmail'        : repEmail,
        'repFirstName'    : widget.rep.firstName,
        'repLastName'     : widget.rep.lastName,
        'company'         : company,
        'companyEmail'    : companyEmail,
        'contactFirstName': _firstName.text.trim(),
        'contactLastName' : _lastName.text.trim(),
        'subject'         : subject,
        'message'         : msg,
      };

      await widget.api.sendRepContact(payload);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.rep_contact_sent)),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.rep_contact_error)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t     = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;

    final company      = (widget.customerCompany ?? '').trim();
    final companyEmail = (widget.customerEmail ?? '').trim();
    final firstRep     = widget.rep.firstName.trim();
    final lastRep      = widget.rep.lastName.trim();

    return WillPopScope(
      onWillPop: _confirmLeaveIfDirty,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.rep_contact_title),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t.rep_contact_intro(firstRep, lastRep),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withOpacity(.8),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: company.isNotEmpty ? company : t.yourCompany,
                enabled: false,
                decoration: InputDecoration(
                  labelText: t.rep_contact_company_label,
                  prefixIcon: const Icon(Icons.business),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: companyEmail,
                enabled: false,
                decoration: InputDecoration(
                  labelText: t.rep_contact_company_email_label,
                  prefixIcon: const Icon(Icons.alternate_email),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _firstName,
                      decoration: InputDecoration(
                        labelText: t.firstName,
                        prefixIcon: const Icon(Icons.person_outline),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _lastName,
                      decoration: InputDecoration(
                        labelText: t.lastName,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _subject,
                decoration: InputDecoration(
                  labelText: t.rep_contact_subject_label,
                  prefixIcon: const Icon(Icons.subject),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _message,
                minLines: 5,
                maxLines: 10,
                decoration: InputDecoration(
                  labelText: t.rep_contact_message_label,
                  alignLabelWithHint: true,
                  prefixIcon: const Icon(Icons.message_outlined),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _sending ? null : _handleCancel,
                      child: Text(t.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _sending ? null : _handleSend,
                      icon: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_outlined),
                      label: Text(t.send),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
