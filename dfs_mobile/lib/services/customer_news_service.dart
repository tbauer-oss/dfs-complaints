// lib/services/customer_news_service.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../api/client.dart';
import '../models/customer_news_entry.dart';

class CustomerNewsService {
  static const String endpoint = '/api/news';
  static const Duration cacheTtl = Duration(minutes: 2);

  CustomerNewsService({required ApiClient api}) : _api = api;

  final ApiClient _api;

  List<CustomerNewsEntry>? _cache;
  DateTime? _loadedAt;

  String? lastUrl;
  int? lastStatus;
  int? lastCount;
  String? lastError;

  String get apiBase => _api.baseUrl;

  String _extractMessage(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is String) return j['error'] as String;
      if (j is Map && j['message'] is String) return j['message'] as String;
      return body.isNotEmpty ? body : 'Unknown error';
    } catch (_) {
      return body.isNotEmpty ? body : 'Unknown error';
    }
  }

  bool _cacheValid() =>
      _cache != null &&
      _loadedAt != null &&
      DateTime.now().difference(_loadedAt!) < cacheTtl;

  Future<List<CustomerNewsEntry>> list({bool refresh = false}) async {
    if (!refresh && _cacheValid()) {
      return _cache!;
    }

    final uri = Uri.parse('${_api.baseUrl}$endpoint');
    lastUrl = uri.toString();
    lastError = null;

    if (kDebugMode) {
      debugPrint('[news] GET $uri refresh=$refresh');
    }

    final r = await http.get(
      uri,
      headers: const {'Content-Type': 'application/json'},
    );
    lastStatus = r.statusCode;

    if (kDebugMode) {
      debugPrint('[news] response ${r.statusCode} bytes=${r.body.length}');
    }

    if (r.statusCode < 200 || r.statusCode >= 300) {
      lastError = _extractMessage(r.body);
      if (kDebugMode) {
        debugPrint('[news] request failed: ${r.statusCode} $lastError');
      }
      throw ApiError(r.statusCode, lastError ?? 'news request failed');
    }

    final body = r.body.trim();
    dynamic decoded;
    try {
      decoded = body.isEmpty ? null : jsonDecode(body);
    } catch (e, stack) {
      lastError = 'invalid news response';
      if (kDebugMode) {
        debugPrint('[news] json decode failed: $e');
        debugPrint(stack.toString());
      }
      throw ApiError(r.statusCode, lastError!);
    }

    final List<CustomerNewsEntry> items = [];
    final List rawList = decoded is Map<String, dynamic>
        ? (decoded['items'] is List ? decoded['items'] as List : const [])
        : (decoded is List ? decoded : const []);

    var parseFailures = 0;
    for (final entry in rawList) {
      if (entry is Map<String, dynamic>) {
        try {
          items.add(CustomerNewsEntry.fromJson(entry));
        } catch (e, stack) {
          parseFailures += 1;
          if (kDebugMode) {
            debugPrint('[news] parse failed for entry: $e');
            debugPrint(stack.toString());
          }
        }
      } else {
        parseFailures += 1;
      }
    }

    if (items.isEmpty && rawList.isNotEmpty) {
      lastError = 'news parsing failed';
      throw ApiError(r.statusCode, lastError!);
    }

    lastCount = items.length;

    if (parseFailures > 0 && kDebugMode) {
      debugPrint('[news] parse failures=$parseFailures');
    }
    if (kDebugMode) {
      debugPrint('[news] parsed ${items.length} items');
    }

    _cache = items;
    _loadedAt = DateTime.now();
    return items;
  }

  void clearCache() {
    _cache = null;
    _loadedAt = null;
  }
}
