import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../api/client.dart';
import '../models/training_signature.dart';

class TrainingSignaturePage extends StatefulWidget {
  const TrainingSignaturePage({super.key, required this.api});

  final ApiClient api;

  @override
  State<TrainingSignaturePage> createState() => _TrainingSignaturePageState();
}

class _TrainingSignaturePageState extends State<TrainingSignaturePage> {
  late final SignatureController _controller;
  TrainingSignContext? _context;
  bool _loading = true;
  bool _saving = false;
  bool _confirmed = false;
  bool _success = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black87,
      exportBackgroundColor: Colors.white,
    );
    _loadContext();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _readToken() {
    final params = Uri.base.queryParameters;
    return params['t'] ?? params['token'] ?? '';
  }

  Future<void> _loadContext() async {
    final token = _readToken();
    if (token.isEmpty) {
      setState(() {
        _loading = false;
        _errorMessage = 'Kein Signatur-Token gefunden.';
      });
      return;
    }
    try {
      final ctx = await widget.api.publicTrainingSignContext(token);
      if (!mounted) return;
      setState(() {
        _context = ctx;
        _loading = false;
        _errorMessage = null;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = err is ApiError && err.status == 410
            ? 'Dieser Signatur-Link ist abgelaufen oder wurde bereits verwendet. Bitte neuen QR-Code anfordern.'
            : 'Signatur-Link konnte nicht geladen werden.';
      });
    }
  }

  Future<void> _submit() async {
    final token = _readToken();
    if (token.isEmpty) return;
    setState(() => _saving = true);
    try {
      final bytes = await _controller.toPngBytes();
      if (bytes == null) {
        setState(() => _saving = false);
        return;
      }
      final signature = base64Encode(bytes);
      await widget.api.publicSubmitTrainingSignature(
        token: token,
        signatureBase64: signature,
        confirmationChecked: _confirmed,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _success = true;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = err is ApiError && err.status == 410
            ? 'Dieser Signatur-Link ist abgelaufen oder wurde bereits verwendet. Bitte neuen QR-Code anfordern.'
            : 'Speichern fehlgeschlagen. Bitte erneut versuchen.';
      });
    }
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
        ),
      );
    }
    if (_success) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
              const SizedBox(height: 16),
              const Text('Danke! Unterschrift wurde gespeichert.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Schließen'),
              ),
            ],
          ),
        ),
      );
    }

    final ctx = _context!;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(ctx.expiresAt).toLocal();
    final canSave = _confirmed && _controller.isNotEmpty && !_saving;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Unterschrift für: ${ctx.participantDisplayName}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text('Schulung: ${ctx.trainingTitle}', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text('Link gültig bis: ${expiresAt.toLocal()}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          Container(
            height: 220,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
            ),
            child: Signature(controller: _controller, backgroundColor: Colors.white),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _confirmed,
            title: const Text('Ich bestätige die Teilnahme an der Schulung.'),
            onChanged: (value) => setState(() => _confirmed = value ?? false),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton(
                onPressed: _saving
                    ? null
                    : () {
                        _controller.clear();
                        setState(() {});
                      },
                child: const Text('Löschen'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: canSave ? _submit : null,
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Speichern'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Unterschrift'),
      ),
      body: SafeArea(child: _buildContent()),
    );
  }
}
