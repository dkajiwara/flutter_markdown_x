// The Static tab toggles the task list checkboxes of the sample by rewriting its text.
@TestOn('vm')
library;

import 'package:flutter_markdown_x_example/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('tapping a task in the Static tab toggles it', (tester) async {
    tester.view.physicalSize = const Size(900, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    final checked = find.byIcon(Icons.check_box);
    final unchecked = find.byIcon(Icons.check_box_outline_blank);
    final checkedBefore = checked.evaluate().length;
    final uncheckedBefore = unchecked.evaluate().length;
    expect(checkedBefore, greaterThan(0));
    expect(uncheckedBefore, greaterThan(0));

    await tester.ensureVisible(unchecked.first);
    await tester.tap(unchecked.first);
    await tester.pumpAndSettle();
    expect(checked.evaluate().length, checkedBefore + 1);
    expect(unchecked.evaluate().length, uncheckedBefore - 1);

    await tester.ensureVisible(checked.first);
    await tester.tap(checked.first);
    await tester.pumpAndSettle();
    expect(checked.evaluate().length, checkedBefore);
    expect(unchecked.evaluate().length, uncheckedBefore);
    expect(tester.takeException(), isNull);
  });
}
