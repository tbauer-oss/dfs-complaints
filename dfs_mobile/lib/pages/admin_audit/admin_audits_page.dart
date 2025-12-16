import 'package:flutter/material.dart';
import 'package:dfs_mobile/api/client.dart';

class AdminAuditsPage extends StatelessWidget {
  final ApiClient api;

  const AdminAuditsPage({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audits'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.checklist_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'Auditverwaltung ist in dieser App-Version noch nicht verfügbar.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
