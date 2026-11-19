import 'dart:math';

import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_markdown_x/math.dart';
import 'package:flutter_markdown_x/src/extensions/math_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/prefixes.dart';
import '../support/selection_harness.dart';

final _insideArea = find.descendant(
  of: find.byType(SelectionArea),
  matching: find.byType(RichText),
);

/// Parses [source] with the math extension.
List<MdxBlock> _ir(
  String source, {
  bool streaming = false,
  List<MarkdownXExtension>? extensions,
}) => IncrementalMarkdownParser().parse(
  source,
  extensions: extensions ?? [markdownXMathExtension],
  streaming: streaming,
);

/// Collects math inlines in the IR, in order of appearance.
List<MdxCustomInline> _inlineMath(List<MdxBlock> blocks) {
  final out = <MdxCustomInline>[];
  void inline(MdxInline i) {
    switch (i) {
      case MdxCustomInline() when i.type == 'math':
        out.add(i);
      case MdxStyled():
        i.children.forEach(inline);
      case MdxLink():
        i.children.forEach(inline);
      case MdxSpan():
        i.children.forEach(inline);
      case _:
        break;
    }
  }

  void block(MdxBlock b) {
    switch (b) {
      case MdxParagraph():
        b.inlines.forEach(inline);
      case MdxHeading():
        b.inlines.forEach(inline);
      case MdxBlockquote():
        b.blocks.forEach(block);
      case MdxList():
        for (final item in b.items) {
          item.blocks.forEach(block);
        }
      case MdxTable():
        for (final c in b.header) {
          c.forEach(inline);
        }
        for (final row in b.rows) {
          for (final cell in row) {
            cell.forEach(inline);
          }
        }
      case MdxDetails():
        b.summary.forEach(inline);
        b.blocks.forEach(block);
      case MdxCustomBlock():
        b.inlines.forEach(inline);
        b.blocks.forEach(block);
      case _:
        break;
    }
  }

  blocks.forEach(block);
  return out;
}

List<MdxCustomBlock> _blockMath(List<MdxBlock> blocks) => [
  for (final b in blocks)
    if (b is MdxCustomBlock && b.type == 'math') b,
];

/// Concatenates the text that did not become math (or surrounds it).
String _plain(List<MdxBlock> blocks) {
  final buf = StringBuffer();
  void inline(MdxInline i) {
    switch (i) {
      case MdxText():
        buf.write(i.text);
      case MdxLineBreak():
        buf.write('\n');
      case MdxStyled():
        i.children.forEach(inline);
      case MdxLink():
        i.children.forEach(inline);
      case MdxSpan():
        i.children.forEach(inline);
      case MdxCustomInline():
        buf.write('<math:${i.attributes['tex']}>');
      case _:
        break;
    }
  }

  for (final b in blocks) {
    switch (b) {
      case MdxParagraph():
        b.inlines.forEach(inline);
      case MdxHeading():
        b.inlines.forEach(inline);
      case MdxCustomBlock():
        buf.write('<mathblock:${b.attributes['tex']}>');
      case _:
        break;
    }
  }
  return buf.toString();
}

/// String form of the whole IR. Used to look for leaked markers.
String _dump(List<MdxBlock> blocks) => blocks.toString();

List<String> _texes(String source) => [
  for (final m in _inlineMath(_ir(source))) m.attributes['tex']!,
];

void main() {
  group('inline delimiters', () {
    test(r'$...$', () {
      final m = _inlineMath(_ir(r'a $x+y$ b'));
      expect(m, hasLength(1));
      expect(m.single.attributes['tex'], 'x+y');
      expect(m.single.attributes['display'], 'false');
      expect(m.single.attributes['raw'], r'$x+y$');
    });

    test(r'\(...\)', () {
      final m = _inlineMath(_ir(r'a \(x+y\) b'));
      expect(m, hasLength(1));
      expect(m.single.attributes['tex'], 'x+y');
      expect(m.single.attributes['display'], 'false');
      expect(m.single.attributes['raw'], r'\(x+y\)');
    });

    test('surrounding text stays and math becomes one inline', () {
      expect(_plain(_ir(r'before $x$ after')), 'before <math:x> after');
      expect(_plain(_ir(r'前 $x$ 後 \(y\) 末')), '前 <math:x> 後 <math:y> 末');
    });

    test('detects math adjacent to Japanese text', () {
      expect(_texes(r'式$x^2$は二次です'), ['x^2']);
      expect(_texes(r'式\(x^2\)は二次です'), ['x^2']);
    });

    test(
      'detects inside emphasis, headings, tables, lists, quotes and links',
      () {
        expect(_texes(r'**太字 $a$**'), ['a']);
        expect(_texes(r'*$a$*'), ['a']);
        expect(_texes('# 見出し \$a\$'), ['a']);
        expect(_texes('| h |\n|---|\n| \$a|b\$ |'), ['a|b']);
        expect(_texes('- 項目 \$a\$\n- 二つ目 \$b\$'), ['a', 'b']);
        expect(_texes('> 引用 \$a\$'), ['a']);
        expect(_texes(r'[リンク $a$](https://example.com)'), ['a']);
        expect(
          _texes('<details>\n<summary>\$a\$</summary>\n\n\$b\$\n</details>'),
          ['a', 'b'],
        );
      },
    );

    test('detects several in one paragraph', () {
      expect(_texes(r'$a$ と $b$ と $c$'), ['a', 'b', 'c']);
      // Adjacent math forms consecutive escaped code spans, so the second is not math.
      expect(_texes(r'$a$$b$'), ['a']);
      expect(_texes(r'$a$ $b$'), ['a', 'b']);
    });

    test('spans a line break within a paragraph', () {
      final m = _inlineMath(_ir('a \$x\n+ y\$ b'));
      expect(m, hasLength(1));
      expect(m.single.attributes['tex'], 'x\n+ y');
    });

    test('does not span a blank line', () {
      expect(_texes('a \$x\n\ny\$ b'), isEmpty);
      expect(_texes('a \\(x\n\ny\\) b'), isEmpty);
      expect(_blockMath(_ir('\$\$\nx\n\ny\n\$\$')), isEmpty);
    });
  });

  group('TeX content is intact (not broken by CommonMark)', () {
    final cases = <String, String>{
      r'$x_1 + y_2$': 'x_1 + y_2',
      r'$a*b*c$': 'a*b*c',
      r'$a * b * c$': 'a * b * c',
      r'$a**b**c$': 'a**b**c',
      r'$\alpha_{i}$': r'\alpha_{i}',
      r'$\{x\}$': r'\{x\}',
      r'$a\\b$': r'a\\b',
      r'$\begin{pmatrix}a\\b\end{pmatrix}$':
          r'\begin{pmatrix}a\\b\end{pmatrix}',
      r'$a<b>c$': 'a<b>c',
      r'$a&amp;b$': 'a&amp;b',
      r'$\text{A `b` C}$': r'\text{A `b` C}',
      r'$a|b$': 'a|b',
      r'$100\%$': r'100\%',
      r'$\$5$': r'\$5',
      r'$[a](b)$': '[a](b)',
      r'$\text{日本語}$': r'\text{日本語}',
      r'\(x_1 * y_2\)': 'x_1 * y_2',
      r'\(a\\b\)': r'a\\b',
      r'\(\{x\}\)': r'\{x\}',
      r'\(\alpha_1\)': r'\alpha_1',
    };
    for (final entry in cases.entries) {
      test(entry.key, () {
        expect(_texes('x ${entry.key} y'), [entry.value]);
      });
    }

    test(r'display keeps \\, _ and *', () {
      final b = _blockMath(_ir('\$\$\nx_1 * y_2 \\\\\n\\{z\\}\n\$\$'));
      expect(b, hasLength(1));
      expect(b.single.attributes['tex'], 'x_1 * y_2 \\\\\n\\{z\\}');
      expect(b.single.attributes['display'], 'true');
    });
  });

  group('block delimiters', () {
    test(r'$$...$$ written on one line', () {
      final blocks = _ir(r'$$E = mc^2$$');
      expect(blocks, hasLength(1));
      final b = blocks.single as MdxCustomBlock;
      expect(b.type, 'math');
      expect(b.attributes['tex'], 'E = mc^2');
      expect(b.attributes['display'], 'true');
      expect(b.attributes['raw'], r'$$E = mc^2$$');
    });

    test(r'multiple lines with $$ on its own line', () {
      final b = _blockMath(_ir('\$\$\na = b\nc = d\n\$\$'));
      expect(b.single.attributes['tex'], 'a = b\nc = d');
    });

    test(r'\[...\] becomes a block', () {
      final b = _blockMath(_ir('\\[\nx^2\n\\]'));
      expect(b.single.attributes['tex'], 'x^2');
      expect(b.single.attributes['display'], 'true');
      expect(_blockMath(_ir(r'\[x^2\]')).single.attributes['tex'], 'x^2');
    });

    test('is distinguished from surrounding paragraphs', () {
      final blocks = _ir('前の段落\n\n\$\$x\$\$\n\n後の段落');
      expect(blocks, hasLength(3));
      expect(blocks[0], isA<MdxParagraph>());
      expect(blocks[1], isA<MdxCustomBlock>());
      expect(blocks[2], isA<MdxParagraph>());
    });

    test(r'$$ mid-paragraph becomes a display inline', () {
      final blocks = _ir(r'文 $$x$$ 文');
      expect(blocks.single, isA<MdxParagraph>());
      final m = _inlineMath(blocks);
      expect(m.single.attributes['display'], 'true');
    });

    test('block math inside lists and quotes', () {
      final quote = _ir('> \$\$x\$\$').single as MdxBlockquote;
      expect(quote.blocks.single, isA<MdxCustomBlock>());
      final list = _ir('- \$\$x\$\$').single as MdxList;
      expect(list.items.single.blocks.single, isA<MdxCustomBlock>());
    });

    test('multiple lines inside a quote', () {
      final quote = _ir('> \$\$\n> a\n> b\n> \$\$').single as MdxBlockquote;
      final b = quote.blocks.single as MdxCustomBlock;
      expect(b.attributes['tex'], 'a\nb');
    });

    test('a document without math keeps its structure', () {
      const source = '# 見出し\n\n段落 **強調**\n\n- a\n- b\n';
      expect(_ir(source), _ir(source, extensions: const []));
    });

    test('a paragraph with only inline math does not become a block', () {
      expect(_ir(r'$x$').single, isA<MdxParagraph>());
    });
  });

  group('distinguishing from currency signs (pandoc rules)', () {
    final notMath = <String>[
      r'$5 and $10',
      r'costs $5.',
      r'costs $5. and $10.',
      r'US$10',
      r'US$10 to US$20',
      r'$ x $',
      r'$ x$',
      r'$x $',
      r'$',
      r'$$',
      r'$$ $$',
      r'$ $',
      r'about $20, maybe $30 more',
      r'コストは$5と$10です',
      r'値段は\$5と\$10',
      r'\$x\$',
      r'$5 for 3 and $7 for 4',
      r'$1,000 and $2,000',
      r'$x',
      r'x$',
    ];
    for (final source in notMath) {
      test('not math: $source', () {
        final blocks = _ir(source);
        expect(_inlineMath(blocks), isEmpty);
        expect(_blockMath(blocks), isEmpty);
      });
    }

    test(r'an escaped \$ becomes a literal $', () {
      expect(_plain(_ir(r'\$x\$')), r'$x$');
      expect(_plain(_ir(r'価格は\$5')), r'価格は$5');
    });

    final isMath = <String, String>{
      r'$x$': 'x',
      r'$x$.': 'x',
      r'($x$)': 'x',
      r'$2^n$': '2^n',
      r'$5$': '5',
      r'$x$ and $y$': 'x',
      r'とても$x$です': 'x',
    };
    for (final entry in isMath.entries) {
      test('becomes math: ${entry.key}', () {
        expect(_texes(entry.key).first, entry.value);
      });
    }

    test('currency and math in the same paragraph', () {
      expect(_texes(r'It costs $5 and $x$ is a var'), ['x']);
      expect(
        _plain(_ir(r'It costs $5 and $x$ is a var')),
        'It costs \$5 and <math:x> is a var',
      );
    });

    test(r'a closing $ followed by a digit does not close', () {
      expect(_texes(r'$a$1'), isEmpty);
      expect(_texes(r'$x$ $y$1'), ['x']);
    });

    test(r'no whitespace rule applies to $$', () {
      expect(_blockMath(_ir(r'$$ x $$')).single.attributes['tex'], 'x');
      expect(_blockMath(_ir('\$\$\nx\n\$\$')), hasLength(1));
    });

    test(r'\( \) and \[ \] are detected regardless of currency', () {
      expect(_texes(r'\( x \)'), ['x']);
    });
  });

  group('regions left untouched', () {
    test('inside inline code', () {
      final blocks = _ir(r'`$x$` と ``$y$``');
      expect(_inlineMath(blocks), isEmpty);
      expect(_plain(blocks), r'$x$ と $y$');
    });

    test('inside a code block', () {
      for (final source in [
        '```\n\$x\$\n\$\$y\$\$\n```',
        '~~~tex\n\$x\$\n~~~',
        '    \$x\$',
        '- a\n\n  ```\n  \$x\$\n  ```',
        '> ```\n> \$x\$\n> ```',
      ]) {
        final blocks = _ir(source);
        expect(_inlineMath(blocks), isEmpty, reason: source);
        expect(_blockMath(blocks), isEmpty, reason: source);
      }
    });

    test('link href, autolink, URL and inline HTML', () {
      expect(_texes(r'[a](https://example.com/$x$/y)'), isEmpty);
      expect(_texes(r'<https://example.com/$x$>'), isEmpty);
      expect(_texes(r'https://example.com/a$b$c'), isEmpty);
      expect(_texes(r'<span title="$x$">t</span>'), isEmpty);
      expect(_texes('[ref]: https://example.com/\$x\$\n\n[ref]'), isEmpty);
    });

    test('image alt', () {
      expect(_texes(r'![alt $x$](https://example.com/a.png)'), isEmpty);
    });

    test('detects math after a code block', () {
      expect(_texes('```\n\$x\$\n```\n\n\$y\$'), ['y']);
    });

    test('does not break right next to a code span', () {
      expect(_texes(r'`a` $x$ `b`'), ['x']);
    });

    test(
      'math adjacent to a backtick is not math (to avoid breaking code spans)',
      () {
        expect(_texes(r'`$x$'), isEmpty);
        expect(_plain(_ir(r'$x$` y')), r'$x$` y');
      },
    );
  });

  group('does not break on false positives', () {
    String codeOf(List<MdxBlock> blocks) {
      final out = StringBuffer();
      void block(MdxBlock b) {
        switch (b) {
          case MdxCodeBlock():
            out.write(b.code);
          case MdxList():
            for (final item in b.items) {
              item.blocks.forEach(block);
            }
          case MdxBlockquote():
            b.blocks.forEach(block);
          case _:
            break;
        }
      }

      blocks.forEach(block);
      return out.toString();
    }

    test('indented code block inside a list', () {
      final blocks = _ir('- a\n\n      \$x\$\n');
      expect(_inlineMath(blocks), isEmpty);
      expect(codeOf(blocks), contains(r'$x$'));
      expect(codeOf(blocks), isNot(contains(mathMarker)));
    });

    test('indented code block inside a quote', () {
      final blocks = _ir('>     \$x\$\n');
      expect(_inlineMath(blocks), isEmpty);
      expect(codeOf(blocks), contains(r'$x$'));
      expect(codeOf(blocks), isNot(contains(mathMarker)));
    });

    test('restores the original text even if an escape remains in a code block (safety net)', () {
      final protected = protectMath(r'a $x_1$ b');
      final blocks = applyMarkdownXExtensions(
        [MdxCodeBlock(protected)],
        [markdownXMathExtension],
      );
      expect((blocks.single as MdxCodeBlock).code, r'a $x_1$ b');
    });

    test('image alt keeps the original text', () {
      final blocks = _ir(r'![alt $x_1$ と \(y\)](https://example.com/a.png)');
      final image = (blocks.single as MdxParagraph).inlines.single as MdxImage;
      expect(image.alt, r'alt $x_1$ と (y)');
      expect(_inlineMath(blocks), isEmpty);
    });

    test('escapes do not leak into heading slugs and TOC text', () {
      final blocks = _ir('# 見出し \$a_1\$ です\n\n## 二つ目');
      final headings = markdownXHeadings(blocks);
      expect(headings.first.text, isNot(contains(mathMarker)));
      expect(headings.first.text, contains('a_1'));
      expect(headings.first.id, isNot(contains('uE000')));
    });

    test('math inside a footnote definition', () {
      final blocks = _ir('文[^1]\n\n[^1]: 説明 \$x_1\$');
      expect(_texes('文[^1]\n\n[^1]: 説明 \$x_1\$'), ['x_1']);
      expect(_plain(blocks), isNot(contains(mathMarker)));
    });

    test('no escape marker remains in any IR', () {
      for (final source in [
        '- a\n\n      \$x\$',
        '>     \$x\$',
        '![\$x\$](u)',
        '| \$a|b\$ |\n|---|\n| \$c\$ |',
        '[^1]: \$x\$\n\n文[^1]',
        '<details><summary>\$a\$</summary>\n\n\$b\$\n</details>',
        '<span>\$a\$</span>',
        '<div>\$a\$</div>',
        '<p align="center">\$a_1\$</p>',
      ]) {
        expect(_dump(_ir(source)), isNot(contains(mathMarker)), reason: source);
      }
    });
  });

  group('without an extension', () {
    test('math stays plain text', () {
      final blocks = _ir(r'a $x$ b', extensions: const []);
      expect(_plain(blocks), r'a $x$ b');
    });
  });

  group('wiring', () {
    test('MarkdownXExtension.transformSource is applied once per chunk', () {
      final seen = <String>[];
      final ext = MarkdownXExtension(
        transformSource: (source, {required streaming}) {
          seen.add(source);
          return source;
        },
      );
      final parser = IncrementalMarkdownParser();
      parser.parse('a\n\nb\n\nc', extensions: [ext]);
      expect(seen.toSet(), {'a\n\n', 'b\n\n', 'c'});
      seen.clear();
      parser.parse('a\n\nb\n\nc!', extensions: [ext]);
      expect(seen, ['c!']);
    });

    test('full parse and per-chunk parse match', () {
      const doc =
          'A \$x_1\$\n\n\$\$\na\n\\\\\nb\n\$\$\n\n- \$5 and \$10\n\n'
          '```\n\$no\$\n```\n\n\\(y*z\\) と \$w\$\n\n| a |\n|---|\n| \$p|q\$ |\n';
      final chunked = _ir(doc);
      final whole = applyMarkdownXExtensions(
        parseMarkdown(
          applyMarkdownXSourceTransforms(doc, [markdownXMathExtension]),
        ),
        [markdownXMathExtension],
      );
      expect(chunked, whole);
    });

    test('the same input reuses the same chunk instance', () {
      final parser = IncrementalMarkdownParser();
      final a = parser.parse(
        'x \$a\$\n\ny',
        extensions: [markdownXMathExtension],
      );
      final b = parser.parse(
        'x \$a\$\n\ny!',
        extensions: [markdownXMathExtension],
      );
      expect(identical(a.first, b.first), isTrue);
    });
  });

  group('random input', () {
    // Arrange delimiters, escapes, code, tables and quotes randomly and check properties.
    const atoms = [
      r'$',
      r'$$',
      r'\',
      r'\(',
      r'\)',
      r'\[',
      r'\]',
      '_',
      '*',
      '`',
      '``',
      '|',
      '\n',
      '\n\n',
      ' ',
      'a',
      '1',
      '5',
      '>',
      '- ',
      '<b>',
      '](',
      '日本',
    ];
    final random = Random(14);
    final inputs = [
      for (var n = 0; n < 400; n++)
        [
          for (var k = random.nextInt(24) + 1; k > 0; k--)
            atoms[random.nextInt(atoms.length)],
        ].join(),
    ];

    test('throws no exception and escaped source has paired backticks', () {
      for (final input in inputs) {
        for (final streaming in [false, true]) {
          final out = protectMath(input, streaming: streaming);
          // The escaped span's delimiter length differs from every backtick run in the source.
          final runs = {
            for (final m in RegExp('`+').allMatches(input)) m[0]!.length,
          };
          for (final m in RegExp('(`+)$mathMarker[mp]').allMatches(out)) {
            expect(runs, isNot(contains(m[1]!.length)), reason: input);
          }
        }
      }
    });

    test(
      'per-chunk results match the IR of parsing the transformed full text',
      () {
        var compared = 0;
        for (final input in inputs) {
          // Definitions (`]:`) span chunks. Also exclude parser differences unrelated to math.
          if (input.contains(']:')) continue;
          final whole = parseMarkdown(input);
          if (_ir(input, extensions: const []).toString() != whole.toString()) {
            continue;
          }
          final expected = applyMarkdownXExtensions(
            parseMarkdown(
              applyMarkdownXSourceTransforms(input, [markdownXMathExtension]),
            ),
            [markdownXMathExtension],
          );
          expect(_ir(input), expected, reason: input.replaceAll('\n', '⏎'));
          compared++;
        }
        expect(compared, greaterThan(200));
      },
    );

    test('payload encode and decode are inverse', () {
      for (final input in inputs) {
        expect(decodeMathPayload(encodeMathPayload(input)), input);
        expect(encodeMathPayload(input), isNot(contains('`')));
        expect(encodeMathPayload(input), isNot(contains('\n')));
        expect(encodeMathPayload(input), isNot(contains('|')));
      }
    });
  });

  group('streaming', () {
    List<MdxBlock> s(String source) => _ir(source, streaming: true);

    test(r'an unclosed $x stays literal (indistinguishable from currency)', () {
      final blocks = s(r'値は $x_1 + y');
      expect(_inlineMath(blocks), isEmpty);
      expect(_plain(blocks), contains(r'$x_1 + y'));
    });

    test(r'becomes math once closed', () {
      expect(_texes(r'値は $x_1$'), ['x_1']);
      expect(_inlineMath(s(r'値は $x_1$')), hasLength(1));
    });

    test(r'an unclosed $$ becomes a pending block', () {
      final blocks = s('前\n\n\$\$\na_1 +');
      final b = blocks.last as MdxCustomBlock;
      expect(b.type, 'math');
      expect(b.attributes['pending'], 'true');
      expect(b.attributes['tex'], 'a_1 +');
      // The raw `$$` marker is not emitted as text.
      expect(_plain(blocks), isNot(contains(r'$$')));
    });

    test(r'an unclosed \[ becomes a pending block', () {
      final b = s('\\[\nx^2 +').single as MdxCustomBlock;
      expect(b.attributes['pending'], 'true');
    });

    test(r'an unclosed \( becomes a pending inline', () {
      final m = _inlineMath(s(r'a \(x_1 +'));
      expect(m.single.attributes['pending'], 'true');
    });

    test('streaming: false does not repair', () {
      final blocks = _ir('\$\$\na_1 +');
      expect(_blockMath(blocks), isEmpty);
      expect(blocks.single, isA<MdxParagraph>());
    });

    test('a complete document yields the same IR with streaming', () {
      for (final source in [
        r'a $x$ b',
        '\$\$\nx\n\$\$',
        r'It costs $5 and $10',
        '\\[x\\]',
      ]) {
        expect(s(source), _ir(source), reason: source);
      }
    });

    test('math does not leak when one parser is reused', () {
      const doc =
          '先頭の \$a_1\$\n\n\$\$\nx_1 \\\\\ny_2\n\$\$\n\n後ろ \$b\$ と `c` と \$5 and \$6\n\n\\[z^2\\] と \\(w\\)';
      final parser = IncrementalMarkdownParser();
      for (final n in prefixEnds(doc)) {
        final prefix = doc.substring(0, n);
        final shared = parser.parse(
          prefix,
          extensions: [markdownXMathExtension],
          streaming: true,
        );
        expect(shared, _ir(prefix, streaming: true), reason: 'n=$n');
      }
      final done = parser.parse(doc, extensions: [markdownXMathExtension]);
      expect(done, _ir(doc));
    });

    test(r'does not pollute the cache even when hiding a trailing unclosed backtick yields math', () {
      final parser = IncrementalMarkdownParser();
      final partial = parser.parse(
        '\$x\$`',
        extensions: [markdownXMathExtension],
        streaming: true,
      );
      expect(_inlineMath(partial), hasLength(1));
      final done = parser.parse(r'$x$', extensions: [markdownXMathExtension]);
      expect(_inlineMath(done), hasLength(1));
      expect(done, _ir(r'$x$'));
    });

    test('earlier finalized blocks do not change across prefixes', () {
      const doc =
          '先頭の段落 \$a_1\$\n\n\$\$\nx_1 \\\\\ny_2\n\$\$\n\n後ろ \$b\$ と \$5 and \$6 です\n\n'
          '\\[z^2\\] と \\(w\\)';
      MdxBlock? firstOf(String p) {
        final blocks = s(p);
        return blocks.isEmpty ? null : blocks.first;
      }

      final expectedFirst = firstOf(doc);
      final firstEnd = doc.indexOf('\n\n') + 2;
      for (final n in prefixEnds(doc).where((n) => n > firstEnd)) {
        expect(firstOf(doc.substring(0, n)), expectedFirst, reason: 'n=$n');
      }
    });

    test(
      'no exception on any prefix and raw delimiters do not leak outside math',
      () {
        const doc =
            '先頭 \$a_1 + b\$ と \\(c\\) です。\n\n\$\$\nx_1 \\\\\ny_2\n\$\$\n\n'
            '\\[z^2\\]\n\n| a |\n|---|\n| \$p\$ |\n\n- \$q\$\n';
        for (final n in prefixEnds(doc)) {
          final prefix = doc.substring(0, n);
          final blocks = s(prefix);
          final plain = _plain(blocks);
          // `$$` is never emitted as text even before it closes (it becomes a pending block).
          expect(plain, isNot(contains(r'$$')), reason: 'n=$n: $prefix');
          expect(plain, isNot(contains(r'\[')), reason: 'n=$n: $prefix');
        }
      },
    );
  });

  group('widget', () {
    Widget app(
      String data, {
      MarkdownXMath? math,
      bool streaming = false,
      double scale = 1.0,
      double width = 400,
      bool selectable = false,
    }) {
      final m = math ?? MarkdownXMath();
      final body = MarkdownBody(
        data: data,
        streaming: streaming,
        extensions: [m.extension],
        inlineBuilder: m.inlineBuilder,
        blockBuilder: m.blockBuilder,
      );
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: selectable ? SelectionArea(child: body) : body,
              ),
            ),
          ),
        ),
      );
    }

    Widget fake(
      BuildContext context,
      String tex, {
      required bool display,
      required TextStyle style,
    }) => Container(
      key: ValueKey('${display ? 'D' : 'I'}:$tex'),
      width: 40,
      height: 20,
      color: Colors.blue,
    );

    testWidgets('builder renders inline and block math', (tester) async {
      final calls = <String>[];
      final math = MarkdownXMath(
        builder: (context, tex, {required display, required style}) {
          calls.add('${display ? 'D' : 'I'}:$tex');
          return fake(context, tex, display: display, style: style);
        },
      );
      await tester.pumpWidget(
        app('文 \$x^2\$ 文\n\n\$\$\\int f\$\$', math: math),
      );
      expect(find.byKey(const ValueKey('I:x^2')), findsOneWidget);
      expect(find.byKey(const ValueKey(r'D:\int f')), findsOneWidget);
      expect(calls, containsAll(['I:x^2', r'D:\int f']));
    });

    testWidgets('builder receives the surrounding text style', (tester) async {
      TextStyle? seen;
      final math = MarkdownXMath(
        builder: (context, tex, {required display, required style}) {
          seen = style;
          return const SizedBox(width: 10, height: 10);
        },
      );
      await tester.pumpWidget(app('# 見出し \$x\$', math: math));
      expect(seen, isNotNull);
      // The heading font size is passed (larger than body text).
      expect(seen!.fontSize, greaterThan(16));
    });

    testWidgets(
      'without a builder, shows the TeX source in monospace (inline)',
      (tester) async {
        await tester.pumpWidget(app('文 \$x^2\$ 文'));
        expect(
          find.textContaining(r'$x^2$', findRichText: true),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'without a builder, shows the TeX source in monospace (block)',
      (tester) async {
        await tester.pumpWidget(app('\$\$\na^2 + b^2\n\$\$'));
        final finder = find.textContaining('a^2 + b^2');
        expect(finder, findsOneWidget);
        final text = tester.widget<Text>(finder);
        final family = text.style?.fontFamily;
        final fallback = text.style?.fontFamilyFallback;
        expect(family != null || (fallback?.isNotEmpty ?? false), isTrue);
        expect(text.data, contains(r'$$'));
      },
    );

    testWidgets('shows the source when only the extension is passed', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownBody(
              data: '文 \$x\$ 文\n\n\$\$y\$\$',
              extensions: [markdownXMathExtension],
            ),
          ),
        ),
      );
      expect(find.textContaining(r'$x$', findRichText: true), findsOneWidget);
      expect(find.textContaining(r'$$y$$', findRichText: true), findsOneWidget);
    });

    testWidgets('block math scrolls horizontally when it exceeds the width', (
      tester,
    ) async {
      final math = MarkdownXMath(
        builder: (context, tex, {required display, required style}) =>
            const SizedBox(key: ValueKey('wide'), width: 1000, height: 20),
      );
      await tester.pumpWidget(app('\$\$x\$\$', math: math, width: 300));
      expect(tester.takeException(), isNull);
      final scrollable = find.byType(SingleChildScrollView);
      expect(scrollable, findsOneWidget);
      expect(
        tester.widget<SingleChildScrollView>(scrollable).scrollDirection,
        Axis.horizontal,
      );
      expect(tester.getSize(find.byKey(const ValueKey('wide'))).width, 1000);
      // Does not exceed the parent's width.
      expect(tester.getSize(scrollable).width, lessThanOrEqualTo(300));
      await tester.drag(scrollable, const Offset(-200, 0));
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('wide'))).dx,
        lessThan(0),
      );
    });

    testWidgets('block math is centered when there is spare width', (
      tester,
    ) async {
      final math = MarkdownXMath(builder: fake);
      await tester.pumpWidget(app('\$\$x\$\$', math: math, width: 400));
      final box = tester.getRect(find.byKey(const ValueKey('D:x')));
      expect(box.center.dx, closeTo(200, 1));
    });

    Widget textBuilder(
      BuildContext context,
      String tex, {
      required bool display,
      required TextStyle style,
    }) => Text(tex, key: ValueKey('t:$tex'), style: style);

    testWidgets('follows textScaler (inline, builder returning Text)', (
      tester,
    ) async {
      final math = MarkdownXMath(builder: textBuilder);
      await tester.pumpWidget(app('文 \$x\$ 文', math: math, scale: 1));
      final base = tester.getSize(find.byKey(const ValueKey('t:x'))).height;
      await tester.pumpWidget(app('文 \$x\$ 文', math: math, scale: 2));
      final scaled = tester.getSize(find.byKey(const ValueKey('t:x'))).height;
      // Doubles, and is not applied twice (4x).
      expect(scaled, closeTo(base * 2, base * 0.2));
    });

    testWidgets('follows textScaler (block, builder returning Text)', (
      tester,
    ) async {
      final math = MarkdownXMath(builder: textBuilder);
      await tester.pumpWidget(app('\$\$x\$\$', math: math, scale: 1));
      final base = tester.getSize(find.byKey(const ValueKey('t:x'))).height;
      await tester.pumpWidget(app('\$\$x\$\$', math: math, scale: 2));
      final scaled = tester.getSize(find.byKey(const ValueKey('t:x'))).height;
      expect(scaled, closeTo(base * 2, base * 0.2));
    });

    testWidgets(
      'the style fontSize passed to the builder is the value before text scale is applied',
      (tester) async {
        final sizes = <double?>[];
        final math = MarkdownXMath(
          builder: (context, tex, {required display, required style}) {
            sizes.add(style.fontSize);
            return const SizedBox();
          },
        );
        await tester.pumpWidget(
          app('文 \$x\$\n\n\$\$y\$\$', math: math, scale: 1),
        );
        final base = List.of(sizes);
        expect(base, hasLength(2));
        sizes.clear();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          app('文 \$x\$\n\n\$\$y\$\$', math: math, scale: 2),
        );
        expect(sizes, base);
      },
    );

    testWidgets('the semantics label is the TeX source', (tester) async {
      final handle = tester.ensureSemantics();
      final math = MarkdownXMath(builder: fake);
      await tester.pumpWidget(
        app('文 \$x^2\$ 文\n\n\$\$\\sum_i a_i\$\$', math: math),
      );
      expect(find.bySemanticsLabel(r'\sum_i a_i'), findsOneWidget);
      // The inline label is read aloud chained with the surrounding text as one paragraph label.
      expect(find.bySemanticsLabel(RegExp(r'文\s+x\^2\s+文')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('selecting and copying block math yields TeX with delimiters', (
      tester,
    ) async {
      final probe = ClipboardProbe();
      mockClipboard(tester, probe);
      final math = MarkdownXMath(builder: fake);
      await tester.pumpWidget(
        app('前\n\n\$\$a_1\$\$\n\n後', math: math, selectable: true),
      );
      await tester.pumpAndSettle();
      final copied = await selectAllAndCopy(tester, probe, _insideArea);
      expect(copied, '前\n\$\$a_1\$\$\n後');
    });

    testWidgets(
      'selecting and copying inline math yields TeX with delimiters',
      (tester) async {
        final probe = ClipboardProbe();
        mockClipboard(tester, probe);
        final math = MarkdownXMath(builder: fake);
        await tester.pumpWidget(
          app('値は \$x_1\$ です', math: math, selectable: true),
        );
        await tester.pumpAndSettle();
        final copied = await selectAllAndCopy(tester, probe, _insideArea);
        expect(copied, '値は \$x_1\$ です');
      },
    );

    testWidgets('the same text is copied without a builder (source display)', (
      tester,
    ) async {
      final probe = ClipboardProbe();
      mockClipboard(tester, probe);
      await tester.pumpWidget(
        app('値は \$x_1\$ です\n\n\$\$y\$\$', selectable: true),
      );
      await tester.pumpAndSettle();
      final copied = await selectAllAndCopy(tester, probe, _insideArea);
      expect(copied, '値は \$x_1\$ です\n\$\$y\$\$');
    });

    testWidgets(
      'math written with \\( \\) is copied with the delimiters as written',
      (tester) async {
        final probe = ClipboardProbe();
        mockClipboard(tester, probe);
        final math = MarkdownXMath(builder: fake);
        await tester.pumpWidget(
          app(r'値は \(x\) です', math: math, selectable: true),
        );
        await tester.pumpAndSettle();
        final copied = await selectAllAndCopy(tester, probe, _insideArea);
        expect(copied, r'値は \(x\) です');
      },
    );

    testWidgets('no selection Widget is created outside SelectionArea', (
      tester,
    ) async {
      final math = MarkdownXMath(builder: fake);
      await tester.pumpWidget(app('\$\$x\$\$', math: math));
      expect(find.byType(SelectionContainer), findsNothing);
    });

    testWidgets(
      'a streaming pending block shows the source without calling the builder',
      (tester) async {
        var called = 0;
        final math = MarkdownXMath(
          builder: (context, tex, {required display, required style}) {
            called++;
            return const SizedBox();
          },
        );
        await tester.pumpWidget(
          app('\$\$\na_1 +', math: math, streaming: true),
        );
        expect(called, 0);
        expect(find.textContaining('a_1 +'), findsOneWidget);
        expect(find.textContaining(r'$$'), findsNothing);
        await tester.pumpWidget(
          app('\$\$\na_1 + b\$\$', math: math, streaming: false),
        );
        expect(called, 1);
      },
    );

    testWidgets('composes with other inlineBuilders (null for non-math)', (
      tester,
    ) async {
      final math = MarkdownXMath(builder: fake);
      final result = math.inlineBuilder(
        _FakeContext.of(tester),
        MdxText('a'),
        const TextStyle(),
        () => const TextSpan(text: 'default'),
      );
      expect(result, isNull);
    });

    testWidgets('currency does not become math and is shown as is', (
      tester,
    ) async {
      final math = MarkdownXMath(builder: fake);
      await tester.pumpWidget(app(r'It costs $5 and $10.', math: math));
      expect(find.byType(Container), findsNothing);
      expect(
        find.textContaining(r'It costs $5 and $10.', findRichText: true),
        findsOneWidget,
      );
    });
  });
}

class _FakeContext {
  static BuildContext of(WidgetTester tester) => tester.binding.rootElement!;
}
