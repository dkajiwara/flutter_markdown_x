/// Shared conformance logic: loading fixtures, running backends, classification.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_markdown_x/src/ir/nodes.dart';

import 'html_normalize.dart';
import 'ir_html.dart';

/// One parser backend.
class ConformanceBackend {
  const ConformanceBackend(this.name, this.parse);

  final String name;
  final List<MdxBlock> Function(String) parse;
}

/// One fixture entry.
class ConformanceExample {
  ConformanceExample(Map<String, dynamic> json)
    : id = json['example'] as int,
      markdown = json['markdown'] as String,
      html = json['html'] as String,
      section = json['section'] as String;

  final int id;
  final String markdown;
  final String html;
  final String section;
}

/// Classification of a result.
enum Outcome {
  /// The normalized HTML matched exactly.
  pass,

  /// Differs only in the presence of `<p>` due to tight / loose lists.
  listTightness,

  /// The parser threw an exception.
  exception,

  /// Any other mismatch.
  fail,
}

class ExampleResult {
  ExampleResult(this.example, this.outcome, this.actual, this.expected);

  final ConformanceExample example;
  final Outcome outcome;

  /// The normalized actual HTML (the exception message if it threw).
  final String actual;
  final String expected;

  /// A coarse classification of the failure (automatic).
  ///
  /// - `raw-html`: the input appears to contain HTML tags, and this likely conflicts with
  ///   the by-design rule of not emitting tags outside the allowed set.
  /// - `gfm-autolink`: the GFM extended autolink created more links than CommonMark
  ///   core expects.
  /// - `other`: anything else. Needs individual investigation.
  String get category {
    if (tolerantPass) return outcome.name;
    if (RegExp(r'<[a-zA-Z/!?]').hasMatch(example.markdown)) return 'raw-html';
    if (!expected.contains('<a ') && actual.contains('<a ')) {
      return 'gfm-autolink';
    }
    return 'other';
  }

  bool get strictPass => outcome == Outcome.pass;
  bool get tolerantPass =>
      outcome == Outcome.pass || outcome == Outcome.listTightness;
}

List<ConformanceExample> loadFixture(String path) {
  final data = jsonDecode(File(path).readAsStringSync()) as List<dynamic>;
  return [
    for (final e in data.cast<Map<String, dynamic>>()) ConformanceExample(e),
  ];
}

ExampleResult runExample(ConformanceBackend backend, ConformanceExample ex) {
  final expectedStrict = normalizeHtml(ex.html);
  try {
    final actualHtml = blocksToHtml(backend.parse(ex.markdown));
    final actual = normalizeHtml(actualHtml);
    if (actual == expectedStrict) {
      return ExampleResult(ex, Outcome.pass, actual, expectedStrict);
    }
    final expectedLoose = normalizeHtml(ex.html, tolerantLists: true);
    final actualLoose = normalizeHtml(actualHtml, tolerantLists: true);
    if (actualLoose == expectedLoose) {
      return ExampleResult(ex, Outcome.listTightness, actual, expectedStrict);
    }
    return ExampleResult(ex, Outcome.fail, actual, expectedStrict);
  } on Object catch (e) {
    return ExampleResult(ex, Outcome.exception, '$e', expectedStrict);
  }
}

List<ExampleResult> runSuite(
  ConformanceBackend backend,
  List<ConformanceExample> examples,
) => [for (final ex in examples) runExample(backend, ex)];

/// Per-section totals (preserving the order in which sections appear).
Map<String, List<ExampleResult>> bySection(List<ExampleResult> results) {
  final map = <String, List<ExampleResult>>{};
  for (final r in results) {
    map.putIfAbsent(r.example.section, () => []).add(r);
  }
  return map;
}

String pct(int n, int total) =>
    total == 0 ? '-' : '${(n * 100 / total).toStringAsFixed(1)}%';

/// Turns the per-section pass rate table into a string.
String formatTable(String title, List<ExampleResult> results) {
  final sections = bySection(results);
  final width = sections.keys.fold<int>(
    7,
    (w, k) => k.length > w ? k.length : w,
  );
  final b = StringBuffer()
    ..writeln(title)
    ..writeln(
      '${'section'.padRight(width)}  total  strict  tolerant   strict%  tolerant%',
    );
  void row(String name, List<ExampleResult> rs) {
    final s = rs.where((r) => r.strictPass).length;
    final t = rs.where((r) => r.tolerantPass).length;
    b.writeln(
      '${name.padRight(width)}  ${'${rs.length}'.padLeft(5)}  '
      '${'$s'.padLeft(6)}  ${'$t'.padLeft(8)}   '
      '${pct(s, rs.length).padLeft(7)}  ${pct(t, rs.length).padLeft(9)}',
    );
  }

  sections.forEach(row);
  row('TOTAL', results);
  return b.toString();
}

/// One suite of baseline.json: the pass IDs for strict and tolerant.
class BaselineEntry {
  BaselineEntry(this.strict, this.tolerant);

  factory BaselineEntry.fromResults(List<ExampleResult> results) =>
      BaselineEntry(
        [
          for (final r in results)
            if (r.strictPass) r.example.id,
        ]..sort(),
        [
          for (final r in results)
            if (r.tolerantPass) r.example.id,
        ]..sort(),
      );

  factory BaselineEntry.fromJson(Map<String, dynamic> json) => BaselineEntry(
    (json['strict'] as List<dynamic>).cast<int>(),
    (json['tolerant'] as List<dynamic>).cast<int>(),
  );

  final List<int> strict;
  final List<int> tolerant;

  Map<String, Object> toJson() => {'strict': strict, 'tolerant': tolerant};
}

/// The whole baseline (`{backend: {suite: entry}}`).
Map<String, Map<String, BaselineEntry>> readBaseline(String path) {
  final file = File(path);
  if (!file.existsSync()) return {};
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final b in json.entries)
      b.key: {
        for (final s in (b.value as Map<String, dynamic>).entries)
          s.key: BaselineEntry.fromJson(s.value as Map<String, dynamic>),
      },
  };
}

void writeBaseline(
  String path,
  Map<String, Map<String, BaselineEntry>> baseline,
) {
  final sorted = {
    for (final b in baseline.keys.toList()..sort())
      b: {
        for (final s in baseline[b]!.keys.toList()..sort())
          s: baseline[b]![s]!.toJson(),
      },
  };
  File(path).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(sorted)}\n',
  );
}
