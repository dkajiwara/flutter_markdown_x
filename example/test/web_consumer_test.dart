@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_markdown_x/src/parser/backend.dart' as backend;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fixtures/commonmark_inputs.dart';

const _wasmAssetKey =
    'packages/flutter_markdown_x/prebuilt/web/mdx_native.wasm';
const _wasmAssetUrl = '/fixtures/mdx_native.wasm';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  late ByteData packagedWasm;
  setUpAll(() async {
    final response = await _fetch(_wasmAssetUrl.toJS).toDart;
    if (response.status != 200) {
      throw StateError('WASM asset fetch returned HTTP ${response.status}');
    }
    final buffer = await response.arrayBuffer().toDart;
    packagedWasm = ByteData.sublistView(JSUint8Array(buffer).toDart);
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final key = const StringCodec().decodeMessage(message);
          return key == _wasmAssetKey ? packagedWasm : null;
        });
  });

  testWidgets(
    'widget shows raw text until WebAssembly activates, then renders Markdown',
    (tester) async {
      expect(backend.isNativeParserActive, isFalse);
      final initialRevision = backend.parserRevision;
      final incremental = IncrementalMarkdownParser();
      // Before initialization there is no parser at all.
      expect(
        () => incremental.parse('first\n\nsecond'),
        throwsA(isA<MarkdownXParserUnavailableException>()),
      );
      expect(
        () => backend.parseMarkdown('early sync parse'),
        throwsA(isA<MarkdownXParserUnavailableException>()),
      );

      const source =
          '<details>\n<summary>More</summary>\n\nloaded body\n\n</details>';
      await tester.pumpWidget(_app(const MarkdownBody(data: source)));

      // The widget is usable before any caller initializes the parser: it shows
      // the raw Markdown.
      expect(find.textContaining('<details>'), findsOneWidget);

      for (
        var attempt = 0;
        attempt < 500 && !backend.isNativeParserActive;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(
        backend.isNativeParserActive,
        isTrue,
        reason:
            'The package WebAssembly asset should initialize in the browser.',
      );
      expect(backend.parserRevision, greaterThan(initialRevision));
      await tester.pump();

      // Now the Markdown is parsed and rendered.
      expect(find.textContaining('<details>'), findsNothing);
      expect(find.textContaining('More'), findsOneWidget);
      expect(find.textContaining('loaded body'), findsNothing);
      await tester.tap(find.textContaining('More'));
      await tester.pump();
      expect(find.textContaining('loaded body'), findsOneWidget);
      expect(incremental.parse('first\n\nsecond'), hasLength(2));
    },
  );

  test(
    'awaited WebAssembly parser parses blocks and the corpus incrementally',
    () async {
      await backend.initializeParser().timeout(const Duration(seconds: 10));
      expect(backend.isNativeParserActive, isTrue);
      expect(backend.parserRevision, isA<int>());

      const source = 'plain text\n\n```\npayload\n```\n\n| h |\n|---|\n| v |';
      final blocks = backend.parseMarkdown(source);
      expect(blocks, hasLength(3));
      expect((blocks[0] as MdxParagraph).inlines.single, MdxText('plain text'));
      expect((blocks[1] as MdxCodeBlock).code, 'payload');
      final table = blocks[2] as MdxTable;
      expect((table.header.single.single as MdxText).text, 'h');
      expect((table.rows.single.single.single as MdxText).text, 'v');

      final incremental = IncrementalMarkdownParser();
      for (final (example, markdown) in commonMarkInputs) {
        expect(
          listEquals(
            incremental.parse(markdown),
            backend.parseMarkdown(markdown),
          ),
          isTrue,
          reason: 'WebAssembly full/incremental CommonMark example $example',
        );
      }
    },
  );
}

@JS('fetch')
external JSPromise<_FetchResponse> _fetch(JSString url);

@JS()
extension type _FetchResponse(JSObject _) implements JSObject {
  external int get status;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}
