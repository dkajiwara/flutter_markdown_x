import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';

const _wasmAssetKey =
    'packages/flutter_markdown_x/prebuilt/web/mdx_native.wasm';

// Served from test/fixtures (a link to prebuilt/web/mdx_native.wasm).
const _wasmFixtureUrl = '/fixtures/mdx_native.wasm';

/// Loads the WebAssembly parser for widget tests in Chrome.
Future<void> installWebParser() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final response = await _fetch(_wasmFixtureUrl.toJS).toDart;
  if (response.status != 200) {
    throw StateError('WASM fixture fetch returned HTTP ${response.status}');
  }
  final buffer = await response.arrayBuffer().toDart;
  final bytes = ByteData.sublistView(JSUint8Array(buffer).toDart);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
        final key = const StringCodec().decodeMessage(message);
        return key == _wasmAssetKey ? bytes : null;
      });
  await initializeParser();
  if (!isNativeParserActive) {
    throw StateError(
      'WASM parser did not load: '
      '${markdownXParserDiagnostics().nativeUnavailableReason}',
    );
  }
}

@JS('fetch')
external JSPromise<_FetchResponse> _fetch(JSString url);

@JS()
extension type _FetchResponse(JSObject _) implements JSObject {
  external int get status;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}
