import 'package:flutter_markdown_x/src/style/highlighter.dart';
import 'package:flutter_test/flutter_test.dart';

const _keyword = MdxCodeTokenKind.keyword;
const _string = MdxCodeTokenKind.string;
const _comment = MdxCodeTokenKind.comment;
const _number = MdxCodeTokenKind.number;

void main() {
  group('additional languages', () {
    const samples = {
      'php': r'<?php echo "a"; // c',
      'html': '<a href="x">y</a> <!-- c -->',
      'xml': '<a b="c"/>',
      'svg': '<svg a="1"/>',
      'css': 'a { color: #fff; /* c */ }',
      'scss': 'a { b: 1px; }',
      'diff': '+added\n-removed\n@@ -1 +1 @@',
      'patch': '+a',
      'markdown': '# title\n`code` **bold**',
      'md': '# t',
      'lua': 'local x = 1 -- c',
      'dockerfile': 'FROM a\nRUN b # c',
      'ini': '[a]\nb = 1 ; c',
      'scala': 'val x = 1',
      'perl': r'my $x = 1; # c',
      'r': 'x <- 1 # c',
      'powershell': 'Write-Host "a" # c',
      'ps1': r'param($a)',
      'graphql': 'query { a }',
      'objc': '@interface A',
      'cmake': 'set(a 1) # c',
      'makefile': 'a: b # c',
    };
    for (final entry in samples.entries) {
      test(
        '${entry.key} highlights it and concatenating tokens restores the source',
        () {
          final tokens = highlightCode(entry.value, entry.key);
          expect(tokens, isNotNull);
          expect(tokens!.map((t) => t.text).join(), entry.value);
        },
      );
    }

    test('diff colors added and removed lines', () {
      final tokens = highlightCode('+a\n-b\n c', 'diff')!;
      expect(tokens.where((t) => t.kind == _string).single.text, '+a');
      expect(tokens.where((t) => t.kind == _keyword).single.text, '-b');
    });

    test('html separates tags, attribute values and comments', () {
      final tokens = highlightCode('<a href="x"><!-- c --></a>', 'html')!;
      expect(tokens.any((t) => t.kind == _keyword && t.text == '<a'), isTrue);
      expect(tokens.any((t) => t.kind == _string && t.text == '"x"'), isTrue);
      expect(
        tokens.any((t) => t.kind == _comment && t.text == '<!-- c -->'),
        isTrue,
      );
    });

    test('css separates color values and numbers with units', () {
      final tokens = highlightCode('a { color: #fff; margin: 4px; }', 'css')!;
      expect(tokens.any((t) => t.kind == _number && t.text == '#fff'), isTrue);
      expect(tokens.any((t) => t.kind == _number && t.text == '4px'), isTrue);
    });

    test('markdown separates headings and code', () {
      final tokens = highlightCode('# title\nx `c`', 'md')!;
      expect(
        tokens.any((t) => t.kind == _keyword && t.text == '# title'),
        isTrue,
      );
      expect(tokens.any((t) => t.kind == _string && t.text == '`c`'), isTrue);
    });
  });

  group('performance', () {
    const languages = [
      'dart',
      'python',
      'sql',
      'html',
      'css',
      'php',
      'markdown',
      'diff',
      'shell',
      'json',
      'lua',
      'rust',
      'ini',
    ];
    final nasty = <String>[
      'a' * 200000,
      '"' * 100000,
      "'" * 100000,
      '/*' * 50000,
      '<!--' * 30000,
      '<' * 100000,
      '"\\' * 50000,
      '1.' * 50000,
      '0x' * 50000,
      '`' * 100000,
      '#' * 100000,
      '*' * 100000,
      ' ' * 100000,
      '+' * 100000,
      '[' * 100000,
    ];
    for (final language in languages) {
      test('$language: does not backtrack even on one long line', () {
        final watch = Stopwatch()..start();
        for (final input in nasty) {
          final tokens = highlightCode(input, language);
          expect(tokens!.map((t) => t.text).join(), input);
        }
        expect(watch.elapsedMilliseconds, lessThan(2000));
      });
    }
  });
}
