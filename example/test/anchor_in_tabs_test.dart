// Tapping an internal link in the Static tab must not switch the TabBarView.
@TestOn('vm')
library;

import 'package:flutter_markdown_x_example/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('tapping the footnote reference keeps the Static tab', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();
    final controller = DefaultTabController.of(
      tester.element(find.byType(TabBarView)),
    );
    expect(controller.index, 0);

    // The footnote reference is a superscript "1" in "Footnotes[^1]".
    final reference = find.text('1');
    await tester.scrollUntilVisible(
      reference,
      300,
      scrollable: find
          .descendant(
            of: find.byType(TabBarView),
            matching: find.byType(Scrollable),
          )
          .at(1),
    );
    await tester.pumpAndSettle();
    await tester.tap(reference.first);
    await tester.pumpAndSettle();

    expect(controller.index, 0);
    expect(find.text('Static'), findsOneWidget);
    final definition = find.textContaining('↩');
    expect(definition, findsWidgets);
    final y = tester.getCenter(definition.first).dy;
    expect(y, inInclusiveRange(0, tester.view.physicalSize.height));
    final tabScrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(TabBarView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(tabScrollable.position.pixels, 0.0); // still on page 0
    expect(tester.takeException(), isNull);
  });
}
