/// Source-stage processing of math (independent of Flutter).
///
/// CommonMark interprets the TeX of math as ordinary Markdown first.
/// `\\` becomes `\`, `\{` becomes `{`, `\(` becomes `(`, `_` and `*` become emphasis, `|` becomes a
/// table delimiter, and a newline becomes a space. These cannot be restored from the IR after parsing,
/// so math is found before parsing, and its content is made safe and escaped into a code span.
/// The escaped code span is turned back into a math inline by the IR transform (`math_ir.dart`).
///
/// Escaping is a transform on the source string, so the same source goes to both the Dart and native
/// backends and yields the same IR.
library;

/// The marker (one private-use character) placed at the start of the content of an escaped code span.
const mathMarker = '';

/// The kind of escape. `m` is closed math, `p` is unclosed math during streaming.
const mathKindComplete = 'm';

/// The mark for unclosed math (unfinished text during streaming).
const mathKindPending = 'p';

/// Returns the source with the math in [source] escaped into code spans.
///
/// Not converted: fenced and indented code blocks, inline code, link destinations,
/// autolinks, URLs, inline HTML, reference definitions, and escaped `\$`.
///
/// To tell it apart from currency (`$5 and $10`), `$...$` follows pandoc's rules. It is math only when the
/// character right after the opening `$` is not whitespace, the character right before the closing `$` is not whitespace, and the character right after the closing one is not a digit.
/// Only the first `$` that appears is a closing candidate; if the conditions are not met, the opening `$` is
/// left as a literal character. `$$...$$`, `\(...\)` and `\[...\]` are not subject to this rule.
///
/// Math does not cross a blank line. Converting chunk by chunk split at blank lines gives
/// the same result as converting the whole text.
///
/// When [streaming] is true, `$$`, `\(` and `\[` that remain unclosed to the end of the source are
/// escaped as unfinished math (`p`). A single `$` cannot be told from currency, so it stays a literal character.
/// Re-applying to an already converted source is not supported (the parser does not apply it twice).
String protectMath(
  String source, {
  bool streaming = false,
  bool dollar = true,
  bool bracket = true,
}) {
  if (!source.contains(r'$') && !(bracket && source.contains(r'\'))) {
    return source;
  }
  return _Scanner(source, streaming, dollar, bracket).run();
}

/// Turns [raw] (the math source with delimiters) into a string to put in a code span.
///
/// Only the characters that break a code span (backtick, newline), the table delimiter `|`, and the escape `%` are turned
/// into `%XX`. Other characters (`\`, `<`, `&`, Japanese) are not interpreted inside a code span.
String encodeMathPayload(String raw) => raw
    .replaceAll('%', '%25')
    .replaceAll('`', '%60')
    .replaceAll('|', '%7C')
    .replaceAll('\n', '%0A')
    .replaceAll('\r', '%0D');

final _spanWithMarker = RegExp('(`+)$mathMarker[mp]([^`]*)\\1(?!`)');

/// Restores escaped code spans in text to the original math characters.
///
/// A safety net for when an escape remains in a region found not to be math (such as a code block).
String restoreMathMarkers(String text) {
  if (!text.contains(mathMarker)) return text;
  return text.replaceAllMapped(
    _spanWithMarker,
    (m) => decodeMathPayload(m[2]!),
  );
}

final _payloadEscape = RegExp('%(25|60|7C|0A|0D)');

/// The inverse of [encodeMathPayload].
String decodeMathPayload(String payload) =>
    payload.replaceAllMapped(_payloadEscape, (m) {
      return switch (m[1]) {
        '25' => '%',
        '60' => '`',
        '7C' => '|',
        '0A' => '\n',
        _ => '\r',
      };
    });

final _fenceOpen = RegExp(
  r'^[ \t>]*(?:(?:[-*+]|\d{1,9}[.)])[ \t]+)*(`{3,}(?=[^`]*$)|~{3,})',
);
final _quotePrefix = RegExp(r'^[\s>]+');
final _listMarker = RegExp(r'^\s*(?:[-*+]|\d{1,9}[.)])(?:[ \t]|$)');
final _definition = RegExp(r'^ {0,3}\[(?!\^)[^\]]+\]:');
final _quoteMarkers = RegExp(r'^[ \t]*(?:>[ \t]?)*');
final _backtickRun = RegExp('`+');
final _quoteContinuation = RegExp(r'\n[ \t]*(?:>[ \t]?)+');

bool _isSpace(int c) =>
    c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x3000;

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

bool _isAlnum(int c) =>
    _isDigit(c) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

class _Scanner {
  _Scanner(this.s, this.streaming, this.dollar, this.bracket)
    : length = s.length;

  final String s;
  final int length;
  final bool streaming;
  final bool dollar;
  final bool bracket;

  final _out = StringBuffer();
  var _copied = 0;

  /// The number of backticks of the escaped code span. Choose a length that does not
  /// coincide with the length of any backtick run in the source (runs of the same length pair up as a code span's open and close,
  /// so an unclosed backtick must not pair with the delimiter of an escaped span).
  late final int _fence = _freeFenceLength();

  int _freeFenceLength() {
    final used = <int>{
      for (final m in _backtickRun.allMatches(s)) m[0]!.length,
    };
    var n = 1;
    while (used.contains(n)) {
      n++;
    }
    return n;
  }

  /// The start position of each line, and whether it is excluded from conversion.
  final _starts = <int>[];
  final _protected = <bool>[];

  String run() {
    _classifyLines();
    var i = 0;
    var line = 0;
    while (i < length) {
      while (line + 1 < _starts.length && _starts[line + 1] <= i) {
        line++;
      }
      if (_protected[line] && i == _starts[line]) {
        final next = s.indexOf('\n', i);
        if (next == -1) break;
        i = next + 1;
        continue;
      }
      i = _step(i);
    }
    if (_copied == 0) return s;
    _out.write(s.substring(_copied));
    return _out.toString();
  }

  void _classifyLines() {
    String? fence;
    var prevBlank = true;
    var inList = false;
    var start = 0;
    while (start <= length) {
      var end = s.indexOf('\n', start);
      if (end == -1) end = length;
      final line = s.substring(start, end);
      _starts.add(start);
      var isProtected = false;
      if (fence != null) {
        isProtected = true;
        final t = line.replaceFirst(_quotePrefix, '').trim();
        if (t.startsWith(fence) && t.replaceAll(fence[0], '').isEmpty) {
          fence = null;
        }
      } else if (line.trim().isEmpty) {
        prevBlank = true;
      } else {
        final open = _fenceOpen.firstMatch(line);
        if (open != null) {
          fence = open[1];
          isProtected = true;
        } else if (prevBlank && _isIndentedCode(line, inList)) {
          isProtected = true;
        } else if (_definition.hasMatch(line)) {
          isProtected = true;
        }
        if (_listMarker.hasMatch(line)) {
          inList = true;
        } else if (!line.startsWith(' ') && !line.startsWith('\t')) {
          inList = false;
        }
        prevBlank = false;
      }
      _protected.add(isProtected);
      start = end + 1;
    }
  }

  /// Whether this is a line of an indented code block after a blank line.
  ///
  /// Counted on what remains after removing the quote's `>`. Inside a list, content indented deeper by
  /// the item's body offset is treated as code (an approximation; even if wrong, `restoreMathMarkers` restores
  /// escapes inside a code block to the original characters).
  bool _isIndentedCode(String line, bool inList) {
    final content = line.substring(_quoteMarkers.firstMatch(line)![0]!.length);
    var width = 0;
    for (var k = 0; k < content.length; k++) {
      final c = content.codeUnitAt(k);
      if (c == 0x20) {
        width++;
      } else if (c == 0x09) {
        width += 4 - width % 4;
      } else {
        break;
      }
    }
    // Inside a list, the threshold is 4 plus the position of the item body (about 2).
    return width >= (inList ? 6 : 4);
  }

  /// Advances position [i] by one step. Returns the position after advancing.
  int _step(int i) {
    final c = s.codeUnitAt(i);
    switch (c) {
      case 0x5C: // backslash
        if (bracket && i + 1 < length) {
          final n = s.codeUnitAt(i + 1);
          if (n == 0x28 || n == 0x5B) return _bracketMath(i, n == 0x5B);
        }
        return i + 2;
      case 0x60: // backtick
        return _skipCodeSpan(i);
      case 0x3C: // <
        return _skipTag(i);
      case 0x21: // !
        // The alt of an image is not interpreted as inline; only its text is extracted.
        if (i + 1 < length && s.codeUnitAt(i + 1) == 0x5B) {
          return _skipBracket(i + 1);
        }
        return i + 1;
      case 0x5D: // ]
        if (i + 1 < length && s.codeUnitAt(i + 1) == 0x28) {
          return _skipDestination(i + 1);
        }
        return i + 1;
      case 0x68 || 0x77: // h, w
        return _skipUrl(i);
      case 0x24: // $
        return dollar ? _dollarMath(i) : i + 1;
      default:
        return i + 1;
    }
  }

  int _skipCodeSpan(int i) {
    var n = 1;
    while (i + n < length && s.codeUnitAt(i + n) == 0x60) {
      n++;
    }
    var j = i + n;
    while (j < length) {
      if (s.codeUnitAt(j) == 0x0A && _blankLineAfter(j)) break;
      if (s.codeUnitAt(j) == 0x60) {
        var m = 1;
        while (j + m < length && s.codeUnitAt(j + m) == 0x60) {
          m++;
        }
        if (m == n) return j + m;
        j += m;
      } else {
        j++;
      }
    }
    return i + n;
  }

  int _skipTag(int i) {
    if (i + 1 >= length) return i + 1;
    final n = s.codeUnitAt(i + 1);
    final opens = _isAlnum(n) && !_isDigit(n) || n == 0x2F || n == 0x21;
    if (!opens) return i + 1;
    final eol = _lineEnd(i);
    final close = s.indexOf('>', i + 1);
    return close != -1 && close < eol ? close + 1 : i + 1;
  }

  /// The position after the `]` matching the `[` at [open]. If not found, the position after [open].
  int _skipBracket(int open) {
    var depth = 0;
    for (var j = open; j < length; j++) {
      final c = s.codeUnitAt(j);
      if (c == 0x5C) {
        j++;
      } else if (c == 0x5B) {
        depth++;
      } else if (c == 0x5D) {
        depth--;
        if (depth == 0) return j + 1;
      } else if (c == 0x0A && _blankLineAfter(j)) {
        break;
      }
    }
    return open + 1;
  }

  int _skipDestination(int open) {
    final eol = _lineEnd(open);
    var depth = 0;
    for (var j = open; j < eol; j++) {
      final c = s.codeUnitAt(j);
      if (c == 0x5C) {
        j++;
      } else if (c == 0x28) {
        depth++;
      } else if (c == 0x29) {
        depth--;
        if (depth == 0) return j + 1;
      }
    }
    return open;
  }

  int _skipUrl(int i) {
    final isUrl =
        s.startsWith('http://', i) ||
        s.startsWith('https://', i) ||
        s.startsWith('www.', i);
    if (!isUrl || (i > 0 && _isAlnum(s.codeUnitAt(i - 1)))) return i + 1;
    var j = i;
    while (j < length &&
        !_isSpace(s.codeUnitAt(j)) &&
        s.codeUnitAt(j) != 0x3C) {
      j++;
    }
    return j;
  }

  int _lineEnd(int i) {
    final e = s.indexOf('\n', i);
    return e == -1 ? length : e;
  }

  /// Whether the line after [nl] (the position of a newline) is blank.
  bool _blankLineAfter(int nl) {
    final next = s.indexOf('\n', nl + 1);
    if (next == -1) return false;
    for (var k = nl + 1; k < next; k++) {
      if (!_isSpace(s.codeUnitAt(k))) return false;
    }
    return true;
  }

  /// The position of the unescaped [delimiter] at or after [from].
  /// -1 if a blank line is hit, -2 if not found by the end.
  int _find(int from, String delimiter, {required bool single}) {
    final d0 = delimiter.codeUnitAt(0);
    for (var j = from; j < length; j++) {
      final c = s.codeUnitAt(j);
      if (c == 0x5C) {
        if (delimiter.codeUnitAt(0) == 0x5C &&
            j + 1 < length &&
            s.codeUnitAt(j + 1) == delimiter.codeUnitAt(1)) {
          return j;
        }
        j++;
      } else if (c == 0x0A) {
        if (_blankLineAfter(j)) return -1;
      } else if (c == d0) {
        if (single || s.startsWith(delimiter, j)) return j;
      }
    }
    return -2;
  }

  int _dollarMath(int i) {
    if (i + 1 < length && s.codeUnitAt(i + 1) == 0x24) {
      return _display(i, r'$$', r'$$', 2);
    }
    if (i + 1 >= length || _isSpace(s.codeUnitAt(i + 1))) return i + 1;
    final close = _find(i + 1, r'$', single: true);
    if (close < 0) return i + 1;
    final before = s.codeUnitAt(close - 1);
    final afterIsDigit =
        close + 1 < length && _isDigit(s.codeUnitAt(close + 1));
    if (_isSpace(before) || afterIsDigit) return i + 1;
    return _emit(i, close + 1) ?? i + 1;
  }

  int _bracketMath(int i, bool display) {
    if (display) return _display(i, r'\[', r'\]', 2);
    final close = _find(i + 2, r'\)', single: false);
    if (close >= 0) {
      if (s.substring(i + 2, close).trim().isEmpty) return i + 2;
      return _emit(i, close + 2) ?? i + 2;
    }
    if (close == -2 && streaming) return _emitPending(i);
    return i + 2;
  }

  /// `$$...$$` and `\[...\]`.
  int _display(int i, String open, String close, int openLength) {
    final end = _find(i + openLength, close, single: false);
    if (end >= 0) {
      if (s.substring(i + openLength, end).trim().isEmpty) {
        return i + openLength;
      }
      return _emit(i, end + close.length) ?? i + openLength;
    }
    if (end == -2 && streaming) return _emitPending(i);
    return i + openLength;
  }

  /// Escapes [start, end) as math. Returns null, without escaping, when adjacent to a backtick
  /// (it would mix with the code span delimiters).
  int? _emit(int start, int end) {
    // If escaped spans are adjacent, their backticks run together and are read as one code span.
    if ((start > 0 && s.codeUnitAt(start - 1) == 0x60) ||
        (end < length && s.codeUnitAt(end) == 0x60) ||
        (start > 0 && _copied == start)) {
      return null;
    }
    _write(start, end, mathKindComplete);
    return end;
  }

  int _emitPending(int start) {
    var end = length;
    while (end > start && _isSpace(s.codeUnitAt(end - 1))) {
      end--;
    }
    if (start > 0 && (s.codeUnitAt(start - 1) == 0x60 || _copied == start)) {
      return start + 2;
    }
    _write(start, end, mathKindPending);
    return end;
  }

  void _write(int start, int end, String kind) {
    var raw = s.substring(start, end);
    if (raw.contains('\n')) {
      // Math inside a quote has the `>` of the continuation lines removed.
      final lineStart = start == 0 ? 0 : s.lastIndexOf('\n', start - 1) + 1;
      if (s.substring(lineStart, start).contains('>')) {
        raw = raw.replaceAll(_quoteContinuation, '\n');
      }
    }
    final fence = '`' * _fence;
    _out
      ..write(s.substring(_copied, start))
      ..write('$fence$mathMarker$kind${encodeMathPayload(raw)}$fence');
    _copied = end;
  }
}
