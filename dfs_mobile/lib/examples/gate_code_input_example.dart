import 'package:flutter/material.dart';
import 'package:dfs_mobile/widgets/gate_code_input.dart';

void main() {
  runApp(const GateCodeDemoApp());
}

class GateCodeDemoApp extends StatelessWidget {
  const GateCodeDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gate Code Demo',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF0A4FA3)),
      home: const GateCodeDemoPage(),
    );
  }
}

class GateCodeDemoPage extends StatefulWidget {
  const GateCodeDemoPage({super.key});

  @override
  State<GateCodeDemoPage> createState() => _GateCodeDemoPageState();
}

class _GateCodeDemoPageState extends State<GateCodeDemoPage> {
  String? _lastCompletedCode;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gate-Passwort eingeben')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Bitte geben Sie das Gate-Passwort ein, das Sie von DFS erhalten haben.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            GateCodeInput(
              onCompleted: (code) {
                setState(() => _lastCompletedCode = code);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Vollständiger Code: $code')),
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              _lastCompletedCode == null
                  ? 'Noch kein vollständiger Code eingegeben.'
                  : 'Letzter Code: $_lastCompletedCode',
            ),
          ],
        ),
      ),
    );
  }
}
