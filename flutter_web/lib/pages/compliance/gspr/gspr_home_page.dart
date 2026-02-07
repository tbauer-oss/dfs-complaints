import 'package:flutter/material.dart';

import '../../../api/client.dart';
import '../../../l10n/app_localizations.dart';
import 'gspr_chapter_table.dart';

class GsprHomePage extends StatelessWidget {
  final ApiClient api;
  final bool canEdit;
  final bool isPrrc;
  final bool isAdmin;
  final bool isQm;

  const GsprHomePage({
    super.key,
    required this.api,
    required this.canEdit,
    required this.isPrrc,
    required this.isAdmin,
    required this.isQm,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            elevation: 1,
            child: TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: t.gsprChapterI),
                Tab(text: t.gsprChapterII),
                Tab(text: t.gsprChapterIII),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                GsprChapterTable(
                  api: api,
                  chapter: 'I',
                  canEdit: canEdit,
                  isAdmin: isAdmin,
                  isPrrc: isPrrc,
                  isQm: isQm,
                ),
                GsprChapterTable(
                  api: api,
                  chapter: 'II',
                  canEdit: canEdit,
                  isAdmin: isAdmin,
                  isPrrc: isPrrc,
                  isQm: isQm,
                ),
                GsprChapterTable(
                  api: api,
                  chapter: 'III',
                  canEdit: canEdit,
                  isAdmin: isAdmin,
                  isPrrc: isPrrc,
                  isQm: isQm,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
