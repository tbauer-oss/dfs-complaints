// lib/pages/dashboard_page.dart
import 'package:flutter/material.dart';

import '../api/client.dart';
import '../l10n/app_localizations.dart';

import 'complaint_form_page.dart';
import 'my_complaints_page.dart';
import 'account_page.dart';
import 'support_page.dart';

class DashboardPage extends StatelessWidget {
  final ApiClient api;
  final VoidCallback onLoggedOut;

  // onLocaleChanged nicht mehr nötig, wir steuern die Sprache im App-Root
  const DashboardPage({
    super.key,
    required this.api,
    required this.onLoggedOut,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    final tiles = <_Entry>[
      _Entry(t.reportComplaint, Icons.add_circle, () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ComplaintFormPage(api: api),
        ));
      }),
      _Entry(t.myComplaints, Icons.list_alt, () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MyComplaintsPage(api: api),
        ));
      }),
      _Entry(t.myAccount, Icons.person, () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AccountPage(api: api),
        ));
      }),
      _Entry(t.supportTitle, Icons.support_agent, () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SupportPage(api: api),
        ));
      }),
    ];

    // << KEIN Scaffold und KEINE AppBar hier >>
    return Center(
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
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
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
