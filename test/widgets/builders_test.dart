import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget? _headingBuilder(
  BuildContext context,
  MdxBlock block,
  Widget Function() buildDefault,
) {
  if (block is! MdxHeading) return null;
  return Text('H${block.level}!');
}

Widget? _wrapBuilder(
  BuildContext context,
  MdxBlock block,
  Widget Function() buildDefault,
) {
  if (block is! MdxParagraph) return null;
  return Container(key: const Key('wrapped'), child: buildDefault());
}

InlineSpan? _inlineBuilder(
  BuildContext context,
  MdxInline inline,
  TextStyle style,
  InlineSpan Function() buildDefault,
) {
  if (inline is MdxCustomInline && inline.type == 'mention') {
    return TextSpan(
      text: '<${inline.attributes['name']}>',
      style: const TextStyle(color: Color(0xFF123456)),
    );
  }
  if (inline is MdxLink) {
    return WidgetSpan(child: Text('link:${inline.href}'));
  }
  return null;
}

final _mention = MarkdownXExtension(
  inlineSyntaxes: [
    MarkdownXInlineSyntax(
      pattern: RegExp(r'@(\w+)'),
      build: (m) => MdxCustomInline(
        'mention',
        attributes: {'name': m[1]!},
        children: [MdxText(m[0]!)],
      ),
    ),
  ],
);

void main() {
  group('blockBuilder', () {
    testWidgets('replaces a top-level block', (tester) async {
      await tester.pumpWidget(
        _app(
          const Markdown(data: '# T\n\npara', blockBuilder: _headingBuilder),
        ),
      );
      expect(find.text('H1!'), findsOneWidget);
      expect(find.textContaining('para'), findsOneWidget);
    });

    testWidgets('headings inside blockquote are also replaced', (tester) async {
      await tester.pumpWidget(
        _app(
          const Markdown(
            data: '> ## Q\n>\n> body',
            blockBuilder: _headingBuilder,
          ),
        ),
      );
      expect(find.text('H2!'), findsOneWidget);
      expect(find.text('Q'), findsNothing);
      expect(find.textContaining('body'), findsOneWidget);
    });

    testWidgets(
      'replaced inside list item and details, and in MarkdownBody too',
      (tester) async {
        await tester.pumpWidget(
          _app(
            const MarkdownBody(
              data: '- # in list\n\n<details><summary>s</summary>\n\n# in details\n\n</details>',
              blockBuilder: _headingBuilder,
            ),
          ),
        );
        expect(find.text('H1!'), findsOneWidget);
        await tester.tap(find.textContaining('s').first);
        await tester.pump();
        expect(find.text('H1!'), findsNWidgets(2));
      },
    );

    testWidgets('the whole table can be replaced', (tester) async {
      await tester.pumpWidget(
        _app(
          Markdown(
            data: '| a |\n|---|\n| b |',
            blockBuilder: (context, block, buildDefault) =>
                block is MdxTable ? const Text('TABLE') : null,
          ),
        ),
      );
      expect(find.text('TABLE'), findsOneWidget);
      expect(find.byType(Table), findsNothing);
    });

    testWidgets('returning null falls back to the default rendering', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const Markdown(data: 'plain', blockBuilder: _headingBuilder)),
      );
      expect(find.textContaining('plain'), findsOneWidget);
    });

    testWidgets('buildDefault can wrap the default Widget', (tester) async {
      await tester.pumpWidget(
        _app(const Markdown(data: 'plain', blockBuilder: _wrapBuilder)),
      );
      expect(find.byKey(const Key('wrapped')), findsOneWidget);
      expect(find.textContaining('plain'), findsOneWidget);
    });

    testWidgets('the default Widget is unused unless buildDefault is called', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Markdown(
            data: '# T',
            blockBuilder: (context, block, buildDefault) =>
                const SizedBox(key: Key('x'), height: 10),
          ),
        ),
      );
      expect(find.byKey(const Key('x')), findsOneWidget);
      expect(find.text('T'), findsNothing);
    });

    testWidgets('a code block can be replaced with blockBuilder', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Markdown(
            data: '```\nA\n```',
            blockBuilder: (c, b, d) =>
                b is MdxCodeBlock ? Text('cb:${b.code.trim()}') : null,
          ),
        ),
      );
      expect(find.text('cb:A'), findsOneWidget);
    });

    testWidgets('redraws when the blockBuilder instance changes', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const Markdown(data: '# T', blockBuilder: _headingBuilder)),
      );
      expect(find.text('H1!'), findsOneWidget);
      await tester.pumpWidget(_app(const Markdown(data: '# T')));
      expect(find.text('H1!'), findsNothing);
      expect(find.text('T'), findsOneWidget);
    });
  });

  group('inlineBuilder and extensions', () {
    testWidgets('renders a custom inline with the builder', (tester) async {
      await tester.pumpWidget(
        _app(
          Markdown(
            data: 'hi @alice!',
            extensions: [_mention],
            inlineBuilder: _inlineBuilder,
          ),
        ),
      );
      expect(find.textContaining('hi <alice>!'), findsOneWidget);
    });

    testWidgets(
      'without a builder, a custom inline renders its children as plain text',
      (tester) async {
        await tester.pumpWidget(
          _app(Markdown(data: 'hi @alice!', extensions: [_mention])),
        );
        expect(find.textContaining('hi @alice!'), findsOneWidget);
      },
    );

    testWidgets('a link can be replaced with a WidgetSpan', (tester) async {
      await tester.pumpWidget(
        _app(
          const Markdown(
            data: 'a [x](http://u) b',
            inlineBuilder: _inlineBuilder,
          ),
        ),
      );
      expect(find.text('link:http://u'), findsOneWidget);
    });

    testWidgets(
      'the builder receives the computed style and the default span',
      (tester) async {
        TextStyle? seen;
        InlineSpan? seenDefault;
        await tester.pumpWidget(
          _app(
            Markdown(
              data: '**bold**',
              inlineBuilder: (context, inline, style, buildDefault) {
                if (inline is MdxStyled) {
                  seen = style;
                  seenDefault = buildDefault();
                }
                return null;
              },
            ),
          ),
        );
        expect(seen?.fontSize, isNotNull);
        expect(seenDefault, isA<TextSpan>());
        expect(find.textContaining('bold'), findsOneWidget);
      },
    );

    testWidgets('text itself can be replaced, and null restores the default', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Markdown(
            data: 'abc',
            inlineBuilder: (context, inline, style, d) => inline is MdxText
                ? TextSpan(text: inline.text.toUpperCase())
                : null,
          ),
        ),
      );
      expect(find.textContaining('ABC'), findsOneWidget);
    });

    testWidgets('inlines in table cells and headings are also replaced', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Markdown(
            data: '# @h\n\n| c |\n|---|\n| @t |',
            extensions: [_mention],
            inlineBuilder: _inlineBuilder,
          ),
        ),
      );
      expect(find.text('<h>'), findsOneWidget);
      expect(find.text('<t>'), findsOneWidget);
    });

    testWidgets('an image can be replaced via inlineBuilder', (tester) async {
      await tester.pumpWidget(
        _app(
          Markdown(
            data: '![x](a)',
            inlineBuilder: (c, inline, style, d) => inline is MdxImage
                ? const WidgetSpan(child: Icon(Icons.star))
                : null,
          ),
        ),
      );
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('changing extensions re-parses even with the same data', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(Markdown(data: 'hi @alice', inlineBuilder: _inlineBuilder)),
      );
      expect(find.textContaining('<alice>'), findsNothing);

      await tester.pumpWidget(
        _app(
          Markdown(
            data: 'hi @alice',
            inlineBuilder: _inlineBuilder,
            extensions: [_mention],
          ),
        ),
      );
      expect(find.textContaining('hi <alice>'), findsOneWidget);

      await tester.pumpWidget(
        _app(Markdown(data: 'hi @alice', inlineBuilder: _inlineBuilder)),
      );
      expect(find.textContaining('<alice>'), findsNothing);
      expect(find.textContaining('hi @alice'), findsOneWidget);
    });

    testWidgets('extensions also take effect in MarkdownBody', (tester) async {
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '@bob',
            extensions: [_mention],
            inlineBuilder: _inlineBuilder,
          ),
        ),
      );
      expect(find.text('<bob>'), findsOneWidget);
    });

    testWidgets(
      'a custom block renders with blockBuilder, or its content plainly if absent',
      (tester) async {
        final ext = MarkdownXExtension(
          transformBlock: (b) => b is MdxParagraph
              ? MdxCustomBlock('note', inlines: b.inlines)
              : null,
        );
        await tester.pumpWidget(
          _app(Markdown(data: 'body', extensions: [ext])),
        );
        expect(find.textContaining('body'), findsOneWidget);

        await tester.pumpWidget(
          _app(
            Markdown(
              data: 'body',
              extensions: [ext],
              blockBuilder: (c, b, d) =>
                  b is MdxCustomBlock ? Text('custom:${b.type}') : null,
            ),
          ),
        );
        expect(find.text('custom:note'), findsOneWidget);
      },
    );
  });
}
