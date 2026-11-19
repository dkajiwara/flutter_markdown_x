import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';

final _mentionSyntax = MarkdownXInlineSyntax(
  pattern: RegExp(r'@(\w+)'),
  build: (match) => MdxCustomInline(
    'mention',
    attributes: {'name': match[1]!},
    children: [MdxText(match[0]!)],
  ),
);

final _mention = MarkdownXExtension(inlineSyntaxes: [_mentionSyntax]);

List<MdxBlock> _parse(String source) => parseMarkdown(source);

MdxInline _mentionOf(String name) => MdxCustomInline(
  'mention',
  attributes: {'name': name},
  children: [MdxText('@$name')],
);

void main() {
  group('MdxCustomInline / MdxCustomBlock', () {
    test('attributes are immutable and comparable by value', () {
      final source = {'a': '1', 'b': '2'};
      final x = MdxCustomInline('t', attributes: source);
      source['a'] = 'changed';
      expect(x.attributes['a'], '1');
      expect(() => x.attributes['c'] = '3', throwsUnsupportedError);

      // Independent of Map ordering.
      final y = MdxCustomInline('t', attributes: {'b': '2', 'a': '1'});
      expect(x, y);
      expect(x.hashCode, y.hashCode);
      expect(x, isNot(MdxCustomInline('t', attributes: {'a': '1', 'b': '9'})));
      expect(x, isNot(MdxCustomInline('u', attributes: {'a': '1', 'b': '2'})));
    });

    test('children are defensively copied', () {
      final children = <MdxInline>[MdxText('a')];
      final x = MdxCustomInline('t', children: children);
      children.add(MdxText('b'));
      expect(x.children, hasLength(1));
      expect(() => x.children.add(MdxText('c')), throwsUnsupportedError);
    });

    test('MdxCustomBlock is also immutable and comparable', () {
      final inlines = <MdxInline>[MdxText('a')];
      final blocks = <MdxBlock>[MdxThematicBreak()];
      final a = MdxCustomBlock(
        'note',
        attributes: {'k': 'v'},
        inlines: inlines,
        blocks: blocks,
      );
      inlines.clear();
      blocks.clear();
      expect(a.inlines, hasLength(1));
      expect(a.blocks, hasLength(1));
      expect(
        a,
        MdxCustomBlock(
          'note',
          attributes: {'k': 'v'},
          inlines: [MdxText('a')],
          blocks: [MdxThematicBreak()],
        ),
      );
    });
  });

  group('inline syntax', () {
    test('splits text into custom inline', () {
      final out = applyMarkdownXExtensions(_parse('hi @alice and @bob!'), [
        _mention,
      ]);
      expect(out, [
        MdxParagraph([
          MdxText('hi '),
          _mentionOf('alice'),
          MdxText(' and '),
          _mentionOf('bob'),
          MdxText('!'),
        ]),
      ]);
    });

    test('does not transform inside code spans and code blocks', () {
      final blocks = _parse('`@a` and **@b**\n\n```\n@c\n```');
      final out = applyMarkdownXExtensions(blocks, [_mention]);
      final paragraph = out[0] as MdxParagraph;
      expect(
        paragraph.inlines[0],
        MdxStyled(MdxStyleKind.code, [MdxText('@a')]),
      );
      expect(
        paragraph.inlines[2],
        MdxStyled(MdxStyleKind.strong, [_mentionOf('b')]),
      );
      expect(out[1], blocks[1]);
      expect(identical(out[1], blocks[1]), isTrue);
    });

    test(
      'link href is not transformed, and by default link text is not either',
      () {
        final blocks = _parse('[@a](https://x.test/@b)');
        final out = applyMarkdownXExtensions(blocks, [_mention]);
        expect(out, blocks);
      },
    );

    test('with applyInsideLinks: true link text is also transformed', () {
      final ext = MarkdownXExtension(
        inlineSyntaxes: [
          MarkdownXInlineSyntax(
            pattern: RegExp(r'@(\w+)'),
            applyInsideLinks: true,
            build: (m) => _mentionOf(m[1]!),
          ),
        ],
      );
      final out = applyMarkdownXExtensions(_parse('[@a](u)'), [ext]);
      final link = (out[0] as MdxParagraph).inlines[0] as MdxLink;
      expect(link.href, 'u');
      expect(link.children, [_mentionOf('a')]);
    });

    test('also transforms inside blockquote, list, table and details', () {
      final blocks = _parse(
        '> @q\n\n- @l\n\n| h |\n|---|\n| @t |\n\n'
        '<details><summary>@s</summary>\n\n@d\n\n</details>',
      );
      final out = applyMarkdownXExtensions(blocks, [_mention]);
      String dump(Object? n) => n.toString();
      for (final name in ['q', 'l', 't', 's', 'd']) {
        expect(out.map(dump).join(), contains('mention'), reason: name);
      }
      final text = out.map(dump).join();
      expect('mention'.allMatches(text).length, greaterThanOrEqualTo(5));
    });

    test('a subtree without transformations returns the same instance', () {
      final blocks = _parse('plain\n\n> quote\n\nhello @x');
      final out = applyMarkdownXExtensions(blocks, [_mention]);
      expect(identical(out[0], blocks[0]), isTrue);
      expect(identical(out[1], blocks[1]), isTrue);
      expect(identical(out[2], blocks[2]), isFalse);
    });

    test('with no extensions the input is returned as is', () {
      final blocks = _parse('hi @a');
      expect(
        identical(applyMarkdownXExtensions(blocks, const []), blocks),
        isTrue,
      );
    });

    test('with multiple syntaxes the earlier match wins, and registration order breaks ties at the same position', () {
      final hash = MarkdownXInlineSyntax(
        pattern: RegExp(r'#(\w+)'),
        build: (m) => MdxCustomInline('tag', attributes: {'n': m[1]!}),
      );
      final out = applyMarkdownXExtensions(_parse('#t @u'), [
        MarkdownXExtension(inlineSyntaxes: [_mentionSyntax, hash]),
      ]);
      final inlines = (out[0] as MdxParagraph).inlines;
      expect(inlines.first, isA<MdxCustomInline>());
      expect((inlines.first as MdxCustomInline).type, 'tag');
      expect(inlines.last, _mentionOf('u'));
    });

    test('a match whose build returns null is ignored', () {
      final syntax = MarkdownXInlineSyntax(
        pattern: RegExp(r'@(\w+)'),
        build: (m) => m[1] == 'skip' ? null : _mentionOf(m[1]!),
      );
      final out = applyMarkdownXExtensions(_parse('@skip @ok'), [
        MarkdownXExtension(inlineSyntaxes: [syntax]),
      ]);
      expect((out[0] as MdxParagraph).inlines, [
        MdxText('@skip '),
        _mentionOf('ok'),
      ]);
    });

    test('an empty match does not cause an infinite loop', () {
      final syntax = MarkdownXInlineSyntax(
        pattern: RegExp(r'x*'),
        build: (m) => MdxCustomInline('e'),
      );
      final blocks = _parse('abc');
      final out = applyMarkdownXExtensions(blocks, [
        MarkdownXExtension(inlineSyntaxes: [syntax]),
      ]);
      expect(out, blocks);
    });

    test('escapes are already resolved in the IR so they cannot be distinguished (by design)', () {
      final out = applyMarkdownXExtensions(_parse(r'\@foo'), [_mention]);
      expect(out.toString(), contains('mention'));
    });
  });

  group('block transform', () {
    final admonition = MarkdownXExtension(
      transformBlock: (block) {
        if (block is MdxParagraph &&
            block.inlines.isNotEmpty &&
            block.inlines.first is MdxText &&
            (block.inlines.first as MdxText).text.startsWith('NOTE: ')) {
          return MdxCustomBlock(
            'note',
            inlines: [
              MdxText((block.inlines.first as MdxText).text.substring(6)),
              ...block.inlines.skip(1),
            ],
          );
        }
        return null;
      },
    );

    test('replaces a paragraph with a custom block (including nested)', () {
      final out = applyMarkdownXExtensions(
        _parse('NOTE: a\n\n> NOTE: b\n\nz'),
        [admonition],
      );
      expect(out[0], isA<MdxCustomBlock>());
      expect(
        ((out[1] as MdxBlockquote).blocks.single as MdxCustomBlock).type,
        'note',
      );
      expect(out[2], isA<MdxParagraph>());
    });

    test('transforms blocks after seeing the inline transform result', () {
      final ext = MarkdownXExtension(
        inlineSyntaxes: [_mentionSyntax],
        transformBlock: (b) =>
            b is MdxParagraph && b.inlines.any((i) => i is MdxCustomInline)
            ? MdxCustomBlock('mentioned', inlines: b.inlines)
            : null,
      );
      final out = applyMarkdownXExtensions(_parse('hi @a'), [ext]);
      expect(out.single, isA<MdxCustomBlock>());
    });
  });

  group('IncrementalMarkdownParser', () {
    test(
      'applies extensions and returns the same instance for the same chunk',
      () {
        final parser = IncrementalMarkdownParser(parse: _parse);
        final a = parser.parse('hi @a\n\nsecond\n\n', extensions: [_mention]);
        final b = parser.parse(
          'hi @a\n\nsecond\n\nthird',
          extensions: [_mention],
        );
        expect(a.first.toString(), contains('mention'));
        expect(identical(a[0], b[0]), isTrue);
        expect(identical(a[1], b[1]), isTrue);
      },
    );

    test('drops the cache when the extensions elements change', () {
      final parser = IncrementalMarkdownParser(parse: _parse);
      final a = parser.parse('hi @a\n\nsecond', extensions: [_mention]);
      final b = parser.parse('hi @a\n\nsecond');
      expect(a.first.toString(), contains('mention'));
      expect(b.first.toString(), isNot(contains('mention')));
      // A different list holding the same instances is not considered a change.
      final c = parser.parse('hi @a\n\nsecond', extensions: [_mention]);
      final d = parser.parse('hi @a\n\nsecond', extensions: [_mention]);
      expect(identical(c[1], d[1]), isTrue);
      // A different instance, even of the same type, is considered a change.
      final e = parser.parse(
        'hi @a\n\nsecond',
        extensions: [
          MarkdownXExtension(inlineSyntaxes: [_mentionSyntax]),
        ],
      );
      expect(identical(d[1], e[1]), isFalse);
    });

    test('chunked parsing matches parsing the whole at once', () {
      const source = 'a @x\n\n- b @y\n\n```\n@z\n```\n\nc @w';
      final whole = applyMarkdownXExtensions(_parse(source), [_mention]);
      final incremental = IncrementalMarkdownParser(parse: _parse)
          .parse(source, extensions: [_mention]);
      expect(incremental, whole);
    });
  });
}
