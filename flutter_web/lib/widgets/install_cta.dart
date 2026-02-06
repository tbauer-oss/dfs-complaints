import 'dart:js' as js;
import 'dart:js_util' as jsu;
import 'package:flutter/material.dart';

class InstallCta extends StatefulWidget {
  const InstallCta({super.key});
  @override
  State<InstallCta> createState() => _InstallCtaState();
}

class _InstallCtaState extends State<InstallCta> {
  bool _canInstall = false;

  @override
  void initState() {
    super.initState();
    _canInstall = js.context['__pwaCanInstall'] == true;
    // Reagieren auf das Custom-Event aus index.html
    js.context.callMethod('addEventListener', [
      'pwa-can-install',
      (e) => setState(() => _canInstall = true),
    ]);
  }

  Future<void> _install() async {
    final fn = js.context['showInstallPrompt'];
    if (fn != null) {
      final ok = await jsu.promiseToFuture(jsu.callMethod(fn, 'call', [js.context]));
      // Optional: Feedback anzeigen, Telemetrie etc.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canInstall) return const SizedBox.shrink();
    return ElevatedButton.icon(
      onPressed: _install,
      icon: const Icon(Icons.download),
      label: const Text('App installieren'),
      style: ElevatedButton.styleFrom(minimumSize: const Size(220, 48)),
    );
  }
}