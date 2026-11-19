import 'dart:math';

import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';

const _sentinel = '';

const _alertsOnly = [markdownXAlertsExtension];

List<MdxBlock> _ir(String source, {bool streaming = false}) =>
    IncrementalMarkdownParser().parse(
      source,
      extensions: _alertsOnly,
      streaming: streaming,
    );

List<MdxBlock> _whole(String source) => applyMarkdownXExtensions(
  parseMarkdown(applyMarkdownXSourceTransforms(source, _alertsOnly)),
  _alertsOnly,
);

String _src(String source, {bool streaming = false}) =>
    applyMarkdownXSourceTransforms(source, _alertsOnly, streaming: streaming);

MdxBlock _alert(String kind, [List<MdxBlock> blocks = const []]) =>
    MdxCustomBlock(
      markdownXAlertType,
      attributes: {'kind': kind},
      blocks: blocks,
    );

MdxBlock _p(String text) => MdxParagraph([MdxText(text)]);

/// A paragraph of [lines] separated by soft breaks.
MdxBlock _soft(List<String> lines) => MdxParagraph([
  for (var i = 0; i < lines.length; i++) ...[
    if (i > 0) MdxSoftBreak(),
    MdxText(lines[i]),
  ],
]);

/// Collects every string in the IR (text, code, attributes).
void _collectAll(List<Object> nodes, List<String> out) {
  for (final n in nodes) {
    _collect(n, out);
  }
}

void _collect(Object node, List<String> out) {
  switch (node) {
    case MdxText():
      out.add(node.text);
    case MdxCodeBlock():
      out.add(node.code);
    case MdxStyled():
      _collectAll(node.children, out);
    case MdxSpan():
      _collectAll(node.children, out);
    case MdxLink():
      out
        ..add(node.href)
        ..add(node.title ?? '');
      _collectAll(node.children, out);
    case MdxImage():
      out
        ..add(node.src)
        ..add(node.alt ?? '')
        ..add(node.title ?? '');
    case MdxCustomInline():
      out.addAll(node.attributes.values);
      _collectAll(node.children, out);
    case MdxParagraph():
      _collectAll(node.inlines, out);
    case MdxHeading():
      _collectAll(node.inlines, out);
    case MdxBlockquote():
      _collectAll(node.blocks, out);
    case MdxList():
      for (final item in node.items) {
        _collectAll(item.blocks, out);
      }
    case MdxTable():
      for (final cell in node.header) {
        _collectAll(cell, out);
      }
      for (final row in node.rows) {
        for (final cell in row) {
          _collectAll(cell, out);
        }
      }
    case MdxDetails():
      _collectAll(node.summary, out);
      _collectAll(node.blocks, out);
    case MdxCustomBlock():
      out.addAll(node.attributes.values);
      _collectAll(node.inlines, out);
      _collectAll(node.blocks, out);
    default:
      break;
  }
}

bool _leaks(List<MdxBlock> blocks) {
  final out = <String>[];
  _collectAll(blocks, out);
  return out.any((s) => s.contains(_sentinel));
}

void main() {
  group('text continuing on the same line is not an alert', () {
    test('`> [!NOTE] text` is a normal quote and [!NOTE] stays as text', () {
      expect(_ir('> [!NOTE] text'), [
        MdxBlockquote([_p('[!NOTE] text')]),
      ]);
      expect(_ir('> [!NOTE] text\n> more'), [
        MdxBlockquote([
          _soft(['[!NOTE] text', 'more']),
        ]),
      ]);
    });

    test('a marker-only line becomes an alert', () {
      expect(_ir('> [!NOTE]\n> text'), [
        _alert('note', [_p('text')]),
      ]);
      expect(_ir('> [!TIP]'), [_alert('tip')]);
    });

    test('allows mixed case and trailing whitespace', () {
      expect(_ir('> [!note]  \n> x'), [
        _alert('note', [_p('x')]),
      ]);
      expect(_ir('> [!Warning] \n> x'), [
        _alert('warning', [_p('x')]),
      ]);
      expect(_ir('> [!caution]\t\n> x'), [
        _alert('caution', [_p('x')]),
      ]);
    });

    test('nested quotes', () {
      expect(_ir('> > [!TIP]\n> > x'), [
        MdxBlockquote([
          _alert('tip', [_p('x')]),
        ]),
      ]);
      expect(_ir('> > [!TIP] x\n> > y'), [
        MdxBlockquote([
          MdxBlockquote([
            _soft(['[!TIP] x', 'y']),
          ]),
        ]),
      ]);
      expect(_ir('> a\n> > [!TIP]\n> > x'), [
        MdxBlockquote([
          _p('a'),
          _alert('tip', [_p('x')]),
        ]),
      ]);
    });

    test('quote inside a list item', () {
      final list = _ir('- > [!TIP]\n  > x').single as MdxList;
      expect(list.items.single.blocks, [
        _alert('tip', [_p('x')]),
      ]);
      final same = _ir('- > [!TIP] x').single as MdxList;
      expect(same.items.single.blocks, [
        MdxBlockquote([_p('[!TIP] x')]),
      ]);
    });

    test('a marker on the second or later quote line is not an alert', () {
      expect(_ir('> a\n> [!NOTE]\n> b'), [
        MdxBlockquote([
          _soft(['a', '[!NOTE]', 'b']),
        ]),
      ]);
      expect(_ir('> a\n>\n> [!NOTE]\n> b'), [
        MdxBlockquote([
          _p('a'),
          _soft(['[!NOTE]', 'b']),
        ]),
      ]);
    });

    test('a marker in a lazy continuation is not an alert', () {
      expect(_ir('> > a\n> [!NOTE]\n> b'), [
        MdxBlockquote([
          MdxBlockquote([
            _soft(['a', '[!NOTE]', 'b']),
          ]),
        ]),
      ]);
    });
  });

  group('transformSource', () {
    test('adds a sentinel right after the `]` of a marker-only line', () {
      expect(_src('> [!NOTE]\n> x'), '> [!NOTE]$_sentinel\n> x');
      expect(_src('> [!note]  \n> x'), '> [!note]$_sentinel  \n> x');
      expect(_src('> > [!TIP]\n> > x'), '> > [!TIP]$_sentinel\n> > x');
      expect(_src('- > [!TIP]\n  > x'), '- > [!TIP]$_sentinel\n  > x');
    });

    test('non-target input is returned as the same string', () {
      for (final source in [
        'plain',
        '> [!NOTE] text',
        '> a [!NOTE]',
        '> a\n> [!NOTE]',
        '> [!INFO]\n> a',
        '> [! NOTE]\n> a',
        '[!NOTE]\n\ntext',
        '- [!NOTE]\n',
        '> - [!NOTE]\n',
        '> ```\n> [!NOTE]\n> ```',
        '```\n> [!NOTE]\n```',
        '~~~\n> [!NOTE]\n~~~',
        '- a\n\n  ```\n  > [!NOTE]\n  ```',
        'a\n\n    > [!NOTE]\n    > x',
      ]) {
        expect(_src(source), source, reason: source);
      }
    });

    test('a marker after a fence is a target', () {
      expect(
        _src('```\nx\n```\n\n> [!NOTE]\n> a'),
        '```\nx\n```\n\n> [!NOTE]$_sentinel\n> a',
      );
    });

    test('CRLF is also a target', () {
      expect(_src('> [!NOTE]\r\n> x'), '> [!NOTE]$_sentinel\r\n> x');
    });

    test('inside fences and indented code there is no alert and no sentinel remains', () {
      for (final source in [
        '> ```\n> [!NOTE]\n> ```',
        'a\n\n    > [!NOTE]\n    > x',
        '```\n> [!NOTE]\n> x\n```',
      ]) {
        final ir = _ir(source);
        expect(ir.whereType<MdxCustomBlock>(), isEmpty, reason: source);
        expect(_leaks(ir), isFalse, reason: source);
      }
    });

    test('streaming: a marker without a trailing newline gets no sentinel', () {
      expect(_src('> [!NOTE]', streaming: true), '> [!NOTE]');
      expect(_src('> [!NOTE]', streaming: false), '> [!NOTE]$_sentinel');
      expect(_src('> [!NOTE]\n', streaming: true), '> [!NOTE]$_sentinel\n');
    });
  });

  group('streaming', () {
    const doc = '> [!NOTE]\n> text\n\n> [!TIP] same\n\n> [!WARNING]  \n> w';

    test('for any prefix, a partial marker is not visible as text', () {
      for (var i = 1; i <= doc.length; i++) {
        final blocks = _ir(doc.substring(0, i), streaming: true);
        final out = <String>[];
        _collectAll(blocks, out);
        final joined = out.join('\n');
        expect(joined, isNot(contains(_sentinel)), reason: '$i');
        // A partial marker of the leading alert is not visible as text.
        if (i <= '> [!NOTE]'.length) {
          expect(joined, isNot(contains('[!')), reason: '$i');
          expect(joined, isNot(contains('!NO')), reason: '$i');
        }
      }
    });

    test(
      'appears as an alert once the marker line is terminated by a newline',
      () {
        expect(_ir('> [!NOTE]\n', streaming: true), [_alert('note')]);
        expect(_ir('> [!NOTE]\n> te', streaming: true), [
          _alert('note', [_p('te')]),
        ]);
      },
    );

    test('a quote whose text arrives on the same line is not an alert', () {
      expect(_ir('> [!NOTE] te', streaming: true), [
        MdxBlockquote([_p('[!NOTE] te')]),
      ]);
    });

    test(
      'in a completed document, a trailing marker-only quote is also an alert',
      () {
        expect(_ir('> [!NOTE]'), [_alert('note')]);
      },
    );
  });

  group('chunk', () {
    const docs = [
      '> [!NOTE]\n> a\n\n> [!TIP] b\n\n> [!WARNING]\n> c\n\ntext',
      '- > [!TIP]\n  > x\n\n- y\n\n> > [!NOTE]\n> > z',
      '```\n> [!NOTE]\n```\n\n> [!CAUTION]\n> a\n\n    > [!NOTE]\n',
      '> a\n>\n> [!NOTE]\n> b\n\n> [!IMPORTANT]  \n> i',
    ];

    test('per-chunk parse matches full-text parse', () {
      for (final doc in docs) {
        expect(_ir(doc), _whole(doc), reason: doc);
      }
    });

    test(
      'appending one character at a time ends up matching full-text parse',
      () {
        for (final doc in docs) {
          final parser = IncrementalMarkdownParser();
          late List<MdxBlock> last;
          for (var i = 1; i <= doc.length; i++) {
            last = parser.parse(
              doc.substring(0, i),
              extensions: _alertsOnly,
              streaming: i < doc.length,
            );
          }
          expect(last, _whole(doc), reason: doc);
        }
      },
    );

    test('the transform is pure; the same chunk gives the same result', () {
      for (final doc in docs) {
        expect(_src(doc), _src(doc));
      }
    });
  });

  group('Sentinels do not leak', () {
    test('no sentinel is added when the extension is disabled', () {
      final ir = IncrementalMarkdownParser().parse('> [!NOTE]\n> a');
      final out = <String>[];
      _collectAll(ir, out);
      expect(out.join(), isNot(contains(_sentinel)));
      expect(ir.single, isA<MdxBlockquote>());
    });

    test('also removes sentinels outside an alert (unexpected positions)', () {
      // Parse a source containing sentinels directly, without going through the transform.
      for (final source in [
        '> [!NOTE]$_sentinel\n> a\n>\n> [!TIP]$_sentinel',
        '- [!NOTE]$_sentinel',
        '[!NOTE]$_sentinel',
        '# h [!NOTE]$_sentinel',
        '```\n[!NOTE]$_sentinel\n```',
        '    [!NOTE]$_sentinel',
        '`[!NOTE]$_sentinel`',
        '[a[!NOTE]$_sentinel](u$_sentinel)',
        '| a$_sentinel |\n|---|\n| b$_sentinel |',
        '> [!NOTE]$_sentinel\n> ---',
        '- > a\n\n  > [!NOTE]$_sentinel\n  > b',
        '<details><summary>s$_sentinel</summary>\n\n> [!NOTE]$_sentinel\n> x\n\n</details>',
      ]) {
        final ir = applyMarkdownXExtensions(parseMarkdown(source), _alertsOnly);
        expect(_leaks(ir), isFalse, reason: source);
      }
    });

    test('property: with many inputs, no sentinel appears in the final IR', () {
      const pieces = [
        '> ',
        '> > ',
        '- ',
        '1. ',
        '  ',
        '    ',
        '[!NOTE]',
        '[!tip]',
        '[!WARNING]',
        '[!X]',
        ' ',
        'text',
        '**b**',
        '`c`',
        '```',
        '~~~',
        '# ',
        '---',
        '|a|b|',
        '|-|-|',
        '\n',
        '\n',
        '\n\n',
        '<details>',
        '</details>',
        '<summary>s</summary>',
        '\\',
        '[l](u)',
      ];
      final random = Random(20260101);
      for (var n = 0; n < 1500; n++) {
        final source = [
          for (var k = random.nextInt(14) + 1; k > 0; k--)
            pieces[random.nextInt(pieces.length)],
        ].join();
        final whole = _ir(source);
        expect(_leaks(whole), isFalse, reason: source);
        final streamed = _ir(source, streaming: true);
        expect(_leaks(streamed), isFalse, reason: source);
      }
    });
  });
}
