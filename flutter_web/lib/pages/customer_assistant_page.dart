import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../models/chatbot.dart';
import '../widgets/legal_footer.dart';

class CustomerAssistantPage extends StatefulWidget {
  final ApiClient api;
  const CustomerAssistantPage({super.key, required this.api});

  @override
  State<CustomerAssistantPage> createState() => _CustomerAssistantPageState();
}

class _ChatEntry {
  final bool isUser;
  final String text;
  final bool isPending;

  const _ChatEntry({required this.isUser, required this.text, this.isPending = false});

  _ChatEntry copyWith({String? text, bool? isPending}) =>
      _ChatEntry(isUser: isUser, text: text ?? this.text, isPending: isPending ?? this.isPending);
}

class _CustomerAssistantPageState extends State<CustomerAssistantPage> {
  final _input = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatEntry> _messages = [];
  final List<ChatbotMessage> _history = [];

  bool _busy = false;
  ChatbotAnswer? _lastAnswer;

  @override
  void dispose() {
    _input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<String> _suggestions(AppLocalizations t) => [
        t.customerAssistantIdeaStatus,
        t.customerAssistantIdeaEvidence,
        t.customerAssistantIdeaTimeline,
      ];

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _sendPrompt([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    final localeTag = Localizations.localeOf(context).toLanguageTag();

    setState(() {
      _busy = true;
      _messages.add(_ChatEntry(isUser: true, text: text));
      _messages.add(const _ChatEntry(isUser: false, text: '', isPending: true));
      _input.clear();
    });
    _scrollToEnd();

    try {
      final answer = await widget.api.askChatbot(
        question: text,
        history: List.unmodifiable(_history),
        lang: localeTag,
      );
      if (!mounted) return;
      setState(() {
        _history
          ..add(ChatbotMessage.user(text))
          ..add(ChatbotMessage.assistant(answer.answer));
        final lastIndex = _messages.length - 1;
        _messages[lastIndex] = _messages[lastIndex].copyWith(text: answer.answer, isPending: false);
        _busy = false;
        _lastAnswer = answer;
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_messages.isNotEmpty && _messages.last.isPending) {
          _messages.removeLast();
        }
        _busy = false;
      });
      final t = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t.error}: $e')),
      );
    }
  }

  Widget _buildHero(AppLocalizations t, ThemeData theme) {
    final gradientColors = [
      theme.colorScheme.primaryContainer.withOpacity(0.95),
      theme.colorScheme.secondaryContainer.withOpacity(0.85),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.12),
            offset: const Offset(0, 18),
            blurRadius: 48,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withOpacity(0.15),
                ),
                child: Icon(Icons.auto_awesome, color: theme.colorScheme.primary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  t.customerAssistantTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            t.customerAssistantSubtitle,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer.withOpacity(0.9),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            t.customerAssistantIdeasTitle,
            style: theme.textTheme.labelLarge?.copyWith(
              letterSpacing: 0.4,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onPrimaryContainer.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _suggestions(t)
                .map(
                  (idea) => ActionChip(
                    label: Text(idea),
                    onPressed: () => _sendPrompt(idea),
                    avatar: const Icon(Icons.chat_bubble_outline, size: 18),
                    backgroundColor: theme.colorScheme.surface.withOpacity(0.92),
                    labelStyle: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 28),
          Text(
            t.customerAssistantDisclaimer,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer.withOpacity(0.75),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(AppLocalizations t, ThemeData theme) {
    final answer = _lastAnswer;
    final isFallback = answer?.isFallback ?? false;
    final label = isFallback ? t.customerAssistantFallbackBadge : t.customerAssistantAiBadge;
    final baseColor = isFallback
        ? theme.colorScheme.tertiaryContainer
        : theme.colorScheme.primaryContainer;
    final textColor = ThemeData.estimateBrightnessForColor(baseColor) == Brightness.dark
        ? Colors.white
        : theme.colorScheme.onPrimaryContainer;
    final icon = isFallback ? Icons.menu_book_outlined : Icons.auto_awesome;
    return Chip(
      avatar: Icon(icon, size: 18, color: textColor),
      label: Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
      backgroundColor: baseColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: const StadiumBorder(),
    );
  }

  Widget _buildMessages(AppLocalizations t, ThemeData theme) {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 42, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              t.customerAssistantEmptyState,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: _suggestions(t)
                  .map(
                    (idea) => OutlinedButton(
                      onPressed: () => _sendPrompt(idea),
                      child: Text(idea),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      physics: const BouncingScrollPhysics(),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final entry = _messages[index];
        final isUser = entry.isUser;
        final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
        final bubbleColor = isUser
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceVariant.withOpacity(0.9);
        final textColor = isUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
        return Align(
          alignment: align,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(isUser ? 20 : 8),
                  topRight: Radius.circular(isUser ? 8 : 20),
                  bottomLeft: const Radius.circular(20),
                  bottomRight: const Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.shadow.withOpacity(0.08),
                    offset: const Offset(0, 8),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: entry.isPending
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          t.customerAssistantTyping,
                          style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                        ),
                      ],
                    )
                  : Text(
                      entry.text,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: textColor,
                        height: 1.45,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSources(AppLocalizations t, ThemeData theme) {
    final answer = _lastAnswer;
    if (answer == null || answer.sources.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.customerAssistantSourcesTitle,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            t.customerAssistantSourcesHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          ...answer.sources.map((source) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.title,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: source.tags
                        .map(
                          (tag) => Chip(
                            label: Text(tag),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildInput(AppLocalizations t, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: t.customerAssistantInputHint,
                  border: InputBorder.none,
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendPrompt(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _busy ? null : () => _sendPrompt(),
            icon: _busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.onPrimary),
                    ),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(t.customerAssistantSend),
          ),
        ],
      ),
    );
  }

  Widget _buildChatCard(AppLocalizations t, ThemeData theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withOpacity(0.08),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                    child: Icon(Icons.support_agent, color: theme.colorScheme.primary, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.customerAssistantTitle,
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t.customerAssistantSubtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusChip(t, theme),
                ],
              ),
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
            Expanded(child: _buildMessages(t, theme)),
            _buildSources(t, theme),
            _buildInput(t, theme),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.customerAssistantTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      bottomNavigationBar: LegalFooter(api: widget.api),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.surfaceTint.withOpacity(0.04),
              theme.colorScheme.surfaceVariant.withOpacity(0.08),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 980;
                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 360, child: _buildHero(t, theme)),
                          const SizedBox(width: 32),
                          Expanded(child: _buildChatCard(t, theme)),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        _buildHero(t, theme),
                        const SizedBox(height: 24),
                        Expanded(child: _buildChatCard(t, theme)),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
