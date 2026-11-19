// Widget-level checks for the HTML Living Standard phrasing tags (doc/html.md):
// cite / dfn / var, samp / tt, big, abbr / acronym, q, bdi / bdo, wbr and hr.
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';

import '../support/selection_harness.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

/// The effective style of the leaf span whose text is [text].
TextStyle? _style(WidgetTester tester, String text) {
  TextStyle? walk(InlineSpan span, TextStyle inherited) {
    if (span is! TextSpan) return null;
    final style = span.style == null ? inherited : inherited.merge(span.style);
    if (span.text == text) return style;
    for (final child in span.children ?? const <InlineSpan>[]) {
      final found = walk(child, style);
      if (found != null) return found;
    }
    return null;
  }

  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    final found = walk(rich.text, const TextStyle());
    if (found != null) return found;
  }
  return null;
}

/// All the text of the first paragraph-like RichText.
String _plain(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((rich) => rich.text.toPlainText(includePlaceholders: false))
    .join('|');

class _Tags extends MarkdownElementBuilder {
  final List<md.Element> seen = [];

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    seen.add(element);
    return null;
  }
}

void main() {
  group('italic family', () {
    for (final tag in ['cite', 'dfn', 'var']) {
      testWidgets('<$tag> is italic', (tester) async {
        await tester.pumpWidget(_app(MarkdownBody(data: 'a <$tag>x</$tag> b')));
        expect(_style(tester, 'x')?.fontStyle, FontStyle.italic);
        expect(_style(tester, 'a ')?.fontStyle, isNot(FontStyle.italic));
      });
    }
  });

  group('monospace', () {
    for (final tag in ['samp', 'tt']) {
      testWidgets('<$tag> uses the code font without a background', (
        tester,
      ) async {
        await tester.pumpWidget(_app(MarkdownBody(data: 'a <$tag>x</$tag> b')));
        final style = _style(tester, 'x')!;
        expect(style.fontFamily, 'monospace');
        expect(style.backgroundColor, isNull);
      });
    }

    testWidgets('inline code keeps its background', (tester) async {
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: 'a <code>x</code>',
            styleSheet: MarkdownStyleSheet(
              code: const TextStyle(backgroundColor: Color(0xFF123456)),
            ),
          ),
        ),
      );
      expect(_style(tester, 'x')?.backgroundColor, const Color(0xFF123456));
    });
  });

  group('font size', () {
    testWidgets('<big> is larger and <small> smaller by the CSS step 1.2', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const MarkdownBody(data: 'a <big>b</big> <small>s</small>')),
      );
      final base = _style(tester, 'a ')!.fontSize ?? 14.0;
      expect(_style(tester, 'b')!.fontSize, closeTo(base * 1.2, 0.001));
      expect(_style(tester, 's')!.fontSize, closeTo(base / 1.2, 0.001));
    });
  });

  group('abbr and acronym', () {
    for (final tag in ['abbr', 'acronym']) {
      testWidgets('<$tag title> has a dotted underline', (tester) async {
        await tester.pumpWidget(
          _app(
            MarkdownBody(
              data: '<$tag title="Long">L</$tag> and <$tag>N</$tag>',
            ),
          ),
        );
        final titled = _style(tester, 'L')!;
        expect(titled.decoration, TextDecoration.underline);
        expect(titled.decorationStyle, TextDecorationStyle.dotted);
        expect(
          _style(tester, 'N')!.decoration,
          isNot(TextDecoration.underline),
        );
      });
    }
  });

  group('generated text', () {
    testWidgets('q draws quotation marks, nested ones alternate', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const MarkdownBody(data: 'a <q>b <q>c</q></q> d')),
      );
      expect(_plain(tester), 'a “b ‘c’” d');
    });

    testWidgets('bdi, bdo and wbr insert their control characters', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const MarkdownBody(
            data: '<bdi>a</bdi> <bdo dir="rtl">b</bdo> c<wbr>d',
          ),
        ),
      );
      expect(_plain(tester), '\u{2068}a\u{2069} \u{202E}b\u{202C} c\u{200B}d');
    });
  });

  testWidgets('a block hr draws the same rule as ---', (tester) async {
    int boxes(String data) {
      return find
          .descendant(
            of: find.byType(MarkdownBody),
            matching: find.byType(DecoratedBox),
          )
          .evaluate()
          .length;
    }

    await tester.pumpWidget(_app(const MarkdownBody(data: 'a\n\nb')));
    final none = boxes('');
    await tester.pumpWidget(_app(const MarkdownBody(data: 'a\n\n---\n\nb')));
    final markdown = boxes('');
    await tester.pumpWidget(_app(const MarkdownBody(data: 'a\n\n<hr>\n\nb')));
    expect(markdown, greaterThan(none));
    expect(boxes(''), markdown);
  });

  group('copy', () {
    testWidgets('quotation marks are copied, invisible controls are not', (
      tester,
    ) async {
      final clipboard = ClipboardProbe();
      mockClipboard(tester, clipboard);
      await tester.pumpWidget(
        selectionApp(
          const MarkdownBody(
            data: '<q>a</q> <bdi>b</bdi> <bdo dir="rtl">c</bdo> d<wbr>e',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final text = await selectAllAndCopy(
        tester,
        clipboard,
        find.byType(MarkdownBody),
      );
      expect(text, '“a” b c de');
    });
  });

  group('builders', () {
    testWidgets('new tags reach builders under their original names', (
      tester,
    ) async {
      final builder = _Tags();
      const tags = [
        'cite',
        'dfn',
        'var',
        'samp',
        'tt',
        'big',
        'abbr',
        'acronym',
      ];
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: [for (final tag in tags) '<$tag title="T-$tag">x$tag</$tag>']
                .join(' '),
            builders: {for (final tag in tags) tag: builder},
          ),
        ),
      );
      expect(builder.seen.map((e) => e.tag), tags);
      final abbr = builder.seen.firstWhere((e) => e.tag == 'abbr');
      expect(abbr.attributes['title'], 'T-abbr');
      expect(abbr.textContent, 'xabbr');
      final cite = builder.seen.firstWhere((e) => e.tag == 'cite');
      expect(cite.attributes.containsKey('title'), isFalse);
    });
  });
}
