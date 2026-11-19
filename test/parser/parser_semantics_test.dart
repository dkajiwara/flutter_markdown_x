// VM only: reads test/fixtures through dart:io, which a browser cannot do.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';

late List<Map<String, dynamic>> _examples;

Map<String, dynamic> _example(int id) =>
    _examples.singleWhere((example) => example['example'] == id);

void main() {
  setUpAll(() {
    final corpus = jsonDecode(
      File('test/fixtures/commonmark_0.31.2.json').readAsStringSync(),
    ) as List<dynamic>;
    _examples = corpus.cast<Map<String, dynamic>>();
  });

  test('example 6 retains tab columns in quoted indented code', () {
    final example = _example(6);
    expect(example['html'], contains('<pre><code>  foo\n'));

    final quote =
        parseMarkdown(example['markdown'] as String).single as MdxBlockquote;
    expect(quote.blocks.single, MdxCodeBlock('  foo'));
  });

  test('example 39 normalizes source breaks before decoding entities', () {
    final example = _example(39);
    expect(example['html'], contains('<p>foo\n\nbar</p>'));

    final paragraph =
        parseMarkdown(example['markdown'] as String).single as MdxParagraph;
    expect(paragraph.inlines, [MdxText('foo\n\nbar')]);
  });

  test('example 354 follows CommonMark asterisk delimiter rules', () {
    final example = _example(354);
    expect(example['html'], contains('<p>*£*bravo.</p>'));
    expect(example['html'], contains('<p>*€*charlie.</p>'));

    final blocks = parseMarkdown(example['markdown'] as String);
    expect(blocks, [
      MdxParagraph([MdxText('*\$*alpha.')]),
      MdxParagraph([MdxText('*£*bravo.')]),
      MdxParagraph([MdxText('*€*charlie.')]),
    ]);
  });

  test('currency exception leaves unrelated GFM asterisk emphasis intact', () {
    final expected = <int, List<MdxBlock>>{
      355: [
        MdxParagraph([
          MdxText('foo'),
          MdxStyled(MdxStyleKind.emphasis, [MdxText('bar')]),
        ]),
      ],
      356: [
        MdxParagraph([
          MdxText('5'),
          MdxStyled(MdxStyleKind.emphasis, [MdxText('6')]),
          MdxText('78'),
        ]),
      ],
      370: [
        MdxParagraph([
          MdxStyled(MdxStyleKind.emphasis, [MdxText('foo')]),
          MdxText('bar'),
        ]),
      ],
      381: [
        MdxParagraph([
          MdxText('foo'),
          MdxStyled(MdxStyleKind.strong, [MdxText('bar')]),
        ]),
      ],
      396: [
        MdxParagraph([
          MdxStyled(MdxStyleKind.strong, [MdxText('foo')]),
          MdxText('bar'),
        ]),
      ],
      411: [
        MdxParagraph([
          MdxStyled(MdxStyleKind.emphasis, [
            MdxText('foo'),
            MdxStyled(MdxStyleKind.strong, [MdxText('bar')]),
            MdxText('baz'),
          ]),
        ]),
      ],
      415: [
        MdxParagraph([
          MdxStyled(MdxStyleKind.emphasis, [
            MdxText('foo'),
            MdxStyled(MdxStyleKind.strong, [MdxText('bar')]),
          ]),
        ]),
      ],
      416: [
        MdxParagraph([
          MdxText('foo'),
          MdxStyled(MdxStyleKind.emphasis, [
            MdxStyled(MdxStyleKind.strong, [MdxText('bar')]),
          ]),
          MdxText('baz'),
        ]),
      ],
      417: [
        MdxParagraph([
          MdxText('foo'),
          MdxStyled(MdxStyleKind.strong, [
            MdxStyled(MdxStyleKind.strong, [
              MdxStyled(MdxStyleKind.strong, [MdxText('bar')]),
            ]),
          ]),
          MdxText('***baz'),
        ]),
      ],
      429: [
        MdxParagraph([
          MdxStyled(MdxStyleKind.strong, [
            MdxText('foo'),
            MdxStyled(MdxStyleKind.emphasis, [MdxText('bar')]),
            MdxText('baz'),
          ]),
        ]),
      ],
    };

    for (final entry in expected.entries) {
      expect(
        parseMarkdown(_example(entry.key)['markdown'] as String),
        entry.value,
        reason: 'CommonMark example ${entry.key}',
      );
    }
  });

  test('example 625 does not leak a multiline HTML comment into text', () {
    final example = _example(625);
    expect(example['html'], contains('<!-- this is a --\ncomment'));

    final paragraph =
        parseMarkdown(example['markdown'] as String).single as MdxParagraph;
    expect(paragraph.inlines, [MdxText('foo')]);
  });

  test('example 626 treats <!--> and <!---> as empty comments', () {
    final example = _example(626);
    expect(example['html'], contains('foo <!--> foo --&gt;'));
    expect(example['html'], contains('foo <!---> foo --&gt;'));

    expect(parseMarkdown(example['markdown']), [
      MdxParagraph([MdxText('foo  foo -->')]),
      MdxParagraph([MdxText('foo  foo -->')]),
    ]);
  });

  test('entity-escaped comment-like text remains visible', () {
    final paragraph =
        parseMarkdown('foo &lt;!-- visible --&gt; bar').single as MdxParagraph;
    expect(paragraph.inlines, [MdxText('foo <!-- visible --> bar')]);
  });

  test('examples 636 and 637 discard indentation after hard breaks', () {
    for (final id in [636, 637]) {
      final example = _example(id);
      expect(example['html'], contains('<br />\nbar'));

      final paragraph =
          parseMarkdown(example['markdown'] as String).single as MdxParagraph;
      expect(paragraph.inlines, [
        MdxText('foo'),
        MdxLineBreak(),
        MdxText('bar'),
      ], reason: 'CommonMark example $id');
    }
  });
}
