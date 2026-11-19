# WebAssembly parser for Flutter Web

`flutter_markdown_x` includes a Rust/WebAssembly parser for web builds. The
package declares `prebuilt/web/mdx_native.wasm` as an asset in its own
`pubspec.yaml`, so Flutter includes it through the normal package asset bundle.

## Consumer setup

Use the Markdown widgets and run `flutter build web`. Flutter bundles the
parser asset through the package's pubspec. The widgets initialize it and
switch from source text to rendered Markdown. See [Parser diagnostics](parser.md)
for the fallback behavior.

To call the parser directly, initialize Flutter's bindings and await the parser:

```dart
WidgetsFlutterBinding.ensureInitialized();
await initializeParser();
final blocks = parseMarkdown(markdown);
```

## Startup and performance

The parser runs on the UI thread. Its timing includes UTF-8 conversion, memory
copying, and IR decoding. In one macOS release build with headless Chrome 157,
local asset loading and module validation took 3.9 ms. The deployed download
size depends on compression at the host.

The [browser consumer test](../example/test/web_consumer_test.dart) covers
automatic startup and compares full and incremental parsing on the CommonMark
input corpus.

## Maintainer commands

Consumers do not run these commands. Maintainers regenerate the checked-in
artifact with Rust's `wasm32-unknown-unknown` target:

```sh
sh tool/build_wasm.sh
node tool/check_wasm.mjs
flutter test --platform chrome test/parser/web_wasm_test.dart
cd example
flutter test --platform chrome test/web_consumer_test.dart
```

For the release benchmark, run from `example/`:

```sh
flutter build web --target=../benchmark/web_parser.dart --output=/tmp/mdx-web-benchmark
```

Serve the output over HTTP and open it in a browser to see the measurements.
