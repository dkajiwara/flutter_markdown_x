/// The parser entry point for environments with `dart:ffi`. Calls the bundled Rust parser through FFI.
library;

import 'package:flutter/foundation.dart';

import 'native/ir_decoder.dart';
import 'native/native_parser.dart';
import '../ir/nodes.dart';
import 'parser_status.dart';

const _pendingReason =
    'native parser is still initializing; await initializeParser() first';

/// For tests. Simulates a state where native is unavailable or still initializing.
final class DebugNativeSimulation {
  /// Simulates the native state with [unavailableReason] and [initialization].
  /// If [initialization] is null, starts out as already initialized.
  DebugNativeSimulation({this.unavailableReason, Future<void>? initialization})
    : initialized = initialization == null {
    initialization?.whenComplete(() => initialized = true);
    _initialization = initialization;
  }

  /// The reason native is unavailable once initialization has finished. If null, the real native is used.
  final String? unavailableReason;

  /// Whether initialization has finished. Native is treated as unavailable until then.
  bool initialized;

  Future<void>? _initialization;
}

/// For tests. When non-null, simulates the state of the [DebugNativeSimulation].
@visibleForTesting
DebugNativeSimulation? debugNativeSimulation;

String? get _unavailableReason {
  final simulation = debugNativeSimulation;
  if (simulation != null) {
    if (!simulation.initialized) return _pendingReason;
    if (simulation.unavailableReason != null) {
      return simulation.unavailableReason;
    }
  }
  return nativeParserUnavailableReason;
}

/// Whether the native parser is in use.
bool get isNativeParserActive => _unavailableReason == null;

/// Native code assets are loaded synchronously.
Future<void> initializeParser() =>
    debugNativeSimulation?._initialization ?? Future<void>.value();

/// The native backend does not change after startup.
int get parserRevision => 0;

/// Parses [source] with the Rust parser.
///
/// Throws [MarkdownXParserUnavailableException] when it is unavailable (no binary, ABI mismatch,
/// and so on). There is no fallback to a Dart implementation.
List<MdxBlock> parseMarkdown(String source) {
  final reason = _unavailableReason;
  if (reason != null) throw MarkdownXParserUnavailableException(reason);
  return parseNative(source);
}

/// The current state of the parser.
MarkdownXParserDiagnostics markdownXParserDiagnostics() {
  final reason = _unavailableReason;
  final available = reason == null;
  return MarkdownXParserDiagnostics(
    platform: MarkdownXNativePlatform.ffi,
    nativeAvailable: available,
    nativeUnavailableReason: reason,
    nativeBuildInfo: available ? nativeParserBuildInfo : null,
    abiVersion: available ? expectedMdxAbiVersion : null,
    irVersion: available ? mdxIrVersion : null,
    initialized: debugNativeSimulation?.initialized ?? true,
  );
}
