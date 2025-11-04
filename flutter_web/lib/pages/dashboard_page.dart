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

    return SafeArea(
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final size = MediaQuery.of(ctx).size;
          final isPortrait = MediaQuery.of(ctx).orientation == Orientation.portrait;
          final isPhone = size.width < 600;

          // Zielbreiten für Kacheln (maxCrossAxisExtent). Auf dem Phone kleiner.
          final double maxExtent = isPhone
              ? (isPortrait ? 160 : 200) // Handy: Portrait knackig, Landscape etwas breiter
              : (size.width < 1024 ? 220 : 240); // Tablet/Desktop

          // Kompakt-Optik für Phones: kleinere Icons/Schrift und engeres Padding
          final double iconSize = isPhone ? 28 : 44;
          final double vGap = isPhone ? 8 : 10;
          final double fontSize = isPhone ? 12.5 : 14.0;
          final EdgeInsets cardPad = EdgeInsets.symmetric(
            horizontal: isPhone ? 6 : 10,
            vertical: isPhone ? 8 : 12,
          );

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: maxExtent,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  // etwas „flacher“ auf Phones, damit mehr Kacheln auf den Screen passen
                  childAspectRatio: isPhone ? 1.05 : 1.12,
                ),
                itemCount: tiles.length,
                itemBuilder: (context, i) {
                  final e = tiles[i];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: e.onTap,
                      child: Padding(
                        padding: cardPad,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(e.icon, size: iconSize),
                              SizedBox(height: vGap),
                              Text(
                                e.label,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: fontSize,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
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
