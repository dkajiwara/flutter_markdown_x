// MarkdownWidget.builders and paddingBuilders: the call protocol of flutter_markdown's
// MarkdownBuilder, reproduced over the IR (doc/flutter_markdown_compat.md, sections 2.5, 2.6, 5a).
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_markdown_x/math.dart' show markdownXMathExtension;
import 'package:flutter_markdown_x/src/flutter_markdown/md_bridge.dart'
    show debugMdBridgeRuns;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

typedef _Call = ({String method, String tag, Map<String, String> attributes});

class _Recorder extends MarkdownElementBuilder {
  _Recorder(this.log, {this.after, this.keepText = false});

  final List<String> log;
  final Widget? Function(md.Element element)? after;
  final bool keepText;
  final List<_Call> calls = [];
  final List<TextStyle?> preferred = [];
  final List<TextStyle?> parent = [];

  @override
  bool isBlockElement() => false;

  @override
  void visitElementBefore(md.Element element) {
    calls.add((
      method: 'before',
      tag: element.tag,
      attributes: Map.of(element.attributes),
    ));
    log.add('before:${element.tag}');
  }

  @override
  Widget? visitText(md.Text t, TextStyle? preferredStyle) {
    calls.add((method: 'text', tag: t.text, attributes: const {}));
    log.add('text:${t.text}');
    if (keepText) return Text(t.text);
    return null;
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    calls.add((
      method: 'after',
      tag: element.tag,
      attributes: Map.of(element.attributes),
    ));
    preferred.add(preferredStyle);
    parent.add(parentStyle);
    log.add('after:${element.tag}:${element.textContent}');
    return after?.call(element);
  }
}

class _Padding extends MarkdownPaddingBuilder {
  _Padding(this.log, this.value);

  final List<String> log;
  final EdgeInsets value;
  int getPaddingCalls = 0;

  @override
  void visitElementBefore(md.Element element) =>
      log.add('padding-before:${element.tag}');

  @override
  EdgeInsets getPadding() {
    getPaddingCalls++;
    return value;
  }
}

Future<void> _pump(
  WidgetTester tester,
  String data, {
  Map<String, MarkdownElementBuilder> builders = const {},
  Map<String, MarkdownPaddingBuilder> paddingBuilders = const {},
  MarkdownTapLinkCallback? onTapLink,
  MarkdownStyleSheet? styleSheet,
  md.ExtensionSet? extensionSet,
  List<MarkdownXExtension> extensions = const [],
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: MarkdownBody(
          data: data,
          builders: builders,
          paddingBuilders: paddingBuilders,
          onTapLink: onTapLink,
          styleSheet: styleSheet,
          extensionSet: extensionSet,
          extensions: extensions,
        ),
      ),
    ),
  ),
);

void main() {
  group('call protocol', () {
    testWidgets(
      'a code builder sees fenced code with class and trailing newline',
      (tester) async {
        final log = <String>[];
        final b = _Recorder(log, after: (e) => Text('X:${e.textContent}'));
        await _pump(tester, '```dart\nvar x;\n```\n', builders: {'code': b});
        expect(b.calls.map((c) => c.method), ['before', 'after']);
        expect(b.calls.first.attributes, {'class': 'language-dart'});
        expect(log, ['before:code', 'after:code:var x;\n']);
        expect(find.text('X:var x;\n'), findsOneWidget);
        expect(find.text('var x;'), findsNothing);
        // The widget is still inside the code block's decoration.
        final container = find.ancestor(
          of: find.text('X:var x;\n'),
          matching: find.byType(Container),
        );
        expect(container, findsWidgets);
      },
    );

    testWidgets(
      'preferredStyle is the sheet style of the tag, parentStyle the pre style',
      (tester) async {
        final sheet = MarkdownStyleSheet(
          code: const TextStyle(fontSize: 11),
          codeblockDecoration: const BoxDecoration(),
        );
        final b = _Recorder([]);
        await _pump(
          tester,
          '```\nx\n```\n',
          builders: {'code': b},
          styleSheet: sheet,
        );
        expect(b.preferred.single?.fontSize, 11);
        expect(b.parent.single, isNotNull);
      },
    );

    testWidgets('inline code reaches the same builder without a class', (
      tester,
    ) async {
      final b = _Recorder([]);
      await _pump(tester, 'a `x` b\n', builders: {'code': b});
      expect(b.calls.map((c) => c.method), ['before', 'after']);
      expect(b.calls.first.attributes, isEmpty);
    });

    testWidgets('visitText goes to the block builder and null drops the text', (
      tester,
    ) async {
      final log = <String>[];
      final b = _Recorder(log);
      await _pump(tester, 'hello *world*\n', builders: {'p': b});
      expect(log, [
        'before:p',
        'text:hello ',
        'text:world',
        'after:p:hello world',
      ]);
      expect(find.textContaining('hello'), findsNothing);
    });

    testWidgets('a block builder that returns text keeps the text', (
      tester,
    ) async {
      final b = _Recorder([], keepText: true);
      await _pump(tester, 'hello\n', builders: {'p': b});
      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('a block result replaces the block; li keeps the bullet row', (
      tester,
    ) async {
      final b = _Recorder([], after: (_) => const Text('ITEM'));
      await _pump(tester, '- a\n- b\n', builders: {'li': b});
      expect(find.text('ITEM'), findsNWidgets(2));
      expect(find.text('•'), findsNWidgets(2));
    });

    testWidgets('blockquote result stays inside the decoration', (
      tester,
    ) async {
      final b = _Recorder([], after: (_) => const Text('QUOTE'));
      await _pump(tester, '> q\n', builders: {'blockquote': b});
      expect(find.text('QUOTE'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('QUOTE'),
          matching: find.byType(DecoratedBox),
        ),
        findsWidgets,
      );
    });

    testWidgets('hr and table results are used as they are', (tester) async {
      final hr = _Recorder([], after: (_) => const Text('RULE'));
      final table = _Recorder([], after: (_) => const Text('TABLE'));
      await _pump(
        tester,
        'a\n\n---\n\n| h |\n|---|\n| c |\n',
        builders: {'hr': hr, 'table': table},
      );
      expect(find.text('RULE'), findsOneWidget);
      expect(find.text('TABLE'), findsOneWidget);
    });

    testWidgets('table cells call th and td builders with align', (
      tester,
    ) async {
      final th = _Recorder([]);
      final td = _Recorder([], after: (e) => Text('C:${e.textContent}'));
      await _pump(
        tester,
        '| a | b |\n|:--|--:|\n| 1 | |\n',
        builders: {'th': th, 'td': td},
      );
      expect(
        th.calls.where((c) => c.method == 'before').map((c) => c.attributes),
        [
          {'align': 'left'},
          {'align': 'right'},
        ],
      );
      expect(find.text('C:1'), findsOneWidget);
      expect(find.text('C:'), findsOneWidget);
    });

    testWidgets(
      'an inline result replaces the inline; img gets src, alt, title',
      (tester) async {
        final b = _Recorder(
          [],
          after: (e) => Text('IMG:${e.attributes['alt']}'),
        );
        await _pump(tester, '![alt](a.png#10x20 "T")\n', builders: {'img': b});
        expect(b.calls.first.attributes, {
          'src': 'a.png#10x20',
          'alt': 'alt',
          'title': 'T',
        });
        expect(find.text('IMG:alt'), findsOneWidget);
      },
    );

    testWidgets('an a builder owns the link: no onTapLink', (tester) async {
      final taps = <String>[];
      final b = _Recorder([]);
      await _pump(
        tester,
        '[link](http://x "t")\n',
        builders: {'a': b},
        onTapLink: (text, href, title) => taps.add(text),
      );
      expect(b.calls.first.attributes, {'href': 'http://x', 'title': 't'});
      await tester.tapAt(
        tester.getTopLeft(find.byType(RichText).first) + const Offset(3, 3),
      );
      expect(taps, isEmpty);
    });

    testWidgets('the task checkbox is an input element', (tester) async {
      final b = _Recorder([]);
      await _pump(tester, '- [x] done\n- [ ] todo\n', builders: {'input': b});
      expect(
        b.calls.where((c) => c.method == 'before').map((c) => c.attributes),
        [
          {'type': 'checkbox', 'checked': 'true'},
          {'type': 'checkbox'},
        ],
      );
    });

    testWidgets('a tight list item is not wrapped in p', (tester) async {
      final p = _Recorder([]);
      final li = _Recorder([], keepText: true);
      await _pump(tester, '- a\n- b\n', builders: {'p': p, 'li': li});
      expect(p.calls, isEmpty);
      expect(li.calls.where((c) => c.method == 'text').map((c) => c.tag), [
        'a',
        'b',
      ]);
    });

    testWidgets('a loose list item is wrapped in p', (tester) async {
      final p = _Recorder([]);
      await _pump(tester, '- a\n\n- b\n', builders: {'p': p});
      expect(p.calls.where((c) => c.method == 'before'), hasLength(2));
    });
  });

  group('laziness', () {
    testWidgets('empty builders and unrelated blocks never run the bridge', (
      tester,
    ) async {
      final before = debugMdBridgeRuns;
      await _pump(tester, '# t\n\ntext\n');
      expect(debugMdBridgeRuns, before);
      final b = _Recorder([]);
      await _pump(tester, '# t\n\ntext\n', builders: {'code': b});
      expect(debugMdBridgeRuns, before);
      expect(b.calls, isEmpty);
    });

    testWidgets('only the block with a registered tag is bridged', (
      tester,
    ) async {
      final before = debugMdBridgeRuns;
      final b = _Recorder([]);
      await _pump(tester, '# t\n\n`x`\n\ntext\n', builders: {'code': b});
      expect(debugMdBridgeRuns - before, 1);
    });
  });

  group('paddingBuilders', () {
    testWidgets('p padding applies to a top-level paragraph', (tester) async {
      final log = <String>[];
      final pad = _Padding(log, const EdgeInsets.all(7));
      await _pump(tester, 'hello\n', paddingBuilders: {'p': pad});
      expect(log, ['padding-before:p']);
      expect(pad.getPaddingCalls, 1);
      final padding = tester.widget<Padding>(
        find
            .ancestor(of: find.text('hello'), matching: find.byType(Padding))
            .first,
      );
      expect(padding.padding, const EdgeInsets.all(7));
    });

    testWidgets('a blockquote padding affects the text inside it', (
      tester,
    ) async {
      final pad = _Padding([], const EdgeInsets.all(9));
      await _pump(tester, '> q\n', paddingBuilders: {'blockquote': pad});
      final paddings = tester
          .widgetList<Padding>(
            find.ancestor(of: find.text('q'), matching: find.byType(Padding)),
          )
          .map((p) => p.padding);
      expect(paddings, contains(const EdgeInsets.all(9)));
    });

    testWidgets('img padding wraps the image', (tester) async {
      final pad = _Padding([], const EdgeInsets.all(5));
      await _pump(tester, '![a](x.png)\n', paddingBuilders: {'img': pad});
      expect(pad.getPaddingCalls, 1);
      expect(
        find.byWidgetPredicate(
          (w) => w is Padding && w.padding == const EdgeInsets.all(5),
        ),
        findsOneWidget,
      );
    });

    testWidgets('hr padding wraps the rule', (tester) async {
      final pad = _Padding([], const EdgeInsets.all(4));
      await _pump(tester, 'a\n\n---\n', paddingBuilders: {'hr': pad});
      expect(
        find.byWidgetPredicate(
          (w) => w is Padding && w.padding == const EdgeInsets.all(4),
        ),
        findsOneWidget,
      );
    });
  });

  group('tag mapping', () {
    Future<_Recorder> record(
      WidgetTester tester,
      String data,
      String tag, {
      md.ExtensionSet? extensionSet,
      List<MarkdownXExtension> extensions = const [],
    }) async {
      final r = _Recorder([]);
      await _pump(
        tester,
        data,
        builders: {tag: r},
        extensionSet: extensionSet,
        extensions: extensions,
      );
      return r;
    }

    testWidgets('lists: start, contains-task-list and task-list-item', (
      tester,
    ) async {
      final ol = await record(tester, '3. a\n4. b\n', 'ol');
      expect(ol.calls.first.attributes, {'start': '3'});
      final ul = await record(tester, '- [x] a\n- b\n', 'ul');
      expect(ul.calls.first.attributes, {'class': 'contains-task-list'});
      final li = await record(tester, '- [x] a\n- b\n', 'li');
      expect(
        li.calls.where((c) => c.method == 'before').map((c) => c.attributes),
        [
          {'class': 'task-list-item'},
          <String, String>{},
        ],
      );
    });

    testWidgets('pre keeps the rest of the info string in data-metadata', (
      tester,
    ) async {
      final pre = await record(
        tester,
        '```dart title="x" {1}\ncode\n```\n',
        'pre',
      );
      expect(pre.calls.first.attributes, {'data-metadata': 'title="x" {1}'});
      final code = await record(
        tester,
        '```dart title="x"\ncode\n```\n',
        'code',
      );
      expect(code.calls.first.attributes, {'class': 'language-dart'});
    });

    testWidgets('an indented code block has no class and a trailing newline', (
      tester,
    ) async {
      final code = await record(tester, '    plain\n', 'code');
      expect(code.calls.first.attributes, isEmpty);
      expect(code.log.last, 'after:code:plain\n');
    });

    testWidgets('gitHubWeb gives headings a generatedId', (tester) async {
      String? id;
      final b = _Recorder(
        [],
        after: (e) {
          id = e.generatedId;
          return null;
        },
      );
      await _pump(
        tester,
        '## Hello World\n',
        builders: {'h2': b},
        extensionSet: md.ExtensionSet.gitHubWeb,
      );
      expect(id, 'hello-world');
      id = 'unset';
      await _pump(
        tester,
        '## Hello World\n',
        builders: {'h2': b},
        extensionSet: md.ExtensionSet.gitHubFlavored,
      );
      expect(id, isNull);
    });

    testWidgets('alerts are div.markdown-alert with a title paragraph', (
      tester,
    ) async {
      final div = await record(tester, '> [!NOTE]\n> body\n', 'div');
      expect(div.calls.first.attributes, {
        'class': 'markdown-alert markdown-alert-note',
      });
      expect(div.log.last, 'after:div:Notebody');
    });

    testWidgets('HTML-derived nodes: span style, details and summary', (
      tester,
    ) async {
      final span = await record(
        tester,
        'a <span style="color:red">r</span>\n',
        'span',
      );
      expect(span.calls.first.attributes, {'style': 'color: #ff0000'});
      final details = await record(
        tester,
        '<details open>\n<summary>S</summary>\n\nbody\n\n</details>\n',
        'details',
      );
      expect(details.calls.first.attributes, {'open': ''});
      final summary = await record(
        tester,
        '<details>\n<summary>S</summary>\n\nbody\n\n</details>\n',
        'summary',
      );
      expect(summary.log.last, 'after:summary:S');
    });

    testWidgets('math nodes carry tex and display', (tester) async {
      final inline = await record(
        tester,
        'a \$x^2\$ b\n',
        'math',
        extensions: [markdownXMathExtension],
      );
      expect(inline.calls.first.attributes['tex'], 'x^2');
      expect(inline.calls.first.attributes['display'], 'false');
      final display = await record(
        tester,
        '\$\$\nx\n\$\$\n',
        'math',
        extensions: [markdownXMathExtension],
      );
      expect(display.calls.first.attributes['display'], 'true');
      expect(display.log.last, 'after:math:x');
    });

    testWidgets('a custom inline syntax node is reached by its type', (
      tester,
    ) async {
      final ext = MarkdownXExtension(
        inlineSyntaxes: [
          MarkdownXInlineSyntax(
            pattern: RegExp(r'~~~(\w+)~~~'),
            build: (m) => MdxCustomInline('sub', children: [MdxText(m[1]!)]),
          ),
        ],
      );
      final b = _Recorder([], after: (e) => Text('SUB:${e.textContent}'));
      await _pump(
        tester,
        'x ~~~y~~~ z\n',
        builders: {'sub': b},
        extensions: [ext],
      );
      expect(b.log, ['before:sub', 'after:sub:y']);
      expect(find.textContaining('SUB:y', findRichText: true), findsOneWidget);
    });

    testWidgets('a footnote reference and definition', (tester) async {
      final sup = await record(tester, 'a[^1]\n\n[^1]: n\n', 'sup');
      expect(sup.calls.first.attributes, {'class': 'footnote-ref'});
      final li = await record(tester, 'a[^1]\n\n[^1]: n\n', 'li');
      expect(li.calls.first.attributes, {'id': 'fn-1'});
      final section = await record(tester, 'a[^1]\n\n[^1]: n\n', 'section');
      expect(section.calls.first.attributes, {'class': 'footnotes'});
    });
  });

  group('caching', () {
    testWidgets(
      'a parent that rebuilds with new builders calls them once per element',
      (tester) async {
        var calls = 0;
        late StateSetter rebuild;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  // A new builder instance on every build, as typical flutter_markdown code does.
                  return MarkdownBody(
                    data: '```dart\nx\n```\n\n```\ny\n```\n\ntext\n',
                    builders: {
                      'code': _Recorder(
                        [],
                        after: (_) {
                          calls++;
                          return null;
                        },
                      ),
                    },
                  );
                },
              ),
            ),
          ),
        );
        expect(calls, 2);
        for (var i = 0; i < 10; i++) {
          rebuild(() {});
          await tester.pump();
        }
        expect(calls, 2);
      },
    );
  });
}
