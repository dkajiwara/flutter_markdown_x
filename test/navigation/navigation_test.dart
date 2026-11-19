import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_markdown_x/src/navigation/navigation.dart'
    show markdownXAddFootnoteBackrefs, markdownXResolvePath;
import 'package:flutter_test/flutter_test.dart';

List<MdxBlock> _parse(String data) => parseMarkdown(data);

List<String> _ids(String data) => [
  for (final h in markdownXHeadings(_parse(data))) h.id,
];

void main() {
  group('markdownXSlug', () {
    test('lowercases, drops symbols, and turns whitespace into -', () {
      expect(markdownXSlug('Hello, World!'), 'hello-world');
      expect(markdownXSlug('Foo_Bar-baz'), 'foo_bar-baz');
      expect(markdownXSlug('a  b'), 'a--b');
      expect(markdownXSlug('C++ & Rust (2024)'), 'c--rust-2024');
    });

    test('keeps Unicode characters such as Japanese', () {
      expect(markdownXSlug('はじめに'), 'はじめに');
      expect(markdownXSlug('第1章：概要'), '第1章概要');
      expect(markdownXSlug('Über Café'), 'über-café');
    });

    test('falls back to section when empty', () {
      expect(markdownXSlug('!!!'), 'section');
      expect(markdownXSlug(''), 'section');
    });
  });

  group('markdownXHeadings', () {
    test('returns id, level, text and path in document order', () {
      final headings = markdownXHeadings(
        _parse('# Title\n\ntext\n\n## **Bold** and `code` [link](x)'),
      );
      expect(headings.map((h) => '${h.id}|${h.level}|${h.text}|${h.path}'), [
        'title|1|Title|[0]',
        'bold-and-code-link|2|Bold and code link|[2]',
      ]);
    });

    test('appends -1, -2 to duplicate headings', () {
      expect(_ids('# A\n\n## A\n\n### A\n\n# B\n\n# A'), [
        'a',
        'a-1',
        'a-2',
        'b',
        'a-3',
      ]);
    });

    test(
      'stays unique even if a generated id collides with another heading slug',
      () {
        expect(_ids('# A\n\n# A\n\n# A 1'), ['a', 'a-1', 'a-1-1']);
        expect(_ids('# A\n\n# A-1\n\n# A'), ['a', 'a-1', 'a-2']);
      },
    );

    test('also picks up headings in quotes, lists and details, addressable by path', () {
      const source =
          '> # Quoted\n\n- # In list\n\n<details>\n<summary>s</summary>\n\n'
          '## In details\n\n</details>';
      final blocks = _parse(source);
      final headings = markdownXHeadings(blocks);
      expect(headings.map((h) => h.id), ['quoted', 'in-list', 'in-details']);
      for (final heading in headings) {
        final resolved = markdownXResolvePath(blocks, heading.path)!;
        expect(resolved.chain.last, isA<MdxHeading>());
        expect(resolved.item, isNull);
      }
    });

    test('also picks up headings inside blocks made by an extension', () {
      final blocks = [
        MdxCustomBlock(
          'box',
          blocks: [
            MdxHeading(2, [MdxText('Inside')]),
          ],
        ),
      ];
      expect(markdownXHeadings(blocks).single.path, [0, 0]);
    });

    test('the result is unmodifiable', () {
      final headings = markdownXHeadings(_parse('# A'));
      expect(() => headings.add(headings.first), throwsUnsupportedError);
      expect(() => headings.first.path.add(1), throwsUnsupportedError);
    });

    test('the same input yields the same headings and targets', () {
      const source = '# A\n\ntext[^1]\n\n## A\n\n[^1]: note';
      final first = parseMarkdown(source);
      final second = parseMarkdown(source);
      expect(markdownXHeadings(first), markdownXHeadings(second));
      expect(markdownXAnchors(first), markdownXAnchors(second));
    });
  });

  group('Footnotes', () {
    const source = 'a[^x] b[^y] c[^x]\n\n> q[^y]\n\n[^x]: first\n[^y]: second';

    test('the definition and the first reference become jump targets', () {
      final anchors = markdownXAnchors(_parse(source));
      expect(anchors['fn-x']!.kind, MarkdownXAnchorKind.footnote);
      expect(anchors['fn-x']!.path, [3, 0]);
      expect(anchors['fn-y']!.path, [3, 1]);
      expect(anchors['fnref-x']!.kind, MarkdownXAnchorKind.footnoteReference);
      expect(anchors['fnref-x']!.path, [0]);
      expect(anchors['fnref-y']!.path, [0]);
    });

    test(
      'if the second reference is only inside a quote, points to that path',
      () {
        final anchors = markdownXAnchors(_parse('> q[^y]\n\n[^y]: second'));
        expect(anchors['fnref-y']!.path, [0, 0]);
      },
    );

    test(
      'appends a back link to the first reference at the end of the definition',
      () {
        final blocks = markdownXAddFootnoteBackrefs(_parse(source));
        final list = blocks.last as MdxList;
        for (final (i, label) in ['x', 'y'].indexed) {
          final paragraph = list.items[i].blocks.last as MdxParagraph;
          final link = paragraph.inlines.last as MdxLink;
          expect(link.href, '#fnref-$label');
          expect(link.children, [MdxText('↩')]);
        }
      },
    );

    test('the IR of a document without footnote definitions is unchanged', () {
      final blocks = _parse('a[^none]\n\n---\n\n1. one\n2. two');
      expect(identical(markdownXAddFootnoteBackrefs(blocks), blocks), isTrue);
      expect(markdownXAnchors(blocks), isEmpty);
    });

    test('a list whose reference and definition counts differ is not treated as footnotes', () {
      final ref = MdxStyled(MdxStyleKind.superscript, [
        MdxLink(href: '#fn-1', children: [MdxText('1')]),
      ]);
      final blocks = [
        MdxParagraph([ref]),
        MdxThematicBreak(),
        MdxList(
          ordered: true,
          items: [
            MdxListItem([
              MdxParagraph([MdxText('x')]),
            ]),
            MdxListItem([
              MdxParagraph([MdxText('y')]),
            ]),
          ],
        ),
      ];
      expect(markdownXAnchors(blocks), isEmpty);
      expect(identical(markdownXAddFootnoteBackrefs(blocks), blocks), isTrue);
    });

    test('heading slugs avoid footnote ids', () {
      final blocks = _parse('# fn-1\n\ntext[^1]\n\n[^1]: note');
      expect(markdownXHeadings(blocks).single.id, 'fn-1-1');
      expect(
        markdownXAnchors(blocks)['fn-1']!.kind,
        MarkdownXAnchorKind.footnote,
      );
    });
  });
}
