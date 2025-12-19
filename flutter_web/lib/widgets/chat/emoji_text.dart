import 'package:flutter/material.dart';

import 'emoji_data.dart';
import 'twemoji.dart';

class EmojiText {
  // Wir erkennen nur Emojis, die wir im Picker anbieten
  static final Set<String> _knownEmojis = {
    for (final entry in EmojiData.emojiCategories.entries)
      ...entry.value,
  };

  static List<InlineSpan> buildMessageSpans(String text, TextStyle style) {
    final spans = <InlineSpan>[];

    // Matches whitespace runs OR any non-whitespace runs, so whitespace is preserved as tokens.
    final tokenRe = RegExp(r'\s+|[^\s]+');

    for (final m in tokenRe.allMatches(text)) {
      final token = m.group(0);
      if (token == null || token.isEmpty) continue;

      // whitespace must be preserved
      if (RegExp(r'^\s+$').hasMatch(token)) {
        spans.add(TextSpan(text: token, style: style));
        continue;
      }

      // known unicode emoji token -> Twemoji
      if (_knownEmojis.contains(token)) {
        final size = (style.fontSize ?? 16) * 1.15;
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.0),
              child: Image.network(
                Twemoji.pngUrl(token),
                width: size,
                height: size,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => Text(token, style: style),
              ),
            ),
          ),
        );
        continue;
      }

      // normal text (keep as-is)
      spans.add(TextSpan(text: token, style: style));
    }

    return spans;
  }
}
