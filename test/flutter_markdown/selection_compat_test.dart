// onSelectionChanged, selectable, onTapText and contextMenuBuilder: the adapted semantics of
// doc/flutter_markdown_compat.md (2.2, 2.3 and the UNSUPPORTED list).
import 'package:flutter/gestures.dart';
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

Future<void> _dragAcross(WidgetTester tester, String text) async {
  final finder = find.text(text, findRichText: true);
  final start = tester.getTopLeft(finder) + const Offset(2, 5);
  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump(const Duration(milliseconds: 500));
  await gesture.moveBy(const Offset(40, 0));
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

void main() {
  group('onSelectionChanged', () {
    testWidgets('keeps the invariant text.substring(start, end) == text', (
      tester,
    ) async {
      final calls = <(String, TextSelection, SelectionChangedCause?)>[];
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: 'select me',
            selectable: true,
            onSelectionChanged: (text, selection, cause) =>
                calls.add((text!, selection, cause)),
          ),
        ),
      );
      await _dragAcross(tester, 'select me');
      expect(calls, isNotEmpty);
      for (final (text, selection, cause) in calls) {
        expect(text, isNotEmpty);
        expect('select me', contains(text));
        expect(selection.start, 0);
        expect(selection.end, text.length);
        expect(text.substring(selection.start, selection.end), text);
        expect(cause, isNull);
      }
    });

    testWidgets('is not called when the selection is cleared', (tester) async {
      final calls = <String?>[];
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: 'select me',
            selectable: true,
            onSelectionChanged: (text, selection, cause) => calls.add(text),
          ),
        ),
      );
      await _dragAcross(tester, 'select me');
      final before = calls.length;
      await tester.tapAt(const Offset(700, 500));
      await tester.pump();
      expect(calls.length, before);
      expect(calls, everyElement(isNotEmpty));
    });

    testWidgets('is not called, and there is no SelectionArea, when not '
        'selectable', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: 'select me',
            onSelectionChanged: (text, selection, cause) => calls++,
          ),
        ),
      );
      expect(find.byType(SelectionArea), findsNothing);
      await _dragAcross(tester, 'select me');
      expect(calls, 0);
    });

    testWidgets('a new closure is called at event time without a rebuild', (
      tester,
    ) async {
      final first = <String?>[];
      final second = <String?>[];
      Widget body(void Function(String?) sink) => _app(
        MarkdownBody(
          data: 'select me',
          selectable: true,
          onSelectionChanged: (text, selection, cause) => sink(text),
        ),
      );
      await tester.pumpWidget(body(first.add));
      await tester.pumpWidget(body(second.add));
      await _dragAcross(tester, 'select me');
      expect(first, isEmpty);
      expect(second, isNotEmpty);
    });
  });

  group('selectable and onTapText', () {
    testWidgets('selectable wraps the body in exactly one SelectionArea', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const MarkdownBody(data: 'a\n\nb', selectable: true)),
      );
      expect(find.byType(SelectionArea), findsOneWidget);
    });

    testWidgets('onTapText is not called when not selectable', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(MarkdownBody(data: 'tap me', onTapText: () => taps++)),
      );
      await tester.tap(find.text('tap me', findRichText: true));
      expect(taps, 0);
    });

    testWidgets('a link wins the tap over onTapText', (tester) async {
      var taps = 0;
      final links = <String?>[];
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '[go](https://a.example)',
            selectable: true,
            handleAnchorLinks: false,
            onTapText: () => taps++,
            onTapLink: (text, href, title) => links.add(href),
          ),
        ),
      );
      await tester.tap(find.text('go', findRichText: true));
      expect(links, ['https://a.example']);
      expect(taps, 0);
    });
  });

  group('contextMenuBuilder', () {
    SelectionArea area(WidgetTester tester) =>
        tester.widget<SelectionArea>(find.byType(SelectionArea));

    testWidgets('the default keeps the SelectionArea default menu', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const MarkdownBody(data: 'a', selectable: true)),
      );
      expect(area(tester).contextMenuBuilder, isNotNull);
    });

    testWidgets('null turns the context menu off', (tester) async {
      await tester.pumpWidget(
        _app(
          const MarkdownBody(
            data: 'a',
            selectable: true,
            contextMenuBuilder: null,
          ),
        ),
      );
      expect(area(tester).contextMenuBuilder, isNull);
    });

    testWidgets('a custom function is reported once and the default is used', (
      tester,
    ) async {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);
      Widget custom(BuildContext c, EditableTextState s) =>
          const SizedBox.shrink();
      Widget body(String data) => _app(
        MarkdownBody(data: data, selectable: true, contextMenuBuilder: custom),
      );
      await tester.pumpWidget(body('a'));
      await tester.pumpWidget(body('b'));
      expect(reported, hasLength(1));
      expect(reported.single.exception, isA<UnsupportedError>());
      expect(area(tester).contextMenuBuilder, isNotNull);
    });

    testWidgets('is ignored when not selectable', (tester) async {
      await tester.pumpWidget(
        _app(const MarkdownBody(data: 'a', contextMenuBuilder: null)),
      );
      expect(find.byType(SelectionArea), findsNothing);
    });
  });
}
