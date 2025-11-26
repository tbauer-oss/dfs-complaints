// lib/pages/complaint_chat_page.dart
import 'package:flutter/material.dart';
import '../models/complaint_chat.dart';

class ComplaintChatPageArgs {
  final ComplaintChatRole role;
  final String? ticket;
  final List<String> contacts;
  final String? defaultContact;

  const ComplaintChatPageArgs({
    required this.role,
    this.ticket,
    this.contacts = const [],
    this.defaultContact,
  });
}

class ComplaintChatPage extends StatefulWidget {
  final ComplaintChatRole role;
  final String? ticket;
  final List<String> contacts;
  final String? defaultContact;

  const ComplaintChatPage({
    super.key,
    this.ticket,
    ComplaintChatRole? role,
    List<String>? contacts,
    this.defaultContact,
  })  : role = role ?? ComplaintChatRole.rep,
        contacts = contacts ?? const [];

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
  late List<String> _contactOptions;
  List<ComplaintChatConversation> _conversations = [];
  String? _activeConversationId;

  @override
  void initState() {
    super.initState();
    _currentRole = widget.role;
    _contactOptions = widget.contacts;
    if (widget.ticket != null) _ticketCtrl.text = widget.ticket!;
    if (_currentRole == ComplaintChatRole.rep) {
      _contactOptions = const ['QM / Admin'];
      _contactCtrl.text = widget.defaultContact?.isNotEmpty == true
          ? widget.defaultContact!
          : 'QM / Admin';
    } else if (widget.defaultContact != null && widget.defaultContact!.isNotEmpty) {
      _contactCtrl.text = widget.defaultContact!;
    } else if (_contactOptions.isNotEmpty) {
      _contactCtrl.text = _contactOptions.first;
    }
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
    if (subject.isEmpty || contact.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            subject.isEmpty
                ? 'Bitte einen Betreff eingeben und einen Vertreter auswählen.'
                : 'Bitte einen Vertreter auswählen.',
          ),
        ),
      );
      return;
    }

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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Betreff, Kontakt oder Ticketnummer suchen',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _startConversation,
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('Neuer Chat'),
              ),
            ],
          ),
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
                  itemBuilder: (_, i) {
                    final conv = filtered[i];
                    final unread = conv.unreadCount(_currentRole);
                    return ListTile(
                      selected: conv.id == _activeConversationId,
                      onTap: () => _selectConversation(conv.id),
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Text(conv.contactLabel.isEmpty
                            ? 'C'
                            : conv.contactLabel.substring(0, 1).toUpperCase()),
                      ),
                      title: Text(conv.subject,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(conv.contactLabel,
                              style: theme.textTheme.bodySmall),
                          if (conv.ticketNumber != null)
                            _chip(conv.ticketNumber!, theme),
                          if (conv.internalNumber != null)
                            _chip(conv.internalNumber!, theme),
                        ],
                      ),
                      trailing: unread > 0
                          ? Chip(
                              label: Text('$unread neu'),
                              avatar: const Icon(Icons.mark_chat_unread,
                                  size: 16),
                              backgroundColor:
                                  theme.colorScheme.secondaryContainer,
                            )
                          : const SizedBox.shrink(),
                    );
                  },
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemCount: filtered.length,
                ),
        ),
      ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(conv.subject,
            style:
                theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
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
    );
  }

  Widget _buildMessages(ComplaintChatConversation conv) {
    final theme = Theme.of(context);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: conv.messages.length,
      itemBuilder: (_, i) {
        final m = conv.messages[i];
        final isMine = m.author == _currentRole;
        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMine
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(m.text, style: theme.textTheme.bodyMedium),
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

  Widget _buildComposer() {
    final theme = Theme.of(context);
    final isRep = _currentRole == ComplaintChatRole.rep;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _subjectCtrl,
                decoration: const InputDecoration(
                  labelText: 'Betreff',
                  hintText: 'z. B. Rückfrage zur Prüfung',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _buildContactField(isRep)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ticketCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ticketnummer (optional)',
                  prefixIcon: Icon(Icons.confirmation_number_outlined),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _internalCtrl,
                decoration: const InputDecoration(
                  labelText: 'DFS Reklamationsnr. (optional)',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _messageCtrl,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Nachricht',
            hintText: 'Direkt schreiben – Fotos/Videos können angehängt werden',
          ),
          onSubmitted: (_) => _sendMessage(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              tooltip: 'Foto anhängen',
              onPressed: () {},
              icon: const Icon(Icons.photo_outlined),
            ),
            IconButton(
              tooltip: 'Video anhängen',
              onPressed: () {},
              icon: const Icon(Icons.video_file_outlined),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _sendMessage,
              icon: const Icon(Icons.send),
              label: const Text('Senden'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          isRep ? 'Sie antworten als Vertreter' : 'Sie antworten als QM/Admin',
          style: theme.textTheme.labelMedium,
        ),
      ],
    );
  }

  Widget _buildContactField(bool isRep) {
    if (isRep) {
      return TextField(
        controller: _contactCtrl,
        readOnly: true,
        decoration: const InputDecoration(
          labelText: 'Kontakt',
          helperText: 'Interne Chats gehen immer an QM/Admin',
          prefixIcon: Icon(Icons.verified_user_outlined),
        ),
      );
    }

    if (_contactOptions.isEmpty) {
      return TextField(
        controller: _contactCtrl,
        readOnly: true,
        decoration: const InputDecoration(
          labelText: 'Kontakt',
          helperText: 'Keine Vertreter verfügbar. Bitte zuerst anlegen.',
          prefixIcon: Icon(Icons.badge_outlined),
        ),
      );
    }

    if (_contactOptions.isNotEmpty) {
      return DropdownButtonFormField<String>(
        value: _contactCtrl.text.isNotEmpty ? _contactCtrl.text : null,
        items: _contactOptions
            .map((c) => DropdownMenuItem<String>(value: c, child: Text(c)))
            .toList(),
        onChanged: (val) => setState(() => _contactCtrl.text = val ?? ''),
        decoration: const InputDecoration(
          labelText: 'Kontakt',
          prefixIcon: Icon(Icons.badge_outlined),
        ),
      );
    }

    return TextField(
      controller: _contactCtrl,
      decoration: const InputDecoration(
        labelText: 'Kontakt',
        hintText: 'Name des Vertreters',
        prefixIcon: Icon(Icons.badge_outlined),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Interner Chat QM ↔ Vertreter'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Chip(
              avatar: Icon(
                _currentRole == ComplaintChatRole.admin
                    ? Icons.verified_user_outlined
                    : Icons.badge_outlined,
              ),
              label: Text(_currentRole == ComplaintChatRole.admin
                  ? 'Admin aktiv'
                  : 'Vertreter aktiv'),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 960;
          return Row(
            children: [
              SizedBox(
                width: isWide ? 340 : 0,
                child: isWide
                    ? Card(
                        margin: const EdgeInsets.all(12),
                        child: _buildConversationList(isWide),
                      )
                    : const SizedBox.shrink(),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isWide)
                        Card(
                          child: SizedBox(
                            height: 260,
                            child: _buildConversationList(isWide),
                          ),
                        ),
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: _activeConversation == null
                                ? _emptyConversationPlaceholder(theme)
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _buildConversationHeader(
                                          _activeConversation!),
                                      const Divider(height: 28),
                                      Expanded(
                                        child: _buildMessages(
                                            _activeConversation!),
                                      ),
                                      const Divider(height: 28),
                                      _buildComposer(),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _emptyConversationPlaceholder(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined,
              size: 52, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            'Kontakt und Betreff setzen, dann Chat öffnen.',
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
