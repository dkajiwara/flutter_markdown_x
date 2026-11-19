#!/bin/sh
# Builds the native parser for each platform and places the results in prebuilt/.
#
#   sh tool/build_native.sh            # all targets
#   sh tool/build_native.sh macos ios  # only the given OSes
#
# Requires: rustup targets, Xcode, and the Android NDK.
# The NDK is taken from ANDROID_NDK_HOME, or else the latest one in the Android SDK.
#
# linux needs zig and cargo-zigbuild (brew install zig, cargo install cargo-zigbuild --locked),
# and windows needs cargo-xwin (cargo install cargo-xwin --locked); both can cross-build from any host.
# On a Linux host, linux can also be built with plain cargo
# (LINUX_BUILDER=cargo builds only the host arch; used by CI's native-rebuild-linux).
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/native/Cargo.toml"
TARGET_DIR="$ROOT/native/target"
OUT="$ROOT/prebuilt"
LIBRARY=mdx_native

# Minimum supported OS versions. Match Flutter's defaults.
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.15}"
export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-13.0}"
ANDROID_API="${ANDROID_API:-24}"
# The minimum glibc the Linux binaries require: 2.17 (CentOS 7 equivalent) for both x64 and arm64.
GLIBC_VERSION="${GLIBC_VERSION:-2.17}"
# How to build linux: zigbuild (default; lets you set the glibc floor) or cargo.
LINUX_BUILDER="${LINUX_BUILDER:-zigbuild}"

# Replace build-machine paths (the cargo registry, the toolchain sources, and
# this checkout) that rustc embeds in panic locations, so the shipped binaries
# do not reveal the maintainer's home directory. Paths must not contain spaces.
BASE_RUSTFLAGS="--remap-path-prefix=${CARGO_HOME:-$HOME/.cargo}=/cargo --remap-path-prefix=${RUSTUP_HOME:-$HOME/.rustup}=/rustup --remap-path-prefix=$ROOT=/flutter_markdown_x"
export RUSTFLAGS="$BASE_RUSTFLAGS"

# Rust target, output directory, and library file name.
build() {
  rust_target="$1"
  directory="$2"
  file="$3"
  echo "==> $rust_target"
  cargo build --release --manifest-path "$MANIFEST" --target "$rust_target"
  install_output "$rust_target" "$directory" "$file"
}

install_output() {
  rust_target="$1"
  directory="$2"
  file="$3"
  mkdir -p "$OUT/$directory"
  cp "$TARGET_DIR/$rust_target/release/$file" "$OUT/$directory/$file"
}

# Flutter rewrites the install name of bundled dylibs to a path inside the
# consuming app's build directory. Without spare header space,
# install_name_tool fails when that path is long, so reserve the maximum.
# The install name is fixed to @rpath so the build machine path is not embedded.
APPLE_RUSTFLAGS="-C link-arg=-Wl,-headerpad_max_install_names -C link-arg=-Wl,-install_name,@rpath/libmdx_native.dylib"

build_macos() {
  export RUSTFLAGS="$BASE_RUSTFLAGS $APPLE_RUSTFLAGS"
  build aarch64-apple-darwin macos-arm64 "lib$LIBRARY.dylib"
  build x86_64-apple-darwin macos-x64 "lib$LIBRARY.dylib"
  export RUSTFLAGS="$BASE_RUSTFLAGS"
}

build_ios() {
  export RUSTFLAGS="$BASE_RUSTFLAGS $APPLE_RUSTFLAGS"
  build aarch64-apple-ios ios-arm64 "lib$LIBRARY.dylib"
  build aarch64-apple-ios-sim ios-arm64-sim "lib$LIBRARY.dylib"
  build x86_64-apple-ios ios-x64-sim "lib$LIBRARY.dylib"
  export RUSTFLAGS="$BASE_RUSTFLAGS"
}

build_linux() {
  if [ "$LINUX_BUILDER" = cargo ]; then
    # Plain cargo has no cross linker, so build only the host arch.
    case "$(uname -m)" in
      x86_64) build x86_64-unknown-linux-gnu linux-x64 "lib$LIBRARY.so" ;;
      aarch64 | arm64) build aarch64-unknown-linux-gnu linux-arm64 "lib$LIBRARY.so" ;;
      *) echo "unsupported host: $(uname -m)" >&2; exit 1 ;;
    esac
    return
  fi
  for arch in x86_64 aarch64; do
    rust_target="$arch-unknown-linux-gnu"
    echo "==> $rust_target (glibc $GLIBC_VERSION)"
    cargo zigbuild --release --manifest-path "$MANIFEST" \
      --target "$rust_target.$GLIBC_VERSION"
    case "$arch" in
      x86_64) directory=linux-x64 ;;
      aarch64) directory=linux-arm64 ;;
    esac
    install_output "$rust_target" "$directory" "lib$LIBRARY.so"
  done
}

build_windows() {
  # Statically link the MSVC CRT so users do not need the VC++ Redistributable.
  # xwin fetches the MSVC CRT and the Windows SDK (several hundred MB on first run).
  export RUSTFLAGS="$BASE_RUSTFLAGS -C target-feature=+crt-static"
  for arch in x86_64 aarch64; do
    rust_target="$arch-pc-windows-msvc"
    echo "==> $rust_target"
    cargo xwin build --release --manifest-path "$MANIFEST" --target "$rust_target"
    case "$arch" in
      x86_64) directory=windows-x64 ;;
      aarch64) directory=windows-arm64 ;;
    esac
    install_output "$rust_target" "$directory" "$LIBRARY.dll"
  done
  export RUSTFLAGS="$BASE_RUSTFLAGS"
}

build_android() {
  sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  ndk="${ANDROID_NDK_HOME:-$(ls -d "$sdk"/ndk/* | sort -V | tail -1)}"
  host="$(ls "$ndk/toolchains/llvm/prebuilt" | head -1)"
  bin="$ndk/toolchains/llvm/prebuilt/$host/bin"
  echo "using NDK: $ndk"

  export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$bin/aarch64-linux-android$ANDROID_API-clang"
  export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER="$bin/armv7a-linux-androideabi$ANDROID_API-clang"
  export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$bin/x86_64-linux-android$ANDROID_API-clang"
  # Make the library loadable on Android 15+ devices with 16 KB pages.
  export RUSTFLAGS="$BASE_RUSTFLAGS -C link-arg=-Wl,-z,max-page-size=16384"

  build aarch64-linux-android android-arm64 "lib$LIBRARY.so"
  build armv7-linux-androideabi android-arm "lib$LIBRARY.so"
  build x86_64-linux-android android-x64 "lib$LIBRARY.so"
  export RUSTFLAGS="$BASE_RUSTFLAGS"
}

if [ "$#" -eq 0 ]; then
  set -- macos ios android linux windows
fi
for os in "$@"; do
  case "$os" in
    macos) build_macos ;;
    ios) build_ios ;;
    android) build_android ;;
    linux) build_linux ;;
    windows) build_windows ;;
    *) echo "unknown target: $os" >&2; exit 1 ;;
  esac
done

echo "==> done"
find "$OUT" -type f -exec ls -l {} \; | awk '{print $5, $9}'
