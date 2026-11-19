// The Streaming tab must stream the whole sample and stop by itself.
//
// The sample's data: images are thousands of base64 characters. Streaming them
// a few characters at a time used to hide the half-written image for tens of
// seconds, which looked like the demo had stalled.
@TestOn('vm')
library;

import 'package:flutter_markdown_x_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

/// Upper bound on the simulated streaming time.
const _timeLimit = Duration(seconds: 20);
const _frame = Duration(milliseconds: 16);

void main() {
  testWidgets('the Streaming tab streams the whole sample and stops', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.tap(find.text('Streaming'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.text('Stop'), findsOneWidget);

    var elapsed = Duration.zero;
    while (find.text('Stop').evaluate().isNotEmpty && elapsed < _timeLimit) {
      await tester.pump(_frame);
      elapsed += _frame;
    }

    expect(
      find.text('Start'),
      findsOneWidget,
      reason: 'streaming did not finish within $_timeLimit',
    );
    expect(tester.takeException(), isNull);
  });
}
