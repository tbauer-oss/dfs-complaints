// lib/pages/complaint_chat_page.dart
// Layout Update: Builds a messenger-like two-pane layout with a permanent
// sidebar on wide screens and a responsive single-pane flow on narrow widths
// without touching any chat logic or data handling.
import 'package:flutter/material.dart';
import '../models/complaint_chat.dart';

class ComplaintChatPageArgs {
  final ComplaintChatRole role;
  final String? ticket;
  const ComplaintChatPageArgs({required this.role, this.ticket});
}

class ComplaintChatPage extends StatefulWidget {
  final ComplaintChatRole role;
  final String? ticket;

  const ComplaintChatPage({super.key, this.ticket, ComplaintChatRole? role})
      : role = role ?? ComplaintChatRole.rep;

  @override
  State<ComplaintChatPage> createState() => _ComplaintChatPageState();
}

class _ComplaintChatPageState extends State<ComplaintChatPage> {
  final TextEditingController _subjectCtrl = TextEditingController();
  final TextEditingController _contactCtrl = TextEditingController();
  final TextEditingController _ticketCtrl = TextEditingController();
  final TextEditingController _internalCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _messageCtrl = TextEditingController();

  late ComplaintChatRole _currentRole;
  List<ComplaintChatConversation> _conversations = [];
  String? _activeConversationId;

  @override
  void initState() {
    super.initState();
    _currentRole = widget.role;
    if (widget.ticket != null) _ticketCtrl.text = widget.ticket!;
    _syncUnread();
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _contactCtrl.dispose();
    _ticketCtrl.dispose();
    _internalCtrl.dispose();
    _searchCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  void _syncUnread() {
    ComplaintChatInboxState.syncUnread(_conversations);
  }

  ComplaintChatConversation? get _activeConversation => _conversations
      .where((c) => c.id == _activeConversationId)
      .cast<ComplaintChatConversation?>()
      .firstWhere((c) => c != null, orElse: () => null);

  void _startConversation() {
    final subject = _subjectCtrl.text.trim();
    final contact = _contactCtrl.text.trim();
    if (subject.isEmpty || contact.isEmpty) return;

    final conv = ComplaintChatConversation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      subject: subject,
      contactLabel: contact,
      ticketNumber: _ticketCtrl.text.trim().isEmpty
          ? null
          : _ticketCtrl.text.trim(),
      internalNumber: _internalCtrl.text.trim().isEmpty
          ? null
          : _internalCtrl.text.trim(),
      createdAt: DateTime.now(),
      messages: const [],
    );

    setState(() {
      _conversations = [conv, ..._conversations];
      _activeConversationId = conv.id;
      _messageCtrl.clear();
    });
    _syncUnread();
  }

  void _selectConversation(String id) {
    setState(() => _activeConversationId = id);
    _markConversationRead(id);
  }

  void _markConversationRead(String id) {
    setState(() {
      _conversations = _conversations.map((conv) {
        if (conv.id != id) return conv;
        final updatedMessages = conv.messages
            .map((m) => m.readBy.contains(_currentRole)
                ? m
                : m.copyWith(readBy: {...m.readBy, _currentRole}))
            .toList();
        return conv.copyWith(messages: updatedMessages);
      }).toList();
    });
    _syncUnread();
  }

  void _sendMessage() {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;

    if (_activeConversation == null) {
      _startConversation();
      if (_activeConversation == null) return;
    }

    final msg = ComplaintChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      author: _currentRole,
      text: text,
      createdAt: DateTime.now(),
      readBy: {_currentRole},
    );

    setState(() {
      _conversations = _conversations.map((conv) {
        if (conv.id != _activeConversationId) return conv;
        return conv.copyWith(messages: [...conv.messages, msg]);
      }).toList();
      _messageCtrl.clear();
    });
    _markConversationRead(_activeConversationId!);
  }

  Widget _buildConversationList(bool isWide) {
    final theme = Theme.of(context);
    final sidePadding = isWide ? 16.0 : 12.0;
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = _conversations.where((c) {
      if (query.isEmpty) return true;
      final haystack =
          '${c.subject} ${c.contactLabel} ${c.ticketNumber ?? ''} ${c.internalNumber ?? ''}'
              .toLowerCase();
      return haystack.contains(query);
    }).toList()
      ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding:
              EdgeInsets.symmetric(horizontal: sidePadding, vertical: 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nachrichten',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Alle Konversationen im Überblick',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.outline)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Archiv',
                onPressed: () {},
                icon: Icon(Icons.archive_outlined,
                    color: theme.colorScheme.outline),
              ),
              IconButton(
                tooltip: 'Weitere Optionen',
                onPressed: () {},
                icon: Icon(Icons.more_vert, color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(sidePadding, 12, sidePadding, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Betreff, Kontakt oder Ticketnummer suchen',
                    filled: true,
                    fillColor:
                        theme.colorScheme.surfaceVariant.withOpacity(0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _startConversation,
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('Neuer Chat'),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: sidePadding),
          child: Divider(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 48, color: theme.colorScheme.outline),
                      const SizedBox(height: 12),
                      Text('Noch keine internen Chats angelegt',
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('Kontakt auswählen, Betreff setzen und loslegen.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.outline)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.symmetric(
                      horizontal: isWide ? 12 : 10, vertical: 8),
                  itemBuilder: (_, i) {
                    final conv = filtered[i];
                    final unread = conv.unreadCount(_currentRole);
                    final selected = conv.id == _activeConversationId;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _selectConversation(conv.id),
                        borderRadius: BorderRadius.circular(14),
                        hoverColor:
                            theme.colorScheme.primary.withOpacity(0.05),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border(
                              left: BorderSide(
                                color: selected
                                    ? theme.colorScheme.primary
                                    : Colors.transparent,
                                width: 4,
                              ),
                            ),
                            color: selected
                                ? theme.colorScheme.primary
                                    .withOpacity(0.06)
                                : null,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                child: Text(conv.contactLabel.isEmpty
                                    ? 'C'
                                    : conv.contactLabel
                                        .substring(0, 1)
                                        .toUpperCase()),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            conv.subject,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                    fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _formatConversationTime(
                                              conv.lastActivity),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                  color:
                                                      theme.colorScheme.outline),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      conv.messages.isNotEmpty
                                          ? conv.messages.last.text
                                          : 'Keine Nachrichten',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.outline,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(conv.contactLabel,
                                            style: theme.textTheme.bodySmall),
                                        if (conv.ticketNumber != null)
                                          _chip(conv.ticketNumber!, theme),
                                        if (conv.internalNumber != null)
                                          _chip(conv.internalNumber!, theme),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                children: [
                                  if (unread > 0)
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  Icon(Icons.chevron_right,
                                      color: theme.colorScheme.outline),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemCount: filtered.length,
                ),
        ),
      ],
    );
  }

  Widget _buildSidebar(bool isWide) {
    return SizedBox(
      width: isWide ? 340 : null,
      child: Card(
        margin: EdgeInsets.all(isWide ? 16 : 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        elevation: 4,
        child: _buildConversationList(isWide),
      ),
    );
  }

  Widget _buildChatPane(bool isWide) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(isWide ? 8 : 0, 16, isWide ? 16 : 0, 16),
      child: Column(
        children: [
          Expanded(
            child: Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.surface,
                      theme.colorScheme.surfaceVariant.withOpacity(0.15),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: _activeConversation == null
                    ? _emptyConversationPlaceholder(theme, isWide)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!isWide)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () =>
                                      setState(() => _activeConversationId = null),
                                  icon: const Icon(Icons.chevron_left),
                                  label: const Text('Zurück zur Liste'),
                                ),
                              ),
                            ),
                          _buildConversationHeader(_activeConversation!),
                          Expanded(
                            child: _buildMessages(_activeConversation!),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: _buildComposer(),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: theme.textTheme.labelMedium),
    );
  }

  Widget _buildConversationHeader(ComplaintChatConversation conv) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(conv.subject,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                      label: Text(conv.contactLabel),
                      avatar: const Icon(Icons.person_outline),
                    ),
                    if (conv.ticketNumber != null)
                      Chip(
                        label: Text('Ticket ${conv.ticketNumber}'),
                        avatar:
                            const Icon(Icons.confirmation_number_outlined),
                      ),
                    if (conv.internalNumber != null)
                      Chip(
                        label: Text('DFS ${conv.internalNumber}'),
                        avatar: const Icon(Icons.badge_outlined),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Archivieren',
                onPressed: () {},
                icon:
                    Icon(Icons.archive_outlined, color: theme.colorScheme.primary),
              ),
              IconButton(
                tooltip: 'Info',
                onPressed: () {},
                icon: Icon(Icons.info_outline,
                    color: theme.colorScheme.onSurfaceVariant),
              ),
              IconButton(
                tooltip: 'Menü',
                onPressed: () {},
                icon: Icon(Icons.more_vert,
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessages(ComplaintChatConversation conv) {
    final theme = Theme.of(context);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      itemCount: conv.messages.length,
      itemBuilder: (_, i) {
        final m = conv.messages[i];
        final isMine = m.author == _currentRole;
        final bubbleColor = isMine
            ? const Color(0xFF0865A2).withOpacity(0.18)
            : theme.colorScheme.surfaceVariant;
        final radius = BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMine ? 18 : 8),
          bottomRight: Radius.circular(isMine ? 8 : 18),
        );

        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
              minWidth: 160,
            ),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: radius,
              ),
              child: Column(
                crossAxisAlignment:
                    isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMine)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        m.author == ComplaintChatRole.admin
                            ? 'Admin'
                            : 'Vertreter',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  Text(
                    m.text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        m.author == ComplaintChatRole.admin
                            ? Icons.verified_user_outlined
                            : Icons.badge_outlined,
                        size: 14,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        m.author == ComplaintChatRole.admin
                            ? 'Admin'
                            : 'Vertreter',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _formatTime(m.createdAt),
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (now.difference(dt).inDays == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}';
  }

  String _formatConversationTime(DateTime dt) {
    final now = DateTime.now();
    if (now.difference(dt).inDays == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (now.difference(dt).inDays == 1) return 'Gestern';
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}';
  }

  Widget _buildComposer() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _subjectCtrl,
                  decoration: InputDecoration(
                    labelText: 'Betreff',
                    hintText: 'z. B. Rückfrage zur Prüfung',
                    filled: true,
                    fillColor:
                        theme.colorScheme.surfaceVariant.withOpacity(0.4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: theme.colorScheme.outlineVariant),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _contactCtrl,
                  decoration: InputDecoration(
                    labelText: 'Kontakt',
                    hintText: 'Name oder Team',
                    filled: true,
                    fillColor:
                        theme.colorScheme.surfaceVariant.withOpacity(0.4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: theme.colorScheme.outlineVariant),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ticketCtrl,
                  decoration: InputDecoration(
                    labelText: 'Ticketnummer (optional)',
                    prefixIcon: const Icon(Icons.confirmation_number_outlined),
                    filled: true,
                    fillColor:
                        theme.colorScheme.surfaceVariant.withOpacity(0.4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: theme.colorScheme.outlineVariant),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _internalCtrl,
                  decoration: InputDecoration(
                    labelText: 'DFS-Reklamationsnummer (optional)',
                    prefixIcon: const Icon(Icons.badge_outlined),
                    filled: true,
                    fillColor:
                        theme.colorScheme.surfaceVariant.withOpacity(0.4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: theme.colorScheme.outlineVariant),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Emoji',
                  onPressed: () {},
                  icon: Icon(Icons.emoji_emotions_outlined,
                      color: theme.colorScheme.outline),
                ),
                Expanded(
                  child: TextField(
                    controller: _messageCtrl,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Nachricht schreiben…',
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  tooltip: 'Foto anhängen',
                  onPressed: () {},
                  icon: Icon(Icons.photo_outlined,
                      color: theme.colorScheme.outline),
                ),
                IconButton(
                  tooltip: 'Video anhängen',
                  onPressed: () {},
                  icon: Icon(Icons.video_file_outlined,
                      color: theme.colorScheme.outline),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: _sendMessage,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(14),
                    shape: const CircleBorder(),
                  ),
                  child: const Icon(Icons.send, size: 18),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _currentRole == ComplaintChatRole.admin
                ? 'Sie antworten als QM/Admin'
                : 'Sie antworten als Vertreter',
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.25),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1260, maxHeight: 960),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: theme.shadowColor.withOpacity(0.12),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                          child: Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Interner Chat',
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Zweispaltiges Messenger-Layout mit klarer Rollenanzeige.',
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Chip(
                                avatar: Icon(
                                  _currentRole == ComplaintChatRole.admin
                                      ? Icons.verified_user_outlined
                                      : Icons.badge_outlined,
                                ),
                                label: Text(_currentRole == ComplaintChatRole.admin
                                    ? 'Admin aktiv'
                                    : 'Vertreter aktiv'),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, _) {
                              final showList = isWide || _activeConversation == null;
                              final showChat = isWide || _activeConversation != null;

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (showList)
                                    if (isWide)
                                      _buildSidebar(isWide)
                                    else
                                      Expanded(child: _buildSidebar(isWide)),
                                  if (showList && showChat && isWide)
                                    VerticalDivider(
                                      width: 1,
                                      color: theme.colorScheme.outlineVariant.withOpacity(0.6),
                                    ),
                                  if (showChat)
                                    Expanded(
                                      child: _buildChatPane(isWide),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _emptyConversationPlaceholder(ThemeData theme, bool isWide) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined,
              size: 52, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            isWide
                ? 'Wähle eine Konversation, um Nachrichten anzuzeigen.'
                : 'Kontakt und Betreff setzen, dann Chat öffnen.',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Ticketnummern oder DFS-Reklamationsnummern können optional hinzugefügt werden.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
