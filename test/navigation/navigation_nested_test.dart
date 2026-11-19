import 'package:flutter/rendering.dart';
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

String _sections(int count) =>
    [for (var i = 0; i < count; i++) '## Section $i\n\nBody of section $i.\n']
        .join('\n');

String _doc() =>
    '[go](#target) and a note[^1].\n\n${_sections(80)}\n\n# Target\n\n'
    '${_sections(5)}\n\n[^1]: The note text.';

bool _onScreen(WidgetTester tester, Finder finder) {
  if (finder.evaluate().isEmpty) return false;
  final center = tester.getCenter(finder.first);
  return center.dy >= 0 &&
      center.dy <= 600 &&
      center.dx >= 0 &&
      center.dx <= 800;
}

Future<void> _tapSpan(WidgetTester tester, Finder finder, String needle) async {
  final paragraph = tester.renderObject<RenderParagraph>(finder.first);
  final start = paragraph.text.toPlainText().indexOf(needle);
  expect(start, greaterThanOrEqualTo(0));
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + needle.length),
  );
  await tester.tapAt(paragraph.localToGlobal(boxes.first.toRect().center));
}

double _pageOffset(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(TabBarView),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position
    .pixels;

Widget _tabs(TabController? controller, Widget Function(int index) tab) {
  return MaterialApp(
    home: DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) {
          return Scaffold(
            appBar: AppBar(
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'A'),
                  Tab(text: 'B'),
                ],
              ),
            ),
            body: TabBarView(children: [tab(0), tab(1)]),
          );
        },
      ),
    ),
  );
}

TabController _tabController(WidgetTester tester) =>
    DefaultTabController.of(tester.element(find.byType(TabBarView)));

void _expectStayed(WidgetTester tester) {
  expect(_tabController(tester).index, 0);
  expect(_pageOffset(tester), 0.0);
}

Future<bool> _jump(
  WidgetTester tester,
  MarkdownXController controller,
  String id,
) async {
  var done = false;
  var result = false;
  controller.jumpToAnchor(id).then((v) {
    done = true;
    result = v;
  });
  for (var i = 0; i < 200 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(done, isTrue);
  return result;
}

void main() {
  group('inside a TabBarView', () {
    testWidgets('Markdown: tapping an internal link keeps the tab', (
      tester,
    ) async {
      await tester.pumpWidget(_tabs(null, (i) => Markdown(data: _doc())));
      await _tapSpan(tester, find.textContaining('go and'), 'go');
      await tester.pumpAndSettle();
      _expectStayed(tester);
      expect(_onScreen(tester, find.text('Target')), isTrue);
    });

    testWidgets('Markdown: jumpToAnchor keeps the tab', (tester) async {
      final controller = MarkdownXController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _tabs(
          null,
          (i) => i == 0
              ? Markdown(data: _doc(), markdownController: controller)
              : const SizedBox(),
        ),
      );
      expect(await _jump(tester, controller, 'target'), isTrue);
      await tester.pumpAndSettle();
      _expectStayed(tester);
      expect(_onScreen(tester, find.text('Target')), isTrue);
    });

    testWidgets('Markdown: footnote round trip keeps the tab', (tester) async {
      await tester.pumpWidget(_tabs(null, (i) => Markdown(data: _doc())));
      await tester.tap(find.text('1').first);
      await tester.pumpAndSettle();
      _expectStayed(tester);
      final note = find.textContaining('The note text.');
      expect(_onScreen(tester, note), isTrue);
      await _tapSpan(tester, note, '↩');
      await tester.pumpAndSettle();
      _expectStayed(tester);
      expect(_onScreen(tester, find.textContaining('go and')), isTrue);
    });

    testWidgets('MarkdownBody in SingleChildScrollView keeps the tab', (
      tester,
    ) async {
      final controller = MarkdownXController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _tabs(
          null,
          (i) => SingleChildScrollView(
            child: MarkdownBody(
              data: _doc(),
              markdownController: i == 0 ? controller : null,
            ),
          ),
        ),
      );
      await _tapSpan(tester, find.textContaining('go and'), 'go');
      await tester.pumpAndSettle();
      _expectStayed(tester);
      expect(_onScreen(tester, find.text('Target')), isTrue);
      expect(await _jump(tester, controller, 'section-3'), isTrue);
      await tester.pumpAndSettle();
      _expectStayed(tester);
    });

    testWidgets('SliverMarkdown in CustomScrollView keeps the tab', (
      tester,
    ) async {
      final controller = MarkdownXController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _tabs(
          null,
          (i) => CustomScrollView(
            slivers: [
              SliverMarkdown(
                data: _doc(),
                markdownController: i == 0 ? controller : null,
              ),
            ],
          ),
        ),
      );
      await _tapSpan(tester, find.textContaining('go and'), 'go');
      await tester.pumpAndSettle();
      _expectStayed(tester);
      expect(_onScreen(tester, find.text('Target')), isTrue);
      expect(await _jump(tester, controller, 'section-3'), isTrue);
      await tester.pumpAndSettle();
      _expectStayed(tester);
    });
  });

  group('inside a horizontal scrollable', () {
    testWidgets('PageView parent keeps the page', (tester) async {
      final pages = PageController();
      addTearDown(pages.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageView(
              controller: pages,
              children: [
                Markdown(data: _doc()),
                const SizedBox(),
              ],
            ),
          ),
        ),
      );
      await _tapSpan(tester, find.textContaining('go and'), 'go');
      await tester.pumpAndSettle();
      expect(pages.position.pixels, 0.0);
      expect(_onScreen(tester, find.text('Target')), isTrue);
    });

    testWidgets('horizontal ListView parent keeps its offset', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: scroll,
              scrollDirection: Axis.horizontal,
              children: [
                SizedBox(width: 800, child: Markdown(data: _doc())),
                const SizedBox(width: 800),
              ],
            ),
          ),
        ),
      );
      await _tapSpan(tester, find.textContaining('go and'), 'go');
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, 0.0);
      expect(_onScreen(tester, find.text('Target')), isTrue);
    });
  });
}
