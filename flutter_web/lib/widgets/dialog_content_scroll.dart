import 'package:flutter/material.dart';

/// Helper widget to avoid overflow errors inside [AlertDialog]s by
/// constraining the dialog body and making it scrollable when needed.
class DialogContentScroll extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const DialogContentScroll({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final maxHeight = media?.size.height ?? 0;
    final resolvedChild = padding == null
        ? child
        : Padding(
            padding: padding!,
            child: child,
          );

    // Keep enough headroom for dialog actions while preventing the typical
    // "BOTTOM OVERFLOWED" errors on compact devices or with long contents.
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: maxHeight > 0 ? maxHeight * 0.75 : 400,
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: resolvedChild,
      ),
    );
  }
}
