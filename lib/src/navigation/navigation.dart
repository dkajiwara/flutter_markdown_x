/// Computes heading IDs, the table of contents, and footnote targets from the IR.
///
/// It does not depend on the parser implementation (Dart or native) and is decided
/// by the IR alone, so every backend gives the same result. It does not depend on Flutter.
library;

import '../ir/nodes.dart';

/// The fallback string used when a heading produces an empty slug.
const markdownXEmptySlug = 'section';

/// The prefix of the href of a footnote reference link (`#fn-<label>`).
const _footnoteHrefPrefix = '#fn-';

/// The prefix of the id of the link that returns from a footnote definition to its first reference (`fnref-<label>`).
const _footnoteBackrefIdPrefix = 'fnref-';

/// The text shown on the link that returns from a footnote definition to its reference.
const _footnoteBackrefText = '↩';

/// One heading. It becomes an item of the table of contents.
final class MarkdownXHeading {
  /// Creates a heading. [path] keeps an unmodifiable copy.
  MarkdownXHeading({
    required this.id,
    required this.level,
    required this.text,
    required List<int> path,
  }) : path = List<int>.unmodifiable(path);

  /// The target of an internal link (`#id`). Unique within the document.
  final String id;

  /// The heading level (1 to 6).
  final int level;

  /// Only the text of the heading (decoration and links removed).
  final String text;

  /// The path that descends to the heading's block. The same representation as [MarkdownXAnchor.path].
  final List<int> path;

  @override
  bool operator ==(Object other) =>
      other is MarkdownXHeading &&
      other.id == id &&
      other.level == level &&
      other.text == text &&
      _sameInts(other.path, path);

  @override
  int get hashCode => Object.hash(id, level, text, Object.hashAll(path));

  @override
  String toString() => 'MarkdownXHeading($id, h$level, "$text", $path)';
}

/// The kind of a target.
enum MarkdownXAnchorKind {
  /// A heading.
  heading,

  /// A footnote definition (an item of the list at the end).
  footnote,

  /// The first reference of a footnote (where the definition returns to). Moves to the block that contains the reference.
  footnoteReference,
}

/// The target of an internal link.
///
/// [path] is a route that descends through nesting, starting from the index of a
/// top-level block. A quote, details, or custom block adds one child block index,
/// and a list adds the item index followed by the index of a block within the
/// item. A footnote definition points at the item itself, so its path ends with
/// the item index.
final class MarkdownXAnchor {
  /// Creates a target. [path] keeps an unmodifiable copy.
  MarkdownXAnchor({
    required this.id,
    required this.kind,
    required List<int> path,
  }) : path = List<int>.unmodifiable(path);

  /// The ID of the target. A heading slug or a footnote ID.
  final String id;

  /// The kind of the target.
  final MarkdownXAnchorKind kind;

  /// The path that descends to the target block. See the description of this class.
  final List<int> path;

  @override
  bool operator ==(Object other) =>
      other is MarkdownXAnchor &&
      other.id == id &&
      other.kind == kind &&
      _sameInts(other.path, path);

  @override
  int get hashCode => Object.hash(id, kind, Object.hashAll(path));

  @override
  String toString() => 'MarkdownXAnchor($id, $kind, $path)';
}

bool _sameInts(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// Drop everything except letters, combining marks, digits, connector punctuation (including `_`), `-`, and whitespace.
final RegExp _slugDisallowed = RegExp(
  r'[^\p{L}\p{M}\p{N}\p{Pc}\- ]',
  unicode: true,
);

/// Builds a slug from heading text using the same rules as GitHub (duplicates are not handled).
///
/// It lowercases, drops everything except letters, digits, `-`, `_`, and
/// whitespace, and turns whitespace into `-`. Unicode letters such as Japanese
/// are kept. An empty result returns [markdownXEmptySlug].
String markdownXSlug(String text) {
  final slug = text
      .trim()
      .toLowerCase()
      .replaceAll(_slugDisallowed, '')
      .replaceAll(' ', '-');
  return slug.isEmpty ? markdownXEmptySlug : slug;
}

/// Returns the table of contents of headings in document order. It includes headings
/// inside nested blocks (quotes, lists, details, custom blocks). Duplicate slugs get `-1`, `-2`, and so on.
List<MarkdownXHeading> markdownXHeadings(List<MdxBlock> blocks) =>
    MarkdownXNavigationIndex.build(blocks).headings;

/// Returns the mapping from target (heading and footnote) ids to positions.
Map<String, MarkdownXAnchor> markdownXAnchors(List<MdxBlock> blocks) =>
    MarkdownXNavigationIndex.build(blocks).anchors;

/// The result of [markdownXHeadings] and [markdownXAnchors].
final class MarkdownXNavigationIndex {
  MarkdownXNavigationIndex._(this.headings, this.anchors);

  /// Computes the heading table of contents and the target mapping from [blocks].
  factory MarkdownXNavigationIndex.build(List<MdxBlock> blocks) {
    final footnotes = _FootnoteSection.find(blocks);
    final anchors = <String, MarkdownXAnchor>{};
    // Footnote ids are reserved before headings, so heading slugs yield to them.
    if (footnotes != null) {
      for (final entry in footnotes.anchors.entries) {
        anchors[entry.key] = entry.value;
      }
    }
    final used = {...anchors.keys};
    final counters = <String, int>{};
    final headings = <MarkdownXHeading>[];
    _walkBlocks(blocks, const [], (block, path) {
      if (block is! MdxHeading) return;
      final text = _plainText(block.inlines);
      final base = markdownXSlug(text);
      var id = base;
      while (used.contains(id)) {
        id = '$base-${counters[base] = (counters[base] ?? 0) + 1}';
      }
      used.add(id);
      headings.add(
        MarkdownXHeading(id: id, level: block.level, text: text, path: path),
      );
      anchors[id] = MarkdownXAnchor(
        id: id,
        kind: MarkdownXAnchorKind.heading,
        path: path,
      );
    });
    return MarkdownXNavigationIndex._(
      List.unmodifiable(headings),
      Map.unmodifiable(anchors),
    );
  }

  /// The heading table of contents, in document order.
  final List<MarkdownXHeading> headings;

  /// The mapping from target ID to position (headings and footnotes).
  final Map<String, MarkdownXAnchor> anchors;
}

/// The chain of blocks that [path] points to (from the top level to the target
/// block), and the item index when it points only at a list item. Null when the path does not match the document.
({List<MdxBlock> chain, int? item})? markdownXResolvePath(
  List<MdxBlock> blocks,
  List<int> path,
) {
  if (path.isEmpty) return null;
  final chain = <MdxBlock>[];
  var siblings = blocks;
  var i = 0;
  while (i < path.length) {
    final index = path[i++];
    if (index < 0 || index >= siblings.length) return null;
    final block = siblings[index];
    chain.add(block);
    if (i == path.length) return (chain: chain, item: null);
    switch (block) {
      case MdxBlockquote():
        siblings = block.blocks;
      case MdxDetails():
        siblings = block.blocks;
      case MdxCustomBlock():
        siblings = block.blocks;
      case MdxList():
        final item = path[i++];
        if (item < 0 || item >= block.items.length) return null;
        if (i == path.length) return (chain: chain, item: item);
        siblings = block.items[item].blocks;
      default:
        return null;
    }
  }
  return null;
}

/// Returns the IR with a link back to the first reference added to each item of the trailing footnote definition list.
///
/// Footnote definitions appear at the end of a document that contains references
/// as a "horizontal rule + ordered list" (reference number N corresponds to the
/// N-th list item). When it cannot be read that way, [blocks] is returned as-is.
List<MdxBlock> markdownXAddFootnoteBackrefs(List<MdxBlock> blocks) {
  final section = _FootnoteSection.find(blocks);
  if (section == null) return blocks;
  final list = blocks.last as MdxList;
  final items = <MdxListItem>[];
  for (var i = 0; i < list.items.length; i++) {
    final label = section.labels[i + 1]!;
    final link = MdxLink(
      href: '#$_footnoteBackrefIdPrefix$label',
      children: [MdxText(_footnoteBackrefText)],
    );
    final item = list.items[i];
    final last = item.blocks.isEmpty ? null : item.blocks.last;
    final tail = last is MdxParagraph
        ? MdxParagraph([...last.inlines, MdxText(' '), link], align: last.align)
        : null;
    items.add(
      MdxListItem(
        [
          ...item.blocks.take(item.blocks.length - (tail == null ? 0 : 1)),
          tail ?? MdxParagraph([link]),
        ],
        checked: item.checked,
        markerOffset: item.markerOffset,
      ),
    );
  }
  return [
    ...blocks.take(blocks.length - 1),
    MdxList(ordered: true, start: list.start, tight: list.tight, items: items),
  ];
}

/// The footnote definitions at the end of the document and their correspondence to references.
final class _FootnoteSection {
  _FootnoteSection(this.labels, this.anchors);

  /// Reference number (from 1) to label.
  final Map<int, String> labels;
  final Map<String, MarkdownXAnchor> anchors;

  static _FootnoteSection? find(List<MdxBlock> blocks) {
    if (blocks.length < 2) return null;
    final list = blocks.last;
    if (list is! MdxList ||
        !list.ordered ||
        blocks[blocks.length - 2] is! MdxThematicBreak) {
      return null;
    }
    final labels = <int, String>{};
    final firstRefs = <int, List<int>>{};
    _walkBlocks(blocks, const [], (block, path) {
      for (final inlines in _blockInlines(block)) {
        _walkInlines(inlines, (inline) {
          final ref = _footnoteReference(inline);
          if (ref == null || labels.containsKey(ref.number)) return;
          labels[ref.number] = ref.label;
          firstRefs[ref.number] = path;
        });
      }
    });
    if (labels.isEmpty || labels.length != list.items.length) return null;
    for (var n = 1; n <= list.items.length; n++) {
      if (!labels.containsKey(n)) return null;
    }
    final listPath = blocks.length - 1;
    final anchors = <String, MarkdownXAnchor>{};
    for (var n = 1; n <= list.items.length; n++) {
      final label = labels[n]!;
      anchors['$_footnoteBackrefIdPrefix$label'] = MarkdownXAnchor(
        id: '$_footnoteBackrefIdPrefix$label',
        kind: MarkdownXAnchorKind.footnoteReference,
        path: firstRefs[n]!,
      );
      final id = 'fn-$label';
      anchors[id] = MarkdownXAnchor(
        id: id,
        kind: MarkdownXAnchorKind.footnote,
        path: [listPath, n - 1],
      );
    }
    return _FootnoteSection(labels, anchors);
  }
}

/// If the inline has the form `<sup><a href="#fn-label">N</a></sup>`, its number and label.
({int number, String label})? _footnoteReference(MdxInline inline) {
  if (inline is! MdxStyled ||
      inline.kind != MdxStyleKind.superscript ||
      inline.children.length != 1) {
    return null;
  }
  final link = inline.children.single;
  if (link is! MdxLink ||
      !link.href.startsWith(_footnoteHrefPrefix) ||
      link.children.length != 1) {
    return null;
  }
  final text = link.children.single;
  if (text is! MdxText) return null;
  final number = int.tryParse(text.text);
  if (number == null) return null;
  return (
    number: number,
    label: link.href.substring(_footnoteHrefPrefix.length),
  );
}

/// Walks blocks in document order (parent first, then children). [path] is the same as [MarkdownXAnchor.path].
void _walkBlocks(
  List<MdxBlock> blocks,
  List<int> prefix,
  void Function(MdxBlock block, List<int> path) visit,
) {
  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    final path = [...prefix, i];
    visit(block, path);
    switch (block) {
      case MdxBlockquote():
        _walkBlocks(block.blocks, path, visit);
      case MdxDetails():
        _walkBlocks(block.blocks, path, visit);
      case MdxCustomBlock():
        _walkBlocks(block.blocks, path, visit);
      case MdxList():
        for (var j = 0; j < block.items.length; j++) {
          _walkBlocks(block.items[j].blocks, [...path, j], visit);
        }
      default:
        break;
    }
  }
}

/// The sequence of inlines that the block itself holds (not including those of child blocks).
Iterable<List<MdxInline>> _blockInlines(MdxBlock block) sync* {
  switch (block) {
    case MdxParagraph():
      yield block.inlines;
    case MdxHeading():
      yield block.inlines;
    case MdxDetails():
      yield block.summary;
    case MdxCustomBlock():
      yield block.inlines;
    case MdxTable():
      yield* block.header;
      for (final row in block.rows) {
        yield* row;
      }
    default:
      break;
  }
}

void _walkInlines(List<MdxInline> inlines, void Function(MdxInline) visit) {
  for (final inline in inlines) {
    visit(inline);
    switch (inline) {
      case MdxStyled():
        _walkInlines(inline.children, visit);
      case MdxLink():
        _walkInlines(inline.children, visit);
      case MdxSpan():
        _walkInlines(inline.children, visit);
      case MdxCustomInline():
        _walkInlines(inline.children, visit);
      default:
        break;
    }
  }
}

/// Concatenates only the text of inlines. Images become their alt text and line breaks (hard and soft) become spaces.
String _plainText(List<MdxInline> inlines) {
  final buffer = StringBuffer();
  void write(List<MdxInline> items) {
    for (final inline in items) {
      switch (inline) {
        case MdxText():
          buffer.write(inline.text);
        case MdxLineBreak() || MdxSoftBreak():
          buffer.write(' ');
        case MdxStyled():
          write(inline.children);
        case MdxLink():
          write(inline.children);
        case MdxSpan():
          write(inline.children);
        case MdxCustomInline():
          write(inline.children);
        case MdxImage():
          buffer.write(inline.alt ?? '');
      }
    }
  }

  write(inlines);
  return buffer.toString();
}
