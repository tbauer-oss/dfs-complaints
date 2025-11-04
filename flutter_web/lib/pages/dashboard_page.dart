// lib/pages/dashboard_page.dart
import 'dart:html' as html; // für mailto-Link
import 'package:flutter/material.dart';

import '../api/client.dart';
import '../l10n/app_localizations.dart';

import 'complaint_form_page.dart';
import 'my_complaints_page.dart';
import 'account_page.dart';
import 'support_page.dart';

class DashboardPage extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onLoggedOut;

  const DashboardPage({
    super.key,
    required this.api,
    required this.onLoggedOut,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  MyRep? _myRep;

  @override
  void initState() {
    super.initState();
    // Vertreter laden (falls zugeordnet). Wenn keiner: _myRep bleibt null -> kein Banner.
    widget.api.getMyRep().then((rep) {
      if (!mounted) return;
      setState(() => _myRep = rep);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    final tiles = <_Entry>[
      _Entry(t.reportComplaint, Icons.add_circle, () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ComplaintFormPage(api: widget.api),
        ));
      }),
      _Entry(t.myComplaints, Icons.list_alt, () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MyComplaintsPage(api: widget.api),
        ));
      }),
      _Entry(t.myAccount, Icons.person, () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AccountPage(api: widget.api),
        ));
      }),
      _Entry(t.supportTitle, Icons.support_agent, () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SupportPage(api: widget.api),
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

          // Vertreterzeile (optional)
          Widget? repBanner;
          if (_myRep != null) {
            final name = '${_myRep!.firstName.trim()} ${_myRep!.lastName.trim()}'.trim();
            final hasEmail = _myRep!.email.trim().isNotEmpty;
            final region = _myRep!.region.trim();

            repBanner = Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.08),
                  border: Border.all(color: Colors.blue, width: 1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.handshake_outlined, size: 20, color: Colors.blue),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Lokalisierter Titel mit Name
                          Text(
                            t.rep_banner_title(name.isEmpty ? '—' : name),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (hasEmail || region.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                [
                                  if (hasEmail) _myRep!.email,
                                  if (region.isNotEmpty) region,
                                ].join(' • '),
                                style: TextStyle(color: Colors.grey[800]),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (hasEmail)
                      Tooltip(
                        message: t.rep_email_tooltip,
                        child: TextButton.icon(
                          onPressed: () {
                            final subject = Uri.encodeComponent(t.mail_subject_rep);
                            final mailto = 'mailto:${_myRep!.email}?subject=$subject';
                            html.window.open(mailto, '_self');
                          },
                          icon: const Icon(Icons.email_outlined),
                          label: Text(t.rep_email_button),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                children: [
                  if (repBanner != null) repBanner,
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: maxExtent,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
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
                ],
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
