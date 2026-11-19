import 'dart:async';

import 'support/web_parser_stub.dart'
    if (dart.library.js_interop) 'support/web_parser_web.dart';

/// Runs once per test file (flutter_test picks this file up automatically).
///
/// On the web the parser is WebAssembly loaded from the package asset, which `flutter test
/// --platform chrome` does not serve. [installWebParser] feeds the module to the asset channel
/// from `test/fixtures/mdx_native.wasm` and awaits `initializeParser()`, so the tests see the same
/// ready parser as on the VM. It does nothing on the VM.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await installWebParser();
  await testMain();
}
