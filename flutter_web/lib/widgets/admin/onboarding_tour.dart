import 'dart:math' as math;

import 'package:flutter/material.dart';

class OnboardingTourStep {
  final String title;
  final String description;
  final List<GlobalKey> targetKeys;

  const OnboardingTourStep({
    required this.title,
    required this.description,
    required this.targetKeys,
  });
}

class OnboardingTourOverlay extends StatelessWidget {
  final OnboardingTourStep step;
  final Rect targetRect;
  final int index;
  final int total;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkipStep;
  final VoidCallback onSkip;

  const OnboardingTourOverlay({
    super.key,
    required this.step,
    required this.targetRect,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onBack,
    required this.onSkipStep,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLast = index >= total - 1;
    final canGoBack = index > 0;
    final size = MediaQuery.of(context).size;
    final overlayColor = theme.brightness == Brightness.dark
        ? Colors.black.withOpacity(0.62)
        : Colors.black.withOpacity(0.48);
    final highlightColor = theme.colorScheme.primary;
    final padding = 16.0;
    final tooltipWidth = math.min(420.0, math.min(size.width * 0.35, size.width - padding * 2));
    final tooltipMaxHeight = math.min(420.0, size.height * 0.4);
    final tooltipLeft = (targetRect.center.dx - tooltipWidth / 2)
        .clamp(padding, size.width - tooltipWidth - padding)
        .toDouble();
    final placeAbove = targetRect.center.dy > size.height * 0.55;
    final tooltipTop = placeAbove
        ? null
        : (targetRect.bottom + 16).clamp(padding, size.height - 180).toDouble();
    final tooltipBottom = placeAbove
        ? (size.height - targetRect.top + 16).clamp(padding, size.height - padding).toDouble()
        : null;

    final highlightRect = Rect.fromLTWH(
      targetRect.left - 8,
      targetRect.top - 8,
      targetRect.width + 16,
      targetRect.height + 16,
    );

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () {},
              child: Container(color: overlayColor),
            ),
          ),
          Positioned(
            left: highlightRect.left,
            top: highlightRect.top,
            width: highlightRect.width,
            height: highlightRect.height,
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: highlightColor.withOpacity(0.9),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: highlightColor.withOpacity(0.55),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: tooltipLeft,
            top: tooltipTop,
            bottom: tooltipBottom,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: tooltipWidth,
                maxHeight: tooltipMaxHeight,
              ),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(16),
                color: theme.colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Schritt ${index + 1} von $total',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        step.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Flexible(
                        fit: FlexFit.loose,
                        child: Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            child: SelectableText(
                              step.description,
                              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          TextButton(
                            onPressed: canGoBack ? onBack : null,
                            child: const Text('Zurück'),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: onSkipStep,
                            child: const Text('Überspringen'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: onSkip,
                            child: const Text('Tour beenden'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: onNext,
                            child: Text(isLast ? 'Fertig' : 'Weiter'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
