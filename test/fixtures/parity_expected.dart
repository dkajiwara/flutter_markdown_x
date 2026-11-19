import 'package:flutter_markdown_x/src/ir/nodes.dart';

/// Canonical (golden) IR expectations for the remaining CommonMark examples,
/// asserted against the Rust parser (test/parser/ir_golden_test.dart).
///
/// Raw HTML follows the converter's behavior: inline style handling is scoped
/// to a paragraph, unsupported containers lose their tags but retain text, and
/// each source LF in ordinary raw text becomes one space. The package does not
/// promise browser-equivalent handling of raw HTML blocks.
final Map<int, List<MdxBlock>> parityExpected = {
  // The spec HTML code payload retains the two spaces after the blockquote.
  6: [
    MdxBlockquote([MdxCodeBlock('  foo')]),
  ],
  // Current converter keeps the serialized raw HTML href and discards its LF.
  21: [
    MdxParagraph([MdxLink(href: r'/bar\/)', children: [])]),
  ],
  31: [
    MdxParagraph([MdxLink(href: '&ouml;&ouml;.html', children: [])]),
  ],
  // Numeric reference LFs are decoded content and remain literal linefeeds.
  39: [
    MdxParagraph([MdxText('foo\n\nbar')]),
  ],
  148: [
    MdxTable(
      alignments: [null],
      header: [],
      rows: [
        [
          [
            MdxText('**Hello**,'),
            MdxLineBreak(),
            MdxStyled(MdxStyleKind.emphasis, [MdxText('world')]),
            MdxText('.'),
          ],
        ],
      ],
    ),
  ],
  // HTML block wrappers are paragraph-scoped; inner Markdown emphasis remains.
  167: [
    MdxParagraph([
      MdxStyled(MdxStyleKind.emphasis, [MdxText('foo')]),
    ]),
  ],
  // <pre> is a literal code block (inner tags stripped, no highlighting);
  // the first and last newline of its content are dropped.
  169: [
    MdxCodeBlock(
      'import Text.HTML.TagSoup\n\nmain :: IO ()\nmain = print \$ parseTags tags',
    ),
    MdxParagraph([MdxText('okay')]),
  ],
  // <script> and <style> are dropped together with their content.
  170: [
    MdxParagraph([MdxText('okay')]),
  ],
  // <textarea> content is literal text: a code block with no Markdown parsing.
  171: [MdxCodeBlock('\n*foo*\n\n_bar_\n')],
  172: [
    MdxParagraph([MdxText('okay')]),
  ],
  180: [
    MdxParagraph([MdxText("<?php  echo '>';  ?>")]),
    MdxParagraph([MdxText('okay')]),
  ],
  182: [
    MdxParagraph([
      MdxText(
        '<![CDATA[ function matchwo(a,b) { if (a < b && a < 0) then { return 1;  } else {  return 0; } } ]]>',
      ),
    ]),
    MdxParagraph([MdxText('okay')]),
  ],
  // Spec HTML confirms these currency-adjacent delimiter runs are literal.
  354: [
    MdxParagraph([MdxText('*\$*alpha.')]),
    MdxParagraph([MdxText('*£*bravo.')]),
    MdxParagraph([MdxText('*€*charlie.')]),
  ],
  // The escaped email autolink remains escaped plain text, not a link.
  606: [
    MdxParagraph([MdxText('<foo+@bar.example.com>')]),
  ],
  // Comments are invisible in rendered package output.
  625: [
    MdxParagraph([MdxText('foo')]),
  ],
  636: [
    MdxParagraph([MdxText('foo'), MdxLineBreak(), MdxText('bar')]),
  ],
  637: [
    MdxParagraph([MdxText('foo'), MdxLineBreak(), MdxText('bar')]),
  ],
};
