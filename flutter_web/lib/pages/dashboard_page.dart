// lib/pages/dashboard_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import 'complaint_form_page.dart';
import 'my_complaints_page.dart';
import 'account_page.dart';
import 'support_page.dart';
import '../widgets/logout_action.dart'; // <-- NEU

class DashboardPage extends StatelessWidget {
  final ApiClient api;
  const DashboardPage({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    final tiles = <_Entry>[
      _Entry('Reklamation melden', Icons.add_circle, () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ComplaintFormPage(api: api),
        ));
      }),
      _Entry('Meine Reklamationen', Icons.list_alt, () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MyComplaintsPage(api: api),
        ));
      }),
      _Entry('Mein Account', Icons.person, () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AccountPage(api: api),
        ));
      }),
      _Entry('DFS Support', Icons.support_agent, () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SupportPage(api: api),
        ));
      }),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kundenbereich'),
        actions: [
          LogoutAction(api: api), // <-- Abmelde-Button in der AppBar
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: GridView.count(
            padding: const EdgeInsets.all(24),
            crossAxisCount: MediaQuery.of(context).size.width > 720 ? 4 : 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            children: [
              for (final e in tiles)
                Card(
                  child: InkWell(
                    onTap: e.onTap,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(e.icon, size: 44),
                          const SizedBox(height: 10),
                          Text(
                            e.label,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Entry {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  _Entry(this.label, this.icon, this.onTap);
}
