// Tapping a task list checkbox reports a MarkdownXTask; the app rewrites its own data.
import 'dart:ui' show CheckedState;

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_markdown_x/src/widgets/renderer.dart'
    show debugMdxBlockBuildCount;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Kind { markdown, body, sliver }

class _Host extends StatefulWidget {
  const _Host({
    super.key,
    required this.initial,
    this.kind = _Kind.body,
    this.interactive = true,
    this.streaming = false,
    this.selectable = false,
    this.extensions = const [],
    this.checkboxBuilder,
    this.builders = const {},
  });

  final String initial;
  final _Kind kind;
  final bool interactive;
  final bool streaming;
  final bool selectable;
  final List<MarkdownXExtension> extensions;
  final MarkdownCheckboxBuilder? checkboxBuilder;
  final Map<String, MarkdownElementBuilder> builders;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late String data = widget.initial;
  final taps = <MarkdownXTask>[];
  bool apply = true;

  void edit(String Function(String) change) =>
      setState(() => data = change(data));

  void _tap(MarkdownXTask task) {
    taps.add(task);
    if (apply) setState(() => data = task.toggle(data));
  }

  @override
  Widget build(BuildContext context) {
    final callback = widget.interactive ? _tap : null;
    return switch (widget.kind) {
      _Kind.markdown => Markdown(
        data: data,
        streaming: widget.streaming,
        selectable: widget.selectable,
        extensions: widget.extensions,
        checkboxBuilder: widget.checkboxBuilder,
        builders: widget.builders,
        onTapCheckbox: callback,
      ),
      _Kind.body => SingleChildScrollView(
        child: MarkdownBody(
          data: data,
          streaming: widget.streaming,
          selectable: widget.selectable,
          extensions: widget.extensions,
          checkboxBuilder: widget.checkboxBuilder,
          builders: widget.builders,
          onTapCheckbox: callback,
        ),
      ),
      _Kind.sliver => CustomScrollView(
        slivers: [
          SliverMarkdown(
            data: data,
            streaming: widget.streaming,
            extensions: widget.extensions,
            checkboxBuilder: widget.checkboxBuilder,
            builders: widget.builders,
            onTapCheckbox: callback,
          ),
        ],
      ),
    };
  }
}

Future<GlobalKey<_HostState>> _pump(
  WidgetTester tester,
  String data, {
  _Kind kind = _Kind.body,
  bool interactive = true,
  bool streaming = false,
  bool selectable = false,
  List<MarkdownXExtension> extensions = const [],
  MarkdownCheckboxBuilder? checkboxBuilder,
  Map<String, MarkdownElementBuilder> builders = const {},
}) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final key = GlobalKey<_HostState>();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: _Host(
          key: key,
          initial: data,
          kind: kind,
          interactive: interactive,
          streaming: streaming,
          selectable: selectable,
          extensions: extensions,
          checkboxBuilder: checkboxBuilder,
          builders: builders,
        ),
      ),
    ),
  );
  await tester.pump();
  return key;
}

final _unchecked = find.byIcon(Icons.check_box_outline_blank);
final _checked = find.byIcon(Icons.check_box);

void main() {
  for (final kind in _Kind.values) {
    group(kind.name, () {
      testWidgets('a tap reports the task and the app rewrites its data', (
        tester,
      ) async {
        const data = '# Tasks\n\n- [ ] one\n- [x] two\n- [ ] three\n';
        final key = await _pump(tester, data, kind: kind);
        expect(_unchecked, findsNWidgets(2));
        expect(_checked, findsOneWidget);

        await tester.tap(_unchecked.last);
        await tester.pump();

        final state = key.currentState!;
        expect(state.taps, hasLength(1));
        final task = state.taps.single;
        expect(task.checked, isFalse);
        expect(task.index, 2);
        expect(task.markerStart, data.indexOf('[ ] three'));
        expect(task.markerEnd, task.markerStart + 3);
        expect(state.data, data.replaceFirst('[ ] three', '[x] three'));
        // The checkbox follows the data.
        expect(_unchecked, findsOneWidget);
        expect(_checked, findsNWidgets(2));
      });

      testWidgets('tapping a checked task unchecks it', (tester) async {
        final key = await _pump(tester, '- [x] done\n', kind: kind);
        await tester.tap(_checked);
        await tester.pump();
        expect(key.currentState!.taps.single.checked, isTrue);
        expect(key.currentState!.data, '- [ ] done\n');
        expect(_unchecked, findsOneWidget);
      });

      testWidgets('without onTapCheckbox nothing is interactive', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        final key = await _pump(
          tester,
          '- [ ] one\n- [x] two\n',
          kind: kind,
          interactive: false,
        );
        await tester.tap(_unchecked, warnIfMissed: false);
        await tester.pump();
        expect(key.currentState!.taps, isEmpty);
        expect(
          find.semantics
              .byPredicate(
                (n) => n.getSemanticsData().hasAction(SemanticsAction.tap),
              )
              .evaluate(),
          isEmpty,
        );
        handle.dispose();
      });
    });
  }

  group('which task is reported', () {
    testWidgets('nested lists, blockquotes and ordered lists', (tester) async {
      const data = '- [ ] a\n  - [x] b\n    - [ ] c\n\n> - [ ] d\n\n1. [x] e\n';
      final key = await _pump(tester, data);
      final state = key.currentState!..apply = false;
      final markers = [
        for (final m in RegExp(r'\[[ x]\]').allMatches(data)) m.start,
      ];
      // Tap each checkbox by its position on screen (top to bottom).
      final all = find.byWidgetPredicate(
        (w) =>
            w is Icon &&
            (w.icon == Icons.check_box ||
                w.icon == Icons.check_box_outline_blank),
      );
      expect(all, findsNWidgets(5));
      for (var i = 0; i < 5; i++) {
        await tester.tap(all.at(i));
        await tester.pump();
      }
      expect(state.taps.map((t) => t.index), [0, 1, 2, 3, 4]);
      expect(state.taps.map((t) => t.markerStart), markers);
      expect(state.taps.map((t) => t.checked), [
        false,
        true,
        false,
        false,
        true,
      ]);
    });

    testWidgets('two identical lists are told apart', (tester) async {
      const data = '- [ ] same\n\npara\n\n- [ ] same\n';
      final key = await _pump(tester, data);
      await tester.tap(_unchecked.last);
      await tester.pump();
      final task = key.currentState!.taps.single;
      expect(task.index, 1);
      expect(task.markerStart, data.lastIndexOf('[ ]'));
      expect(key.currentState!.data, '- [ ] same\n\npara\n\n- [x] same\n');
    });

    testWidgets('non-ASCII text and CRLF before the task', (tester) async {
      const data = '日本語 😀\r\n\r\n- [ ] é\r\n- [x] ü\r\n';
      final key = await _pump(tester, data);
      await tester.tap(_checked);
      await tester.pump();
      expect(key.currentState!.data, data.replaceFirst('[x]', '[ ]'));
    });

    testWidgets('with every extension and reference definitions', (
      tester,
    ) async {
      const data =
          '[r]: https://example.com\n\n> [!NOTE]\n> - [ ] in alert [r]\n\n- [x] plain [1]\n';
      final key = await _pump(
        tester,
        data,
        extensions: [markdownXEmojiExtension],
      );
      await tester.tap(_unchecked.first);
      await tester.pump();
      expect(key.currentState!.taps.single.index, 0);
      expect(key.currentState!.data, data.replaceFirst('[ ] in', '[x] in'));
    });

    testWidgets('selectable documents still react to taps', (tester) async {
      final key = await _pump(tester, '- [ ] a\n', selectable: true);
      await tester.tap(_unchecked);
      await tester.pump();
      expect(key.currentState!.data, '- [x] a\n');
    });
  });

  group('when the text moves', () {
    testWidgets(
      'text inserted before a task list rebuilds nothing and the tap is still right',
      (tester) async {
        const list = '- [ ] a\n- [x] b\n';
        final key = await _pump(tester, 'para\n\n$list');
        final before = debugMdxBlockBuildCount;
        key.currentState!.edit(
          (d) => 'a longer paragraph\n\nand another\n\n$d'.replaceFirst(
            'para\n\n',
            '',
          ),
        );
        await tester.pump();
        // Two paragraphs are new; the unchanged list block is not rebuilt.
        expect(debugMdxBlockBuildCount - before, 2);

        await tester.tap(_unchecked);
        await tester.pump();
        final task = key.currentState!.taps.single;
        final data = 'a longer paragraph\n\nand another\n\n$list';
        expect(task.markerStart, data.indexOf('[ ]'));
        expect(key.currentState!.data, data.replaceFirst('[ ] a', '[x] a'));
      },
    );

    testWidgets('a growing document keeps tapping the right marker', (
      tester,
    ) async {
      final key = await _pump(
        tester,
        '- [ ] a\n\npara\n\n- [x] b\n',
        streaming: true,
      );
      final state = key.currentState!;
      for (final more in ['\npara two\n', '\n- [ ] c\n', '- [ ] d\n']) {
        state.edit((d) => d + more);
        await tester.pump();
      }
      state.apply = false;
      final all = find.byWidgetPredicate(
        (w) =>
            w is Icon &&
            (w.icon == Icons.check_box ||
                w.icon == Icons.check_box_outline_blank),
      );
      expect(all, findsNWidgets(4));
      for (var i = 0; i < 4; i++) {
        await tester.tap(all.at(i));
        await tester.pump();
      }
      for (final task in state.taps) {
        expect(
          task.matches(state.data),
          isTrue,
          reason: '$task in ${state.data}',
        );
      }
      expect(state.taps.map((t) => t.index), [0, 1, 2, 3]);
    });

    testWidgets(
      'streaming: a tap on the unfinished tail refers to the current data',
      (tester) async {
        const data = '- [ ] a\n\n- [ ] b **half';
        final key = await _pump(tester, data, streaming: true);
        await tester.tap(_unchecked.last);
        await tester.pump();
        final state = key.currentState!;
        expect(state.taps.single.index, 1);
        expect(state.taps.single.markerStart, data.lastIndexOf('[ ]'));
        expect(state.data, '- [ ] a\n\n- [x] b **half');
      },
    );

    testWidgets('a stale task leaves new text alone', (tester) async {
      final key = await _pump(tester, '- [ ] a\n');
      final state = key.currentState!..apply = false;
      await tester.tap(_unchecked);
      await tester.pump();
      final task = state.taps.single;
      expect(task.toggle('x\n- [ ] a\n'), 'x\n- [ ] a\n');
    });
  });

  group('callbacks and rebuilds', () {
    testWidgets('a new closure is used without rebuilding blocks', (
      tester,
    ) async {
      final calls = <String>[];
      Widget app(void Function(MarkdownXTask) f) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarkdownBody(data: '- [ ] a\n', onTapCheckbox: f),
          ),
        ),
      );
      await tester.pumpWidget(app((_) => calls.add('first')));
      await tester.pump();
      final before = debugMdxBlockBuildCount;
      await tester.pumpWidget(app((_) => calls.add('second')));
      await tester.pump();
      expect(debugMdxBlockBuildCount, before);
      await tester.tap(_unchecked);
      expect(calls, ['second']);
    });

    testWidgets('turning the callback on and off switches interactivity', (
      tester,
    ) async {
      final calls = <MarkdownXTask>[];
      Widget app(void Function(MarkdownXTask)? f) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarkdownBody(data: '- [ ] a\n', onTapCheckbox: f),
          ),
        ),
      );
      await tester.pumpWidget(app(null));
      await tester.tap(_unchecked, warnIfMissed: false);
      expect(calls, isEmpty);
      await tester.pumpWidget(app(calls.add));
      await tester.tap(_unchecked);
      expect(calls, hasLength(1));
      await tester.pumpWidget(app(null));
      await tester.tap(_unchecked, warnIfMissed: false);
      expect(calls, hasLength(1));
    });
  });

  group('checkboxBuilder', () {
    testWidgets('the app widget is wrapped with the tap and the semantics', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final key = await _pump(
        tester,
        '- [ ] a\n- [x] b\n',
        checkboxBuilder: (checked) => Text(checked ? 'YES' : 'NO'),
      );
      await tester.tap(find.text('NO'));
      await tester.pump();
      final state = key.currentState!;
      expect(state.taps.single.checked, isFalse);
      expect(state.data, '- [x] a\n- [x] b\n');
      expect(find.text('YES'), findsNWidgets(2));
      expect(
        find.semantics
            .byPredicate(
              (n) =>
                  n.getSemanticsData().flagsCollection.isChecked ==
                      CheckedState.isTrue &&
                  n.getSemanticsData().hasAction(SemanticsAction.tap),
            )
            .evaluate(),
        hasLength(2),
      );
      handle.dispose();
    });

    testWidgets('without onTapCheckbox the builder output is untouched', (
      tester,
    ) async {
      final key = await _pump(
        tester,
        '- [ ] a\n',
        interactive: false,
        checkboxBuilder: (checked) => const Text('NO'),
      );
      await tester.tap(find.text('NO'), warnIfMissed: false);
      expect(key.currentState!.taps, isEmpty);
    });
  });

  group('keyboard', () {
    for (final entry in {
      'space': LogicalKeyboardKey.space,
      'enter': LogicalKeyboardKey.enter,
      'numpad enter': LogicalKeyboardKey.numpadEnter,
    }.entries) {
      testWidgets('${entry.key} toggles the focused checkbox', (tester) async {
        final key = await _pump(tester, '- [ ] a\n- [x] b\n');
        // The first Tab reaches the first checkbox, the second one the next.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(entry.value);
        await tester.pump();
        final state = key.currentState!;
        expect(state.taps.single.index, 0);
        expect(state.data, '- [x] a\n- [x] b\n');

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(entry.value);
        await tester.pump();
        expect(state.taps.last.index, 1);
        expect(state.data, '- [x] a\n- [ ] b\n');
      });
    }

    testWidgets('a non-interactive document is not focusable', (tester) async {
      final key = await _pump(tester, '- [ ] a\n', interactive: false);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(key.currentState!.taps, isEmpty);
    });
  });

  group('semantics', () {
    testWidgets('a checkbox exposes its state and a tap action', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final key = await _pump(tester, '- [ ] todo\n- [x] done\n');
      Iterable<SemanticsNode> nodes(CheckedState state) => find.semantics
          .byPredicate(
            (n) => n.getSemanticsData().flagsCollection.isChecked == state,
          )
          .evaluate();
      expect(nodes(CheckedState.isTrue), hasLength(1));
      expect(nodes(CheckedState.isFalse), hasLength(1));
      for (final node in [
        ...nodes(CheckedState.isTrue),
        ...nodes(CheckedState.isFalse),
      ]) {
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      }

      tester.semantics.tap(
        find.semantics.byPredicate(
          (n) =>
              n.getSemanticsData().flagsCollection.isChecked ==
              CheckedState.isFalse,
        ),
      );
      await tester.pump();
      expect(key.currentState!.data, '- [x] todo\n- [x] done\n');
      handle.dispose();
    });
  });

  group('other options', () {
    testWidgets('a registered builder map does not disturb the checkbox', (
      tester,
    ) async {
      final key = await _pump(
        tester,
        '- [ ] a\n',
        builders: {'code': _NoopBuilder()},
      );
      await tester.tap(_unchecked);
      await tester.pump();
      expect(key.currentState!.data, '- [x] a\n');
    });
  });
}

class _NoopBuilder extends MarkdownElementBuilder {}
