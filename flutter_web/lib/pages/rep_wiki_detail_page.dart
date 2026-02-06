import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../models/wiki_article.dart';
import '../utils/lang_utils.dart';

class RepWikiDetailPage extends StatefulWidget {
  final ApiClient api;
  final String articleId;
  final WikiArticle? initialArticle;
  const RepWikiDetailPage({
    super.key,
    required this.api,
    required this.articleId,
    this.initialArticle,
  });

  @override
  State<RepWikiDetailPage> createState() => _RepWikiDetailPageState();
}

class _RepWikiDetailPageState extends State<RepWikiDetailPage> {
  WikiArticle? _article;
  bool _loading = true;
  String? _err;
  String? _lastLocale;

  @override
  void initState() {
    super.initState();
    _article = widget.initialArticle;
    _loading = _article == null;
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = normalizeLangCode(Localizations.localeOf(context).languageCode);
    if (_lastLocale == null) {
      _lastLocale = locale;
      return;
    }
    if (_lastLocale != locale) {
      _lastLocale = locale;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = _article == null;
      _err = null;
    });
    try {
      final lang = normalizeLangCode(Localizations.localeOf(context).languageCode);
      final article = await widget.api.fetchWikiArticle(widget.articleId, lang: lang);
      if (!mounted) return;
      setState(() {
        _article = _localizedArticle(article, lang);
        _loading = false;
      });
      return;
    } catch (e) {
      WikiArticle? fallbackArticle;
      String? err;
      if (e is ApiError && e.status == 404) {
        try {
          fallbackArticle = await widget.api.fetchWikiArticle(widget.articleId);
        } catch (fallbackErr) {
          err = fallbackErr.toString();
        }
      } else {
        err = e.toString();
      }
      if (!mounted) return;
      setState(() {
        final lang = normalizeLangCode(Localizations.localeOf(context).languageCode);
        _article = fallbackArticle != null ? _localizedArticle(fallbackArticle, lang) : _article;
        _err = _article == null ? (err ?? e.toString()) : null;
        _loading = false;
      });
    }
  }

  WikiArticle _localizedArticle(WikiArticle article, String lang) {
    final tr = article.translationFor(lang);
    return article.copyWith(
      title: tr.title.isNotEmpty ? tr.title : article.title,
      teaser: tr.teaser.isNotEmpty ? tr.teaser : article.teaser,
      contentMarkdown: tr.contentMarkdown.isNotEmpty ? tr.contentMarkdown : article.contentMarkdown,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = AppLocalizations.of(context)!;
    final article = _article;
    return Scaffold(
      appBar: AppBar(
        title: Text(article?.title ?? t.repWikiArticleTitleFallback),
        leading: Navigator.of(context).canPop() ? const BackButton() : null,
        actions: [
          IconButton(
            tooltip: t.repWikiReload,
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 80, height: 80, child: CircularProgressIndicator(strokeWidth: 5)),
                  const SizedBox(height: 16),
                  Text(t.repWikiArticleLoading, style: theme.textTheme.titleMedium),
                ],
              ),
            )
          : article == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48),
                      const SizedBox(height: 12),
                      Text(_err ?? t.repWikiArticleError, style: TextStyle(color: cs.error)),
                      const SizedBox(height: 8),
                      ElevatedButton(onPressed: _load, child: Text(t.repWikiRetry)),
                    ],
                  ),
                )
              : LayoutBuilder(
                  builder: (context, cons) {
                    final narrow = cons.maxWidth < 720;
                    final content = Card(
                      margin: const EdgeInsets.only(top: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_err != null)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: cs.errorContainer,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: cs.error),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline, color: cs.onErrorContainer),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        t.repWikiArticleCachedInfo(_err ?? ''),
                                        style: TextStyle(color: cs.onErrorContainer),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
                                      Text(t.repWikiArticleUpdatedAt(
                                          '${article.updatedAt.toLocal()}'.split('.').first)),
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
                              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                                p: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                                h1: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                                h2: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                                h3: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                blockSpacing: 18,
                                listBullet: TextStyle(color: cs.primary, fontWeight: FontWeight.bold),
                                codeblockDecoration: BoxDecoration(
                                  color: cs.surfaceVariant,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: cs.outlineVariant),
                                ),
                                blockquoteDecoration: BoxDecoration(
                                  color: cs.tertiaryContainer.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border(left: BorderSide(color: cs.primary, width: 4)),
                                ),
                                horizontalRuleDecoration: BoxDecoration(border: Border.all(color: cs.outlineVariant)),
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
                ),
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
