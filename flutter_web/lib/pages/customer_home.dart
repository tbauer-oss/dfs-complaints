import 'package:flutter/material.dart';
import '../api/client.dart';
import 'complaint_form_page.dart'; // deine bestehende Seite zum Melden
import 'my_complaints_page.dart';
import 'account_page.dart';
import 'support_page.dart';

class CustomerHomePage extends StatelessWidget {
  final ApiClient api;
  const CustomerHomePage({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    final btnStyle = ElevatedButton.styleFrom(
      minimumSize: const Size(250, 56),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Kundenbereich')),
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
              label: const Text('Reklamation melden'),
            ),
            ElevatedButton.icon(
              style: btnStyle,
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => MyComplaintsPage(api: api),
                ));
              },
              icon: const Icon(Icons.list_alt),
              label: const Text('Meine Reklamationen'),
            ),
            const Divider(height: 40, thickness: 1),
            ElevatedButton.icon(
              style: btnStyle,
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AccountPage(api: api),
                ));
              },
              icon: const Icon(Icons.person),
              label: const Text('Mein Account'),
            ),
            ElevatedButton.icon(
              style: btnStyle,
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SupportPage(api: api),
                ));
              },
              icon: const Icon(Icons.support_agent),
              label: const Text('DFS Support'),
            ),
          ],
        ),
      ),
    );
  }
}
