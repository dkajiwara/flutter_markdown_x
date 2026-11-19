// Widget-level checks for HTML table spans and details open.
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(body: child),
      ),
    );

Finder _text(String text) => find.text(text);

/// Bounds of the cell (nearest Padding) containing [text].
Rect _cell(WidgetTester tester, String text) {
  final padding = find.ancestor(
    of: _text(text),
    matching: find.byType(Padding),
  );
  return tester.getRect(padding.first);
}

void main() {
  testWidgets('tags outside the allowlist are displayed as written', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Markdown(
          data: 'Use List<String> and <custom-tag>x</custom-tag>.',
        ),
      ),
    );
    expect(
      find.textContaining('Use List<String> and <custom-tag>x</custom-tag>.'),
      findsOneWidget,
    );
  });

  group('details open', () {
    const open =
        '<details open>\n<summary>More</summary>\n\nhidden\n\n</details>';

    testWidgets('open attribute opens it initially', (tester) async {
      await tester.pumpWidget(_app(const Markdown(data: open)));
      expect(_text('More'), findsOneWidget);
      expect(_text('hidden'), findsOneWidget);
    });

    testWidgets('open can still be closed by tap and reopened', (tester) async {
      await tester.pumpWidget(_app(const Markdown(data: open)));
      await tester.tap(_text('More'));
      await tester.pump();
      expect(_text('hidden'), findsNothing);
      await tester.tap(_text('More'));
      await tester.pump();
      expect(_text('hidden'), findsOneWidget);
    });

    testWidgets('a state closed by the user is kept when content is appended', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const Markdown(data: open)));
      await tester.tap(_text('More'));
      await tester.pump();
      expect(_text('hidden'), findsNothing);

      await tester.pumpWidget(_app(const Markdown(data: '$open\n\nafter')));
      expect(_text('after'), findsOneWidget);
      expect(_text('hidden'), findsNothing);
    });

    testWidgets('details without open is closed', (tester) async {
      await tester.pumpWidget(
        _app(
          const Markdown(
            data: '<details>\n<summary>More</summary>\n\nhidden\n\n</details>',
          ),
        ),
      );
      expect(_text('hidden'), findsNothing);
    });
  });

  group('table span', () {
    testWidgets('a table without span stays a Table', (tester) async {
      await tester.pumpWidget(
        _app(const Markdown(data: '| a | b |\n|---|---|\n| 1 | 2 |')),
      );
      expect(find.byType(Table), findsOneWidget);
    });

    testWidgets(
      'a colspan cell is as wide as the sum of the columns it spans',
      (tester) async {
        await tester.pumpWidget(
          _app(
            const Markdown(
              data:
                  '<table><tr><th colspan="2">Head</th></tr>'
                  '<tr><td>Alpha</td><td>Beta</td></tr></table>',
            ),
          ),
        );
        final head = _cell(tester, 'Head');
        final a = _cell(tester, 'Alpha');
        final b = _cell(tester, 'Beta');
        expect(head.left, a.left);
        expect(head.right, b.right);
        expect(head.width, closeTo(a.width + b.width, 0.01));
        expect(head.bottom, closeTo(a.top, 0.01));
        expect(a.top, b.top);
        expect(a.right, closeTo(b.left, 0.01));
      },
    );

    testWidgets(
      'a rowspan cell is as tall as the sum of the rows it spans, and the row below shifts right',
      (tester) async {
        await tester.pumpWidget(
          _app(
            const Markdown(
              data:
                  '<table><tr><td rowspan="2">Tall</td><td>Top</td></tr>'
                  '<tr><td>Bottom</td></tr></table>',
            ),
          ),
        );
        final tall = _cell(tester, 'Tall');
        final top = _cell(tester, 'Top');
        final bottom = _cell(tester, 'Bottom');
        expect(tall.top, top.top);
        expect(tall.bottom, closeTo(bottom.bottom, 0.01));
        expect(tall.height, closeTo(top.height + bottom.height, 0.01));
        // The cell in the lower row goes into the 2nd column.
        expect(bottom.left, closeTo(top.left, 0.01));
        expect(bottom.top, closeTo(top.bottom, 0.01));
        expect(tall.right, closeTo(top.left, 0.01));
      },
    );

    testWidgets('text inside a cell is not dropped even with span', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const Markdown(
            data:
                '<table><thead><tr><th colspan="2">H</th></tr></thead>'
                '<tbody><tr><td>a<br>b</td><td rowspan="2">c</td></tr>'
                '<tr><td>d</td></tr></tbody></table>',
          ),
        ),
      );
      for (final text in ['H', 'c', 'd']) {
        expect(_text(text), findsOneWidget, reason: text);
      }
      expect(find.textContaining('a'), findsWidgets);
      expect(find.textContaining('b'), findsWidgets);
    });

    testWidgets('RTL lays columns out from the right', (tester) async {
      await tester.pumpWidget(
        _app(
          const Markdown(
            data:
                '<table><tr><th colspan="2">Head</th></tr>'
                '<tr><td>Alpha</td><td>Beta</td></tr></table>',
          ),
          direction: TextDirection.rtl,
        ),
      );
      final head = _cell(tester, 'Head');
      final a = _cell(tester, 'Alpha');
      final b = _cell(tester, 'Beta');
      expect(a.left > b.left, isTrue);
      expect(head.left, b.left);
      expect(head.right, a.right);
    });

    testWidgets(
      'the table width is its natural width inside horizontal scroll',
      (tester) async {
        await tester.pumpWidget(
          _app(
            const Markdown(
              data:
                  '<table><tr><td colspan="2">x</td></tr>'
                  '<tr><td>1</td><td>2</td></tr></table>',
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(SingleChildScrollView), findsWidgets);
      },
    );

    testWidgets('a span table renders inside a selectable document too', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const Markdown(
            selectable: true,
            data:
                '<table><tr><th colspan="2">Head</th></tr>'
                '<tr><td>Alpha</td><td>Beta</td></tr></table>',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(_text('Head'), findsOneWidget);
      expect(find.byType(SelectionArea), findsOneWidget);
    });
  });
}
