import 'package:flutter/material.dart';

import 'emoji_data.dart';

class EmojiPicker extends StatefulWidget {
  final ValueChanged<String> onInsertToken;

  const EmojiPicker({super.key, required this.onInsertToken});

  @override
  State<EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<EmojiPicker> {
  EmojiCategory _selectedCategory = EmojiCategory.smileys;
  String _query = '';
  final List<String> _recentTokens = [];

  List<EmojiCategory> get _categories => EmojiCategory.values;

  void _setCategory(EmojiCategory next) {
    setState(() => _selectedCategory = next);
  }

  void _setQuery(String value) {
    setState(() => _query = value.trim());
  }

  void _addRecent(String token) {
    if (token.isEmpty) return;
    setState(() {
      _recentTokens.remove(token);
      _recentTokens.insert(0, token);
      if (_recentTokens.length > 32) {
        _recentTokens.removeRange(32, _recentTokens.length);
      }
    });
  }

  List<_EmojiItem> _buildItems() {
    if (_query.isNotEmpty) {
      final queryLower = _query.toLowerCase();
      final customMatches = EmojiData.customEmojisDental
          .where((e) => e.label.toLowerCase().contains(queryLower) || e.shortcode.contains(queryLower))
          .map((e) => _EmojiItem(token: e.shortcode, custom: e))
          .toList();
      final unicodeMatches = EmojiData.emojiCategories.values
          .expand((list) => list)
          .where((e) => e.contains(_query))
          .map((e) => _EmojiItem(token: e))
          .toList();
      return [...customMatches, ...unicodeMatches];
    }

    switch (_selectedCategory) {
      case EmojiCategory.recent:
        return _recentTokens
            .map((token) => _EmojiItem(token: token, custom: EmojiData.customEmojiByCode[token]))
            .toList();
      case EmojiCategory.dental:
        return EmojiData.customEmojisDental
            .map((e) => _EmojiItem(token: e.shortcode, custom: e))
            .toList();
      default:
        return (EmojiData.emojiCategories[_selectedCategory] ?? [])
            .map((e) => _EmojiItem(token: e))
            .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _buildItems();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: TextField(
            onChanged: _setQuery,
            decoration: InputDecoration(
              hintText: 'Emoji suchen',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () => _setQuery(''),
                    ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: _categories.map((c) {
                final selected = _selectedCategory == c && _query.isEmpty;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _setCategory(c),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceVariant.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant.withOpacity(0.6),
                        ),
                      ),
                      child: Icon(
                        EmojiData.categoryIcon(c),
                        size: 18,
                        color: selected
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    _selectedCategory == EmojiCategory.recent
                        ? 'Keine kürzlichen Emojis'
                        : 'Keine Emojis gefunden',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columnCount = (constraints.maxWidth / 36)
                        .floor()
                        .clamp(8, 10);
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columnCount,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return InkResponse(
                          onTap: () {
                            widget.onInsertToken(item.token);
                            _addRecent(item.token);
                          },
                          radius: 20,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: item.custom != null
                                  ? Image.asset(
                                      item.custom!.assetPath,
                                      width: 22,
                                      height: 22,
                                      filterQuality: FilterQuality.high,
                                      errorBuilder: (context, error, stackTrace) => Text(
                                        item.custom!.shortcode,
                                        style: const TextStyle(fontSize: 10),
                                        textAlign: TextAlign.center,
                                      ),
                                    )
                                  : Text(
                                      item.token,
                                      style: const TextStyle(fontSize: 18),
                                    ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EmojiItem {
  final String token;
  final CustomEmoji? custom;

  const _EmojiItem({required this.token, this.custom});
}
