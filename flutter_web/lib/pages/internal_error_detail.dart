import 'package:flutter/material.dart';
import '../models/internal_error_model.dart';
import '../services/internal_error_service.dart';
import 'internal_error_form.dart';

class InternalErrorDetailPage extends StatefulWidget {
  final InternalErrorService service;
  final InternalError? initialError;
  final bool canWrite;
  final bool canOverrideCapa;
  final String? currentUser;

  const InternalErrorDetailPage({
    super.key,
    required this.service,
    this.initialError,
    required this.canWrite,
    required this.canOverrideCapa,
    this.currentUser,
  });

  @override
  State<InternalErrorDetailPage> createState() => _InternalErrorDetailPageState();
}

class _InternalErrorDetailPageState extends State<InternalErrorDetailPage> {
  final _formKey = GlobalKey<InternalErrorFormState>();
  bool _saving = false;
  String? _error;
  late InternalError _draft;

  bool get _isNew => widget.initialError == null;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialError ?? InternalError(createdBy: widget.currentUser ?? '');
  }

  Future<void> _handleSave() async {
    if (!widget.canWrite) return;
    final value = _formKey.currentState?.submit(
      onError: (message) => _showMessage(message, isError: true),
    );
    if (value == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = _isNew
          ? await widget.service.create(value, createdBy: widget.currentUser)
          : await widget.service.update(value);
      if (!mounted) return;
      setState(() => _draft = saved);
      Navigator.of(context).pop(saved);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? theme.colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = _isNew ? 'Neuer interner Fehler' : 'Interner Fehler ${_draft.errorCode}';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (widget.canWrite)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _saving ? null : _handleSave,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Speichert…' : 'Speichern'),
              ),
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.primaryContainer.withOpacity(theme.brightness == Brightness.dark ? 0.12 : 0.28),
              cs.surface,
              cs.surfaceVariant.withOpacity(0.2),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: cs.onErrorContainer),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _error!,
                              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onErrorContainer),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_error != null) const SizedBox(height: 16),
                  InternalErrorForm(
                    key: _formKey,
                    initial: _draft,
                    canOverrideCapa: widget.canOverrideCapa,
                    onChanged: (value) => setState(() => _draft = value),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
