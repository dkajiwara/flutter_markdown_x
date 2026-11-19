# ABI and IR format of the native parser

This document defines the boundary between the Rust parser in `native/` (`mdx_native`) and Dart (`lib/src/parser/native/`, `lib/src/parser/web/`). It covers the C ABI functions, memory ownership, failure contracts, the binary IR format, and how versions are handled.

## Two versions

| Name | Current value | Meaning | Rust | Dart |
|---|---|---|---|---|
| ABI version | 2 | Names, arguments, return values, ownership, and failure contracts of the exported functions | `ABI_VERSION` / `mdx_abi_version()` | `expectedMdxAbiVersion` |
| IR version | 6 | Format of the binary IR byte stream | `ir::IR_VERSION` / `mdx_ir_version()` | `mdxIrVersion` |

## C ABI

Exported on every target.

| Function | Description |
|---|---|
| `u32 mdx_abi_version()` | Returns the ABI version |
| `u32 mdx_ir_version()` | Returns the version of the IR it emits |
| `const char* mdx_build_info()` | A static NUL-terminated string `mdx_native <crate version> abi=<ABI> ir=<IR>`. Not freed. CI uses it to identify builds |
| `u8* mdx_parse(const u8* source, usize source_len, usize* out_len)` | Converts UTF-8 Markdown to IR |
| `void mdx_free(u8* pointer, usize len)` | Frees a region returned by `mdx_parse` |

Only wasm32 also exports the following so that JavaScript can use linear memory.

| Function | Description |
|---|---|
| `u8* mdx_alloc(usize len)` | Allocates `len` zero-initialized bytes |
| `void mdx_dealloc(u8* pointer, usize len)` | Frees a region from `mdx_alloc`. Null does nothing |

wasm also exports `memory`. It has no imports. The old `mdx_wasm_abi_version` was retired and unified into `mdx_abi_version`.

## Ownership

- The region returned by `mdx_parse` is a `Box<[u8]>` allocated by Rust. The caller owns it, but only `mdx_free` can release it. It must never be passed to the caller's `free` / `malloc.free`.
- Pass `mdx_free` the pointer returned by `mdx_parse` and the length written to `*out_len`, exactly as they are. Changing the length is undefined behavior. A double free is also forbidden. Null does nothing.
- `source` is read only for the duration of the call. `mdx_parse` does not retain it.
- The returned region may be read only before `mdx_free`. Dart uses the `asTypedList` view only inside `read` and never lets it escape (`native_parser.dart`). Web copies it with `Uint8List.fromList` before `mdx_free`.
- The wasm input and the `out_len` region are allocated with `mdx_alloc` and returned to `mdx_dealloc` with the same length. After `mdx_parse`, `memory.buffer` may be replaced by growth, so re-acquire views on every call.

## Failure contract

On failure, `mdx_parse` returns null and, if `out_len` is not null, writes 0 to `*out_len`. Failure occurs when:

- `out_len` is null
- `source` is null and `source_len` is not 0 (if `source_len` is 0, null is acceptable)
- `source_len` exceeds `isize::MAX`
- A panic during parsing (see below)
- The IR is too large to represent in `u32` (a string or sequence length of 4 GiB or more). `Writer` returns `IrError::TooLarge` instead of using `expect`

Invalid UTF-8 is not a failure; it is accepted after being replaced with U+FFFD. A successful IR is never empty because of the header.

Dart never decodes null. `parseNative` throws `MdxNativeException`. Web throws `StateError`.

## Handling panics

The release profile in `native/Cargo.toml` does **not** use `panic = "abort"` (the default unwind is used), because with `abort` a panic during parsing would terminate the whole Flutter app. `mdx_parse` catches panics with `std::panic::catch_unwind` and returns null, following the failure contract. The default panic hook output (stderr) remains.

- native (macOS / iOS / Android): the panic is caught and becomes null. Dart throws `MdxNativeException`.
- wasm32-unknown-unknown: stable Rust cannot unwind, so a panic becomes an `unreachable` trap and surfaces to JavaScript as a `RuntimeError`. `catch_unwind` has no effect. An instance after a trap should not be reused, since the allocator may be in an intermediate state. When an initialized module throws, the web parser disables it and throws `MarkdownXParserUnavailableException` (the widget switches to showing the source text).
- A stack overflow from deep nesting cannot be caught (it can take down the process on any target). This is not a panic. The Dart decoder places no fixed limit on nesting depth and throws `MdxIrFormatException` only when the Dart stack is exhausted (so that native does not reject a document whose depth the parser accepted).

## Binary IR format

Integers are little endian.

```text
document   = header blocks
header     = magic(4 byte, ASCII "MDXI") ir_version(u32)
blocks     = count(u32) block*count
string     = byte_len(u32) utf8
opt_string = present(u8: 0 | 1) [string]
opt_f64    = f64 (absent is NaN)
```

A custom block (block tag 8, decoded as `MdxCustomBlock`) is laid out as follows.

```text
custom     = tag(u8: 8) type(string) count(u32) (key(string) value(string))*count inlines blocks
inlines    = count(u32) inline*count
```

Each element of a sequence occupies at least 1 byte, so if the count exceeds the remaining byte count, the decoder can reject it as corrupt before allocating. The constants for block and inline tags and each layout are in `native/src/ir.rs` and `lib/src/parser/native/ir_decoder.dart`, and both must be changed together.

What the decoder rejects (all as `MdxIrFormatException`, with `offset` as the position from the start).

- A magic mismatch or an IR version mismatch
- Truncation (every read checks the remaining byte count)
- A count exceeding the remaining byte count
- An unknown block / inline tag
- A custom block with an empty type or a repeated attribute name
- Out-of-range values: align (0..3), the `MdxStyleKind` index (0..17; the titled inline accepts only 16 and 17, the plain styled inline rejects them), checked (0..2), a task marker offset that does not fit the source text (only when the decoder is given the source), boolean / presence bytes (0 / 1), heading level (1..6), undefined span flag bits, table cell colspan and rowspan (1..100)
- Invalid UTF-8
- Nesting deep enough to exhaust the Dart stack
- Bytes left over after the document

`RangeError`, `StateError`, and `ArgumentError` do not leak from the decoder.

## IR version

The current IR version is 6 (`ir::IR_VERSION` in Rust, `mdxIrVersion` in Dart). It is stored in the header, and a decoder accepts only its own version: IR of any other version is rejected, so a binary built from different sources is detected as a mismatch (see below).

## Version policy

- **Bump the IR version** when the binary IR format changes: adding, removing, or reordering tags, adding fields, changing enum values, or changing the header. Bump Rust's `IR_VERSION` and Dart's `mdxIrVersion` together, fix the decoder, and rebuild `prebuilt/`. Compatibility is not kept (old IR cannot be read).
- **Bump the ABI version** when the contract of the exported functions changes: making an added function mandatory, or changing names, arguments, return values, ownership, or failure contracts. Bump Rust's `ABI_VERSION` (and the `mdx_build_info` string) and Dart's `expectedMdxAbiVersion` together.
- If only the IR format changes, do not bump the ABI. If only a function contract changes, do not bump the IR. If both change, bump both.
- A fix that changes only behavior (parse results) without bumping either is unrelated to versions. To identify a build, use the crate version in `mdx_build_info`.

## How Dart detects a mismatch

native (`native_parser.dart`) probes exactly once on first use and remembers the result.

1. Call `mdx_abi_version`. If the symbol or binary is missing, catch the `ArgumentError` and treat it as "binary or symbol missing".
2. Verify that the ABI version equals `expectedMdxAbiVersion`.
3. Verify that `mdx_ir_version` equals `mdxIrVersion`.
4. Parse `''`, restore it with the decoder that validates the header, and verify that it is empty (a smoke parse).

If any step fails, native is treated as unavailable, `parseMarkdown` throws `MarkdownXParserUnavailableException`, and the widget shows the source text ([parser.md](parser.md)). The reason can be read from `nativeParserUnavailableReason` (a human-readable string, or null if available). `isNativeParserAvailable` is whether the reason is null. When available, `nativeParserBuildInfo` is the `mdx_build_info` string.

web (`wasm_parser.dart`) checks, after `WebAssembly.instantiate`, the presence of `mdx_abi_version`, the ABI version, `mdx_ir_version`, and a smoke parse, in that order. If any differs, it rejects loading with a `FormatException` (the widget keeps working by showing the source text).

A stale binary can cause native tests to be skipped, so when they skip, the reason is shown. CI on supported OSes should require that native is enabled.

## Generating the FFI bindings

To prevent Rust's `extern "C"` and Dart's `@Native` from diverging, the Dart bindings are not handwritten but generated from Rust.

```text
native/src/lib.rs ──cbindgen──> native/include/mdx_native.h ──ffigen──> lib/src/parser/native/bindings.dart
```

- The cbindgen configuration is `native/cbindgen.toml`. Doc comments are kept in the header. `usize` becomes `size_t`. wasm32-only `mdx_alloc` / `mdx_dealloc` are wrapped in `#if defined(MDX_TARGET_WASM32)`, so they do not appear in the native bindings.
- The ffigen configuration is `ffigen.yaml`. It emits `@Native` bindings, and the asset name is `package:flutter_markdown_x/src/parser/native/bindings.dart` (matching `_assetName` in `hook/build.dart`). `functions.leaf` makes every function `isLeaf: true`, and `size_t` becomes `Size`. Doc comments are carried over from the header.
- Function names stay as the C names (such as `mdx_parse`), and `native_parser.dart` calls them directly. `const char*` becomes `Pointer<Char>`, so use `cast<Utf8>()` when converting it to a string.
- The versions are cbindgen 0.29.4 and ffigen 20.1.1 (pinned exactly in `pubspec.yaml`). ffigen uses Xcode's libclang (`llvm-path` in `ffigen.yaml`).

### Regenerating

When you change Rust's C ABI, run the following and commit the diff.

```sh
cargo install cbindgen --locked --version 0.29.4   # first time only
flutter pub get
sh tool/generate_bindings.sh
```

Do not edit the generated files (`native/include/mdx_native.h`, `lib/src/parser/native/bindings.dart`) directly. When you change the ABI contract (names, arguments, return values, ownership, failure), also bump `ABI_VERSION` and `expectedMdxAbiVersion` as before.

### CI check

The CI `bindings-drift` job (Linux; `ffigen.yaml` lists the Xcode and apt libclang paths) runs `tool/generate_bindings.sh` and uses `git diff --exit-code -- native/include lib/src/parser/native/bindings.dart` to confirm there is no difference from the committed generated files. If you change a Rust signature and forget to regenerate, it fails here. The header and configuration do not affect the binary's contents, so they are not included in the inputs of `tool/prebuilt_manifest.dart`.

### What is guaranteed

ffigen guards only the **function signatures** (names, argument types, return types). The binary IR format (header, tags, each layout) does not appear in C types, so it is still guarded by checking the ABI and IR versions, the validation in `ir_decoder.dart`, and updating `native/src/ir.rs` in lockstep. Ownership and failure contracts are only carried over as doc comments and are not mechanically verified.

## Supported targets and build

The mapping between binaries in `prebuilt/` and the directory that `hook/build.dart` selects.

| OS / arch | Directory | File | Rust target | Notes |
|---|---|---|---|---|
| macOS arm64 / x64 | `macos-arm64` / `macos-x64` | `libmdx_native.dylib` | `*-apple-darwin` | Minimum 10.15 |
| iOS device / simulator | `ios-arm64` / `ios-arm64-sim` / `ios-x64-sim` | `libmdx_native.dylib` | `*-apple-ios*` | Minimum 13.0 |
| Android arm / arm64 / x64 | `android-<arch>` | `libmdx_native.so` | `*-linux-android*` | API 24, 16 KB page support |
| Linux x64 / arm64 | `linux-x64` / `linux-arm64` | `libmdx_native.so` | `*-unknown-linux-gnu` | glibc 2.17 or later |
| Windows x64 / arm64 | `windows-x64` / `windows-arm64` | `mdx_native.dll` | `*-pc-windows-msvc` | CRT statically linked |
| Web | `web` | `mdx_native.wasm` | `wasm32-unknown-unknown` | `tool/build_wasm.sh` |

The file name is determined by `code.targetOS.dylibFileName('mdx_native')` (a `.so` with the `lib` prefix on Linux / Android, and a `.dll` without the prefix on Windows). The only supported arches are `arm64` / `x64` / `arm`; others (Linux `arm` / `riscv64`, 32-bit x86 on Windows, and so on) have no binary and the hook registers nothing.

### Linux (glibc)

- The oldest supported glibc is 2.17 (equivalent to CentOS 7 / Ubuntu 14.04). Both x64 and arm64 are built with `cargo zigbuild --target <triple>.2.17`, using zig's libc stubs. The symbols actually referenced go up to GLIBC_2.14 on x64 and GLIBC_2.17 on arm64.
- We do not build for musl (Alpine), because Flutter's Linux embedder assumes glibc.
- Requirements: zig (`brew install zig`; the version we verified is 0.17.1) and `cargo install cargo-zigbuild --locked` (the version we verified is in the 0.23 series). It can be built on both macOS and Linux.
- To rebuild on a Linux host with plain cargo rather than the distribution build, use `LINUX_BUILDER=cargo sh tool/build_native.sh linux` (only the host's arch; it depends on the runner's glibc). CI's `native-rebuild-linux` tests with this.

### Windows (MSVC)

- We choose the MSVC ABI (`*-pc-windows-msvc`). It is the same ABI as Flutter's Windows embedder; since the DLL boundary is only the C ABI, GNU would also work, but we align with the standard toolchain on Windows.
- `-C target-feature=+crt-static` links the MSVC CRT statically. It loads even on a user's PC without the Visual C++ Redistributable (`vcruntime140.dll` and so on). It imports only `KERNEL32.dll`, `ntdll.dll`, `api-ms-win-core-synch-l1-2-0.dll`, and `bcryptprimitives.dll`, which are standard on Windows 10 and later.
- `malloc` / `free` inside the DLL belong to the DLL's own CRT. They must not be passed to the caller's `free` (as in the Ownership section, only `mdx_free` releases memory). This policy does not conflict with the static CRT.
- Requirements: `cargo install cargo-xwin --locked` (the version we verified is 0.23.1). On first use it fetches the MSVC CRT and the Windows SDK (several hundred MB; you are treated as having agreed to Microsoft's license). It can be built from any host: macOS, Linux, or Windows.
- Windows arm64 has been verified only up to the build and the export / import check, and not on real hardware. CI's `flutter-windows` runs on an x64 runner.

### Rebuild procedure

```text
sh tool/build_native.sh linux windows   # you can pass only the targets you need
dart run tool/prebuilt_manifest.dart --write
```

`rust-toolchain.toml` lists every Rust target in the table above in `targets`. Changing `tool/build_native.sh` changes the manifest's source hash, so update it with `--write` (the SHA-256 of existing binaries does not change).

## Verification

- Rust: `cargo test --manifest-path native/Cargo.toml` (header, ABI failure contract, `mdx_build_info`, length limits).
- Dart: `test/parser/ir_decoder_test.dart` (independent of native; every prefix of byte streams built with the Dart-side encoder, corruption of every byte, huge counts, deep nesting), `test/parser/native_parser_test.dart` (the ABI of the actual binary, and every prefix of real IR).
- web: `node tool/check_wasm.mjs` and `flutter test --platform chrome test/parser/web_wasm_test.dart`.
- build: `sh tool/build_native.sh` (macOS / iOS / Android / Linux / Windows) and `sh tool/build_wasm.sh`. After rebuilding with the same rustc, record the SHA-256 of the binaries in `prebuilt/manifest.json` with `dart run tool/prebuilt_manifest.dart --write`.
