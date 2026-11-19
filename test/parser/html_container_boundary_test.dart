@TestOn('vm')
library;

import 'package:flutter_markdown_x/src/ir/nodes.dart';
import 'package:flutter_markdown_x/src/parser/incremental_parser.dart';
import 'package:flutter_markdown_x/src/parser/native/native_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Inputs where the chunk splitter and the Rust parser must agree on where an
/// HTML container ends.
const _incrementalCases = {
  'closing tag in inline code inside a quote': '<blockquote>\n\nWrite `</blockquote>` to end.\n\nstill quoted\n\n</blockquote>\n\nafter\n',
  'closing tag in inline code inside a list':
      '<ul>\n<li>a\n\nUse `</ul>` here\n\n<li>b\n</ul>\n\nafter\n',
  'inline closing tag inside a list paragraph':
      '<ul>\n<li>a\n\ntext and </ul> inline\n\n<li>b\n</ul>\n\nafter\n',
  'mismatched list closing tag': '<ul>\n<li>a\n</ol>\n\nafter\n\nmore\n',
};

void main() {
  group('incremental parse matches the whole-document parse', () {
    for (final MapEntry(key: name, value: source)
        in _incrementalCases.entries) {
      test(name, () {
        final full = parseNative(source);
        expect(
          IncrementalMarkdownParser(parse: parseNative).parse(source),
          full,
        );
        for (var end = 1; end <= source.length; end++) {
          final prefix = source.substring(0, end);
          expect(
            IncrementalMarkdownParser(parse: parseNative).parse(prefix),
            parseNative(prefix),
            reason: 'prefix $end',
          );
        }
      });
    }
  });

  group('HTML heading keeps block tags as inline content', () {
    test('blockquote inside h2', () {
      final blocks = parseNative('<h2>Title <blockquote>q</blockquote></h2>');
      expect(blocks, hasLength(1));
      expect(blocks.single, isA<MdxHeading>());
    });
    test('list inside h2', () {
      final blocks = parseNative('<h2><ul><li>x</li></ul></h2>');
      expect(blocks, hasLength(1));
      expect(blocks.single, isA<MdxHeading>());
    });
  });
}
