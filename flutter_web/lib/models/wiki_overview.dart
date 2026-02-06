import 'wiki_article.dart';
import 'wiki_category.dart';

class WikiOverview {
  final List<WikiCategory> categories;
  final List<WikiArticle> articles;

  const WikiOverview({
    required this.categories,
    required this.articles,
  });
}
