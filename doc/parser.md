# Parser (Rust) availability and diagnostics

The conversion from Markdown to IR (the parser) is provided only by the bundled Rust implementation. This document defines how to call the parser, what happens when it is unavailable (the source text is shown), Web initialization, and how to diagnose its state.

## How it is invoked

| Platform | Mechanism |
|---|---|
| iOS, Android, macOS, Linux, Windows | `dart:ffi`. Calls the native binary bundled by the build hook ([native-abi.md](native-abi.md)) |
| Web | WebAssembly. Asynchronously loads the package asset `prebuilt/web/mdx_native.wasm` ([web-wasm.md](web-wasm.md)) |

```dart
final blocks = parseMarkdown(source); // MarkdownXParserUnavailableException when unavailable
```

## Behavior when unavailable

`parseMarkdown` and `IncrementalMarkdownParser` with the default parser throw `MarkdownXParserUnavailableException` when the parser is unavailable. It carries a `reason` (a descriptive string) and, when present, a `cause`. There is no Dart fallback.

| Situation | Result |
|---|---|
| No binary for this platform, or the ABI or IR version does not match (FFI) | Exception. `reason` contains the cause |
| Web, before `initializeParser()` has completed | Exception. `reason` says to await `initializeParser()` |
| Web, after the WASM load failed | Exception. `reason` is the error from loading. It does not retry |
| Web, WASM trapped during a parse | WASM is disabled, and an exception with the cause in `cause` is thrown. It stays unavailable afterward |

When you pass your own parse function to `IncrementalMarkdownParser({parse})`, that function is used and this exception is not involved.

## Widget behavior (source text display)

`Markdown`, `MarkdownBody`, and `SliverMarkdown` show the original `data` as
one text block while the parser is unavailable. It uses the paragraph style,
supports `selectable: true`, and has no headings for navigation.

On Web, the widgets initialize the parser automatically and switch to rendered
Markdown after it loads. A failure is reported through `FlutterError.reportError`
once per widget state until a successful parse. Pending initialization does not
report an error.

## Web initialization timing

For direct parsing outside a widget, call `await initializeParser()` before
`parseMarkdown`. See [Web setup](web-wasm.md#consumer-setup).

## Diagnostics

`markdownXParserDiagnostics()` returns the current state as an immutable object.

```dart
final d = markdownXParserDiagnostics();
debugPrint('$d');
// MarkdownXParserDiagnostics(platform: ffi, nativeAvailable: true,
//   nativeUnavailableReason: null, nativeBuildInfo: ..., abiVersion: 2,
//   irVersion: 5, initialized: true)
```

| Field | Meaning |
|---|---|
| `platform` | `ffi` or `web` |
| `nativeAvailable` | Whether the parser is usable now (same as `isNativeParserActive`) |
| `nativeUnavailableReason` | Why it is unavailable. Null if available |
| `nativeBuildInfo` | The native build identifier. FFI only; null on Web |
| `abiVersion` / `irVersion` | The binary's ABI and IR versions. Only when available |
| `initialized` | Whether initialization has finished. On Web, true after `initializeParser()` completes; always true for FFI |

To check at startup that the parser is required, use `markdownXParserDiagnostics().nativeAvailable`. See [native-abi.md](native-abi.md) for details on ABI and IR versions and build information.

See [Builders and syntax extensions](extensions.md) for the source and IR
transforms that run around the parser.
