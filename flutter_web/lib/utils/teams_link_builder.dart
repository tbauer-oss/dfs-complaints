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

  static TeamsDeepLink buildChatLink(List<String> users, {String? message}) {
    final usersValue = _buildUsersValue(users);
    final params = <String, String>{'users': usersValue};
    if (message != null && message.trim().isNotEmpty) {
      params['message'] = Uri.encodeQueryComponent(message.trim());
    }
    final web = _buildTeamsUri(path: '/l/chat/0/0', params: params);
    return TeamsDeepLink(primary: web, fallback: _buildTeamsWebHome());
  }

  static TeamsDeepLink buildVideoCallLink(List<String> users) {
    final usersValue = _buildUsersValue(users);
    final params = <String, String>{'users': usersValue};
    final web = _buildTeamsUri(path: '/l/call/0/0', params: params);
    return TeamsDeepLink(primary: web, fallback: _buildTeamsWebHome());
  }

  static TeamsDeepLink buildMeetingLink({List<String> participants = const [], String? topic}) {
    final params = <String, String>{};
    if (participants.isNotEmpty) {
      params['attendees'] = participants.map(Uri.encodeQueryComponent).join(',');
    }
    if (topic != null && topic.trim().isNotEmpty) {
      params['subject'] = Uri.encodeQueryComponent(topic.trim());
    }
    final web = _buildTeamsUri(path: '/l/meeting/new', params: params);
    return TeamsDeepLink(primary: web, fallback: _buildTeamsWebHome());
  }

  static String buildContextMessage({required String label, required String url}) {
    final trimmedLabel = label.trim();
    final trimmedUrl = url.trim();
    if (trimmedLabel.isEmpty) return trimmedUrl;
    if (trimmedUrl.isEmpty) return trimmedLabel;
    return '$trimmedLabel\n$trimmedUrl';
  }

  static Uri _buildTeamsWebHome() {
    return Uri.https('teams.microsoft.com', '/');
  }

  static String _buildUsersValue(List<String> users) {
    return users
        .map((user) => user.trim())
        .where((user) => user.isNotEmpty)
        .map(Uri.encodeQueryComponent)
        .join(',');
  }

  static Uri _buildTeamsUri({required String path, required Map<String, String> params}) {
    final query = params.entries.map((entry) => '${entry.key}=${entry.value}').join('&');
    return Uri(
      scheme: 'https',
      host: 'teams.microsoft.com',
      path: path,
      query: query,
    );
  }
}
