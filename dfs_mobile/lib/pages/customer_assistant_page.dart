import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../models/chatbot.dart';

class CustomerAssistantPage extends StatefulWidget {
  final ApiClient api;
  const CustomerAssistantPage({super.key, required this.api});

  @override
  State<CustomerAssistantPage> createState() => _CustomerAssistantPageState();
}

class _AssistantEntry {
  final bool fromUser;
  final String text;
  final ChatbotAnswer? answer;

  const _AssistantEntry.user(this.text)
      : fromUser = true,
        answer = null;

  const _AssistantEntry.assistant(this.text, this.answer) : fromUser = false;
}

class _CustomerAssistantPageState extends State<CustomerAssistantPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatbotMessage> _history = [];
  final List<_AssistantEntry> _entries = [];
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      _scrollController.animateTo(
        position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendPrompt([String? preset]) async {
    if (_sending) return;
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty) return;

    final entry = _AssistantEntry.user(text);
    setState(() {
      _entries.add(entry);
      _sending = true;
    });
    _controller.clear();

    try {
      final lang = Localizations.localeOf(context).languageCode;
      final answer = await widget.api.askChatbot(
        question: text,
        history: List<ChatbotMessage>.unmodifiable(_history),
        lang: lang,
      );
      if (!mounted) return;
      setState(() {
        _entries.add(_AssistantEntry.assistant(answer.answer, answer));
        _history
          ..add(ChatbotMessage.user(text))
          ..add(ChatbotMessage.assistant(answer.answer));
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _entries.remove(entry);
      });
      _controller.text = text;
      final t = AppLocalizations.of(context);
      final prefix = t?.error ?? 'Error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$prefix: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final ideas = <String?>[
      t.customerAssistantIdeaStatus,
      t.customerAssistantIdeaEvidence,
      t.customerAssistantIdeaTimeline,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).toList(growable: false);

    final conversation = <Widget>[
      _AssistantHero(
        title: t.customerAssistantTitle,
        subtitle: t.customerAssistantSubtitle,
      ),
      if (ideas.isNotEmpty) ...[
        const SizedBox(height: 8),
        _IdeaChips(ideas: ideas, onTap: _sendPrompt, label: t.customerAssistantIdeasTitle),
      ],
      const SizedBox(height: 12),
      if (_entries.isEmpty)
        _EmptyState(message: t.customerAssistantEmptyState)
      else
        ..._entries.map((entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _AssistantBubble(entry: entry, cs: cs, t: t),
            )),
      const SizedBox(height: 24),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(t.customerAssistantTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: t.back,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: conversation,
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: t.customerAssistantInputHint,
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _sending ? null : () => _sendPrompt(),
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(t.customerAssistantSend),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                t.customerAssistantDisclaimer,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantHero extends StatelessWidget {
  final String title;
  final String subtitle;
  const _AssistantHero({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            cs.secondaryContainer.withOpacity(0.6),
            cs.surfaceVariant.withOpacity(0.3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.onSecondaryContainer.withOpacity(0.08),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
            ),
            child: Icon(Icons.auto_awesome, color: cs.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IdeaChips extends StatelessWidget {
  final List<String> ideas;
  final void Function(String) onTap;
  final String label;
  const _IdeaChips({required this.ideas, required this.onTap, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ideas
              .map(
                (idea) => ActionChip(
                  label: Text(idea),
                  avatar: const Icon(Icons.chat_bubble_outline, size: 18),
                  onPressed: () => onTap(idea),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  final _AssistantEntry entry;
  final ColorScheme cs;
  final AppLocalizations t;
  const _AssistantBubble({required this.entry, required this.cs, required this.t});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = entry.fromUser;
    final bubbleColor = isUser
        ? cs.primary.withOpacity(theme.brightness == Brightness.light ? 0.14 : 0.25)
        : cs.surfaceVariant.withOpacity(theme.brightness == Brightness.light ? 0.7 : 0.35);
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final radius = isUser
        ? const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(6),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(6),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          );

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: radius,
            border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.text,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
                if (!isUser && entry.answer != null) ...[
                  const SizedBox(height: 10),
                  _AnswerMeta(answer: entry.answer!, t: t),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnswerMeta extends StatelessWidget {
  final ChatbotAnswer answer;
  final AppLocalizations t;
  const _AnswerMeta({required this.answer, required this.t});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final badgeColor = answer.isFallback ? cs.tertiary : cs.primary;
    final badgeIcon = answer.isFallback ? Icons.info_outline : Icons.auto_awesome;
    final badgeLabel = answer.isFallback ? t.customerAssistantFallbackBadge : t.customerAssistantAiBadge;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(badgeIcon, size: 16, color: badgeColor),
            const SizedBox(width: 6),
            Text(
              badgeLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: badgeColor,
              ),
            ),
          ],
        ),
        if (answer.sources.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            t.customerAssistantSourcesTitle,
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          ...answer.sources.take(3).map(
                (source) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(
                        child: Text(
                          source.title,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 4),
          Text(
            t.customerAssistantSourcesHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.chat_bubble_outline, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
