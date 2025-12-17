// lib/services/chat_service.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/client.dart';
import '../models/chat_message.dart';
import '../models/portal_user.dart';

class ChatService {
  final ApiClient api;
  Future<List<PortalUserSummary>>? _staffUsersFuture;

  ChatService(this.api);

  static String normalizeUserId(String value) {
    final trimmed = value.trim().toLowerCase();
    if (!trimmed.contains('@')) return trimmed;
    return base64Url.encode(utf8.encode(trimmed)).replaceAll('=', '');
  }

  String buildMessageId(String convId) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '$convId:$ts';
  }

  Future<List<PortalUserSummary>> fetchStaffUsers({bool forceRefresh = false}) {
    if (_staffUsersFuture != null && !forceRefresh) return _staffUsersFuture!;
    _staffUsersFuture = _loadStaffUsers();
    return _staffUsersFuture!;
  }

  Future<List<PortalUserSummary>> _loadStaffUsers() async {
    final uri = api.buildUri('/api/admin/users', query: {'scope': 'staff', 'includeInactive': 'true'});
    final response = await http.get(uri, headers: api.portalHeaders());
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    final list = jsonBody['users'] as List<dynamic>? ?? const [];
    final users = list
        .whereType<Map<String, dynamic>>()
        .map(PortalUserSummary.fromJson)
        .toList(growable: false);
    users.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return users;
  }

  Future<List<ChatConversationSummary>> fetchConversations() async {
    final uri = api.buildUri('/api/chat/v1/conversations');
    final response = await http.get(uri, headers: api.portalHeaders());
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    final list = jsonBody['conversations'] as List<dynamic>? ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(ChatConversationSummary.fromJson)
        .toList(growable: false);
  }

  Future<ChatConversationSummary> ensureDirectConversation(
    String participantId,
    String participantDisplayName,
  ) async {
    final uri = api.buildUri('/api/chat/v1/dm');
    final payload = {
      'participant': participantId,
      'displayName': participantDisplayName,
    };
    final response = await http.post(uri, headers: api.portalHeaders(), body: jsonEncode(payload));
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    final data = jsonBody['conversation'] as Map<String, dynamic>;
    return ChatConversationSummary.fromJson(data);
  }

  Future<ChatTimelineResponse> fetchMessages(
    String convId, {
    int limit = 50,
    int? afterTs,
    int? beforeTs,
  }) async {
    final query = <String, dynamic>{'limit': '$limit'};
    if (afterTs != null) query['afterTs'] = '$afterTs';
    if (beforeTs != null) query['beforeTs'] = '$beforeTs';
    final uri = api.buildUri('/api/chat/v1/conversations/$convId/messages', query: query);
    final response = await http.get(uri, headers: api.portalHeaders());
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    final messages = (jsonBody['messages'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList(growable: false);
    return ChatTimelineResponse(
      messages: messages,
      hasMoreBefore: jsonBody['hasMoreBefore'] == true,
      hasMoreAfter: jsonBody['hasMoreAfter'] == true,
    );
  }

  Future<ChatMessage> sendMessage(String convId, String body, {String? msgId}) async {
    final uri = api.buildUri('/api/chat/v1/conversations/$convId/messages');
    final payload = {
      'body': body,
      if (msgId != null) 'msgId': msgId,
    };
    final response = await http.post(uri, headers: api.portalHeaders(), body: jsonEncode(payload));
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    return ChatMessage.fromJson(jsonBody['message'] as Map<String, dynamic>);
  }
}
