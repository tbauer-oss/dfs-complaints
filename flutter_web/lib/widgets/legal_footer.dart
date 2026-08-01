import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';

class LegalFooter extends StatelessWidget {
  final ApiClient api;
  final EdgeInsets padding;
  final Widget? trailing;
  const LegalFooter(
      {super.key,
      required this.api,
      this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      this.trailing});

  Future<void> _showVersionDialog(BuildContext context) async {
    Map<String, dynamic>? meta;
    String? err;
    try {
      meta = await api.getAppMeta(
          refresh: true); // lädt/aktualisiert Version vom Backend
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
              Text('Hinweise:',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: scheme.onSurface)),
              const SizedBox(height: 4),
              Text(n),
            ],
            if (err != null) ...[
              const SizedBox(height: 8),
              Text('Fehler beim Laden: $err',
                  style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // manuelles Reload
              try {
                await api.getAppMeta(refresh: true);
              } catch (_) {}
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
          SizedBox(
              width: 110,
              child: Text('$k:',
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context)!;

    Widget footerLink({
      required String label,
      required IconData icon,
      required VoidCallback onPressed,
    }) {
      return TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(color: scheme.outlineVariant.withOpacity(.72)),
          ),
        ),
        padding: padding,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final links = Wrap(
              spacing: 2,
              runSpacing: 2,
              children: [
                footerLink(
                  label: t.imprint_title,
                  icon: Icons.gavel_outlined,
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/legal/imprint'),
                ),
                footerLink(
                  label: t.help_center_title,
                  icon: Icons.help_outline_rounded,
                  onPressed: () => Navigator.of(context).pushNamed('/help'),
                ),
                footerLink(
                  label: t.privacy_link,
                  icon: Icons.privacy_tip_outlined,
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/legal/privacy'),
                ),
              ],
            );

            final meta = Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Text(
                  '© DFS-Diamon GmbH',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (trailing != null) trailing!,
                IconButton(
                  tooltip: t.versioninfo,
                  onPressed: () => _showVersionDialog(context),
                  icon: const Icon(Icons.info_outline_rounded),
                ),
              ],
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  links,
                  const SizedBox(height: 6),
                  Align(alignment: Alignment.centerRight, child: meta),
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: links),
                const SizedBox(width: 16),
                meta,
              ],
            );
          },
        ),
      ),
    );
  }
}
