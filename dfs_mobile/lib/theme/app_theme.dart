import 'package:flutter/material.dart';

const kDfsPrimary = Color(0xFF0A63A8);

ThemeData lightTheme() {
  final baseScheme = ColorScheme.fromSeed(
    seedColor: kDfsPrimary,
    brightness: Brightness.light,
  );
  final scheme = baseScheme.copyWith(
    primary: kDfsPrimary,
    background: const Color(0xFFF3F6FB),
    surface: const Color(0xFFF8FAFD),
    onBackground: const Color(0xFF0B1220),
    onSurface: const Color(0xFF0B1220),
    surfaceVariant: const Color(0xFFE3EAF5),
    onSurfaceVariant: const Color(0xFF4B5B6E),
    outline: const Color(0xFFB8C4D6),
    outlineVariant: const Color(0xFFD6DFEC),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.background,
    visualDensity: VisualDensity.standard,
    typography: Typography.material2021(),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
        fontSize: 20,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      shadowColor: scheme.shadow.withOpacity(.12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: scheme.onPrimary,
        backgroundColor: scheme.primary,
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: const StadiumBorder(),
        elevation: 2,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        side: BorderSide(color: scheme.outline),
        shape: const StadiumBorder(),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withOpacity(.75),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withOpacity(.8)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh.withOpacity(.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    listTileTheme: ListTileThemeData(iconColor: scheme.onSurfaceVariant),
    checkboxTheme: CheckboxThemeData(fillColor: MaterialStatePropertyAll(scheme.primary)),
    radioTheme: RadioThemeData(fillColor: MaterialStatePropertyAll(scheme.primary)),
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStatePropertyAll(scheme.primary),
      trackColor: MaterialStatePropertyAll(scheme.primary.withOpacity(.35)),
    ),
  );
}

ThemeData darkTheme() {
  final baseScheme = ColorScheme.fromSeed(
    seedColor: kDfsPrimary,
    brightness: Brightness.dark,
  );
  final scheme = baseScheme.copyWith(
    primary: const Color(0xFF3B82D6),
    background: const Color(0xFF0B1220),
    surface: const Color(0xFF111827),
    surfaceVariant: const Color(0xFF1F2937),
    onBackground: const Color(0xFFE5E7EB),
    onSurface: const Color(0xFFE5E7EB),
    onSurfaceVariant: const Color(0xFFCBD5E1),
    outline: const Color(0xFF334155),
    outlineVariant: const Color(0xFF1F2937),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.background,
    visualDensity: VisualDensity.standard,
    typography: Typography.material2021(),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
        fontSize: 20,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      shadowColor: scheme.shadow.withOpacity(.18),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: scheme.onPrimary,
        backgroundColor: scheme.primary,
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: const StadiumBorder(),
        elevation: 2,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: scheme.onSecondaryContainer,
        backgroundColor: scheme.secondaryContainer,
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outline),
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: const StadiumBorder(),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh.withOpacity(.7),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withOpacity(.9)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh.withOpacity(.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    listTileTheme: ListTileThemeData(iconColor: scheme.onSurfaceVariant),
    checkboxTheme: CheckboxThemeData(fillColor: MaterialStatePropertyAll(scheme.primary)),
    radioTheme: RadioThemeData(fillColor: MaterialStatePropertyAll(scheme.primary)),
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStatePropertyAll(scheme.primary),
      trackColor: MaterialStatePropertyAll(scheme.primary.withOpacity(.35)),
    ),
  );
}
