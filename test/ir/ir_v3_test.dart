// IR v3: soft line breaks (`MdxSoftBreak`), list tightness (`MdxList.tight`) and the fence
// info string (`MdxCodeBlock.info`), from the parser through every IR rewrite pass.
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_markdown_x/math.dart';
import 'package:flutter_markdown_x/src/navigation/navigation.dart'
    show markdownXAddFootnoteBackrefs;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/selection_harness.dart';

List<MdxBlock> _parse(String source) => parseMarkdown(source);

final _pair = MarkdownXInlineSyntax(
  pattern: RegExp(r'\[(\d+),\s*(\d+)\]'),
  build: (match) => MdxCustomInline(
    'pair',
    attributes: {'a': match[1]!, 'b': match[2]!},
    children: [MdxText(match[0]!)],
  ),
);

final _pairExtension = MarkdownXExtension(inlineSyntaxes: [_pair]);

List<MdxInline> _inlines(List<MdxBlock> blocks) =>
    (blocks.single as MdxParagraph).inlines;

void main() {
  group('nodes', () {
    test('MdxSoftBreak has value equality and no props', () {
      expect(MdxSoftBreak(), MdxSoftBreak());
      expect(MdxSoftBreak().hashCode, MdxSoftBreak().hashCode);
      expect(MdxSoftBreak() == MdxLineBreak(), isFalse);
    });

    test('hand-built defaults: tight is true, info is null', () {
      expect(MdxList(ordered: false, items: const []).tight, isTrue);
      expect(MdxCodeBlock('x').info, isNull);
    });

    test('tight and info take part in equality', () {
      expect(
        MdxList(ordered: false, items: const []),
        isNot(MdxList(ordered: false, tight: false, items: const [])),
      );
      expect(MdxCodeBlock('x', info: 'a'), isNot(MdxCodeBlock('x', info: 'b')));
      expect(MdxCodeBlock('x', info: 'a'), MdxCodeBlock('x', info: 'a'));
    });
  });

  group('parser', () {
    test('a source newline in a paragraph is a soft break', () {
      expect(_inlines(_parse('a\nb')), [
        MdxText('a'),
        MdxSoftBreak(),
        MdxText('b'),
      ]);
    });

    test('tight and loose lists', () {
      expect((_parse('- a\n- b').single as MdxList).tight, isTrue);
      expect((_parse('- a\n\n- b').single as MdxList).tight, isFalse);
    });

    test('the fence info string after the language is kept', () {
      final block = _parse('```rust {1,3} title="x"\nfn a() {}\n```').single;
      expect(
        block,
        MdxCodeBlock('fn a() {}', language: 'rust', info: '{1,3} title="x"'),
      );
      expect(
        _parse('```rust\nx\n```').single,
        MdxCodeBlock('x', language: 'rust'),
      );
    });
  });

  group('inline syntaxes', () {
    test('a match can span a soft break', () {
      final out = applyMarkdownXExtensions(_parse('see [1,\n2] now'), [
        _pairExtension,
      ]);
      final inlines = _inlines(out);
      expect(inlines, hasLength(3));
      expect(inlines[1], isA<MdxCustomInline>());
      expect((inlines[1] as MdxCustomInline).attributes, {'a': '1', 'b': '2'});
    });

    test('soft breaks outside a match are restored', () {
      final out = applyMarkdownXExtensions(_parse('a\n[1, 2]\nb'), [
        _pairExtension,
      ]);
      final inlines = _inlines(out);
      expect(inlines, [
        MdxText('a'),
        MdxSoftBreak(),
        inlines[2],
        MdxSoftBreak(),
        MdxText('b'),
      ]);
      expect(inlines[2], isA<MdxCustomInline>());
    });

    test('a run without a match is returned unchanged', () {
      final blocks = _parse('a\nb\nc');
      expect(applyMarkdownXExtensions(blocks, [_pairExtension]), blocks);
    });

    test('a soft break between styled nodes survives', () {
      final out = applyMarkdownXExtensions(_parse('*a*\n*b*'), [
        _pairExtension,
      ]);
      expect(_inlines(out)[1], MdxSoftBreak());
    });
  });

  group('rewrite passes keep tight and info', () {
    const extensions = [markdownXAlertsExtension];

    test('applyMarkdownXExtensions with an inline syntax', () {
      final out = applyMarkdownXExtensions(
        _parse('- [1, 2]\n\n- b\n\n```js hl=1\nx\n```'),
        [_pairExtension],
      );
      expect((out[0] as MdxList).tight, isFalse);
      expect((out[1] as MdxCodeBlock).info, 'hl=1');
    });

    test('alerts transform keeps tight and info', () {
      final source = applyMarkdownXSourceTransforms(
        '- > [!NOTE]\n  > x\n\n- b\n\n```js hl=1\nx\n```',
        extensions,
      );
      final out = applyMarkdownXExtensions(parseMarkdown(source), extensions);
      expect((out[0] as MdxList).tight, isFalse);
      expect((out[1] as MdxCodeBlock).info, 'hl=1');
    });

    test('alert marker followed by a soft break leaves no leading break', () {
      final source = applyMarkdownXSourceTransforms(
        '> [!NOTE]\n> body\n> more',
        extensions,
      );
      final out = applyMarkdownXExtensions(parseMarkdown(source), extensions);
      final alert = out.single as MdxCustomBlock;
      expect(
        alert.blocks.single,
        MdxParagraph([MdxText('body'), MdxSoftBreak(), MdxText('more')]),
      );
    });

    test('math extension keeps info on code blocks it rewrites', () {
      final math = MarkdownXMath().extension;
      final out = applyMarkdownXExtensions(
        _parse('```js hl=1\nx\n```\n\n- a\n- b'),
        [math],
      );
      expect((out[0] as MdxCodeBlock).info, 'hl=1');
      expect((out[1] as MdxList).tight, isTrue);
    });

    test('footnote backref pass keeps tight', () {
      final blocks = _parse('a[^1]\n\n[^1]: note');
      final out = markdownXAddFootnoteBackrefs(blocks);
      expect((out.last as MdxList).tight, (blocks.last as MdxList).tight);
    });
  });

  group('navigation', () {
    test('a soft break is a space in heading text and slugs', () {
      final headings = markdownXHeadings(_parse('one\ntwo\n==='));
      expect(headings.single.text, 'one two');
      expect(headings.single.id, 'one-two');
    });
  });

  group('rendering', () {
    testWidgets('a soft break renders as one space', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MarkdownBody(data: 'a\nb')),
        ),
      );
      final text = tester.widget<RichText>(find.byType(RichText).first);
      expect(text.text.toPlainText(), 'a b');
    });

    testWidgets('copying a soft break gives a space', (tester) async {
      final clipboard = ClipboardProbe();
      mockClipboard(tester, clipboard);
      await tester.pumpWidget(selectionApp(const MarkdownBody(data: 'a\nb')));
      await tester.pumpAndSettle();
      final copied = await selectAllAndCopy(
        tester,
        clipboard,
        find.byType(MarkdownBody),
      );
      expect(copied, 'a b');
    });
  });
}
