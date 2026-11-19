#!/bin/sh
# Build the precompiled Flutter Web parser artifact.
#
# Maintainers need Rust and the wasm32-unknown-unknown target. Consumers use
# the checked-in prebuilt/web/mdx_native.wasm and do not need a Rust toolchain.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/native/Cargo.toml"
TARGET_DIR="$ROOT/native/target"
TARGET="wasm32-unknown-unknown"
OUT="$ROOT/prebuilt/web/mdx_native.wasm"

# Replace build-machine paths embedded in panic locations (see build_native.sh).
export RUSTFLAGS="--remap-path-prefix=${CARGO_HOME:-$HOME/.cargo}=/cargo --remap-path-prefix=${RUSTUP_HOME:-$HOME/.rustup}=/rustup --remap-path-prefix=$ROOT=/flutter_markdown_x"
cargo build --locked --release --manifest-path "$MANIFEST" --target "$TARGET"
mkdir -p "$(dirname -- "$OUT")"
cp "$TARGET_DIR/$TARGET/release/mdx_native.wasm" "$OUT"

echo "Built $OUT"
ls -lh "$OUT"
