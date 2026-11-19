// Verifies the display policy while streaming (doc/streaming.md).
//
// Unit tests for repair, which fixes up trailing incomplete syntax, and properties
// when streaming every prefix of representative documents (no exceptions, no raw markers
// visible, finalized blocks unchanged).
import 'dart:math';

import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/prefixes.dart';

String repair(String source) => markdownXRepairStreamingTail(source);

/// Projection of the displayed text. Excludes code block and inline code content.
String visibleText(Iterable<MdxBlock> blocks) {
  final out = StringBuffer();
  void write(List<MdxInline> list) {
    for (final inline in list) {
      switch (inline) {
        case MdxText(:final text):
          out.write(text);
        case MdxLineBreak():
          out.write('\n');
        case MdxSoftBreak():
          out.write(' ');
        case MdxStyled(:final kind, :final children):
          if (kind != MdxStyleKind.code) write(children);
        case MdxCustomInline(:final children):
          write(children);
        case MdxSpan(:final children):
          write(children);
        case MdxLink(:final children):
          write(children);
        case MdxImage(:final alt):
          out.write(alt ?? '');
      }
    }
    out.write('\n');
  }

  void block(MdxBlock b) {
    switch (b) {
      case MdxParagraph(:final inlines):
        write(inlines);
      case MdxHeading(:final inlines):
        write(inlines);
      case MdxBlockquote(:final blocks):
        blocks.forEach(block);
      case MdxList(:final items):
        for (final item in items) {
          item.blocks.forEach(block);
        }
      case MdxTable(:final header, :final rows):
        header.forEach(write);
        for (final row in rows) {
          row.forEach(write);
        }
      case MdxDetails(:final summary, :final blocks):
        write(summary);
        blocks.forEach(block);
      case MdxCustomBlock(:final inlines, :final blocks):
        write(inlines);
        blocks.forEach(block);
      case MdxCodeBlock():
      case MdxThematicBreak():
        break;
    }
  }

  blocks.forEach(block);
  return out.toString();
}

/// Collects all link targets and image srcs.
Set<String> destinations(Iterable<MdxBlock> blocks) {
  final found = <String>{};
  void visit(List<MdxInline> list) {
    for (final inline in list) {
      switch (inline) {
        case MdxLink(:final href, :final children):
          found.add(href);
          visit(children);
        case MdxImage(:final src):
          found.add(src);
        case MdxStyled(:final children):
          visit(children);
        case MdxSpan(:final children):
          visit(children);
        case MdxCustomInline(:final children):
          visit(children);
        case MdxText():
        case MdxLineBreak():
        case MdxSoftBreak():
          break;
      }
    }
  }

  void block(MdxBlock b) {
    switch (b) {
      case MdxParagraph(:final inlines):
        visit(inlines);
      case MdxHeading(:final inlines):
        visit(inlines);
      case MdxBlockquote(:final blocks):
        blocks.forEach(block);
      case MdxList(:final items):
        for (final item in items) {
          item.blocks.forEach(block);
        }
      case MdxTable(:final header, :final rows):
        header.forEach(visit);
        for (final row in rows) {
          row.forEach(visit);
        }
      case MdxDetails(:final summary, :final blocks):
        visit(summary);
        blocks.forEach(block);
      case MdxCustomBlock(:final inlines, :final blocks):
        visit(inlines);
        blocks.forEach(block);
      case MdxCodeBlock():
      case MdxThematicBreak():
        break;
    }
  }

  blocks.forEach(block);
  return found;
}

void main() {
  group('repair: incomplete inline', () {
    test('unclosed strong / emphasis / strikethrough are closed with the intended decoration', () {
      expect(repair('Hello **bol'), 'Hello **bol**');
      expect(repair('Hello *it'), 'Hello *it*');
      expect(repair('Hello _it'), 'Hello _it_');
      expect(repair('Hello ~~gon'), 'Hello ~~gon~~');
      expect(repair('Hello ***both'), 'Hello ***both***');
      expect(repair('**a *b'), '**a *b***');
    });

    test('a partial closing marker is completed', () {
      expect(repair('**bold*'), '**bold**');
      expect(repair('~~gone~'), '~~gone~~');
    });

    test('an opening marker with no content is hidden', () {
      expect(repair('Hello **'), 'Hello ');
      expect(repair('Hello ~~'), 'Hello ');
      expect(repair('Hello _'), 'Hello ');
      expect(repair('Hello **bold** and *'), 'Hello **bold** and ');
    });

    test(
      'closed markers and markers not satisfying flanking are unchanged',
      () {
        expect(repair('a **b** c'), 'a **b** c');
        expect(repair('snake_case_name'), 'snake_case_name');
        expect(repair('2 * 3 = 6'), '2 * 3 = 6');
      },
    );

    test('an unclosed marker satisfying opening conditions is closed even in a complete document', () {
      // The second ** is left-flanking, so it is treated as an opening marker (doc/streaming.md).
      expect(repair('日本語**「強調」**です'), '日本語**「強調」**です**');
    });

    test('also hidden when removing the trailing marker leaves only a line-start marker', () {
      expect(repair('- a\n-<b'), '- a\n');
      expect(repair('Title\n--<b'), 'Title\n');
      expect(repair('#<b'), '');
    });

    test('an unclosed inline code is closed, or hidden if empty', () {
      expect(repair('Use `cod'), 'Use `cod`');
      expect(repair('Use ``a b'), 'Use ``a b``');
      expect(repair('Use `'), 'Use ');
      expect(repair('Use `code` and `'), 'Use `code` and ');
      expect(repair('a **b `c'), 'a **b `c`**');
    });

    test('markers inside code are not treated as decoration', () {
      expect(repair('`**` and `*` done'), '`**` and `*` done');
    });

    test('a partial link becomes text only and a partial image is hidden', () {
      expect(repair('[text](htt'), 'text');
      expect(repair('[text](https://example.com "ti'), 'text');
      expect(repair('[text'), 'text');
      expect(repair('See [te'), 'See te');
      expect(repair('![alt](ur'), '');
      expect(repair('Look ![al'), 'Look ');
      expect(repair('[**bo](ht'), '**bo**');
      expect(repair('[a](b) and [c](d'), '[a](b) and c');
    });

    test('complete links and images are unchanged', () {
      expect(
        repair('[a](https://e.com) ![b](c.png)'),
        '[a](https://e.com) ![b](c.png)',
      );
      expect(repair('[a](https://e.com/(x))'), '[a](https://e.com/(x))');
    });

    test('a partial footnote reference is hidden', () {
      expect(repair('Claim[^no'), 'Claim');
      expect(repair('Claim[^1] done'), 'Claim[^1] done');
    });

    test('a partial HTML tag is hidden', () {
      expect(repair('<det'), '');
      expect(repair('x <span style="col'), 'x ');
      expect(repair('x </spa'), 'x ');
      expect(repair('a <span>b</span> c'), 'a <span>b</span> c');
      expect(repair('a < b and 1 <= 2'), 'a < b and 1 <= 2');
      expect(repair('<https://exa'), '');
      expect(repair('<https://example.com> ok'), '<https://example.com> ok');
    });

    test('a lone backslash at the end of a line is hidden', () {
      expect(repair('a\\'), 'a');
      expect(repair('a\\\\'), 'a\\\\');
    });

    test('also closes inside headings and lists', () {
      expect(repair('## Title **bo'), '## Title **bo**');
      expect(repair('- item **bo'), '- item **bo**');
      expect(repair('1. item `co'), '1. item `co`');
      expect(repair('> quote *em'), '> quote *em*');
      expect(repair('- **'), '');
      expect(repair('- a\n- **bo\n  more'), '- a\n- **bo\n  more**');
    });

    test('completed blocks are left alone', () {
      expect(repair('**a\n\nnext *b'), '**a\n\nnext *b*');
      expect(repair('para **a**\n\n'), 'para **a**\n\n');
    });
  });

  group('repair: mid-block', () {
    test('a line with only a line-start marker is hidden', () {
      expect(repair('-'), '');
      expect(repair('- a\n-'), '- a\n');
      expect(repair('- a\n- '), '- a\n');
      expect(repair('*'), '');
      expect(repair('1.'), '');
      expect(repair('1)'), '');
      expect(repair('#'), '');
      expect(repair('###'), '');
      expect(repair('>'), '');
      expect(repair('- [ ]'), '');
      expect(repair('- [x'), '');
      expect(repair('[foo]:'), '');
      expect(repair('[^1]'), '');
      expect(repair('a\n\n[^note]:'), 'a\n\n');
    });

    test('an underline-only line right after a paragraph is hidden to prevent setext misreading', () {
      expect(repair('Title\n-'), 'Title\n');
      expect(repair('Title\n--'), 'Title\n');
      expect(repair('Title\n---'), 'Title\n');
      expect(repair('Title\n='), 'Title\n');
      expect(repair('Title\n=='), 'Title\n');
      // --- after a blank line is a horizontal rule.
      expect(repair('Title\n\n---'), 'Title\n\n---');
      // --- right after a heading is also a horizontal rule.
      expect(repair('# T\n---'), '# T\n---');
    });

    test('lines that reached a newline and normal body text are unchanged', () {
      expect(repair('Title\n---\n'), 'Title\n---\n');
      expect(repair('#hashtag'), '#hashtag');
      expect(repair('- a\n- b\n'), '- a\n- b\n');
    });

    test('mid-fence: the info string of the opening line is held until the newline', () {
      expect(repair('```'), '```');
      expect(repair('```da'), '```');
      expect(repair('Intro\n\n```dart'), 'Intro\n\n```');
      expect(repair('```dart\n'), '```dart\n');
      expect(repair('```dart\ncode'), '```dart\ncode');
      expect(repair('  ~~~py'), '  ~~~');
    });

    test('mid-fence: a partial closing fence is hidden', () {
      expect(repair('```dart\ncode\n``'), '```dart\ncode');
      expect(repair('```dart\ncode\n`'), '```dart\ncode');
      expect(repair('````\ncode\n```'), '````\ncode');
      expect(repair('```\ncode\n\n'), '```\ncode');
      expect(repair('```\ncode\n```'), '```\ncode\n```');
    });

    test('fence content is not repaired as inline', () {
      expect(repair('```\n**bo `x <a'), '```\n**bo `x <a');
    });

    test('body text after a closed fence is repaired', () {
      expect(repair('```\ncode\n```\ntext **b'), '```\ncode\n```\ntext **b**');
    });

    test('indented code blocks are left alone', () {
      expect(repair('para\n\n    def f(**kw'), 'para\n\n    def f(**kw');
    });
  });

  group('repair: table', () {
    test('a header-only row gets a delimiter row so it can be treated as an empty table', () {
      expect(repair('| a | b |'), '| a | b |\n| --- | --- |');
      expect(repair('| a | b'), '| a | b\n| --- | --- |');
      expect(repair('| a | b |\n'), '| a | b |\n| --- | --- |');
      expect(repair('Intro\n\n| a | b |'), 'Intro\n\n| a | b |\n| --- | --- |');
    });

    test('a partial delimiter row is matched to the header column count', () {
      expect(repair('| a | b |\n|'), '| a | b |\n| --- | --- |');
      expect(repair('| a | b |\n| -'), '| a | b |\n| --- | --- |');
      expect(repair('| a | b |\n| ---'), '| a | b |\n| --- | --- |');
      expect(repair('| a | b |\n| --- | :'), '| a | b |\n| --- | :--- |');
      expect(repair('| a | b |\n| :--- | ---:'), '| a | b |\n| :--- | ---:');
      expect(repair('a | b\n-'), 'a | b\n');
      expect(repair('a | b\n-|'), 'a | b\n| --- | --- |');
    });

    test('complete delimiter rows and body rows are unchanged', () {
      expect(repair('| a | b |\n| --- | --- |'), '| a | b |\n| --- | --- |');
      expect(
        repair('| a | b |\n| --- | --- |\n| 1 | 2 |'),
        '| a | b |\n| --- | --- |\n| 1 | 2 |',
      );
    });

    test('only the last cell of a body row gets inline repair, and an empty row is hidden', () {
      expect(
        repair('| a | b |\n| - | - |\n| 1 | **2'),
        '| a | b |\n| - | - |\n| 1 | **2**',
      );
      expect(
        repair('| a | b |\n| - | - |\n| **1** | 2 |\n|'),
        '| a | b |\n| - | - |\n| **1** | 2 |\n',
      );
      expect(
        repair('| a | b |\n| - | - |\n| **1 | 2 |'),
        '| a | b |\n| - | - |\n| **1 | 2 |',
      );
    });

    test('an empty header is hidden', () {
      expect(repair('|*'), '');
      expect(repair('Intro\n\n| **'), 'Intro\n\n');
    });

    test('text without | is left alone', () {
      expect(repair('plain text'), 'plain text');
      expect(repair('a | b'), 'a | b');
    });
  });

  group(
    'parse: streaming: false, meaning complete, is the same as a normal parse',
    () {
      test('streaming: false does not repair even a partial document', () {
        for (final source in _inProgress) {
          final parser = IncrementalMarkdownParser();
          expect(parser.parse(source), parseMarkdown(source), reason: source);
          expect(
            parser.parse(source, streaming: false),
            parseMarkdown(source),
            reason: source,
          );
        }
      });

      test('streaming: true changes only the partial tail', () {
        final parser = IncrementalMarkdownParser();
        final blocks = parser.parse('para\n\nHello **bo', streaming: true);
        expect(blocks, [
          MdxParagraph([MdxText('para')]),
          MdxParagraph([
            MdxText('Hello '),
            MdxStyled(MdxStyleKind.strong, [MdxText('bo')]),
          ]),
        ]);
      });

      test('complete blocks reuse the same instance even when streaming', () {
        final parser = IncrementalMarkdownParser();
        final first = parser.parse(
          '# Head\n\npara one\n\nnext *a',
          streaming: true,
        );
        final second = parser.parse(
          '# Head\n\npara one\n\nnext *ab',
          streaming: true,
        );
        expect(identical(first[0], second[0]), isTrue);
        expect(identical(first[1], second[1]), isTrue);
        expect(first.last, isNot(second.last));
      });

      test(
        'the tail is repaired even in a document with reference definitions',
        () {
          final parser = IncrementalMarkdownParser();
          final blocks = parser.parse(
            '[a]: /url\n\nsee [a] and **b',
            streaming: true,
          );
          expect(visibleText(blocks), isNot(contains('**')));
        },
      );
    },
  );

  group('prefix: stream every prefix', () {
    for (final doc in _documents) {
      test(doc.name, () {
        _checkDocument(doc);
      });
    }

    test('streaming: true after the document is complete is the same as a normal parse', () {
      for (final doc in _documents) {
        final parser = IncrementalMarkdownParser();
        expect(
          parser.parse(doc.text, streaming: true),
          parseMarkdown(doc.text),
          reason: doc.name,
        );
      }
    });

    test('exception: when a footnote definition arrives, the block containing the earlier reference changes', () {
      final parser = IncrementalMarkdownParser();
      final before = parser.parse('Claim[^1].\n\nNext', streaming: true);
      final after = parser.parse(
        'Claim[^1].\n\nNext\n\n[^1]: Note.',
        streaming: true,
      );
      expect(after.first, isNot(before.first));
    });

    test('table: no pipe paragraph is emitted at the header-only stage', () {
      final parser = IncrementalMarkdownParser();
      for (final prefix in const [
        '| a | b |',
        '| a | b |\n',
        '| a | b |\n|',
        '| a | b |\n| -',
      ]) {
        final blocks = parser.parse(prefix, streaming: true);
        expect(blocks, hasLength(1), reason: _show(prefix));
        expect(blocks.single, isA<MdxTable>(), reason: _show(prefix));
        final table = blocks.single as MdxTable;
        expect(table.header, hasLength(2));
        expect(table.rows, isEmpty);
      }
    });

    test(
      'setext: a trailing - does not turn the previous line into a heading',
      () {
        final parser = IncrementalMarkdownParser();
        for (final prefix in const [
          'Title\n-',
          'Title\n--',
          'Title\n---',
          'Title\n=',
        ]) {
          final blocks = parser.parse(prefix, streaming: true);
          expect(blocks.single, isA<MdxParagraph>(), reason: _show(prefix));
        }
        expect(
          parser.parse('Title\n---\n', streaming: true).single,
          isA<MdxHeading>(),
        );
      },
    );

    test(
      'fence: the language is not shown until the opening line has a newline',
      () {
        final parser = IncrementalMarkdownParser();
        for (final prefix in const ['```', '```d', '```dar', '```dart']) {
          final block =
              parser.parse(prefix, streaming: true).single as MdxCodeBlock;
          expect(block.language, isNull, reason: prefix);
        }
        final done =
            parser.parse('```dart\nx', streaming: true).single as MdxCodeBlock;
        expect(done.language, 'dart');
        expect(done.code, 'x');
      },
    );
  });

  group('fuzz', () {
    const tokens = [
      '**',
      '*',
      '_',
      '~~',
      '`',
      '```',
      '[',
      ']',
      '(',
      ')',
      '![',
      '<',
      '>',
      '|',
      '-',
      '#',
      '1.',
      '\n',
      '\n\n',
      ' ',
      'a',
      'bc',
      '日本',
      ':',
      '\\',
      '---',
      '| - |',
      '<b>',
      '</b>',
      'http://x.y',
      '[^1]',
      '- ',
      '> ',
    ];

    // Input of randomly arranged markers. Only checks that no exception is thrown and that
    // the result matches a normal parse once the same document is completed.
    test('no exception on any prefix of random marker sequences', () {
      final random = Random(20260115);
      final parser = IncrementalMarkdownParser();
      for (var round = 0; round < 200; round++) {
        final source = [
          for (var i = 0; i < 25; i++) tokens[random.nextInt(tokens.length)],
        ].join();
        for (final i in prefixEnds(source)) {
          parser.parse(source.substring(0, i), streaming: true);
        }
        expect(
          parser.parse(source),
          parseMarkdown(source),
          reason: _show(source),
        );
      }
    });
  });

  group('widget', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('Markdown does not show incomplete markers while streaming', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const Markdown(data: 'Hello **bol', streaming: true)),
      );
      await tester.pump();
      expect(find.textContaining('**', findRichText: true), findsNothing);
      expect(find.textContaining('bol', findRichText: true), findsOneWidget);
    });

    testWidgets(
      'MarkdownBody does not show incomplete markers while streaming',
      (tester) async {
        await tester.pumpWidget(
          host(const MarkdownBody(data: 'Hello **bol', streaming: true)),
        );
        await tester.pump();
        expect(find.textContaining('**', findRichText: true), findsNothing);
      },
    );

    testWidgets('setting streaming to false returns to normal parse display', (
      tester,
    ) async {
      Future<void> pump(bool streaming) async {
        await tester.pumpWidget(
          host(MarkdownBody(data: 'Hello **bol', streaming: streaming)),
        );
        await tester.pump();
      }

      await pump(true);
      expect(find.textContaining('**', findRichText: true), findsNothing);
      await pump(false);
      expect(find.textContaining('**bol', findRichText: true), findsOneWidget);
    });

    testWidgets('the default (streaming: false) does not repair', (
      tester,
    ) async {
      await tester.pumpWidget(host(const MarkdownBody(data: 'Hello **bol')));
      await tester.pump();
      expect(find.textContaining('**bol', findRichText: true), findsOneWidget);
    });
  });
}

/// Input including partial states.
const _inProgress = <String>[
  'Hello **bol',
  '`cod',
  '[text](htt',
  '![alt](ur',
  '```dart\ncode\n``',
  '| a | b |\n| -',
  '<det',
  'Title\n-',
  '-',
  '#',
  '1.',
  'para\n\n- a\n- **b',
];

String _show(String s) => s.replaceAll('\n', r'\n');

class _Doc {
  const _Doc(
    this.name,
    this.text, {
    this.stable = true,
    this.rawBrackets = false,
  });

  final String name;
  final String text;

  /// Whether to verify that finalized blocks do not change in later prefixes.
  /// False for documents where later input changes earlier blocks, such as reference definitions and footnotes.
  final bool stable;

  /// Whether `[` `]` may appear in the body (e.g. footnote references).
  final bool rawBrackets;
}

const _documents = <_Doc>[
  _Doc(
    'emphasis',
    'This is **bold text**, *em phasis*, ~~struck out~~ and `inline code` '
        'and ***both***.\n\nSecond ***para*** with __under__ done and _it_ too.\n',
  ),
  _Doc(
    'links and images',
    'See [the docs](https://example.com/docs "Title") and '
        '![logo](https://example.com/a.png) then [other](https://example.org/x_y) '
        'and <https://example.com/auto> end.\n\n'
        '[**bold link**](https://example.com/b) and [plain] text.\n',
  ),
  _Doc(
    'fence',
    "Intro\n\n```dart\nvoid main() {\n\n  print('**x** `y` <z');\n}\n```\n\n"
        '~~~py\nx = 1\n~~~\n\n````md\n```\nnested\n```\n````\n\nDone.',
  ),
  _Doc(
    'table',
    '| Name | Qty |\n| --- | ---: |\n| Apple | **3** |\n| Pear | 4 |\n\n'
        'After table.\n\na | b\n--|--\n1 | 2\n\nEnd',
  ),
  _Doc(
    'HTML',
    'Text <span style="color: red">red</span> and <b>bold</b> end.\n\n'
        '<details>\n<summary>Sum</summary>\n\nInside **text**.\n\n</details>\n\nTail',
  ),
  _Doc(
    'lists and headings',
    '# Heading **one**\n\nIntro line\n\n- item one\n- item **two**\n'
        '  continued\n- [ ] task a\n- [x] task b\n\n1. first\n2. second\n\n'
        '> quote *here*\n\n## Second\n\nSetext Title\n---\n\n***\n\nEnd',
  ),
  _Doc(
    'footnotes',
    'Claim one[^1] and two[^note].\n\n[^1]: First note.\n'
        '[^note]: Second **note**.\n',
    // Until the definition arrives, the footnote reference stays as body text. When it arrives, the earlier block changes.
    stable: false,
    rawBrackets: true,
  ),
  _Doc(
    'Japanese',
    '# 見出し\n\nこれは**重要**な文章です。*強調*と~~取り消し~~と`コード`。\n\n'
        '[リンク](https://example.jp/ページ)を参照。\n\n- 箇条書き**一**\n- 項目二\n\n'
        '| 名前 | 数 |\n|---|---|\n| りんご | 3 |\n\n終わり。',
  ),
];

void _checkDocument(_Doc doc) {
  final full = parseMarkdown(doc.text);
  final allowed = destinations(full);
  final parser = IncrementalMarkdownParser();
  var stable = <MdxBlock>[];

  for (final i in prefixEnds(doc.text)) {
    final prefix = doc.text.substring(0, i);
    final reason = 'prefix ${_show(prefix)}';
    final blocks = parser.parse(prefix, streaming: true);

    // No raw markers visible.
    final text = visibleText(blocks);
    for (final raw in const ['**', '~~', '`', '](', '![', '<']) {
      expect(text, isNot(contains(raw)), reason: '$raw in $reason');
    }
    expect(RegExp(r'<[A-Za-z/!]').hasMatch(text), isFalse, reason: reason);
    if (!doc.rawBrackets) {
      expect(
        RegExp(r'\[(?![^\]]*\])').hasMatch(text.replaceAll('[plain]', '')),
        isFalse,
        reason: '[ in $reason',
      );
    }
    expect(
      RegExp(r'^\s*\|', multiLine: true).hasMatch(text),
      isFalse,
      reason: 'pipe row in $reason',
    );

    // No broken links / images.
    expect(allowed.containsAll(destinations(blocks)), isTrue, reason: reason);

    // No empty blocks (empty headings, items, quotes).
    for (final block in blocks) {
      _expectNotEmpty(block, reason);
    }

    // The language name does not appear partway.
    for (final block in blocks.whereType<MdxCodeBlock>()) {
      final languages = full.whereType<MdxCodeBlock>().map((b) => b.language);
      expect(
        block.language == null || languages.contains(block.language),
        isTrue,
        reason: reason,
      );
    }

    // Finalized blocks (before the last) do not change in later prefixes.
    if (doc.stable) {
      expect(
        blocks.length >= stable.length,
        isTrue,
        reason: 'block count shrank at $reason',
      );
      for (var j = 0; j < stable.length; j++) {
        expect(blocks[j], stable[j], reason: 'block $j changed at $reason');
      }
      if (blocks.length - 1 > stable.length) {
        stable = blocks.sublist(0, blocks.length - 1);
      }
    }
  }

  // The last frame (streaming: false) matches a normal parse.
  expect(parser.parse(doc.text), full);
}

void _expectNotEmpty(MdxBlock block, String reason) {
  switch (block) {
    case MdxHeading(:final inlines):
      expect(inlines, isNotEmpty, reason: 'empty heading at $reason');
    case MdxBlockquote(:final blocks):
      expect(blocks, isNotEmpty, reason: 'empty quote at $reason');
      for (final b in blocks) {
        _expectNotEmpty(b, reason);
      }
    case MdxList(:final items):
      for (final item in items) {
        expect(item.blocks, isNotEmpty, reason: 'empty item at $reason');
      }
    case MdxParagraph(:final inlines):
      expect(inlines, isNotEmpty, reason: 'empty paragraph at $reason');
    default:
      break;
  }
}
