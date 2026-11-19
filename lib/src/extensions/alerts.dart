/// Implements GitHub-style alerts (`> [!NOTE]` and so on) as an IR transform.
///
/// When the first paragraph of a blockquote starts with a line that holds only a
/// marker (such as `[!NOTE]`), the quote is replaced with
/// `MdxCustomBlock('alert', {'kind': 'note'}, blocks: remaining blocks)`.
/// GitHub requires the marker to be on a line of its own (`> [!NOTE] text` is not
/// an alert), but the IR folds soft breaks into spaces, so the IR alone cannot
/// tell the two apart. Therefore, before parsing (`transformSource`), a mark
/// ([alertSourceMarker]) is added right after the `]` of every marker-only line,
/// and the IR transform turns only marked markers into alerts and removes the mark.
/// The parser is left untouched, so every backend produces the same result.
/// This file does not depend on Flutter. See doc/alerts-and-citations.md for the
/// specification.
library;

import 'extension.dart';
import '../ir/nodes.dart';

/// The [MdxCustomBlock.type] of an alert.
const markdownXAlertType = 'alert';

/// The attribute that holds the alert `kind`.
const markdownXAlertKindAttribute = 'kind';

/// The alert kinds defined by GitHub. [name] is both the lowercase marker and the `kind` value.
enum MarkdownXAlertKind {
  /// `[!NOTE]`。
  note,

  /// `[!TIP]`。
  tip,

  /// `[!IMPORTANT]`。
  important,

  /// `[!WARNING]`。
  warning,

  /// `[!CAUTION]`。
  caution,
}

/// Returns the kind of [block] if it is an alert, or null otherwise.
///
/// An unknown `kind` value returns [MarkdownXAlertKind.note] so the block can still be drawn as an alert.
MarkdownXAlertKind? markdownXAlertKindOf(MdxBlock block) {
  if (block is! MdxCustomBlock || block.type != markdownXAlertType) return null;
  final name = block.attributes[markdownXAlertKindAttribute];
  for (final kind in MarkdownXAlertKind.values) {
    if (kind.name == name) return kind;
  }
  return MarkdownXAlertKind.note;
}

/// The mark (one private-use character) added right after the `]` of a marker-only line.
///
/// The IR transform removes it, so users never see it.
const alertSourceMarker = '';

/// The GitHub alert transform. [Markdown] and friends apply it by default (`alerts: false` turns it off).
///
/// When you process only the IR without the default widgets, apply the transform to the source as well.
/// `applyMarkdownXExtensions(parseMarkdown(applyMarkdownXSourceTransforms(source, [markdownXAlertsExtension])), [markdownXAlertsExtension])`
const markdownXAlertsExtension = MarkdownXExtension(
  transformSource: markdownXAlertSource,
  transformBlock: markdownXTransformAlert,
  transformRoot: _stripCandidates,
);

final _marker = RegExp(
  '^\\[!(note|tip|important|warning|caution)\\]$alertSourceMarker[ \\t]*',
  caseSensitive: false,
);

// The shape used to recognize unmarked markers (such as `> [!NOTE] text`).
final _candidateHead = RegExp(
  '^\\[!(?:note|tip|important|warning|caution)\\]$alertSourceMarker',
  caseSensitive: false,
);

/// The sequence of quote prefixes (`>`, list markers, and the whitespace before them).
final _prefix = RegExp(r'^(?:[ \t]*(?:>|(?:[-*+]|\d{1,9}[.)])(?=[ \t])))*');

/// A marker-only line (a prefix followed by `[!KIND]` and trailing whitespace only).
final _markerLine = RegExp(
  r'^((?:[ \t]*(?:>|(?:[-*+]|\d{1,9}[.)])(?=[ \t])))+)[ \t]*'
  r'\[!(?:note|tip|important|warning|caution)\][ \t]*\r?$',
  caseSensitive: false,
);

final _fenceOpen = RegExp(
  r'^[ \t>]*(?:(?:[-*+]|\d{1,9}[.)])[ \t]+)*(`{3,}(?=[^`]*$)|~{3,})',
);
final _fenceQuotePrefix = RegExp(r'^[\s>]+');
final _listStart = RegExp(r'^\s*(?:[-*+]|\d{1,9}[.)])(?:[ \t]|$)');
final _blockStart = RegExp(
  r'^ {0,3}(?:#{1,6}(?:[ \t]|$)|[-*+](?:[ \t]|$)|\d{1,9}[.)](?:[ \t]|$)|`{3,}|~{3,}|<|(?:[-*_][ \t]*){3,}$)',
);

/// Returns [source] with [alertSourceMarker] added right after the `]` of every
/// marker-only line (the first line of a blockquote), or [source] itself when
/// there is nothing to mark.
///
/// A line qualifies when it is the first line of a blockquote and consists only of
/// `[!NOTE]` (the kind is case-insensitive) and trailing whitespace. The `>` may
/// be nested or inside a list item. These do not qualify:
///
/// - a line followed by text on the same line (`> [!NOTE] text`)
/// - the second and later lines of a quote (`> a\n> [!NOTE]`, including lazy continuation)
/// - the inside of fenced and indented code blocks
///
/// When [streaming] is true, a last line without a trailing newline does not
/// qualify. Text might still follow on the same line, so the streaming repair
/// (`markdownXRepairStreamingTail`) hides it until the newline arrives.
///
/// The transform depends only on lines and on whether the state ends at a blank
/// line. Applying it per chunk (chunks are split only after a blank line) gives the
/// same result as applying it to the whole text.
String markdownXAlertSource(String source, {required bool streaming}) {
  if (!source.contains('[!')) return source;
  StringBuffer? out;
  var copied = 0;
  String? fence;
  var prevBlank = true;
  var inList = false;
  var prevDepth = 0;
  var lineStart = 0;
  final length = source.length;
  while (lineStart <= length) {
    var end = source.indexOf('\n', lineStart);
    final terminated = end != -1;
    if (!terminated) end = length;
    final line = source.substring(lineStart, end);
    final prefix = _prefix.firstMatch(line)![0]!;
    var depth = '>'.allMatches(prefix).length;
    if (fence != null) {
      final t = line.replaceFirst(_fenceQuotePrefix, '').trim();
      if (t.startsWith(fence) && t.replaceAll(fence[0], '').isEmpty) {
        fence = null;
      }
      prevDepth = depth;
    } else if (line.trim().isEmpty) {
      prevBlank = true;
      prevDepth = 0;
    } else {
      final open = _fenceOpen.firstMatch(line);
      if (open != null) {
        fence = open[1];
      } else {
        // A line without the quote's `>` is still inside the quote if it continues a paragraph (lazy continuation).
        if (depth == 0 && prevDepth > 0 && !_blockStart.hasMatch(line)) {
          depth = prevDepth;
        }
        final match = _markerLine.firstMatch(line);
        if (match != null &&
            (terminated || !streaming) &&
            _isQuoteStart(match[1]!, depth, prevDepth) &&
            !(prevBlank && !inList && _indent(match[1]!) >= 4)) {
          final at = lineStart + line.lastIndexOf(']') + 1;
          (out ??= StringBuffer()).write(source.substring(copied, at));
          out.write(alertSourceMarker);
          copied = at;
        }
      }
      if (_listStart.hasMatch(line)) {
        inList = true;
      } else if (!line.startsWith(' ') && !line.startsWith('\t')) {
        inList = false;
      }
      prevBlank = false;
      prevDepth = depth;
    }
    lineStart = end + 1;
  }
  if (out == null) return source;
  out.write(source.substring(copied));
  return out.toString();
}

/// Whether the last `>` of [prefix] starts its quote on this line.
bool _isQuoteStart(String prefix, int depth, int prevDepth) {
  if (!prefix.trimRight().endsWith('>')) return false;
  final hasList = prefix.contains(RegExp(r'[-*+\d]'));
  return hasList || depth > prevDepth;
}

int _indent(String prefix) {
  var width = 0;
  for (var k = 0; k < prefix.length; k++) {
    final c = prefix.codeUnitAt(k);
    if (c == 0x20) {
      width++;
    } else if (c == 0x09) {
      width += 4 - width % 4;
    } else {
      break;
    }
  }
  return width;
}

/// The body of the [markdownXAlertsExtension] transform. For a non-alert, it only removes the mark.
///
/// A blockquote that starts with a marked marker-only line becomes an alert. Marks
/// left in positions that cannot become alerts (unexpected code, second and later
/// paragraphs, and so on) are removed here as well.
/// Because it receives blocks after their children have been processed, the mark
/// on the first paragraph of a quote is kept until the quote sees it, and the
/// quote (and parents such as lists and details) removes it.
MdxBlock? markdownXTransformAlert(MdxBlock block) {
  switch (block) {
    case MdxBlockquote():
      return _blockquote(block);
    case MdxParagraph():
      return _isCandidate(block) ? null : _stripParagraph(block);
    case MdxHeading():
      final inlines = _stripInlines(block.inlines);
      return identical(inlines, block.inlines)
          ? null
          : MdxHeading(block.level, inlines, align: block.align);
    case MdxCodeBlock():
      return block.code.contains(alertSourceMarker)
          ? MdxCodeBlock(
              block.code.replaceAll(alertSourceMarker, ''),
              language: block.language,
              info: block.info,
            )
          : null;
    case MdxTable():
      return _stripTable(block);
    case MdxList():
      var changed = false;
      final items = [
        for (final item in block.items)
          () {
            final blocks = _stripCandidates(item.blocks);
            if (identical(blocks, item.blocks)) return item;
            changed = true;
            return MdxListItem(
              blocks,
              checked: item.checked,
              markerOffset: item.markerOffset,
            );
          }(),
      ];
      return changed
          ? MdxList(
              ordered: block.ordered,
              start: block.start,
              tight: block.tight,
              items: items,
            )
          : null;
    case MdxDetails():
      final summary = _stripInlines(block.summary);
      final blocks = _stripCandidates(block.blocks);
      return identical(summary, block.summary) &&
              identical(blocks, block.blocks)
          ? null
          : MdxDetails(summary: summary, blocks: blocks);
    case MdxCustomBlock() || MdxThematicBreak():
      return null;
  }
}

MdxBlock? _blockquote(MdxBlockquote block) {
  if (block.blocks.isEmpty) return null;
  final first = block.blocks.first;
  if (first is MdxParagraph && first.inlines.isNotEmpty) {
    final head = first.inlines.first;
    final match = head is MdxText ? _marker.firstMatch(head.text) : null;
    if (match != null) {
      final kind = match[1]!.toLowerCase();
      final rest = (head as MdxText).text.substring(match.end);
      final inlines = <MdxInline>[
        if (rest.isNotEmpty) MdxText(rest),
        ...first.inlines.skip(1),
      ];
      // A hard or soft break at the end of the marker line is not body content.
      if (inlines.isNotEmpty &&
          (inlines.first is MdxLineBreak || inlines.first is MdxSoftBreak)) {
        inlines.removeAt(0);
      }
      final body = _stripCandidates(block.blocks.skip(1).toList());
      return MdxCustomBlock(
        markdownXAlertType,
        attributes: {markdownXAlertKindAttribute: kind},
        blocks: [
          if (inlines.isNotEmpty)
            MdxParagraph(_stripInlines(inlines), align: first.align),
          ...body,
        ],
      );
    }
  }
  final blocks = _stripCandidates(block.blocks);
  return identical(blocks, block.blocks) ? null : MdxBlockquote(blocks);
}

/// A paragraph that starts with a marked marker (kept until the parent turns it into an alert or removes the mark).
bool _isCandidate(MdxParagraph p) {
  if (p.inlines.isEmpty) return false;
  final head = p.inlines.first;
  return head is MdxText && _candidateHead.hasMatch(head.text);
}

/// Removes the mark from the paragraph in [blocks] that still carries it.
List<MdxBlock> _stripCandidates(List<MdxBlock> blocks) {
  List<MdxBlock>? out;
  for (var i = 0; i < blocks.length; i++) {
    final b = blocks[i];
    if (b is MdxParagraph && _isCandidate(b)) {
      out ??= blocks.toList();
      out[i] = _stripParagraph(b);
    }
  }
  return out ?? blocks;
}

MdxBlock _stripParagraph(MdxParagraph p) {
  final inlines = _stripInlines(p.inlines);
  return identical(inlines, p.inlines)
      ? p
      : MdxParagraph(inlines, align: p.align);
}

MdxBlock? _stripTable(MdxTable t) {
  var changed = false;
  List<MdxInline> cell(List<MdxInline> c) {
    final r = _stripInlines(c);
    if (!identical(r, c)) changed = true;
    return r;
  }

  final header = [for (final c in t.header) cell(c)];
  final rows = [
    for (final row in t.rows) [for (final c in row) cell(c)],
  ];
  return changed
      ? MdxTable(alignments: t.alignments, header: header, rows: rows)
      : null;
}

List<MdxInline> _stripInlines(List<MdxInline> inlines) {
  List<MdxInline>? out;
  for (var i = 0; i < inlines.length; i++) {
    final inline = inlines[i];
    final mapped = _stripInline(inline);
    if (out == null && !identical(mapped, inline)) {
      out = inlines.sublist(0, i);
    }
    if (mapped != null) out?.add(mapped);
  }
  return out ?? inlines;
}

/// The inline with the mark removed. Null (dropped) when the text becomes empty.
MdxInline? _stripInline(MdxInline inline) {
  switch (inline) {
    case MdxText():
      if (!inline.text.contains(alertSourceMarker)) return inline;
      final text = inline.text.replaceAll(alertSourceMarker, '');
      return text.isEmpty ? null : MdxText(text);
    case MdxStyled():
      final children = _stripInlines(inline.children);
      return identical(children, inline.children)
          ? inline
          : MdxStyled(inline.kind, children, title: inline.title);
    case MdxSpan():
      final children = _stripInlines(inline.children);
      return identical(children, inline.children)
          ? inline
          : MdxSpan(inline.style, children);
    case MdxLink():
      final children = _stripInlines(inline.children);
      final href = inline.href.replaceAll(alertSourceMarker, '');
      final title = inline.title?.replaceAll(alertSourceMarker, '');
      return identical(children, inline.children) &&
              href == inline.href &&
              title == inline.title
          ? inline
          : MdxLink(href: href, title: title, children: children);
    case MdxImage():
      final src = inline.src.replaceAll(alertSourceMarker, '');
      final alt = inline.alt?.replaceAll(alertSourceMarker, '');
      final title = inline.title?.replaceAll(alertSourceMarker, '');
      return src == inline.src && alt == inline.alt && title == inline.title
          ? inline
          : MdxImage(
              src: src,
              alt: alt,
              title: title,
              width: inline.width,
              height: inline.height,
            );
    case MdxLineBreak() || MdxSoftBreak() || MdxCustomInline():
      return inline;
  }
}
