// VM only: reads test/fixtures through dart:io, which a browser cannot do.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/parity_expected.dart';
import '../support/prefixes.dart';

const _canonicalExampleIds = <int>{
  6,
  21,
  31,
  39,
  148,
  167,
  169,
  170,
  171,
  172,
  180,
  182,
  354,
  606,
  625,
  636,
  637,
};

void main() {
  test('remaining CommonMark examples match explicit canonical IR', () {
    final fixtureFile = File('test/fixtures/commonmark_0.31.2.json');
    expect(fixtureFile.existsSync(), isTrue);
    final fixture = jsonDecode(fixtureFile.readAsStringSync()) as List<dynamic>;
    final byId = {
      for (final example in fixture.cast<Map<String, dynamic>>())
        example['example'] as int: example['markdown'] as String,
    };
    expect(parityExpected.keys.toSet(), _canonicalExampleIds);

    for (final entry in parityExpected.entries) {
      final source = byId[entry.key];
      expect(
        source,
        isNotNull,
        reason: 'Missing CommonMark example ${entry.key}',
      );
      expect(
        parseMarkdown(source!),
        entry.value,
        reason: 'Canonical IR for CommonMark example ${entry.key}',
      );
    }
  });

  test('Parser accepts every prefix of reference-link edge cases', () {
    const sources = <String>[
      "<?php\n\n  echo '>';\n\n?>\nokay\n",
      "[Foo*bar\\]]:my_(url) 'title (with parens)'\n\n[Foo*bar\\]]\n",
      '[Foo\n  bar]: /url\n\n[Baz][Foo bar]\n',
      '[foo][ref[]\n\n[ref[]: /uri\n',
      '[foo\nbar\\',
      '> [foo\n> bar\\',
      '- [foo\n  bar\\',
      '<div align="center">\n\n<!-- </div> -->\n\none\n\ntwo\n\n</div>\n',
    ];

    for (final source in sources) {
      for (final end in prefixEnds(source)) {
        expect(
          () => parseMarkdown(source.substring(0, end)),
          returnsNormally,
          reason: 'prefix length $end of ${jsonEncode(source)}',
        );
      }
    }
  });

  test(
    'incomplete-label guard leaves fenced, indented, and inline code intact',
    () {
      const fenced = '```\n[code\\\n```\n\n[label\\';
      final fencedBlocks = parseMarkdown(fenced);
      expect((fencedBlocks.first as MdxCodeBlock).code, '[code\\');

      const indented = '    [code\\\n\n[label\\';
      final indentedBlocks = parseMarkdown(indented);
      expect((indentedBlocks.first as MdxCodeBlock).code, '[code\\');

      const inline = '`[code\\`\n[label\\';
      final inlineBlocks = parseMarkdown(inline);
      final paragraph = inlineBlocks.first as MdxParagraph;
      final code = paragraph.inlines.first as MdxStyled;
      expect((code.children.single as MdxText).text, '[code\\');
    },
  );

  test(
    'incomplete label on a continuation line does not split a paragraph',
    () {
      const source = 'opening paragraph\n[unfinished label\\';
      final blocks = parseMarkdown(source);
      expect(blocks, hasLength(1));
      expect(blocks.single, isA<MdxParagraph>());
    },
  );

  test('CommonMark 0.31.2 corpus has identical full and incremental IR', () {
    final fixture = File('test/fixtures/commonmark_0.31.2.json');
    expect(
      fixture.existsSync(),
      isTrue,
      reason: 'CommonMark corpus fixture is required',
    );
    final examples = jsonDecode(fixture.readAsStringSync()) as List<dynamic>;
    expect(examples, hasLength(652));

    final incremental = IncrementalMarkdownParser();
    for (final example in examples.cast<Map<String, dynamic>>()) {
      final source = example['markdown'] as String;
      expect(
        listEquals(incremental.parse(source), parseMarkdown(source)),
        isTrue,
        reason: 'Incremental example ${example['example']}',
      );
    }
  });

  test('normalized URL callback values', () {
    const sources = <String>[
      '[foo](/f&ouml;&ouml; "f&ouml;&ouml;")',
      '<foo@bar.example.com>',
      '<foo+special@Bar.baz-bar0.com>',
    ];
    MdxLink link(String source) =>
        (parseMarkdown(source).single as MdxParagraph).inlines.single
            as MdxLink;

    expect(link(sources[0]).href, '/f%C3%B6%C3%B6');
    expect(link(sources[0]).title, 'föö');
    expect(link(sources[1]).href, 'mailto:foo@bar.example.com');
    expect(link(sources[2]).href, 'mailto:foo+special@Bar.baz-bar0.com');
  });
}
