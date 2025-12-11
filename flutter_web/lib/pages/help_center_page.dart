import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../l10n/app_localizations.dart';
import '../models/help_content.dart';
import '../services/help_center_loader.dart';
import '../services/app_prefs_scope.dart';
import '../services/app_prefs.dart';
import '../widgets/lang_action.dart';
import '../widgets/theme_action.dart';

class HelpCenterPage extends StatefulWidget {
  final String? initialSectionId;
  final String? initialTopicId;
  final bool allowPop;

  const HelpCenterPage({
    super.key,
    this.initialSectionId,
    this.initialTopicId,
    this.allowPop = true,
  });

  @override
  State<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends State<HelpCenterPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _loader = HelpCenterLoader();
  final _searchCtrl = TextEditingController();
  AppPrefs? _prefs;

  HelpCenterContent? _content;
  String? _selectedSectionId;
  String? _selectedTopicId;
  String? _error;
  bool _loading = true;
  String _currentLang = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _prefs?.removeListener(_handlePrefsChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final prefs = AppPrefsScope.of(context);
    if (_prefs != prefs) {
      _prefs?.removeListener(_handlePrefsChanged);
      _prefs = prefs..addListener(_handlePrefsChanged);
    }

    final lang = Localizations.localeOf(context).languageCode;
    if (lang != _currentLang) {
      _currentLang = lang;
      _loadContent();
    }
  }

  Future<void> _loadContent() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _loader.load(_currentLang);
      setState(() {
        _content = data;
        _selectedSectionId = widget.initialSectionId ?? data.sections.firstOrNull?.id;
        _selectedTopicId = widget.initialTopicId ?? data.sectionById(_selectedSectionId)?.topics.firstOrNull?.id;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectTopic(String sectionId, String topicId) {
    setState(() {
      _selectedSectionId = sectionId;
      _selectedTopicId = topicId;
    });
    _searchCtrl.clear();
    _maybeCloseDrawer();
  }

  void _maybeCloseDrawer() {
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      _scaffoldKey.currentState?.closeDrawer();
    }
  }

  List<_SearchResult> _searchResults() {
    final query = _searchCtrl.text.trim().toLowerCase();
    final data = _content;
    if (query.isEmpty || data == null) return const [];

    final List<_SearchResult> results = [];
    for (final section in data.sections) {
      for (final topic in section.topics) {
        final corpus = [
          section.title,
          section.audience,
          topic.title,
          topic.summary ?? '',
          ...topic.tags,
          ...topic.steps.map((s) => s.title),
          ...topic.steps.map((s) => s.description),
          ...topic.tips,
        ].join(' ').toLowerCase();
        if (corpus.contains(query)) {
          results.add(
            _SearchResult(
              sectionId: section.id,
              topicId: topic.id,
              sectionTitle: section.title,
              topicTitle: topic.title,
              audience: section.audience,
              summary: topic.summary ?? '',
            ),
          );
        }
      }
    }
    return results.take(20).toList();
  }

  Widget _buildSearchField(AppLocalizations t, {bool dense = false}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return TextField(
      controller: _searchCtrl,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: t.help_search_placeholder,
        isDense: dense,
        filled: true,
        fillColor: cs.surfaceVariant.withOpacity(theme.brightness == Brightness.dark ? 0.35 : 0.2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isNarrow = MediaQuery.of(context).size.width < 1000;
    final prefs = AppPrefsScope.of(context);

    return Scaffold(
      key: _scaffoldKey,
      drawer: isNarrow
          ? Drawer(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildSidebar(t, drawerMode: true),
                ),
              ),
            )
          : null,
      appBar: AppBar(
        leading: isNarrow
            ? IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              )
            : (widget.allowPop ? const BackButton() : null),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.help_center_title, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              t.help_center_subtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          LangAction(onLocaleChanged: (l) => prefs.setLang(l.languageCode)),
          const SizedBox(width: 4),
          const ThemeAction(),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 1000;
                    return Row(
                      children: [
                        if (isWide)
                          SizedBox(
                            width: 320,
                            child: _buildSidebar(t, drawerMode: false),
                          ),
                        Expanded(child: _buildContentArea(t, showNavSummary: !isWide)),
                      ],
                    );
                  },
                ),
    );
  }

  void _handlePrefsChanged() {
    final langCode = _prefs?.locale?.languageCode;
    if (langCode == null) return;

    final normalized = langCode.toLowerCase();
    if (normalized != _currentLang) {
      _currentLang = normalized;
      _loadContent();
    }
  }

  Widget _buildSidebar(AppLocalizations t, {required bool drawerMode}) {
    final section = _content?.sectionById(_selectedSectionId);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.help_section_navigation, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _buildSearchField(t),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            children: [
              ...?_content?.sections.map(
                (sec) => Card(
                  color: sec.id == _selectedSectionId
                      ? cs.primaryContainer.withOpacity(0.45)
                      : cs.surface,
                  child: ExpansionTile(
                    initiallyExpanded: sec.id == _selectedSectionId,
                    title: Text(sec.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(sec.audience),
                    trailing: Icon(
                      sec.id == _selectedSectionId ? Icons.expand_less : Icons.expand_more,
                    ),
                    children: [
                      ...sec.topics.map(
                        (topic) => ListTile(
                          selected: sec.id == _selectedSectionId && topic.id == _selectedTopicId,
                          title: Text(topic.title),
                          subtitle: topic.summary == null ? null : Text(topic.summary!),
                          onTap: () => _selectTopic(sec.id, topic.id),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (drawerMode) const SizedBox(height: 12),
        if (drawerMode)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              icon: const Icon(Icons.close),
              label: Text(MaterialLocalizations.of(context).closeButtonLabel),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
      ],
    );
  }

  Widget _buildContentArea(AppLocalizations t, {required bool showNavSummary}) {
    final section = _content?.sectionById(_selectedSectionId);
    final topic = section?.topicById(_selectedTopicId);
    final results = _searchResults();
    final cs = Theme.of(context).colorScheme;

    if (section == null || topic == null) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showNavSummary) ...[
                Text(t.help_section_navigation, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _buildSearchField(t, dense: true),
                const SizedBox(height: 12),
              ],
              Text(t.help_topic_navigation, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(t.help_center_subtitle),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showNavSummary) ...[
                Text(t.help_section_navigation, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _buildSearchField(t, dense: true),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _content?.sections
                          .map(
                          (s) => ChoiceChip(
                            label: Text(s.title),
                            selected: s.id == section?.id,
                            onSelected: (_) {
                              final topicId = s.topics.firstOrNull?.id;
                              if (topicId != null && topicId.isNotEmpty) {
                                _selectTopic(s.id, topicId);
                              }
                            },
                          ),
                          )
                          .toList() ??
                      [],
                ),
                const SizedBox(height: 16),
              ],
              if (_searchCtrl.text.isNotEmpty) ...[
                Text(t.help_results, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (results.isEmpty)
                  Text(t.help_no_results)
                else
                  Card(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, idx) {
                        final r = results[idx];
                        return ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: Text(r.topicTitle),
                          subtitle: Text('${r.sectionTitle} • ${r.audience}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _selectTopic(r.sectionId, r.topicId),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 16),
              ],
              _buildBreadcrumbs(t, section!, topic!),
              const SizedBox(height: 12),
              _buildTopicHeader(t, section, topic, cs),
              const SizedBox(height: 16),
              _buildStepCards(t, topic, cs),
              const SizedBox(height: 14),
              _buildTips(t, topic),
              const SizedBox(height: 14),
              _buildScreenshots(t, topic),
              const SizedBox(height: 14),
              _buildLinks(t, section, topic),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBreadcrumbs(AppLocalizations t, HelpSection section, HelpTopic topic) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Chip(
          avatar: const Icon(Icons.home_outlined, size: 18),
          label: Text(t.help_center_title),
          backgroundColor: cs.surfaceVariant,
        ),
        const Icon(Icons.chevron_right, size: 18),
        Chip(
          label: Text(section.title),
          avatar: const Icon(Icons.people_outline, size: 18),
        ),
        const Icon(Icons.chevron_right, size: 18),
        Chip(
          label: Text(topic.title),
          avatar: const Icon(Icons.article_outlined, size: 18),
        ),
      ],
    );
  }

  Widget _buildTopicHeader(AppLocalizations t, HelpSection section, HelpTopic topic, ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    topic.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    Chip(
                      label: Text(t.help_topic_actions),
                      avatar: const Icon(Icons.touch_app_outlined),
                    ),
                    Chip(
                      label: Text(section.audience),
                      avatar: const Icon(Icons.verified_user_outlined),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (topic.summary != null) ...[
              Text(t.help_topic_summary, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              MarkdownBody(data: topic.summary!),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _roleChip(t.help_role_customer, section.audience.contains('Kunde') || section.audience.contains('Customer')),
                _roleChip(t.help_role_representative, section.audience.contains('Vertreter') || section.audience.contains('Representative')),
                _roleChip(t.help_role_dfs, section.audience.contains('DFS')),
                _roleChip(t.help_role_prrc, section.audience.contains('PRRC')),
                ...topic.tags.map((tag) => Chip(label: Text(tag))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleChip(String label, bool active) {
    final cs = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label),
      selected: active,
      onSelected: (_) {},
      showCheckmark: active,
      selectedColor: cs.primaryContainer,
    );
  }

  Widget _buildStepCards(AppLocalizations t, HelpTopic topic, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.help_topic_steps, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...topic.steps.asMap().entries.map(
          (entry) => Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    child: Text('${entry.key + 1}'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.value.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        MarkdownBody(data: entry.value.description),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTips(AppLocalizations t, HelpTopic topic) {
    if (topic.tips.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.secondaryContainer.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline, color: cs.onSecondaryContainer),
                const SizedBox(width: 8),
                Text(t.help_topic_tips, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            ...topic.tips.map(
              (tip) => ListTile(
                dense: true,
                leading: const Icon(Icons.check_circle_outline),
                title: MarkdownBody(data: tip),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScreenshots(AppLocalizations t, HelpTopic topic) {
    if (topic.screenshots.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.help_topic_screens, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: topic.screenshots
              .map(
                (text) => Container(
                  width: 260,
                  height: 150,
                  decoration: BoxDecoration(
                    color: cs.surfaceVariant.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.outlineVariant),
                    image: null,
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Center(
                    child: Text(
                      text,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildLinks(AppLocalizations t, HelpSection section, HelpTopic topic) {
    final cs = Theme.of(context).colorScheme;
    final deeplink = Uri(
      path: '/help',
      queryParameters: {'section': section.id, 'topic': topic.id},
    ).toString();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.help_topic_links, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.link),
                  label: Text(t.help_copy_deeplink),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: deeplink));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(t.help_deeplink_copied)),
                      );
                    }
                  },
                ),
                ...topic.deepLinks.map(
                  (link) => OutlinedButton.icon(
                    icon: const Icon(Icons.push_pin_outlined),
                    label: Text(link),
                    onPressed: () {},
                  ),
                ),
                if (section.topics.length > 1)
                  Wrap(
                    spacing: 6,
                    children: section.topics
                        .map(
                          (t) => ActionChip(
                            label: Text(t.title),
                            avatar: const Icon(Icons.arrow_forward_ios, size: 16),
                            onPressed: () => _selectTopic(section.id, t.id),
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              t.help_topic_navigation,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResult {
  final String sectionId;
  final String topicId;
  final String sectionTitle;
  final String topicTitle;
  final String audience;
  final String summary;

  _SearchResult({
    required this.sectionId,
    required this.topicId,
    required this.sectionTitle,
    required this.topicTitle,
    required this.audience,
    required this.summary,
  });
}
