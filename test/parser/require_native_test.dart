// The Rust parser is the package's only parser, so the whole suite fails in an
// environment without the binary. Here we check that explicitly, with a reason.
//
// The former `MDX_REQUIRE_NATIVE=1` is no longer needed (always required). It is
// harmless if CI still sets it.
@TestOn('vm')
library;

import 'package:flutter_markdown_x/src/parser/native/native_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native parser is usable (a missing binary or ABI mismatch fails)', () {
    expect(
      isNativeParserAvailable,
      isTrue,
      reason:
          'native parser is required but unavailable: '
          '$nativeParserUnavailableReason (sh tool/build_native.sh)',
    );
  });
}
