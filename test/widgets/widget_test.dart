import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Finds a [Text] by the string formed by concatenating its spans.
Finder _rich(String text) => find.textContaining(text);

void main() {
  highlightAndBuilderTests();

  testWidgets('shows headings, paragraphs, lists and code blocks', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Markdown(
          data: '# Title\n\nHello **world**\n\n- item\n\n```\ncode\n```',
        ),
      ),
    );

    expect(_rich('Title'), findsOneWidget);
    expect(_rich('Hello world'), findsOneWidget);
    expect(_rich('item'), findsOneWidget);
    expect(_rich('code'), findsOneWidget);
  });

  testWidgets('inline HTML tags are not shown as text', (tester) async {
    await tester.pumpWidget(
      _app(const Markdown(data: 'a <kbd>Ctrl</kbd> <mark>hit</mark><br>b')),
    );

    expect(_rich('Ctrl'), findsOneWidget);
    expect(_rich('hit'), findsOneWidget);
    expect(_rich('<kbd>'), findsNothing);
    expect(_rich('<br>'), findsNothing);
  });

  testWidgets('tapping a link calls onTapLink', (tester) async {
    String? tapped;
    await tester.pumpWidget(
      _app(
        Markdown(
          data: '[link](https://example.com)',
          onTapLink: (text, href, title) => tapped = href,
        ),
      ),
    );

    // Text spans the full width, so tap the left edge where the text is, not the center.
    const insideFirstGlyph = Offset(4, 4);
    await tester.tapAt(tester.getTopLeft(_rich('link')) + insideFirstGlyph);
    expect(tapped, 'https://example.com');

    // Tapping where there is no text does not react.
    tapped = null;
    await tester.tap(_rich('link'));
    expect(tapped, isNull);
  });

  testWidgets('details toggles open and closed on tap', (tester) async {
    await tester.pumpWidget(
      _app(
        const Markdown(
          data: '<details>\n<summary>More</summary>\n\nhidden\n\n</details>',
        ),
      ),
    );

    expect(_rich('More'), findsOneWidget);
    expect(_rich('hidden'), findsNothing);

    await tester.tap(_rich('More'));
    await tester.pump();
    expect(_rich('hidden'), findsOneWidget);

    await tester.tap(_rich('More'));
    await tester.pump();
    expect(_rich('hidden'), findsNothing);
  });

  const detailsA = '<details>\n<summary>A</summary>\n\nbody A\n\n</details>';
  const detailsB = '<details>\n<summary>B</summary>\n\nbody B\n\n</details>';

  testWidgets('MarkdownBody keeps details state with its block after prepend', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const MarkdownBody(data: detailsA, shrinkWrap: false)),
    );
    await tester.tap(_rich('A'));
    await tester.pump();
    expect(_rich('body A'), findsOneWidget);

    await tester.pumpWidget(
      _app(
        const MarkdownBody(data: '$detailsB\n\n$detailsA', shrinkWrap: false),
      ),
    );
    expect(_rich('body A'), findsOneWidget);
    expect(_rich('body B'), findsNothing);
  });

  testWidgets('Markdown maps reordered list children to stable block keys', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const Markdown(data: detailsA)));
    await tester.tap(_rich('A'));
    await tester.pump();

    await tester.pumpWidget(
      _app(const Markdown(data: '$detailsB\n\n$detailsA')),
    );
    expect(_rich('body A'), findsOneWidget);
    expect(_rich('body B'), findsNothing);
  });

  testWidgets('equal details occurrences have independent state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const MarkdownBody(data: '$detailsA\n\n$detailsA')),
    );
    expect(_rich('A'), findsNWidgets(2));
    await tester.tap(_rich('A').first);
    await tester.pump();
    expect(_rich('body A'), findsOneWidget);
  });

  testWidgets(
    'MarkdownBody preserves block state through reorder and removal',
    (tester) async {
      await tester.pumpWidget(
        _app(
          const MarkdownBody(data: '$detailsA\n\n$detailsB', shrinkWrap: false),
        ),
      );
      await tester.tap(_rich('A'));
      await tester.pump();

      await tester.pumpWidget(
        _app(
          const MarkdownBody(data: '$detailsB\n\n$detailsA', shrinkWrap: false),
        ),
      );
      expect(_rich('body A'), findsOneWidget);
      expect(_rich('body B'), findsNothing);

      await tester.pumpWidget(
        _app(const MarkdownBody(data: detailsA, shrinkWrap: false)),
      );
      expect(_rich('body A'), findsOneWidget);
    },
  );

  testWidgets(
    'MarkdownBody keeps duplicate occurrence matching ordered on update',
    (tester) async {
      await tester.pumpWidget(
        _app(const Markdown(data: '$detailsA\n\n$detailsA', shrinkWrap: true)),
      );
      await tester.tap(_rich('A').first);
      await tester.pump();

      // Removing the first equal occurrence deterministically reuses the first
      // previous occurrence for the remaining one.
      await tester.pumpWidget(
        _app(const Markdown(data: detailsA, shrinkWrap: true)),
      );
      expect(_rich('body A'), findsOneWidget);
    },
  );

  testWidgets('Markdown preserves details state through reorder and removal', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const Markdown(data: '$detailsA\n\n$detailsB', shrinkWrap: true)),
    );
    await tester.tap(_rich('A'));
    await tester.pump();

    await tester.pumpWidget(
      _app(const Markdown(data: '$detailsB\n\n$detailsA', shrinkWrap: true)),
    );
    expect(_rich('body A'), findsOneWidget);
    expect(_rich('body B'), findsNothing);

    await tester.pumpWidget(
      _app(const Markdown(data: detailsA, shrinkWrap: true)),
    );
    expect(_rich('body A'), findsOneWidget);
  });

  testWidgets('Markdown duplicate occurrence matching is ordered on update', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const Markdown(data: '$detailsA\n\n$detailsA', shrinkWrap: true)),
    );
    await tester.tap(_rich('A').first);
    await tester.pump();

    await tester.pumpWidget(
      _app(const Markdown(data: detailsA, shrinkWrap: true)),
    );
    expect(_rich('body A'), findsOneWidget);
  });

  testWidgets('shows table cells', (tester) async {
    await tester.pumpWidget(
      _app(const Markdown(data: '| h1 | h2 |\n|---|---|\n| c1 | c2 |')),
    );

    for (final text in ['h1', 'h2', 'c1', 'c2']) {
      expect(_rich(text), findsOneWidget);
    }
  });

  testWidgets('blocks that did not change are not rebuilt when data changes', (
    tester,
  ) async {
    const first = 'para one\n\npara two';
    await tester.pumpWidget(_app(const Markdown(data: first)));
    final before = tester.widget(_rich('para one'));

    // Append to the end (simulating streaming).
    await tester.pumpWidget(_app(const Markdown(data: '$first more\n\nnew')));

    expect(_rich('para two more'), findsOneWidget);
    expect(_rich('new'), findsOneWidget);
    // If not rebuilt, the child Widget instance stays the same.
    expect(identical(tester.widget(_rich('para one')), before), isTrue);
  });

  testWidgets('a theme change also redraws cached blocks', (tester) async {
    Widget build(Brightness brightness) => MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: const Scaffold(body: Markdown(data: 'text')),
    );

    await tester.pumpWidget(build(Brightness.light));
    final light = tester.widget<Text>(_rich('text')).style?.color;

    await tester.pumpWidget(build(Brightness.dark));
    await tester.pumpAndSettle();
    final dark = tester.widget<Text>(_rich('text')).style?.color;

    expect(light, isNotNull);
    expect(dark, isNot(light));
  });

  testWidgets('MarkdownBody can be placed in a parent that does not scroll', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const SingleChildScrollView(
          child: Column(
            children: [
              MarkdownBody(data: 'first'),
              MarkdownBody(data: 'second'),
            ],
          ),
        ),
      ),
    );

    expect(_rich('first'), findsOneWidget);
    expect(_rich('second'), findsOneWidget);
  });
}

// ---------------------------------------------------------------------------
// highlight and builder
// ---------------------------------------------------------------------------

/// Finds the color applied to the leaf span holding [text] from the [Text] spans.
Color? _spanColor(Text widget, String text) =>
    _findColor(widget.textSpan!, text, null);

Color? _findColor(InlineSpan span, String text, Color? inherited) {
  if (span is! TextSpan) return null;
  final color = span.style?.color ?? inherited;
  if (span.text == text) return color;
  for (final child in span.children ?? const <InlineSpan>[]) {
    final found = _findColor(child, text, color);
    if (found != null) return found;
  }
  return null;
}

/// Colors every all-caps word as a keyword with [color].
class _UpperCaseHighlighter extends SyntaxHighlighter {
  _UpperCaseHighlighter(this.color);

  final Color color;

  @override
  TextSpan format(String source) => TextSpan(
    children: [
      for (final word in source.split(' '))
        TextSpan(
          text: word,
          style: word == word.toUpperCase() ? TextStyle(color: color) : null,
        ),
    ],
  );
}

InlineSpan? _iconForImage(
  BuildContext context,
  MdxInline inline,
  TextStyle style,
  InlineSpan Function() buildDefault,
) => inline is MdxImage && inline.src == 'icon'
    ? const WidgetSpan(child: Icon(Icons.star))
    : null;

Widget? _customCode(
  BuildContext context,
  MdxBlock block,
  Widget Function() buildDefault,
) => block is MdxCodeBlock && block.language == 'custom'
    ? Text('custom:${block.code}')
    : null;

/// The theme with localized text sizes, as `MaterialApp` provides.
ThemeData _localized(ThemeData theme) =>
    ThemeData.localize(theme, Typography.englishLike2021);

void highlightAndBuilderTests() {
  testWidgets('keywords in a code block get colored', (tester) async {
    final style = MarkdownStyleSheet.fromTheme(_localized(ThemeData()));
    await tester.pumpWidget(
      _app(Markdown(data: '```dart\nfinal a = 1;\n```', styleSheet: style)),
    );

    final code = tester.widget<Text>(_rich('final a'));
    expect(_spanColor(code, 'final'), style.codeSyntax!.keyword);
    expect(_spanColor(code, '1'), style.codeSyntax!.number);
  });

  testWidgets(
    'a code block with an unsupported language is shown without color',
    (tester) async {
      await tester.pumpWidget(_app(const Markdown(data: '```\nfinal a\n```')));
      expect(tester.widget<Text>(_rich('final a')).data, 'final a');
    },
  );

  testWidgets('the highlighter can be replaced', (tester) async {
    final style = MarkdownStyleSheet.fromTheme(_localized(ThemeData()));
    await tester.pumpWidget(
      _app(
        Markdown(
          data: '```whatever\nfoo BAR\n```',
          styleSheet: style,
          syntaxHighlighter: _UpperCaseHighlighter(style.codeSyntax!.keyword),
        ),
      ),
    );

    final code = tester.widget<Text>(_rich('foo'));
    expect(_spanColor(code, 'BAR'), style.codeSyntax!.keyword);
  });

  testWidgets('inlineBuilder can replace images', (tester) async {
    await tester.pumpWidget(
      _app(
        const Markdown(data: 'a ![x](icon) b', inlineBuilder: _iconForImage),
      ),
    );
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets(
    'when blockBuilder returns null, the default rendering is restored',
    (tester) async {
      await tester.pumpWidget(
        _app(
          const Markdown(
            data: '```custom\nA\n```\n\n```\nB\n```',
            blockBuilder: _customCode,
          ),
        ),
      );
      expect(find.text('custom:A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    },
  );

  testWidgets('reflects HTML align and inline style', (tester) async {
    await tester.pumpWidget(
      _app(
        const Markdown(
          data: '<p align="center">mid <span style="color:#f00">red</span></p>',
        ),
      ),
    );
    final text = tester.widget<Text>(_rich('mid red'));
    expect(text.textAlign, TextAlign.center);
    expect(_spanColor(text, 'red'), const Color(0xFFFF0000));
  });
}
