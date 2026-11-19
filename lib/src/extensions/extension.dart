/// Syntax extensions. They transform the parsed IR to create custom inlines and blocks.
///
/// Extensions do not go into the parser. The Dart implementation and the native
/// implementation produce the same IR, so extensions are implemented as
/// backend-independent transforms over that IR. As a result, every backend gives
/// the same result, and the cross-parser consistency checks are not broken.
/// This file does not depend on Flutter, so it also works with `dart run`.
library;

import '../ir/nodes.dart';

/// The type of [MarkdownXInlineSyntax.build]. Creates an inline from [match].
/// Returning null treats that match as if it never happened.
typedef MarkdownXInlineBuild = MdxInline? Function(Match match);

/// The type of [MarkdownXExtension.transformBlock].
/// Returns the replacement block. Null means [block] is used as-is.
typedef MarkdownXBlockTransform = MdxBlock? Function(MdxBlock block);

/// The type of [MarkdownXExtension.transformRoot]. Transforms the whole list of top-level blocks of a document.
/// Return [blocks] itself when nothing changes.
typedef MarkdownXRootTransform = List<MdxBlock> Function(List<MdxBlock> blocks);

/// The type of [MarkdownXExtension.transformSource]. Transforms the Markdown source
/// before parsing.
///
/// [streaming] says whether [source] is the last chunk of text that is still being generated.
/// The function must be pure and return the same result for the same input (the
/// chunk cache is keyed by the original source, so keeping state would make it
/// disagree with the cache). Re-applying it to an already transformed source is
/// not supported (the parser never applies it twice).
typedef MarkdownXSourceTransform = String Function(
  String source, {
  required bool streaming,
});

/// The type of [MarkdownXExtension.transformInline]. Returns the replacement inline.
/// Null means the inline is used as-is.
typedef MarkdownXInlineTransform = MdxInline? Function(MdxInline inline);

/// An inline syntax over strings.
///
/// [pattern] is applied to the [MdxText] nodes of the IR (adjacent text nodes are
/// concatenated first). Code spans, code blocks, link hrefs, and image alt text
/// are not targets, and link text is a target only when [applyInsideLinks] is true
/// (the text of an autolink, which is the URL itself, never is).
class MarkdownXInlineSyntax {
  /// Creates a syntax that replaces the range matched by [pattern] with the inline returned by [build].
  MarkdownXInlineSyntax({
    required this.pattern,
    required this.build,
    this.applyInsideLinks = false,
    this.rescanAfterRejected = false,
  });

  /// The regular expression that finds inlines.
  final RegExp pattern;

  /// The function that creates the replacement inline from a match. Returning null leaves the match unreplaced.
  final MarkdownXInlineBuild build;

  /// Whether to also apply it inside link text. Defaults to false (to avoid nesting links).
  final bool applyInsideLinks;

  /// Where to look for the next match when [build] returns null. By default the search
  /// resumes after the rejected match. When true it resumes one character after the
  /// start of the rejected match, so a match that overlaps it is still found (for
  /// example `:foo:smile:` after rejecting `:foo:`).
  final bool rescanAfterRejected;
}

/// A bundle of syntax extensions. Pass it as `extensions` of [Markdown] and friends.
///
/// Cache invalidation is decided by instance identity, so keep the extension in a
/// field or a `const` and reuse it. Creating a new one on every build re-parses
/// the whole document every time.
class MarkdownXExtension {
  /// Creates a syntax extension. Omitted members do nothing.
  const MarkdownXExtension({
    this.inlineSyntaxes = const [],
    this.transformBlock,
    this.transformInline,
    this.transformSource,
    this.transformRoot,
  });

  /// Inline syntaxes. Earlier registrations take priority.
  final List<MarkdownXInlineSyntax> inlineSyntaxes;

  /// Block transform. Receives a block after its children (nested blocks and inline
  /// transforms) have been processed. Use it for things like turning a paragraph into an [MdxCustomBlock].
  final MarkdownXBlockTransform? transformBlock;

  /// Transform for every inline other than text (including those inside code spans,
  /// links, and emphasis). Receives an inline after its children have been
  /// processed. Code spans are targets too, so use it to restore notation that was
  /// set aside into a code span before parsing. Use it as a pair with `transformSource`.
  final MarkdownXInlineTransform? transformInline;

  /// Transforms the source before parsing. Use it to set aside, before parsing,
  /// notation that CommonMark would break if it interpreted it first (such as `_`,
  /// `\\`, and `\{` in math) into code spans and the like.
  ///
  /// The transform is applied per chunk (`splitChunks`). Chunks are split only after
  /// a blank line, so notation that does not cross blank lines gives the same result
  /// as applying it to the whole text. The transformed source is passed to every
  /// backend as-is, so Dart and native produce the same IR.
  /// The transform must be pure.
  final MarkdownXSourceTransform? transformSource;

  /// Transform for the whole sequence of top-level blocks. Called after all blocks have been processed.
  /// `transformBlock` does not know the parent, so for mechanisms where the parent
  /// cleans up (such as removing the alert mark) because children are processed
  /// before parents, use this for the top-level cleanup.
  /// IncrementalMarkdownParser calls it per chunk (a contiguous range of top-level blocks).
  final MarkdownXRootTransform? transformRoot;
}

/// Applies the `transformSource` of [extensions] to [source], in order.
///
/// [IncrementalMarkdownParser] applies it per chunk. Applying it to the whole
/// text gives the same result as per chunk for transforms that do not cross blank lines.
String applyMarkdownXSourceTransforms(
  String source,
  List<MarkdownXExtension> extensions, {
  bool streaming = false,
}) {
  var result = source;
  for (final e in extensions) {
    final t = e.transformSource;
    if (t != null) result = t(result, streaming: streaming);
  }
  return result;
}

/// Whether [a] and [b] hold the same instances in the same order. Used for cache decisions.
bool sameExtensions(List<MarkdownXExtension> a, List<MarkdownXExtension> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}

/// Returns the IR with [extensions] applied to [blocks].
///
/// Subtrees that did not change are returned as the same instance (the Widget
/// block cache relies on instance and value equality). When nothing changes,
/// [blocks] itself is returned.
List<MdxBlock> applyMarkdownXExtensions(
  List<MdxBlock> blocks,
  List<MarkdownXExtension> extensions,
) {
  if (extensions.isEmpty) return blocks;
  var result = _Transformer(extensions)._blocks(blocks);
  for (final e in extensions) {
    final root = e.transformRoot;
    if (root != null) result = root(result);
  }
  return result;
}

class _Candidate {
  _Candidate(this.match, this.inline);
  final Match match;
  final MdxInline inline;
}

class _Transformer {
  _Transformer(List<MarkdownXExtension> extensions)
    : _syntaxes = [for (final e in extensions) ...e.inlineSyntaxes],
      _linkSyntaxes = [
        for (final e in extensions)
          for (final s in e.inlineSyntaxes)
            if (s.applyInsideLinks) s,
      ],
      _transforms = [
        for (final e in extensions)
          if (e.transformBlock != null) e.transformBlock!,
      ],
      _inlineTransforms = [
        for (final e in extensions)
          if (e.transformInline != null) e.transformInline!,
      ];

  final List<MarkdownXInlineSyntax> _syntaxes;
  final List<MarkdownXInlineSyntax> _linkSyntaxes;
  final List<MarkdownXBlockTransform> _transforms;
  final List<MarkdownXInlineTransform> _inlineTransforms;

  /// Returns [list] as-is when every element is the same instance.
  List<T> _mapList<T>(List<T> list, T Function(T) f) {
    List<T>? out;
    for (var i = 0; i < list.length; i++) {
      final mapped = f(list[i]);
      if (out == null && !identical(mapped, list[i])) {
        out = list.sublist(0, i);
      }
      out?.add(mapped);
    }
    return out ?? list;
  }

  List<MdxBlock> _blocks(List<MdxBlock> blocks) => _mapList(blocks, _block);

  MdxBlock _block(MdxBlock block) {
    final converted = switch (block) {
      MdxParagraph() => _paragraph(block),
      MdxHeading() => _heading(block),
      MdxBlockquote() => _blockquote(block),
      MdxList() => _list(block),
      MdxTable() => _table(block),
      MdxDetails() => _details(block),
      MdxCodeBlock() || MdxThematicBreak() || MdxCustomBlock() => block,
    };
    var result = converted;
    for (final transform in _transforms) {
      result = transform(result) ?? result;
    }
    return result;
  }

  MdxBlock _paragraph(MdxParagraph b) {
    final inlines = _inlines(b.inlines, _syntaxes);
    return identical(inlines, b.inlines)
        ? b
        : MdxParagraph(inlines, align: b.align);
  }

  MdxBlock _heading(MdxHeading b) {
    final inlines = _inlines(b.inlines, _syntaxes);
    return identical(inlines, b.inlines)
        ? b
        : MdxHeading(b.level, inlines, align: b.align);
  }

  MdxBlock _blockquote(MdxBlockquote b) {
    final blocks = _blocks(b.blocks);
    return identical(blocks, b.blocks) ? b : MdxBlockquote(blocks);
  }

  MdxBlock _list(MdxList b) {
    final items = _mapList<MdxListItem>(b.items, (item) {
      final blocks = _blocks(item.blocks);
      return identical(blocks, item.blocks)
          ? item
          : MdxListItem(
              blocks,
              checked: item.checked,
              markerOffset: item.markerOffset,
            );
    });
    return identical(items, b.items)
        ? b
        : MdxList(
            ordered: b.ordered,
            start: b.start,
            tight: b.tight,
            items: items,
          );
  }

  MdxBlock _table(MdxTable b) {
    List<MdxInline> cell(List<MdxInline> c) => _inlines(c, _syntaxes);
    final header = _mapList(b.header, cell);
    final rows = _mapList<List<List<MdxInline>>>(
      b.rows,
      (row) => _mapList(row, cell),
    );
    return identical(header, b.header) && identical(rows, b.rows)
        ? b
        : MdxTable(
            alignments: b.alignments,
            header: header,
            rows: rows,
            headerSpans: b.headerSpans,
            rowSpans: b.rowSpans,
          );
  }

  MdxBlock _details(MdxDetails b) {
    final summary = _inlines(b.summary, _syntaxes);
    final blocks = _blocks(b.blocks);
    return identical(summary, b.summary) && identical(blocks, b.blocks)
        ? b
        : MdxDetails(summary: summary, blocks: blocks, open: b.open);
  }

  List<MdxInline> _inlines(
    List<MdxInline> inlines,
    List<MarkdownXInlineSyntax> syntaxes,
  ) {
    if (syntaxes.isEmpty && _inlineTransforms.isEmpty) return inlines;
    final out = <MdxInline>[];
    var changed = false;
    var i = 0;
    while (i < inlines.length) {
      final inline = inlines[i];
      if (inline is MdxText || inline is MdxSoftBreak) {
        // Adjacent text nodes are treated as one string (crossing the boundaries where the parser split them).
        // A soft break is one ' ' of glue, so a match can span a source line; unmatched
        // stretches get their MdxSoftBreak nodes back.
        var end = i;
        final buffer = StringBuffer();
        final breaks = <int>[];
        while (end < inlines.length) {
          final part = inlines[end];
          if (part is MdxText) {
            buffer.write(part.text);
          } else if (part is MdxSoftBreak) {
            breaks.add(buffer.length);
            buffer.write(' ');
          } else {
            break;
          }
          end++;
        }
        final split = syntaxes.isEmpty
            ? null
            : _split(buffer.toString(), syntaxes, breaks);
        if (split == null) {
          out.addAll(inlines.getRange(i, end));
        } else {
          out.addAll(split);
          changed = true;
        }
        i = end;
        continue;
      }
      final mapped = _inline(inline, syntaxes);
      if (!identical(mapped, inline)) changed = true;
      out.add(mapped);
      i++;
    }
    return changed ? out : inlines;
  }

  MdxInline _inline(MdxInline inline, List<MarkdownXInlineSyntax> syntaxes) {
    final mapped = _inlineSyntaxes(inline, syntaxes);
    var result = mapped;
    for (final transform in _inlineTransforms) {
      result = transform(result) ?? result;
    }
    return result;
  }

  MdxInline _inlineSyntaxes(
    MdxInline inline,
    List<MarkdownXInlineSyntax> syntaxes,
  ) {
    switch (inline) {
      case MdxStyled():
        if (inline.kind == MdxStyleKind.code ||
            inline.kind == MdxStyleKind.keyboard) {
          return inline;
        }
        final children = _inlines(inline.children, syntaxes);
        return identical(children, inline.children)
            ? inline
            : MdxStyled(inline.kind, children, title: inline.title);
      case MdxSpan():
        final children = _inlines(inline.children, syntaxes);
        return identical(children, inline.children)
            ? inline
            : MdxSpan(inline.style, children);
      case MdxLink():
        if (_isAutolink(inline)) return inline;
        final children = _inlines(inline.children, _linkSyntaxes);
        return identical(children, inline.children)
            ? inline
            : MdxLink(
                href: inline.href,
                title: inline.title,
                children: children,
              );
      case MdxText() ||
          MdxSoftBreak() ||
          MdxLineBreak() ||
          MdxImage() ||
          MdxCustomInline():
        return inline;
    }
  }

  /// Whether [link] is an autolink: its only child is the URL itself as text (a bare URL or `<url>`).
  /// A URL is not prose, so syntaxes never apply to it.
  bool _isAutolink(MdxLink link) {
    if (link.children.length != 1) return false;
    final child = link.children.single;
    if (child is! MdxText) return false;
    final text = child.text;
    final href = link.href;
    return href == text ||
        href == 'http://$text' ||
        href == 'https://$text' ||
        href == 'mailto:$text';
  }

  /// Splits [text]. Null if nothing matches.
  ///
  /// Keeps the next match of each syntax and takes the earliest one. At the same
  /// position, registration order wins. Empty matches and matches for which
  /// [MarkdownXInlineSyntax.build] returns null are ignored.
  ///
  /// [breaks] are the offsets in [text] that stand for an [MdxSoftBreak] (one space each).
  List<MdxInline>? _split(
    String text,
    List<MarkdownXInlineSyntax> syntaxes,
    List<int> breaks,
  ) {
    final candidates = List<_Candidate?>.filled(syntaxes.length, null);
    final exhausted = List<bool>.filled(syntaxes.length, false);
    final out = <MdxInline>[];
    var pos = 0;
    while (true) {
      _Candidate? best;
      for (var i = 0; i < syntaxes.length; i++) {
        if (exhausted[i]) continue;
        var candidate = candidates[i];
        if (candidate == null || candidate.match.start < pos) {
          candidate = _next(syntaxes[i], text, pos);
          candidates[i] = candidate;
          if (candidate == null) {
            exhausted[i] = true;
            continue;
          }
        }
        if (best == null || candidate.match.start < best.match.start) {
          best = candidate;
        }
      }
      if (best == null) break;
      _addPlain(out, text, pos, best.match.start, breaks);
      _addInline(out, best.inline);
      pos = best.match.end;
    }
    if (out.isEmpty) return null;
    _addPlain(out, text, pos, text.length, breaks);
    return out;
  }

  /// Adds `text[from, to)` as text, restoring an [MdxSoftBreak] at each of [breaks].
  void _addPlain(
    List<MdxInline> out,
    String text,
    int from,
    int to,
    List<int> breaks,
  ) {
    var start = from;
    for (final at in breaks) {
      if (at < from) continue;
      if (at >= to) break;
      if (at > start) _addInline(out, MdxText(text.substring(start, at)));
      out.add(MdxSoftBreak());
      start = at + 1;
    }
    if (to > start) _addInline(out, MdxText(text.substring(start, to)));
  }

  /// Adds [inline], merging it into the previous node when both are text (a syntax
  /// that returns plain text, such as an emoji, then reads as part of its surroundings).
  void _addInline(List<MdxInline> out, MdxInline inline) {
    final last = out.isEmpty ? null : out.last;
    if (last is MdxText && inline is MdxText) {
      out[out.length - 1] = MdxText(last.text + inline.text);
    } else {
      out.add(inline);
    }
  }

  _Candidate? _next(MarkdownXInlineSyntax syntax, String text, int from) {
    var at = from;
    while (at <= text.length) {
      final match = syntax.pattern.allMatches(text, at).firstOrNull;
      if (match == null) return null;
      final inline = match.end == match.start ? null : syntax.build(match);
      if (inline != null) return _Candidate(match, inline);
      at = syntax.rescanAfterRejected || match.end == match.start
          ? match.start + 1
          : match.end;
    }
    return null;
  }
}
