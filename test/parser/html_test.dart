// Verifies the supported HTML scope (doc/html.md) through parser output.
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';

MdxText t(String text) => MdxText(text);

MdxParagraph p(List<MdxInline> inlines) => MdxParagraph(inlines);

const one = (colSpan: 1, rowSpan: 1);

MdxTable table(String source) {
  final blocks = parseMarkdown(source);
  expect(blocks, hasLength(1), reason: source);
  return blocks.single as MdxTable;
}

void main() {
  htmlPhrasingTests();
  test(
    'HTML quote, list, table caption, and entities share the native and Web IR',
    () {
      final blocks = parseMarkdown(
        '<blockquote><ol start="4"><li><table><caption>&copy; <b>Data</b>'
        '</caption><tr><td>Value</td></tr></table></li></ol></blockquote>',
      );
      final quote = blocks.single as MdxBlockquote;
      final list = quote.blocks.single as MdxList;
      expect(list.start, 4);
      expect(list.items.single.blocks, [
        p([
          t('© '),
          MdxStyled(MdxStyleKind.strong, [t('Data')]),
        ]),
        isA<MdxTable>(),
      ]);
    },
  );

  group('details', () {
    test('open attribute makes it open', () {
      for (final source in [
        '<details open><summary>S</summary>\nbody\n</details>',
        '<details OPEN="">\n<summary>S</summary>\nbody\n</details>',
        '<details class="x" open="open"><summary>S</summary>\nbody\n</details>',
      ]) {
        final details = parseMarkdown(source).single as MdxDetails;
        expect(details.open, isTrue, reason: source);
        expect(details.summary, [t('S')]);
      }
    });

    test('without open it is closed', () {
      final details =
          parseMarkdown('<details><summary>S</summary>\nbody\n</details>')
                  .single
              as MdxDetails;
      expect(details.open, isFalse);
    });

    test('nested details each keep their own open', () {
      const source = '''
<details open>
<summary>outer</summary>

<details>
<summary>inner</summary>

x

</details>

</details>
''';
      final outer = parseMarkdown(source).single as MdxDetails;
      expect(outer.open, isTrue);
      final inner = outer.blocks.single as MdxDetails;
      expect(inner.open, isFalse);
    });
  });

  group('table span', () {
    test('reads colspan and rowspan, and treats thead as header', () {
      const source = '''
<table>
<thead><tr><th colspan="2">Head</th></tr></thead>
<tbody>
<tr><td rowspan="2">A</td><td>B</td></tr>
<tr><td>C</td></tr>
</tbody>
</table>
''';
      expect(
        table(source),
        MdxTable(
          alignments: [null, null],
          header: [
            [t('Head')],
          ],
          rows: [
            [
              [t('A')],
              [t('B')],
            ],
            [
              [t('C')],
            ],
          ],
          headerSpans: [(colSpan: 2, rowSpan: 1)],
          rowSpans: [
            [(colSpan: 1, rowSpan: 2), one],
            [one],
          ],
        ),
      );
    });

    test(
      'column count is determined by the occupied width including spans',
      () {
        final parsed = table(
          '<table><tr><td colspan="3">wide</td></tr>'
          '<tr><td>1</td><td>2</td></tr></table>',
        );
        expect(parsed.alignments, hasLength(3));
        expect(parsed.rowSpanAt(0, 0).colSpan, 3);
      },
    );

    test('an invalid span becomes 1, and an oversized colspan is clamped to the limit', () {
      final parsed = table(
        '<table><tr>'
        '<td colspan="0">a</td><td colspan="x" rowspan="-2">b</td>'
        '<td colspan=" 2 ">c</td><td colspan="9999">d</td>'
        '<td rowspan="0">e</td>'
        '</tr></table>',
      );
      expect(parsed.rowSpanAt(0, 0), one);
      expect(parsed.rowSpanAt(0, 1), one);
      expect(parsed.rowSpanAt(0, 2), (colSpan: 2, rowSpan: 1));
      expect(parsed.rowSpanAt(0, 3), (colSpan: mdxMaxCellSpan, rowSpan: 1));
      expect(parsed.rowSpanAt(0, 4), one);
    });

    test(
      'a rowspan beyond the table bottom is clamped to the remaining rows',
      () {
        final parsed = table(
          '<table><tr><td rowspan="500">a</td><td>b</td></tr>'
          '<tr><td>c</td></tr></table>',
        );
        expect(parsed.rowSpanAt(0, 0), (colSpan: 1, rowSpan: 2));
      },
    );

    test('a table without span has no span', () {
      final parsed = table('<table><tr><td>a</td><td>b</td></tr></table>');
      expect(parsed.hasSpans, isFalse);
    });

    test('rows in thead become header even with td', () {
      final parsed = table(
        '<table><thead><tr><td>h</td></tr></thead>'
        '<tbody><tr><td>v</td></tr></tbody></table>',
      );
      expect(parsed.header, [
        [t('h')],
      ]);
      expect(parsed.rows, [
        [
          [t('v')],
        ],
      ]);
    });
  });

  group('table cell content', () {
    test('br becomes a line break', () {
      final parsed = table('<table><tr><td>a<br>b</td></tr></table>');
      expect(parsed.rows.single.single, [t('a'), MdxLineBreak(), t('b')]);
    });

    test('a list in a cell becomes text with a marker per line', () {
      final parsed = table(
        '<table><tr><td>\n\n- one\n- two\n\n</td></tr></table>',
      );
      expect(parsed.rows.single.single, [
        t('• one'),
        MdxLineBreak(),
        t('• two'),
      ]);
    });

    test('pre in a cell keeps its text as is', () {
      final parsed = table('<table><tr><td><pre>a\nb</pre></td></tr></table>');
      expect(parsed.rows.single.single, [t('a\nb')]);
    });
  });

  group('script / style / pre / comments', () {
    test('script and style disappear with their content', () {
      expect(parseMarkdown('<script>alert(1)</script>\n\nafter'), [
        p([t('after')]),
      ]);
      expect(parseMarkdown('x <style>p{}</style>y'), [
        p([t('x y')]),
      ]);
    });

    test('pre becomes a code block, and the language is read from class', () {
      expect(
        parseMarkdown(
          '<pre><code class="language-dart">var a = 1;\n</code></pre>',
        ),
        [MdxCodeBlock('var a = 1;', language: 'dart')],
      );
      expect(parseMarkdown('<pre>\n**raw**\n</pre>'), [
        MdxCodeBlock('**raw**'),
      ]);
    });

    test('comments disappear', () {
      expect(parseMarkdown('a <!-- c --> b'), [
        p([t('a  b')]),
      ]);
      expect(parseMarkdown('a<!-->b'), [
        p([t('ab')]),
      ]);
    });

    test('unsupported tags are shown as written', () {
      expect(parseMarkdown('<section>hello <foo>world</foo></section>'), [
        p([t('<section>hello <foo>world</foo></section>')]),
      ]);
      expect(parseMarkdown('Use List<String> or <T>.'), [
        p([t('Use List<String> or <T>.')]),
      ]);
    });

    test('a span without attributes keeps only its content', () {
      expect(parseMarkdown('a <span>b</span> c'), [
        p([t('a b c')]),
      ]);
    });
  });
}

// HTML Living Standard, section 15 (rendering): phrasing content.
void htmlPhrasingTests() {
  List<MdxInline> inlines(String source) =>
      (parseMarkdown(source).single as MdxParagraph).inlines;

  group('phrasing tags', () {
    test('cite, dfn, var, samp, tt and big keep their own kind', () {
      const kinds = {
        'cite': MdxStyleKind.cite,
        'dfn': MdxStyleKind.definition,
        'var': MdxStyleKind.variable,
        'samp': MdxStyleKind.sample,
        'tt': MdxStyleKind.teletype,
        'big': MdxStyleKind.big,
      };
      kinds.forEach((tag, kind) {
        expect(inlines('<$tag>x</$tag>'), [
          MdxStyled(kind, [t('x')]),
        ], reason: tag);
      });
    });

    test('abbr and acronym keep the title', () {
      expect(inlines('<abbr title="World Health">WHO</abbr>'), [
        MdxStyled(MdxStyleKind.abbreviation, [t('WHO')], title: 'World Health'),
      ]);
      expect(inlines('<acronym title="x">NB</acronym> <abbr>y</abbr>'), [
        MdxStyled(MdxStyleKind.acronym, [t('NB')], title: 'x'),
        t(' '),
        MdxStyled(MdxStyleKind.abbreviation, [t('y')]),
      ]);
    });

    test('q alternates the quotation marks by nesting depth', () {
      expect(inlines('<q>a<q>b</q>c</q>'), [t('“a‘b’c”')]);
    });

    test('an unclosed q is closed with its closing quote', () {
      expect(inlines('<q>a'), [t('“a”')]);
    });

    test('bdi isolates and bdo overrides', () {
      expect(inlines('<bdi>x</bdi>'), [t('\u{2068}x\u{2069}')]);
      expect(inlines('<bdi dir="rtl">x</bdi>'), [t('\u{2067}x\u{2069}')]);
      expect(inlines('<bdo dir="rtl">x</bdo>'), [t('\u{202E}x\u{202C}')]);
      expect(inlines('<bdo dir="ltr">x</bdo>'), [t('\u{202D}x\u{202C}')]);
      expect(inlines('<bdo>x</bdo>'), [t('x')]);
    });

    test('wbr is a zero width space', () {
      expect(inlines('a<wbr>b'), [t('a\u{200B}b')]);
    });

    test('a block hr is a thematic break', () {
      expect(parseMarkdown('a\n\n<hr>\n\nb'), [
        p([t('a')]),
        MdxThematicBreak(),
        p([t('b')]),
      ]);
    });
  });
}
