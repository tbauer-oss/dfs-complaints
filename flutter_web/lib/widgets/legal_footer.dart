import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';

class LegalFooter extends StatelessWidget {
  final ApiClient api;
  final EdgeInsets padding;
  final Widget? trailing;
  const LegalFooter({super.key, required this.api, this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10), this.trailing});

  Future<void> _showVersionDialog(BuildContext context) async {
    final t = Localizations.of<dynamic>(context, Object) != null
        ? Theme.of(context)
        : Theme.of(context); // nur damit Theme sicher vorhanden ist

    Map<String, dynamic>? meta;
    String? err;
    try {
      meta = await api.getAppMeta(refresh: true); // lädt/aktualisiert Version vom Backend
    } catch (e) {
      err = e.toString();
    }

    if (!context.mounted) return;
    final scheme = Theme.of(context).colorScheme;
    final v = meta?['version']?.toString() ?? '—';
    final b = meta?['build']?.toString() ?? '—';
    final u = meta?['updatedAt']?.toString() ?? '—';
    final n = meta?['notes']?.toString() ?? '';

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('App-Version'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('Version', v),
            _kv('Build', b),
            _kv('Aktualisiert', u),
            if (n.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Hinweise:', style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface)),
              const SizedBox(height: 4),
              Text(n),
            ],
            if (err != null) ...[
              const SizedBox(height: 8),
              Text('Fehler beim Laden: $err', style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // manuelles Reload
              try { await api.getAppMeta(refresh: true); } catch (_) {}
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Neu laden'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  static Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text('$k:', style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context)!;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        padding: padding,
        child: Row(
          children: [
            // Impressum (interne Route)
            InkWell(
              onTap: () => Navigator.of(context).pushNamed('/legal/imprint'),
              child: Text(
                t.imprint_title,
                style: TextStyle(
                  color: scheme.primary,
                  decoration: TextDecoration.underline,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Hilfe / Support (interne Route)
            InkWell(
              onTap: () => Navigator.of(context).pushNamed('/help'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.help_outline, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    t.help_center_title,
                    style: TextStyle(
                      color: scheme.primary,
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Datenschutz (interne Route) – mit demselben Icon wie vorher
            InkWell(
              onTap: () => Navigator.of(context).pushNamed('/legal/privacy'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.privacy_tip_outlined, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    t.privacy_link,
                    style: TextStyle(
                      color: scheme.primary,
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (trailing != null) ...[
              trailing!,
              const SizedBox(width: 8),
            ],
            // „?“ / Info-Icon für Version
            IconButton(
              tooltip: t.versioninfo,
              onPressed: () => _showVersionDialog(context),
              icon: const Icon(Icons.help_outline),
            ),
          ],
        ),
      ),
    );
  }
}
