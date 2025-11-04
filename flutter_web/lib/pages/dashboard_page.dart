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

    // Farben pro Kachel (wie Admin-Optik)
    final tiles = <_Entry>[
      _Entry(t.reportComplaint, Icons.add_circle, Colors.indigo, () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ComplaintFormPage(api: api),
        ));
      }),
      _Entry(t.myComplaints, Icons.list_alt, Colors.teal, () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MyComplaintsPage(api: api),
        ));
      }),
      _Entry(t.myAccount, Icons.person, Colors.cyan, () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AccountPage(api: api),
        ));
      }),
      _Entry(t.supportTitle, Icons.support_agent, Colors.amber.shade800, () {
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

          // Zielbreiten für Kacheln
          final double maxExtent = isPhone
              ? (isPortrait ? 160 : 200)
              : (size.width < 1024 ? 220 : 240);

          // Kompakt-Optik für Phones
          final double iconSize = isPhone ? 28 : 44;
          final double fontSize = isPhone ? 12.5 : 14.0;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
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
                  return _DashTile(
                    icon: e.icon,
                    label: e.label,
                    color: e.color,
                    onTap: e.onTap,
                    iconSize: iconSize,
                    fontSize: fontSize,
                    // badge: const _BusyDot(), // optional
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
  final Color color;
  final VoidCallback onTap;
  _Entry(this.label, this.icon, this.color, this.onTap);
}

/// Hübsche Kachel wie im Adminbereich (runde Ecken, Hover, Shadow)
class _DashTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final Widget? badge;

  // Responsive Größen (vom Dashboard übergeben)
  final double iconSize;
  final double fontSize;

  const _DashTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badge,
    this.iconSize = 44,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      elevation: 1.5,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        hoverColor: color.withOpacity(0.06),
        splashColor: color.withOpacity(0.10),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: iconSize, color: color),
                const SizedBox(height: 10),
                Text(
                  label,
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

    if (badge == null) return card;

    return Stack(
      children: [
        card,
        Positioned(right: 10, top: 10, child: badge!),
      ],
    );
  }
}

// Optionaler Busy-Indikator (kleiner Badge)
class _BusyDot extends StatelessWidget {
  const _BusyDot({super.key});
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
