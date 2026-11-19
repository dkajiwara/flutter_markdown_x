import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _citations = markdownXCitationExtension();

List<MdxBlock> _apply(String source, [MarkdownXExtension? ext]) =>
    applyMarkdownXExtensions(parseMarkdown(source), [ext ?? _citations]);

MdxInline _cite(String ids, [String? raw]) => MdxCustomInline(
  markdownXCitationType,
  attributes: {'id': ids.split(',').first, 'ids': ids},
  children: [MdxText(raw ?? '[$ids]')],
);

List<MdxInline> _inlines(List<MdxBlock> blocks) =>
    (blocks.first as MdxParagraph).inlines;

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('extension', () {
    test('[1] and [1, 2] become citations', () {
      expect(_inlines(_apply('a [1] b [1, 2] c')), [
        MdxText('a '),
        _cite('1'),
        MdxText(' b '),
        _cite('1,2', '[1, 2]'),
        MdxText(' c'),
      ]);
    });

    test('【1†source】 also becomes a citation', () {
      final inlines = _inlines(_apply('x【3†source】y'));
      expect(inlines[1], isA<MdxCustomInline>());
      final cite = inlines[1] as MdxCustomInline;
      expect(cite.attributes['id'], '3');
      expect(cite.attributes['ids'], '3');
    });

    test('non-numeric [text] and [a1] stay as text', () {
      final parsed = parseMarkdown('[abc] [a1] [] [1a]');
      expect(
        identical(applyMarkdownXExtensions(parsed, [_citations]), parsed),
        isTrue,
      );
    });

    test('inside code spans, code blocks and links is excluded', () {
      for (final source in ['`[1]`', '```\n[1]\n```', '[see [1]](https://a)']) {
        final parsed = parseMarkdown(source);
        expect(
          identical(applyMarkdownXExtensions(parsed, [_citations]), parsed),
          isTrue,
          reason: source,
        );
      }
    });

    test('[1] resolved as a reference link stays a link', () {
      final blocks = _apply('see [1]\n\n[1]: https://a.example');
      final inlines = _inlines(blocks);
      expect(inlines.whereType<MdxLink>(), hasLength(1));
      expect(inlines.whereType<MdxCustomInline>(), isEmpty);
    });

    test('becomes a citation inside headings and emphasis', () {
      final blocks = _apply('**bold [2]**');
      final strong = _inlines(blocks).single as MdxStyled;
      expect(
        strong.children.whereType<MdxCustomInline>().single.attributes['id'],
        '2',
      );
    });

    test('pattern can be replaced (group 1 is the id)', () {
      final ext = markdownXCitationExtension(pattern: RegExp(r'\(ref:(\w+)\)'));
      final cite = _inlines(_apply('a (ref:x9) b', ext))[1] as MdxCustomInline;
      expect(cite.attributes['id'], 'x9');
    });

    test('the default extension returns the same instance (for caching)', () {
      expect(identical(markdownXCitationExtension(), _citations), isTrue);
    });
  });

  group('streaming', () {
    test('a partial citation is hidden and stays as text once complete (becomes a chip)', () {
      for (final s in [
        'see [1',
        'see [12',
        'see [1,',
        'see [1, 2',
        'see 【1†sou',
        'see 【',
      ]) {
        final out = markdownXRepairStreamingTail(s);
        expect(out, isNot(contains('[')), reason: s);
        expect(out, isNot(contains('【')), reason: s);
        expect(out, isNot(contains('1')), reason: s);
      }
      expect(markdownXRepairStreamingTail('see [1]'), 'see [1]');
    });
  });

  group('widget', () {
    testWidgets(
      'renders a chip; semantics is Citation N; tap invokes the callback',
      (tester) async {
        final handle = tester.ensureSemantics();
        final tapped = <String>[];
        await tester.pumpWidget(
          _app(
            MarkdownBody(
              data: 'fact [1] and [2, 3].',
              extensions: [_citations],
              onTapCitation: tapped.add,
            ),
          ),
        );
        expect(find.text('1'), findsOneWidget);
        expect(find.text('[1]'), findsNothing);
        expect(find.bySemanticsLabel('Citation 1'), findsOneWidget);
        expect(find.bySemanticsLabel('Citation 3'), findsOneWidget);
        await tester.tap(find.text('1'));
        await tester.tap(find.text('3'));
        expect(tapped, ['1', '3']);
        handle.dispose();
      },
    );

    testWidgets('without onTapCitation it is not exposed as a button', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(MarkdownBody(data: 'a [1]', extensions: [_citations])),
      );
      // The label of a non-interactive chip is included in the paragraph spoken text.
      final finder = find.bySemanticsLabel(RegExp('Citation 1'));
      expect(finder, findsOneWidget);
      expect(
        tester
            .getSemantics(finder)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );
      handle.dispose();
    });

    testWidgets('can be focused by keyboard and is invoked with Enter', (
      tester,
    ) async {
      final tapped = <String>[];
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: 'a [4]',
            extensions: [_citations],
            onTapCitation: tapped.add,
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(tapped, ['4']);
    });

    testWidgets('citationBuilder can replace the chip', (tester) async {
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: 'a [1, 2]',
            extensions: [_citations],
            citationBuilder: (context, ids, style) =>
                TextSpan(text: '<${ids.join('|')}>', style: style),
          ),
        ),
      );
      expect(find.textContaining('<1|2>', findRichText: true), findsOneWidget);
    });

    testWidgets('without the extension [1] stays as text', (tester) async {
      await tester.pumpWidget(_app(const MarkdownBody(data: 'a [1]')));
      expect(find.text('a [1]'), findsOneWidget);
    });

    testWidgets('style label can be overridden', (tester) async {
      final handle = tester.ensureSemantics();
      final style =
          MarkdownStyleSheet.fromTheme(
            ThemeData(textTheme: Typography.material2021().englishLike),
          ).copyWith(
            citation: MarkdownXCitationStyle.light.copyWith(
              semanticsLabel: (id) => '出典 $id',
            ),
          );
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: 'a [1]',
            extensions: [_citations],
            styleSheet: style,
          ),
        ),
      );
      expect(find.bySemanticsLabel(RegExp('出典 1')), findsOneWidget);
      handle.dispose();
    });
  });
}
