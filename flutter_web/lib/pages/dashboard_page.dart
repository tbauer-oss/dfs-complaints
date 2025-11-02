import 'package:flutter/material.dart';
import '../api/client.dart';
import '../widgets/lang_action.dart';       // +++ NEU (falls noch nicht drin)
import '../widgets/logout_action.dart';     // +++ NEU
import 'complaint_form_page.dart';
import 'my_complaints_page.dart';
import 'account_page.dart';
import 'support_page.dart';

class DashboardPage extends StatelessWidget {
  final ApiClient api;
  final VoidCallback onLoggedOut; // <- Callback, der zurück zur Login-Startseite führt

  const DashboardPage({
    super.key,
    required this.api,
    required this.onLoggedOut,
  });

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
        centerTitle: true,
        elevation: 1,
        scrolledUnderElevation: 1,
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        title: const Text('Kundenbereich'),
        actions: const [
          LangAction(),
          SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0),
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 8.0, bottom: 6.0),
              child: LogoutAction(
                api: api,
                onLoggedOut: () {
                  // nach Logout zurück zur Login-Seite:
                  Navigator.of(context).popUntil((r) => r.isFirst);
                },
              ),
            ),
          ),
        ),
      ),
      // WICHTIG: KEINE zweite Überschrift im Body!
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
                          Text(e.label, style: const TextStyle(fontWeight: FontWeight.w600)),
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
