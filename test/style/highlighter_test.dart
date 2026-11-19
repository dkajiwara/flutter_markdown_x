import 'package:flutter_markdown_x/src/style/highlighter.dart';
import 'package:flutter_test/flutter_test.dart';

const _plain = MdxCodeTokenKind.plain;
const _keyword = MdxCodeTokenKind.keyword;
const _string = MdxCodeTokenKind.string;
const _comment = MdxCodeTokenKind.comment;
const _number = MdxCodeTokenKind.number;

/// Sequence of (kind, text) with whitespace-only plain tokens removed.
List<(MdxCodeTokenKind, String)> _tokens(String code, String language) => [
  for (final token in highlightCode(code, language)!)
    if (token.kind != _plain || token.text.trim().isNotEmpty)
      (token.kind, token.text.trim()),
];

void main() {
  test('returns null when the language is unspecified or unsupported', () {
    expect(highlightCode('a', null), isNull);
    expect(highlightCode('a', 'brainfuck'), isNull);
  });

  test('separates Dart keywords, strings, numbers and comments', () {
    expect(_tokens("final a = 'x'; // note\nreturn 42;", 'dart'), [
      (_keyword, 'final'),
      (_plain, 'a ='),
      (_string, "'x'"),
      (_plain, ';'),
      (_comment, '// note'),
      (_keyword, 'return'),
      (_number, '42'),
      (_plain, ';'),
    ]);
  });

  test('a keyword that is part of an identifier is not colored', () {
    expect(_tokens('finally classy', 'dart'), [
      (_keyword, 'finally'),
      (_plain, 'classy'),
    ]);
    expect(_tokens('finalValue', 'dart'), [(_plain, 'finalValue')]);
  });

  test('a comment marker inside a string is not a comment', () {
    expect(_tokens('"http://example.com"', 'js'), [
      (_string, '"http://example.com"'),
    ]);
  });

  test('multi-line comments and strings', () {
    expect(_tokens('/* a\n b */ x', 'ts'), [
      (_comment, '/* a\n b */'),
      (_plain, 'x'),
    ]);
    expect(_tokens('"""a\nb""" x', 'python'), [
      (_string, '"""a\nb"""'),
      (_plain, 'x'),
    ]);
  });

  test('Python and shell treat # as a comment', () {
    expect(_tokens('def f(): # c', 'py'), [
      (_keyword, 'def'),
      (_plain, 'f():'),
      (_comment, '# c'),
    ]);
    expect(_tokens('echo hi # c', 'bash').last, (_comment, '# c'));
  });

  test('SQL keywords are case-insensitive', () {
    expect(_tokens('select 1 -- c', 'sql'), [
      (_keyword, 'select'),
      (_number, '1'),
      (_comment, '-- c'),
    ]);
  });

  test('JSON literals and strings', () {
    expect(_tokens('{"a": true, "b": 1.5}', 'json'), [
      (_plain, '{'),
      (_string, '"a"'),
      (_plain, ':'),
      (_keyword, 'true'),
      (_plain, ','),
      (_string, '"b"'),
      (_plain, ':'),
      (_number, '1.5'),
      (_plain, '}'),
    ]);
  });

  test('concatenating tokens restores the original code', () {
    const samples = {
      'dart': "void main() {\n  final s = 'it\\'s'; /* x */ print(0x1F);\n}\n",
      'rust': "fn main<'a>() { let x: &'a str = \"a\"; } // c",
      'go': 'func main() { s := `raw\nstring` }',
      'yaml': 'key: "value" # c\nn: 10',
      'kotlin': 'val unterminated = "abc',
    };
    for (final MapEntry(key: language, value: code) in samples.entries) {
      final tokens = highlightCode(code, language)!;
      expect(tokens.map((t) => t.text).join(), code, reason: language);
    }
  });
}
