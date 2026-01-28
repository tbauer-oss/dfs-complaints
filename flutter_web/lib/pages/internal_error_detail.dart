import 'package:flutter/material.dart';
import '../models/internal_error_model.dart';
import '../services/internal_error_service.dart';
import '../services/internal_error_capa_service.dart';
import '../api/client.dart';
import '../models/capa_report.dart';
import 'internal_error_form.dart';
import 'capa_detail_page.dart';

class InternalErrorDetailPage extends StatefulWidget {
  final InternalErrorService service;
  final ApiClient api;
  final InternalError? initialError;
  final bool canWrite;
  final bool canOverrideCapa;
  final bool canReadCapa;
  final bool canWriteCapa;
  final String? currentUser;

  const InternalErrorDetailPage({
    super.key,
    required this.service,
    required this.api,
    this.initialError,
    required this.canWrite,
    required this.canOverrideCapa,
    required this.canReadCapa,
    required this.canWriteCapa,
    this.currentUser,
  });

  @override
  State<InternalErrorDetailPage> createState() => _InternalErrorDetailPageState();
}

class _InternalErrorDetailPageState extends State<InternalErrorDetailPage> {
  final _formKey = GlobalKey<InternalErrorFormState>();
  bool _saving = false;
  bool _capaBusy = false;
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

  Future<void> _openCapaById(String capaId) async {
    try {
      final list = await widget.api.adminCapas();
      final report = list.firstWhere(
        (c) => c.id == capaId || c.capaNumber == capaId,
        orElse: () => CapaReport(id: ''),
      );
      if (!mounted) return;
      if (report.id.isEmpty) {
        _showMessage('CAPA $capaId nicht gefunden.', isError: true);
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CapaDetailPage(
            api: widget.api,
            canWrite: widget.canWriteCapa,
            initialReport: report,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _showMessage('CAPA $capaId konnte nicht geöffnet werden.', isError: true);
    }
  }

  Future<void> _handleCapaAction(InternalError entry) async {
    if (_capaBusy) return;
    if (entry.id.isEmpty) {
      _showMessage('Bitte den internen Fehler zuerst speichern.', isError: true);
      return;
    }
    final existing = entry.capaNumber?.trim() ?? '';
    if (!widget.canReadCapa) {
      _showMessage('Keine Berechtigung für CAPA.', isError: true);
      return;
    }
    if (existing.isNotEmpty) {
      await _openCapaById(existing);
      return;
    }
    if (!widget.canWriteCapa) {
      _showMessage('Keine Berechtigung zum Erstellen einer CAPA.', isError: true);
      return;
    }
    setState(() => _capaBusy = true);
    try {
      final prefill = buildCapaFromInternalError(entry);
      final saved = await widget.api.adminSaveCapa(prefill);
      final updated = entry.copyWith(capaNumber: saved.effectiveNumber);
      final persisted = await widget.service.update(updated);
      if (!mounted) return;
      setState(() => _draft = persisted);
      await _openCapaById(saved.effectiveNumber);
    } catch (e) {
      if (mounted) _showMessage('CAPA konnte nicht erstellt werden: $e', isError: true);
    } finally {
      if (mounted) setState(() => _capaBusy = false);
    }
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
                    canReadCapa: widget.canReadCapa,
                    canWriteCapa: widget.canWriteCapa,
                    capaBusy: _capaBusy,
                    onChanged: (value) => setState(() => _draft = value),
                    onCapaAction: _handleCapaAction,
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
