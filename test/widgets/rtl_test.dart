import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(Widget child, {TextDirection direction = TextDirection.rtl}) =>
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: double.infinity, child: child),
          ),
        ),
      ),
    );

Rect _rect(WidgetTester tester, Finder finder) => tester.getRect(finder.first);

void main() {
  final style = MarkdownStyleSheet.fromTheme(
    ThemeData(textTheme: Typography.material2021().englishLike),
  );
  final listCol = style.listIndent! + style.listBulletPadding!.horizontal;

  for (final direction in TextDirection.values) {
    final rtl = direction == TextDirection.rtl;

    group('$direction', () {
      testWidgets('a paragraph aligns to the start side', (tester) async {
        await tester.pumpWidget(
          _app(const MarkdownBody(data: 'short'), direction: direction),
        );
        final screen = tester.getRect(find.byType(Scaffold));
        final text = _rect(tester, find.text('short'));
        if (rtl) {
          expect(text.right, closeTo(screen.right, 0.5));
        } else {
          expect(text.left, closeTo(screen.left, 0.5));
        }
      });

      testWidgets('the list marker is on the start side, outside the body', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(
            const MarkdownBody(data: '- item\n\n1. first'),
            direction: direction,
          ),
        );
        final screen = tester.getRect(find.byType(Scaffold));
        for (final pair in [('•', 'item'), ('1.', 'first')]) {
          final marker = _rect(tester, find.text(pair.$1));
          final body = _rect(tester, find.text(pair.$2));
          if (rtl) {
            expect(marker.left, greaterThan(body.right - 0.5), reason: pair.$1);
            // The marker stays inside the list column at the start edge.
            expect(marker.right, lessThanOrEqualTo(screen.right + 0.5));
            expect(
              marker.left,
              greaterThanOrEqualTo(screen.right - listCol - 0.5),
            );
            expect(body.right, closeTo(screen.right - listCol, 0.5));
          } else {
            expect(marker.right, lessThan(body.left + 0.5), reason: pair.$1);
            expect(marker.left, greaterThanOrEqualTo(screen.left - 0.5));
            expect(marker.right, lessThan(screen.left + listCol));
            expect(body.left, closeTo(screen.left + listCol, 0.5));
          }
        }
      });

      testWidgets('the task list checkbox is also on the start side', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(const MarkdownBody(data: '- [x] done'), direction: direction),
        );
        final icon = _rect(tester, find.byType(Icon));
        final body = _rect(tester, find.text('done'));
        if (rtl) {
          expect(icon.left, greaterThan(body.right - 0.5));
        } else {
          expect(icon.right, lessThan(body.left + 0.5));
        }
      });

      testWidgets('the quote box padding is applied on the start side', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(const MarkdownBody(data: '> quoted'), direction: direction),
        );
        final boxFinder = find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox && w.decoration == style.blockquoteDecoration,
        );
        final container = tester.getRect(boxFinder.first);
        final text = _rect(tester, find.text('quoted'));
        final inset = style.blockquotePadding!.horizontal / 2;
        if (rtl) {
          expect(text.right, closeTo(container.right - inset, 0.5));
        } else {
          expect(text.left, closeTo(container.left + inset, 0.5));
        }
      });

      testWidgets('table columns are laid out from the start', (tester) async {
        await tester.pumpWidget(
          _app(
            const MarkdownBody(data: '| h1 | h2 |\n|---|---|\n| c1 | c2 |'),
            direction: direction,
          ),
        );
        final h1 = _rect(tester, find.text('h1'));
        final h2 = _rect(tester, find.text('h2'));
        expect(h1.left < h2.left, !rtl);
        expect(
          _rect(tester, find.text('c1')).left <
              _rect(tester, find.text('c2')).left,
          !rtl,
        );
      });

      testWidgets('code block text is always LTR and starts from the left', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(
            const MarkdownBody(data: '```\nfoo(bar)\n```'),
            direction: direction,
          ),
        );
        final text = find.textContaining('foo(bar)');
        expect(Directionality.of(tester.element(text)), TextDirection.ltr);
        final block = _rect(tester, find.byType(SingleChildScrollView).last);
        expect(
          _rect(tester, text).left,
          closeTo(block.left + style.codeblockPadding!.left, 0.5),
        );
      });

      testWidgets(
        'the details arrow is on the start side and its direction matches',
        (tester) async {
          await tester.pumpWidget(
            _app(
              const MarkdownBody(
                data: '<details><summary>Sum</summary>\n\nbody\n\n</details>',
              ),
              direction: direction,
            ),
          );
          final screen = tester.getRect(find.byType(Scaffold));
          final icon = find.byType(Icon);
          final summary = _rect(tester, find.text('Sum'));
          final arrow = _rect(tester, icon);
          if (rtl) {
            expect(arrow.left, greaterThan(summary.right - 0.5));
            expect(arrow.right, closeTo(screen.right, 0.5));
          } else {
            expect(arrow.right, lessThan(summary.left + 0.5));
            expect(arrow.left, closeTo(screen.left, 0.5));
          }
          // The closed arrow flips to match the direction (Icon matchTextDirection).
          final data = tester.widget<Icon>(icon).icon!;
          expect(data.matchTextDirection, isTrue);

          await tester.tap(find.text('Sum'));
          await tester.pumpAndSettle();
          final body = _rect(tester, find.text('body'));
          if (rtl) {
            expect(body.right, closeTo(screen.right - style.listIndent!, 0.5));
          } else {
            expect(body.left, closeTo(screen.left + style.listIndent!, 0.5));
          }
        },
      );
    });
  }
}
