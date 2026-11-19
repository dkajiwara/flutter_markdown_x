// The example wires flutter_math_fork and mermaid_flutter into both tabs.
@TestOn('vm')
library;

import 'package:flutter_markdown_x_example/main.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mermaid_flutter/mermaid_flutter.dart';

void main() {
  testWidgets('the Static tab renders math and a Mermaid diagram', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();
    expect(find.byType(Math), findsWidgets);
    expect(find.byType(MermaidDiagram), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Streaming tab draws math and the diagram once closed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ExampleApp());
    await tester.tap(find.text('Streaming'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pump();

    var elapsed = Duration.zero;
    var sawOpenFence = false;
    while (find.text('Stop').evaluate().isNotEmpty &&
        elapsed < const Duration(seconds: 20)) {
      await tester.pump(const Duration(milliseconds: 16));
      elapsed += const Duration(milliseconds: 16);
      // While the fence is open the source is a code block, not a diagram.
      if (find.textContaining('A[Start]').evaluate().isNotEmpty &&
          find.byType(MermaidDiagram).evaluate().isEmpty) {
        sawOpenFence = true;
      }
    }

    expect(find.text('Start'), findsOneWidget);
    expect(sawOpenFence, isTrue);
    expect(find.byType(Math), findsWidgets);
    expect(find.byType(MermaidDiagram), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
