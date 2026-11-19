import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/selection_harness.dart';

const _mixed = '''
Para one

- a
- b

1. x
2. y

| h1 | h2 |
|---|---|
| c1 | c2 |

```
line1
line2
```

> quote
''';

String _lines(int count, {Set<int> blank = const {}}) =>
    [for (var i = 1; i <= count; i++) blank.contains(i) ? '' : 'l$i']
        .join('\n');

Widget _fence(String code) => MarkdownBody(data: '```\n$code\n```');

/// The Text inside [SelectionArea] (selection is driven through this inner context).
final _insideArea = find.descendant(
  of: find.byType(SelectionArea),
  matching: find.byType(RichText),
);

void main() {
  late ClipboardProbe clipboard;

  setUp(() => clipboard = ClipboardProbe());

  Future<String?> copyAllOf(WidgetTester tester, Widget child) async {
    mockClipboard(tester, clipboard);
    await tester.pumpWidget(selectionApp(child));
    await tester.pumpAndSettle();
    return selectAllAndCopy(tester, clipboard, find.byType(MarkdownBody));
  }

  group('Copying multiple blocks', () {
    testWidgets(
      'separates paragraphs, lists, tables, code and quotes with newlines and tabs',
      (tester) async {
        final text = await copyAllOf(tester, const MarkdownBody(data: _mixed));
        expect(
          text,
          'Para one\n• a\n• b\n1. x\n2. y\nh1\th2\nc1\tc2\nline1\nline2\nquote',
        );
      },
    );

    testWidgets(
      'Markdown (sliver) copies already-built blocks in the same format',
      (tester) async {
        mockClipboard(tester, clipboard);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SelectionArea(child: const Markdown(data: _mixed)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final text = await selectAllAndCopy(
          tester,
          clipboard,
          find.byType(Markdown),
        );
        expect(
          text,
          'Para one\n• a\n• b\n1. x\n2. y\nh1\th2\nc1\tc2\nline1\nline2\nquote',
        );
      },
    );

    testWidgets(
      'also separates nested blocks (list in a quote, multiple paragraphs in a list item)',
      (tester) async {
        final text = await copyAllOf(
          tester,
          const MarkdownBody(
            data: '> q1\n>\n> - i1\n> - i2\n\n- p1\n\n  p2\n- n',
          ),
        );
        expect(text, 'q1\n• i1\n• i2\n• p1\np2\n• n');
      },
    );

    testWidgets('no newline is added when only one block is selected', (
      tester,
    ) async {
      mockClipboard(tester, clipboard);
      await tester.pumpWidget(
        selectionApp(const MarkdownBody(data: 'alpha beta\n\ngamma')),
      );
      await tester.pumpAndSettle();
      final target =
          tester.getTopLeft(find.textContaining('alpha')) + const Offset(4, 4);
      final gesture = await tester.startGesture(
        target,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.down(target);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump();
      final text = await copySelection(
        tester,
        clipboard,
        find.byType(MarkdownBody),
      );
      expect(text, isNotNull);
      expect(text, isNot(contains('\n')));
      expect(text, isNot(contains('gamma')));
    });

    testWidgets('an empty cell emits no separator tab (known limitation)', (
      tester,
    ) async {
      final text = await copyAllOf(
        tester,
        const MarkdownBody(data: '| a | b | c |\n|---|---|---|\n| 1 |  | 3 |'),
      );
      expect(text, 'a\tb\tc\n1\t3');
    });

    testWidgets(
      'task list copies only the body, not the checkbox state as text',
      (tester) async {
        final text = await copyAllOf(
          tester,
          const MarkdownBody(data: '- [x] done\n- [ ] todo'),
        );
        expect(text, 'done\ntodo');
      },
    );

    testWidgets('no selection container is created outside SelectionArea', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MarkdownBody(data: _mixed)),
        ),
      );
      expect(find.byType(SelectionContainer), findsNothing);
    });
  });

  group('RTL', () {
    testWidgets(
      'RTL still copies markers and cells in logical order (from start)',
      (tester) async {
        mockClipboard(tester, clipboard);
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SelectionArea(
                  child: SingleChildScrollView(
                    child: SizedBox(
                      width: double.infinity,
                      child: const MarkdownBody(
                        data: '- a\n- b\n\n| h1 | h2 |\n|---|---|\n| c1 | c2 |',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final text = await selectAllAndCopy(
          tester,
          clipboard,
          find.byType(MarkdownBody),
        );
        expect(text, '• a\n• b\nh1\th2\nc1\tc2');
      },
    );
  });

  group('code block', () {
    for (final count in [199, 200, 201, 400, 401, 450]) {
      testWidgets(
        '$count lines are copied with exact newlines even across chunk boundaries',
        (tester) async {
          final code = _lines(count);
          final text = await copyAllOf(tester, _fence(code));
          expect(text, code);
        },
      );
    }

    testWidgets('a blank line at a chunk boundary is preserved', (
      tester,
    ) async {
      for (final blank in [
        {200},
        {201},
        {199, 200, 201, 202},
      ]) {
        final code = _lines(402, blank: blank);
        final text = await copyAllOf(tester, _fence(code));
        expect(text, code, reason: 'blank: $blank');
      }
    });

    testWidgets('also separates code from the paragraphs around it', (
      tester,
    ) async {
      final code = _lines(250);
      final text = await copyAllOf(
        tester,
        MarkdownBody(data: 'before\n\n```\n$code\n```\n\nafter'),
      );
      expect(text, 'before\n$code\nafter');
    });
  });

  group('inline', () {
    testWidgets(
      'copies superscript and subscript as characters at their original position',
      (tester) async {
        final text = await copyAllOf(
          tester,
          const MarkdownBody(
            data: 'H<sub>2</sub>O and x<sup>2</sup>y and `code` [link](http://a.b) end',
          ),
        );
        expect(text, 'H2O and x2y and code link end');
      },
    );

    testWidgets('copies superscript and subscript on wrapped lines in order', (
      tester,
    ) async {
      final words = List.filled(30, 'word').join(' ');
      final text = await copyAllOf(
        tester,
        MarkdownBody(data: '$words E=mc<sup>2</sup> $words H<sub>2</sub>O end'),
      );
      expect(text, '$words E=mc2 $words H2O end');
    });

    testWidgets(
      'image alt is not copied (nor the fallback shown on load failure)',
      (tester) async {
        final text = await copyAllOf(
          tester,
          const MarkdownBody(
            data: 'a ![the alt](http://example.invalid/x.png) b',
          ),
        );
        expect(text, 'a  b');
      },
    );

    testWidgets('the footnote back link ↩ is included in the copy', (
      tester,
    ) async {
      final text = await copyAllOf(
        tester,
        const MarkdownBody(data: 'text[^1]\n\n[^1]: note'),
      );
      expect(text, contains('note'));
      expect(text, contains('↩'));
    });
  });

  group('selectable argument', () {
    testWidgets('MarkdownBody(selectable: true) wraps in SelectionArea', (
      tester,
    ) async {
      mockClipboard(tester, clipboard);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownBody(data: 'one\n\ntwo', selectable: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SelectionArea), findsOneWidget);
      final text = await selectAllAndCopy(tester, clipboard, _insideArea);
      expect(text, 'one\ntwo');
    });

    testWidgets('Markdown(selectable: true) wraps in SelectionArea', (
      tester,
    ) async {
      mockClipboard(tester, clipboard);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Markdown(data: 'one\n\ntwo', selectable: true)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SelectionArea), findsOneWidget);
      final text = await selectAllAndCopy(tester, clipboard, _insideArea);
      expect(text, 'one\ntwo');
    });

    testWidgets('does not create SelectionArea by default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Markdown(data: 'one')),
        ),
      );
      expect(find.byType(SelectionArea), findsNothing);
    });
  });

  group('Markdown lazy building', () {
    testWidgets('off-screen blocks are not included in select-all', (
      tester,
    ) async {
      mockClipboard(tester, clipboard);
      final data = [for (var i = 0; i < 300; i++) 'paragraph $i'].join('\n\n');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionArea(child: Markdown(data: data)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final text = await selectAllAndCopy(
        tester,
        clipboard,
        find.byType(Markdown),
      );
      expect(text, startsWith('paragraph 0\nparagraph 1\n'));
      expect(text, isNot(contains('paragraph 299')));
    });
  });

  group('Selection during updates', () {
    Widget app(String data, {bool streaming = true}) =>
        selectionApp(MarkdownBody(data: data, streaming: streaming));

    testWidgets(
      'appending a block does not crash and keeps selection of unchanged blocks',
      (tester) async {
        mockClipboard(tester, clipboard);
        await tester.pumpWidget(app('first\n\nsecond'));
        await tester.pumpAndSettle();
        Actions.invoke(
          tester.element(find.byType(MarkdownBody)),
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();

        await tester.pumpWidget(app('first\n\nsecond\n\nthird'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final text = await copySelection(
          tester,
          clipboard,
          find.byType(MarkdownBody),
        );
        expect(text, startsWith('first\nsecond'));
      },
    );

    testWidgets(
      'growing the last block does not crash and keeps selection of earlier blocks',
      (tester) async {
        mockClipboard(tester, clipboard);
        await tester.pumpWidget(app('first\n\nsecond'));
        await tester.pumpAndSettle();
        Actions.invoke(
          tester.element(find.byType(MarkdownBody)),
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();

        for (final tail in [
          'second more',
          'second more words',
          'second **more',
        ]) {
          await tester.pumpWidget(app('first\n\n$tail'));
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
        final text = await copySelection(
          tester,
          clipboard,
          find.byType(MarkdownBody),
        );
        // Selection of the changed block is dropped; selection of unchanged blocks is kept.
        expect(text, 'first');
      },
    );

    testWidgets('does not crash when the selected block changes', (
      tester,
    ) async {
      mockClipboard(tester, clipboard);
      await tester.pumpWidget(app('first\n\nsecond'));
      await tester.pumpAndSettle();
      Actions.invoke(
        tester.element(find.byType(MarkdownBody)),
        const SelectAllTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pump();
      await tester.pumpWidget(app('FIRST changed\n\nsecond'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(app('second'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await copySelection(tester, clipboard, find.byType(MarkdownBody));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'select-all while appending in Markdown (sliver) does not crash',
      (tester) async {
        mockClipboard(tester, clipboard);
        Widget sliverApp(String data) => MaterialApp(
          home: Scaffold(
            body: SelectionArea(child: Markdown(data: data, streaming: true)),
          ),
        );
        var data = 'first\n\nsecond';
        await tester.pumpWidget(sliverApp(data));
        await tester.pumpAndSettle();
        Actions.invoke(
          tester.element(find.byType(Markdown)),
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();
        for (var i = 0; i < 8; i++) {
          data += ' w$i';
          await tester.pumpWidget(sliverApp(data));
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
        data += '\n\nthird';
        await tester.pumpWidget(sliverApp(data));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final text = await copySelection(
          tester,
          clipboard,
          find.byType(Markdown),
        );
        expect(text, 'first');
      },
    );
  });
}
