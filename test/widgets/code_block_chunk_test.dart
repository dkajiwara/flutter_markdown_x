import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

String _code(int lines) =>
    [for (var i = 0; i < lines; i++) 'final v$i = "s$i"; // c$i'].join('\n');

String _text(WidgetTester tester) => [
  for (final widget in tester.widgetList<RichText>(
    find.descendant(
      of: find.byType(SingleChildScrollView),
      matching: find.byType(RichText),
    ),
  ))
    widget.text.toPlainText(),
].join('\n');

Future<void> _pump(WidgetTester tester, String markdown) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: MarkdownBody(data: markdown)),
    ),
  ),
);

void main() {
  const chunk = MarkdownXDefaults.codeChunkLines;

  testWidgets('a code block within the chunk line count stays a single Text', (
    tester,
  ) async {
    final code = _code(chunk);
    await _pump(tester, '```dart\n$code\n```');
    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView).last,
        matching: find.byType(RichText),
      ),
      findsOneWidget,
    );
    expect(_text(tester), contains(code));
  });

  for (final language in ['dart', 'text']) {
    testWidgets(
      'a huge code block ($language) is split by line count and content is unchanged',
      (tester) async {
        final code = _code(chunk * 2 + 50);
        await _pump(tester, '```$language\n$code\n```');
        final texts = tester
            .widgetList<RichText>(
              find.descendant(
                of: find.byType(SingleChildScrollView).last,
                matching: find.byType(RichText),
              ),
            )
            .map((w) => w.text.toPlainText())
            .toList();
        expect(texts, hasLength(3));
        expect(texts.join('\n'), code);
        expect(texts.first.split('\n'), hasLength(chunk));
      },
    );
  }
}
