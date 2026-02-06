import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../api/client.dart';
import '../services/notification_permission_service.dart';
import '../services/push_notifications.dart';

class PushDebugPage extends StatefulWidget {
  const PushDebugPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<PushDebugPage> createState() => _PushDebugPageState();
}

class _PushDebugPageState extends State<PushDebugPage> {
  Future<PushDiagnosticsSnapshot>? _future;
  PushDiagnosticsSnapshot? _lastSnapshot;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = PushMessagingService.instance
          .diagnostics(widget.api)
          .then((value) => _lastSnapshot = value);
    });
  }

  Future<void> _refreshToken() async {
    await PushMessagingService.instance.setup(widget.api, forcePermissionPrompt: true);
    _reload();
  }

  Future<void> _replayToken() async {
    await PushMessagingService.instance.replayLatestToken(widget.api);
    _reload();
  }

  Future<void> _copyToken(BuildContext context) async {
    final token = _lastSnapshot?.currentToken ?? _lastSnapshot?.storedToken;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kein Token verfügbar.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: token));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Token kopiert.')),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  Widget _tile(String label, String? value, {Widget? trailing}) {
    return ListTile(
      dense: true,
      title: Text(label),
      subtitle: SelectableText(value?.isNotEmpty == true ? value! : '-'),
      trailing: trailing,
      contentPadding: EdgeInsets.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Push Debug'),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
          ),
        ],
      ),
      body: FutureBuilder<PushDiagnosticsSnapshot>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData) {
            return Center(
              child: Text('No diagnostics available: ${snapshot.error ?? 'unknown error'}'),
            );
          }

          final data = snapshot.data!;
          final permission = data.permission;
          final channel = data.channelInfo;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _refreshToken,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Token neu holen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _replayToken,
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('Token erneut registrieren'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _copyToken(context),
                icon: const Icon(Icons.copy),
                label: const Text('Token kopieren'),
              ),
              _sectionTitle(context, 'Firebase'),
              _tile('Project ID', data.firebaseProjectId),
              _tile('App ID', data.firebaseAppId),
              _tile('Sender ID', data.firebaseSenderId),
              _tile('Package', data.packageName),
              _sectionTitle(context, 'Device & Build'),
              _tile('Android SDK', data.androidSdk?.toString()),
              _tile('compileSdk', data.compileSdk?.toString()),
              _tile('targetSdk', data.targetSdk?.toString()),
              _tile('Platform', kIsWeb ? 'web' : defaultTargetPlatform.name),
              _sectionTitle(context, 'Notification Permission'),
              _tile('Status', permission.status.name),
              _tile('Runtime required', permission.isRuntimeRequired.toString()),
              _tile('Attempted', permission.attempted.toString()),
              _tile('Request count', permission.requestCount.toString()),
              _tile('First-run prompt flagged', permission.firstLaunchPrompted.toString()),
              _tile('Last requested at', permission.lastRequestedAt),
              if (permission.isPermanentlyDenied)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await NotificationPermissionService.instance.openSettingsIfNeeded(permission);
                    },
                    icon: const Icon(Icons.settings),
                    label: const Text('Open app notification settings'),
                  ),
                ),
              _sectionTitle(context, 'FCM Token'),
              _tile('Current token', data.currentToken),
              _tile('Stored token', data.storedToken),
              _tile('Stored token at', data.storedTokenAt),
              _tile('API cached token', data.apiToken),
              _sectionTitle(context, 'Upload Status'),
              _tile('Last upload status', data.lastUploadStatus),
              _tile('Last upload status code', data.lastUploadStatusCode?.toString()),
              _tile('Last upload error', data.lastUploadError),
              _tile('Last upload at', data.lastUploadAt),
              _sectionTitle(context, 'Last Message'),
              _tile('Last message id', data.lastMessageId),
              _tile('Last message at', data.lastMessageAt),
              _sectionTitle(context, 'Notification Channel'),
              _tile('Channel id', channel?.id),
              _tile('Channel name', channel?.name),
              _tile('Importance', channel?.importance),
            ],
          );
        },
      ),
    );
  }
}
