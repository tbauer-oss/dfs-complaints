// lib/services/customer_news_service.dart
import 'dart:convert';
import 'dart:html' as html;

import '../models/customer_news_entry.dart';

typedef NewsRequest = Future<html.HttpRequest> Function(
  String method,
  String path, {
  Map<String, String>? q,
  Object? body,
});

class CustomerNewsService {
  static const String endpoint = '/api/news';

  CustomerNewsService(this._request);

  final NewsRequest _request;

  Future<List<CustomerNewsEntry>> list({bool includeDrafts = false}) async {
    final res = await _request(
      'GET',
      endpoint,
      q: includeDrafts ? const {'includeDrafts': '1'} : null,
    );
    if (res.status != 200) {
      throw 'news GET: HTTP ${res.status} ${res.responseText}';
    }
    final txt = res.responseText?.trim() ?? '';
    dynamic data = txt.isEmpty ? const {} : jsonDecode(txt);
    if (data is Map && data['items'] is List) {
      data = data['items'];
    }
    final List list = data is List ? data : const [];
    return list
        .whereType<Map>()
        .map((e) => CustomerNewsEntry.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<({CustomerNewsEntry entry, int? status})> save({
    String? id,
    required String title,
    required String summary,
    required String category,
    required bool pinned,
    required bool draft,
    required DateTime publishedAt,
    String? linkLabel,
    String? linkUrl,
  }) async {
    final body = <String, dynamic>{
      if (id != null && id.isNotEmpty) 'id': id,
      'title': title,
      'summary': summary,
      'category': category,
      'pinned': pinned,
      'draft': draft,
      'published': !draft,
      'audience': 'customer',
      'publishedAt': publishedAt.toUtc().toIso8601String(),
      if (linkLabel != null) 'linkLabel': linkLabel,
      if (linkUrl != null) 'linkUrl': linkUrl,
    };
    final res = await _request('POST', endpoint, body: body);
    if (res.status != 200 && res.status != 201) {
      throw 'news POST: HTTP ${res.status} ${res.responseText}';
    }
    final txt = res.responseText?.trim() ?? '';
    final Map<String, dynamic> j = txt.isEmpty ? <String, dynamic>{} : jsonDecode(txt);
    return (entry: CustomerNewsEntry.fromJson(j), status: res.status);
  }

  Future<void> delete(String id) async {
    final res = await _request('DELETE', endpoint, body: {'id': id});
    if (res.status != 200 && res.status != 204) {
      throw 'news DELETE: HTTP ${res.status} ${res.responseText}';
    }
  }
}
