#!/bin/sh
# Runs every test file that can run in a browser on Chrome (`flutter test --platform chrome`).
#
# `flutter test` compiles every file it is given for the browser even when the file says
# `@TestOn('vm')`, and files that use dart:ffi, dart:io or paths outside test/ do not compile, so
# the VM-only files are left out here instead. A new test file runs on Chrome unless it is marked
# `@TestOn('vm')` with a comment that says why.
#
# Needs Chrome (set CHROME_EXECUTABLE if it is not found). Extra arguments go to `flutter test`.
set -eu
cd "$(dirname "$0")/.."
find test -name '*_test.dart' | sort | xargs grep -L "@TestOn('vm')" > "${TMPDIR:-/tmp}/mdx_chrome_tests.txt"
xargs flutter test --no-pub --platform chrome "$@" < "${TMPDIR:-/tmp}/mdx_chrome_tests.txt"
