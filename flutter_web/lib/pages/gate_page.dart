import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';

class GatePage extends StatefulWidget {
  final ApiClient api; final VoidCallback onUnlocked;
  const GatePage({super.key, required this.api, required this.onUnlocked});
  @override State<GatePage> createState() => _GatePageState();
}
class _GatePageState extends State<GatePage> {
  final _ctrl = TextEditingController(); String? _err; bool _busy=false;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Center(
      child: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(t.gate_prompt, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: _ctrl,
          obscureText: true,
          decoration: InputDecoration(border: const OutlineInputBorder(), labelText: t.gate_password),
        ),
        if (_err!=null) Padding(padding: const EdgeInsets.only(top:8), child: Text(_err!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _busy ? null : () async {
            setState(()=>_busy=true); _err=null;
            final ok = await widget.api.gateUnlock(_ctrl.text);
            setState(()=>_busy=false);
            if (ok) widget.onUnlocked(); else setState(()=>_err=t.invalid);
          },
          child: _busy ? const CircularProgressIndicator() : Text(t.continueLabel),
        )
      ])),
    );
  }
}
