// Conformance measurement against CommonMark 0.31.2 and GFM 0.29 (extensions).
//
// Prints the pass rate per section, and fails only on regression from the baseline
// (an example that used to pass now fails).
//
// Environment variables:
//   MDX_UPDATE_CONFORMANCE=1  rewrite baseline.json with the current results
//   MDX_CONFORMANCE_DUMP=path write the diffs of failed examples to path
//
// VM only: uses the native parser (dart:ffi) and reads files through dart:io.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_markdown_x/src/parser/native/native_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'conformance_support.dart';

const _baselinePath = 'test/conformance/baseline.json';
const _suites = <String, String>{
  'commonmark': 'test/fixtures/commonmark_0.31.2.json',
  'gfm': 'test/fixtures/gfm_0.29.json',
};

String _categories(List<ExampleResult> results) {
  final ids = <String, List<int>>{};
  for (final r in results.where((r) => !r.tolerantPass)) {
    ids.putIfAbsent(r.category, () => []).add(r.example.id);
  }
  if (ids.isEmpty) return 'none';
  return ids.entries
      .map(
        (e) =>
            '${e.key}=${e.value.length}'
            '${e.value.length <= 6 ? ' ${e.value}' : ''}',
      )
      .join(', ');
}

void main() {
  final update = Platform.environment['MDX_UPDATE_CONFORMANCE'] == '1';
  final dumpPath = Platform.environment['MDX_CONFORMANCE_DUMP'];
  final fixtures = {
    for (final e in _suites.entries) e.key: loadFixture(e.value),
  };
  // The parser is the Rust implementation only. Without the binary the test fails (no skip).
  final backends = <ConformanceBackend>[
    const ConformanceBackend('native', parseNative),
  ];

  final baseline = readBaseline(_baselinePath);
  final dump = StringBuffer();

  for (final backend in backends) {
    test('conformance (${backend.name}): no regression vs baseline', () {
      expect(
        isNativeParserAvailable,
        isTrue,
        reason: 'native parser is unavailable: $nativeParserUnavailableReason',
      );
      final problems = <String>[];
      for (final suite in _suites.keys) {
        final results = runSuite(backend, fixtures[suite]!);
        // ignore: avoid_print
        print(
          '\n${formatTable('[${backend.name}] $suite', results)}'
          'list-tightness-only: '
          '${results.where((r) => r.outcome == Outcome.listTightness).length}, '
          'exceptions: '
          '${results.where((r) => r.outcome == Outcome.exception).length}\n'
          'failure categories: ${_categories(results)}',
        );

        for (final r in results.where((r) => !r.tolerantPass)) {
          dump
            ..writeln(
              '=== ${backend.name} $suite #${r.example.id} '
              '[${r.example.section}] ${r.outcome.name}',
            )
            ..writeln(
              '--- markdown\n${r.example.markdown}'
              '--- expected\n${r.expected}\n--- actual\n${r.actual}\n',
            );
        }

        final current = BaselineEntry.fromResults(results);
        final base = baseline[backend.name]?[suite];
        if (update) {
          baseline.putIfAbsent(backend.name, () => {})[suite] = current;
          continue;
        }
        if (base == null) {
          // ignore: avoid_print
          print(
            '[conformance] no baseline for ${backend.name}/$suite '
            '(run with MDX_UPDATE_CONFORMANCE=1)',
          );
          continue;
        }
        final strictLost = base.strict.toSet().difference(
          current.strict.toSet(),
        );
        final tolerantLost = base.tolerant.toSet().difference(
          current.tolerant.toSet(),
        );
        final gained = current.strict.toSet().difference(base.strict.toSet());
        if (gained.isNotEmpty) {
          final ids = gained.toList()..sort();
          // ignore: avoid_print
          print(
            '[conformance] newly passing ${backend.name}/$suite: $ids '
            '-> update baseline with MDX_UPDATE_CONFORMANCE=1',
          );
        }
        if (strictLost.isNotEmpty || tolerantLost.isNotEmpty) {
          problems.add(
            '${backend.name}/$suite regressed: '
            'strict=${(strictLost.toList()..sort())} '
            'tolerant=${(tolerantLost.toList()..sort())}',
          );
        }
      }
      if (update) {
        writeBaseline(_baselinePath, baseline);
        // ignore: avoid_print
        print('[conformance] baseline updated: $_baselinePath');
      }
      if (dumpPath != null) {
        File(dumpPath).writeAsStringSync(dump.toString());
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }
}
