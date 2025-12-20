// lib/widgets/admin/global_search_bar.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/client.dart';
import '../../models/chat_message.dart';
import '../../models/customer_news_entry.dart';
import '../../models/global_search.dart';
import '../../models/portal_user.dart';
import '../../models/rep_download_item.dart';
import '../../models/wiki_article.dart';
import '../../services/chat_service.dart';
import '../skeletons.dart';

enum _DateFilter {
  today,
  last7,
  last30,
  custom,
}

class GlobalSearchBar extends StatefulWidget {
  final ApiClient api;
  final ChatService? chatService;
  final String? currentUserId;
  final ValueChanged<GlobalSearchResult>? onNavigate;

  const GlobalSearchBar({
    super.key,
    required this.api,
    this.chatService,
    this.currentUserId,
    this.onNavigate,
  });

  @override
  State<GlobalSearchBar> createState() => _GlobalSearchBarState();

  static const double preferredHeight = 132;
}

class _GlobalSearchBarState extends State<GlobalSearchBar> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();
  Timer? _debounce;
  OverlayEntry? _overlayEntry;

  bool _loading = false;
  bool _searching = false;
  bool _dataLoaded = false;
  List<GlobalSearchResult> _allResults = const [];
  List<GlobalSearchResult> _filteredResults = const [];
  List<String> _suggestions = const [];

  Set<GlobalSearchType> _selectedTypes = {
    GlobalSearchType.content,
    GlobalSearchType.message,
    GlobalSearchType.file,
    GlobalSearchType.user,
  };
  _DateFilter _dateFilter = _DateFilter.last30;
  DateTimeRange? _customRange;
  String? _categoryFilter;
  PortalUserSummary? _senderFilter;

  List<String> _categoryOptions = const [];
  List<PortalUserSummary> _senderOptions = const [];

  late final ChatService _chatService = widget.chatService ?? ChatService(widget.api);

  final Map<String, List<String>> _synonyms = const {
    'reklamation': ['complaint', 'beanstandung'],
    'vertreter': ['sales', 'repräsentant'],
    'dokument': ['datei', 'file'],
    'nachricht': ['message', 'chat'],
    'datei': ['dokument', 'file'],
    'nutzer': ['user', 'kunde'],
    'inhalt': ['content', 'wiki', 'news'],
    'kategorie': ['category', 'gruppe'],
  };

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_handleQueryChanged);
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _overlayEntry?.remove();
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      _removeOverlay();
    } else if (_searchCtrl.text.trim().isNotEmpty) {
      _showOverlay();
    }
  }

  void _handleQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), _performSearch);
  }

  Future<void> _ensureDataLoaded() async {
    if (_dataLoaded || _loading) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.api.adminFetchWikiArticles(),
        widget.api.adminDownloads(),
        widget.api.fetchPortalUsers(),
        widget.api.adminFetchCustomerNewsEntries(),
        widget.api.adminFetchPortalNewsEntries(),
        _chatService.fetchConversations(),
      ]);

      final wikiArticles = results[0] as List<WikiArticle>;
      final downloads = results[1] as List<RepDownloadItem>;
      final users = results[2] as List<PortalUserSummary>;
      final customerNews = results[3] as List<CustomerNewsEntry>;
      final portalNews = results[4] as List<CustomerNewsEntry>;
      final conversations = results[5] as List<ChatConversationSummary>;

      final output = <GlobalSearchResult>[];

      output.addAll(
        wikiArticles.map(
          (article) => GlobalSearchResult(
            id: article.id,
            type: GlobalSearchType.content,
            title: article.title,
            snippet: article.teaser.isNotEmpty ? article.teaser : article.contentMarkdown,
            date: article.updatedAt,
            sender: '',
            category: article.categoryName ?? article.categoryId,
            routeTarget: 'wiki:${article.id}',
            payload: article,
          ),
        ),
      );

      output.addAll(
        customerNews.map(
          (entry) => GlobalSearchResult(
            id: entry.id,
            type: GlobalSearchType.content,
            title: entry.title,
            snippet: entry.summary,
            date: entry.updatedAt,
            sender: '',
            category: entry.category,
            routeTarget: 'news:customer:${entry.id}',
            payload: entry,
          ),
        ),
      );

      output.addAll(
        portalNews.map(
          (entry) => GlobalSearchResult(
            id: entry.id,
            type: GlobalSearchType.content,
            title: entry.title,
            snippet: entry.summary,
            date: entry.updatedAt,
            sender: '',
            category: entry.category,
            routeTarget: 'news:portal:${entry.id}',
            payload: entry,
          ),
        ),
      );

      output.addAll(
        conversations.map(
          (conv) => GlobalSearchResult(
            id: conv.conversationId,
            type: GlobalSearchType.message,
            title: conv.title.isNotEmpty ? conv.title : 'Konversation',
            snippet: conv.lastMessagePreview ?? conv.lastMessage ?? 'Keine Vorschau verfügbar',
            date: conv.lastMessageAt ?? DateTime.now(),
            sender: conv.lastAuthor ?? '',
            category: conv.isGroup ? 'Gruppe' : 'Direkt',
            routeTarget: 'chat:${conv.conversationId}',
            payload: conv,
          ),
        ),
      );

      output.addAll(
        downloads.map(
          (item) => GlobalSearchResult(
            id: item.id,
            type: GlobalSearchType.file,
            title: item.title,
            snippet: item.description.isNotEmpty ? item.description : item.fileName,
            date: DateTime.fromMillisecondsSinceEpoch(item.updatedAt),
            sender: '',
            category: item.category,
            routeTarget: 'download:${item.id}',
            payload: item,
          ),
        ),
      );

      output.addAll(
        users.map(
          (user) => GlobalSearchResult(
            id: user.email,
            type: GlobalSearchType.user,
            title: user.label,
            snippet: user.email,
            date: DateTime.now(),
            sender: user.label,
            category: user.role,
            routeTarget: 'user:${user.email}',
            payload: user,
          ),
        ),
      );

      final categorySet = <String>{};
      for (final item in output) {
        final value = item.category.trim();
        if (value.isNotEmpty) categorySet.add(value);
      }

      users.sort((a, b) => a.sortKey.compareTo(b.sortKey));

      if (!mounted) return;
      setState(() {
        _allResults = output;
        _categoryOptions = categorySet.toList()..sort();
        _senderOptions = users;
        _dataLoaded = true;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _performSearch() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) {
      setState(() {
        _filteredResults = const [];
        _suggestions = const [];
      });
      _removeOverlay();
      return;
    }

    setState(() => _searching = true);
    await _ensureDataLoaded();
    final normalized = query.toLowerCase();
    final terms = _expandTerms(normalized);

    final results = _allResults.where((item) {
      if (!_selectedTypes.contains(item.type)) return false;
      if (!_matchesDateFilter(item.date)) return false;
      if (_categoryFilter != null && _categoryFilter!.isNotEmpty) {
        if (item.category.toLowerCase() != _categoryFilter!.toLowerCase()) return false;
      }
      if (_senderFilter != null) {
        final sender = item.sender.toLowerCase();
        final target = _senderFilter!.label.toLowerCase();
        if (sender.isEmpty || !sender.contains(target)) return false;
      }
      return _matchesQuery(item, normalized, terms);
    }).toList();

    _refreshCategoryOptions();

    results.sort((a, b) {
      final scoreA = _scoreMatch(a, normalized, terms);
      final scoreB = _scoreMatch(b, normalized, terms);
      if (scoreA != scoreB) return scoreB.compareTo(scoreA);
      return b.date.compareTo(a.date);
    });

    final suggestions = _buildSuggestions(normalized, results);

    if (!mounted) return;
    setState(() {
      _filteredResults = results;
      _suggestions = suggestions;
      _searching = false;
    });

    if (_focusNode.hasFocus) {
      _showOverlay();
    }
  }

  bool _matchesDateFilter(DateTime date) {
    final now = DateTime.now();
    switch (_dateFilter) {
      case _DateFilter.today:
        return date.year == now.year && date.month == now.month && date.day == now.day;
      case _DateFilter.last7:
        return date.isAfter(now.subtract(const Duration(days: 7)));
      case _DateFilter.last30:
        return date.isAfter(now.subtract(const Duration(days: 30)));
      case _DateFilter.custom:
        if (_customRange == null) return true;
        return date.isAfter(_customRange!.start.subtract(const Duration(seconds: 1))) &&
            date.isBefore(_customRange!.end.add(const Duration(days: 1)));
    }
  }

  bool _matchesQuery(GlobalSearchResult item, String query, Set<String> terms) {
    final haystack = <String>[
      item.title,
      item.snippet,
      item.sender,
      item.category,
    ].join(' ').toLowerCase();

    if (haystack.contains(query)) return true;

    final tokens = haystack.split(RegExp(r'\s+')).where((t) => t.trim().isNotEmpty).toList();
    for (final term in terms) {
      if (term.isEmpty) continue;
      if (haystack.contains(term)) return true;
      for (final token in tokens) {
        if (_distance(term, token) <= 2) return true;
      }
    }
    return false;
  }

  int _scoreMatch(GlobalSearchResult item, String query, Set<String> terms) {
    int score = 0;
    final title = item.title.toLowerCase();
    final snippet = item.snippet.toLowerCase();
    final sender = item.sender.toLowerCase();
    final category = item.category.toLowerCase();

    if (title.contains(query)) score += 4;
    if (title.startsWith(query)) score += 3;
    if (snippet.contains(query)) score += 2;
    if (sender.contains(query)) score += 1;
    if (category.contains(query)) score += 1;

    for (final term in terms) {
      if (term.isEmpty) continue;
      if (title.contains(term)) score += 2;
      if (snippet.contains(term)) score += 1;
    }

    return score;
  }

  Set<String> _expandTerms(String query) {
    final terms = <String>{query};
    final parts = query.split(RegExp(r'\s+')).where((p) => p.trim().isNotEmpty);
    final lookup = _synonymLookup();
    for (final part in parts) {
      terms.add(part);
      final synonyms = lookup[part];
      if (synonyms != null) terms.addAll(synonyms);
      for (final entry in lookup.entries) {
        if (_distance(part, entry.key) <= 2) {
          terms.add(entry.key);
          terms.addAll(entry.value);
        }
      }
    }
    return terms;
  }

  Map<String, Set<String>> _synonymLookup() {
    final map = <String, Set<String>>{};
    for (final entry in _synonyms.entries) {
      final key = entry.key.toLowerCase();
      final values = entry.value.map((e) => e.toLowerCase()).toSet();
      map.putIfAbsent(key, () => <String>{}).addAll(values);
      for (final value in values) {
        map.putIfAbsent(value, () => <String>{}).add(key);
      }
    }
    return map;
  }

  List<String> _buildSuggestions(String query, List<GlobalSearchResult> results) {
    final suggestions = <String>{};
    final lookup = _synonymLookup();

    for (final entry in lookup.entries) {
      if (query.contains(entry.key)) {
        suggestions.addAll(entry.value);
      } else if (_distance(query, entry.key) <= 2) {
        suggestions.add(entry.key);
        suggestions.addAll(entry.value);
      }
    }

    for (final result in results.take(4)) {
      suggestions.add(result.title);
    }

    return suggestions.take(5).toList();
  }

  int _distance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final matrix = List.generate(a.length + 1, (_) => List<int>.filled(b.length + 1, 0));

    for (int i = 0; i <= a.length; i++) {
      matrix[i][0] = i;
    }
    for (int j = 0; j <= b.length; j++) {
      matrix[0][j] = j;
    }

    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        ].reduce((value, element) => value < element ? value : element);
      }
    }
    return matrix[a.length][b.length];
  }

  void _showOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = _buildOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _buildOverlayEntry() {
    final renderBox = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final size = renderBox?.size ?? const Size(640, 48);
    final theme = Theme.of(context);

    return OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 8),
          child: Material(
            elevation: 12,
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.shadow.withOpacity(0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: _buildResultsList(theme),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultsList(ThemeData theme) {
    if (_searching || _loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: SkeletonTable(rows: 5, columns: 2, rowHeight: 16),
      );
    }

    final hasResults = _filteredResults.isNotEmpty;
    final hasSuggestions = _suggestions.isNotEmpty;

    if (!hasResults && !hasSuggestions) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, color: theme.colorScheme.outline, size: 36),
            const SizedBox(height: 12),
            Text(
              'Keine Treffer. Bitte Suchbegriff oder Filter anpassen.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final dateFmt = DateFormat('dd.MM.yyyy');

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      shrinkWrap: true,
      children: [
        if (hasSuggestions) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              hasResults ? 'Vorschläge' : 'Meinten Sie vielleicht …',
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestions
                .map(
                  (suggestion) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: ActionChip(
                      label: Text(suggestion),
                      onPressed: () {
                        _searchCtrl.text = suggestion;
                        _searchCtrl.selection = TextSelection.collapsed(offset: suggestion.length);
                        _performSearch();
                      },
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
        ],
        if (hasResults)
          ..._filteredResults.map(
            (result) => ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(result.typeIcon, color: theme.colorScheme.onPrimaryContainer),
              ),
              title: Text(result.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.snippet.isNotEmpty ? result.snippet : 'Keine Vorschau verfügbar',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${result.typeLabel} · ${result.category.isEmpty ? 'Allgemein' : result.category} · '
                    '${dateFmt.format(result.date)}'
                    '${result.sender.isNotEmpty ? ' · ${result.sender}' : ''}',
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              onTap: () {
                _removeOverlay();
                widget.onNavigate?.call(result);
              },
            ),
          ),
      ],
    );
  }

  Future<void> _handleDateFilterChange(_DateFilter? filter) async {
    if (filter == null) return;
    if (filter == _DateFilter.custom) {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
        lastDate: DateTime.now(),
        initialDateRange: _customRange,
      );
      if (range != null) {
        setState(() {
          _customRange = range;
          _dateFilter = _DateFilter.custom;
        });
      }
    } else {
      setState(() {
        _dateFilter = filter;
      });
    }
    _performSearch();
  }

  void _handleTypeToggle(GlobalSearchType type) {
    setState(() {
      if (_selectedTypes.contains(type)) {
        if (_selectedTypes.length > 1) _selectedTypes.remove(type);
      } else {
        _selectedTypes.add(type);
      }
    });
    _refreshCategoryOptions();
    _performSearch();
  }

  void _clearFilters() {
    setState(() {
      _selectedTypes = {
        GlobalSearchType.content,
        GlobalSearchType.message,
        GlobalSearchType.file,
        GlobalSearchType.user,
      };
      _dateFilter = _DateFilter.last30;
      _customRange = null;
      _categoryFilter = null;
      _senderFilter = null;
    });
    _refreshCategoryOptions();
    _performSearch();
  }

  void _refreshCategoryOptions() {
    if (!_dataLoaded || !mounted) return;
    final set = <String>{};
    for (final item in _allResults) {
      if (!_selectedTypes.contains(item.type)) continue;
      final value = item.category.trim();
      if (value.isNotEmpty) set.add(value);
    }
    final sorted = set.toList()..sort();
    if (_categoryFilter != null && _categoryFilter!.isNotEmpty) {
      if (!sorted.contains(_categoryFilter)) {
        _categoryFilter = null;
      }
    }
    setState(() => _categoryOptions = sorted);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hintStyle = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CompositedTransformTarget(
                link: _layerLink,
                child: TextField(
                  key: _fieldKey,
                  controller: _searchCtrl,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_outlined),
                    hintText: 'Globale Suche: Inhalte, Nachrichten, Dateien, Nutzer',
                    hintStyle: hintStyle,
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Suche löschen',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _searchCtrl.clear();
                              _performSearch();
                            },
                          ),
                  ),
                  onSubmitted: (_) => _performSearch(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    label: const Text('Inhalte'),
                    selected: _selectedTypes.contains(GlobalSearchType.content),
                    onSelected: (_) => _handleTypeToggle(GlobalSearchType.content),
                  ),
                  FilterChip(
                    label: const Text('Nachrichten'),
                    selected: _selectedTypes.contains(GlobalSearchType.message),
                    onSelected: (_) => _handleTypeToggle(GlobalSearchType.message),
                  ),
                  FilterChip(
                    label: const Text('Dateien'),
                    selected: _selectedTypes.contains(GlobalSearchType.file),
                    onSelected: (_) => _handleTypeToggle(GlobalSearchType.file),
                  ),
                  FilterChip(
                    label: const Text('Nutzer'),
                    selected: _selectedTypes.contains(GlobalSearchType.user),
                    onSelected: (_) => _handleTypeToggle(GlobalSearchType.user),
                  ),
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<_DateFilter>(
                      value: _dateFilter,
                      decoration: const InputDecoration(
                        labelText: 'Zeitraum',
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: _DateFilter.today, child: Text('Heute')),
                        DropdownMenuItem(value: _DateFilter.last7, child: Text('7 Tage')),
                        DropdownMenuItem(value: _DateFilter.last30, child: Text('30 Tage')),
                        DropdownMenuItem(value: _DateFilter.custom, child: Text('Custom Range')),
                      ],
                      onChanged: _handleDateFilterChange,
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String?>(
                      value: _categoryFilter,
                      decoration: const InputDecoration(
                        labelText: 'Kategorie',
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Alle Kategorien'),
                        ),
                        ..._categoryOptions.map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => _categoryFilter = value);
                        _performSearch();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<PortalUserSummary?>(
                      value: _senderFilter,
                      decoration: const InputDecoration(
                        labelText: 'Absender',
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<PortalUserSummary?>(
                          value: null,
                          child: Text('Alle Absender'),
                        ),
                        ..._senderOptions.map(
                          (user) => DropdownMenuItem(
                            value: user,
                            child: Text(user.label, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => _senderFilter = value);
                        _performSearch();
                      },
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _clearFilters,
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Filter zurücksetzen'),
                  ),
                  if (_searching || _loading)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: SkeletonBox(width: 18, height: 18, borderRadius: BorderRadius.all(Radius.circular(4))),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
