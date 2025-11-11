// lib/pages/customer_home_page.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';

import 'complaint_form_page.dart';
import 'my_complaints_page.dart';
import 'account_page.dart';
import 'support_page.dart';
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
      label: const Flexible(
        child: Text(
          'App installieren',
          textAlign: TextAlign.center,
        ),
      ),
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
      minimumSize: const Size(0, 56),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    );

    return Scaffold(
      appBar: AppBar(title: Text(t.customer_area)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          double buttonWidth = 280;
          if (maxWidth.isFinite) {
            final padded = maxWidth - 32;
            if (padded > 0) {
              buttonWidth = math.min(280, padded);
            } else if (maxWidth > 0) {
              buttonWidth = math.min(280, maxWidth);
            } else {
              buttonWidth = 0;
            }
          }

          Widget buildButton({
            required IconData icon,
            required String label,
            required VoidCallback onPressed,
          }) {
            final button = ElevatedButton.icon(
              style: btnStyle,
              onPressed: onPressed,
              icon: Icon(icon),
              label: Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                ),
              ),
            );
            if (buttonWidth <= 0) {
              return button;
            }
            return SizedBox(width: buttonWidth, child: button);
          }

          final SizedBox spacer = SizedBox(
            width: buttonWidth > 0 ? buttonWidth : null,
            height: 40,
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 20,
                runSpacing: 20,
                children: [
                  buildButton(
                    icon: Icons.add_circle_outline,
                    label: t.reportComplaint,
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ComplaintFormPage(api: api),
                      ));
                    },
                  ),
                  buildButton(
                    icon: Icons.list_alt,
                    label: t.myComplaints,
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => MyComplaintsPage(api: api),
                      ));
                    },
                  ),
                  spacer,
                  buildButton(
                    icon: Icons.person,
                    label: t.myAccount,
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => AccountPage(api: api),
                      ));
                    },
                  ),
                  buildButton(
                    icon: Icons.support_agent,
                    label: t.supportTitle, // ← übersetzt
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SupportPage(api: api),
                      ));
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
