// lib/pages/customer_home_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';

import 'complaint_form_page.dart';
import 'my_complaints_page.dart';
import 'account_page.dart';
import 'support_page.dart';

class CustomerHomePage extends StatelessWidget {
  final ApiClient api;
  const CustomerHomePage({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    final btnStyle = ElevatedButton.styleFrom(
      minimumSize: const Size(250, 56),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    );

    return Scaffold(
      appBar: AppBar(title: Text(t.customer_area)), // „Kundenbereich“ lokalisiert
      body: Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 20,
          runSpacing: 20,
          children: [
            ElevatedButton.icon(
              style: btnStyle,
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ComplaintFormPage(api: api),
                ));
              },
              icon: const Icon(Icons.add_circle_outline),
              label: Text(t.reportComplaint), // „Reklamation melden“
            ),
            ElevatedButton.icon(
              style: btnStyle,
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => MyComplaintsPage(api: api),
                ));
              },
              icon: const Icon(Icons.list_alt),
              label: Text(t.myComplaints), // „Meine Reklamationen“
            ),

            const SizedBox(height: 40), // statt Divider in Wrap (wirkt sauberer)

            ElevatedButton.icon(
              style: btnStyle,
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AccountPage(api: api),
                ));
              },
              icon: const Icon(Icons.person),
              label: Text(t.myAccount), // „Mein Account“
            ),
            ElevatedButton.icon(
              style: btnStyle,
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SupportPage(api: api),
                ));
              },
              icon: const Icon(Icons.support_agent),
              label: Text(t.supportTitle), // „DFS Support“ lokalisiert
            ),
          ],
        ),
      ),
    );
  }
}
