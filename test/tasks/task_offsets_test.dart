// Where the task markers sit in the source: the offsets the parser attaches to task items must
// map back to the ORIGINAL data, whatever the chunking, the definitions put in front of a
// chunk, the source transforms (math, alerts, mermaid) and the streaming repair do to the text.
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_markdown_x/math.dart';
import 'package:flutter_markdown_x/mermaid.dart';
import 'package:flutter_markdown_x/src/ir/task_markers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every task of the latest result of [parser], as an app would receive it.
List<MarkdownXTask> _tasks(
  IncrementalMarkdownParser parser,
  List<MdxBlock> blocks,
) {
  final tasks = <MarkdownXTask>[];
  for (var i = 0; i < blocks.length; i++) {
    final count = mdxTaskCount([blocks[i]]);
    for (var ordinal = 0; ordinal < count; ordinal++) {
      final task = parser.taskAt(blocks, i, ordinal);
      if (task != null) tasks.add(task);
    }
  }
  return tasks;
}

final _citations = markdownXCitationExtension();

final _extensionSets = <String, List<MarkdownXExtension>>{
  'no extensions': const [],
  'alerts': [markdownXAlertsExtension],
  'all extensions': [
    markdownXMathExtension,
    markdownXAlertsExtension,
    _citations,
    markdownXEmojiExtension,
    markdownXMermaidExtension,
  ],
};

/// A document, the words that follow the markers in order, and their check states.
typedef _Case = ({String data, List<String> words, List<bool> checked});

final _cases = <String, _Case>{
  'a simple list': (
    data: '- [ ] one\n- [x] two\n- [X] three\n',
    words: ['one', 'two', 'three'],
    checked: [false, true, true],
  ),
  'ordered and loose': (
    data: '1. [ ] one\n\n2. [x] two\n\n10. [ ] three\n',
    words: ['one', 'two', 'three'],
    checked: [false, true, false],
  ),
  'nested lists': (
    data: '- [ ] outer\n  - [x] inner\n    - [ ] deep\n- [x] next\n',
    words: ['outer', 'inner', 'deep', 'next'],
    checked: [false, true, false, true],
  ),
  'a blockquote': (
    data: '> - [ ] quoted\n> - [x] again\n\n- [ ] plain\n',
    words: ['quoted', 'again', 'plain'],
    checked: [false, true, false],
  ),
  'a task after other blocks and chunks': (
    data:
        '# Title\n\nSome text.\n\n- [ ] a\n\nMore text.\n\n- [x] b\n- [ ] c\n',
    words: ['a', 'b', 'c'],
    checked: [false, true, false],
  ),
  'non-ASCII text before the task': (
    data: '日本語の見出し 😀 é\n\n- [ ] 日本 😀\n- [x] café\n',
    words: ['日本', 'café'],
    checked: [false, true],
  ),
  'CRLF line endings': (
    data:
        '# T\r\n\r\n- [ ] one\r\n- [x] two\r\n\r\npara\r\n\r\n- [ ] three\r\n',
    words: ['one', 'two', 'three'],
    checked: [false, true, false],
  ),
  'reference definitions before and after': (
    data: '[ref]: https://example.com\n\n- [ ] see [ref]\n\npara\n\n- [x] again\n\n[other]: https://example.org\n',
    words: ['see', 'again'],
    checked: [false, true],
  ),
  'definitions that change the chunk text': (
    data: 'intro [a]\n\n[a]: https://a.example\n[b]: https://b.example\n\n- [x] item [b]\n',
    words: ['item'],
    checked: [true],
  ),
  'a fake marker in a code fence': (
    data: '```\n- [ ] fake\n```\n\n- [x] real\n',
    words: ['real'],
    checked: [true],
  ),
  'math before the task in the same chunk': (
    data:
        r'$$'
        '\n'
        r'a_1 \\ b'
        '\n'
        r'$$'
        '\n- [ ] after display\n'
        r'- [x] with $x_1$ inline'
        '\n',
    words: ['after', 'with'],
    checked: [false, true],
  ),
  'an alert and a task': (
    data: '> [!NOTE]\n> - [ ] in the alert\n\n- [x] outside\n',
    words: ['in', 'outside'],
    checked: [false, true],
  ),
  'a mermaid fence before a task': (
    data: '```mermaid\ngraph TD; A-->B\n```\n\n- [ ] after mermaid\n',
    words: ['after'],
    checked: [false],
  ),
  'html comments force a whole-document parse': (
    data: '<!-- note -->\n\n- [ ] one\n\n[r]: https://x.example\n\n- [x] two [r]\n',
    words: ['one', 'two'],
    checked: [false, true],
  ),
  'citations and emoji in the task text': (
    data: '- [ ] claim [1] :smile:\n- [x] other [2, 3]\n',
    words: ['claim', 'other'],
    checked: [false, true],
  ),
  'a task inside details': (
    data: '<details>\n<summary>S</summary>\n\n- [ ] hidden\n\n</details>\n\n- [x] shown\n',
    words: ['hidden', 'shown'],
    checked: [false, true],
  ),
};

void main() {
  for (final MapEntry(key: setName, value: extensions)
      in _extensionSets.entries) {
    for (final streaming in [false, true]) {
      group('$setName, streaming: $streaming', () {
        for (final MapEntry(key: name, value: c) in _cases.entries) {
          test(name, () {
            final parser = IncrementalMarkdownParser();
            final blocks = parser.parse(
              c.data,
              extensions: extensions,
              streaming: streaming,
            );
            final tasks = _tasks(parser, blocks);
            expect(tasks.map((t) => t.checked), c.checked);
            expect(
              tasks.map((t) => t.index),
              List.generate(c.words.length, (i) => i),
            );
            for (var i = 0; i < tasks.length; i++) {
              final task = tasks[i];
              expect(
                task.matches(c.data),
                isTrue,
                reason: '$task in ${c.data}',
              );
              expect(
                c.data.substring(task.markerEnd).trimLeft(),
                startsWith(c.words[i]),
                reason: 'task $i of ${c.data}',
              );
            }
          });
        }
      });
    }
  }

  group('toggling through the offsets', () {
    test('each task flips exactly its own marker', () {
      final data = _cases['a task after other blocks and chunks']!.data;
      final parser = IncrementalMarkdownParser();
      final tasks = _tasks(parser, parser.parse(data));
      expect(tasks[0].toggle(data), data.replaceFirst('- [ ] a', '- [x] a'));
      expect(tasks[1].toggle(data), data.replaceFirst('- [x] b', '- [ ] b'));
      expect(tasks[2].toggle(data), data.replaceFirst('- [ ] c', '- [x] c'));
    });

    test('a toggled document parses to the opposite state', () {
      final data = '日本 😀\n\n- [ ] a\n- [x] b\r\n- [ ] c\n';
      final parser = IncrementalMarkdownParser();
      var text = data;
      for (var i = 0; i < 3; i++) {
        final tasks = _tasks(parser, parser.parse(text));
        final before = tasks.map((t) => t.checked).toList();
        text = tasks[i].toggle(text);
        final after = _tasks(
          parser,
          parser.parse(text),
        ).map((t) => t.checked).toList();
        expect(after[i], !before[i]);
        for (var j = 0; j < after.length; j++) {
          if (j != i) expect(after[j], before[j]);
        }
      }
    });
  });

  group('the incremental parser', () {
    test('offsets of reused chunks stay correct as the document grows', () {
      const lines = [
        '# Title\n',
        '\n',
        '- [ ] first\n',
        '- [x] second\n',
        '\n',
        '日本語 😀\n',
        '\n',
        '- [ ] third\n',
        '\n',
        '[r]: https://x.example\n',
        '\n',
        '> - [x] fourth [r]\n',
        '\n',
        'end\n',
        '\n',
        '- [ ] fifth\n',
      ];
      final parser = IncrementalMarkdownParser();
      var data = '';
      for (final line in lines) {
        for (final streaming in [false, true]) {
          data += line;
          final blocks = parser.parse(data, streaming: streaming);
          final fresh = IncrementalMarkdownParser();
          final expected = _tasks(
            fresh,
            fresh.parse(data, streaming: streaming),
          );
          final tasks = _tasks(parser, blocks);
          expect(tasks, expected, reason: 'after ${data.length} chars');
          for (final task in tasks) {
            expect(task.matches(data), isTrue, reason: '$task in $data');
          }
        }
      }
    });

    test('char by char appends keep every marker valid', () {
      const data =
          '日本\n\n- [ ] a\n- [x] b\n\n> - [ ] c\n\n[r]: https://x.example\n\n1. [x] d [r]\n';
      for (final extensions in _extensionSets.values) {
        for (final streaming in [false, true]) {
          final parser = IncrementalMarkdownParser();
          for (var end = 1; end <= data.length; end++) {
            final prefix = data.substring(0, end);
            final tasks = _tasks(
              parser,
              parser.parse(
                prefix,
                extensions: extensions,
                streaming: streaming,
              ),
            );
            for (final task in tasks) {
              // A task is reported only for a marker that exists in the text so far.
              expect(
                task.matches(prefix),
                isTrue,
                reason: '$task in "$prefix"',
              );
            }
          }
        }
      }
    });

    test('inserting text before a task list moves the offsets but keeps the blocks equal', () {
      const list = '- [ ] a\n- [x] b\n';
      final parser = IncrementalMarkdownParser();
      final first = parser.parse('para\n\n$list');
      final second = parser.parse('a longer paragraph\n\nanother one\n\n$list');
      expect(second.last, first.last);
      expect(second.last.hashCode, first.last.hashCode);
      final tasks = _tasks(parser, second);
      final data = 'a longer paragraph\n\nanother one\n\n$list';
      expect(tasks.map((t) => t.markerStart), [
        data.indexOf('[ ]'),
        data.indexOf('[x]'),
      ]);
    });

    test('a pure append reuses the chunk instances and keeps the offsets', () {
      final parser = IncrementalMarkdownParser();
      const head = '- [ ] a\n- [x] b\n\npara\n\n';
      final first = parser.parse('$head- [ ] c\n');
      final second = parser.parse('$head- [ ] c\n\nmore text\n\n- [x] d\n');
      expect(identical(second.first, first.first), isTrue);
      final tasks = _tasks(parser, second);
      expect(tasks.map((t) => t.index), [0, 1, 2, 3]);
      for (final task in tasks) {
        expect(task.matches('$head- [ ] c\n\nmore text\n\n- [x] d\n'), isTrue);
      }
    });

    test('blockSourceStart is the start of the chunk holding the block', () {
      final parser = IncrementalMarkdownParser();
      // A list right after a paragraph stays in the paragraph's chunk (it might continue a list).
      const data = 'one\n\ntwo\n\n- [ ] x\n\nthree\n';
      final blocks = parser.parse(data);
      expect(blocks, hasLength(4));
      expect(parser.blockSourceStart(0), 0);
      expect(parser.blockSourceStart(1), data.indexOf('two'));
      expect(parser.blockSourceStart(2), data.indexOf('two'));
      expect(parser.blockSourceStart(3), data.indexOf('three'));
    });
  });

  test('a block without tasks has none', () {
    final parser = IncrementalMarkdownParser();
    final blocks = parser.parse('- a\n- b\n\n[ ] not a task\n');
    expect(_tasks(parser, blocks), isEmpty);
    expect(parser.taskAt(blocks, 0, 0), isNull);
    expect(parser.taskAt(blocks, 9, 0), isNull);
  });
}
