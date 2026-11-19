// VM only: uses the native parser (dart:ffi) and imports benchmark/ and example/, which are outside the test root that `flutter test --platform chrome` compiles.
@TestOn('vm')
library;

import 'package:flutter_markdown_x/src/parser/incremental_parser.dart';
import 'package:flutter_markdown_x/src/parser/native/native_parser.dart';
import 'package:flutter_markdown_x/src/ir/nodes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../benchmark/document.dart';
// example is a separate package, so it cannot be imported with package:.
// ignore: avoid_relative_lib_imports
import '../../example/lib/sample.dart';
import '../support/prefixes.dart';

/// Document collecting structures that are fragile at chunk boundaries.
const _tricky = '''
# Title

para one
still para one

- tight a
- tight b

- loose c

  continued c

1. one

2. two

> quote one

> quote two

```dart
void main() {

  print('blank line inside fence');
}
```

~~~
tilde fence

# not a heading
~~~

<details>
<summary>Sum</summary>

inside details

```
fence inside details

</details>
```

still inside

</details>

<!-- comment

spanning blank -->

| a | b |
|---|---|
| 1 | 2 |

    indented code

    more indented code

Setext
======

* * *

last para with H<sub>2</sub>O
''';

/// Document containing reference link definitions.
const _references = '''
# Refs

First [one] and [two][2] and [Missing].

[one]: https://one.example "One"

Second para with [one] again.

```
[code]: not-a-definition
```

- item with [two][2]

[2]: <https://two.example>
[one]: https://duplicate.example

last [one]
''';

// CommonMark 0.31.2 examples that exposed unsafe incremental boundaries.
const _commonMark180 = """<?php

  echo '>';

?>
okay
""";
const _commonMark194 = """[Foo*bar\\]]:my_(url) 'title (with parens)'

[Foo*bar\\]]
""";
const _commonMark541 = '''[Foo
  bar]: /url

[Baz][Foo bar]
''';
const _commonMark546 = '''[foo][ref[]

[ref[]: /uri
''';
const _commentedDiv = '''<div align="center">

<!-- </div> -->

one

two

</div>
''';
const _headingAcrossBlankLine = '<h1>one\n\ntwo</h1>\n';

void main() {
  group('splitChunks', () {
    test('splits blocks separated by blank lines', () {
      expect(splitChunks('# A\n\npara\n\n> q'), ['# A\n\n', 'para\n\n', '> q']);
    });

    test('concatenating restores the original string', () {
      expect(splitChunks(_tricky).join(), _tricky);
    });

    test('does not split at blank lines inside a fence', () {
      expect(splitChunks('```\na\n\nb\n```\n\nafter'), [
        '```\na\n\nb\n```\n\n',
        'after',
      ]);
    });

    test('does not split before list items', () {
      expect(splitChunks('- a\n\n- b\n\n  c\n\npara'), [
        '- a\n\n- b\n\n  c\n\n',
        'para',
      ]);
    });

    test('does not split inside details', () {
      expect(splitChunks('<details>\n\na\n\n</details>\n\nafter'), [
        '<details>\n\na\n\n</details>\n\n',
        'after',
      ]);
    });

    test('keeps HTML quotes and lists together across blank lines', () {
      for (final tag in ['blockquote', 'ul', 'ol', 'li']) {
        final html = '<$tag>\n\none\n\ntwo\n\n</$tag>\n\n';
        expect(splitChunks('${html}after'), [html, 'after'], reason: tag);
      }
    });

    test('resumes splitting after a list with omitted li end tags', () {
      const list = '<ul><li>one\n\n<li>two</ul>\n\n';
      expect(splitChunks('${list}after'), [list, 'after']);
    });

    test('does not split at blank lines inside an HTML heading', () {
      expect(splitChunks(_headingAcrossBlankLine), [_headingAcrossBlankLine]);
    });
  });

  // An incremental parse must match the result of parsing the whole document at once.
  _incrementalTests('Rust parser', parseNative);
}

void _incrementalTests(String name, List<MdxBlock> Function(String) parse) {
  IncrementalMarkdownParser create() => IncrementalMarkdownParser(parse: parse);

  group('IncrementalMarkdownParser ($name)', () {
    test('matches the whole-document parse even for fragile structures', () {
      expect(create().parse(_tricky), parse(_tricky));
    });

    test('defers ambiguous CommonMark boundary cases and tags in comments to the whole-document parse', () {
      for (final source in [
        _commonMark180,
        _commonMark194,
        _commonMark541,
        _commonMark546,
        _commentedDiv,
        _headingAcrossBlankLine,
      ]) {
        expect(create().parse(source), parse(source), reason: source);
      }
    });

    test(
      'matches the whole-document parse for every prefix of the problem cases',
      () {
        for (final source in [
          _commonMark180,
          _commonMark194,
          _commonMark541,
          _commonMark546,
          _commentedDiv,
          _headingAcrossBlankLine,
        ]) {
          final parser = create();
          for (final end in prefixEnds(source)) {
            final prefix = source.substring(0, end);
            Object? incrementalError;
            Object? fullError;
            List<MdxBlock>? incrementalResult;
            List<MdxBlock>? fullResult;
            try {
              incrementalResult = parser.parse(prefix);
            } catch (error) {
              incrementalError = error;
            }
            try {
              fullResult = parse(prefix);
            } catch (error) {
              fullError = error;
            }

            final reason = 'prefix length $end: $prefix';
            expect(
              incrementalError?.runtimeType,
              fullError?.runtimeType,
              reason: reason,
            );
            if (incrementalError == null && fullError == null) {
              expect(incrementalResult, fullResult, reason: reason);
            }
          }
        }
      },
    );

    test('matches the whole-document parse at every step when appending one character at a time', () {
      final parser = create();
      for (final end in prefixEnds(_tricky)) {
        final prefix = _tricky.substring(0, end);
        expect(
          parser.parse(prefix),
          parse(prefix),
          reason: 'prefix length $end',
        );
      }
    });

    test('matches on the benchmark document too', () {
      final source = buildDocument(5);
      expect(create().parse(source), parse(source));
    });

    test('unchanged blocks keep the same instance after appending', () {
      final parser = create();
      final before = parser.parse('# A\n\npara one\n\npara two');
      final after = parser.parse('# A\n\npara one\n\npara two more\n\nnew');

      expect(after, hasLength(4));
      expect(identical(after[0], before[0]), isTrue);
      expect(identical(after[1], before[1]), isTrue);
      expect(identical(after[2], before[2]), isFalse);
    });

    test('parses incrementally even with reference link definitions, with matching results', () {
      final parser = create();
      for (final end in prefixEnds(_references)) {
        final prefix = _references.substring(0, end);
        expect(
          parser.parse(prefix),
          parse(prefix),
          reason: 'prefix length $end',
        );
      }
    });

    test('reuses unchanged blocks even with reference link definitions', () {
      final parser = create();
      const source = 'see [ref]\n\nother\n\n[ref]: https://example.com';
      final before = parser.parse(source);
      final after = parser.parse('$source\n\nnew para');

      expect(after, parse('$source\n\nnew para'));
      expect(identical(after[0], before[0]), isTrue);
      expect(identical(after[1], before[1]), isTrue);
    });

    test('rebuilds referencing blocks when definitions increase', () {
      final parser = create();
      const first = 'see [a] and [b]\n\n[a]: https://a.example';
      const second = '$first\n[b]: https://b.example';
      parser.parse(first);
      expect(parser.parse(second), parse(second));
    });

    test('definition-only validation runs once when definitions change', () {
      const first = 'see [ref]\n\n[ref]: https://one.example';
      const second = '$first\n[other]: https://two.example';
      var validationCount = 0;
      final parser = IncrementalMarkdownParser(
        parse: (source) {
          if (source == '[ref]: https://one.example' ||
              source ==
                  '[ref]: https://one.example\n[other]: https://two.example') {
            validationCount++;
          }
          return parse(source);
        },
      );

      parser.parse(first);
      expect(validationCount, 1);
      parser.parse('$first\n\nappended');
      expect(validationCount, 1);
      parser.parse(second);
      expect(validationCount, 2);
    });

    test('invalid reference definition candidates also match the whole-document parse', () {
      final overlongLabelText = List.filled(1000, 'x').join();
      final overlongLabel = '[$overlongLabelText]: /url';
      final sources = [
        '[x]\n\n[ ]: /url', // whitespace-only label
        '[x]\n\n[]: /url', // empty label
        '[x]\n\n$overlongLabel', // CommonMark labels are limited to 999 chars
        '[x]\n\n[ref]: <bad destination>', // invalid angle destination
      ];
      for (final source in sources) {
        expect(create().parse(source), parse(source), reason: source);
      }
    });

    test('matches the whole-document parse when there are definitions that cannot be handled safely', () {
      const sources = [
        // Footnote numbers and the trailing list are determined by the whole document.
        'text[^1]\n\nmore\n\n[^1]: note',
        // Definition whose title continues on the next line.
        'see [a]\n\n[a]: https://a.example\n"Title"\n\nafter',
        // Definition inside a blockquote or list.
        'see [a]\n\n> [a]: https://a.example\n\nafter',
        'see [a]\n\n- [a]: https://a.example\n\nafter',
        // A continuation line of a paragraph is not a definition.
        'see [a]\n\npara\n[a]: https://a.example\n\nafter',
      ];
      for (final source in sources) {
        expect(create().parse(source), parse(source), reason: source);
      }
    });

    test(
      'matches when appending the example sample one character at a time',
      () {
        final parser = create();
        for (final end in prefixEnds(sampleMarkdown)) {
          final prefix = sampleMarkdown.substring(0, end);
          expect(
            parser.parse(prefix),
            parse(prefix),
            reason: 'prefix length $end',
          );
        }
      },
    );

    test('matches for text after a block hr, over every prefix', () {
      final noBlank = sampleMarkdown.replaceFirst('<hr>\n\n', '<hr>\n');
      expect(noBlank, isNot(sampleMarkdown));
      for (final source in [
        '<hr>\nfoo\n\n<p',
        '<hr>\nfoo\n\n<p>bar</p>',
        noBlank,
      ]) {
        final parser = create();
        for (final end in prefixEnds(source)) {
          final prefix = source.substring(0, end);
          expect(
            parser.parse(prefix),
            parse(prefix),
            reason: 'prefix length $end of ${source.length}',
          );
        }
      }
    });
  });
}
