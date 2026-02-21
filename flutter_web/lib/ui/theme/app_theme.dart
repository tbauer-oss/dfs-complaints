import 'package:flutter/material.dart';

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

class AppRadius {
  static const BorderRadius card = BorderRadius.all(Radius.circular(14));
  static const BorderRadius chip = BorderRadius.all(Radius.circular(999));
}

class AppSemanticColors {
  static Color success(BuildContext context) => const Color(0xFF15803D);
  static Color warning(BuildContext context) => const Color(0xFFB45309);
  static Color error(BuildContext context) => Theme.of(context).colorScheme.error;
  static Color info(BuildContext context) => Theme.of(context).colorScheme.primary;
}

class AppButtons {
  static ButtonStyle primary(BuildContext context) => FilledButton.styleFrom(minimumSize: const Size(0, 44));
  static ButtonStyle secondary(BuildContext context) => OutlinedButton.styleFrom(minimumSize: const Size(0, 44));
  static ButtonStyle tonal(BuildContext context) => FilledButton.tonalStyleFrom(minimumSize: const Size(0, 44));
}
