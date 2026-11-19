#!/bin/sh
# Checks that a consuming app can use the package from the published archive contents.
#
#   sh tool/package_smoke_test.sh
#
# 1. Run `flutter pub publish --dry-run`. A successful dry-run is mandatory: any non-zero exit
#    fails the script, except one explicitly allowed case. When the working tree is dirty, pub
#    warns "N checked-in file(s) modified/untracked" and exits non-zero; that single kind of
#    warning is tolerated for local runs (the published candidate must be committed, and CI runs
#    on a clean checkout, where the allowance never applies). Any other warning or any error fails.
#    Then check that the listing includes the bundled binaries, WASM, and build hook, and does
#    not include build outputs or the maintainer-only files that .pubignore excludes.
# 2. Extract the committed files into a temp directory, minus the tracked files that .pubignore
#    excludes, and reference them by path from a new app. This approximates the pub archive; it
#    is not identical to it. `git archive HEAD` plus the .pubignore rules (matched with
#    `git ls-files --ignored --exclude-from=.pubignore`) gives the same file set as pub for this
#    repository, but pub has its own rules (for example it skips some hidden files) and reads
#    .gitignore files in subdirectories on its own. The authoritative list is the dry-run output.
# 3. In that app, run a widget test (native is required if the host is macOS or Linux) and a web build.
#
# Uncommitted changes are not extracted, so run this after committing.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mdx_smoke.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PACKAGE="$WORK/flutter_markdown_x"
APP="$WORK/consumer"

echo "==> publish dry-run"
cd "$ROOT"
status=0
flutter pub publish --dry-run > "$WORK/publish.txt" 2>&1 || status=$?
cat "$WORK/publish.txt"

# Any error fails, whatever the exit code says.
if grep -qE 'Package validation found the following (error|errors)' "$WORK/publish.txt"; then
  echo "The publish dry-run reported errors" >&2
  exit 1
fi
if [ "$status" -ne 0 ]; then
  # The only tolerated failure: a dirty tree. Every warning must be the "checked-in file" kind.
  warnings="$(grep -cE '^\* ' "$WORK/publish.txt" || true)"
  dirty_warnings="$(grep -cE '^\* [0-9]+ checked-in files? (is|are) (modified|untracked)' "$WORK/publish.txt" || true)"
  if [ "$warnings" -eq 0 ] || [ "$warnings" -ne "$dirty_warnings" ]; then
    echo "The publish dry-run failed (exit $status) for a reason other than uncommitted changes" >&2
    exit 1
  fi
  echo "note: tolerating the uncommitted-changes warning (commit before publishing)" >&2
fi

require() {
  if ! grep -q "$1" "$WORK/publish.txt"; then
    echo "The published archive does not include $1" >&2
    exit 1
  fi
}
require 'build.dart'
require 'libmdx_native.so'
require 'libmdx_native.dylib'
require 'mdx_native.dll'
require 'mdx_native.wasm'
require 'manifest.json'
require 'LICENSE'
if grep -qE '(^|[^a-z])target/|\.dart_tool' "$WORK/publish.txt"; then
  echo "The published archive includes build outputs" >&2
  exit 1
fi
# The WASM module ships once (prebuilt/web); the test fixture symlinks are excluded.
if [ "$(grep -c 'mdx_native\.wasm' "$WORK/publish.txt")" -ne 1 ]; then
  echo "mdx_native.wasm should appear exactly once in the published archive" >&2
  exit 1
fi

echo "==> extract committed package (minus .pubignore)"
mkdir -p "$PACKAGE"
git -C "$ROOT" archive HEAD | tar -x -C "$PACKAGE"
git -C "$ROOT" ls-files --cached --ignored --exclude-from=.pubignore > "$WORK/pubignored.txt"
(cd "$PACKAGE" && xargs -I{} rm -rf "{}" < "$WORK/pubignored.txt")

echo "==> create consumer app"
case "$(uname -s)" in
  Linux) PLATFORMS=linux,web ;;
  *) PLATFORMS=macos,web ;;
esac
flutter create --no-pub --platforms="$PLATFORMS" --project-name mdx_consumer "$APP" > /dev/null
cd "$APP"
flutter pub add "flutter_markdown_x:{\"path\":\"$PACKAGE\"}"
# The package follows the Theme of material_ui, so the app (and this test) uses that, not the
# deprecated package:flutter/material.dart.
flutter pub add material_ui

mkdir -p test
cat > test/smoke_test.dart <<'EOF'
import 'dart:io';

import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('native parser is active on macOS and Linux', () {
    if (!Platform.isMacOS && !Platform.isLinux) return;
    expect(isNativeParserActive, isTrue);
  });

  testWidgets('renders Markdown', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Markdown(data: '# Hello\n\n**world**'))),
    );
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('world', findRichText: true), findsOneWidget);
  });
}
EOF

echo "==> consumer widget test"
flutter test --no-pub test/smoke_test.dart

echo "==> consumer web build"
flutter build web --no-pub > /dev/null
test -f build/web/assets/packages/flutter_markdown_x/prebuilt/web/mdx_native.wasm

echo "==> package smoke test passed"
