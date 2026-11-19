import 'dart:ui' show CheckedState;

import 'package:flutter/services.dart';
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_markdown_x/src/widgets/renderer.dart'
    show mdxLinkFocusLabel;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Iterable<Object> _checked(CheckedState state) => find.semantics
    .byPredicate(
      (node) => node.getSemanticsData().flagsCollection.isChecked == state,
    )
    .evaluate();

/// Whether the [TextSpan] holding [text] has a background color (focus indicator).
bool _highlighted(WidgetTester tester, String text) {
  var result = false;
  bool visit(InlineSpan span, TextStyle? inherited) {
    final style = span is TextSpan && span.style != null
        ? (inherited?.merge(span.style) ?? span.style)
        : inherited;
    if (span is TextSpan && span.text == text) {
      result = style?.backgroundColor != null;
      return false;
    }
    var keepGoing = true;
    span.visitDirectChildren((child) {
      keepGoing = keepGoing && visit(child, style);
      return keepGoing;
    });
    return keepGoing;
  }

  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    visit(richText.text, null);
  }
  return result;
}

void main() {
  group('Links', () {
    testWidgets('is exposed in semantics as a link with a label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(const MarkdownBody(data: 'see [the docs](https://a.example) now')),
      );
      expect(
        find.semantics.byLabel('the docs').evaluate().single,
        isSemantics(isLink: true, label: 'the docs', hasTapAction: true),
      );
      handle.dispose();
    });

    testWidgets(
      'can be focused in order with Tab and opened with Enter or Space',
      (tester) async {
        final taps = <String>[];
        await tester.pumpWidget(
          _app(
            MarkdownBody(
              data: '[one](#a) and [two](#b)\n\nplain\n\n[three](#c)',
              handleAnchorLinks: false,
              onTapLink: (text, href, title) => taps.add(href!),
            ),
          ),
        );
        expect(_highlighted(tester, 'one'), isFalse);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(_highlighted(tester, 'one'), isTrue);
        expect(_highlighted(tester, 'two'), isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(taps, ['#a']);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(_highlighted(tester, 'one'), isFalse);
        expect(_highlighted(tester, 'two'), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        expect(taps, ['#a', '#b']);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(_highlighted(tester, 'two'), isFalse);
        expect(_highlighted(tester, 'three'), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
        expect(taps, ['#a', '#b', '#c']);

        // Shift+Tab moves back.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(_highlighted(tester, 'three'), isFalse);
        expect(_highlighted(tester, 'two'), isTrue);
      },
    );

    testWidgets('links inside headings and table cells can also be focused', (
      tester,
    ) async {
      final taps = <String>[];
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '# [head](#h)\n\n| c |\n|---|\n| [cell](#c) |',
            handleAnchorLinks: false,
            onTapLink: (text, href, title) => taps.add(href!),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(taps, ['#h', '#c']);
    });

    testWidgets('a paragraph without links does not take focus', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const MarkdownBody(data: 'no links\n\nat all')),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(
        find.byWidgetPredicate(
          (w) => w is Focus && w.debugLabel == mdxLinkFocusLabel,
        ),
        findsNothing,
      );
    });

    testWidgets('focus state stays intact when the link changes on update', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const MarkdownBody(data: '[a](#1) [b](#2)')),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpWidget(_app(const MarkdownBody(data: '[a](#1)')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(tester.takeException(), isNull);
    });
  });

  group('details', () {
    testWidgets('summary is a button and exposes its expanded state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          const MarkdownBody(
            data:
                '<details><summary>More</summary>\n\nhidden body\n\n</details>',
          ),
        ),
      );
      expect(
        find.semantics.byLabel('More').evaluate().single,
        isSemantics(
          isButton: true,
          hasExpandedState: true,
          isExpanded: false,
          label: 'More',
          hasTapAction: true,
        ),
      );
      expect(find.text('hidden body'), findsNothing);

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(
        find.semantics.byLabel('More').evaluate().single,
        isSemantics(isButton: true, hasExpandedState: true, isExpanded: true),
      );
      expect(find.text('hidden body'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('can be toggled by keyboard (Tab, Enter, Space)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const MarkdownBody(
            data:
                '<details><summary>More</summary>\n\nhidden body\n\n</details>',
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('hidden body'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('hidden body'), findsNothing);
    });
  });

  group('Other elements', () {
    testWidgets('a heading is a header', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(const MarkdownBody(data: '# Title\n\ntext')),
      );
      expect(
        find.semantics.byLabel('Title').evaluate().single,
        isSemantics(isHeader: true),
      );
      handle.dispose();
    });

    testWidgets('an image becomes an image with its alt as label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          const MarkdownBody(
            data: 'x ![a red dot](http://example.invalid/x.png) y',
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The paragraph spoken text includes the image alt as an image.
      expect(
        find.semantics.byLabel(RegExp('a red dot')).evaluate().single,
        isSemantics(isImage: true),
      );
      handle.dispose();
    });

    testWidgets('an image without alt is not announced', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(const MarkdownBody(data: 'x ![](http://example.invalid/x.png) y')),
      );
      await tester.pumpAndSettle();
      expect(
        find.semantics
            .byPredicate(
              (node) => node.getSemanticsData().flagsCollection.isImage,
            )
            .evaluate(),
        isEmpty,
      );
      handle.dispose();
    });

    testWidgets(
      'with the default image display (including load failure) alt is read exactly once',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _app(
            const MarkdownBody(
              data: '![a red dot](http://example.invalid/x.png)',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.semantics.byLabel('a red dot').evaluate(), hasLength(1));
        handle.dispose();
      },
    );

    testWidgets('a task list checkbox exposes its checked state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(const MarkdownBody(data: '- [x] done\n- [ ] todo')),
      );
      expect(_checked(CheckedState.isTrue), hasLength(1));
      expect(_checked(CheckedState.isFalse), hasLength(1));
      handle.dispose();
    });

    testWidgets('table cells can be read one by one', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(const MarkdownBody(data: '| h1 | h2 |\n|---|---|\n| c1 | c2 |')),
      );
      for (final cell in ['h1', 'h2', 'c1', 'c2']) {
        expect(
          find.semantics.byLabel(cell).evaluate(),
          hasLength(1),
          reason: cell,
        );
      }
      handle.dispose();
    });
  });
}
