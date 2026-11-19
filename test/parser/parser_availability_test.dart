// Availability, diagnostics and unavailable-state behavior of the parser (Rust, FFI) (doc/parser.md).
//
// The no-binary state is simulated with `debugNativeSimulation`. Web is covered by
// web_backend_selection_test.dart and example/test/web_consumer_test.dart.
@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_markdown_x/src/parser/backend_ffi.dart' as ffi;
import 'package:flutter_markdown_x/src/parser/native/native_parser.dart';
import 'package:flutter_markdown_x/src/widgets/renderer.dart' show MdxBlockView;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _sample =
    '# Title\n\nHello **bold** [link](https://example.com/a b)\n\n- a\n- b\n';

const _rawKey = ValueKey('flutter_markdown_x.raw_text');

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  tearDown(() => ffi.debugNativeSimulation = null);

  group('parseMarkdown', () {
    test('parses with the bundled Rust parser', () {
      expect(parseMarkdown(_sample), parseNative(_sample));
      expect(parseMarkdown(_sample), isNotEmpty);
    });

    test('throws MarkdownXParserUnavailableException when unavailable', () {
      ffi.debugNativeSimulation = ffi.DebugNativeSimulation(
        unavailableReason: 'simulated missing binary',
      );
      expect(
        () => parseMarkdown(_sample),
        throwsA(
          isA<MarkdownXParserUnavailableException>()
              .having((e) => e.reason, 'reason', 'simulated missing binary')
              .having(
                (e) => e.toString(),
                'toString',
                allOf(
                  contains('MarkdownXParserUnavailableException'),
                  contains('simulated missing binary'),
                ),
              ),
        ),
      );
      expect(isNativeParserActive, isFalse);
    });

    test('throws while initialization is pending, works afterwards', () async {
      final init = Completer<void>();
      ffi.debugNativeSimulation = ffi.DebugNativeSimulation(
        initialization: init.future,
      );
      expect(
        () => parseMarkdown(_sample),
        throwsA(
          isA<MarkdownXParserUnavailableException>().having(
            (e) => e.reason,
            'reason',
            contains('initializeParser()'),
          ),
        ),
      );
      init.complete();
      await initializeParser();
      expect(parseMarkdown(_sample), isNotEmpty);
    });
  });

  group('diagnostics', () {
    test('report availability with ABI 2 / IR 6 and build info', () {
      final d = markdownXParserDiagnostics();
      expect(d.platform, MarkdownXNativePlatform.ffi);
      expect(d.nativeAvailable, isTrue);
      expect(d.nativeUnavailableReason, isNull);
      expect(d.abiVersion, 2);
      expect(d.irVersion, 6);
      expect(d.nativeBuildInfo, isNotEmpty);
      expect(d.initialized, isTrue);
      expect(d.toString(), contains('nativeAvailable: true'));
      expect(isNativeParserActive, isTrue);
    });

    test('report the reason when unavailable', () {
      ffi.debugNativeSimulation = ffi.DebugNativeSimulation(
        unavailableReason: 'nope',
      );
      final d = markdownXParserDiagnostics();
      expect(d.nativeAvailable, isFalse);
      expect(d.nativeUnavailableReason, 'nope');
      expect(d.nativeBuildInfo, isNull);
      expect(d.abiVersion, isNull);
      expect(d.irVersion, isNull);
      expect(d.initialized, isTrue);
    });
  });

  group('IncrementalMarkdownParser', () {
    test('explicit parse function is independent of the Rust parser', () {
      var calls = 0;
      final parser = IncrementalMarkdownParser(
        parse: (source) {
          calls++;
          return const [];
        },
      );
      ffi.debugNativeSimulation = ffi.DebugNativeSimulation(
        unavailableReason: 'nope',
      );
      expect(parser.parse('x'), isEmpty);
      expect(calls, greaterThan(0));
    });

    test('default parser throws when unavailable and recovers later', () {
      final parser = IncrementalMarkdownParser();
      ffi.debugNativeSimulation = ffi.DebugNativeSimulation(
        unavailableReason: 'nope',
      );
      expect(
        () => parser.parse('[a]: /u\n\n[a]'),
        throwsA(isA<MarkdownXParserUnavailableException>()),
      );
      ffi.debugNativeSimulation = null;
      expect(parser.parse('[a]: /u\n\n[a]'), parseMarkdown('[a]: /u\n\n[a]'));
    });
  });

  group('raw text fallback', () {
    /// Contents reported to FlutterError.reportError. Call [capture] at the start of each test
    /// (the test binding replaces onError when a test starts).
    late List<FlutterErrorDetails> reported;

    void capture() {
      reported = [];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);
    }

    Finder rawText() => find.byKey(_rawKey);

    testWidgets('MarkdownX shows the raw Markdown and reports once', (
      tester,
    ) async {
      capture();
      ffi.debugNativeSimulation = ffi.DebugNativeSimulation(
        unavailableReason: 'simulated',
      );
      await tester.pumpWidget(_host(const Markdown(data: _sample)));
      expect(rawText(), findsOneWidget);
      expect(tester.widget<Text>(rawText()).data, _sample);
      expect(find.byType(MdxBlockView), findsNothing);
      expect(reported, hasLength(1));
      expect(reported.single.library, 'flutter_markdown_x');
      expect(
        reported.single.exception,
        isA<MarkdownXParserUnavailableException>().having(
          (e) => e.reason,
          'reason',
          'simulated',
        ),
      );
      // Rebuilding with the same input does not report again.
      await tester.pumpWidget(_host(const Markdown(data: _sample)));
      await tester.pump();
      expect(reported, hasLength(1));
    });

    testWidgets('MarkdownBody and SliverMarkdown show the raw Markdown', (
      tester,
    ) async {
      capture();
      ffi.debugNativeSimulation = ffi.DebugNativeSimulation(
        unavailableReason: 'simulated',
      );
      await tester.pumpWidget(_host(const MarkdownBody(data: '# a\n\nb')));
      expect(tester.widget<Text>(rawText()).data, '# a\n\nb');

      await tester.pumpWidget(
        _host(
          const CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: Text('HEAD')),
              SliverMarkdown(data: '# a\n\nb'),
            ],
          ),
        ),
      );
      expect(find.text('HEAD'), findsOneWidget);
      expect(tester.widget<Text>(rawText()).data, '# a\n\nb');
    });

    testWidgets('raw text honors the paragraph style', (tester) async {
      capture();
      ffi.debugNativeSimulation = ffi.DebugNativeSimulation(
        unavailableReason: 'simulated',
      );
      const style = TextStyle(fontSize: 23, color: Color(0xFF123456));
      final custom = MarkdownStyleSheet(p: style);
      await tester.pumpWidget(
        _host(MarkdownBody(data: 'x', styleSheet: custom)),
      );
      final text = tester.widget<Text>(rawText());
      // The sheet is merged onto the theme's paragraph style.
      expect(text.style?.fontSize, 23);
      expect(text.style?.color, const Color(0xFF123456));
    });

    testWidgets('raw text is selectable and has no headings', (tester) async {
      capture();
      ffi.debugNativeSimulation = ffi.DebugNativeSimulation(
        unavailableReason: 'simulated',
      );
      final controller = MarkdownXController();
      await tester.pumpWidget(
        _host(
          Markdown(
            data: _sample,
            markdownController: controller,
            selectable: true,
          ),
        ),
      );
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(rawText(), findsOneWidget);
      expect(controller.headings, isEmpty);
    });

    testWidgets('pending initialization shows raw text without reporting, '
        'then switches to the parsed Markdown', (tester) async {
      capture();
      final init = Completer<void>();
      ffi.debugNativeSimulation = ffi.DebugNativeSimulation(
        initialization: init.future,
      );
      final controller = MarkdownXController();
      await tester.pumpWidget(
        _host(Markdown(data: _sample, markdownController: controller)),
      );
      expect(rawText(), findsOneWidget);
      expect(reported, isEmpty);
      expect(controller.headings, isEmpty);

      init.complete();
      await tester.pump();
      await tester.pump();
      expect(reported, isEmpty);
      expect(rawText(), findsNothing);
      expect(find.byType(MdxBlockView), findsWidgets);
      expect(controller.headings.map((h) => h.id), ['title']);
    });

    testWidgets('pending initialization that fails reports once', (
      tester,
    ) async {
      capture();
      final init = Completer<void>();
      ffi.debugNativeSimulation = ffi.DebugNativeSimulation(
        unavailableReason: 'load failed',
        initialization: init.future,
      );
      await tester.pumpWidget(_host(const MarkdownBody(data: _sample)));
      expect(reported, isEmpty);
      init.complete();
      await tester.pump();
      await tester.pump();
      expect(reported, hasLength(1));
      expect(
        reported.single.exception,
        isA<MarkdownXParserUnavailableException>().having(
          (e) => e.reason,
          'reason',
          'load failed',
        ),
      );
      expect(rawText(), findsOneWidget);
    });

    testWidgets('data updates while unavailable keep showing the new text', (
      tester,
    ) async {
      capture();
      ffi.debugNativeSimulation = ffi.DebugNativeSimulation(
        unavailableReason: 'simulated',
      );
      await tester.pumpWidget(_host(const MarkdownBody(data: 'one')));
      await tester.pumpWidget(_host(const MarkdownBody(data: 'two')));
      expect(tester.widget<Text>(rawText()).data, 'two');
      expect(reported, hasLength(1));
    });

    testWidgets('recovers to parsed output once the parser is usable', (
      tester,
    ) async {
      capture();
      ffi.debugNativeSimulation = ffi.DebugNativeSimulation(
        unavailableReason: 'simulated',
      );
      await tester.pumpWidget(_host(const MarkdownBody(data: 'hi **x**')));
      expect(rawText(), findsOneWidget);
      ffi.debugNativeSimulation = null;
      await tester.pumpWidget(_host(const MarkdownBody(data: 'hi **y**')));
      expect(rawText(), findsNothing);
      expect(find.textContaining('hi y', findRichText: true), findsOneWidget);
    });
  });
}
