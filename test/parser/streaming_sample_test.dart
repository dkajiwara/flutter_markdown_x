// Streaming the example app's sample document.
//
// VM only: the sample lives in example/, outside the test root that `flutter test --platform
// chrome` compiles.
@TestOn('vm')
library;

import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';

// example is a separate package, so it cannot be imported via package:.
// ignore: avoid_relative_lib_imports
import '../../example/lib/sample.dart';
import '../support/prefixes.dart';

void main() {
  test('streaming the example sample matches the full parse once complete', () {
    final parser = IncrementalMarkdownParser();
    for (final i in prefixEnds(sampleMarkdown)) {
      if (i % 7 != 0) continue;
      parser.parse(sampleMarkdown.substring(0, i), streaming: true);
    }
    expect(parser.parse(sampleMarkdown), parseMarkdown(sampleMarkdown));
  });
}
