/// Tidies up the tail of a Markdown stream for display.
///
/// Markdown that is still being generated ends mid-construct. Parsing it as is
/// shows an unclosed `**` or `[text](ht` as raw symbols, which then turn into
/// emphasis or a link on the next token. Instead, only the unfinished syntax at
/// the tail is tidied up at the source level before parsing.
///
/// Only the last block of the last chunk (the last entry of `splitChunks`) is
/// tidied. The source of completed blocks is never touched, so the incremental
/// parse cache stays valid. Nothing is added to the backend parser, so Dart and
/// native produce the same result.
/// See doc/streaming.md for the full list of policies.
library;

import 'incremental_parser.dart';

/// Returns [source] with its unfinished tail tidied up.
///
/// A complete document is returned unchanged.
String markdownXRepairStreamingTail(String source) {
  final chunks = splitChunks(source);
  if (chunks.isEmpty) return source;
  final last = chunks.last;
  final repaired = repairStreamingChunk(last);
  if (identical(repaired, last) || repaired == last) return source;
  return source.substring(0, source.length - last.length) + repaired;
}

/// The opening line of a fence. Also matches fences inside quotes and lists.
final _fenceOpen = RegExp(
  r'^([ \t>]*(?:(?:[-*+]|\d{1,9}[.)])[ \t]+)*)(`{3,}(?=[^`]*$)|~{3,})',
);
final _quotePrefix = RegExp(r'^[\s>]+');
final _markerOnly = RegExp(r'^\s*(?:[-*+]|\d{1,9}[.)])\s*$');
final _headingOnly = RegExp(r'^\s{0,3}#{1,6}\s*$');
final _quoteOnly = RegExp(r'^\s*(?:>\s*)+$');
final _taskOnly = RegExp(r'^\s*(?:[-*+]|\d{1,9}[.)])\s+\[[ xX]?\]?\s*$');
final _definitionOnly = RegExp(
  r'^\s{0,3}(?:\[[^\]]*\]:|\[\^[^\]\s]*(?:\]:?)?)\s*$',
);
final _pipesOnly = RegExp(r'^[\s|]*\|[\s|]*$');
final _underlineOnly = RegExp(r'^\s{0,3}(?:-+|=+)\s*$');
final _listStart = RegExp(r'^\s*(?:[-*+]|\d{1,9}[.)])[ \t]+');
final _headingStart = RegExp(r'^\s{0,3}#{1,6}(?:[ \t]|$)');
final _thematic = RegExp(
  r'^\s{0,3}(?:(?:-\s*){3,}|(?:\*\s*){3,}|(?:_\s*){3,})$',
);
final _contentPrefix = RegExp(
  r'^(?:\s*>)*\s*(?:(?:[-*+]|\d{1,9}[.)])[ \t]+)*(?:\[[ xX]\][ \t]+)?'
  r'(?:#{1,6}[ \t]+)?',
);
final _delimiterLike = RegExp(r'^\s*\|?[\s:\-|]*$');
final _delimiterCell = RegExp(r'^:?-+:?$');
final _indentedCode = RegExp(r'^(?: {4}|\t)');
final _punctuation = RegExp(r'[\p{P}\p{S}]', unicode: true);
final _whitespaceRun = RegExp(
  r'[\s\u00A0\u1680\u2000-\u200A\u202F\u205F\u3000]',
  unicode: true,
);

/// A half-written alert marker (`> [!NO`) on the first line of a quote.
final _alertTail = RegExp(r'^\s{0,3}>[\s>]*(\[[!A-Za-z\]]*)[ \t]*$');
const _alertMarkers = [
  '[!note]',
  '[!tip]',
  '[!important]',
  '[!warning]',
  '[!caution]',
];

/// A half-written citation (`[1`, `[1, 2`, or `【1†sou`).
final _citationTail = RegExp(r'(?<!\\)(?:\[\d[\d\s,]*|【[^】]*)$');

bool _isBlankLine(String line) => line.trim().isEmpty;

/// Tidies up the last chunk. Returns [chunk] as is if nothing changes.
String repairStreamingChunk(String chunk) {
  if (chunk.isEmpty) return chunk;
  final lines = chunk.split('\n');
  final lastIndex = lines.length - 1;

  // Find the fence state and the start of the last block in a single scan.
  String? fence;
  var fenceLine = -1;
  var region = 0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (fence != null) {
      final t = line.replaceFirst(_quotePrefix, '').trim();
      if (t.startsWith(fence) && t.replaceAll(fence[0], '').isEmpty) {
        fence = null;
        region = i + 1;
      }
    } else if (i < lastIndex && _isBlankLine(line)) {
      // The last element is text still being written after a newline, so it is
      // not a blank line even when empty.
      region = i + 1;
    } else if (_isBlankLine(line)) {
      // The last line has no content yet.
    } else {
      final open = _fenceOpen.firstMatch(line);
      if (open != null) {
        fence = open[2];
        fenceLine = i;
      } else if (i < lastIndex &&
          (_headingStart.hasMatch(line) || _thematic.hasMatch(line))) {
        region = i + 1;
      }
    }
  }

  if (fence != null) return _repairFence(lines, fence, fenceLine);

  // An indented code block (4+ spaces) is shown as is.
  if (region <= lastIndex && _indentedCode.hasMatch(lines[region])) {
    final firstContent = lines.firstWhere(
      (l) => !_isBlankLine(l),
      orElse: () => '',
    );
    if (!_listStart.hasMatch(firstContent)) return chunk;
  }

  var changed = false;

  // Hide a line that consists only of a half-written line-start marker.
  final tail = lines[lastIndex];
  if (tail.isNotEmpty && _isPendingMarkerLine(tail, lines, lastIndex, region)) {
    lines[lastIndex] = '';
    changed = true;
  }

  // The last line with content.
  var k = lines.length - 1;
  while (k >= region && _isBlankLine(lines[k])) {
    k--;
  }
  if (k < region) return changed ? _join(lines, lines.length) : chunk;

  final tableMode = _isTableRegion(lines, region, k);
  if (tableMode) {
    changed = _repairTable(lines, region, k) || changed;
    return changed ? _join(lines, lines.length) : chunk;
  }

  // Find the first line of the last block.
  var u = k;
  while (u > region &&
      !_listStart.hasMatch(lines[u]) &&
      !_headingStart.hasMatch(lines[u])) {
    u--;
  }
  final prefix = _contentPrefix.firstMatch(lines[u])![0]!;
  final unit = StringBuffer(lines[u].substring(prefix.length));
  for (var i = u + 1; i <= k; i++) {
    unit
      ..write('\n')
      ..write(lines[i]);
  }
  final original = unit.toString();
  final repaired = repairInline(original);
  if (repaired != original) {
    // If no content remains, hide the line-start marker as well.
    final hidden = repaired.trim().isEmpty;
    final text = '$prefix$repaired';
    // If stripping the trailing marker turns the line into a new fence opening,
    // do nothing.
    if (!hidden &&
        _fenceOpen.hasMatch(text.split('\n').first) &&
        !_fenceOpen.hasMatch(lines[u])) {
      return chunk;
    }
    final out = [
      ...lines.sublist(0, u),
      if (hidden && u > 0) '' else if (!hidden) text,
    ];
    return _hidePendingTail(out.join('\n'), region);
  }
  return changed ? _join(lines, lines.length) : chunk;
}

/// Also hides the last line of the tidied result if it consists only of a
/// half-written marker.
String _hidePendingTail(String text, int region) {
  final lines = text.split('\n');
  final lastIndex = lines.length - 1;
  final tail = lines[lastIndex];
  if (tail.isNotEmpty && _isPendingMarkerLine(tail, lines, lastIndex, region)) {
    lines[lastIndex] = '';
    return lines.join('\n');
  }
  return text;
}

String _join(List<String> lines, int length) => lines.take(length).join('\n');

/// Whether the last line is only a half-written marker.
bool _isPendingMarkerLine(
  String tail,
  List<String> lines,
  int lastIndex,
  int region,
) {
  if (_markerOnly.hasMatch(tail) ||
      _headingOnly.hasMatch(tail) ||
      _quoteOnly.hasMatch(tail) ||
      _taskOnly.hasMatch(tail) ||
      _definitionOnly.hasMatch(tail) ||
      _pipesOnly.hasMatch(tail)) {
    return true;
  }
  // An underline right after a paragraph would turn it into a setext heading.
  // After a blank line or a heading it is a thematic break or a paragraph, so
  // leave it unchanged.
  if (_isPendingAlertMarker(tail, lines, lastIndex)) return true;
  if (_underlineOnly.hasMatch(tail) && lastIndex - 1 >= region) {
    final previous = lines[lastIndex - 1];
    return !_isBlankLine(previous) &&
        !_headingStart.hasMatch(previous) &&
        !_thematic.hasMatch(previous);
  }
  return false;
}

/// Whether the first line of a quote is a partial alert marker. A complete
/// marker is hidden too, because text may follow on the same line until the line
/// is terminated by a newline. Second and later lines of a quote are ignored.
bool _isPendingAlertMarker(String tail, List<String> lines, int lastIndex) {
  final match = _alertTail.firstMatch(tail);
  if (match == null) return false;
  if (lastIndex > 0 && lines[lastIndex - 1].trimLeft().startsWith('>')) {
    return false;
  }
  final marker = match[1]!.toLowerCase();
  return _alertMarkers.any((m) => m.startsWith(marker));
}

String _repairFence(List<String> lines, String fence, int fenceLine) {
  final lastIndex = lines.length - 1;
  final tail = lines[lastIndex];
  if (fenceLine == lastIndex) {
    // Do not show the language name on the opening line until a newline
    // arrives (otherwise the language changes one character at a time).
    final open = _fenceOpen.firstMatch(tail)!;
    final bare = '${open[1]}${open[2]}';
    if (bare == tail) return lines.join('\n');
    lines[lastIndex] = bare;
    return lines.join('\n');
  }
  // A half-written closing fence (shorter than the opening one) is not shown
  // as code content.
  final t = tail.replaceFirst(_quotePrefix, '').trim();
  if (t.isNotEmpty &&
      t.length < fence.length &&
      t.replaceAll(fence[0], '').isEmpty &&
      tail.length - tail.trimLeft().length <= 3) {
    lines[lastIndex] = '';
  }
  // Trailing blank lines are not shown as code content (backends handle the
  // trailing newline differently, so the height would jitter as lines are
  // added). The opening line keeps its newline.
  while (lines.length - 1 > fenceLine && _isBlankLine(lines.last)) {
    lines.removeLast();
  }
  if (lines.length - 1 == fenceLine) lines.add('');
  return lines.join('\n');
}

// ---------------------------------------------------------------------------
// table
// ---------------------------------------------------------------------------

bool _startsWithPipe(String line) {
  final t = line.trimLeft();
  return t.startsWith('|') && line.length - t.length < 4;
}

/// Extracts the cells from a pipe row. `\|` is not a separator.
List<String> _cells(String line) {
  var t = line.trim();
  if (t.startsWith('|')) t = t.substring(1);
  if (t.endsWith('|') && !t.endsWith(r'\|')) t = t.substring(0, t.length - 1);
  final cells = <String>[];
  final cell = StringBuffer();
  for (var i = 0; i < t.length; i++) {
    final c = t[i];
    if (c == r'\' && i + 1 < t.length) {
      cell
        ..write(c)
        ..write(t[++i]);
    } else if (c == '|') {
      cells.add(cell.toString().trim());
      cell.clear();
    } else {
      cell.write(c);
    }
  }
  cells.add(cell.toString().trim());
  return cells;
}

bool _hasUnescapedPipe(String line) {
  for (var i = 0; i < line.length; i++) {
    if (line[i] == r'\') {
      i++;
    } else if (line[i] == '|') {
      return true;
    }
  }
  return false;
}

bool _isValidDelimiterRow(String line) {
  if (!_hasUnescapedPipe(line) && !line.contains('-')) return false;
  final cells = _cells(line);
  return cells.isNotEmpty && cells.every(_delimiterCell.hasMatch);
}

bool _isTableRegion(List<String> lines, int region, int k) {
  final first = lines[region];
  if (_startsWithPipe(first)) return true;
  return k > region &&
      _hasUnescapedPipe(first) &&
      _isValidDelimiterRow(lines[region + 1]) &&
      lines[region + 1].contains('-');
}

String _delimiterRow(List<String> existing, int columns) {
  final out = <String>[];
  for (var i = 0; i < columns; i++) {
    final cell = i < existing.length ? existing[i] : '';
    final left = cell.startsWith(':');
    final right = cell.length > 1 && cell.endsWith(':');
    out.add('${left ? ':' : ''}---${right ? ':' : ''}');
  }
  return '| ${out.join(' | ')} |';
}

/// Tidies up a partial table. Returns true if anything changed.
///
/// `region..k` of [lines] is the table candidate. Only blank lines follow the
/// last row.
bool _repairTable(List<String> lines, int region, int k) {
  final first = lines[region];
  final columns = _cells(first).length;
  var changed = false;

  if (k == region) {
    // Header only. Add a delimiter row so it is shown as an empty table.
    final fixed = _repairLastCell(first);
    lines.length = region;
    // A header with no content cannot be treated as a table (backends disagree
    // on the result).
    if (_cells(fixed).any((cell) => cell.isNotEmpty)) {
      lines
        ..add(fixed)
        ..add(_delimiterRow(const [], _cells(fixed).length));
    }
    return true;
  }

  if (k == region + 1) {
    final second = lines[k];
    final isTail = k == lines.length - 1;
    if (isTail && _delimiterLike.hasMatch(second) && _hasUnescapedPipe(first)) {
      final cells = _cells(second);
      final complete =
          cells.length >= columns && cells.every(_delimiterCell.hasMatch);
      if (!complete) {
        lines
          ..length = k
          ..add(_delimiterRow(cells, columns));
        return true;
      }
      return false;
    }
  }

  // For body rows, only the last cell gets its inline syntax tidied.
  final row = lines[k];
  if (k > region + 1 || !_isValidDelimiterRow(row)) {
    final fixed = _repairLastCell(row);
    if (fixed != row) {
      lines[k] = fixed;
      changed = true;
    }
  }
  return changed;
}

String _repairLastCell(String line) {
  final trimmed = line.trimRight();
  if (trimmed.endsWith('|') && !trimmed.endsWith(r'\|')) return line;
  var p = -1;
  for (var i = 0; i < line.length; i++) {
    if (line[i] == r'\') {
      i++;
    } else if (line[i] == '|') {
      p = i;
    }
  }
  if (p < 0) return line;
  final cell = line.substring(p + 1);
  final fixed = repairInline(cell);
  return fixed == cell ? line : line.substring(0, p + 1) + fixed;
}

// ---------------------------------------------------------------------------
// inline
// ---------------------------------------------------------------------------

class _Delimiter {
  _Delimiter(this.char, this.length, this.position, {required this.both})
    : originalLength = length;

  final int char;
  int length;
  final int originalLength;
  final int position;

  /// Whether this run could be both an opener and a closer (used for the rule
  /// of 3).
  final bool both;
}

const _backslash = 0x5C;
const _backtick = 0x60;
const _lessThan = 0x3C;
const _openBracket = 0x5B;
const _closeBracket = 0x5D;
const _openParen = 0x28;
const _closeParen = 0x29;
const _asterisk = 0x2A;
const _underscore = 0x5F;
const _tilde = 0x7E;
const _bang = 0x21;
const _caret = 0x5E;

bool _isAsciiLetter(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

String _charAt(String s, int index) {
  final unit = s.codeUnitAt(index);
  if (unit >= 0xD800 && unit <= 0xDBFF && index + 1 < s.length) {
    return s.substring(index, index + 2);
  }
  return s[index];
}

String _charBefore(String s, int index) {
  final unit = s.codeUnitAt(index - 1);
  if (unit >= 0xDC00 && unit <= 0xDFFF && index >= 2) {
    return s.substring(index - 2, index);
  }
  return s[index - 1];
}

/// Whether the character is whitespace (out of range counts as whitespace).
bool _ws(String? ch) => ch == null || _whitespaceRun.hasMatch(ch);

bool _punct(String? ch) => ch != null && _punctuation.hasMatch(ch);

/// Tidies up unfinished inline syntax. Returns [text] as is if nothing changes.
///
/// Trailing whitespace is stripped before scanning so that unfinished markers
/// such as `**` are still found when whitespace follows them.
String repairInline(String text) {
  final t = text.trimRight();
  if (t.isEmpty) return text;
  // Hide a half-written citation until it is complete and becomes a chip.
  final citation = _citationTail.firstMatch(t);
  if (citation != null) {
    final head = t.substring(0, citation.start);
    return head.trim().isEmpty ? '' : repairInline(head);
  }
  final n = t.length;

  final stack = <_Delimiter>[];
  final brackets = <({int position, bool image})>[];
  final removed = <int>{};
  var cut = n;
  ({int position, int length})? danglingCode;

  var i = 0;
  scan:
  while (i < n) {
    final c = t.codeUnitAt(i);
    switch (c) {
      case _backslash:
        if (i + 1 >= n) {
          cut = i;
          break scan;
        }
        i += 2;
      case _backtick:
        var j = i;
        while (j < n && t.codeUnitAt(j) == _backtick) {
          j++;
        }
        final length = j - i;
        final close = _findBacktickRun(t, j, length);
        if (close != null) {
          i = close;
        } else if (_hasBacktick(t, j)) {
          i = j;
        } else {
          danglingCode = (position: i, length: length);
          break scan;
        }
      case _lessThan:
        if (i + 1 >= n) {
          cut = i;
          break scan;
        }
        if (i + 1 < n) {
          final next = t.codeUnitAt(i + 1);
          if (_isAsciiLetter(next) || next == 0x2F || next == _bang) {
            final end = t.indexOf('>', i + 1);
            if (end == -1) {
              cut = i;
              break scan;
            }
            i = end + 1;
            continue;
          }
        }
        i++;
      case _openBracket:
        brackets.add((
          position: i,
          image: i > 0 && t.codeUnitAt(i - 1) == _bang,
        ));
        i++;
      case _closeBracket:
        if (brackets.isEmpty) {
          i++;
          break;
        }
        final opener = brackets.removeLast();
        if (i + 1 < n && t.codeUnitAt(i + 1) == _openParen) {
          final end = _findDestinationEnd(t, i + 2);
          if (end == null) {
            // The destination is unfinished. Hide only the text for a link,
            // and the whole thing for an image.
            if (opener.image) {
              cut = opener.position - 1;
            } else {
              removed.add(opener.position);
              cut = i;
            }
            break scan;
          }
          i = end + 1;
        } else {
          // If it ends with `![alt]`, a `(` may still follow.
          if (opener.image && i + 1 >= n) {
            cut = opener.position - 1;
            break scan;
          }
          i++;
        }
      case _asterisk || _underscore || _tilde:
        var j = i;
        while (j < n && t.codeUnitAt(j) == c) {
          j++;
        }
        final length = j - i;
        if (c == _tilde && length > 2) {
          i = j;
          break;
        }
        final before = i == 0 ? null : _charBefore(t, i);
        final after = j >= n ? null : _charAt(t, j);
        final leftFlanking =
            !_ws(after) && (!_punct(after) || _ws(before) || _punct(before));
        final rightFlanking =
            !_ws(before) && (!_punct(before) || _ws(after) || _punct(after));
        final canOpen = c == _underscore
            ? leftFlanking && (!rightFlanking || _punct(before))
            : leftFlanking;
        final canClose = c == _underscore
            ? rightFlanking && (!leftFlanking || _punct(after))
            : rightFlanking;
        final both = canOpen && canClose;
        var remaining = length;
        if (canClose) {
          for (var s = stack.length - 1; s >= 0; s--) {
            final entry = stack[s];
            if (entry.char != c) continue;
            if (c == _tilde && entry.length != length) continue;
            if ((both || entry.both) &&
                (entry.originalLength + length) % 3 == 0 &&
                !(entry.originalLength % 3 == 0 && length % 3 == 0)) {
              continue;
            }
            stack.removeRange(s + 1, stack.length);
            while (remaining > 0 && stack.isNotEmpty && stack.last.char == c) {
              final take = remaining < stack.last.length
                  ? remaining
                  : stack.last.length;
              stack.last.length -= take;
              remaining -= take;
              if (stack.last.length == 0) stack.removeLast();
              if (c == _tilde) break;
            }
            break;
          }
        }
        if (remaining > 0 && canOpen && j < n) {
          stack.add(_Delimiter(c, remaining, i, both: both));
        } else if (remaining > 0 && j >= n) {
          // An unclosable marker at the end is treated as an opener with no
          // content yet, and is hidden.
          cut = i + (length - remaining);
          break scan;
        }
        i = j;
      default:
        i++;
    }
  }

  // Unclosed `[`. Hide image and footnote references; for a link, drop only
  // the brackets.
  for (final bracket in brackets) {
    if (bracket.position >= cut) continue;
    if (bracket.image) {
      cut = bracket.position - 1;
    } else if (bracket.position + 1 < cut &&
        t.codeUnitAt(bracket.position + 1) == _caret &&
        !_hasWhitespace(t, bracket.position, cut)) {
      cut = bracket.position;
    } else {
      removed.add(bracket.position);
    }
  }
  stack.removeWhere((d) => d.position >= cut);
  if (danglingCode != null && danglingCode.position >= cut) {
    danglingCode = null;
  }

  // An opener with no content is hidden instead of being closed.
  while (stack.isNotEmpty) {
    final last = stack.last;
    final from = last.position + last.originalLength;
    if (danglingCode != null || _hasContent(t, from, cut, removed)) break;
    for (var p = last.position; p < from; p++) {
      removed.add(p);
    }
    stack.removeLast();
  }

  final body = StringBuffer();
  for (var p = 0; p < cut; p++) {
    if (!removed.contains(p)) body.write(t[p]);
  }
  var out = body.toString();

  if (danglingCode != null) {
    final code = danglingCode;
    final content = t.substring(code.position + code.length, cut);
    if (content.trim().isEmpty) {
      out = out.substring(0, out.length - content.length - code.length);
    } else {
      out = out.trimRight() + '`' * code.length;
    }
  }
  if (stack.isNotEmpty) {
    final closers = StringBuffer();
    for (final entry in stack.reversed) {
      closers.write(String.fromCharCode(entry.char) * entry.length);
    }
    out = out.trimRight() + closers.toString();
  }
  return out == t ? text : out;
}

bool _hasWhitespace(String s, int from, int to) {
  for (var i = from; i < to; i++) {
    if (_whitespaceRun.hasMatch(s[i])) return true;
  }
  return false;
}

bool _hasContent(String s, int from, int to, Set<int> removed) {
  for (var i = from; i < to; i++) {
    if (removed.contains(i)) continue;
    if (!_whitespaceRun.hasMatch(s[i])) return true;
  }
  return false;
}

bool _hasBacktick(String s, int from) => s.indexOf('`', from) != -1;

/// The position right after the next run of exactly [length] backticks at or
/// after [from].
int? _findBacktickRun(String s, int from, int length) {
  var i = from;
  while (i < s.length) {
    if (s.codeUnitAt(i) != _backtick) {
      i++;
      continue;
    }
    var j = i;
    while (j < s.length && s.codeUnitAt(j) == _backtick) {
      j++;
    }
    if (j - i == length) return j;
    i = j;
  }
  return null;
}

/// The position of the `)` that closes a link destination (scanning from just
/// after the `(`). Null if it is not closed.
int? _findDestinationEnd(String s, int from) {
  var depth = 1;
  for (var i = from; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c == _backslash) {
      i++;
    } else if (c == _openParen) {
      depth++;
    } else if (c == _closeParen && --depth == 0) {
      return i;
    }
  }
  return null;
}
