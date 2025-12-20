import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/teams_link_builder.dart';

class TeamsActionsRow extends StatelessWidget {
  final String userEmail;
  final String? displayName;
  final String contextLabel;
  final String contextUrl;
  final bool showMeeting;
  final bool showLabels;
  final List<String> internalDomains;

  const TeamsActionsRow({
    super.key,
    required this.userEmail,
    required this.contextLabel,
    required this.contextUrl,
    this.displayName,
    this.showMeeting = false,
    this.showLabels = true,
    this.internalDomains = TeamsLinkBuilder.defaultInternalDomains,
  });

  Future<void> _copyContext(BuildContext context) async {
    final text = TeamsLinkBuilder.buildContextMessage(
      label: contextLabel,
      url: contextUrl,
    );
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kontext kopiert – in Teams einfügen, falls nötig.')),
    );
  }

  Future<bool> _launchTeamsUri(Uri uri, {LaunchMode mode = LaunchMode.externalApplication}) async {
    try {
      return await launchUrl(uri, mode: mode);
    } catch (_) {
      return false;
    }
  }

  Future<void> _openTeamsLink(
    BuildContext context, {
    required TeamsDeepLink link,
  }) async {
    await _copyContext(context);
    final launchedPrimary = await _launchTeamsUri(link.primary);
    if (launchedPrimary) return;
    await _launchTeamsUri(link.fallback);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Teams konnte nicht direkt geöffnet werden – Web-Version geöffnet. Kontext wurde kopiert.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!TeamsLinkBuilder.isInternalEmail(userEmail, domains: internalDomains)) {
      return const SizedBox.shrink();
    }

    final chatLink = TeamsLinkBuilder.buildChatLink(
      [userEmail],
      message: TeamsLinkBuilder.buildContextMessage(
        label: contextLabel,
        url: contextUrl,
      ),
    );
    final videoLink = TeamsLinkBuilder.buildVideoCallLink([userEmail]);
    final meetingLink = TeamsLinkBuilder.buildMeetingLink(
      participants: [userEmail],
      topic: contextLabel,
    );

    final tooltip = 'In Microsoft Teams öffnen';
    final labelStyle = Theme.of(context).textTheme.labelLarge;
    final buttonStyle = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
    final iconSize = showLabels ? 18.0 : 20.0;

    Widget buildButton({
      required IconData icon,
      required String label,
      required VoidCallback onPressed,
    }) {
      if (showLabels) {
        return TextButton.icon(
          onPressed: onPressed,
          style: buttonStyle,
          icon: Icon(icon, size: iconSize),
          label: Text(label, style: labelStyle),
        );
      }
      return IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: iconSize),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (showLabels)
          Tooltip(
            message: tooltip,
            child: buildButton(
              icon: Icons.chat_bubble_outline,
              label: 'Teams-Chat',
              onPressed: () => _openTeamsLink(context, link: chatLink),
            ),
          )
        else
          buildButton(
            icon: Icons.chat_bubble_outline,
            label: 'Teams-Chat',
            onPressed: () => _openTeamsLink(context, link: chatLink),
          ),
        if (showLabels)
          Tooltip(
            message: tooltip,
            child: buildButton(
              icon: Icons.videocam_outlined,
              label: 'Video-Call',
              onPressed: () => _openTeamsLink(context, link: videoLink),
            ),
          )
        else
          buildButton(
            icon: Icons.videocam_outlined,
            label: 'Video-Call',
            onPressed: () => _openTeamsLink(context, link: videoLink),
          ),
        if (showMeeting && showLabels)
          Tooltip(
            message: tooltip,
            child: buildButton(
              icon: Icons.calendar_month_outlined,
              label: 'Meeting',
              onPressed: () => _openTeamsLink(context, link: meetingLink),
            ),
          )
        else if (showMeeting)
          buildButton(
            icon: Icons.calendar_month_outlined,
            label: 'Meeting',
            onPressed: () => _openTeamsLink(context, link: meetingLink),
          ),
      ],
    );
  }
}
