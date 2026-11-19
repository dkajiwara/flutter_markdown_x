import 'package:flutter/rendering.dart';
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

String _sections(int count) =>
    [for (var i = 0; i < count; i++) '## Section $i\n\nBody of section $i.\n']
        .join('\n');

/// Whether the center of [finder] is within the screen (600 logical pixels high).
bool _onScreen(WidgetTester tester, Finder finder) {
  if (finder.evaluate().isEmpty) return false;
  final center = tester.getCenter(finder.first);
  return center.dy >= 0 && center.dy <= 600;
}

/// Taps the span at the position of [needle] within [text].
Future<void> _tapSpan(WidgetTester tester, Finder finder, String needle) async {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final start = paragraph.text.toPlainText().indexOf(needle);
  expect(start, greaterThanOrEqualTo(0), reason: 'needle not found');
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + needle.length),
  );
  final local = boxes.first.toRect().center;
  await tester.tapAt(paragraph.localToGlobal(local));
}

/// Completes the jump Future while pumping frames.
Future<bool> _jump(
  WidgetTester tester,
  MarkdownXController controller,
  String id,
) async {
  final future = controller.jumpToAnchor(id);
  var done = false;
  var result = false;
  unawaited(
    future.then((value) {
      done = true;
      result = value;
    }),
  );
  for (var i = 0; i < 200 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(done, isTrue, reason: 'jumpToAnchor did not complete');
  return result;
}

void unawaited(Future<void> future) {}

void main() {
  group('MarkdownXController', () {
    testWidgets('can get headings and notifies when the document changes', (
      tester,
    ) async {
      final controller = MarkdownXController();
      addTearDown(controller.dispose);
      var notified = 0;
      controller.addListener(() => notified++);
      expect(controller.headings, isEmpty);
      expect(await controller.jumpToAnchor('a'), isFalse);

      await tester.pumpWidget(
        _app(Markdown(data: '# A\n\n## A', markdownController: controller)),
      );
      await tester.pump();
      expect(controller.headings.map((h) => h.id), ['a', 'a-1']);
      expect(notified, 1);

      await tester.pumpWidget(
        _app(
          Markdown(data: '# A\n\n## A\n\n# B', markdownController: controller),
        ),
      );
      await tester.pump();
      expect(controller.headings.map((h) => h.id), ['a', 'a-1', 'b']);
      expect(notified, 2);

      // No notification for updates that leave the headings unchanged.
      await tester.pumpWidget(
        _app(
          Markdown(
            data: '# A\n\n## A\n\n# B\n\ntext',
            markdownController: controller,
          ),
        ),
      );
      await tester.pump();
      expect(notified, 2);

      await tester.pumpWidget(_app(const SizedBox()));
      expect(controller.isAttached, isFalse);
    });

    testWidgets('returns false for a nonexistent id', (tester) async {
      final controller = MarkdownXController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(Markdown(data: '# A', markdownController: controller)),
      );
      expect(await _jump(tester, controller, 'nope'), isFalse);
    });
  });

  group('Markdown navigation', () {
    testWidgets('jumps to a far, unbuilt heading and brings it on screen', (
      tester,
    ) async {
      final controller = MarkdownXController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(Markdown(data: _sections(400), markdownController: controller)),
      );
      expect(find.text('Section 350'), findsNothing);

      expect(await _jump(tester, controller, 'section-350'), isTrue);
      await tester.pump();
      expect(_onScreen(tester, find.text('Section 350')), isTrue);

      // Can also move toward the start (backward).
      expect(await _jump(tester, controller, 'section-3'), isTrue);
      await tester.pump();
      expect(_onScreen(tester, find.text('Section 3')), isTrue);

      // Can also move to the last heading.
      expect(await _jump(tester, controller, 'section-399'), isTrue);
      await tester.pump();
      expect(_onScreen(tester, find.text('Section 399')), isTrue);
    });

    testWidgets('converges even when block heights vary', (tester) async {
      final controller = MarkdownXController();
      addTearDown(controller.dispose);
      final data = [
        for (var i = 0; i < 150; i++)
          '# H$i\n\n${List.filled(i % 7 == 0 ? 30 : 1, 'line $i').join('\n\n')}\n',
      ].join('\n');
      await tester.pumpWidget(
        _app(Markdown(data: data, markdownController: controller)),
      );
      expect(await _jump(tester, controller, 'h140'), isTrue);
      await tester.pump();
      expect(_onScreen(tester, find.text('H140')), isTrue);
    });

    testWidgets('jumps to far headings in nested quotes, lists and details', (
      tester,
    ) async {
      final controller = MarkdownXController();
      addTearDown(controller.dispose);
      final data =
          '${_sections(200)}\n\n> ## Quoted\n\n- ## Listed\n\n'
          '<details>\n<summary>Fold</summary>\n\n## Hidden\n\nsecret\n\n</details>\n\n'
          '${_sections(50)}';
      await tester.pumpWidget(
        _app(Markdown(data: data, markdownController: controller)),
      );
      expect(
        controller.headings.map((h) => h.id),
        containsAll(['quoted', 'listed', 'hidden']),
      );

      expect(await _jump(tester, controller, 'quoted'), isTrue);
      await tester.pump();
      expect(_onScreen(tester, find.text('Quoted')), isTrue);

      expect(await _jump(tester, controller, 'listed'), isTrue);
      await tester.pump();
      expect(_onScreen(tester, find.text('Listed')), isTrue);
    });

    testWidgets(
      'a heading inside a closed details is reached after opening it',
      (tester) async {
        final controller = MarkdownXController();
        addTearDown(controller.dispose);
        final data =
            '${_sections(100)}\n\n<details>\n<summary>Fold</summary>\n\n'
            '## Hidden\n\nsecret\n\n</details>\n\n${_sections(30)}';
        await tester.pumpWidget(
          _app(Markdown(data: data, markdownController: controller)),
        );
        expect(await _jump(tester, controller, 'hidden'), isTrue);
        await tester.pump();
        expect(_onScreen(tester, find.text('Hidden')), isTrue);
        expect(find.textContaining('secret'), findsOneWidget);
      },
    );
  });

  group('Internal links', () {
    testWidgets(
      '#id link tap jumps to the heading and does not call onTapLink',
      (tester) async {
        final controller = MarkdownXController();
        addTearDown(controller.dispose);
        final tapped = <String>[];
        await tester.pumpWidget(
          _app(
            Markdown(
              data: '[go](#section-250)\n\n${_sections(300)}',
              markdownController: controller,
              onTapLink: (text, href, title) => tapped.add(href!),
            ),
          ),
        );
        await _tapSpan(tester, find.text('go'), 'go');
        await tester.pumpAndSettle();
        expect(_onScreen(tester, find.text('Section 250')), isTrue);
        expect(tapped, isEmpty);
      },
    );

    testWidgets('also resolves a percent-encoded link to a Japanese heading', (
      tester,
    ) async {
      final tapped = <String>[];
      await tester.pumpWidget(
        _app(
          Markdown(
            data:
                '[to](#%E3%81%AF%E3%81%98%E3%82%81%E3%81%AB)\n\n${_sections(100)}\n\n# はじめに',
            onTapLink: (text, href, title) => tapped.add(href!),
          ),
        ),
      );
      await _tapSpan(tester, find.text('to'), 'to');
      await tester.pumpAndSettle();
      expect(_onScreen(tester, find.text('はじめに')), isTrue);
      expect(tapped, isEmpty);
    });

    testWidgets(
      'an unknown id and handleAnchorLinks: false are passed to onTapLink',
      (tester) async {
        final tapped = <String>[];
        await tester.pumpWidget(
          _app(
            Markdown(
              data: '[x](#nowhere)\n\n# Real',
              onTapLink: (text, href, title) => tapped.add(href!),
            ),
          ),
        );
        await _tapSpan(tester, find.text('x'), 'x');
        expect(tapped, ['#nowhere']);

        tapped.clear();
        await tester.pumpWidget(
          _app(
            Markdown(
              data: '[x](#real)\n\n# Real',
              onTapLink: (text, href, title) => tapped.add(href!),
              handleAnchorLinks: false,
            ),
          ),
        );
        await _tapSpan(tester, find.text('x'), 'x');
        expect(tapped, ['#real']);
      },
    );
  });

  group('Footnote round trip', () {
    testWidgets('reference -> definition -> back to the first reference', (
      tester,
    ) async {
      final controller = MarkdownXController();
      addTearDown(controller.dispose);
      final data =
          'Start[^a] and again[^a].\n\n${_sections(300)}\n\n[^a]: The note text.';
      await tester.pumpWidget(
        _app(Markdown(data: data, markdownController: controller)),
      );
      expect(find.textContaining('The note text.'), findsNothing);

      // Tapping a reference jumps to the definition at the end.
      // The superscript is a WidgetSpan, so tap the inner Text directly.
      await tester.tap(find.text('1').first);
      await tester.pumpAndSettle();
      final note = find.textContaining('The note text.');
      expect(_onScreen(tester, note), isTrue);

      // The definition back link returns to the paragraph with the first reference.
      await _tapSpan(tester, note, '↩');
      await tester.pumpAndSettle();
      expect(_onScreen(tester, find.textContaining('Start')), isTrue);
    });
  });

  group('MarkdownBody', () {
    testWidgets('jumps to a heading inside a parent scroll view', (
      tester,
    ) async {
      final controller = MarkdownXController();
      final scroll = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            controller: scroll,
            child: MarkdownBody(
              data: _sections(100),
              markdownController: controller,
            ),
          ),
        ),
      );
      expect(scroll.offset, 0);
      expect(await _jump(tester, controller, 'section-90'), isTrue);
      await tester.pump();
      expect(scroll.offset, greaterThan(0));
      expect(_onScreen(tester, find.text('Section 90')), isTrue);
    });

    testWidgets('tapping an internal link moves the parent scroll view', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: MarkdownBody(
              data: '[go](#end)\n\n${_sections(60)}\n\n# End',
            ),
          ),
        ),
      );
      await _tapSpan(tester, find.text('go'), 'go');
      await tester.pumpAndSettle();
      expect(_onScreen(tester, find.text('End')), isTrue);
    });
  });

  group('State preservation', () {
    testWidgets(
      'the details open state is preserved when a footnote is appended',
      (tester) async {
        const details =
            '<details>\n<summary>More</summary>\n\nhidden\n\n</details>';
        await tester.pumpWidget(_app(const Markdown(data: details)));
        await tester.tap(find.text('More'));
        await tester.pump();
        expect(find.text('hidden'), findsOneWidget);

        await tester.pumpWidget(
          _app(const Markdown(data: '$details\n\nafter[^1]\n\n[^1]: note')),
        );
        expect(find.text('hidden'), findsOneWidget);
      },
    );
  });
}
