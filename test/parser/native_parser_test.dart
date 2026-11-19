// Verifies calls to the Rust parser (FFI) and IR handoff.
//
// The build hook bundles the native parser binary from `prebuilt/`. If there is no
// binary for this environment, the tests fail rather than skip (`sh tool/build_native.sh`).
//
// VM only: calls the native parser over dart:ffi, which does not exist on the web; the web parser is covered by test/parser/web_wasm_test.dart.
@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_markdown_x/src/parser/native/bindings.dart';
import 'package:flutter_markdown_x/src/parser/native/ir_decoder.dart';
import 'package:flutter_markdown_x/src/parser/native/native_parser.dart';
import 'package:flutter_markdown_x/src/ir/nodes.dart';
import 'package:flutter_markdown_x/src/parser/incremental_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../benchmark/document.dart';
// example is a separate package, so it cannot be imported with package:.
// ignore: avoid_relative_lib_imports
import '../../example/lib/sample.dart';

/// Inputs for which full and incremental parses must return the same result.
const _sources = <String, String>{
  'empty document': '',
  'headings and paragraph': '# Title\n\nHello\n\n###### small',
  'setext heading': 'Title\n=====\n\nSub\n---',
  'emphasis': '**b** *i* ~~s~~ `c` ***bi***',
  'link and image': '[link](https://example.com "T") ![alt](a.png "T")',
  'autolink': '<https://example.com>',
  'soft break and hard break': 'a\nb  \nc\\\nd',
  'fenced code block': '```dart\nfinal a = 1 < 2 && true;\n```',
  'code block without language': '```\nplain\n```',
  'indented code block': '    indented\n    code',
  'blockquote': '> quote\n> **b**\n>\n> second',
  'horizontal rule': 'a\n\n---\n\nb',
  'nested list': '- a\n  - b\n    1. c\n- d',
  'loose list': '- a\n\n- b\n\n  continued',
  'ordered list': '3. a\n4. b',
  'task list': '- [ ] todo\n- [x] done',
  'code block in list': '- item\n\n  ```\n  code\n  ```',
  'table': '| a | b | c |\n|:--|:-:|--:|\n| 1 | **2** | `3` |',
  'symbols': '1 < 2 & 3 > 2 "q" &amp; &copy;',
  'inline HTML decoration':
      'H<sub>2</sub>O x<sup>2</sup> <kbd>Ctrl</kbd> <mark>m</mark>',
  'br': 'a<br>b<br/>c<br />d',
  'HTML spans emphasis': '<u>a **b**</u> and **<i>c</i>**',
  'HTML img': 'x <img src="a.png" alt="A" width="100" height="50"> y',
  'HTML a': 'x <a href="https://e.com/?a=1&amp;b=2" title="t">l</a>',
  'unknown tag': 'a <span class="x">red</span> b',
  'comment': 'a<!-- hidden -->b',
  'unclosed tag': 'a <mark>b',
  'unmatched closing tag': 'a </b> c',
  'HTML in code': '`<sub>x</sub>` and ``a ` b``',
  'details':
      '<details>\n<summary>More <b>info</b></summary>\n\n'
      'inner **bold**\n\n- item\n\n</details>\n\nafter',
  'details without blank lines':
      '<details><summary>S</summary>\nbody\n</details>',
  'unclosed details': '<details>\n<summary>S</summary>\n\nbody',
  'standalone img block': '<img src="a.png" width="40">',
  'unknown block tag': '<section>hello &lt;b&gt;</section>',
  'style attribute':
      '<span style="color: red; background-color: #ff0; font-weight: bold; '
      'text-decoration: underline line-through; font-size: 12.5px; '
      'font-style: italic">x</span>',
  'style color formats':
      '<span style="color:#0f08">a</span><span style="color:rgb(1, 2, 3)">b'
      '</span><span style="color:rgba(1,2,3,0.5)">c</span>'
      '<span style="color:#11223344">d</span>',
  'font tag and style on allowlisted tags':
      '<font color="#00f">a</font> <b style="color:#0f0">b</b>',
  'uninterpretable style':
      '<span style="position: fixed; color: nope">x</span>',
  'p and div align':
      '<p align="center">a <b>b</b></p>\n\n<div align="right">c</div>',
  'div align applies to Markdown':
      '<div align="center">\n\n# T\n\ntext\n\n</div>\n\nafter',
  'center tag': '<center>mid</center>',
  'HTML heading': '<h2 align="center">Title <i>x</i></h2>\n\n<h4>plain</h4>',
  'HTML table':
      '<table>\n<tr><th align="center">H1</th><th>H2</th></tr>\n'
      '<tr><td>a <b>b</b></td><td>c</td></tr>\n</table>',
  'table with thead and tbody':
      '<table><tbody><tr><td>1</td><td>2</td></tr>'
      '<tr><td>3</td></tr></tbody></table>',
  'Markdown in cell':
      '<table>\n<tr><td>\n\n**bold**\n\n</td></tr>\n</table>\n\nafter',
  'footnote': 'text[^1] and[^b]\n\n[^b]: second **note**.\n\n[^1]: first.',
  'multiple references to one footnote': 'a[^x] b[^x]\n\n[^x]: note',
  'footnote without definition': 'a[^none] b',
  'reference link': '[a] and [b][a] and [c][]\n\n[a]: https://a.example "T"',
  'bare URL': 'see https://example.com/a_b?q=1&r=2. Next',
  'www URL': 'see www.example.com, and (www.example.org/a(b))',
  'around URL':
      'xhttps://no.example *https://yes.example* `c`https://x.example',
  'URL in emphasis': '**https://example.com/path** and _http://a.example_',
  'URL in link': '[https://example.com](https://other.example)',
  'email address': 'mail foo.bar+baz@example.co.jp now, not a@b or a@b.c-',
  'URL in Japanese text': '詳細は https://example.com/日本語 を参照。',
  'entity-like tail': 'https://example.com/?a=1&amp; x',
  'nested blockquote and list': '> - a\n>   - b\n> text',
  'image with empty alt': '![](a.png)',
  'fence with info string': '```dart title="x"\ncode\n```',
  'HTML in heading': '# A <kbd>K</kbd>',
};

void main() {
  group('native parser', () {
    test('usable in this environment', () {
      expect(
        isNativeParserAvailable,
        isTrue,
        reason:
            'native parser is unavailable: $nativeParserUnavailableReason '
            '(build it with sh tool/build_native.sh)',
      );
    });

    for (final MapEntry(key: name, value: source) in _sources.entries) {
      test('full parse matches incremental parse: $name', () {
        expect(IncrementalMarkdownParser().parse(source), parseNative(source));
      });
    }

    test('matches on the benchmark document too', () {
      final source = buildDocument(20);
      expect(parseNative(source), isNotEmpty);
      expect(IncrementalMarkdownParser().parse(source), parseNative(source));
    });

    test('matches on the example sample too', () {
      expect(parseNative(sampleMarkdown), isNotEmpty);
      expect(
        IncrementalMarkdownParser().parse(sampleMarkdown),
        parseNative(sampleMarkdown),
      );
    });

    test('passes non-ASCII characters and emoji correctly', () {
      const source = '# 見出し 🎉\n\n日本語の **強調** と `コード` と é';
      final blocks = parseNative(source);
      expect((blocks.first as MdxHeading).inlines, [MdxText('見出し 🎉')]);
      expect(
        ((blocks[1] as MdxParagraph).inlines.last as MdxText).text,
        ' と é',
      );
    });
  });

  group('native ABI and IR', () {
    test('probe has no reason', () {
      expect(nativeParserUnavailableReason, isNull);
    });

    test('ABI version and IR version are as expected', () {
      expect(mdx_abi_version(), expectedMdxAbiVersion);
      expect(mdx_ir_version(), mdxIrVersion);
    });

    test('build info includes crate name, version, ABI and IR', () {
      final info = mdx_build_info().cast<Utf8>().toDartString();
      expect(info, startsWith('mdx_native '));
      expect(info, endsWith(' abi=$expectedMdxAbiVersion ir=$mdxIrVersion'));
      expect(nativeParserBuildInfo, info);
    });

    test('IR starts with a magic and version header', () {
      final bytes = parseNativeToBytes('# t');
      expect(bytes.sublist(0, 4), 'MDXI'.codeUnits);
      expect(ByteData.sublistView(bytes).getUint32(4, Endian.little), 6);
    });

    test('task items carry the UTF-16 offset of their marker', () {
      const source = '日本 😀\n\n- [ ] a\n- [x] b\n';
      final list = parseNative(source).last as MdxList;
      expect(list.items[0].markerOffset, source.indexOf('[ ]'));
      expect(list.items[1].markerOffset, source.indexOf('[x]'));
    });

    test('mdx_parse treats a null out_len and a null source as failures', () {
      final out = malloc<Size>()..value = 99;
      try {
        expect(mdx_parse(nullptr, 5, out), nullptr);
        expect(out.value, 0);
      } finally {
        malloc.free(out);
      }
      final source = malloc<Uint8>(1);
      try {
        expect(mdx_parse(source, 1, nullptr), nullptr);
      } finally {
        malloc.free(source);
      }
    });

    test('rejects every prefix of a real IR and restores the whole', () {
      final bytes = parseNativeToBytes(sampleMarkdown);
      expect(decodeIr(bytes), parseNative(sampleMarkdown));
      for (var length = 0; length < bytes.length; length++) {
        expect(
          () => decodeIr(Uint8List.sublistView(bytes, 0, length)),
          throwsA(isA<MdxIrFormatException>()),
          reason: 'prefix $length/${bytes.length}',
        );
      }
      expect(
        () => decodeIr(Uint8List.fromList([...bytes, 0])),
        throwsA(isA<MdxIrFormatException>()),
      );
    });

    test(
      'corrupting any byte of a real IR leaks only MdxIrFormatException',
      () {
        final bytes = parseNativeToBytes('# T\n\n- [x] a\n\n| a |\n|-|\n| b |');
        for (var index = 0; index < bytes.length; index++) {
          for (final value in [0, 1, 7, 0x7f, 0x80, 0xff]) {
            final broken = Uint8List.fromList(bytes)..[index] = value;
            try {
              decodeIr(broken);
            } on MdxIrFormatException {
              // as expected.
            }
          }
        }
      },
    );
  });
}
