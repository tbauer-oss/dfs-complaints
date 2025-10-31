import 'package:flutter/material.dart';
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
  bool _busy=false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Center(
      child: SizedBox(
        width: 420, 
        child: Column(
          mainAxisSize: MainAxisSize.min, 
          children: [
            // ===== Adminbereich-Button GANZ OBEN (ohne Gate-Passwort) =====
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.admin_panel_settings),
                label: const Text('Adminbereich'),
                onPressed: () {
                  // Adminbereich OHNE Gate-Passwort öffnen
                  Navigator.of(context, rootNavigator: true).pushNamed('/admin');
                },
              ),
            ),
            const SizedBox(height: 12),

            // ===== ursprünglicher Inhalt =====
            Text(t.gate_prompt, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              obscureText: true,
              decoration: InputDecoration(
                border: const OutlineInputBorder(), 
                labelText: t.gate_password,
              ),
            ),
            if (_err!=null) 
              Padding(
                padding: const EdgeInsets.only(top:8), 
                child: Text(_err!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _busy ? null : () async {
                setState(()=>_busy=true); 
                _err=null;
                final ok = await widget.api.gateUnlock(_ctrl.text);
                setState(()=>_busy=false);
                if (ok) {
                  widget.onUnlocked();
                } else {
                  setState(()=>_err=t.invalid);
                }
              },
              child: _busy 
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(t.continueLabel),
            ),
          ],
        ),
      ),
    );
  }
}
