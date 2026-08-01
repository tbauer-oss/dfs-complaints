import 'package:dfs_mobile/theme/app_theme.dart';
import 'package:dfs_mobile/widgets/app_splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('branded splash renders the DFS startup experience',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme(),
        home: const AppSplashScreen(),
      ),
    );

    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('DFS Connect'), findsOneWidget);
    expect(find.text('Quality · Compliance · Service'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
