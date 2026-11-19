// GitHub emoji shortcodes: markdownXEmojiExtension and its automatic enabling
// (doc/extensions.md, doc/flutter_markdown_compat.md section 5b).
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_markdown_x/src/parser/syntax_compat.dart'
    show resetReportedSyntaxes;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

List<MdxBlock> _apply(String source) =>
    applyMarkdownXExtensions(parseMarkdown(source), [markdownXEmojiExtension]);

List<MdxInline> _inlines(String source) =>
    (_apply(source).first as MdxParagraph).inlines;

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

bool _hasText(WidgetTester tester, String needle) => tester
    .widgetList<RichText>(find.byType(RichText))
    .any((r) => r.text.toPlainText().contains(needle));

void main() {
  setUp(resetReportedSyntaxes);

  group('transform', () {
    test('a known shortcode becomes plain text merged with its neighbours', () {
      expect(_inlines('a :smile: b'), [MdxText('a ${md.emojis['smile']} b')]);
    });

    test('+1 and -1 and digits work', () {
      expect(_inlines(':+1: :-1: :100:'), [
        MdxText('${md.emojis['+1']} ${md.emojis['-1']} ${md.emojis['100']}'),
      ]);
    });

    test('an unknown shortcode is left as is (the IR is unchanged)', () {
      final parsed = parseMarkdown('a :notanemoji: b :: ::');
      expect(
        identical(
          applyMarkdownXExtensions(parsed, [markdownXEmojiExtension]),
          parsed,
        ),
        isTrue,
      );
    });

    test('adjacent shortcodes convert', () {
      expect(_inlines(':smile::tada:'), [
        MdxText('${md.emojis['smile']}${md.emojis['tada']}'),
      ]);
    });

    test('an unknown shortcode does not hide an overlapping known one', () {
      // EmojiSyntax advances one character after a rejected match.
      expect(_inlines(':foo:smile:'), [MdxText(':foo${md.emojis['smile']}')]);
    });

    test('upper case is not a shortcode', () {
      final parsed = parseMarkdown(':SMILE: :Smile:');
      expect(
        identical(
          applyMarkdownXExtensions(parsed, [markdownXEmojiExtension]),
          parsed,
        ),
        isTrue,
      );
    });

    test('colons in times and autolinked URLs are left alone', () {
      for (final s in [
        'at 10:30:45 ok',
        'a:b',
        'see https://a.example/:+1:/x now',
        '<https://a/:tada:>',
      ]) {
        final parsed = parseMarkdown(s);
        expect(
          identical(
            applyMarkdownXExtensions(parsed, [markdownXEmojiExtension]),
            parsed,
          ),
          isTrue,
          reason: s,
        );
      }
    });

    test('inline code, code blocks and link destinations are excluded', () {
      for (final s in [
        '`:smile:`',
        '```\n:smile:\n```',
        '[x](https://a.example/:smile:)',
      ]) {
        final parsed = parseMarkdown(s);
        expect(
          identical(
            applyMarkdownXExtensions(parsed, [markdownXEmojiExtension]),
            parsed,
          ),
          isTrue,
          reason: s,
        );
      }
    });

    test('link text and emphasis convert, the href does not', () {
      final link =
          _inlines('[go :tada:](https://a.example/:smile:)').single as MdxLink;
      expect(link.href, 'https://a.example/:smile:');
      expect(link.children, [MdxText('go ${md.emojis['tada']}')]);
      final strong = _inlines('**a :tada:**').single as MdxStyled;
      expect(strong.children, [MdxText('a ${md.emojis['tada']}')]);
    });

    test('headings, tables and list items convert', () {
      expect(((_apply('# hi :tada:').first) as MdxHeading).inlines, [
        MdxText('hi ${md.emojis['tada']}'),
      ]);
      final table = _apply('| a |\n|---|\n| :tada: |').first as MdxTable;
      expect(table.rows.single.single, [MdxText(md.emojis['tada']!)]);
    });

    test('the shortcode is converted across a soft break boundary only within text', () {
      final inlines = _inlines('a\n:tada:');
      expect(inlines, [
        MdxText('a'),
        MdxSoftBreak(),
        MdxText(md.emojis['tada']!),
      ]);
    });

    test('math is not touched', () {
      final blocks = applyMarkdownXExtensions(parseMarkdown(r'$a :smile: b$'), [
        markdownXEmojiExtension,
      ]);
      expect(
        (blocks.first as MdxParagraph).inlines.whereType<MdxText>().first.text,
        isNotEmpty,
      );
    });

    test('heading slug drops the emoji like GitHub', () {
      final headings = markdownXHeadings(_apply('# Hi :tada:'));
      expect(headings.single.text, 'Hi ${md.emojis['tada']}');
      expect(headings.single.id, 'hi-');
      expect(markdownXSlug('Party ${md.emojis['tada']} time'), 'party--time');
    });
  });

  group('streaming', () {
    test('every prefix is stable text; only a closed shortcode converts', () {
      const source = 'go :smile: now';
      final parser = IncrementalMarkdownParser();
      for (var i = 1; i <= source.length; i++) {
        final blocks = applyMarkdownXExtensions(
          parser.parse(source.substring(0, i), streaming: true),
          [markdownXEmojiExtension],
        );
        final text = (blocks.first as MdxParagraph).inlines
            .whereType<MdxText>()
            .map((t) => t.text)
            .join();
        final closed = i >= 'go :smile:'.length;
        expect(text.contains(md.emojis['smile']!), closed, reason: '$i');
        if (!closed) expect(text, source.substring(0, i).trimRight());
      }
    });
  });

  group('widget enabling', () {
    final smile = md.emojis['smile']!;

    testWidgets('default (gitHubFlavored / null) leaves the text', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const MarkdownBody(data: 'a :smile:')));
      expect(_hasText(tester, ':smile:'), isTrue);
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: 'a :smile:',
            extensionSet: md.ExtensionSet.gitHubFlavored,
          ),
        ),
      );
      expect(_hasText(tester, ':smile:'), isTrue);
    });

    testWidgets('gitHubWeb converts', (tester) async {
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: 'a :smile:',
            extensionSet: md.ExtensionSet.gitHubWeb,
          ),
        ),
      );
      expect(_hasText(tester, 'a $smile'), isTrue);
      expect(_hasText(tester, ':smile:'), isFalse);
    });

    testWidgets('EmojiSyntax in inlineSyntaxes converts and is not reported', (
      tester,
    ) async {
      final reports = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reports.add;
      try {
        await tester.pumpWidget(
          _app(
            MarkdownBody(data: 'a :smile:', inlineSyntaxes: [md.EmojiSyntax()]),
          ),
        );
      } finally {
        FlutterError.onError = previous;
      }
      expect(reports, isEmpty);
      expect(_hasText(tester, 'a $smile'), isTrue);
    });

    testWidgets('the explicit extension converts, also with selectable', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: 'a :smile:',
            selectable: true,
            extensions: [markdownXEmojiExtension],
          ),
        ),
      );
      expect(_hasText(tester, 'a $smile'), isTrue);
    });

    testWidgets('semantics sees the emoji', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: 'hi :smile:',
            extensions: [markdownXEmojiExtension],
          ),
        ),
      );
      expect(find.bySemanticsLabel(RegExp('hi $smile')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('builders see the emoji as plain text in the md tree', (
      tester,
    ) async {
      final seen = <String>[];
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: 'b :smile:',
            extensionSet: md.ExtensionSet.gitHubWeb,
            builders: {'p': _TextSpy(seen)},
          ),
        ),
      );
      expect(seen, ['b $smile']);
    });

    testWidgets('toggling the extension set re-parses', (tester) async {
      await tester.pumpWidget(_app(const MarkdownBody(data: ':smile:')));
      expect(_hasText(tester, ':smile:'), isTrue);
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: ':smile:',
            extensionSet: md.ExtensionSet.gitHubWeb,
          ),
        ),
      );
      expect(_hasText(tester, smile), isTrue);
      await tester.pumpWidget(_app(const MarkdownBody(data: ':smile:')));
      expect(_hasText(tester, ':smile:'), isTrue);
    });

    testWidgets('streaming prefixes never show a half shortcode as an emoji', (
      tester,
    ) async {
      const source = 'x :tada: y';
      for (var i = 1; i <= source.length; i++) {
        await tester.pumpWidget(
          _app(
            MarkdownBody(
              data: source.substring(0, i),
              streaming: true,
              extensionSet: md.ExtensionSet.gitHubWeb,
            ),
          ),
        );
        expect(
          _hasText(tester, md.emojis['tada']!),
          i >= 'x :tada:'.length,
          reason: '$i',
        );
      }
    });
  });
}

class _TextSpy extends MarkdownElementBuilder {
  _TextSpy(this.seen);
  final List<String> seen;

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    seen.add(text.text);
    return null;
  }
}
