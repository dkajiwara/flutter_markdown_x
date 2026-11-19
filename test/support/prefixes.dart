/// Returns the list of N for a test that tries every "first N characters" prefix.
///
/// Parsing every one-character prefix is O(n^2) on long, low-meaning strings such as
/// base64 data URIs. Normal characters return every position; inside long opaque
/// runs (a run of base64 characters longer than [_minOpaqueRun], and the payload from
/// `;base64,` to the delimiter), only start, start+1, middle, end-1 and end are returned.
library;

/// Base64 runs longer than this are considered opaque and thinned out.
const _minOpaqueRun = 64;

final _base64Run = RegExp('[A-Za-z0-9+/=]{${_minOpaqueRun + 1},}');
final _dataPayload = RegExp(r';base64,[^\s)"\x27>\]]*');

/// Returns the end positions of prefixes of [source] (0 to `source.length`) in ascending order.
Iterable<int> prefixEnds(String source) sync* {
  final runs = _opaqueRuns(source);
  var run = 0;
  var position = 0;
  while (position <= source.length) {
    while (run < runs.length && runs[run].end < position) {
      run++;
    }
    if (run < runs.length && runs[run].start <= position) {
      final (start, end) = (runs[run].start, runs[run].end);
      final samples = <int>{
        start,
        start + 1,
        (start + end) ~/ 2,
        end - 1,
        end,
      }.where((p) => p >= start && p <= end).toList()..sort();
      for (final p in samples) {
        if (p >= position) yield p;
      }
      position = end + 1;
    } else {
      yield position;
      position++;
    }
  }
}

/// Ranges of runs to thin out (character positions; end is an exclusive end). Overlaps are merged.
List<({int start, int end})> _opaqueRuns(String source) {
  final ranges = <({int start, int end})>[
    for (final m in _base64Run.allMatches(source)) (start: m.start, end: m.end),
    for (final m in _dataPayload.allMatches(source))
      (start: m.start + ';base64,'.length, end: m.end),
  ]..sort((a, b) => a.start.compareTo(b.start));
  final merged = <({int start, int end})>[];
  for (final range in ranges) {
    if (range.end - range.start <= 2) continue;
    if (merged.isNotEmpty && range.start <= merged.last.end) {
      final last = merged.removeLast();
      merged.add((
        start: last.start,
        end: range.end > last.end ? range.end : last.end,
      ));
    } else {
      merged.add(range);
    }
  }
  return merged;
}
