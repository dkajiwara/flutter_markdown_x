import 'package:flutter/rendering.dart';
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

String _sections(int count, {String suffix = ''}) =>
    [for (var i = 0; i < count; i++) '## Section $i\n\nBody of section $i.\n']
        .join('\n') +
    suffix;

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget _scroll({
  required String data,
  ScrollController? controller,
  MarkdownXController? markdownController,
  bool streaming = false,
  Key? markdownKey,
}) => _app(
  CustomScrollView(
    controller: controller,
    slivers: [
      const SliverToBoxAdapter(
        child: SizedBox(height: 100, child: Text('HEAD')),
      ),
      SliverPadding(
        padding: const EdgeInsets.all(8),
        sliver: SliverMarkdown(
          key: markdownKey,
          data: data,
          markdownController: markdownController,
          streaming: streaming,
        ),
      ),
      const SliverToBoxAdapter(
        child: SizedBox(height: 100, child: Text('FOOT')),
      ),
    ],
  ),
);

void main() {
  group('SliverMarkdown', () {
    testWidgets(
      'can sit beside other slivers and builds only on-screen blocks',
      (tester) async {
        await tester.pumpWidget(_scroll(data: _sections(300)));
        expect(find.text('HEAD'), findsOneWidget);
        expect(find.textContaining('Body of section 0.'), findsOneWidget);
        // Lazy construction: distant blocks are not built.
        expect(find.textContaining('Body of section 250.'), findsNothing);
        expect(find.text('FOOT'), findsNothing);

        await tester.scrollUntilVisible(
          find.text('FOOT'),
          500,
          scrollable: find.byType(Scrollable),
          maxScrolls: 2000,
        );
        expect(find.text('FOOT'), findsOneWidget);
        expect(find.textContaining('Body of section 299.'), findsOneWidget);
      },
    );

    testWidgets('appending keeps the details open state and scroll position', (
      tester,
    ) async {
      const first =
          '<details>\n<summary>Sum</summary>\n\nhidden body\n\n</details>\n\n'
          'tail';
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_scroll(data: first, controller: controller));
      expect(find.text('hidden body'), findsNothing);
      await tester.tap(find.text('Sum'));
      await tester.pump();
      expect(find.text('hidden body'), findsOneWidget);

      await tester.pumpWidget(
        _scroll(data: '$first more\n\nnew paragraph', controller: controller),
      );
      expect(find.text('hidden body'), findsOneWidget);
      expect(find.textContaining('new paragraph'), findsOneWidget);
    });

    testWidgets(
      'adding a block at the top does not move the State of the same block',
      (tester) async {
        const details =
            '<details>\n<summary>Sum</summary>\n\nhidden body\n\n</details>';
        await tester.pumpWidget(_scroll(data: details));
        await tester.tap(find.text('Sum'));
        await tester.pump();
        await tester.pumpWidget(_scroll(data: 'inserted first\n\n$details'));
        expect(find.text('hidden body'), findsOneWidget);
      },
    );

    testWidgets(
      'can jumpToAnchor to an unbuilt heading (even with another sliver before it)',
      (tester) async {
        final markdownController = MarkdownXController();
        addTearDown(markdownController.dispose);
        final scrollController = ScrollController();
        addTearDown(scrollController.dispose);
        await tester.pumpWidget(
          _scroll(
            data: _sections(300),
            controller: scrollController,
            markdownController: markdownController,
          ),
        );
        await tester.pump();
        expect(find.text('Section 250'), findsNothing);

        final future = markdownController.jumpToAnchor('section-250');
        var done = false;
        var result = false;
        // ignore: discarded_futures
        future.then((value) {
          done = true;
          result = value;
        });
        for (var i = 0; i < 200 && !done; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(done, isTrue);
        expect(result, isTrue);
        await tester.pump();
        final finder = find.text('Section 250');
        expect(finder, findsOneWidget);
        final top = tester.getTopLeft(finder).dy;
        expect(top, inInclusiveRange(0, 200));
      },
    );

    testWidgets('tapping a #id link scrolls even inside a sliver', (
      tester,
    ) async {
      final data = '[go](#section-100)\n\n${_sections(200)}';
      await tester.pumpWidget(_scroll(data: data));
      expect(find.text('Section 100'), findsNothing);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.textContaining('go', findRichText: true).first,
      );
      final boxes = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 2),
      );
      await tester.tapAt(paragraph.localToGlobal(boxes.first.toRect().center));
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('Section 100'), findsOneWidget);
    });

    testWidgets('the streaming option takes effect', (tester) async {
      await tester.pumpWidget(_scroll(data: 'hello **wor', streaming: true));
      expect(find.textContaining('**'), findsNothing);
      await tester.pumpWidget(_scroll(data: 'hello **wor'));
      expect(find.textContaining('**', findRichText: true), findsOneWidget);
    });

    testWidgets(
      'Markdown renders the same (padding / shrinkWrap compatibility)',
      (tester) async {
        await tester.pumpWidget(
          _app(const Markdown(data: 'one\n\ntwo', padding: EdgeInsets.all(16))),
        );
        expect(tester.getTopLeft(find.text('one')), const Offset(16, 16));
      },
    );
  });
}
