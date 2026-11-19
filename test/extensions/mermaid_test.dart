import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_markdown_x/mermaid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';

import '../support/prefixes.dart';
import '../support/selection_harness.dart';

const _diagram = 'graph TD\n  A-->B';
const _fenced = '```mermaid\n$_diagram\n```';

List<MdxBlock> _ir(
  String source, {
  bool streaming = false,
  MarkdownXExtension? extension,
}) => IncrementalMarkdownParser().parse(
  source,
  extensions: [extension ?? markdownXMermaidExtension],
  streaming: streaming,
);

MdxCustomBlock _custom(MdxBlock block) {
  expect(block, isA<MdxCustomBlock>());
  return block as MdxCustomBlock;
}

class _CodeProbe extends MarkdownElementBuilder {
  final seen = <String>[];

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    seen.add('${element.attributes['class']}:${element.textContent.trim()}');
    return Text('CODE[${element.textContent.trim()}]');
  }
}

void main() {
  group('transform', () {
    test(
      'a mermaid fence becomes a custom block with the code block inside',
      () {
        final blocks = _ir(_fenced);
        expect(blocks, hasLength(1));
        final block = _custom(blocks.single);
        expect(block.type, markdownXMermaidType);
        expect(block.type, 'mermaid');
        expect(block.attributes['source'], _diagram);
        expect(block.attributes.containsKey('pending'), isFalse);
        expect(block.blocks, [MdxCodeBlock(_diagram, language: 'mermaid')]);
      },
    );

    test('the language matches case-insensitively and with ~~~ fences', () {
      for (final open in ['```Mermaid', '```MERMAID', '~~~mermaid']) {
        final close = open.startsWith('~') ? '~~~' : '```';
        final block = _custom(_ir('$open\n$_diagram\n$close').single);
        expect(block.type, 'mermaid', reason: open);
        expect(block.attributes['source'], _diagram, reason: open);
      }
    });

    test('an info string after the language is kept on the fallback', () {
      final block = _custom(_ir('```mermaid title\n$_diagram\n```').single);
      expect(block.attributes['source'], _diagram);
      final code = block.blocks.single as MdxCodeBlock;
      expect(code.language, 'mermaid');
      expect(code.info, 'title');
    });

    test('other code blocks are untouched', () {
      for (final source in [
        '```dart\nvar x;\n```',
        '```mermaidx\nA\n```',
        '```\nA\n```',
        '    indented\n',
        '```mer\nA\n```',
      ]) {
        final plain = IncrementalMarkdownParser().parse(source);
        expect(_ir(source), plain, reason: source);
      }
    });

    test('works inside a blockquote and a list', () {
      final quote = _ir('> ```mermaid\n> graph TD\n>   A-->B\n> ```').single;
      expect(quote, isA<MdxBlockquote>());
      expect((quote as MdxBlockquote).blocks.single, isA<MdxCustomBlock>());
      final list = _ir('- item\n\n  ```mermaid\n  graph TD\n    A-->B\n  ```')
          .single;
      final items = (list as MdxList).items.single.blocks;
      expect(items.whereType<MdxCustomBlock>(), hasLength(1));
    });

    test('an empty diagram gives an empty source', () {
      final block = _custom(_ir('```mermaid\n```').single);
      expect(block.attributes['source'], '');
    });

    test(
      'Windows line endings are normalized by the parser, not kept in source',
      () {
        final block = _custom(_ir('```mermaid\r\nA-->B\r\n```').single);
        expect(block.attributes['source'], isNot(contains('\r')));
      },
    );
  });

  group('streaming IR', () {
    test('an open fence at the tail is marked pending', () {
      final block = _custom(
        _ir('```mermaid\ngraph TD\n  A-->', streaming: true).single,
      );
      expect(block.attributes['pending'], 'true');
      expect(block.attributes['source'], 'graph TD\n  A-->');
      final code = block.blocks.single as MdxCodeBlock;
      expect(code.language, 'mermaid');
      expect(code.info, isNull);
    });

    test('the pending mark does not leak into the info string', () {
      final block = _custom(
        _ir('```mermaid title\nA-->B', streaming: true).single,
      );
      expect(block.attributes['pending'], 'true');
      expect((block.blocks.single as MdxCodeBlock).info, 'title');
    });

    test('a closed fence is not pending, even with streaming on', () {
      final block = _custom(_ir(_fenced, streaming: true).single);
      expect(block.attributes.containsKey('pending'), isFalse);
    });

    test('an unclosed fence without streaming is not pending', () {
      final block = _custom(_ir('```mermaid\nA-->B').single);
      expect(block.attributes.containsKey('pending'), isFalse);
    });

    test('only the fence that is still open at the tail is pending', () {
      final blocks = _ir(
        '$_fenced\n\ntext\n\n```mermaid\nA-->',
        streaming: true,
      );
      final customs = blocks.whereType<MdxCustomBlock>().toList();
      expect(customs, hasLength(2));
      expect(customs[0].attributes.containsKey('pending'), isFalse);
      expect(customs[1].attributes['pending'], 'true');
    });

    test('a non-mermaid open fence is not touched', () {
      final blocks = _ir('```dart\nvar x', streaming: true);
      expect(blocks.single, isA<MdxCodeBlock>());
    });

    test(
      'the opening line alone (no newline yet) shows a plain code block',
      () {
        final blocks = _ir('```mermaid', streaming: true);
        expect(blocks.single, isA<MdxCodeBlock>());
      },
    );

    test('whileStreaming extension never marks pending', () {
      final ext = MarkdownXMermaid(whileStreaming: true).extension;
      final block = _custom(
        _ir('```mermaid\nA-->', streaming: true, extension: ext).single,
      );
      expect(block.attributes.containsKey('pending'), isFalse);
    });

    test('every prefix of a document parses without error', () {
      const doc =
          'Intro\n\n$_fenced\n\nafter *text* and `x`\n\n'
          '- a\n\n  ```mermaid\n  A-->B\n  ```\n';
      for (final n in prefixEnds(doc)) {
        _ir(doc.substring(0, n), streaming: true);
      }
    });
  });

  group('MarkdownXMermaid', () {
    test('the shared extension is reused unless whileStreaming differs', () {
      expect(MarkdownXMermaid().extension, same(markdownXMermaidExtension));
      expect(
        MarkdownXMermaid(whileStreaming: true).extension,
        same(MarkdownXMermaid(whileStreaming: true).extension),
      );
      expect(
        MarkdownXMermaid(whileStreaming: true).extension,
        isNot(same(markdownXMermaidExtension)),
      );
    });
  });

  group('widget', () {
    Widget app(
      String data, {
      MarkdownXMermaid? mermaid,
      bool streaming = false,
      bool useBlockBuilder = true,
      Map<String, MarkdownElementBuilder> builders = const {},
      MarkdownStyleSheet? styleSheet,
      bool selectable = false,
      bool extension = true,
      Widget Function(String data, MarkdownXMermaid m)? custom,
    }) {
      final m = mermaid ?? MarkdownXMermaid();
      final body =
          custom?.call(data, m) ??
          MarkdownBody(
            data: data,
            streaming: streaming,
            extensions: extension ? [m.extension] : const [],
            blockBuilder: useBlockBuilder ? m.blockBuilder : null,
            builders: builders,
            styleSheet: styleSheet,
          );
      return MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              child: selectable ? SelectionArea(child: body) : body,
            ),
          ),
        ),
      );
    }

    MarkdownXMermaid fake(List<String> calls) => MarkdownXMermaid(
      builder: (context, source) {
        calls.add(source);
        return Container(
          key: const ValueKey('diagram'),
          width: 100,
          height: 50,
          color: Colors.blue,
        );
      },
    );

    testWidgets('the builder receives the source and draws the diagram', (
      tester,
    ) async {
      final calls = <String>[];
      await tester.pumpWidget(
        app('before\n\n$_fenced\n\nafter', mermaid: fake(calls)),
      );
      expect(calls, [_diagram]);
      expect(find.byKey(const ValueKey('diagram')), findsOneWidget);
      // The code block is replaced by the diagram.
      expect(find.textContaining('A-->B', findRichText: true), findsNothing);
      expect(find.text('before'), findsOneWidget);
      expect(find.text('after'), findsOneWidget);
    });

    testWidgets('without a builder the block looks like a normal code block', (
      tester,
    ) async {
      final style = MarkdownStyleSheet(
        codeBlockOptions: const MarkdownXCodeBlockOptions(
          showLanguage: true,
          showCopyButton: true,
        ),
      );
      Future<(Size, List<String>)> measure(Widget w) async {
        await tester.pumpWidget(w);
        final size = tester.getSize(find.byType(MarkdownBody));
        final texts = [
          for (final t in tester.widgetList<RichText>(find.byType(RichText)))
            t.text.toPlainText(),
        ];
        final icons = find.byType(Icon).evaluate().length;
        return (size, [...texts, 'icons:$icons']);
      }

      const doc = 'a\n\n```mermaid\n$_diagram\n```\n\nb';
      final plain = await measure(
        app(doc, extension: false, useBlockBuilder: false, styleSheet: style),
      );
      for (final withBuilderApi in [false, true]) {
        final mine = await measure(
          app(
            doc,
            mermaid: MarkdownXMermaid(),
            useBlockBuilder: withBuilderApi,
            styleSheet: style,
          ),
        );
        expect(mine.$1, plain.$1, reason: 'blockBuilder=$withBuilderApi');
        expect(mine.$2, plain.$2, reason: 'blockBuilder=$withBuilderApi');
      }
      expect(plain.$2, contains('mermaid'));
    });

    testWidgets('a fallback code block still copies its source', (
      tester,
    ) async {
      final probe = ClipboardProbe();
      mockClipboard(tester, probe);
      await tester.pumpWidget(app(_fenced, selectable: true));
      await tester.pumpAndSettle();
      final copied = await selectAllAndCopy(
        tester,
        probe,
        find.descendant(
          of: find.byType(SelectionArea),
          matching: find.byType(RichText),
        ),
      );
      expect(copied?.trim(), _diagram);
    });

    testWidgets('a rendered diagram copies the mermaid source', (tester) async {
      final probe = ClipboardProbe();
      mockClipboard(tester, probe);
      await tester.pumpWidget(
        app('before\n\n$_fenced\n\nafter', mermaid: fake([]), selectable: true),
      );
      await tester.pumpAndSettle();
      final copied = await selectAllAndCopy(
        tester,
        probe,
        find.descendant(
          of: find.byType(SelectionArea),
          matching: find.byType(RichText),
        ),
      );
      expect(copied, contains(_diagram));
      expect(copied, contains('before'));
      expect(copied, contains('after'));
    });

    testWidgets(
      'no selection widget is created for a diagram outside SelectionArea',
      (tester) async {
        await tester.pumpWidget(app(_fenced, mermaid: fake([])));
        expect(find.byType(SelectionContainer), findsNothing);
      },
    );

    testWidgets('the diagram has a semantics label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(_fenced, mermaid: fake([])));
      expect(find.bySemanticsLabel('Mermaid diagram'), findsOneWidget);
      handle.dispose();
    });

    group('streaming', () {
      testWidgets(
        'the builder is not called until the fence closes, then once',
        (tester) async {
          final calls = <String>[];
          final m = fake(calls);
          const doc = '$_fenced\n\ntail';
          var sawDiagram = false;
          var switched = -1;
          for (var n = 1; n <= doc.length; n++) {
            await tester.pumpWidget(
              app(doc.substring(0, n), mermaid: m, streaming: true),
            );
            final shown = find
                .byKey(const ValueKey('diagram'))
                .evaluate()
                .isNotEmpty;
            if (shown && !sawDiagram) {
              sawDiagram = true;
              switched = n;
            }
            if (!sawDiagram) expect(calls, isEmpty, reason: 'n=$n');
            if (sawDiagram) expect(shown, isTrue, reason: 'n=$n');
          }
          expect(sawDiagram, isTrue);
          // Never before the closing fence has been fully written.
          expect(switched, greaterThanOrEqualTo(_fenced.length));
          expect(calls, [_diagram]);
        },
      );

      testWidgets('while open, the code is shown without the pending mark', (
        tester,
      ) async {
        final calls = <String>[];
        await tester.pumpWidget(
          app(
            '```mermaid\ngraph TD\n  A-->',
            mermaid: fake(calls),
            streaming: true,
          ),
        );
        expect(calls, isEmpty);
        expect(
          find.textContaining('graph TD', findRichText: true),
          findsOneWidget,
        );
        expect(find.textContaining('', findRichText: true), findsNothing);
      });

      testWidgets(
        'appending after the diagram does not call the builder again',
        (tester) async {
          final calls = <String>[];
          final m = fake(calls);
          var doc = '$_fenced\n\n';
          await tester.pumpWidget(app(doc, mermaid: m, streaming: true));
          expect(calls, hasLength(1));
          for (var i = 0; i < 12; i++) {
            doc += i.isEven ? 'word$i ' : 'more *text* $i\n\n';
            await tester.pumpWidget(app(doc, mermaid: m, streaming: true));
          }
          expect(calls, hasLength(1));
        },
      );

      testWidgets('whileStreaming calls the builder for partial sources', (
        tester,
      ) async {
        final calls = <String>[];
        final m = MarkdownXMermaid(
          whileStreaming: true,
          builder: (context, source) {
            calls.add(source);
            return const SizedBox(key: ValueKey('diagram'));
          },
        );
        await tester.pumpWidget(
          app('```mermaid\ngraph TD\n  A-->', mermaid: m, streaming: true),
        );
        expect(calls, ['graph TD\n  A-->']);
      });

      testWidgets('closing the fence with streaming off also renders', (
        tester,
      ) async {
        final calls = <String>[];
        final m = fake(calls);
        await tester.pumpWidget(
          app('```mermaid\nA-->B', mermaid: m, streaming: true),
        );
        expect(calls, isEmpty);
        await tester.pumpWidget(app('```mermaid\nA-->B', mermaid: m));
        expect(calls, ['A-->B']);
      });
    });

    group('builder errors', () {
      testWidgets(
        'a throwing builder falls back to the code block, reported once',
        (tester) async {
          final reports = <FlutterErrorDetails>[];
          final previous = FlutterError.onError;
          FlutterError.onError = reports.add;
          addTearDown(() => FlutterError.onError = previous);
          final m = MarkdownXMermaid(
            builder: (context, source) => throw StateError('boom'),
          );
          await tester.pumpWidget(app('x\n\n$_fenced', mermaid: m));
          expect(
            find.textContaining('A-->B', findRichText: true),
            findsOneWidget,
          );
          expect(find.text('x'), findsOneWidget);
          expect(reports, hasLength(1));
          expect(reports.single.exception, isA<StateError>());
          expect(reports.single.library, 'flutter_markdown_x');
          // Rebuilding does not report again.
          await tester.pumpWidget(app('x\n\n$_fenced', mermaid: m));
          await tester.pump();
          await tester.pumpWidget(app('x y\n\n$_fenced', mermaid: m));
          expect(reports, hasLength(1));
          expect(tester.takeException(), isNull);
        },
      );
    });

    group('flutter_markdown compat', () {
      testWidgets(
        'without the extension builders[code] sees language-mermaid',
        (tester) async {
          final probe = _CodeProbe();
          await tester.pumpWidget(
            app(
              _fenced,
              extension: false,
              useBlockBuilder: false,
              builders: {'code': probe},
            ),
          );
          expect(probe.seen, ['language-mermaid:$_diagram']);
          expect(find.text('CODE[$_diagram]'), findsOneWidget);
        },
      );

      testWidgets(
        'with the extension and no builder, builders[code] still applies',
        (tester) async {
          final probe = _CodeProbe();
          await tester.pumpWidget(app(_fenced, builders: {'code': probe}));
          expect(probe.seen, ['language-mermaid:$_diagram']);
          expect(find.text('CODE[$_diagram]'), findsOneWidget);
        },
      );

      testWidgets(
        'the mermaid builder wins for mermaid blocks, builders[code] gets the rest',
        (tester) async {
          final probe = _CodeProbe();
          final calls = <String>[];
          await tester.pumpWidget(
            app(
              '$_fenced\n\n```dart\nvar x;\n```',
              mermaid: fake(calls),
              builders: {'code': probe},
            ),
          );
          expect(calls, [_diagram]);
          expect(find.byKey(const ValueKey('diagram')), findsOneWidget);
          expect(find.text('CODE[$_diagram]'), findsNothing);
          expect(find.text('CODE[var x;]'), findsOneWidget);
          // builders[code] may still be run for the mermaid block, but its widget is discarded.
          expect(probe.seen, contains('language-dart:var x;'));
        },
      );

      testWidgets(
        'a user blockBuilder composed after the mermaid one still runs for other blocks',
        (tester) async {
          final calls = <String>[];
          final m = fake(calls);
          await tester.pumpWidget(
            app(
              '$_fenced\n\n# Title',
              mermaid: m,
              custom: (data, m) => MarkdownBody(
                data: data,
                extensions: [m.extension],
                blockBuilder: (context, block, buildDefault) =>
                    m.blockBuilder(context, block, buildDefault) ??
                    (block is MdxHeading ? const Text('H!') : null),
              ),
            ),
          );
          expect(find.byKey(const ValueKey('diagram')), findsOneWidget);
          expect(find.text('H!'), findsOneWidget);
        },
      );
    });

    group('widgets', () {
      testWidgets('Markdown', (tester) async {
        final calls = <String>[];
        await tester.pumpWidget(
          app(
            _fenced,
            custom: (data, m) => Markdown(
              data: data,
              extensions: [m.extension],
              blockBuilder: m.blockBuilder,
            ),
            mermaid: fake(calls),
          ),
        );
        expect(find.byKey(const ValueKey('diagram')), findsOneWidget);
      });

      testWidgets('SliverMarkdown', (tester) async {
        final calls = <String>[];
        final m = fake(calls);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  SliverMarkdown(
                    data: 'a\n\n$_fenced',
                    extensions: [m.extension],
                    blockBuilder: m.blockBuilder,
                  ),
                ],
              ),
            ),
          ),
        );
        expect(find.byKey(const ValueKey('diagram')), findsOneWidget);
        expect(calls, [_diagram]);
      });

      testWidgets('MarkdownBody', (tester) async {
        final calls = <String>[];
        await tester.pumpWidget(app(_fenced, mermaid: fake(calls)));
        expect(find.byKey(const ValueKey('diagram')), findsOneWidget);
      });
    });
  });
}
