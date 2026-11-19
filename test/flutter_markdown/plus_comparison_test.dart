// Behavioral comparison against flutter_markdown_plus 1.0.12 (doc/flutter_markdown_compat.md,
// section 6.2). The same documents are rendered by both packages with recording builders on the
// common tags; the sequence of calls (method, tag, attributes, text content), the arguments of
// onTapLink, imageBuilder, checkboxBuilder and bulletBuilder are compared.
//
// Differences that cannot be removed are listed in [_knownDifferences] and in the tests at the
// end of this file. Each one is an explicit expectation on both sides, never a skip.
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart' as fmp;
import 'package:flutter_markdown_x/flutter_markdown_x.dart' as x;
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';

import '../support/sdk_material.dart';

/// Shared recording core. `md.Element` is the same class in both packages.
class _Core {
  final List<String> log = [];

  void before(md.Element e) => log.add('before ${e.tag} ${_attrs(e)}');

  void text(md.Text t) => log.add('text ${_esc(t.text)}');

  void after(md.Element e, bool preferred, bool parent) => log.add(
    'after ${e.tag} ${_attrs(e)} ${_esc(e.textContent)} '
    'preferred=$preferred parent=$parent',
  );

  static String _esc(String s) => s.replaceAll('\n', r'\n');

  static String _attrs(md.Element e) {
    final keys = e.attributes.keys.toList()..sort();
    return '{${keys.map((k) => '$k=${e.attributes[k]}').join(', ')}}';
  }
}

class _XRecorder extends x.MarkdownElementBuilder {
  _XRecorder(this.core);

  final _Core core;

  @override
  void visitElementBefore(md.Element element) => core.before(element);

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    core.text(text);
    return null;
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    core.after(element, preferredStyle != null, parentStyle != null);
    return null;
  }
}

class _PlusRecorder extends fmp.MarkdownElementBuilder {
  _PlusRecorder(this.core);

  final _Core core;

  @override
  void visitElementBefore(md.Element element) => core.before(element);

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    core.text(text);
    return null;
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    core.after(element, preferredStyle != null, parentStyle != null);
    return null;
  }
}

const _blockish = [
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'p',
  'pre',
  'li',
  'blockquote',
  'hr',
  'ul',
  'ol', //
];
const _inlineish = ['code', 'a', 'img', 'em', 'strong', 'del', 'input', 'sup'];
const _tableTags = ['table', 'thead', 'tbody', 'tr'];

class _XPadding extends x.MarkdownPaddingBuilder {
  _XPadding(this.log);

  final List<String> log;

  @override
  void visitElementBefore(md.Element element) =>
      log.add('before ${element.tag}');

  @override
  EdgeInsets getPadding() {
    log.add('getPadding');
    return const EdgeInsets.all(2);
  }
}

class _PlusPadding extends fmp.MarkdownPaddingBuilder {
  _PlusPadding(this.log);

  final List<String> log;

  @override
  void visitElementBefore(md.Element element) =>
      log.add('before ${element.tag}');

  @override
  EdgeInsets getPadding() {
    log.add('getPadding');
    return const EdgeInsets.all(2);
  }
}

/// flutter_markdown_plus is pumped inside the SDK `MaterialApp`, this package inside the
/// `material_ui` one (see test/support/sdk_material.dart).
Widget _app(Widget child) => child is fmp.MarkdownBody
    ? sdkMaterialApp(child)
    : MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

Future<List<String>> _calls(
  WidgetTester tester,
  String data,
  List<String> tags, {
  required bool plus,
}) async {
  final core = _Core();
  if (plus) {
    await tester.pumpWidget(
      _app(
        fmp.MarkdownBody(
          data: data,
          builders: {for (final t in tags) t: _PlusRecorder(core)},
        ),
      ),
    );
  } else {
    await tester.pumpWidget(
      _app(
        x.MarkdownBody(
          data: data,
          builders: {for (final t in tags) t: _XRecorder(core)},
        ),
      ),
    );
  }
  return core.log;
}

Future<List<String>> _paddings(
  WidgetTester tester,
  String data,
  List<String> tags, {
  required bool plus,
}) async {
  final log = <String>[];
  if (plus) {
    await tester.pumpWidget(
      _app(
        fmp.MarkdownBody(
          data: data,
          paddingBuilders: {for (final t in tags) t: _PlusPadding(log)},
        ),
      ),
    );
  } else {
    await tester.pumpWidget(
      _app(
        x.MarkdownBody(
          data: data,
          paddingBuilders: {for (final t in tags) t: _XPadding(log)},
        ),
      ),
    );
  }
  return log;
}

const _documents = <String, String>{
  'headings and paragraphs': '# Title\n\nText with *em* and **strong** and ~~del~~.\n\n## Two\n\n### Three\n',
  'links and images':
      'A [link](http://x.y "T") and ![alt](a.png#10x20 "it") and ![](b.png)\n\n'
      '[a *b* c](http://z.w)\n\nhttps://example.com/p?q=1\n',
  'code': '```dart\nvar x = 1;\n```\n\n```\nplain\n```\n\n    indented\n\ninline `c` here\n',
  'lists':
      '- a\n- b\n  - c\n  - d\n\n3. three\n4. four\n\n- loose a\n\n- loose b\n',
  'task list': '- [x] done\n- [ ] todo\n\n1. [x] one\n2. [ ] two\n',
  'blockquote': '> quote *e*\n>\n> - item\n> - item2\n\n> > nested\n',
  'hr': 'a\n\n---\n\nb\n',
  'soft and hard breaks': 'line one\nline two  \nline three\n',
  'emphasis nesting': '***both*** and **a *b* c**\n',
};

/// Table tags. A `th` or `td` builder cannot be compared: in flutter_markdown_plus it replaces the
/// code that adds the cell to its row, so the table asserts (see the known differences below).
const _tableDocuments = <String, String>{
  'table': '| a | b | c |\n|:--|:-:|--:|\n| 1 | **2** | |\n| x | y | z |\n',
};

void main() {
  group('builder call sequences equal flutter_markdown_plus', () {
    for (final entry in _documents.entries) {
      testWidgets(entry.key, (tester) async {
        final tags = [..._blockish, ..._inlineish];
        final ours = await _calls(tester, entry.value, tags, plus: false);
        final plus = await _calls(tester, entry.value, tags, plus: true);
        expect(ours, isNotEmpty);
        expect(ours, plus);
      });
    }

    for (final entry in _tableDocuments.entries) {
      testWidgets(entry.key, (tester) async {
        final ours = await _calls(tester, entry.value, _tableTags, plus: false);
        final plus = await _calls(tester, entry.value, _tableTags, plus: true);
        expect(ours, isNotEmpty);
        expect(ours, plus);
      });
    }
  });

  group('padding builders equal flutter_markdown_plus', () {
    for (final entry in _documents.entries) {
      testWidgets(entry.key, (tester) async {
        const tags = [
          'p',
          'h1',
          'h2',
          'h3',
          'blockquote',
          'ul',
          'ol',
          'img',
          'hr',
        ];
        final ours = await _paddings(tester, entry.value, tags, plus: false);
        final plus = await _paddings(tester, entry.value, tags, plus: true);
        expect(ours, plus);
      });
    }
  });

  group('callbacks equal flutter_markdown_plus', () {
    const doc =
        'Go [one](http://a.b/p%20q?x=1&y=2#frag) or [two *em*](http://c.d "Title") '
        'or <http://auto.link> or https://bare.example/x.\n';

    testWidgets('onTapLink receives (text, href, title)', (tester) async {
      Future<List<String>> run({required bool plus}) async {
        final taps = <String>[];
        void onTap(String text, String? href, String title) =>
            taps.add('$text|$href|$title');
        await tester.pumpWidget(
          _app(
            plus
                ? fmp.MarkdownBody(data: doc, onTapLink: onTap)
                : x.MarkdownBody(data: doc, onTapLink: onTap),
          ),
        );
        for (final label in [
          'one',
          'two ',
          'http://auto.link',
          'https://bare',
        ]) {
          await tester.tapOnText(find.textRange.ofSubstring(label));
        }
        return taps;
      }

      final ours = await run(plus: false);
      final plus = await run(plus: true);
      expect(ours, hasLength(4));
      expect(ours, plus);
      expect(ours.first, 'one|http://a.b/p%20q?x=1&y=2#frag|');
      expect(ours[1], 'two em|http://c.d|Title');
    });

    testWidgets('imageBuilder receives (uri, title, alt)', (tester) async {
      const images =
          '![alt](a.png#10x20 "it") ![](b.png) ![x](http://h/i.png "t")\n';
      Future<List<String>> run({required bool plus}) async {
        final calls = <String>[];
        Widget builder(Uri uri, String? title, String? alt) {
          calls.add('$uri|$title|$alt');
          return const SizedBox();
        }

        await tester.pumpWidget(
          _app(
            plus
                // ignore: deprecated_member_use
                ? fmp.MarkdownBody(data: images, imageBuilder: builder)
                // ignore: deprecated_member_use
                : x.MarkdownBody(data: images, imageBuilder: builder),
          ),
        );
        return calls;
      }

      final ours = await run(plus: false);
      expect(ours, hasLength(3));
      expect(ours, await run(plus: true));
      expect(ours.first, 'a.png|it|alt');
    });

    testWidgets('checkboxBuilder and bulletBuilder sequences', (tester) async {
      const lists =
          '- a\n- b\n  - c\n\n3. three\n4. four\n   1. nested\n\n- [x] done\n- [ ] todo\n';
      Future<List<String>> run({required bool plus}) async {
        final calls = <String>[];
        Widget checkbox(bool v) {
          calls.add('checkbox $v');
          return const SizedBox();
        }

        Widget bullet(Object p) => const SizedBox();
        if (plus) {
          await tester.pumpWidget(
            _app(
              fmp.MarkdownBody(
                data: lists,
                checkboxBuilder: checkbox,
                bulletBuilder: (p) {
                  calls.add('bullet ${p.index} ${p.style.name} ${p.nestLevel}');
                  return bullet(p);
                },
              ),
            ),
          );
        } else {
          await tester.pumpWidget(
            _app(
              x.MarkdownBody(
                data: lists,
                checkboxBuilder: checkbox,
                bulletBuilder: (p) {
                  calls.add('bullet ${p.index} ${p.style.name} ${p.nestLevel}');
                  return bullet(p);
                },
              ),
            ),
          );
        }
        return calls;
      }

      final ours = await run(plus: false);
      expect(ours, contains('bullet 2 orderedList 0'));
      expect(ours, contains('bullet 0 orderedList 1'));
      expect(ours, contains('checkbox true'));
      final plus = await run(plus: true);
      // The bullet of an item is built when its row is built (before the nested list here,
      // after it in plus), so the order differs; the set of calls is the same.
      expect([...ours]..sort(), [...plus]..sort());
      expect(ours, [
        'bullet 0 unorderedList 0',
        'bullet 1 unorderedList 0',
        'bullet 0 unorderedList 1',
        'bullet 2 orderedList 0',
        'bullet 3 orderedList 0',
        'bullet 0 orderedList 1',
        'checkbox true',
        'checkbox false',
      ]);
      expect(plus, [
        'bullet 0 unorderedList 0',
        'bullet 0 unorderedList 1',
        'bullet 1 unorderedList 0',
        'bullet 2 orderedList 0',
        'bullet 0 orderedList 1',
        'bullet 3 orderedList 0',
        'checkbox true',
        'checkbox false',
      ]);
    });
  });

  group('known differences (explicit expectations)', () {
    testWidgets(
      'footnotes: this package keeps one extra hr before the definitions',
      (tester) async {
        const doc = 'Footnote[^1] here.\n\n[^1]: The note.\n';
        final tags = [..._blockish, ..._inlineish, 'section'];
        final ours = await _calls(tester, doc, tags, plus: false);
        final plus = await _calls(tester, doc, tags, plus: true);
        expect(ours, isNot(plus));
        expect(
          ours.where((l) => !l.contains(' hr ')).toList(),
          plus,
          reason: 'only the hr pair differs',
        );
        expect(ours.where((l) => l.contains(' hr ')), hasLength(2));
        expect(plus.where((l) => l.contains(' hr ')), isEmpty);
      },
    );

    testWidgets('raw HTML: plus shows it as text, this package interprets it', (
      tester,
    ) async {
      const doc = 'a <b>bold</b> and <span style="color:red">r</span>\n';
      final tags = [..._blockish, 'strong', 'span'];
      final ours = await _calls(tester, doc, tags, plus: false);
      final plus = await _calls(tester, doc, tags, plus: true);
      expect(plus.where((l) => l.startsWith('before strong')), isEmpty);
      expect(plus.where((l) => l.startsWith('before span')), isEmpty);
      expect(ours, contains('before strong {}'));
      expect(ours, contains('before span {style=color: #ff0000}'));
    });

    testWidgets(
      'loose task lists: the same input builder calls; this package shows the checkbox, plus a bullet',
      (tester) async {
        // The Rust parser used to drop the task marker of a loose item; it now reports it.
        // plus (like flutter_markdown) only checks li.children[0], which is the paragraph for a
        // loose item, so it shows a bullet; this package shows the checkbox the source asks for.
        const doc = '- [x] a\n\n- [ ] b\n';
        Future<(List<String>, List<String>)> run({required bool plus}) async {
          final calls = <String>[];
          final core = _Core();
          Widget bullet(int index) {
            calls.add('bullet $index');
            return const SizedBox();
          }

          Widget checkbox(bool value) {
            calls.add('checkbox $value');
            return const SizedBox();
          }

          await tester.pumpWidget(
            _app(
              plus
                  ? fmp.MarkdownBody(
                      data: doc,
                      bulletBuilder: (p) => bullet(p.index),
                      checkboxBuilder: checkbox,
                      builders: {'input': _PlusRecorder(core)},
                    )
                  : x.MarkdownBody(
                      data: doc,
                      bulletBuilder: (p) => bullet(p.index),
                      checkboxBuilder: checkbox,
                      builders: {'input': _XRecorder(core)},
                    ),
            ),
          );
          return (calls, core.log);
        }

        final ours = await run(plus: false);
        final plus = await run(plus: true);
        expect(ours.$1, ['checkbox true', 'checkbox false']);
        expect(plus.$1, ['bullet 0', 'bullet 1']);
        expect(ours.$2, plus.$2);
        expect(
          ours.$2.where((l) => l.startsWith('before input')),
          hasLength(2),
        );
      },
    );

    testWidgets('th and td builders: plus asserts, this package calls them', (
      tester,
    ) async {
      const doc = '| a | b |\n|:--|--:|\n| 1 | |\n';
      final ours = await _calls(tester, doc, ['th', 'td'], plus: false);
      expect(tester.takeException(), isNull);
      expect(ours, [
        'before th {align=left}',
        'after th {align=left} a preferred=true parent=true',
        'before th {align=right}',
        'after th {align=right} b preferred=true parent=true',
        'before td {align=left}',
        'after td {align=left} 1 preferred=true parent=true',
        'before td {align=right}',
        'after td {align=right}  preferred=true parent=true',
      ]);
      // flutter_markdown_plus replaces the code that adds the cell to its row, so the table has
      // empty rows and asserts.
      await _calls(tester, doc, ['th', 'td'], plus: true);
      expect(tester.takeException(), isNotNull);
    });

    testWidgets('a table builder result is used here and discarded by plus', (
      tester,
    ) async {
      const doc = '| a |\n|---|\n| 1 |\n';
      Future<bool> shown({required bool plus}) async {
        await tester.pumpWidget(
          _app(
            plus
                ? fmp.MarkdownBody(
                    data: doc,
                    builders: {'table': _PlusResult(const Text('RESULT'))},
                  )
                : x.MarkdownBody(
                    data: doc,
                    builders: {'table': _XResult(const Text('RESULT'))},
                  ),
          ),
        );
        return find.text('RESULT').evaluate().isNotEmpty;
      }

      expect(await shown(plus: false), isTrue);
      expect(await shown(plus: true), isFalse);
    });

    testWidgets(
      'sizedImageBuilder follows flutter_markdown 0.7.7+1 (plus has none)',
      (tester) async {
        final configs = <x.MarkdownImageConfig>[];
        await tester.pumpWidget(
          _app(
            x.MarkdownBody(
              data: '![alt](a.png#10x20 "it") ![n](b.png#x) <img src="c.png" width="5" height="6">\n',
              sizedImageBuilder: (config) {
                configs.add(config);
                return const SizedBox();
              },
            ),
          ),
        );
        // Records, not strings: on the web `10.0.toString()` is `10`.
        expect(
          configs.map(
            (c) => (c.uri.toString(), c.alt, c.title, c.width, c.height),
          ),
          [
            ('a.png', 'alt', 'it', 10.0, 20.0),
            ('b.png', 'n', null, null, null),
            ('c.png', null, null, 5.0, 6.0),
          ],
        );
      },
    );
  });
}

class _XResult extends x.MarkdownElementBuilder {
  _XResult(this.widget);

  final Widget widget;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => widget;
}

class _PlusResult extends fmp.MarkdownElementBuilder {
  _PlusResult(this.widget);

  final Widget widget;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => widget;
}
