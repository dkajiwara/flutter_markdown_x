// Measures the parse time of the Rust implementation (through FFI) and, for reference, the AST build time of the `markdown` package.
//
//   flutter test benchmark/native_parse_benchmark.dart
//
// The native parser is bundled by the build hook, so run this with flutter test, where the hook runs.
// It runs under JIT, so absolute values are only a guide. Use it for relative comparison.
// ignore_for_file: avoid_print
import 'package:flutter_markdown_x/src/parser/native/ir_decoder.dart';
import 'package:flutter_markdown_x/src/parser/native/native_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

import 'document.dart';

const _sectionCounts = [1, 10, 100, 1000];
const _warmupRuns = 20;
const _measuredRuns = 30;
const _columnWidth = 9;

double _measureMs(void Function() body) {
  for (var i = 0; i < _warmupRuns; i++) {
    body();
  }
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < _measuredRuns; i++) {
    body();
  }
  return stopwatch.elapsedMicroseconds / _measuredRuns / 1000;
}

String _cell(double ms) => '${ms.toStringAsFixed(3).padLeft(_columnWidth)} ms';

void main() {
  test('parse benchmark', () {
    expect(
      isNativeParserAvailable,
      isTrue,
      reason: nativeParserUnavailableReason,
    );
    print(
      'sections |    chars |  md AST (ref) | Rust total |  Rust call |     decode '
      '| speedup',
    );
    for (final sections in _sectionCounts) {
      final source = buildDocument(sections);
      final ast = _measureMs(
        () => md.Document(
          extensionSet: md.ExtensionSet.gitHubFlavored,
          encodeHtml: true,
        ).parse(source),
      );
      final total = _measureMs(() => parseNative(source));
      // The call includes conversion to UTF-8, FFI, parsing in Rust, and copying the result.
      final call = _measureMs(() => parseNativeToBytes(source));
      final bytes = parseNativeToBytes(source);
      final decode = _measureMs(() => decodeIr(bytes));
      print(
        '${sections.toString().padLeft(8)} | '
        '${source.length.toString().padLeft(8)} | '
        '${_cell(ast)} | ${_cell(total)} | ${_cell(call)} | ${_cell(decode)} | '
        '${(ast / total).toStringAsFixed(1).padLeft(6)}x',
      );
    }
  });
}
