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

    final parts = text.split(RegExp(r'(\s+)'));
    for (final part in parts) {
      if (part.isEmpty) continue;

      // Whitespace behalten
      if (RegExp(r'^\s+$').hasMatch(part)) {
        spans.add(TextSpan(text: part, style: style));
        continue;
      }

      // Emoji → Twemoji
      if (_knownEmojis.contains(part)) {
        final size = (style.fontSize ?? 16) * 1.15;
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.0),
              child: Image.network(
                Twemoji.pngUrl(part),
                width: size,
                height: size,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => Text(part, style: style),
              ),
            ),
          ),
        );
        continue;
      }

      // Normaler Text
      spans.add(TextSpan(text: part, style: style));
    }

    return spans;
  }
}
