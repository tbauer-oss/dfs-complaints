import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    final safePadding = MediaQuery.of(context).padding;
    final tooltipMaxWidth = math.min(520.0, size.width - 24);
    final tooltipMaxHeight = math.min(320.0, size.height * 0.35);
    final safeLeft = safePadding.left + padding;
    final safeRight = size.width - safePadding.right - padding;
    final safeTop = safePadding.top + padding;
    final safeBottom = size.height - safePadding.bottom - padding;
    final horizontalSpace = safeRight - safeLeft;
    final useCenter = horizontalSpace < tooltipMaxWidth + padding;
    final minLeft = safeLeft;
    final maxLeft = math.max(safeLeft, safeRight - tooltipMaxWidth);
    final tooltipLeft =
        (useCenter ? (size.width - tooltipMaxWidth) / 2 : safeLeft).clamp(minLeft, maxLeft).toDouble();
    final needsTopPlacement = (safeBottom - safeTop) < tooltipMaxHeight + padding;
    final tooltipTop = needsTopPlacement ? safeTop : null;
    final tooltipBottom = needsTopPlacement ? null : size.height - safeBottom;

    final highlightRect = Rect.fromLTWH(
      targetRect.left - 8,
      targetRect.top - 8,
      targetRect.width + 16,
      targetRect.height + 16,
    );

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.escape): const _DismissOnboardingIntent(),
      },
      child: Actions(
        actions: {
          _DismissOnboardingIntent: CallbackAction<_DismissOnboardingIntent>(
            onInvoke: (_) {
              onSkip();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
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
                      maxWidth: tooltipMaxWidth,
                      maxHeight: tooltipMaxHeight,
                    ),
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(16),
                      color: theme.colorScheme.surface,
                      child: SizedBox(
                        width: tooltipMaxWidth,
                        height: tooltipMaxHeight,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
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
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Tour beenden',
                                    icon: const Icon(Icons.close),
                                    onPressed: onSkip,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Expanded(
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
                              const Divider(height: 20),
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DismissOnboardingIntent extends Intent {
  const _DismissOnboardingIntent();
}
