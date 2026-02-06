import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/lang_utils.dart';

/// Provides a best-effort locale suggestion based on the client's IP address.
class GeoLocaleService {
  GeoLocaleService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Attempts to resolve the preferred language code (e.g. `fr`).
  ///
  /// Returns `null` when no supported language could be determined.
  Future<String?> detectLangCode() async {
    try {
      final response = await _client
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final langs = _pickFromLanguages(data['languages']);
      if (langs != null) return langs;

      return _langForCountryCode(data['country_code']);
    } on TimeoutException catch (e) {
      debugPrint('[geo_locale] detection timed out: $e');
      return null;
    } catch (e) {
      debugPrint('[geo_locale] detection failed: $e');
      return null;
    }
  }

  String? _pickFromLanguages(dynamic languagesField) {
    final raw = (languagesField ?? '').toString().trim();
    if (raw.isEmpty) return null;

    final parts = raw.split(',');
    for (final part in parts) {
      final lang = part.split('-').first.trim().toLowerCase();
      if (lang.isEmpty) continue;
      if (isSupportedLangCode(lang)) return lang;
    }
    return null;
  }

  String? _langForCountryCode(dynamic countryCode) {
    final cc = (countryCode ?? '').toString().toUpperCase();
    if (cc.isEmpty) return null;

    switch (cc) {
      case 'FR':
      case 'GF':
      case 'PF':
      case 'TF':
      case 'MC':
        return 'fr';
      case 'DE':
      case 'AT':
      case 'CH':
      case 'LI':
      case 'LU':
        return 'de';
      case 'IT':
      case 'SM':
      case 'VA':
        return 'it';
      case 'ES':
      case 'MX':
      case 'AR':
      case 'CL':
      case 'CO':
      case 'PE':
      case 'VE':
      case 'UY':
      case 'PY':
      case 'BO':
      case 'CR':
      case 'CU':
      case 'DO':
      case 'EC':
      case 'GT':
      case 'HN':
      case 'NI':
      case 'PA':
      case 'PR':
      case 'SV':
        return 'es';
      case 'US':
      case 'GB':
      case 'IE':
      case 'AU':
      case 'NZ':
      case 'CA':
      default:
        return 'en';
    }
  }

  void dispose() => _client.close();
}
