// Availability, diagnostics and failure behavior of the web parser (WebAssembly).
@TestOn('browser')
library;

import 'package:flutter_markdown_x/src/parser/backend_web.dart';
import 'package:flutter_markdown_x/src/ir/nodes.dart';
import 'package:flutter_markdown_x/src/parser/parser_status.dart';
import 'package:flutter_markdown_x/src/parser/web/wasm_parser.dart';
import 'package:flutter_test/flutter_test.dart';

List<MdxBlock> _blocks(String source) => [
  MdxParagraph([MdxText(source)]),
];

class _FakeWasm implements WasmParser {
  _FakeWasm({this.trap = false});

  final bool trap;

  @override
  List<MdxBlock> parse(String source) {
    if (trap) throw StateError('wasm trap');
    return _blocks(source);
  }
}

void main() {
  test('parse before initialization throws asking to await init', () {
    final backend = WebParserBackend(() async => _FakeWasm());
    expect(
      () => backend.parseMarkdown('x'),
      throwsA(
        isA<MarkdownXParserUnavailableException>().having(
          (e) => e.reason,
          'reason',
          contains('initializeParser()'),
        ),
      ),
    );
    final d = backend.diagnostics();
    expect(d.initialized, isFalse);
    expect(d.nativeAvailable, isFalse);
    expect(backend.isNativeParserActive, isFalse);
  });

  test('parse after load failure reports the captured load error', () async {
    final backend = WebParserBackend(
      () async => throw const FormatException('bad WASM'),
    );
    await backend.initializeParser();
    expect(
      () => backend.parseMarkdown('x'),
      throwsA(
        isA<MarkdownXParserUnavailableException>().having(
          (e) => e.reason,
          'reason',
          contains('bad WASM'),
        ),
      ),
    );
    final d = backend.diagnostics();
    expect(d.initialized, isTrue);
    expect(d.nativeAvailable, isFalse);
    expect(d.nativeUnavailableReason, contains('bad WASM'));
    expect(backend.parserRevision, 0);
  });

  test('parse works after initialization and diagnostics report it', () async {
    final backend = WebParserBackend(() async => _FakeWasm());
    await backend.initializeParser();
    expect(backend.parseMarkdown('# a'), _blocks('# a'));
    final d = backend.diagnostics();
    expect(d.platform, MarkdownXNativePlatform.web);
    expect(d.nativeAvailable, isTrue);
    expect(d.nativeUnavailableReason, isNull);
    expect(d.abiVersion, 2);
    expect(d.irVersion, 6);
    expect(d.initialized, isTrue);
    expect(backend.parserRevision, 1);
  });

  test('a trap disables WASM, bumps the revision and throws', () async {
    final backend = WebParserBackend(() async => _FakeWasm(trap: true));
    await backend.initializeParser();
    expect(backend.parserRevision, 1);
    expect(
      () => backend.parseMarkdown('x'),
      throwsA(
        isA<MarkdownXParserUnavailableException>().having(
          (e) => e.cause,
          'cause',
          isA<StateError>(),
        ),
      ),
    );
    expect(backend.parserRevision, 2);
    expect(backend.isNativeParserActive, isFalse);
    // It stays unusable: there is no fallback parser.
    expect(
      () => backend.parseMarkdown('x'),
      throwsA(isA<MarkdownXParserUnavailableException>()),
    );
  });
}
