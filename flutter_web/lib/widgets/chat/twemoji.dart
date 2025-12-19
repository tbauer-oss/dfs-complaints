class Twemoji {
  static const String _basePng =
      'https://cdnjs.cloudflare.com/ajax/libs/twemoji/14.0.2/72x72/';

  /// Converts a Unicode emoji to a Twemoji PNG filename.
  /// Removes variation selectors FE0F / FE0E.
  static String toCodepoints(String emoji) {
    final cps = <int>[];
    for (final r in emoji.runes) {
      if (r == 0xFE0F || r == 0xFE0E) continue;
      cps.add(r);
    }
    return cps.map((c) => c.toRadixString(16)).join('-');
  }

  static String pngUrl(String emoji) => '$_basePng${toCodepoints(emoji)}.png';
}
