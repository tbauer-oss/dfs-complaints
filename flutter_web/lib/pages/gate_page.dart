// lib/pages/gate_page.dart
import 'package:flutter/material.dart';
import 'dart:html' as html;

import '../api/client.dart';
import '../l10n/app_localizations.dart';

class GatePage extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onUnlocked;
  const GatePage({super.key, required this.api, required this.onUnlocked});
  @override
  State<GatePage> createState() => _GatePageState();
}

class _GatePageState extends State<GatePage> {
  final _ctrl = TextEditingController();
  String? _err;
  bool _busy = false;
  bool _cardHovered = false;
  bool _buttonHovered = false;

  // === Admin: Secret-Dialog + Preflight-Check ===
  Future<void> _openAdmin() async {
    final secretCtrl = TextEditingController(
      text: html.window.localStorage['admin_secret'] ?? '',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Admin-Secret'),
        content: TextField(
          controller: secretCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'X-Admin-Secret',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Weiter')),
        ],
      ),
    );

    if (ok != true) return;

    final secret = secretCtrl.text.trim();
    if (secret.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte ein Admin-Secret eingeben.')),
      );
      return;
    }

    // Persistieren
    html.window.localStorage['admin_secret'] = secret;

    // Preflight gegen /api/admin/users prüfen
    try {
      final base = const String.fromEnvironment('API_BASE', defaultValue: '');
      final apiBase = base.isNotEmpty ? base : html.window.location.origin;

      final res = await html.HttpRequest.request(
        '$apiBase/api/admin/users',
        method: 'GET',
        withCredentials: true,
        requestHeaders: {
          'X-Admin-Secret': secret,
          'Content-Type': 'application/json; charset=utf-8',
        },
      );

      if (res.status == 200) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pushNamed('/admin');
      } else {
        throw 'HTTP ${res.status}';
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Adminzugang verweigert (Secret ungültig/CORS): $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 720;
        final highlights = [
          'Sichere Kommunikation',
          'Transparente Statusupdates',
          'Direkter Kontakt zum DFS-Team',
        ];

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      scheme.brightness == Brightness.dark
                          ? const Color(0xFF0B1220)
                          : const Color(0xFFE8EEF8),
                      scheme.brightness == Brightness.dark
                          ? scheme.primary.withOpacity(.35)
                          : scheme.primary.withOpacity(.15),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            Positioned(
              top: -120,
              left: -60,
              child: _AmbientGlow(color: scheme.primary.withOpacity(.25), size: 280),
            ),
            Positioned(
              bottom: -140,
              right: -40,
              child: _AmbientGlow(color: scheme.secondary.withOpacity(.20), size: 320),
            ),
            Positioned.fill(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 32, vertical: isCompact ? 24 : 48),
                child: Align(
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: MouseRegion(
                    onEnter: (_) => setState(() => _cardHovered = true),
                    onExit: (_) => setState(() => _cardHovered = false),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.all(isCompact ? 24 : 32),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: LinearGradient(
                          colors: scheme.brightness == Brightness.dark
                              ? [scheme.surface.withOpacity(.90), scheme.surface.withOpacity(.75)]
                              : [Colors.white, scheme.surface.withOpacity(.9)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: scheme.shadow.withOpacity(_cardHovered ? .20 : .12),
                            blurRadius: _cardHovered ? 40 : 24,
                            offset: const Offset(0, 20),
                          ),
                        ],
                        border: Border.all(
                          color: scheme.outlineVariant.withOpacity(.35),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: scheme.primary,
                                side: BorderSide(color: scheme.primary.withOpacity(.3)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                textStyle: theme.textTheme.labelLarge,
                              ),
                              icon: const Icon(Icons.admin_panel_settings),
                              label: const Text('Adminbereich'),
                              onPressed: _openAdmin,
                            ),
                          ),
                          SizedBox(height: isCompact ? 16 : 24),
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: scheme.primary.withOpacity(.12),
                            child: Icon(Icons.shield_outlined, color: scheme.primary, size: 36),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            t.gate_prompt,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Melden Sie sich an, um Beschwerden sicher zu verwalten und Ihr Team auf dem Laufenden zu halten.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                          SizedBox(height: isCompact ? 18 : 24),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final text in highlights)
                                Chip(
                                  backgroundColor: scheme.primary.withOpacity(.08),
                                  labelStyle: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
                                  avatar: Icon(Icons.check_circle_rounded, color: scheme.primary, size: 20),
                                  label: Text(text),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                ),
                            ],
                          ),
                          SizedBox(height: isCompact ? 24 : 32),
                          TextField(
                            controller: _ctrl,
                            obscureText: true,
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: t.gate_password,
                              prefixIcon: Icon(Icons.lock_outline, color: scheme.primary),
                            ),
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: _err == null
                                ? const SizedBox.shrink()
                                : Padding(
                                    key: const ValueKey('error'),
                                    padding: const EdgeInsets.only(top: 10),
                                    child: Text(
                                      _err!,
                                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                          ),
                          SizedBox(height: isCompact ? 20 : 28),
                          MouseRegion(
                            onEnter: (_) => setState(() => _buttonHovered = true),
                            onExit: (_) => setState(() => _buttonHovered = false),
                            child: AnimatedScale(
                              duration: const Duration(milliseconds: 160),
                              scale: _buttonHovered ? 1.03 : 1,
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                    textStyle: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  onPressed: _busy ? null : _submit,
                                  icon: _busy
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.arrow_forward_rounded),
                                  label: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Text(t.continueLabel),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    _err = null;
    final ok = await widget.api.gateUnlock(_ctrl.text);
    setState(() => _busy = false);
    if (ok) {
      widget.onUnlocked();
    } else {
      final t = AppLocalizations.of(context)!;
      setState(() => _err = t.invalid);
    }
  }
}

class _AmbientGlow extends StatelessWidget {
  final Color color;
  final double size;

  const _AmbientGlow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, Colors.transparent],
          stops: const [0, 1],
        ),
      ),
    );
  }
}
