// lib/pages/complaint_chat_page.dart
import 'package:flutter/material.dart';
import '../models/complaint_chat.dart';

class ComplaintChatPage extends StatefulWidget {
  final String ticket;
  const ComplaintChatPage({super.key, required this.ticket});

  @override
  State<ComplaintChatPage> createState() => _ComplaintChatPageState();
}

class _ComplaintChatPageState extends State<ComplaintChatPage> {
  late ComplaintChatCase _case;
  late List<ComplaintChatMessage> _threads;

  final TextEditingController _composerCtrl = TextEditingController();
  ComplaintChatRole _author = ComplaintChatRole.rep;
  String? _replyTargetId;
  final List<ComplaintChatAttachment> _pendingAttachments = [];

  @override
  void initState() {
    super.initState();
    _case = ComplaintChatCase(
      ticket: widget.ticket,
      product: 'Premium Streudiamanten 12mm',
      customer: 'Musterhotel Nord GmbH',
      statusLabel: 'In Prüfung (QM)',
      createdAt: DateTime.now().subtract(const Duration(days: 2, hours: 3)),
      updatedAt: DateTime.now().subtract(const Duration(minutes: 35)),
      channelLabel: 'QM ↔ Vertreter',
      accentColor: const Color(0xFF1F4C8F),
    );
    _threads = _seedMessages();
  }

  @override
  void dispose() {
    _composerCtrl.dispose();
    super.dispose();
  }

  List<ComplaintChatMessage> _seedMessages() {
    return [
      ComplaintChatMessage(
        id: 'm1',
        author: ComplaintChatRole.admin,
        text:
            'Hallo Frau Krüger, wir haben die Charge eingelagert und prüfen aktuell die AQL-Muster. Ich gebe Ihnen heute noch Feedback.',
        createdAt: DateTime.now().subtract(const Duration(hours: 6, minutes: 12)),
        readBy: {ComplaintChatRole.rep},
        replies: [
          ComplaintChatMessage(
            id: 'm1r1',
            author: ComplaintChatRole.rep,
            text:
                'Danke! Kunde wartet auf Rückmeldung. Ich habe vorsorglich einen Sperrvermerk gesetzt. Seht ihr das in SAP?',
            createdAt: DateTime.now().subtract(const Duration(hours: 5, minutes: 30)),
            readBy: {ComplaintChatRole.admin},
          ),
          ComplaintChatMessage(
            id: 'm1r2',
            author: ComplaintChatRole.admin,
            text:
                'Ja, Sperrvermerk ist angekommen. Siehst du im Anhang die verpackten Muster (Video)?',
            createdAt: DateTime.now().subtract(const Duration(hours: 4, minutes: 2)),
            attachments: const [
              ComplaintChatAttachment(
                name: 'Musterprüfung.mp4',
                type: ComplaintChatAttachmentType.video,
                url: 'https://samplelib.com/lib/preview/mp4/sample-5s.mp4',
                duration: Duration(seconds: 5),
              ),
            ],
            readBy: {ComplaintChatRole.rep},
          ),
        ],
      ),
      ComplaintChatMessage(
        id: 'm2',
        author: ComplaintChatRole.rep,
        text:
            'Kunde hat uns neue Fotos geschickt. Sie sehen kleine Einschlüsse im Material.',
        createdAt: DateTime.now().subtract(const Duration(hours: 3, minutes: 5)),
        attachments: const [
          ComplaintChatAttachment(
            name: 'einschluss_1.jpg',
            type: ComplaintChatAttachmentType.image,
            url: 'https://picsum.photos/seed/dfs_inclusion/640/420',
          ),
          ComplaintChatAttachment(
            name: 'einschluss_2.jpg',
            type: ComplaintChatAttachmentType.image,
            url: 'https://picsum.photos/seed/dfs_inclusion2/640/420',
          ),
        ],
        readBy: {ComplaintChatRole.admin, ComplaintChatRole.rep},
        acknowledged: true,
      ),
    ];
  }

  void _toggleRead(String id, ComplaintChatRole role) {
    setState(() {
      _threads = _mapMessages(_threads, (m) {
        if (m.id != id) return m;
        final updatedReadBy = Set<ComplaintChatRole>.from(m.readBy);
        if (!updatedReadBy.add(role)) {
          updatedReadBy.remove(role);
        }
        return m.copyWith(readBy: updatedReadBy);
      });
    });
  }

  void _toggleAck(String id) {
    setState(() {
      _threads = _mapMessages(_threads, (m) {
        if (m.id != id) return m;
        return m.copyWith(acknowledged: !m.acknowledged);
      });
    });
  }

  List<ComplaintChatMessage> _mapMessages(
    List<ComplaintChatMessage> list,
    ComplaintChatMessage Function(ComplaintChatMessage) fn,
  ) {
    return list
        .map((m) => fn(m.copyWith(
              replies: _mapMessages(m.replies, fn),
            )))
        .toList();
  }

  void _sendMessage() {
    final text = _composerCtrl.text.trim();
    if (text.isEmpty) return;

    final msg = ComplaintChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      author: _author,
      text: text,
      createdAt: DateTime.now(),
      attachments: List<ComplaintChatAttachment>.from(_pendingAttachments),
      readBy: {_author},
    );

    setState(() {
      if (_replyTargetId == null) {
        _threads = [..._threads, msg];
      } else {
        _threads = _mapMessages(_threads, (m) {
          if (m.id == _replyTargetId) {
            final replies = List<ComplaintChatMessage>.from(m.replies)..add(msg);
            return m.copyWith(replies: replies);
          }
          return m;
        });
      }
      _composerCtrl.clear();
      _replyTargetId = null;
      _pendingAttachments.clear();
    });
  }

  void _setReplyTarget(String? id) {
    setState(() => _replyTargetId = id);
  }

  void _addSampleAttachment(ComplaintChatAttachment attachment) {
    setState(() => _pendingAttachments.add(attachment));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Interner Reklamations-Chat'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 1040;
          final content = [
            SizedBox(
              width: isWide ? 340 : constraints.maxWidth,
              child: _buildCasePanel(),
            ),
            const SizedBox(width: 16, height: 16),
            Expanded(child: _buildChatSurface()),
          ];

          if (isWide) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: content,
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                content[0],
                const SizedBox(height: 12),
                SizedBox(
                  height: 24,
                  child: Divider(color: Colors.grey.shade300),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 640,
                  child: content[2],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCasePanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Ticket ${_case.ticket}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(_case.channelLabel),
                  avatar: const Icon(Icons.swap_horiz),
                  backgroundColor: _case.accentColor.withOpacity(0.08),
                  side: BorderSide(color: _case.accentColor.withOpacity(0.4)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_case.product, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _infoRow(Icons.account_tree, 'Kunde', _case.customer),
            _infoRow(Icons.flag, 'Status', _case.statusLabel),
            _infoRow(Icons.timer, 'Eröffnet', _fmtDate(_case.createdAt)),
            _infoRow(Icons.update, 'Aktualisiert', _fmtDate(_case.updatedAt)),
            const Divider(height: 28),
            Text('Verlauf gehört zur Reklamation',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'QM und Vertreter teilen sich einen fixen Kanal pro Ticket. Alle Nachrichten, Quittierungen '
              'und Beweise (Fotos/Videos) bleiben am Case – kein WhatsApp mehr nötig.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill(Icons.verified_user, 'Quittierpflicht'),
                _pill(Icons.photo_library, 'Fotos/Videos'),
                _pill(Icons.forum, 'Threads'),
                _pill(Icons.history, 'Vollständiger Verlauf'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatSurface() {
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.forum_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Interner Chat',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      const Text('Direkter Kanal QM ↔ Vertreter, mit Threads und Lesestatus.'),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _setReplyTarget(null),
                  icon: const Icon(Icons.add_comment),
                  label: const Text('Neue Nachricht'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _threads.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final msg = _threads[index];
                return _buildMessageCard(msg);
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _buildComposer(),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageCard(ComplaintChatMessage msg, {bool isReply = false}) {
    final color = msg.author == ComplaintChatRole.rep
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceVariant;
    final onColor = Theme.of(context).colorScheme.onPrimaryContainer;
    return Container(
      decoration: BoxDecoration(
        color: isReply ? color.withOpacity(0.35) : color.withOpacity(0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.8)),
      ),
      padding: EdgeInsets.fromLTRB(isReply ? 12 : 16, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                msg.author == ComplaintChatRole.rep
                    ? Icons.person_pin_circle
                    : Icons.verified_user,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                msg.author == ComplaintChatRole.rep ? 'Vertreter' : 'QM / Admin',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: msg.author == ComplaintChatRole.rep ? onColor : null,
                ),
              ),
              const Spacer(),
              Text(_fmtTime(msg.createdAt), style: const TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Text(msg.text, style: const TextStyle(fontSize: 15)),
          if (msg.attachments.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final att in msg.attachments)
                  _attachmentTile(att, Theme.of(context).colorScheme.primary),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                selected: msg.readBy.contains(ComplaintChatRole.rep),
                onSelected: (_) => _toggleRead(msg.id, ComplaintChatRole.rep),
                label: const Text('Gelesen (Vertreter)'),
                avatar: const Icon(Icons.visibility),
              ),
              FilterChip(
                selected: msg.readBy.contains(ComplaintChatRole.admin),
                onSelected: (_) => _toggleRead(msg.id, ComplaintChatRole.admin),
                label: const Text('Gelesen (QM)'),
                avatar: const Icon(Icons.verified),
              ),
              ChoiceChip(
                selected: msg.acknowledged,
                onSelected: (_) => _toggleAck(msg.id),
                label: const Text('Quittiert'),
                avatar: const Icon(Icons.task_alt),
              ),
              TextButton.icon(
                onPressed: () => _setReplyTarget(msg.id),
                icon: const Icon(Icons.reply),
                label: Text(_replyTargetId == msg.id ? 'Antwort aktiv' : 'Antworten'),
              ),
            ],
          ),
          if (msg.replies.isNotEmpty) ...[
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: msg.replies
                  .map((r) => Padding(
                        padding: const EdgeInsets.only(left: 12, top: 6),
                        child: _buildMessageCard(r, isReply: true),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildComposer() {
    final roleLabel = _author == ComplaintChatRole.rep ? 'Vertreter' : 'QM / Admin';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Schreibe als:'),
            const SizedBox(width: 8),
            SegmentedButton<ComplaintChatRole>(
              segments: const [
                ButtonSegment(value: ComplaintChatRole.rep, icon: Icon(Icons.person), label: Text('Vertreter')),
                ButtonSegment(value: ComplaintChatRole.admin, icon: Icon(Icons.security), label: Text('QM / Admin')),
              ],
              selected: {_author},
              onSelectionChanged: (v) => setState(() => _author = v.first),
            ),
            const Spacer(),
            if (_replyTargetId != null)
              Chip(
                label: Text('Antwort auf #$_replyTargetId'),
                deleteIcon: const Icon(Icons.close),
                onDeleted: () => _setReplyTarget(null),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _composerCtrl,
          maxLines: 4,
          minLines: 2,
          decoration: InputDecoration(
            labelText: 'Nachricht im Fall-Chat ($roleLabel)',
            hintText: 'Threaded Chat ohne WhatsApp – inkl. Fotos, Videos und Quittierungen',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: _sendMessage,
              icon: const Icon(Icons.send),
              label: const Text('Senden'),
            ),
            OutlinedButton.icon(
              onPressed: () => _addSampleAttachment(const ComplaintChatAttachment(
                name: 'neues Foto.jpg',
                type: ComplaintChatAttachmentType.image,
                url: 'https://picsum.photos/seed/newdfs/640/480',
              )),
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Foto anhängen'),
            ),
            OutlinedButton.icon(
              onPressed: () => _addSampleAttachment(const ComplaintChatAttachment(
                name: 'Lieferung.mp4',
                type: ComplaintChatAttachmentType.video,
                url: 'https://samplelib.com/lib/preview/mp4/sample-5s.mp4',
                duration: Duration(seconds: 5),
              )),
              icon: const Icon(Icons.video_call),
              label: const Text('Video anhängen'),
            ),
          ],
        ),
        if (_pendingAttachments.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _pendingAttachments
                .map((att) => InputChip(
                      label: Text(att.name),
                      avatar: Icon(att.type == ComplaintChatAttachmentType.image
                          ? Icons.photo
                          : Icons.video_library),
                      onDeleted: () => setState(() => _pendingAttachments.remove(att)),
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text('$label:'),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String text) {
    return Chip(
      label: Text(text),
      avatar: Icon(icon, size: 18),
      backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
    );
  }

  Widget _attachmentTile(ComplaintChatAttachment att, Color accent) {
    final icon = att.type == ComplaintChatAttachmentType.image
        ? Icons.image
        : Icons.videocam;
    return Container(
      width: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withOpacity(0.5)),
        color: Theme.of(context).colorScheme.surface,
      ),
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              image: att.type == ComplaintChatAttachmentType.image
                  ? DecorationImage(image: NetworkImage(att.url), fit: BoxFit.cover)
                  : null,
              color: accent.withOpacity(0.12),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(att.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (att.duration != null)
                  Text('Video · ${att.duration!.inSeconds}s',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                if (att.duration == null)
                  Text('Bild / Beweis',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year} · ${_fmtTime(local)}';
  }

  String _fmtTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
