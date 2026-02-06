import 'package:flutter/material.dart';

/// Zentraler Sprach-Controller.
/// Überall nutzbar via `LocaleController.I.set(Locale('de'))`.
class LocaleController {
  LocaleController._();
  static final LocaleController I = LocaleController._();

  /// `null` = Systemsprache nutzen
  final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(null);

  void set(Locale? v) => locale.value = v;
}
