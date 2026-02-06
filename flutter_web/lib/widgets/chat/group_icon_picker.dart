import 'package:flutter/material.dart';

const Map<String, IconData> kGroupIconOptions = {
  'groups': Icons.groups,
  'shipping': Icons.local_shipping,
  'build': Icons.build,
  'science': Icons.science,
  'assignment': Icons.assignment,
  'support': Icons.support_agent,
  'inventory': Icons.inventory_2,
  'medical': Icons.medical_information,
  'factory': Icons.factory,
  'security': Icons.security,
  'chat': Icons.chat,
};

IconData? iconForGroupIconId(String? id) {
  if (id == null || id.isEmpty) return null;
  return kGroupIconOptions[id];
}

Future<String?> showGroupIconPicker(BuildContext context, {String? initialIconId}) {
  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Gruppen-Icon auswählen'),
        content: SizedBox(
          width: 420,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: kGroupIconOptions.entries
                .map(
                  (entry) => _GroupIconChoice(
                    id: entry.key,
                    icon: entry.value,
                    selected: entry.key == initialIconId,
                    onSelected: (id) => Navigator.of(context).pop(id),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Kein Icon'),
          ),
        ],
      );
    },
  );
}

class _GroupIconChoice extends StatelessWidget {
  final String id;
  final IconData icon;
  final bool selected;
  final ValueChanged<String> onSelected;

  const _GroupIconChoice({
    required this.id,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => onSelected(id),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceVariant.withOpacity(0.4),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant.withOpacity(0.7),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: theme.colorScheme.surface,
              child: Icon(icon, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 8),
            Text(
              id,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
