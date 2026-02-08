import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

class GsprChapterPage extends StatelessWidget {
  final String chapter;

  const GsprChapterPage({
    super.key,
    required this.chapter,
  });

  String _chapterLabel(AppLocalizations t) {
    switch (chapter) {
      case 'I':
        return t.gsprChapterI;
      case 'II':
        return t.gsprChapterII;
      case 'III':
        return t.gsprChapterIII;
      default:
        return chapter;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final chapterLabel = _chapterLabel(t);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.gsprPageTitle),
            Text(
              chapterLabel,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        t.gsprColumnGsprRef,
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        t.gsprColumnApplicable,
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        t.gsprColumnStatus,
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        t.gsprColumnVersion,
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              t.empty_state_no_items,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(t.create_new_gspr_item),
                    content: Text(t.gsprComingSoon),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(t.ok),
                      ),
                    ],
                  ),
                );
              },
              child: Text(t.create_new_gspr_item),
            ),
          ],
        ),
      ),
    );
  }
}
