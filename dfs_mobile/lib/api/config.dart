// lib/api/config.dart
class CFG {
  /// Backend-Basis-URL. Per --dart-define überschreibbar.
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://dfs-complaints-backend.tbauer-mail.workers.dev', // <- dein Backend
  );
}
