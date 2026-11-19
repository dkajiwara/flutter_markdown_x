/// Re-parses only the parts that changed.
///
/// For long documents, Markdown parsing accounts for most of the update cost. The
/// document is split into chunks that "give the same result when parsed on their
/// own", and the result of each chunk is cached, so a streaming append parses
/// only the last chunk.
library;

import 'package:flutter/foundation.dart' show internal;

import 'backend.dart' as selected;
import '../extensions/extension.dart';
import '../ir/nodes.dart';
import '../ir/task.dart';
import '../ir/task_markers.dart';
import 'streaming.dart';

const _space = 0x20;
const _tab = 0x09;
const _lessThan = 0x3C;
const _openBracket = 0x5B;
const _carriageReturn = 0x0D;

/// The start line of a fence. The indent depth is not checked, so fences inside lists are caught too.
/// For a backtick fence, backticks following on the same line make it inline code.
final _fenceOpenPattern = RegExp(r'^[ \t]*(`{3,}(?=[^`]*$)|~{3,})');

/// The start line of a list item. It might connect to the previous list, so it is not split.
final _listMarkerPattern = RegExp(r'^(?:[-*+]|\d{1,9}[.)])(?:[ \t]|$)');

/// The start and end of HTML that continues across blank lines.
const _htmlTags =
    r'details|table|div|center|p|pre|script|style|textarea|blockquote|ul|ol|li|h[1-6]';
const _htmlOpenPattern = r'<(' + _htmlTags + r')\b|<!--';
const _htmlClosePattern = r'</(' + _htmlTags + r')\s*>|-->';
final _htmlBoundaryPattern = RegExp(
  '$_htmlOpenPattern|$_htmlClosePattern',
  caseSensitive: false,
);

/// A line that starts an HTML block for one of the tags above (CommonMark HTML
/// block types 1, 2 and 6, which can also interrupt a paragraph).
///
/// The block parser only sees a closing tag inside an HTML block; one in a
/// Markdown paragraph or in inline code is text to it.
final _htmlBlockStartPattern = RegExp(
  r'^ {0,3}(?:</?(?:' + _htmlTags + r')(?:[\s/>]|$)|<!--)',
  caseSensitive: false,
);

/// The key of an open comment in [_ScanState.htmlOpen].
const _commentKey = '!--';

/// A line that might be a reference link or footnote definition. Ones inside quotes and lists are caught too.
final _maybeDefinitionPattern = RegExp(
  r'^[ \t>]*(?:(?:[-*+]|\d{1,9}[.)])[ \t]+)?\[[^\]\n]+\]:',
);

/// A reference link definition that is complete on a single line.
///
/// Footnotes (`[^1]:`) are not included here, because their numbers and the trailing list are decided by the whole document.
final _simpleDefinitionPattern = RegExp(
  // A safe label has no nested opening bracket and every closing bracket is
  // unescaped. CommonMark permits more complex labels, but those need the
  // full parser's label normalization and cannot be safely copied per chunk.
  r'^ {0,3}\[(?!\^)(?:[^\[\]\\\n]|\\[^\]\n])*\]:[ \t]*(?:<[^<>\n]*>|[^\s<][^\s]*)'
  r'''(?:[ \t]+(?:"[^"\n]*"|'[^'\n]*'|\([^()\n]*\)))?[ \t]*$''',
);

/// Text that might hold a task marker (`[ ]`, `[x]`, `[X]`). Only narrows down the chunks that need their markers located.
final _taskLikePattern = RegExp(r'\[[ xX]\]');

bool _isBlank(String source, int start, int end) {
  for (var i = start; i < end; i++) {
    final unit = source.codeUnitAt(i);
    if (unit != _space && unit != _tab && unit != _carriageReturn) return false;
  }
  return true;
}

bool _contains(String source, int start, int end, int codeUnit) {
  for (var i = start; i < end; i++) {
    if (source.codeUnitAt(i) == codeUnit) return true;
  }
  return false;
}

/// The kind of the previous line. Used to decide whether a reference link definition stands on its own.
enum _LineKind { blank, definition, other }

/// The intermediate state of a scan. It is saved just before the last line and, on an append, the scan resumes from there.
///
/// The scan is a state machine that moves from start to end, and how a line is
/// handled is decided only by the state before it and the line itself. So, given
/// the state just before the previous last line (which may have been incomplete),
/// scanning the appended document again from there gives the same result as
/// scanning the whole text.
final class _ScanState {
  const _ScanState({
    required this.offset,
    required this.chunkStart,
    required this.chunkCount,
    required this.afterBlank,
    required this.htmlDepth,
    required this.htmlOpen,
    required this.inHtmlBlock,
    required this.inHtmlComment,
    required this.fence,
    required this.previous,
    required this.definitionsSafe,
    required this.definitionCount,
    required this.php,
  });

  static const initial = _ScanState(
    offset: 0,
    chunkStart: 0,
    chunkCount: 0,
    afterBlank: false,
    htmlDepth: 0,
    htmlOpen: {},
    inHtmlBlock: false,
    inHtmlComment: false,
    fence: null,
    previous: _LineKind.blank,
    definitionsSafe: true,
    definitionCount: 0,
    php: false,
  );

  /// The position of the start of the line to resume from.
  final int offset;

  /// The position of the start of the open chunk.
  final int chunkStart;

  /// The number of chunks finalized before [chunkStart].
  final int chunkCount;

  final bool afterBlank;
  final int htmlDepth;

  /// The number of open elements per tag name (and [_commentKey]). A closing
  /// tag only closes an element of the same name, as in the block parser.
  final Map<String, int> htmlOpen;

  /// Whether the line before [offset] belongs to an HTML block.
  final bool inHtmlBlock;
  final bool inHtmlComment;
  final String? fence;
  final _LineKind previous;

  /// Whether definitions could be cut out safely (invalidation by `<?` is kept separate in [php]).
  final bool definitionsSafe;

  /// The number of definitions collected before [offset].
  final int definitionCount;

  /// Whether there was a `<?` before [offset].
  final bool php;
}

/// The result of scanning the document (from [_ScanState.offset] on) once.
///
/// `chunks` holds only the chunks from the `_ScanState.chunkCount`-th on. The
/// previous result does not change before that. `resume` is the state to resume the
/// next scan from (null for an empty document).
typedef _Scan = ({
  List<String> chunks,
  bool definitionsSafe,
  _ScanState? resume,
});

/// Scans [source] only from [from] on, splits it into chunks, and collects the reference link definitions.
///
/// The collected definitions are added to [definitions] in document order (the
/// caller truncates it to `definitionCount` of [from] beforehand). When
/// definitions cannot be cut out safely, `definitionsSafe` is false and the
/// document cannot be split into chunks.
_Scan _scan(String source, _ScanState from, List<String> definitions) {
  final chunks = <String>[];
  var definitionsSafe = from.definitionsSafe;
  var previous = from.previous;

  var chunkStart = from.chunkStart;
  var afterBlank = from.afterBlank;
  var htmlDepth = from.htmlDepth;
  final htmlOpen = {...from.htmlOpen};
  var inHtmlBlock = from.inHtmlBlock;
  var inHtmlComment = from.inHtmlComment;
  String? fence = from.fence;
  _ScanState? resume;

  var lineStart = from.offset;
  // PHP processing instructions are HTML blocks to CommonMark, but their
  // boundaries are not understood by this lightweight splitter.
  final phpAt = source.indexOf('<?', from.offset);
  final php = from.php || phpAt != -1;
  while (lineStart < source.length) {
    var lineEnd = source.indexOf('\n', lineStart);
    if (lineEnd == -1) lineEnd = source.length;
    final nextLineStart = lineEnd < source.length ? lineEnd + 1 : lineEnd;

    // Keep the state just before the last line (which may be incomplete). An append resumes from here.
    if (nextLineStart >= source.length) {
      resume = _ScanState(
        offset: lineStart,
        chunkStart: chunkStart,
        chunkCount: from.chunkCount + chunks.length,
        afterBlank: afterBlank,
        htmlDepth: htmlDepth,
        htmlOpen: Map.unmodifiable(htmlOpen),
        inHtmlBlock: inHtmlBlock,
        inHtmlComment: inHtmlComment,
        fence: fence,
        previous: previous,
        definitionsSafe: definitionsSafe,
        definitionCount: definitions.length,
        php: from.php || (phpAt != -1 && phpAt < lineStart),
      );
    }

    if (fence != null) {
      final line = source.substring(lineStart, lineEnd).trim();
      // A closing fence is a line consisting only of at least as many of the same character as the opening one.
      if (line.startsWith(fence) && line.replaceAll(fence[0], '').isEmpty) {
        fence = null;
      }
      previous = _LineKind.other;
    } else if (_isBlank(source, lineStart, lineEnd)) {
      afterBlank = true;
      previous = _LineKind.blank;
      inHtmlBlock = false;
    } else {
      final line = source.substring(lineStart, lineEnd);
      // An HTML block runs from its start line to the next blank line.
      final htmlLine = inHtmlBlock || _htmlBlockStartPattern.hasMatch(line);
      inHtmlBlock = htmlLine;
      // A closing tag inside a comment is text, not an HTML block boundary.
      // Keep comments together conservatively; the comment may contain markup
      // that would otherwise alter the block parser's context.
      if (inHtmlComment || line.contains('<!--') || line.contains('-->')) {
        definitionsSafe = false;
        if (!inHtmlComment && line.contains('<!--')) {
          inHtmlComment = !line.contains('-->');
        } else if (inHtmlComment && line.contains('-->')) {
          inHtmlComment = false;
        }
      }
      final first = source.codeUnitAt(lineStart);
      final indented = first == _space || first == _tab;
      if (afterBlank && htmlDepth == 0 && !indented && lineStart > chunkStart) {
        if (!_listMarkerPattern.hasMatch(line)) {
          chunks.add(source.substring(chunkStart, lineStart));
          chunkStart = lineStart;
        }
      }
      afterBlank = false;

      var kind = _LineKind.other;
      if (_contains(source, lineStart, lineEnd, _openBracket) &&
          _maybeDefinitionPattern.hasMatch(line)) {
        // Only a definition that is complete on one line, directly after a blank line or
        // another definition and outside HTML, can be cut out. Anything else is verified by parsing the whole text.
        final simple =
            htmlDepth == 0 &&
            previous != _LineKind.other &&
            _simpleDefinitionPattern.hasMatch(line);
        if (simple) {
          definitions.add(line);
          kind = _LineKind.definition;
        } else {
          definitionsSafe = false;
        }
      } else if (line.contains(']:')) {
        // A definition label can span lines or contain escaped/nested
        // brackets. If it was not recognized by the simple safe form, do not
        // split: a later paragraph may depend on the parser's full definition
        // table, or the text may not be a definition at all.
        definitionsSafe = false;
      } else if (previous == _LineKind.definition) {
        // A line that follows a definition directly might be the definition's title.
        definitionsSafe = false;
      }
      previous = kind;

      final fenceMatch = _fenceOpenPattern.firstMatch(line);
      if (fenceMatch != null) {
        fence = fenceMatch[1];
      } else if (_contains(source, lineStart, lineEnd, _lessThan)) {
        for (final match in _htmlBoundaryPattern.allMatches(line)) {
          final tag = (match[1] ?? match[2])?.toLowerCase() ?? _commentKey;
          final opens = !match[0]!.startsWith('</') && match[0] != '-->';
          // List items may omit their end tags. The enclosing list already
          // keeps the chunk together, so its items need no separate depth.
          final listDepth = (htmlOpen['ul'] ?? 0) + (htmlOpen['ol'] ?? 0);
          if (tag == 'li' && listDepth > 0) continue;
          final count = htmlOpen[tag] ?? 0;
          if (opens) {
            htmlOpen[tag] = count + 1;
            htmlDepth++;
            continue;
          }
          // Not splitting is always safe, so a closing tag that the block
          // parser might not see (no open element of that name, or outside an
          // HTML block) keeps the element open. A comment ends at any `-->`.
          if (count == 0 || (tag != _commentKey && !htmlLine)) continue;
          htmlOpen[tag] = count - 1;
          htmlDepth--;
        }
      }
    }
    lineStart = nextLineStart;
    if (lineEnd == source.length) break;
  }

  if (chunkStart < source.length) {
    chunks.add(source.substring(chunkStart));
  }
  return (
    chunks: chunks,
    definitionsSafe: definitionsSafe && !php,
    resume: resume,
  );
}

/// Splits [source] into chunks that give the same result when parsed on their own.
///
/// It splits only directly after a blank line, at places where the next line
/// definitely starts a new block. It does not split where in doubt (not splitting
/// is always safe). Concatenating the returned chunks gives back [source].
///
/// Reference link definitions take effect across chunks, so this function's
/// result alone is not enough. [IncrementalMarkdownParser] supplies the
/// definitions to each chunk.
List<String> splitChunks(String source) =>
    _scan(source, _ScanState.initial, <String>[]).chunks;

/// A parser that reuses the previous parse result.
///
/// Reuse one instance per document. For a chunk identical to the previous one it
/// returns the same [MdxBlock] instance, so the Widget cache keeps working as-is.
///
/// When the document was only appended to (streaming), it resumes from the
/// previous scan state and carries over the results of finalized chunks by
/// position. The work of one update is decided by the last line and the size of
/// the open chunk, not by the whole document (doc/performance.md).
class IncrementalMarkdownParser {
  /// [parse] is the function that parses one document (or chunk).
  ///
  /// When omitted, the bundled Rust parser is used. In that case it follows enabling
  /// and disabling of WASM on the web (changes of the parser revision) and rebuilds the cache.
  IncrementalMarkdownParser({List<MdxBlock> Function(String source)? parse})
    : _parseSource = parse ?? selected.parseMarkdown,
      _usesDefaultParser = parse == null;

  final List<MdxBlock> Function(String source) _parseSource;
  final bool _usesDefaultParser;
  int? _backendRevision;

  /// How many instances, counted from the start, of the latest [parse] result are
  /// the same as in the result before it. It is greater than 0 only on the append
  /// fast path. The Widget can skip checking this range.
  int get reusedBlockPrefix => _reusedBlockPrefix;
  int _reusedBlockPrefix = 0;

  /// Where top-level block [index] of the latest [parse] result starts, as a UTF-16 offset
  /// in the source that was parsed. It is the start of the chunk that holds the block, and
  /// the marker offsets of the block's task items ([MdxListItem.markerOffset]) are relative to it.
  ///
  /// 0 when the document was parsed as a whole (it could not be split into chunks), because
  /// the offsets are then relative to the whole document.
  int blockSourceStart(int index) {
    var low = 0;
    var high = _chunkEnds.length;
    // The first chunk whose last block comes after [index].
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_chunkEnds[mid] > index) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low < _chunkStarts.length ? _chunkStarts[low] : 0;
  }

  /// The task item [ordinal] (0-based, among the task items of that block) of top-level block
  /// [blockIndex] of the latest [parse] result [blocks], as the object an app receives from
  /// `onTapCheckbox`.
  ///
  /// Null when there is no such item or its position is unknown.
  MarkdownXTask? taskAt(List<MdxBlock> blocks, int blockIndex, int ordinal) {
    if (blockIndex < 0 || blockIndex >= blocks.length) return null;
    final items = mdxTaskItems([blocks[blockIndex]]);
    if (ordinal < 0 || ordinal >= items.length) return null;
    final item = items[ordinal];
    final offset = item.markerOffset;
    if (offset == null) return null;
    return MarkdownXTask(
      checked: item.checked!,
      index: mdxTaskCount(blocks.take(blockIndex)) + ordinal,
      markerStart: blockSourceStart(blockIndex) + offset,
    );
  }

  /// The cumulative number of characters scanned (for measurement and tests; not public API).
  @internal
  int debugScannedChars = 0;

  /// The cumulative number of characters passed to the parser (for measurement).
  @internal
  int debugParsedChars = 0;

  /// Chunk string to result. For position-independent reuse (edits and reordering).
  Map<String, List<MdxBlock>> _chunks = {};

  /// For the previous document: the chunk strings, the number of blocks up to the end of each chunk, and all blocks.
  /// On an append, the finalized leading part is carried over as-is.
  final List<String> _chunkList = [];
  final List<int> _chunkEnds = [];

  /// Where each chunk of [_chunkList] starts in the source passed to [parse] (the sum of the lengths of the chunks before it).
  final List<int> _chunkStarts = [];
  final List<MdxBlock> _flat = [];

  /// The previous document and the scan state just before its last line (the resume point for an append).
  String? _previousSource;
  _ScanState? _resume;
  final List<String> _definitionList = [];

  /// The reference link definitions when the cache was built.
  String _definitions = '';

  /// Whether it was verified that passing only the extracted definitions to the parser produces no body text.
  bool _definitionsCanBeCopied = true;

  /// The extensions when the cache was built.
  List<MarkdownXExtension> _extensions = const [];

  /// Parses [source]. The result equals parsing the whole document at once.
  ///
  /// When [streaming] is true, [source] is treated as text that is still being
  /// generated, and the unfinished syntax at its end is repaired before parsing
  /// (doc/streaming.md). Only the last chunk is repaired, so the cache of completed
  /// chunks keeps working. With false (the default), the result is exactly the same
  /// as a normal parse with no repair.
  ///
  /// [extensions] are applied to the IR after parsing (applied once per chunk and
  /// cached). If even one element of the list is a different instance from last
  /// time, the cache is discarded, so reuse extension instances.
  List<MdxBlock> parse(
    String source, {
    List<MarkdownXExtension> extensions = const [],
    bool streaming = false,
  }) {
    if (!sameExtensions(_extensions, extensions)) {
      _extensions = List.unmodifiable(extensions);
      _forgetDocument();
    }
    if (!_usesDefaultParser) return _parse(source, streaming);
    final revision = selected.parserRevision;
    if (_backendRevision != revision) _resetBackendCache(revision);
    final result = _parse(source, streaming);
    // A WASM trap can disable the parser while parsing a chunk. Reparse once
    // (which then throws) so a document never mixes results from two states.
    if (selected.parserRevision != revision) {
      _resetBackendCache(selected.parserRevision);
      return _parse(source, streaming);
    }
    return result;
  }

  void _resetBackendCache(int revision) {
    _backendRevision = revision;
    _forgetDocument();
    _definitions = '';
    _definitionsCanBeCopied = true;
  }

  /// Discards all chunk results and append resume points (the next parse scans the whole text).
  void _forgetDocument() {
    _chunks = {};
    _chunkList.clear();
    _chunkEnds.clear();
    _chunkStarts.clear();
    _flat.clear();
    _definitionList.clear();
    _previousSource = null;
    _resume = null;
    _reusedBlockPrefix = 0;
  }

  List<MdxBlock> _parse(String source, bool streaming) {
    try {
      return _parseDocument(source, streaming);
    } on Object {
      // Do not leave a half-updated state behind. The next parse is rebuilt from the whole text.
      _forgetDocument();
      rethrow;
    }
  }

  List<MdxBlock> _parseDocument(String source, bool streaming) {
    _reusedBlockPrefix = 0;
    _preparedTail = null;
    _preparedOriginal = null;
    final previousSource = _previousSource;
    final resume = _resume;
    // For a pure append, the scan can resume from just before the previous last line.
    final canResume =
        previousSource != null &&
        resume != null &&
        source.length >= previousSource.length &&
        // String.startsWith compares one character at a time, so use == which compares with memcmp.
        // Only the comparison with the whole previous document scales with document size
        // (about 80 microseconds at 400 KB).
        (source.length == previousSource.length
            ? source == previousSource
            : source.substring(0, previousSource.length) == previousSource);
    final from = canResume ? resume : _ScanState.initial;
    _definitionList.length = from.definitionCount;
    final scan = _scan(source, from, _definitionList);
    debugScannedChars += source.length - from.offset;

    final original = source;
    final tail = scan.chunks;
    if (streaming && tail.isNotEmpty) {
      final last = tail.last;
      // Transform the source (set aside math and so on) first, so that the repair
      // step does not misread the contents of the set-aside notation (TeX `_` and `*`)
      // as unclosed emphasis. Repairing can change the text into a form that is a
      // transform target (for example `$x$` plus hiding the backtick of an unclosed
      // backtick), so when it changed, transform once more.
      final transformed = applyMarkdownXSourceTransforms(
        last,
        _extensions,
        streaming: true,
      );
      var repaired = repairStreamingChunk(transformed);
      if (repaired != transformed) {
        repaired = applyMarkdownXSourceTransforms(
          repaired,
          _extensions,
          streaming: true,
        );
      }
      if (repaired != last) {
        source = source.substring(0, source.length - last.length) + repaired;
        tail[tail.length - 1] = repaired;
        _preparedTail = repaired;
        _preparedOriginal = last;
      }
    }
    if (!scan.definitionsSafe) {
      _forgetDocument();
      _definitions = '';
      _definitionsCanBeCopied = true;
      return _parseWhole(source, original);
    }

    var reuse = canResume;
    var prefixChunks = const <String>[];
    final definitions = _definitionList.join('\n');
    // When a definition changes, the results of chunks that reference it can change too.
    if (definitions != _definitions) {
      // The Regex is used only to narrow down candidates. It does not reimplement label
      // length, whitespace, or destination validity; it only confirms, when the
      // definitions change, that the parser does not read them as body text. The
      // assignment happens after the check so that state is not broken if parse throws.
      final canBeCopied = _parseSource(definitions).isEmpty;
      if (reuse) prefixChunks = _chunkList.sublist(0, from.chunkCount);
      _chunks = {};
      _chunkList.clear();
      _chunkEnds.clear();
      _chunkStarts.clear();
      _flat.clear();
      reuse = false;
      _definitions = definitions;
      _definitionsCanBeCopied = canBeCopied;
    }
    if (!_definitionsCanBeCopied) {
      _forgetDocument();
      return _parseWhole(source, original);
    }

    if (reuse) {
      _appendTail(tail, from.chunkCount);
      _reusedBlockPrefix = from.chunkCount == 0
          ? 0
          : _chunkEnds[from.chunkCount - 1];
    } else {
      _rebuild([...prefixChunks, ...tail]);
    }
    _previousSource = original;
    _resume = scan.resume;
    return List<MdxBlock>.of(_flat);
  }

  /// Parses the whole document at once, for when it cannot be split into chunks.
  List<MdxBlock> _parseWhole(String source, String original) =>
      _apply(_parseLocated('', _transformDocument(source), original));

  /// Keeps the finalized leading [keep] chunks and replaces only the tail with [tail].
  void _appendTail(List<String> tail, int keep) {
    final dropped = _chunkList.sublist(keep);
    _chunkList.length = keep;
    _chunkEnds.length = keep;
    _chunkStarts.length = keep;
    _flat.length = keep == 0 ? 0 : _chunkEnds[keep - 1];
    for (final chunk in tail) {
      final blocks = _chunks[chunk] ?? _parseChunk(chunk);
      _chunks[chunk] = blocks;
      _addChunk(chunk, blocks);
    }
    // Tail chunks that are no longer used are discarded here.
    for (final chunk in dropped) {
      if (!tail.contains(chunk)) _chunks.remove(chunk);
    }
  }

  void _addChunk(String chunk, List<MdxBlock> blocks) {
    _chunkStarts.add(
      _chunkList.isEmpty ? 0 : _chunkStarts.last + _chunkList.last.length,
    );
    _chunkList.add(chunk);
    _flat.addAll(blocks);
    _chunkEnds.add(_flat.length);
  }

  /// Rebuilds the results of all chunks (the previous results are reused by chunk string).
  void _rebuild(List<String> chunks) {
    final next = <String, List<MdxBlock>>{};
    _chunkList.clear();
    _chunkEnds.clear();
    _chunkStarts.clear();
    _flat.clear();
    for (final chunk in chunks) {
      final blocks = next[chunk] ?? _chunks[chunk] ?? _parseChunk(chunk);
      next[chunk] = blocks;
      _addChunk(chunk, blocks);
    }
    // Chunks that are no longer used are discarded here.
    _chunks = next;
  }

  /// Parses a chunk with the definitions of the whole document supplied.
  ///
  /// The definitions go first. Placed after the chunk, they would become the contents of an unclosed fence.
  List<MdxBlock> _parseChunk(String chunk) {
    // The streaming tail has already been transformed (do not apply it twice).
    final prepared = identical(chunk, _preparedTail);
    final body = prepared ? chunk : _transformSource(chunk);
    final original = prepared ? _preparedOriginal ?? chunk : chunk;
    final prefix = _definitions.isEmpty ? '' : '$_definitions\n\n';
    return _apply(_parseLocated(prefix, body, original));
  }

  /// The streaming tail (the last chunk with the source transform and repair already done). Held only during that parse.
  String? _preparedTail;

  /// The streaming tail before the transform and repair. Held only during that parse.
  String? _preparedOriginal;

  /// Parses `prefix + body` and gives each task item the position of its marker in [original].
  ///
  /// [body] is [original] after the source transforms (and the streaming repair), which can
  /// change the text before a marker (math collapses newlines, for instance), so the
  /// offsets Rust reports for [body] are not positions in [original]. The marker offsets
  /// that [MarkdownXTask] needs are positions in the text the app gave us. They are
  /// relative to [original], so they do not change when the chunk moves in the document and
  /// the cached chunk stays valid.
  ///
  /// - Nothing to locate (no task-like text): the blocks are returned as parsed.
  /// - [body] is [original]: only the length of [prefix] (definitions put in front) is subtracted.
  /// - Otherwise [original] is parsed once more and its markers, which are exact, are paired with
  ///   the displayed task items in order. A task item whose pair cannot be verified (the counts
  ///   or check states disagree) gets no position, and a tap on it does nothing.
  List<MdxBlock> _parseLocated(String prefix, String body, String original) {
    final text = prefix.isEmpty ? body : '$prefix$body';
    debugParsedChars += text.length;
    final blocks = _parseSource(text);
    if (!_taskLikePattern.hasMatch(original)) return blocks;
    final shown = mdxTaskItems(blocks);
    if (shown.isEmpty) return blocks;
    final List<MdxListItem> exact;
    if (identical(body, original) || body == original) {
      exact = shown;
    } else {
      debugParsedChars += prefix.length + original.length;
      exact = mdxTaskItems(_parseSource('$prefix$original'));
    }
    final shift = prefix.length;
    final offsets = <int?>[];
    var paired = true;
    for (var i = 0; i < shown.length; i++) {
      paired =
          paired && i < exact.length && exact[i].checked == shown[i].checked;
      final offset = paired ? exact[i].markerOffset : null;
      offsets.add(offset == null ? null : offset - shift);
    }
    return mdxWithTaskOffsets(blocks, offsets);
  }

  String _transformSource(String source) =>
      applyMarkdownXSourceTransforms(source, _extensions);

  /// Transforms the whole text. When the tail is [_preparedTail], applies it only to what comes before it.
  /// The tail chunk is preceded by a blank line, so the per-chunk result and the whole-text result match.
  String _transformDocument(String source) {
    final tail = _preparedTail;
    if (tail == null || !source.endsWith(tail)) return _transformSource(source);
    final head = source.substring(0, source.length - tail.length);
    return head.isEmpty ? tail : _transformSource(head) + tail;
  }

  List<MdxBlock> _apply(List<MdxBlock> blocks) =>
      applyMarkdownXExtensions(blocks, _extensions);
}
