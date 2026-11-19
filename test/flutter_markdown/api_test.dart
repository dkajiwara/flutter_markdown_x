// The flutter_markdown compatible widget API: defaults, callbacks, and wired parameters.
import 'package:flutter/gestures.dart';
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

/// The style of the leaf span with [text], merged with the styles of its ancestors.
TextStyle? _styleOf(WidgetTester tester, String text) {
  TextStyle? found;
  void walk(InlineSpan span, TextStyle? inherited) {
    if (span is! TextSpan) return;
    final style = inherited?.merge(span.style) ?? span.style;
    if (span.text == text) found = style;
    span.children?.forEach((child) => walk(child, style));
  }

  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    walk(richText.text, null);
  }
  return found;
}

TextSpan? _findSpan(WidgetTester tester, String text) {
  TextSpan? found;
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    richText.text.visitChildren((span) {
      if (span is TextSpan && span.text == text) found = span;
      return true;
    });
  }
  return found;
}

void main() {
  group('defaults', () {
    test('Markdown has flutter_markdown defaults', () {
      const markdown = Markdown(data: '');
      expect(markdown.padding, const EdgeInsets.all(16.0));
      expect(markdown.shrinkWrap, isFalse);
      expect(markdown.noScroll, isFalse);
      expect(markdown.selectable, isFalse);
      expect(markdown.fitContent, isFalse);
      expect(markdown.softLineBreak, isFalse);
      expect(markdown.styleSheetTheme, isNull);
      expect(
        markdown.listItemCrossAxisAlignment,
        MarkdownListItemCrossAxisAlignment.baseline,
      );
      expect(markdown.builders, isEmpty);
      expect(markdown.paddingBuilders, isEmpty);
    });

    test('MarkdownBody shrinks and fits its content', () {
      const body = MarkdownBody(data: '');
      expect(body.shrinkWrap, isTrue);
      expect(body.fitContent, isTrue);
    });

    test('MarkdownWidget defaults the theme to material', () {
      expect(const SliverMarkdown(data: '').styleSheetTheme, isNull);
    });
  });

  group('onTapLink', () {
    testWidgets('receives text, href and title', (tester) async {
      final calls = <(String, String?, String)>[];
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '[the **docs**](https://a.test/x "Docs") and [plain](/p)',
            onTapLink: (text, href, title) => calls.add((text, href, title)),
          ),
        ),
      );
      (_findSpan(tester, 'the ')!.recognizer! as TapGestureRecognizer).onTap!();
      (_findSpan(tester, 'plain')!.recognizer! as TapGestureRecognizer)
          .onTap!();
      expect(calls, [
        ('the docs', 'https://a.test/x', 'Docs'),
        ('plain', '/p', ''),
      ]);
    });

    testWidgets('link text keeps soft breaks and uses an image alt', (
      tester,
    ) async {
      final calls = <(String, String?, String)>[];
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            // An unsupported scheme fails on every platform, so the alt text is shown. (A relative
            // path would load from the page on the web and the tap would hit the loading display.)
            data: '[one\ntwo](/a)\n\n[![the alt](ftp://a.test/a.png)](/b)',
            handleAnchorLinks: false,
            onTapLink: (text, href, title) => calls.add((text, href, title)),
          ),
        ),
      );
      (_findSpan(tester, 'one')!.recognizer! as TapGestureRecognizer).onTap!();
      await tester.tap(find.byType(MdxImageView));
      expect(calls, [('one\ntwo', '/a', ''), ('the alt', '/b', '')]);
    });

    testWidgets('a link without children renders nothing tappable', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const MarkdownBody(data: 'x [](/a) y')));
      expect(_findSpan(tester, '')?.recognizer, isNull);
    });

    testWidgets('uses the callback of the newest widget', (tester) async {
      final calls = <String>[];
      Widget build(String tag) => _app(
        MarkdownBody(
          data: '[x](u)',
          onTapLink: (text, href, title) => calls.add(tag),
        ),
      );
      await tester.pumpWidget(build('old'));
      await tester.pumpWidget(build('new'));
      (_findSpan(tester, 'x')!.recognizer! as TapGestureRecognizer).onTap!();
      expect(calls, ['new']);
    });

    testWidgets('an internal anchor is handled, a missing one is forwarded', (
      tester,
    ) async {
      final calls = <String?>[];
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '[a](#missing)\n\n# Heading\n\n[b](#heading)',
            onTapLink: (text, href, title) => calls.add(href),
          ),
        ),
      );
      (_findSpan(tester, 'a')!.recognizer! as TapGestureRecognizer).onTap!();
      (_findSpan(tester, 'b')!.recognizer! as TapGestureRecognizer).onTap!();
      await tester.pump();
      expect(calls, ['#missing']);
    });
  });

  group('rendering', () {
    testWidgets('the default look is flutter_markdown fromTheme', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const MarkdownBody(data: '[l](u)')));
      expect(_styleOf(tester, 'l')!.color, Colors.blue);
      expect(
        _styleOf(tester, 'l')!.decoration,
        isNot(TextDecoration.underline),
      );
    });

    testWidgets('a styleSheet is merged onto the theme', (tester) async {
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '[l](u)',
            styleSheet: MarkdownStyleSheet(a: const TextStyle(fontSize: 31)),
          ),
        ),
      );
      final style = _styleOf(tester, 'l')!;
      expect(style.fontSize, 31);
      expect(style.color, Colors.blue);
    });

    testWidgets('softLineBreak draws a newline instead of a space', (
      tester,
    ) async {
      Future<String> plain({required bool soft}) async {
        await tester.pumpWidget(
          _app(MarkdownBody(data: 'one\ntwo', softLineBreak: soft)),
        );
        return tester
            .widget<RichText>(find.byType(RichText).first)
            .text
            .toPlainText();
      }

      expect(await plain(soft: false), 'one two');
      expect(await plain(soft: true), 'one\ntwo');
    });

    testWidgets('block spacing and padding follow the style sheet', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: 'a\n\nb',
            styleSheet: MarkdownStyleSheet(blockSpacing: 21),
          ),
        ),
      );
      final first = tester.getBottomLeft(find.text('a', findRichText: true));
      final second = tester.getTopLeft(find.text('b', findRichText: true));
      expect(second.dy - first.dy, 21);
    });

    testWidgets('onTapText fires on a tap of selectable text', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: 'tap me',
            selectable: true,
            onTapText: () => taps++,
          ),
        ),
      );
      await tester.tap(find.text('tap me', findRichText: true));
      expect(taps, 1);
    });

    testWidgets('checkbox and bullet builders are used', (tester) async {
      final bullets = <(int, BulletStyle, int)>[];
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '- a\n  - b\n\n3. x\n4. y\n\n- [x] done',
            bulletBuilder: (p) {
              bullets.add((p.index, p.style, p.nestLevel));
              return const Text('B');
            },
            checkboxBuilder: (checked) => Text(checked ? 'Y' : 'N'),
          ),
        ),
      );
      expect(bullets, [
        (0, BulletStyle.unorderedList, 0),
        (0, BulletStyle.unorderedList, 1),
        (2, BulletStyle.orderedList, 0),
        (3, BulletStyle.orderedList, 0),
      ]);
      expect(find.text('Y'), findsOneWidget);
    });

    testWidgets('sizedImageBuilder gets the configuration', (tester) async {
      MarkdownImageConfig? config;
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '![alt](http://a.test/i.png#100x50 "t")',
            sizedImageBuilder: (c) {
              config = c;
              return const SizedBox(key: ValueKey('img'));
            },
          ),
        ),
      );
      expect(find.byKey(const ValueKey('img')), findsOneWidget);
      expect(config!.uri.toString(), 'http://a.test/i.png');
      expect((config!.alt, config!.title), ('alt', 't'));
      expect((config!.width, config!.height), (100, 50));
    });

    testWidgets('Markdown pads its content by default', (tester) async {
      await tester.pumpWidget(_app(const Markdown(data: 'hello')));
      final topLeft = tester.getTopLeft(find.text('hello', findRichText: true));
      expect(topLeft.dx, 16);
    });

    testWidgets('onSelectionChanged reports the selected text', (tester) async {
      final calls = <String?>[];
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: 'select me',
            selectable: true,
            onSelectionChanged: (text, selection, cause) {
              calls.add(text);
              expect(cause, isNull);
            },
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getTopLeft(find.text('select me', findRichText: true)) +
            const Offset(2, 5),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(calls.whereType<String>(), isNotEmpty);
    });
  });
}
