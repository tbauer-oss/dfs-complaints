// lib/pages/complaint_chat_page.dart
// Layout Update: Builds a messenger-like two-pane layout with a permanent
// sidebar on wide screens and a responsive single-pane flow on narrow widths
// without touching any chat logic or data handling.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  final TextEditingController _messageSearchCtrl = TextEditingController();

  late ComplaintChatRole _currentRole;
  List<ComplaintChatConversation> _conversations = [];
  String? _activeConversationId;
  Set<String> _archivedConversationIds = {};
  bool _showArchived = false;
  bool _showMessageSearch = false;
  List<PlatformFile> _pendingAttachments = [];

  @override
  void initState() {
    super.initState();
    _currentRole = widget.role;
    if (widget.ticket != null) _ticketCtrl.text = widget.ticket!;
    _syncUnread();
    _restoreArchivedConversations();
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _contactCtrl.dispose();
    _ticketCtrl.dispose();
    _internalCtrl.dispose();
    _searchCtrl.dispose();
    _messageCtrl.dispose();
    _messageSearchCtrl.dispose();
    super.dispose();
  }

  void _syncUnread() {
    ComplaintChatInboxState.syncUnread(_conversations);
  }

  void _resortConversations() {
    _conversations = [..._conversations]
      ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
  }

  ComplaintChatConversation? get _activeConversation => _conversations
      .where((c) => c.id == _activeConversationId)
      .cast<ComplaintChatConversation?>()
      .firstWhere((c) => c != null, orElse: () => null);

  Future<void> _restoreArchivedConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('chat_archived_conv_ids') ?? [];
    if (stored.isNotEmpty) {
      setState(() {
        _archivedConversationIds = stored.toSet();
      });
    }
  }

  Future<void> _persistArchivedConversations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'chat_archived_conv_ids',
      _archivedConversationIds.toList(),
    );
  }

  void _toggleArchiveState(String conversationId) {
    setState(() {
      if (_archivedConversationIds.contains(conversationId)) {
        _archivedConversationIds.remove(conversationId);
      } else {
        _archivedConversationIds.add(conversationId);
        if (!_showArchived && _activeConversationId == conversationId) {
          _activeConversationId = null;
        }
      }
    });
    _persistArchivedConversations();
  }

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
      _resortConversations();
    });
    _syncUnread();
  }

  void _selectConversation(String id) {
    setState(() {
      _activeConversationId = id;
      _showMessageSearch = false;
      _messageSearchCtrl.clear();
    });
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
    if (text.isEmpty && _pendingAttachments.isEmpty) return;

    if (_activeConversation == null) {
      _startConversation();
      if (_activeConversation == null) return;
    }

    final attachmentNote = _pendingAttachments.isEmpty
        ? ''
        : '📎 ' + _pendingAttachments.map((file) => file.name).join(', ');
    final composedText = attachmentNote.isEmpty
        ? text
        : text.isEmpty
            ? attachmentNote
            : '$text\n$attachmentNote';

    final msg = ComplaintChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      author: _currentRole,
      text: composedText,
      createdAt: DateTime.now(),
      readBy: {_currentRole},
      attachments: _pendingAttachments
          .map(
            (file) => ComplaintChatAttachment(
              name: file.name,
              type: _inferAttachmentType(file.extension ?? ''),
              url: file.path ?? '',
            ),
          )
          .toList(),
    );

    setState(() {
      _conversations = _conversations.map((conv) {
        if (conv.id != _activeConversationId) return conv;
        return conv.copyWith(messages: [...conv.messages, msg]);
      }).toList();
      _resortConversations();
      _pendingAttachments = [];
      _messageCtrl.clear();
    });
    _markConversationRead(_activeConversationId!);
  }

  ComplaintChatAttachmentType _inferAttachmentType(String extension) {
    final lower = extension.toLowerCase();
    const imageExt = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};
    const videoExt = {'mp4', 'mov', 'avi', 'mkv', 'webm'};
    if (imageExt.contains(lower)) return ComplaintChatAttachmentType.image;
    if (videoExt.contains(lower)) return ComplaintChatAttachmentType.video;
    return ComplaintChatAttachmentType.image;
  }

  Future<void> _pickAttachments() async {
    try {
      final result = await FilePicker.pickFiles(allowMultiple: true);
      if (result == null) return;
      if (!mounted) return;
      setState(() {
        _pendingAttachments = result.files;
      });
    } catch (_) {}
  }

  void _removeAttachment(int index) {
    if (index < 0 || index >= _pendingAttachments.length) return;
    setState(() {
      _pendingAttachments.removeAt(index);
    });
  }

  Widget _buildConversationList(bool isWide) {
    final theme = Theme.of(context);
    final sidePadding = isWide ? 16.0 : 12.0;
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = _conversations
        .where((c) => _showArchived
            ? _archivedConversationIds.contains(c.id)
            : !_archivedConversationIds.contains(c.id))
        .where((c) {
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
              Chip(
                label: Text(_showArchived ? 'Archiviert' : 'Aktiv'),
                avatar: Icon(
                  _showArchived ? Icons.archive_outlined : Icons.chat_outlined,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                backgroundColor: theme.colorScheme.secondaryContainer,
                labelStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(sidePadding, 10, sidePadding, 0),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('Aktiv'),
                selected: !_showArchived,
                onSelected: (_) => setState(() => _showArchived = false),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Archiviert'),
                selected: _showArchived,
                onSelected: (_) => setState(() => _showArchived = true),
              ),
              const Spacer(),
              Text(
                '${filtered.length} Chats',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.outline),
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
                    final isArchived = _archivedConversationIds.contains(conv.id);
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
                                  IconButton(
                                    tooltip:
                                        isArchived ? 'Wiederherstellen' : 'Archivieren',
                                    icon: Icon(
                                      isArchived
                                          ? Icons.unarchive_outlined
                                          : Icons.archive_outlined,
                                      color: isArchived
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.outline,
                                    ),
                                    onPressed: () =>
                                        _toggleArchiveState(conv.id),
                                  ),
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
    final isArchived = _archivedConversationIds.contains(conv.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(conv.subject,
                              style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700)),
                        ),
                        if (isArchived)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: theme.colorScheme.outlineVariant),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.archive_outlined,
                                    size: 16,
                                    color: theme.colorScheme.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Text('Archiviert',
                                    style: theme.textTheme.labelMedium),
                              ],
                            ),
                          ),
                      ],
                    ),
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
                            avatar: const Icon(Icons.confirmation_number_outlined),
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
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _toggleArchiveState(conv.id),
                    icon: Icon(
                      isArchived
                          ? Icons.unarchive_outlined
                          : Icons.archive_outlined,
                    ),
                    label:
                        Text(isArchived ? 'Wiederherstellen' : 'Archivieren'),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'In Nachrichten suchen',
                          icon: const Icon(Icons.search),
                          onPressed: () {
                            setState(() {
                              _showMessageSearch = !_showMessageSearch;
                              if (!_showMessageSearch) {
                                _messageSearchCtrl.clear();
                              }
                            });
                          },
                        ),
                        Container(
                          width: 1,
                          height: 24,
                          color: theme.colorScheme.outlineVariant,
                        ),
                        IconButton(
                          tooltip: 'Mitglieder ansehen',
                          icon: const Icon(Icons.group_outlined),
                          onPressed: () => _showParticipants(conv),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: TextField(
              controller: _messageSearchCtrl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _messageSearchCtrl.clear();
                    setState(() {});
                  },
                ),
                hintText: 'In dieser Unterhaltung suchen',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          crossFadeState: _showMessageSearch
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }

  Widget _buildMessages(ComplaintChatConversation conv) {
    final theme = Theme.of(context);
    final query = _messageSearchCtrl.text.trim().toLowerCase();
    final messages = conv.messages.where((m) {
      if (query.isEmpty) return true;
      return m.text.toLowerCase().contains(query);
    }).toList();

    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, color: theme.colorScheme.outline),
            const SizedBox(height: 8),
            Text('Keine Nachrichten gefunden',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              query.isEmpty
                  ? 'Hier erscheinen alle Nachrichten der Unterhaltung.'
                  : 'Suchbegriff anpassen, um Treffer zu sehen.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      itemCount: messages.length,
      itemBuilder: (_, i) {
        final m = messages[i];
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

  void _showParticipants(ComplaintChatConversation conv) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Teilnehmer:innen',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(conv.contactLabel),
                subtitle: const Text('Kontakt'),
              ),
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(conv.repLabel.isEmpty ? 'Vertreter' : conv.repLabel),
                subtitle: const Text('Vertreter/in'),
              ),
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: Text(conv.adminLabel.isEmpty ? 'Admin' : conv.adminLabel),
                subtitle: const Text('QM/Admin'),
              ),
            ],
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

  String _formatFileSize(double bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes;
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${units[unit]}';
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
          if (_pendingAttachments.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < _pendingAttachments.length; i++)
                  InputChip(
                    avatar: const Icon(Icons.attach_file),
                    label: Text(
                        '${_pendingAttachments[i].name} (${_formatFileSize(_pendingAttachments[i].size.toDouble())})'),
                    onDeleted: () => _removeAttachment(i),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
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
                IconButton(
                  tooltip: 'Datei anhängen',
                  onPressed: _pickAttachments,
                  icon: Icon(Icons.attach_file,
                      color: theme.colorScheme.onSurfaceVariant),
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
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: (_messageCtrl.text.trim().isNotEmpty ||
                          _pendingAttachments.isNotEmpty)
                      ? _sendMessage
                      : null,
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
