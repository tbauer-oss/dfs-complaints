import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../api/client.dart';
import '../models/wiki_article.dart';
import '../utils/lang_utils.dart';

class RepWikiDetailPage extends StatefulWidget {
  final ApiClient api;
  final String articleId;
  const RepWikiDetailPage({super.key, required this.api, required this.articleId});

  @override
  State<RepWikiDetailPage> createState() => _RepWikiDetailPageState();
}

class _RepWikiDetailPageState extends State<RepWikiDetailPage> {
  WikiArticle? _article;
  bool _loading = true;
  String? _err;
  bool _didInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;
    _didInit = true;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final lang = normalizeLangCode(Localizations.localeOf(context).languageCode);
      final article = await widget.api.fetchWikiArticle(widget.articleId, lang: lang);
      if (!mounted) return;
      setState(() => _article = article);
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_err != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_err!, style: TextStyle(color: cs.error)),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _load, child: const Text('Erneut versuchen')),
          ],
        ),
      );
    }
    final article = _article;
    if (article == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, cons) {
        final narrow = cons.maxWidth < 720;
        final content = Card(
          margin: const EdgeInsets.only(top: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            article.title,
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _InfoChip(icon: Icons.folder_open, label: article.categoryName ?? article.categoryId),
                              if (article.productGroups.isNotEmpty)
                                _InfoChip(
                                  icon: Icons.inventory_2_outlined,
                                  label: article.productGroups.join(', '),
                                ),
                              _InfoChip(icon: Icons.label_outline, label: article.type.toUpperCase()),
                              _InfoChip(icon: Icons.star_outline, label: article.importance.toUpperCase()),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (!narrow)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Aktualisiert: ${article.updatedAt.toLocal()}'.split('.').first),
                          if (article.tags.isNotEmpty)
                            Wrap(
                              spacing: 4,
                              children: article.tags
                                  .map((t) => Chip(label: Text(t), visualDensity: VisualDensity.compact))
                                  .toList(),
                            ),
                        ],
                      ),
                  ],
                ),
                const Divider(height: 32),
                MarkdownBody(
                  data: article.contentMarkdown,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet(
                    h1: theme.textTheme.headlineSmall,
                    h2: theme.textTheme.titleLarge,
                    h3: theme.textTheme.titleMedium,
                    blockquoteDecoration: BoxDecoration(
                      color: cs.tertiaryContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border(left: BorderSide(color: cs.primary, width: 4)),
                    ),
                  ),
                  imageBuilder: (uri, title, alt) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(uri.toString(), fit: BoxFit.contain),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: narrow ? 720 : 1100),
            child: content,
          ),
        );
      },
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 18, color: theme.colorScheme.primary),
      label: Text(label),
      side: BorderSide(color: theme.colorScheme.outlineVariant),
    );
  }
}
