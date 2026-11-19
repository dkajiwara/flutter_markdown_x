/// Calls the Rust parser (`native/`) through FFI.
///
/// Depends on `dart:ffi`, so it cannot be used on the web. `backend.dart` loads it with a conditional
/// import.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../ir/nodes.dart';
import 'bindings.dart';
import 'ir_decoder.dart';

/// The reason the native parser is unavailable, or null if it is usable.
///
/// One of the following. Written as human-readable sentences for diagnostics.
/// - There is no binary for this platform, or a symbol cannot be resolved
/// - The ABI version does not match (the binary is too old or too new)
/// - The smoke parse of an empty document failed (including an IR version mismatch)
String? get nativeParserUnavailableReason => _probeResult;

/// Whether the native parser is usable in this environment.
///
/// If no binary for the target platform is bundled, the symbol cannot be resolved and the
/// first call fails. The result, including the ABI version and IR version checks, is tried
/// once and remembered.
bool get isNativeParserAvailable => _probeResult == null;

/// A string identifying the native build (`mdx_build_info`). Null if unavailable.
String? get nativeParserBuildInfo => isNativeParserAvailable
    ? mdx_build_info().cast<Utf8>().toDartString()
    : null;

final String? _probeResult = _probe();

/// Returns null if usable, otherwise the reason. Never lets an exception escape.
String? _probe() {
  final int abi;
  try {
    abi = mdx_abi_version();
    // ArgumentError is thrown when a symbol or library cannot be resolved.
    // ignore: avoid_catching_errors
  } on ArgumentError catch (error) {
    return 'native binary or mdx_abi_version symbol is missing: $error';
    // ignore: avoid_catching_errors
  } on Error catch (error) {
    return 'native binary could not be loaded: $error';
  } on Exception catch (error) {
    return 'native binary could not be loaded: $error';
  }
  if (abi != expectedMdxAbiVersion) {
    return 'native ABI version mismatch: binary is $abi, '
        'package expects $expectedMdxAbiVersion '
        '(rebuild with tool/build_native.sh)';
  }
  final irVersion = mdx_ir_version();
  if (irVersion != mdxIrVersion) {
    return 'native IR version mismatch: binary writes IR v$irVersion, '
        'decoder reads v$mdxIrVersion';
  }
  try {
    final blocks = parseNative('');
    if (blocks.isNotEmpty) return 'native smoke parse of "" was not empty';
  } on MdxNativeException catch (error) {
    return 'native smoke parse failed: ${error.message}';
  } on FormatException catch (error) {
    return 'native smoke parse returned an invalid IR: $error';
  }
  return null;
}

/// Thrown when a call to the native parser fails.
final class MdxNativeException implements Exception {
  /// What failed.
  const MdxNativeException(this.message);

  /// What failed.
  final String message;

  @override
  String toString() => 'MdxNativeException: $message';
}

/// Parses [source] with the native parser and returns the list of top-level blocks.
List<MdxBlock> parseNative(String source) =>
    _withIr(source, (ir) => decodeIr(ir, source: source));

/// Parses [source] with the native parser and returns a copy of the binary IR.
///
/// For measurement and verification, to treat parsing and decoding separately.
Uint8List parseNativeToBytes(String source) =>
    _withIr(source, Uint8List.fromList);

/// Passes the IR in native memory to [read] and frees it once reading is done.
///
/// The list passed to [read] becomes invalid after the free, so it must not be kept outside.
T _withIr<T>(String source, T Function(Uint8List ir) read) {
  final encoded = utf8.encode(source);
  final input = malloc<Uint8>(encoded.length);
  final outLength = malloc<Size>();
  try {
    input.asTypedList(encoded.length).setAll(0, encoded);
    outLength.value = 0;
    final output = mdx_parse(input, encoded.length, outLength);
    if (output == nullptr) {
      throw const MdxNativeException(
        'mdx_parse returned null (parse failed, e.g. panic or oversize input)',
      );
    }
    final length = outLength.value;
    try {
      return read(output.asTypedList(length));
    } finally {
      mdx_free(output, length);
    }
  } finally {
    malloc
      ..free(input)
      ..free(outLength);
  }
}
