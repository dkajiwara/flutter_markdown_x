/// The parser entry point for the web. Loads and uses the bundled WebAssembly parser.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'native/ir_decoder.dart';
import '../ir/nodes.dart';
import 'parser_status.dart';
import 'web/wasm_parser.dart';

/// The type of a function that loads and validates the WebAssembly parser.
typedef WasmParserLoader = Future<WasmParser> Function();

/// Backend state is separated from asset loading so failure and concurrent
/// initialization behavior can be exercised in browser tests.
final class WebParserBackend {
  /// Creates a backend from the parser loading function [_load].
  WebParserBackend(this._load);

  final WasmParserLoader _load;
  WasmParser? _parser;
  Future<void>? _initialization;
  bool _attempted = false;
  int _revision = 0;
  String? _failure;

  /// The parser revision. It changes when WebAssembly is enabled (becomes 1) or permanently
  /// disabled.
  int get parserRevision => _revision;

  /// Whether the validated WebAssembly parser is currently usable.
  bool get isNativeParserActive => _parser != null;

  /// Whether initialization (success or failure) has finished.
  bool get initialized => _attempted;

  /// The reason WebAssembly is unavailable, or null if it is usable.
  String? get unavailableReason {
    if (_parser != null) return null;
    if (!_attempted) {
      return 'WebAssembly parser is not initialized yet; '
          'await initializeParser() first';
    }
    return _failure ?? 'WebAssembly parser is not available';
  }

  /// Loads and validates the WebAssembly parser. Only one attempt is made; neither success nor failure
  /// is retried afterwards. Calling this again while it runs waits for the same initialization.
  Future<void> initializeParser() {
    if (_attempted) return Future<void>.value();
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      final parser = await _load();
      _parser = parser;
      _revision = 1;
    } catch (error) {
      // Asset, compilation, ABI, and smoke-test errors leave the parser
      // unavailable. Initialization is deliberately one-shot. The reason is
      // kept for the exception and diagnostics.
      _parser = null;
      _failure = 'WebAssembly parser failed to load: $error';
    } finally {
      _attempted = true;
      _initialization = null;
    }
  }

  /// Parses [source] with the WebAssembly parser.
  ///
  /// Throws [MarkdownXParserUnavailableException] when it is unavailable (before initialization, after
  /// a load failure, or after a trap).
  List<MdxBlock> parseMarkdown(String source) {
    final parser = _parser;
    if (parser == null) {
      throw MarkdownXParserUnavailableException(unavailableReason!);
    }
    try {
      return parser.parse(source);
    } catch (error) {
      // A trap or malformed response makes this module unusable. Change the
      // revision so incremental consumers discard IR from the old module and
      // widgets fall back to raw text.
      _parser = null;
      _attempted = true;
      _revision++;
      _failure = 'WebAssembly parser was disabled after a failure: $error';
      throw MarkdownXParserUnavailableException(_failure!, cause: error);
    }
  }

  /// The current state of the parser.
  MarkdownXParserDiagnostics diagnostics() {
    final available = _parser != null;
    return MarkdownXParserDiagnostics(
      platform: MarkdownXNativePlatform.web,
      nativeAvailable: available,
      nativeUnavailableReason: unavailableReason,
      // The WebAssembly module does not expose a build-info string.
      abiVersion: available ? expectedMdxAbiVersion : null,
      irVersion: available ? mdxIrVersion : null,
      initialized: _attempted,
    );
  }
}

Future<WasmParser> _loadPackageWasm() async {
  final data = await rootBundle.load(
    'packages/flutter_markdown_x/prebuilt/web/mdx_native.wasm',
  );
  final bytes = Uint8List.fromList(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  return WasmParser.load(bytes);
}

final _backend = WebParserBackend(_loadPackageWasm);

/// Loads and validates the WebAssembly parser once. Until it succeeds (or
/// after it fails) [parseMarkdown] throws and widgets show the raw text.
Future<void> initializeParser() => _backend.initializeParser();

/// Changes when the backend activates or permanently disables WebAssembly.
int get parserRevision => _backend.parserRevision;

/// Whether the validated WebAssembly parser is currently active.
bool get isNativeParserActive => _backend.isNativeParserActive;

/// Parses synchronously with WebAssembly after initialization; throws
/// [MarkdownXParserUnavailableException] before that.
List<MdxBlock> parseMarkdown(String source) => _backend.parseMarkdown(source);

/// The current state of the parser.
MarkdownXParserDiagnostics markdownXParserDiagnostics() =>
    _backend.diagnostics();
