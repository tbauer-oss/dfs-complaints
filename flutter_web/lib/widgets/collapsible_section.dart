import 'package:flutter/material.dart';

class CollapsibleSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget? leading;

  const CollapsibleSection({
    super.key,
    required this.title,
    required this.child,
    required this.expanded,
    required this.onToggle,
    this.subtitle,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700);
    final subtitleStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 12),
                child: leading!,
              ),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: titleStyle),
                  if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: subtitleStyle),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: expanded ? 'Collapse' : 'Expand',
              onPressed: onToggle,
              icon: AnimatedRotation(
                turns: expanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: const Icon(Icons.expand_more),
              ),
            ),
          ],
        ),
        const Divider(height: 16),
        AnimatedCrossFade(
          firstChild: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 18), // EdgeInsets.fromLTRB(left, top, right, bottom)
            child: child,
          ),
          secondChild: const SizedBox.shrink(),
          crossFadeState: expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 220),
          sizeCurve: Curves.easeInOut,
        ),
      ],
    );
  }
}
