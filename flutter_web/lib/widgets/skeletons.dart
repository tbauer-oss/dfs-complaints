import 'package:flutter/material.dart';

class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? margin;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.margin,
  });

  Color _resolveColor(ThemeData theme) {
    final base = theme.colorScheme.surfaceVariant;
    return theme.brightness == Brightness.dark ? base.withOpacity(0.35) : base.withOpacity(0.55);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: _resolveColor(theme),
        borderRadius: borderRadius,
      ),
    );
  }
}

class SkeletonTextBlock extends StatelessWidget {
  final int lines;
  final double lineHeight;
  final double spacing;
  final List<double>? widths;

  const SkeletonTextBlock({
    super.key,
    this.lines = 3,
    this.lineHeight = 12,
    this.spacing = 8,
    this.widths,
  });

  List<double> _resolveWidths() {
    if (widths != null && widths!.isNotEmpty) return widths!;
    return const [1, 0.7, 0.85, 0.6];
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolveWidths();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(lines, (index) {
        final widthFactor = resolved[index % resolved.length];
        return Padding(
          padding: EdgeInsets.only(bottom: index == lines - 1 ? 0 : spacing),
          child: FractionallySizedBox(
            widthFactor: widthFactor,
            child: SkeletonBox(height: lineHeight),
          ),
        );
      }),
    );
  }
}

class SkeletonCard extends StatelessWidget {
  final double? width;
  final double height;
  final EdgeInsetsGeometry padding;

  const SkeletonCard({
    super.key,
    this.width,
    this.height = 96,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Card(
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              SkeletonBox(width: 90, height: 12),
              SizedBox(height: 12),
              SkeletonBox(width: 140, height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class SkeletonTable extends StatelessWidget {
  final int rows;
  final int columns;
  final double rowHeight;
  final double rowSpacing;
  final double columnSpacing;

  const SkeletonTable({
    super.key,
    this.rows = 5,
    this.columns = 4,
    this.rowHeight = 16,
    this.rowSpacing = 12,
    this.columnSpacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(rows, (row) {
        return Padding(
          padding: EdgeInsets.only(bottom: row == rows - 1 ? 0 : rowSpacing),
          child: Row(
            children: List.generate(columns, (col) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: col == columns - 1 ? 0 : columnSpacing),
                  child: SkeletonBox(height: rowHeight),
                ),
              );
            }),
          ),
        );
      }),
    );
  }
}
