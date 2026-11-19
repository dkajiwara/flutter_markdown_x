// Maintainer benchmark. From example/: flutter build web
// --target=../benchmark/web_parser.dart --output=/tmp/mdx-web-benchmark
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:material_ui/material_ui.dart';

@JS('__mdxBenchmark')
external set _benchmarkResult(JSAny value);

const _sample = '''# Markdown 日本語 🚀

A paragraph with **bold**, *emphasis*, [a link](https://example.com),
and inline `code`. 日本語の文と記号を含める。

- First item
- Second item

| Name | Value |
| --- | --- |
| α | 123 |

```dart
final message = 'hello';
```

''';

double _medianMicros(
  List<MdxBlock> Function(String) parse,
  String source,
  int iterations,
) {
  for (var i = 0; i < 10; i++) {
    parse(source);
  }
  final times = <double>[];
  for (var round = 0; round < 5; round++) {
    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      parse(source);
    }
    watch.stop();
    times.add(watch.elapsedMicroseconds / iterations);
  }
  times.sort();
  return times[times.length ~/ 2];
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final startup = Stopwatch()..start();
  await initializeParser();
  startup.stop();
  final cases = <Map<String, Object>>[];
  if (isNativeParserActive) {
    for (final (repetitions, iterations) in [(1, 200), (20, 20), (200, 3)]) {
      final source = List.filled(repetitions, _sample).join();
      final wasmMicros = _medianMicros(parseMarkdown, source, iterations);
      cases.add({
        'utf8Bytes': utf8.encode(source).length,
        'iterationsPerRound': iterations,
        'wasmMicrosPerParse': wasmMicros,
      });
    }
  }
  final result = {
    'active': isNativeParserActive,
    'initializationMillis': startup.elapsedMicroseconds / 1000,
    'rounds': 5,
    'statistic':
        'median per parse; warm parser, includes UTF-8 and IR decoding',
    'cases': cases,
  };
  _benchmarkResult = result.jsify()!;
  final report = const JsonEncoder.withIndent('  ').convert(result);
  // ignore: avoid_print
  print('MDX_WEB_BENCHMARK $report');
  runApp(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: Text(report))),
    ),
  );
}
