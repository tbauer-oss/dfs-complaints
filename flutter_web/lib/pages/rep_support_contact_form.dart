import 'package:flutter/material.dart';

import '../api/client.dart';
import '../l10n/app_localizations.dart';

class RepSupportContactForm extends StatefulWidget {
  final ApiClient api;
  final String repFirstName;
  final String repLastName;
  final String repEmail;
  final String repRegion;
  final VoidCallback? onCancel;
  final VoidCallback? onSent;

  const RepSupportContactForm({
    super.key,
    required this.api,
    required this.repFirstName,
    required this.repLastName,
    required this.repEmail,
    required this.repRegion,
    this.onCancel,
    this.onSent,
  });

  @override
  RepSupportContactFormState createState() => RepSupportContactFormState();
}

class RepSupportContactFormState extends State<RepSupportContactForm> {
  final _subject = TextEditingController();
  final _message = TextEditingController();

  bool _sending = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    for (final ctrl in [_subject, _message]) {
      ctrl.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (!_dirty && (_subject.text.isNotEmpty || _message.text.isNotEmpty)) {
      setState(() => _dirty = true);
    }
  }

  @override
  void dispose() {
    for (final ctrl in [_subject, _message]) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<bool> confirmLeave() async {
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

  Future<void> _handleSend() async {
    final t = AppLocalizations.of(context)!;
    final subject = _subject.text.trim();
    final message = _message.text.trim();
    final firstName = widget.repFirstName.trim();
    final lastName  = widget.repLastName.trim();
    final region    = widget.repRegion.trim();

    if (subject.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.rep_contact_validation)),
      );
      return;
    }

    final email = widget.repEmail.trim();
    if (!email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.rep_support_contact_no_email)),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _sending = true);

    try {
      await widget.api.repContactQM(
        subject: subject,
        message: message,
        repEmail: email,
        repFirstName: firstName,
        repLastName: lastName,
        repRegion: region,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.rep_contact_sent)),
      );

      _subject.clear();
      _message.clear();
      setState(() => _dirty = false);

      widget.onSent?.call();
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t.rep_contact_error} (${e.message})')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.rep_contact_error)),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _handleCancel() async {
    final ok = await confirmLeave();
    if (!ok) return;
    widget.onCancel?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final name = '${widget.repFirstName.trim()} ${widget.repLastName.trim()}'.trim();
    final email = widget.repEmail.trim();
    final region = widget.repRegion.trim();
    const qmMail = 'complaint@dfs-diamon.de';
    final hasValidEmail = email.contains('@');

    Widget infoRow({
      required IconData icon,
      required String label,
      required String value,
    }) {
      if (value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$label: $value',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.rep_support_contact_intro(qmMail),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (hasValidEmail)
              Text(
                t.rep_support_contact_from_hint(email),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withOpacity(.7),
                ),
              )
            else
              Text(
                t.rep_support_contact_no_email,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            const SizedBox(height: 16),
            infoRow(
              icon: Icons.person_outline,
              label: t.contact_person_plain,
              value: name,
            ),
            infoRow(
              icon: Icons.alternate_email,
              label: t.rep_email_label,
              value: email,
            ),
            infoRow(
              icon: Icons.public,
              label: t.region,
              value: region,
            ),
            const SizedBox(height: 20),
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
              maxLines: 12,
              decoration: InputDecoration(
                labelText: t.rep_contact_message_label,
                alignLabelWithHint: true,
                prefixIcon: const Icon(Icons.message_outlined),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                TextButton(
                  onPressed: _sending ? null : _handleCancel,
                  child: Text(t.cancel),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: hasValidEmail && !_sending ? _handleSend : null,
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(t.rep_contact_form),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
