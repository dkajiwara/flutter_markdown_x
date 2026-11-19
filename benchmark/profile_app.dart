// A measurement app for append and huge-block scenarios, run in profile mode.
//
//   cd example
//   flutter run --profile -d macos -t ../benchmark/profile_app.dart \
//     --dart-define=MDX_BENCH_SCENARIOS=stream,stream-compat,blocks
//
// Results are printed to stdout as `MDX_BENCH {json}` lines, and the app exits when done.
// Values in debug mode or on a simulator differ greatly from a real device, so run in profile
// (the iOS simulator does not support profile; only desktop can be measured here).
// Results and conditions are recorded in doc/performance.md.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:material_ui/material_ui.dart';

import 'document.dart';

/// Scenarios to run (`stream`, `stream-compat`, `blocks`). Comma-separated.
///
/// `stream-compat` is the same append loop, but the parent rebuilds on every append with an inline
/// `MarkdownStyleSheet.fromTheme(Theme.of(context))` and an inline `builders` map, as
/// flutter_markdown call sites do.
const _scenarios = String.fromEnvironment(
  'MDX_BENCH_SCENARIOS',
  defaultValue: 'stream,blocks',
);

/// Changes the size of the huge block (`small` is for sanity checks).
const _scale = String.fromEnvironment('MDX_BENCH_SCALE', defaultValue: 'full');

/// Characters per append (assumes receiving a few tokens at a time).
const _appendStep = 60;

/// Number of appends per document size.
const _appendCount = 200;

/// FrameTiming callbacks arrive in a batch about 1 second after the frame.
const _flushDelay = Duration(milliseconds: 1500);

const _streamSizes = [20000, 100000, 400000];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _BenchApp());
}

class _BenchApp extends StatefulWidget {
  const _BenchApp();

  @override
  State<_BenchApp> createState() => _BenchAppState();
}

class _BenchAppState extends State<_BenchApp> {
  String _data = '';
  bool _streaming = false;
  Key _key = UniqueKey();
  final _scroll = ScrollController();
  bool _pinBottom = false;
  bool _compat = false;
  final _frames = <FrameTiming>[];
  final _results = <Map<String, Object?>>[];

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_frames.addAll);
    unawaited(Future<void>.delayed(const Duration(seconds: 1), _run));
  }

  Future<void> _run() async {
    _emit({
      'kind': 'env',
      'mode': const bool.fromEnvironment('dart.vm.product')
          ? 'release'
          : const bool.fromEnvironment('dart.vm.profile')
          ? 'profile'
          : 'debug',
      'os': Platform.operatingSystemVersion,
      'processors': Platform.numberOfProcessors,
      'dart': Platform.version.split(' ').first,
      'nativeParser': isNativeParserActive,
    });
    final names = _scenarios.split(',');
    try {
      if (names.contains('stream')) await _streamScenario();
      if (names.contains('stream-compat')) await _streamScenario(compat: true);
      if (names.contains('blocks')) await _blockScenarios();
    } on Object catch (error, stack) {
      print('MDX_BENCH_ERROR $error\n$stack');
    }
    print('MDX_BENCH_DONE');
    await stdout.flush();
    exit(0);
  }

  void _emit(Map<String, Object?> result) {
    _results.add(result);
    print('MDX_BENCH ${jsonEncode(result)}');
  }

  Future<void> _set(
    String data, {
    bool streaming = false,
    bool resetKey = false,
  }) async {
    setState(() {
      _data = data;
      _streaming = streaming;
      if (resetKey) _key = UniqueKey();
    });
    await WidgetsBinding.instance.endOfFrame;
    if (_pinBottom && _scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  }

  /// Discards accumulated FrameTimings and collects only subsequent frames.
  Future<void> _clearFrames() async {
    await Future<void>.delayed(_flushDelay);
    _frames.clear();
  }

  Future<List<FrameTiming>> _collectFrames() async {
    await Future<void>.delayed(_flushDelay);
    final frames = List<FrameTiming>.of(_frames);
    _frames.clear();
    return frames;
  }

  // -------------------------------------------------------------------------
  // streaming
  // -------------------------------------------------------------------------

  Future<void> _streamScenario({bool compat = false}) async {
    _compat = compat;
    final document = buildDocument(1500);
    for (final size in _streamSizes) {
      final end = size + _appendStep * _appendCount;
      assert(document.length >= end);

      // Time per append for the parser alone (synchronous; excludes frame wait time).
      if (isNativeParserActive && !compat) {
        final parser = IncrementalMarkdownParser();
        parser.parse(document.substring(0, size), streaming: true);
        final times = <double>[];
        for (var i = 1; i <= _appendCount; i++) {
          final data = document.substring(0, size + i * _appendStep);
          final stopwatch = Stopwatch()..start();
          parser.parse(data, streaming: true);
          times.add(stopwatch.elapsedMicroseconds / 1000);
        }
        _emit({
          'kind': 'stream-parser',
          'docChars': size,
          'appendChars': _appendStep,
          'appends': _appendCount,
          'parseMs': _stats(times),
        });
      }

      // The whole widget (parse + diff update + frame). Assumes a chat that follows the bottom.
      _pinBottom = true;
      await _set(document.substring(0, size), streaming: true, resetKey: true);
      await _set(document.substring(0, size), streaming: true);
      await _clearFrames();
      final rssBefore = ProcessInfo.currentRss;
      final wall = <double>[];
      for (var i = 1; i <= _appendCount; i++) {
        final stopwatch = Stopwatch()..start();
        await _set(
          document.substring(0, size + i * _appendStep),
          streaming: true,
        );
        wall.add(stopwatch.elapsedMicroseconds / 1000);
      }
      final frames = await _collectFrames();
      _pinBottom = false;
      _emit({
        'kind': compat ? 'stream-widget-compat' : 'stream-widget',
        'docChars': size,
        'appendChars': _appendStep,
        'appends': _appendCount,
        'frames': _frameStats(frames),
        'appendToFrameEndMs': _stats(wall),
        'rssBeforeMb': _mb(rssBefore),
        'rssAfterMb': _mb(ProcessInfo.currentRss),
        'maxRssMb': _mb(ProcessInfo.maxRss),
      });
      await _set('', resetKey: true);
    }
    _compat = false;
  }

  // -------------------------------------------------------------------------
  // A huge single block
  // -------------------------------------------------------------------------

  List<int> _sizes(List<int> full, List<int> small) =>
      _scale == 'small' ? small : full;

  Future<void> _blockScenarios() async {
    for (final n in _sizes([1000, 5000, 20000], [100, 300])) {
      await _blockCase(
        'list',
        n,
        [for (var i = 0; i < n; i++) '- item $i with **bold** and `code`']
            .join('\n'),
      );
    }
    for (final n in _sizes([250, 1000, 3000], [30, 60])) {
      final rows = [
        for (var i = 0; i < n; i++)
          '| row $i | value $i | note $i | ${i * 7} |',
      ].join('\n');
      await _blockCase(
        'table',
        n,
        '| name | value | note | n |\n|---|---|---:|---:|\n$rows',
      );
    }
    for (final n in _sizes([1000, 10000, 50000], [100, 300])) {
      final lines = [
        for (var i = 0; i < n; i++)
          'final value$i = compute($i, "string $i"); // comment $i',
      ].join('\n');
      await _blockCase('code', n, '```dart\n$lines\n```');
    }
  }

  Future<void> _blockCase(String kind, int n, String markdown) async {
    await _set('', resetKey: true);
    await _clearFrames();
    final rssBefore = ProcessInfo.currentRss;

    final parseWatch = Stopwatch()..start();
    parseMarkdown(markdown);
    final parseMs = parseWatch.elapsedMicroseconds / 1000;

    final stopwatch = Stopwatch()..start();
    await _set(markdown);
    final firstFrameMs = stopwatch.elapsedMicroseconds / 1000;
    // Frames from the second onward (already laid out). Repaint via scroll.
    final rssAfter = ProcessInfo.currentRss;
    final scrollWatch = Stopwatch()..start();
    var scrolls = 0;
    if (_scroll.hasClients) {
      for (var i = 0; i < 30; i++) {
        _scroll.jumpTo(min(_scroll.position.maxScrollExtent, (i + 1) * 400.0));
        await WidgetsBinding.instance.endOfFrame;
        scrolls++;
      }
    }
    final scrollMs = scrolls == 0
        ? 0.0
        : scrollWatch.elapsedMicroseconds / 1000 / scrolls;
    final frames = await _collectFrames();
    _emit({
      'kind': 'block',
      'block': kind,
      'size': n,
      'markdownChars': markdown.length,
      'parseMs': parseMs,
      'setStateToFrameEndMs': firstFrameMs,
      'scrollFrameWallMs': scrollMs,
      'frames': _frameStats(frames),
      'rssBeforeMb': _mb(rssBefore),
      'rssAfterMb': _mb(rssAfter),
      'maxRssMb': _mb(ProcessInfo.maxRss),
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  // -------------------------------------------------------------------------

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        // Use Markdown so it can be compared in the same file as the pre-change implementation (ListView version).
        body: _compat
            ? _compatMarkdown(context)
            : Markdown(
                key: _key,
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                data: _data,
                streaming: _streaming,
              ),
      ),
    );
  }
}

extension on _BenchAppState {
  // Created anew on every build, like a flutter_markdown call site.
  Widget _compatMarkdown(BuildContext context) {
    return Markdown(
      key: _key,
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      data: _data,
      streaming: _streaming,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
      builders: <String, MarkdownElementBuilder>{'code': _PassBuilder()},
    );
  }
}

/// A builder that leaves rendering to the default (returns null).
class _PassBuilder extends MarkdownElementBuilder {}

double _mb(int bytes) => double.parse((bytes / 1048576).toStringAsFixed(1));

double _percentile(List<double> sorted, double p) {
  if (sorted.isEmpty) return 0;
  final index = ((sorted.length - 1) * p).round();
  return sorted[index];
}

Map<String, Object?> _stats(List<double> values) {
  final sorted = [...values]..sort();
  double round(double v) => double.parse(v.toStringAsFixed(3));
  return {
    'n': sorted.length,
    'mean': round(
      sorted.isEmpty ? 0 : sorted.reduce((a, b) => a + b) / sorted.length,
    ),
    'p50': round(_percentile(sorted, 0.5)),
    'p90': round(_percentile(sorted, 0.9)),
    'p99': round(_percentile(sorted, 0.99)),
    'max': round(sorted.isEmpty ? 0 : sorted.last),
  };
}

Map<String, Object?> _frameStats(List<FrameTiming> frames) {
  double ms(Duration d) => d.inMicroseconds / 1000;
  final build = [for (final f in frames) ms(f.buildDuration)];
  final raster = [for (final f in frames) ms(f.rasterDuration)];
  final total = [for (final f in frames) ms(f.totalSpan)];
  return {
    'count': frames.length,
    'buildMs': _stats(build),
    'rasterMs': _stats(raster),
    'totalMs': _stats(total),
    'over16ms': total.where((t) => t > 16.7).length,
    'over33ms': total.where((t) => t > 33.4).length,
  };
}
