// lib/services/chat_service.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/client.dart';
import '../models/chat_message.dart';
import '../models/portal_user.dart';
import '../models/chat_user.dart';

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
    const path = '/api/admin/users';
    final uri = api.buildUri(path, query: {'scope': 'staff', 'includeInactive': 'true'});
    final response = await http.get(uri, headers: api.portalHeadersFor(path));
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
    const path = '/api/chat/v1/conversations';
    final uri = api.buildUri(path, query: {'limit': '50'});
    final response = await http.get(uri, headers: api.portalHeadersFor(path));
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    final list = jsonBody['conversations'] as List<dynamic>? ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(ChatConversationSummary.fromJson)
        .toList(growable: false);
  }

  Future<ChatConversationSummary> ensureDirectConversation(
    String participantEmail,
    String participantDisplayName,
    {String? currentUserId, String? currentUserDisplayName}
  ) async {
    const path = '/api/chat/v1/dm';
    final uri = api.buildUri(path);
    final payload = {
      'peerEmail': participantEmail,
    };
    final response = await http.post(uri, headers: api.portalHeadersFor(path), body: jsonEncode(payload));
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    final convId = (jsonBody['convId'] ?? jsonBody['conversationId'] ?? '').toString();
    if (convId.isEmpty) throw Exception('invalid conversation response');

    try {
      final conversations = await fetchConversations();
      final found = conversations.firstWhere(
        (c) => c.conversationId == convId,
        orElse: () => ChatConversationSummary(
          conversationId: convId,
          type: 'dm',
          title: participantDisplayName,
          participants: [
            ChatParticipant(userId: participantEmail, displayName: participantDisplayName, email: participantEmail),
            if (currentUserId != null)
              ChatParticipant(
                userId: currentUserId,
                displayName: currentUserDisplayName ?? 'Du',
              ),
          ],
          lastMessage: null,
          lastAuthor: null,
          lastMessageAt: null,
        ),
      );
      return found;
    } catch (_) {
      return ChatConversationSummary(
        conversationId: convId,
        type: 'dm',
        title: participantDisplayName,
        participants: [
          ChatParticipant(userId: participantEmail, displayName: participantDisplayName, email: participantEmail),
          if (currentUserId != null)
            ChatParticipant(userId: currentUserId, displayName: currentUserDisplayName ?? 'Du'),
        ],
        lastMessage: null,
        lastAuthor: null,
        lastMessageAt: null,
      );
    }
  }

  Future<ChatConversationSummary> createGroup({
    required String title,
    required List<String> memberUids,
    String? initialMessage,
    String? groupIcon,
  }) async {
    const path = '/api/chat/v1/groups';
    final uri = api.buildUri(path);
    final payload = {
      'title': title,
      'memberUids': memberUids,
      if (initialMessage != null && initialMessage.trim().isNotEmpty) 'initialMessage': initialMessage,
      if (groupIcon != null) 'meta': {'groupIcon': groupIcon},
    };
    final response = await http.post(uri, headers: api.portalHeadersFor(path), body: jsonEncode(payload));
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    final data = jsonBody['conversation'] as Map<String, dynamic>;
    return ChatConversationSummary.fromJson(data);
  }

  Future<List<ChatUserSummary>> searchUsers(String query) async {
    const path = '/api/chat/v1/users';
    final uri = api.buildUri(path, query: {'query': query, 'limit': '50'});
    final response = await http.get(uri, headers: api.portalHeadersFor(path));
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    final list = jsonBody['users'] as List<dynamic>? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(ChatUserSummary.fromJson).toList(growable: false);
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
    final path = '/api/chat/v1/conversations/$convId/messages';
    final uri = api.buildUri(path, query: query);
    final response = await http.get(uri, headers: api.portalHeadersFor(path));
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
    final path = '/api/chat/v1/conversations/$convId/messages';
    final uri = api.buildUri(path);
    final payload = {
      'body': body,
      if (msgId != null) 'msgId': msgId,
    };
    final response = await http.post(uri, headers: api.portalHeadersFor(path), body: jsonEncode(payload));
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    return ChatMessage.fromJson(jsonBody['message'] as Map<String, dynamic>);
  }

  Future<ChatMessage> updateMessage(String messageId, String body) async {
    final path = '/api/chat/v1/messages/$messageId';
    final uri = api.buildUri(path);
    final payload = {'body': body};
    final response = await http.patch(uri, headers: api.portalHeadersFor(path), body: jsonEncode(payload));
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    return ChatMessage.fromJson(jsonBody['message'] as Map<String, dynamic>);
  }

  Future<ChatMessage> deleteMessage(String messageId) async {
    final path = '/api/chat/v1/messages/$messageId';
    final uri = api.buildUri(path);
    final response = await http.delete(uri, headers: api.portalHeadersFor(path));
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    return ChatMessage.fromJson(jsonBody['message'] as Map<String, dynamic>);
  }

  Future<void> deleteConversation(String convId) async {
    final path = '/api/chat/v1/conversations/$convId';
    final uri = api.buildUri(path);
    final response = await http.delete(uri, headers: api.portalHeadersFor(path));
    if (response.statusCode == 204) return;
    api.assertSuccess(response);
  }

  Future<Map<String, dynamic>> updateConversationGroupIcon(
    String convId,
    String? groupIcon,
  ) async {
    final path = '/api/chat/v1/conversations/$convId/meta';
    final uri = api.buildUri(path);
    final payload = {'groupIcon': groupIcon};
    final response = await http.patch(uri, headers: api.portalHeadersFor(path), body: jsonEncode(payload));
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    if (jsonBody['meta'] is Map<String, dynamic>) {
      return Map<String, dynamic>.from(jsonBody['meta'] as Map<String, dynamic>);
    }
    return payload;
  }
}
