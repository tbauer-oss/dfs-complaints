import 'package:flutter/services.dart' show rootBundle;

import '../models/help_content.dart';

/// Loads localized help center content from JSON assets.
class HelpCenterLoader {
  static const Map<String, String> _assetByLang = {
    'de': 'assets/help/help_de.json',
    'en': 'assets/help/help_en.json',
  };

  /// Load a localized help center. Falls back to English and then German.
  Future<HelpCenterContent> load(String locale) async {
    final lang = locale.toLowerCase();
    final List<String> candidates = [
      if (_assetByLang.containsKey(lang)) lang,
      'en',
      'de',
    ];

    for (final candidate in candidates) {
      final asset = _assetByLang[candidate];
      if (asset == null) continue;
      try {
        final jsonString = await rootBundle.loadString(asset);
        return HelpCenterContent.fromJsonString(jsonString);
      } catch (_) {
        // try next fallback
      }
    }

    throw Exception('No help center content available');
  }
}
