/// JavaScript interop bridge for the package's WebAssembly parser.
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import '../native/ir_decoder.dart';
import '../../ir/nodes.dart';

/// A validated instance of the native parser's WebAssembly ABI.
///
/// [load] is intentionally available as an internal seam: callers can check
/// bad modules and ABI mismatches without changing the application asset.
class WasmParser {
  WasmParser._(this._exports);

  final _WasmExports _exports;

  /// Loads the WebAssembly module in [bytes] and returns a parser verified by checking the ABI version, IR version and
  /// parsing an empty string. Throws [FormatException] if they do not match.
  static Future<WasmParser> load(Uint8List bytes) async {
    final source = await _webAssembly
        .instantiate(bytes.toJS, _newObject())
        .toDart;
    final exports = source.instance.exports;
    // Check the ABI before anything else: a stale module may lack the other
    // exports, and its IR layout cannot be trusted.
    if (!exports.has('mdx_abi_version')) {
      throw const FormatException(
        'Markdown WASM module has no mdx_abi_version export (stale build?)',
      );
    }
    final parser = WasmParser._(exports);
    final abi = parser._abiVersion;
    if (abi != expectedMdxAbiVersion) {
      throw FormatException(
        'Unsupported markdown WASM ABI: $abi (expected $expectedMdxAbiVersion)',
      );
    }
    final ir = _number(exports.irVersion.callAsFunction());
    if (ir != mdxIrVersion) {
      throw FormatException(
        'Unsupported markdown WASM IR version: $ir (expected $mdxIrVersion)',
      );
    }
    // The smoke parse also validates the IR header through the decoder.
    final smoke = parser.parse('');
    if (smoke.isNotEmpty) {
      throw const FormatException('Markdown WASM smoke parse was not empty');
    }
    return parser;
  }

  int get _abiVersion => _number(_exports.abiVersion.callAsFunction());

  /// Parses [source] into IR. Throws if the module fails.
  List<MdxBlock> parse(String source) {
    final input = utf8.encode(source);
    // mdx_alloc(0) is valid Rust, but reserve one byte so the pointer remains
    // useful on engines that represent zero-sized allocations as null.
    final inputAllocationLength = input.isEmpty ? 1 : input.length;
    var inputPointer = 0;
    var outLengthPointer = 0;
    var outputPointer = 0;
    var outputLength = 0;
    try {
      inputPointer = _allocate(inputAllocationLength);
      outLengthPointer = _allocate(4);
      _byteView(inputPointer, input.length).setRange(0, input.length, input);
      _byteView(outLengthPointer, 4).fillRange(0, 4, 0);

      outputPointer = _number(
        _exports.parse.callAsFunction(
          null,
          inputPointer.toJS,
          input.length.toJS,
          outLengthPointer.toJS,
        ),
      );
      if (outputPointer == 0) {
        // mdx_parse returns null on failure (out_len is then 0).
        throw StateError(
          'Markdown WASM parse failed (mdx_parse returned null)',
        );
      }

      // Reacquire memory after mdx_parse: it may have grown and detached every
      // view obtained before that call.
      final lengthBytes = _byteView(outLengthPointer, 4);
      outputLength =
          lengthBytes[0] |
          (lengthBytes[1] << 8) |
          (lengthBytes[2] << 16) |
          (lengthBytes[3] << 24);
      final copiedOutput = Uint8List.fromList(
        _byteView(outputPointer, outputLength),
      );
      return decodeIr(copiedOutput, source: source);
    } finally {
      try {
        if (outputPointer != 0) {
          _exports.free.callAsFunction(
            null,
            outputPointer.toJS,
            outputLength.toJS,
          );
        }
      } finally {
        try {
          if (outLengthPointer != 0) {
            _exports.dealloc.callAsFunction(
              null,
              outLengthPointer.toJS,
              4.toJS,
            );
          }
        } finally {
          if (inputPointer != 0) {
            _exports.dealloc.callAsFunction(
              null,
              inputPointer.toJS,
              inputAllocationLength.toJS,
            );
          }
        }
      }
    }
  }

  int _allocate(int length) {
    final pointer = _number(_exports.alloc.callAsFunction(null, length.toJS));
    if (pointer == 0) throw StateError('Markdown WASM allocation failed');
    return pointer;
  }

  Uint8List _byteView(int pointer, int length) =>
      JSUint8Array(_exports.memory.buffer, pointer, length).toDart;
}

int _number(JSAny? value) => (value as JSNumber).toDartInt;

@JS('Object')
external JSObject _newObject();

@JS('WebAssembly')
external _WebAssembly get _webAssembly;

@JS()
extension type _WebAssembly(JSObject _) implements JSObject {
  external JSPromise<_InstantiatedSource> instantiate(
    JSAny bytes,
    JSObject imports,
  );
}

@JS()
extension type _InstantiatedSource(JSObject _) implements JSObject {
  external _Instance get instance;
}

@JS()
extension type _Instance(JSObject _) implements JSObject {
  external _WasmExports get exports;
}

@JS()
extension type _WasmExports(JSObject _) implements JSObject {
  @JS('memory')
  external _WasmMemory get memory;

  @JS('mdx_abi_version')
  external JSFunction get abiVersion;

  @JS('mdx_ir_version')
  external JSFunction get irVersion;

  @JS('mdx_alloc')
  external JSFunction get alloc;

  @JS('mdx_dealloc')
  external JSFunction get dealloc;

  @JS('mdx_parse')
  external JSFunction get parse;

  @JS('mdx_free')
  external JSFunction get free;
}

@JS()
extension type _WasmMemory(JSObject _) implements JSObject {
  external JSArrayBuffer get buffer;
}
