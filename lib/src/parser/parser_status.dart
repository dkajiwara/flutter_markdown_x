/// Shared types for parser diagnostics and exceptions. Depends on neither `dart:ffi` nor `dart:js_interop`.
library;

/// The mechanism used to call the native parser.
enum MarkdownXNativePlatform {
  /// `dart:ffi` (iOS, Android, macOS, Linux, Windows).
  ffi,

  /// WebAssembly (Web).
  web,
}

/// Thrown by [parseMarkdown] when the parser (written in Rust) is currently unavailable.
///
/// This covers a missing binary or ABI mismatch (FFI), and WebAssembly before initialization, after a load failure, or
/// after a trap (web). Widgets catch this exception and show the raw Markdown
/// as is (doc/parser.md).
class MarkdownXParserUnavailableException implements Exception {
  /// Creates the exception from the reason [reason] and the underlying exception [cause] (null if none).
  const MarkdownXParserUnavailableException(this.reason, {this.cause});

  /// The reason it is unavailable. A human-readable sentence.
  final String reason;

  /// The exception that caused it (such as a WebAssembly trap). Null if none.
  final Object? cause;

  @override
  String toString() => 'MarkdownXParserUnavailableException: $reason';
}

/// The current state of the parser. Obtained with [markdownXParserDiagnostics].
class MarkdownXParserDiagnostics {
  /// Creates a value describing the parser state.
  const MarkdownXParserDiagnostics({
    required this.platform,
    required this.nativeAvailable,
    required this.initialized,
    this.nativeUnavailableReason,
    this.nativeBuildInfo,
    this.abiVersion,
    this.irVersion,
  });

  /// The mechanism that calls the parser.
  final MarkdownXNativePlatform platform;

  /// Whether the parser is currently usable.
  final bool nativeAvailable;

  /// The reason it is unavailable, or null if it is usable.
  final String? nativeUnavailableReason;

  /// A string identifying the native build. FFI only; null otherwise.
  final String? nativeBuildInfo;

  /// The ABI version of the native binary. Only when usable.
  final int? abiVersion;

  /// The version of the IR the native binary writes. Only when usable.
  final int? irVersion;

  /// Whether initialization has finished. On the web, true after [initializeParser] completes.
  /// Always true for FFI.
  final bool initialized;

  @override
  String toString() =>
      'MarkdownXParserDiagnostics(platform: ${platform.name}, '
      'nativeAvailable: $nativeAvailable, '
      'nativeUnavailableReason: $nativeUnavailableReason, '
      'nativeBuildInfo: $nativeBuildInfo, abiVersion: $abiVersion, '
      'irVersion: $irVersion, initialized: $initialized)';
}
