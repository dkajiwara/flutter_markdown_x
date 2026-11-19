// Counts the work done per append (characters scanned and characters passed to the parser).
//
//   flutter test benchmark/append_work_benchmark_test.dart
//
// It counts characters rather than time, so results are reproducible in any environment. Used to
// confirm that per-append work does not grow as the document grows (the append fast path).
// ignore_for_file: avoid_print
import 'dart:math';

import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';

import 'document.dart';

const _sectionCounts = [20, 100, 500, 2500];
const _appends = 100;
const _step = 60;

void main() {
  test('append work', () {
    print(
      'sections |    chars | scanned/append (max) | parsed/append (max) | '
      'full scan per append',
    );
    for (final sections in _sectionCounts) {
      final parser = IncrementalMarkdownParser();
      var source = buildDocument(sections);
      parser.parse(source, streaming: true);
      var scanned = 0;
      var parsed = 0;
      for (var i = 0; i < _appends; i++) {
        source += List.filled(_step ~/ 6, 'word ').join();
        if (i % 10 == 9) source += '\n\n';
        final s0 = parser.debugScannedChars;
        final p0 = parser.debugParsedChars;
        parser.parse(source, streaming: true);
        scanned = max(scanned, parser.debugScannedChars - s0);
        parsed = max(parsed, parser.debugParsedChars - p0);
      }
      print(
        '${sections.toString().padLeft(8)} | ${source.length.toString().padLeft(8)} | '
        '${scanned.toString().padLeft(20)} | ${parsed.toString().padLeft(19)} | '
        '${source.length.toString().padLeft(8)} chars (old implementation)',
      );
    }
  });
}
