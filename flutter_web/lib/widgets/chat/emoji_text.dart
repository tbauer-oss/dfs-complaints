import 'package:flutter/material.dart';

import 'emoji_data.dart';

class EmojiText {
  static final RegExp _codeRegex = RegExp(r'(:[a-z0-9_]+:)');

  static List<InlineSpan> buildMessageSpans(String text, TextStyle style) {
    final spans = <InlineSpan>[];
    int last = 0;

    for (final m in _codeRegex.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start), style: style));
      }

      final code = m.group(0)!;
      final ce = EmojiData.customEmojiByCode[code];

      if (ce != null) {
        final size = (style.fontSize ?? 16) * 1.15;
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Image.asset(
                ce.assetPath,
                width: size,
                height: size,
                filterQuality: FilterQuality.high,
                errorBuilder: (context, error, stackTrace) => Text(
                  ce.shortcode,
                  style: style,
                ),
              ),
            ),
          ),
        );
      } else {
        spans.add(TextSpan(text: code, style: style));
      }

      last = m.end;
    }

    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: style));
    }

    return spans;
  }
}
