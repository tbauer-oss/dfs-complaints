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
    final size = MediaQuery.of(context).size;
    final isPortrait = size.height >= size.width;

    // Responsive Breakpoints
    int crossAxisCount;
    if (size.width < 480) {
      crossAxisCount = 1; // Handy schmal
    } else if (size.width < 720) {
      crossAxisCount = 2; // Handy breit oder Querformat
    } else if (size.width < 1100) {
      crossAxisCount = 3; // Tablet
    } else {
      crossAxisCount = 4; // Desktop
    }

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

    // --- Hauptlayout ---
    return LayoutBuilder(
      builder: (ctx, constraints) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // ---------- GRID ----------
                  Expanded(
                    child: GridView.count(
                      padding: const EdgeInsets.all(8),
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: isPortrait ? 1 : 1.3, // Querformat flacher
                      children: [
                        for (final e in tiles)
                          _DashboardCard(entry: e),
                      ],
                    ),
                  ),

                  // ---------- LOGOUT-BUTTON ----------
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: FilledButton.icon(
                        icon: const Icon(Icons.logout, size: 22),
                        label: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            t.logout,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: Size(
                            isPortrait ? size.width * 0.7 : size.width * 0.4,
                            52,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () async {
                          await api.logout();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(t.loggedOut)),
                            );
                          }
                          onLoggedOut();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------
// Card-Komponente (responsive)
// -----------------------------
class _DashboardCard extends StatelessWidget {
  final _Entry entry;
  const _DashboardCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: isDark ? 1.5 : 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: entry.onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [Colors.grey.shade900, Colors.grey.shade800]
                  : [Colors.white, Colors.grey.shade100],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(entry.icon, size: 44, color: theme.colorScheme.primary),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    entry.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------
// Modelklasse für Einträge
// -----------------------------
class _Entry {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  _Entry(this.label, this.icon, this.onTap);
}
