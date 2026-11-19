@TestOn('browser')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_markdown_x/src/parser/backend_web.dart';
import 'package:flutter_markdown_x/src/parser/parser_status.dart';
import 'package:flutter_markdown_x/src/parser/web/wasm_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('truncated WebAssembly bytes are rejected', () async {
    await expectLater(
      WasmParser.load(Uint8List.fromList([0, 97, 115, 109])),
      throwsA(anything),
    );
  });

  test('unsupported ABI is rejected before activation', () async {
    // Small valid module exporting only mdx_abi_version, which returns 3.
    final bytes = Uint8List.fromList([
      0,
      97,
      115,
      109,
      1,
      0,
      0,
      0,
      1,
      5,
      1,
      96,
      0,
      1,
      127,
      3,
      2,
      1,
      0,
      7,
      19,
      1,
      15,
      ...'mdx_abi_version'.codeUnits,
      0,
      0,
      10,
      6,
      1,
      4,
      0,
      65,
      3,
      11,
    ]);
    await expectLater(
      WasmParser.load(bytes),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('ABI'),
        ),
      ),
    );
  });

  test('module without mdx_abi_version is rejected', () async {
    // Empty (but valid) module: no exports at all.
    final bytes = Uint8List.fromList([0, 97, 115, 109, 1, 0, 0, 0]);
    await expectLater(WasmParser.load(bytes), throwsA(isA<FormatException>()));
  });

  test(
    'concurrent failed initialization is attempted once without throwing',
    () async {
      final completer = Completer<WasmParser>();
      var loadCalls = 0;
      final backend = WebParserBackend(() {
        loadCalls++;
        return completer.future;
      });

      final first = backend.initializeParser();
      final second = backend.initializeParser();
      expect(loadCalls, 1);
      completer.completeError(const FormatException('bad WASM'));
      await Future.wait([first, second]);

      expect(backend.isNativeParserActive, isFalse);
      expect(backend.parserRevision, 0);
      expect(
        () => backend.parseMarkdown('unavailable'),
        throwsA(isA<MarkdownXParserUnavailableException>()),
      );
      await backend.initializeParser();
      expect(loadCalls, 1);
    },
  );
}
