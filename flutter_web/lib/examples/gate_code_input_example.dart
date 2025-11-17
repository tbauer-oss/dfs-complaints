import 'package:flutter/material.dart';
import 'package:dfs_customer_complaint/widgets/gate_code_input.dart';

void main() {
  runApp(const GateCodeDemoApp());
}

class GateCodeDemoApp extends StatelessWidget {
  const GateCodeDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gate Code Demo',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF1F4C8F)),
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
  String? _completedCode;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gate-Passwort eingeben')), 
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Bitte geben Sie das Gate-Passwort ein, das Sie erhalten haben.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              GateCodeInput(
                onCompleted: (code) {
                  setState(() => _completedCode = code);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Vollständiger Code: $code')),
                  );
                },
              ),
              const SizedBox(height: 24),
              Text(_completedCode == null ? 'Noch kein Code eingegeben.' : 'Letzter Code: $_completedCode'),
            ],
          ),
        ),
      ),
    );
  }
}
