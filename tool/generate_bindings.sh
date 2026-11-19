#!/bin/sh
# Regenerates the C header and the Dart @Native bindings from the Rust C ABI
# (native/src/lib.rs). This script keeps the Rust and Dart signatures in sync.
#
#   sh tool/generate_bindings.sh
#
# 1. cbindgen: native/cbindgen.toml → native/include/mdx_native.h
# 2. ffigen:   ffigen.yaml          → lib/src/parser/native/bindings.dart
#
# Requires: cbindgen (`cargo install cbindgen --locked`), libclang (Xcode or apt's libclang-dev)
# (llvm-path in ffigen.yaml), and a prior `flutter pub get`.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v cbindgen >/dev/null 2>&1; then
  echo "cbindgen not found: cargo install cbindgen --locked" >&2
  exit 1
fi

echo "==> cbindgen"
(cd native && cbindgen --config cbindgen.toml --crate mdx_native --output include/mdx_native.h)

echo "==> ffigen"
dart run ffigen --config ffigen.yaml
dart format lib/src/parser/native/bindings.dart

echo "==> done"
