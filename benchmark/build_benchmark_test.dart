// Compares the time to build a widget against other libraries.
//
//   flutter test benchmark/build_benchmark_test.dart
//
// flutter test runs in debug mode (JIT), so absolute values differ greatly from a release build
// on a real device. Use it for relative comparison between libraries and to check trends.
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart' as fmp;
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';

import 'document.dart';

const _sections = 200;
const _runs = 10;

/// Number of times to append to the end, simulating streaming.
const _appendSteps = 20;
const _appendChunk = ' more';

typedef _Builder = Widget Function(String data);

final _candidates = <String, _Builder>{
  'flutter_markdown_x': (data) => Markdown(data: data),
  'flutter_markdown_plus': (data) => fmp.Markdown(data: data),
  'markdown + fwfh_core (ListView)': (data) => HtmlWidget(
    md.markdownToHtml(data, extensionSet: md.ExtensionSet.gitHubFlavored),
    // By default long HTML is built asynchronously and falls outside the pump measurement.
    buildAsync: false,
    renderMode: RenderMode.listView,
  ),
};

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

double _median(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

String _ms(double value) => '${value.toStringAsFixed(2).padLeft(9)} ms';

void main() {
  final document = buildDocument(_sections);
  final results = <String, (double, double)>{};

  for (final MapEntry(key: name, value: builder) in _candidates.entries) {
    testWidgets(name, (tester) async {
      final initial = <double>[];
      final append = <double>[];

      for (var run = 0; run < _runs; run++) {
        await tester.pumpWidget(const SizedBox());

        var data = document;
        final stopwatch = Stopwatch()..start();
        await tester.pumpWidget(_app(builder(data)));
        initial.add(stopwatch.elapsedMicroseconds / 1000);

        stopwatch.reset();
        for (var step = 0; step < _appendSteps; step++) {
          data = '$data$_appendChunk';
          await tester.pumpWidget(_app(builder(data)));
        }
        append.add(stopwatch.elapsedMicroseconds / 1000 / _appendSteps);
      }

      results[name] = (_median(initial), _median(append));
    });
  }

  tearDownAll(() {
    final blocks = _sections * blocksPerSection + 1;
    // ignore: avoid_print
    print(
      '\n$_sections sections ($blocks blocks, ${document.length} chars), '
      'median of $_runs runs\n'
      '${'library'.padRight(34)}| initial build | update per append',
    );
    for (final MapEntry(key: name, value: (initial, append))
        in results.entries) {
      // ignore: avoid_print
      print('${name.padRight(34)}| ${_ms(initial)}  | ${_ms(append)}');
    }
  });
}
