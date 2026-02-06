import 'package:flutter/widgets.dart';
import 'app_prefs.dart';

class AppPrefsScope extends InheritedNotifier<AppPrefs> {
  const AppPrefsScope({super.key, required AppPrefs notifier, required Widget child})
      : super(notifier: notifier, child: child);

  static AppPrefs of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<AppPrefsScope>();
    assert(s != null, 'AppPrefsScope not found in widget tree');
    return s!.notifier!;
  }
}
