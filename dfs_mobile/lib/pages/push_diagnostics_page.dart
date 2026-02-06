import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/notification_permission_service.dart';
import '../services/push_notifications.dart';

class PushDiagnosticsPage extends StatefulWidget {
  const PushDiagnosticsPage({super.key});

  @override
  State<PushDiagnosticsPage> createState() => _PushDiagnosticsPageState();
}

class _PushDiagnosticsPageState extends State<PushDiagnosticsPage> {
  Future<PushDiagnosticsSnapshot>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = PushMessagingService.instance.collectDiagnostics();
    });
  }

  Widget _row(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value ?? '-')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Push Diagnostics'),
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
              Text(
                'Device & Build',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _row('Android SDK', data.androidSdk?.toString()),
              _row('compileSdk', data.compileSdk?.toString()),
              _row('targetSdk', data.targetSdk?.toString()),
              _row('Platform', kIsWeb ? 'web' : defaultTargetPlatform.name),
              const Divider(height: 28),
              Text(
                'Notification Permission',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _row('Status', permission.status.name),
              _row('Runtime required', permission.isRuntimeRequired.toString()),
              _row('Attempted', permission.attempted.toString()),
              _row('Request count', permission.requestCount.toString()),
              _row('First-run prompt flagged', permission.firstLaunchPrompted.toString()),
              _row('Last requested at', permission.lastRequestedAt),
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
              const Divider(height: 28),
              Text(
                'FCM Token',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _row('Masked token', data.maskedToken()),
              _row('Stored token at', data.storedTokenAt),
              _row('Last upload status', data.lastUploadStatus),
              _row('Last upload status code', data.lastUploadStatusCode?.toString()),
              _row('Last upload error', data.lastUploadError),
              _row('Last upload at', data.lastUploadAt),
              const SizedBox(height: 8),
              _row('Last message id', data.lastMessageId),
              _row('Last message at', data.lastMessageAt),
              const Divider(height: 28),
              Text(
                'Notification Channel',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _row('Channel id', channel?.id),
              _row('Channel name', channel?.name),
              _row('Importance', channel?.importance),
            ],
          );
        },
      ),
    );
  }
}
