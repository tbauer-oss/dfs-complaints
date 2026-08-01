import 'package:dfs_customer_complaint/widgets/width_bound_dropdown_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keeps the requested field width on web-style layouts', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            child: WidthBoundDropdownMenu(
              width: 360,
              controller: controller,
              label: 'Klassifizierungsregel',
              options: const ['Regel 6', 'Regel 7'],
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(DropdownMenu<String>)).width, 360);
    expect(find.text('Klassifizierungsregel'), findsWidgets);
  });
}
