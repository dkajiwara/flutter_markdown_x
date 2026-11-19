import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';

MdxText t(String text) => MdxText(text);

MdxParagraph p(List<MdxInline> inlines) => MdxParagraph(inlines);

MdxStyled styled(MdxStyleKind kind, List<MdxInline> children) =>
    MdxStyled(kind, children);

void main() {
  group('basic Markdown elements', () {
    test('headings and paragraph', () {
      expect(parseMarkdown('# Title\n\nHello'), [
        MdxHeading(1, [t('Title')]),
        p([t('Hello')]),
      ]);
    });

    test('emphasis, strikethrough and inline code', () {
      expect(parseMarkdown('**b** *i* ~~s~~ `c`'), [
        p([
          styled(MdxStyleKind.strong, [t('b')]),
          t(' '),
          styled(MdxStyleKind.emphasis, [t('i')]),
          t(' '),
          styled(MdxStyleKind.strikethrough, [t('s')]),
          t(' '),
          styled(MdxStyleKind.code, [t('c')]),
        ]),
      ]);
    });

    test('link and image', () {
      expect(parseMarkdown('[link](https://example.com) ![alt](a.png "T")'), [
        p([
          MdxLink(href: 'https://example.com', children: [t('link')]),
          t(' '),
          MdxImage(src: 'a.png', alt: 'alt', title: 'T'),
        ]),
      ]);
    });

    test('soft break is its own node, hard break is a line break', () {
      expect(parseMarkdown('a\nb  \nc'), [
        p([t('a'), MdxSoftBreak(), t('b'), MdxLineBreak(), t('c')]),
      ]);
    });

    test('code block keeps language and content, and restores entities', () {
      expect(parseMarkdown('```dart\nfinal a = 1 < 2 && true;\n```'), [
        MdxCodeBlock('final a = 1 < 2 && true;', language: 'dart'),
      ]);
    });

    test('blockquote', () {
      expect(parseMarkdown('> quote'), [
        MdxBlockquote([
          p([t('quote')]),
        ]),
      ]);
    });

    test('horizontal rule', () {
      expect(parseMarkdown('---'), [MdxThematicBreak()]);
    });

    test('nested list', () {
      expect(parseMarkdown('- a\n  - b\n- c'), [
        MdxList(
          ordered: false,
          items: [
            MdxListItem([
              p([t('a')]),
              MdxList(
                ordered: false,
                items: [
                  MdxListItem([
                    p([t('b')]),
                  ]),
                ],
              ),
            ]),
            MdxListItem([
              p([t('c')]),
            ]),
          ],
        ),
      ]);
    });

    test('ordered list keeps its start number', () {
      final list = parseMarkdown('3. a\n4. b').single as MdxList;
      expect(list.ordered, isTrue);
      expect(list.start, 3);
      expect(list.items, hasLength(2));
    });

    test('task list', () {
      final list = parseMarkdown('- [ ] todo\n- [x] done').single as MdxList;
      expect(list.items.map((item) => item.checked), [false, true]);
      expect(list.items.first.blocks, [
        p([t('todo')]),
      ]);
    });

    test('loose task list keeps the task state', () {
      final list =
          parseMarkdown('- [ ] todo\n\n- [x] done\n\n- plain').single
              as MdxList;
      expect(list.tight, isFalse);
      expect(list.items.map((item) => item.checked), [false, true, null]);
      expect(list.items.first.blocks, [
        p([t('todo')]),
      ]);
    });

    test('table keeps alignment and cell inlines', () {
      expect(parseMarkdown('| a | b |\n|---|:-:|\n| 1 | **2** |'), [
        MdxTable(
          alignments: [null, MdxAlign.center],
          header: [
            [t('a')],
            [t('b')],
          ],
          rows: [
            [
              [t('1')],
              [
                styled(MdxStyleKind.strong, [t('2')]),
              ],
            ],
          ],
        ),
      ]);
    });

    test('symbols in text do not remain as entities', () {
      expect(parseMarkdown('1 < 2 & 3 > 2 "q"'), [
        p([t('1 < 2 & 3 > 2 "q"')]),
      ]);
    });
  });

  group('inline HTML', () {
    test('sub, sup and kbd', () {
      expect(parseMarkdown('H<sub>2</sub>O x<sup>2</sup> <kbd>Ctrl</kbd>'), [
        p([
          t('H'),
          styled(MdxStyleKind.subscript, [t('2')]),
          t('O x'),
          styled(MdxStyleKind.superscript, [t('2')]),
          t(' '),
          styled(MdxStyleKind.keyboard, [t('Ctrl')]),
        ]),
      ]);
    });

    test('br becomes a newline', () {
      expect(parseMarkdown('a<br>b<br/>c'), [
        p([t('a'), MdxLineBreak(), t('b'), MdxLineBreak(), t('c')]),
      ]);
    });

    test('HTML tags pair up even across Markdown emphasis', () {
      expect(parseMarkdown('<u>a **b**</u>'), [
        p([
          styled(MdxStyleKind.underline, [
            t('a '),
            styled(MdxStyleKind.strong, [t('b')]),
          ]),
        ]),
      ]);
    });

    test('img keeps width and height', () {
      expect(
        parseMarkdown('<img src="a.png" alt="A" width="100" height="50">'),
        [
          p([MdxImage(src: 'a.png', alt: 'A', width: 100, height: 50)]),
        ],
      );
    });

    test('HTML a restores entities in href', () {
      expect(parseMarkdown('x <a href="https://e.com/?a=1&amp;b=2">l</a>'), [
        p([
          t('x '),
          MdxLink(href: 'https://e.com/?a=1&b=2', children: [t('l')]),
        ]),
      ]);
    });

    test(
      'tags not in the allowlist are stripped, keeping only the content',
      () {
        expect(parseMarkdown('a <span class="x">red</span> b'), [
          p([t('a red b')]),
        ]);
      },
    );

    test('reads color and decoration from the style attribute', () {
      expect(
        parseMarkdown(
          '<span style="color: red; background-color: #ff0; '
          'font-weight: bold; text-decoration: underline">x</span>',
        ),
        [
          p([
            MdxSpan(
              MdxInlineStyle(
                color: 0xFFFF0000,
                backgroundColor: 0xFFFFFF00,
                bold: true,
                underline: true,
              ),
              [t('x')],
            ),
          ]),
        ],
      );
    });

    test('also reads font tag color and style on allowlisted tags', () {
      expect(
        parseMarkdown(
          '<font color="#00f">a</font> <b style="color:#0f0">b</b>',
        ),
        [
          p([
            MdxSpan(MdxInlineStyle(color: 0xFF0000FF), [t('a')]),
            t(' '),
            MdxSpan(MdxInlineStyle(color: 0xFF00FF00), [
              styled(MdxStyleKind.strong, [t('b')]),
            ]),
          ]),
        ],
      );
    });

    test('ignores uninterpretable style', () {
      expect(parseMarkdown('<span style="position: fixed">x</span>'), [
        p([t('x')]),
      ]);
    });

    test('comments are dropped', () {
      expect(parseMarkdown('a<!-- hidden -->b'), [
        p([t('ab')]),
      ]);
    });

    test('unclosed tags are closed at the end of the paragraph', () {
      expect(parseMarkdown('a <mark>b'), [
        p([
          t('a '),
          styled(MdxStyleKind.mark, [t('b')]),
        ]),
      ]);
    });

    test('HTML inside code is not interpreted', () {
      expect(parseMarkdown('`<sub>x</sub>`'), [
        p([
          styled(MdxStyleKind.code, [t('<sub>x</sub>')]),
        ]),
      ]);
    });
  });

  group('block HTML', () {
    test('details includes its Markdown content across blank lines', () {
      const source = '''
<details>
<summary>More <b>info</b></summary>

inner **bold**

- item

</details>

after
''';
      expect(parseMarkdown(source), [
        MdxDetails(
          summary: [
            t('More '),
            styled(MdxStyleKind.strong, [t('info')]),
          ],
          blocks: [
            p([
              t('inner '),
              styled(MdxStyleKind.strong, [t('bold')]),
            ]),
            MdxList(
              ordered: false,
              items: [
                MdxListItem([
                  p([t('item')]),
                ]),
              ],
            ),
          ],
        ),
        p([t('after')]),
      ]);
    });

    test('details without blank lines makes its content a paragraph', () {
      expect(parseMarkdown('<details><summary>S</summary>\nbody\n</details>'), [
        MdxDetails(
          summary: [t('S')],
          blocks: [
            p([t('body')]),
          ],
        ),
      ]);
    });

    test('a standalone img block becomes a paragraph', () {
      expect(parseMarkdown('<img src="a.png" width="40">'), [
        p([MdxImage(src: 'a.png', width: 40)]),
      ]);
    });

    test('unsupported block tags are shown as written', () {
      expect(parseMarkdown('<section>hello</section>'), [
        p([t('<section>hello</section>')]),
      ]);
    });
  });

  group('block HTML alignment and headings', () {
    test('applies p and div align to the paragraph', () {
      expect(
        parseMarkdown(
          '<p align="center">a <b>b</b></p>\n\n<div align="right">c</div>',
        ),
        [
          MdxParagraph([
            t('a '),
            styled(MdxStyleKind.strong, [t('b')]),
          ], align: MdxAlign.center),
          MdxParagraph([t('c')], align: MdxAlign.right),
        ],
      );
    });

    test('div align also applies to Markdown content across blank lines', () {
      expect(
        parseMarkdown('<div align="center">\n\n# T\n\ntext\n\n</div>\n\nafter'),
        [
          MdxHeading(1, [t('T')], align: MdxAlign.center),
          MdxParagraph([t('text')], align: MdxAlign.center),
          p([t('after')]),
        ],
      );
    });

    test('HTML heading tags become headings', () {
      expect(parseMarkdown('<h2 align="center">Title <i>x</i></h2>'), [
        MdxHeading(2, [
          t('Title '),
          styled(MdxStyleKind.emphasis, [t('x')]),
        ], align: MdxAlign.center),
      ]);
    });
  });

  group('HTML table', () {
    test('treats th rows as header and reads align', () {
      const source = '''
<table>
<tr><th align="center">H1</th><th>H2</th></tr>
<tr><td>a <b>b</b></td><td>c</td></tr>
</table>
''';
      expect(parseMarkdown(source), [
        MdxTable(
          alignments: [MdxAlign.center, null],
          header: [
            [t('H1')],
            [t('H2')],
          ],
          rows: [
            [
              [
                t('a '),
                styled(MdxStyleKind.strong, [t('b')]),
              ],
              [t('c')],
            ],
          ],
        ),
      ]);
    });

    test('reads tables with thead and tbody, and tables without a header', () {
      const source =
          '<table><tbody><tr><td>1</td><td>2</td></tr>'
          '<tr><td>3</td></tr></tbody></table>';
      expect(parseMarkdown(source), [
        MdxTable(
          alignments: [null, null],
          header: [],
          rows: [
            [
              [t('1')],
              [t('2')],
            ],
            [
              [t('3')],
            ],
          ],
        ),
      ]);
    });

    test('also takes in Markdown separated by blank lines inside cells', () {
      const source =
          '<table>\n<tr><td>\n\n**bold**\n\n</td></tr>\n</table>\n\nafter';
      expect(parseMarkdown(source), [
        MdxTable(
          alignments: [null],
          header: [],
          rows: [
            [
              [
                styled(MdxStyleKind.strong, [t('bold')]),
              ],
            ],
          ],
        ),
        p([t('after')]),
      ]);
    });
  });

  group('footnotes', () {
    test('references become superscript links, definitions become a numbered list at the end', () {
      expect(parseMarkdown('text[^1]\n\n[^1]: The **note**.'), [
        p([
          t('text'),
          styled(MdxStyleKind.superscript, [
            MdxLink(href: '#fn-1', children: [t('1')]),
          ]),
        ]),
        MdxThematicBreak(),
        MdxList(
          ordered: true,
          tight: false,
          items: [
            MdxListItem([
              p([
                t('The '),
                styled(MdxStyleKind.strong, [t('note')]),
                t('.'),
              ]),
            ]),
          ],
        ),
      ]);
    });
  });

  group('reference links', () {
    test('resolves links that reference a definition', () {
      expect(parseMarkdown('[a]\n\n[a]: https://a.example "T"'), [
        p([
          MdxLink(href: 'https://a.example', title: 'T', children: [t('a')]),
        ]),
      ]);
    });

    test('a definition with an unclosed <...> becomes plain text, not an exception', () {
      expect(parseMarkdown('[a]: <https://a.example'), [
        p([t('[a]: <https://a.example')]),
      ]);
    });
  });

  group('equality', () {
    test('the same input gives equal blocks', () {
      const source = '# A\n\ntext **b**\n\n- x\n- y';
      final first = parseMarkdown(source);
      final second = parseMarkdown(source);
      expect(first, second);
      expect(first.map((b) => b.hashCode), second.map((b) => b.hashCode));
    });

    test('different content is not equal', () {
      expect(
        parseMarkdown('text').single == parseMarkdown('text!').single,
        isFalse,
      );
    });
  });
}
