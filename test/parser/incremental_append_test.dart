// append fast path: a pure append resumes from the previous scan state, and the result
// must always match parsing the full text.
//
// VM only: uses the native parser (dart:ffi) and imports benchmark/ and example/, which are outside the test root that `flutter test --platform chrome` compiles.
@TestOn('vm')
library;

import 'dart:math';

import 'package:flutter_markdown_x/src/parser/incremental_parser.dart';
import 'package:flutter_markdown_x/src/parser/native/native_parser.dart';
import 'package:flutter_markdown_x/src/ir/nodes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../benchmark/document.dart';
// ignore: avoid_relative_lib_imports
import '../../example/lib/sample.dart';
import '../support/prefixes.dart';

const _fenceAndHtml = '''
# Title

para one
still para one

```dart
void main() {

  print('blank line inside fence');
}
```

<details>
<summary>Sum</summary>

inside details

</details>

- a

- b

  continued

> quote

| a | b |
|---|---|
| 1 | 2 |

last para with **bold** and *emph* and [link](https://x.example) text
''';

const _references = '''
# Refs

First [one] and [two][2] and [Missing].

[one]: https://one.example "One"

Second para with [one] again.

- item with [two][2]

[2]: <https://two.example>

last [one]
''';

const _footnotes = '''
Text with a note[^1] and another[^b].

middle paragraph

more text

[^1]: First note.

[^b]: Second note
    with continuation.
''';

const _comments = '''
<div align="center">

<!-- </div> -->

one

two

</div>

<?php

echo '>';

?>
tail paragraph
''';

final _documents = <String, String>{
  'fence/html/list/table': _fenceAndHtml,
  'reference definitions': _references,
  'footnotes': _footnotes,
  'comments and php': _comments,
  'benchmark': buildDocument(6),
  'sample': sampleMarkdown,
};

void main() {
  _appendTests('Rust parser', parseNative);
  _workTests();
}

void _appendTests(String name, List<MdxBlock> Function(String) parse) {
  IncrementalMarkdownParser create() => IncrementalMarkdownParser(parse: parse);

  List<MdxBlock> reference(String source, {required bool streaming}) =>
      create().parse(source, streaming: streaming);

  group('append fast path ($name)', () {
    for (final streaming in [false, true]) {
      for (final MapEntry(key: label, value: document) in _documents.entries) {
        test(
          '$label: matches the full text when appending random-sized chunks (streaming=$streaming)',
          () {
            final random = Random(label.hashCode ^ (streaming ? 1 : 0));
            for (var trial = 0; trial < 4; trial++) {
              final parser = create();
              var end = 0;
              while (end < document.length) {
                end = min(document.length, end + 1 + random.nextInt(40));
                final prefix = document.substring(0, end);
                expect(
                  parser.parse(prefix, streaming: streaming),
                  reference(prefix, streaming: streaming),
                  reason: '$label prefix $end (trial $trial)',
                );
              }
            }
          },
        );
      }
    }

    test('matches when appending one character at a time (small document, both streaming modes)', () {
      for (final streaming in [false, true]) {
        for (final document in [_footnotes, _references, _comments]) {
          final parser = create();
          for (final end in prefixEnds(document)) {
            final prefix = document.substring(0, end);
            expect(
              parser.parse(prefix, streaming: streaming),
              reference(prefix, streaming: streaming),
              reason: 'streaming=$streaming prefix $end',
            );
          }
        }
      }
    });

    test('streams and reuses finalized blocks around nested HTML lists', () {
      const document =
          '# Intro\n\n<blockquote>\n\n<ol start="3">\n'
          '<li>first\n\n<ul><li>nested</li></ul>\n\n</li>\n'
          '<li>second</li>\n</ol>\n\n</blockquote>';
      for (final streaming in [false, true]) {
        final parser = create();
        final heading = parser.parse('# Intro\n\n', streaming: streaming).first;
        for (final end in prefixEnds(document)) {
          if (end < '# Intro\n\n'.length) continue;
          final prefix = document.substring(0, end);
          expect(
            parser.parse(prefix, streaming: streaming),
            reference(prefix, streaming: streaming),
            reason: 'prefix $end',
          );
        }
        final result = parser.parse('$document\n\nafter', streaming: streaming);
        expect(result.first, same(heading));
        expect(parser.reusedBlockPrefix, greaterThan(0));
        expect((result[1] as MdxBlockquote).blocks.single, isA<MdxList>());
        expect(result, parse('$document\n\nafter'));
      }
    });

    test('matches when alternating appends with mid-text edits, shrinking and full replacement', () {
      final parser = create();
      final sources = <String>[
        _fenceAndHtml.substring(0, 120),
        _fenceAndHtml.substring(0, 180),
        // Edit in the middle.
        '${_fenceAndHtml.substring(0, 20)}X${_fenceAndHtml.substring(21, 200)}',
        // Shrink.
        _fenceAndHtml.substring(0, 60),
        _fenceAndHtml,
        // Replace everything.
        _references,
        '$_references\nappended',
        '',
        _footnotes,
        '$_footnotes\n\nmore',
      ];
      for (final source in sources) {
        expect(
          parser.parse(source),
          reference(source, streaming: false),
          reason: source,
        );
      }
    });

    test('an append reuses the instances of finalized blocks', () {
      final parser = create();
      final source = buildDocument(30);
      final before = parser.parse(source);
      final after = parser.parse('$source\n\nappended paragraph\n');
      expect(parser.reusedBlockPrefix, greaterThanOrEqualTo(before.length - 1));
      for (var i = 0; i < parser.reusedBlockPrefix; i++) {
        expect(identical(after[i], before[i]), isTrue, reason: 'block $i');
      }
    });

    test('a non-append update gives reusedBlockPrefix of 0', () {
      final parser = create();
      parser.parse('# A\n\none\n\ntwo');
      parser.parse('# B\n\none\n\ntwo');
      expect(parser.reusedBlockPrefix, 0);
    });
  });
}

/// Counts that the work per append does not grow in proportion to document size.
void _workTests() {
  group('append work (operation count)', () {
    const appendCount = 60;

    /// Appends [appendCount] times to a document with [sections] sections, and
    /// returns the maximum per append of (characters scanned, characters passed to parse).
    ({int scanned, int parsed, int length}) measure(
      int sections, {
      bool streaming = false,
    }) {
      final parser = IncrementalMarkdownParser(parse: parseNative);
      var source = buildDocument(sections);
      parser.parse(source, streaming: streaming);
      var worstScanned = 0;
      var worstParsed = 0;
      for (var i = 0; i < appendCount; i++) {
        source += 'Appended paragraph $i with **bold** text.\n\n';
        final scanned = parser.debugScannedChars;
        final parsed = parser.debugParsedChars;
        parser.parse(source, streaming: streaming);
        worstScanned = max(worstScanned, parser.debugScannedChars - scanned);
        worstParsed = max(worstParsed, parser.debugParsedChars - parsed);
      }
      return (
        scanned: worstScanned,
        parsed: worstParsed,
        length: source.length,
      );
    }

    for (final streaming in [false, true]) {
      test(
        'scan and parse work does not grow when the document becomes 20 times larger (streaming=$streaming)',
        () {
          final small = measure(20, streaming: streaming);
          final large = measure(400, streaming: streaming);
          expect(large.length, greaterThan(small.length * 15));
          // Only the appended paragraph (about 45 characters) and the trailing chunk are targeted.
          expect(small.scanned, lessThan(500));
          expect(large.scanned, lessThan(500));
          expect(large.scanned, lessThanOrEqualTo(small.scanned + 100));
          expect(small.parsed, lessThan(500));
          expect(large.parsed, lessThanOrEqualTo(small.parsed + 100));
        },
      );
    }

    test(
      'rebuilds all chunks when reference link definitions increase (fallback)',
      () {
        final parser = IncrementalMarkdownParser(parse: parseNative);
        final source =
            '${buildDocument(50)}\nsee [a]\n\n[a]: https://a.example\n';
        parser.parse(source);
        final before = parser.debugParsedChars;
        parser.parse('$source[b]: https://b.example\n');
        expect(
          parser.debugParsedChars - before,
          greaterThan(source.length ~/ 2),
        );
      },
    );
  });
}
