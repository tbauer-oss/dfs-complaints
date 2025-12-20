import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../utils/teams_link_builder.dart';

class ChatTeamsActionsRow extends StatelessWidget {
  final List<String> participantEmails;
  final String conversationTitle;
  final String conversationId;
  final String currentUserEmail;
  final bool isGroup;
  final String? referenceId;

  const ChatTeamsActionsRow({
    super.key,
    required this.participantEmails,
    required this.conversationTitle,
    required this.conversationId,
    required this.currentUserEmail,
    required this.isGroup,
    this.referenceId,
  });

  String _buildContextText() {
    final trimmedTitle = conversationTitle.trim();
    final title = trimmedTitle.isEmpty ? 'Ohne Titel' : trimmedTitle;
    final buffer = StringBuffer('DFS Connect+ – Konversation: $title');
    buffer.writeln();
    buffer.write('Route: chat:$conversationId');
    final ref = referenceId?.trim();
    if (ref != null && ref.isNotEmpty) {
      buffer.writeln();
      buffer.write('Bezug: $ref');
    }
    return buffer.toString();
  }

  List<String> _normalizeEmails(Iterable<String> emails) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in emails) {
      final normalized = raw.trim().toLowerCase();
      if (normalized.isEmpty) continue;
      if (!TeamsLinkBuilder.isValidEmail(normalized)) continue;
      if (seen.add(normalized)) {
        result.add(normalized);
      }
    }
    return result;
  }

  List<String> _counterparts(List<String> normalizedEmails) {
    final current = currentUserEmail.trim().toLowerCase();
    return normalizedEmails.where((email) => email != current).toList(growable: false);
  }

  bool _allInternal(List<String> emails) {
    return emails.isNotEmpty && emails.every(TeamsLinkBuilder.isDfsInternal);
  }

  Future<void> _openTeamsLink(BuildContext context, Uri primary) async {
    final contextText = _buildContextText();
    await Clipboard.setData(ClipboardData(text: contextText));
    final messenger = ScaffoldMessenger.of(context);
    bool launched = false;
    try {
      launched = await launchUrl(primary, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched) {
      await launchUrl(
        Uri.https('teams.microsoft.com', '/'),
        mode: LaunchMode.externalApplication,
      );
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Teams konnte nicht direkt geöffnet werden – Web-Version geöffnet. Kontext wurde kopiert.',
            ),
          ),
        );
      }
      return;
    }
    if (context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Teams geöffnet. Kontext wurde kopiert.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final normalizedParticipants = _normalizeEmails(participantEmails);
    if (normalizedParticipants.isEmpty) {
      return const SizedBox.shrink();
    }
    final counterparts = _counterparts(normalizedParticipants);
    final allInternal = _allInternal(normalizedParticipants);
    final isEnabled = allInternal && counterparts.isNotEmpty;
    final targetEmails = isGroup ? normalizedParticipants : counterparts;
    final tooltip = isEnabled ? 'In Microsoft Teams öffnen' : 'Teams nur für DFS intern';

    final chatLink = TeamsLinkBuilder.buildChatLink(
      targetEmails,
      message: _buildContextText(),
    );
    final callLink = TeamsLinkBuilder.buildCallLink(targetEmails);

    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Tooltip(
          message: tooltip,
          child: IconButton(
            tooltip: 'In Teams chatten',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: isEnabled ? () => _openTeamsLink(context, chatLink.primary) : null,
          ),
        ),
        Tooltip(
          message: tooltip,
          child: IconButton(
            tooltip: 'Teams Call',
            icon: const Icon(Icons.call_outlined),
            onPressed: isEnabled ? () => _openTeamsLink(context, callLink.primary) : null,
          ),
        ),
      ],
    );
  }
}
