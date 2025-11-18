// lib/pages/customer_home_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';

import 'complaint_form_page.dart';
import 'my_complaints_page.dart';
import 'account_page.dart';
import 'support_page.dart';
import 'customer_assistant_page.dart';
import 'customer_news_page.dart';
import 'dart:html' as html;

class InstallPwaButton extends StatefulWidget {
  const InstallPwaButton({super.key});
  @override
  State<InstallPwaButton> createState() => _InstallPwaButtonState();
}

class _InstallPwaButtonState extends State<InstallPwaButton> {
  bool _canInstall = false;

  @override
  void initState() {
    super.initState();
    _canInstall = (html.window as dynamic).__pwaCanInstall == true;
    html.window.addEventListener('pwa-can-install', (_) {
      if (mounted) setState(() => _canInstall = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_canInstall) return const SizedBox.shrink();
    return ElevatedButton.icon(
      icon: const Icon(Icons.download),
      label: const Text('App installieren'),
      onPressed: () async {
        final accepted = await (html.window as dynamic).showInstallPrompt() as bool? ?? false;
        if (!accepted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Installation abgebrochen.')));
        }
      },
    );
  }
}

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
      appBar: AppBar(title: Text(t.customer_area)),
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
              label: Text(t.reportComplaint),
            ),
            ElevatedButton.icon(
              style: btnStyle,
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => MyComplaintsPage(api: api),
                ));
              },
              icon: const Icon(Icons.list_alt),
              label: Text(t.myComplaints),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              style: btnStyle,
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AccountPage(api: api),
                ));
              },
              icon: const Icon(Icons.person),
              label: Text(t.myAccount),
            ),
            ElevatedButton.icon(
              style: btnStyle,
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SupportPage(api: api),
                ));
              },
              icon: const Icon(Icons.support_agent),
              label: Text(t.supportTitle), // ← übersetzt
            ),
            ElevatedButton.icon(
              style: btnStyle,
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CustomerAssistantPage(api: api),
                ));
              },
              icon: const Icon(Icons.auto_awesome),
              label: Text(t.customerAssistantCta),
            ),
            ElevatedButton.icon(
              style: btnStyle,
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CustomerNewsPage(api: api),
                ));
              },
              icon: const Icon(Icons.campaign_outlined),
              label: Text(t.customerNewsTile),
            ),
          ],
        ),
      ),
    );
  }
}
