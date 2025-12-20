class TeamsDeepLink {
  final Uri primary;
  final Uri fallback;

  const TeamsDeepLink({required this.primary, required this.fallback});
}

class TeamsLinkBuilder {
  static const List<String> defaultInternalDomains = ['dfs-diamon.de'];

  static bool isValidEmail(String? email) {
    if (email == null) return false;
    final trimmed = email.trim();
    if (trimmed.isEmpty) return false;
    final parts = trimmed.split('@');
    if (parts.length != 2) return false;
    return parts[0].isNotEmpty && parts[1].contains('.');
  }

  static bool isInternalEmail(String? email, {List<String> domains = defaultInternalDomains}) {
    if (!isValidEmail(email)) return false;
    final domain = email!.trim().toLowerCase().split('@').last;
    return domains.any((d) => domain == d.toLowerCase());
  }

  static TeamsDeepLink buildChatLink(String email, {String? message}) {
    final params = <String, String>{'users': email};
    if (message != null && message.trim().isNotEmpty) {
      params['message'] = message.trim();
    }
    final web = Uri.https('teams.microsoft.com', '/l/chat/0/0', params);
    final app = Uri.parse('msteams://teams.microsoft.com/l/chat/0/0?${Uri(queryParameters: params).query}');
    return TeamsDeepLink(primary: app, fallback: web);
  }

  static TeamsDeepLink buildVideoCallLink(String email) {
    final params = <String, String>{'users': email, 'withvideo': 'true'};
    final web = Uri.https('teams.microsoft.com', '/l/call/0/0', params);
    final app = Uri.parse('msteams://teams.microsoft.com/l/call/0/0?${Uri(queryParameters: params).query}');
    return TeamsDeepLink(primary: app, fallback: web);
  }

  static TeamsDeepLink buildMeetingLink({List<String> participants = const [], String? topic}) {
    final params = <String, String>{};
    if (participants.isNotEmpty) {
      params['attendees'] = participants.join(',');
    }
    if (topic != null && topic.trim().isNotEmpty) {
      params['subject'] = topic.trim();
    }
    final web = Uri.https('teams.microsoft.com', '/l/meeting/new', params);
    final app = Uri.parse('msteams://teams.microsoft.com/l/meeting/new?${Uri(queryParameters: params).query}');
    return TeamsDeepLink(primary: app, fallback: web);
  }

  static String buildContextMessage({required String label, required String url}) {
    final trimmedLabel = label.trim();
    final trimmedUrl = url.trim();
    if (trimmedLabel.isEmpty) return trimmedUrl;
    if (trimmedUrl.isEmpty) return trimmedLabel;
    return '$trimmedLabel\n$trimmedUrl';
  }
}
