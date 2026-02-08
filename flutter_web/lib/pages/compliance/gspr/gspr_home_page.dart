import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

class GsprHomePage extends StatelessWidget {
  const GsprHomePage({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.gsprPageTitle,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            t.gsprComingSoon,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 12),
          _GsprNavCard(
            label: t.gsprChapterI,
            onTap: () => Navigator.of(context).pushNamed('/compliance/gspr/chapter/I'),
          ),
          const SizedBox(height: 12),
          _GsprNavCard(
            label: t.gsprChapterII,
            onTap: () => Navigator.of(context).pushNamed('/compliance/gspr/chapter/II'),
          ),
          const SizedBox(height: 12),
          _GsprNavCard(
            label: t.gsprChapterIII,
            onTap: () => Navigator.of(context).pushNamed('/compliance/gspr/chapter/III'),
          ),
        ],
      ),
    );
  }
}

class _GsprNavCard extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _GsprNavCard({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: ListTile(
        title: Text(label),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
