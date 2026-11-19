/// Markdown normalized into an intermediate representation (IR) for rendering.
///
/// All nodes are immutable and comparable by value. The per-block Widget cache
/// relies on this equality. It does not depend on Flutter, so it also works under `dart run`.
library;

int _deepHash(Object? value) {
  if (value is List) {
    return Object.hashAll(value.map(_deepHash));
  }
  if (value is Map) {
    // Make the hash independent of Map ordering.
    return Object.hashAllUnordered(
      value.entries.map(
        (e) => Object.hash(_deepHash(e.key), _deepHash(e.value)),
      ),
    );
  }
  return value.hashCode;
}

bool _deepEquals(Object? a, Object? b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}

/// Base class of the IR. Provides value comparison through [props] and a cached hash.
abstract class MdxNode {
  /// The values used to determine equality.
  List<Object?> get props;

  @override
  late final int hashCode = Object.hash(runtimeType, _deepHash(props));

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MdxNode &&
        other.runtimeType == runtimeType &&
        other.hashCode == hashCode &&
        _deepEquals(props, other.props);
  }

  @override
  String toString() => '$runtimeType$props';
}

// ---------------------------------------------------------------------------
// Inline
// ---------------------------------------------------------------------------

/// Inline element.
sealed class MdxInline extends MdxNode {}

List<T> _freeze<T>(Iterable<T> values) => List<T>.unmodifiable(values);

List<List<T>> _freeze2<T>(Iterable<Iterable<T>> values) =>
    List<List<T>>.unmodifiable(values.map(_freeze<T>));

List<List<List<T>>> _freeze3<T>(Iterable<Iterable<Iterable<T>>> values) =>
    List<List<List<T>>>.unmodifiable(values.map(_freeze2<T>));

/// Plain text.
final class MdxText extends MdxInline {
  /// Creates a text node whose string is [text].
  MdxText(this.text);

  /// The string.
  final String text;

  @override
  List<Object?> get props => [text];
}

/// Hard line break (`<br>` or two trailing spaces at the end of a line).
final class MdxLineBreak extends MdxInline {
  @override
  List<Object?> get props => const [];
}

/// Soft line break: a source newline inside a paragraph (not `<br>` or a trailing backslash).
///
/// It renders as one space by default, or as a line break when the renderer's soft line
/// break mode is on. The parser trims it at the edges of a paragraph.
final class MdxSoftBreak extends MdxInline {
  @override
  List<Object?> get props => const [];
}

/// The kind of text decoration. Created from both Markdown syntax and allowed HTML tags.
enum MdxStyleKind {
  /// Emphasis (bold).
  strong,

  /// Emphasis (italic).
  emphasis,

  /// Strikethrough.
  strikethrough,

  /// inline code.
  code,

  /// Underline.
  underline,

  /// Highlight (`<mark>`).
  mark,

  /// Subscript.
  subscript,

  /// Superscript.
  superscript,

  /// Keyboard input (`<kbd>`).
  keyboard,

  /// Small text (`<small>`).
  small,

  /// Title of a work (`<cite>`). Italic.
  cite,

  /// Defining instance of a term (`<dfn>`). Italic.
  definition,

  /// Variable (`<var>`). Italic.
  variable,

  /// Sample output (`<samp>`). Monospace font, without the code background.
  sample,

  /// Teletype text (`<tt>`). Monospace font, without the code background.
  teletype,

  /// Larger text (`<big>`).
  big,

  /// Abbreviation (`<abbr>`). Dotted underline when it has a [MdxStyled.title].
  abbreviation,

  /// Acronym (`<acronym>`, obsolete alias of `abbr`). Dotted underline when it has a [MdxStyled.title].
  acronym,
}

/// A range of decorated text.
final class MdxStyled extends MdxInline {
  /// Creates an inline that applies the [kind] decoration to [children]. [children] holds an unmodifiable copy.
  ///
  /// [title] is meaningful only for [MdxStyleKind.abbreviation] and [MdxStyleKind.acronym].
  MdxStyled(this.kind, List<MdxInline> children, {this.title})
    : children = _freeze(children);

  /// The kind of text decoration.
  final MdxStyleKind kind;

  /// The decorated inlines.
  final List<MdxInline> children;

  /// The `title` attribute of an `abbr` or `acronym` (its expansion). Null for every other kind.
  final String? title;

  @override
  List<Object?> get props => [kind, children, title];
}

/// An app-specific inline created by an extension (`MarkdownXExtension`).
///
/// The [type] distinguishes the kind, and [attributes] holds arbitrary string values. [children] is
/// the fallback shown when there is no builder, and is rendered like any ordinary inline.
/// The parser never creates it. It appears only as a result of the conversion to IR (`applyMarkdownXExtensions`).
final class MdxCustomInline extends MdxInline {
  /// Creates a custom inline of [type]. [attributes] and [children] hold unmodifiable copies.
  MdxCustomInline(
    this.type, {
    Map<String, String> attributes = const {},
    List<MdxInline> children = const [],
  }) : attributes = Map<String, String>.unmodifiable(attributes),
       children = _freeze(children);

  /// The name that distinguishes the kind of custom inline.
  final String type;

  /// Arbitrary string values.
  final Map<String, String> attributes;

  /// The inlines used as the fallback display when there is no builder.
  final List<MdxInline> children;

  @override
  List<Object?> get props => [type, attributes, children];
}

/// The text appearance read from an HTML `style` attribute and the like.
///
/// Colors are held as ARGB integers (`0xAARRGGBB`) to stay independent of Flutter.
final class MdxInlineStyle extends MdxNode {
  /// Creates a text appearance. Omitted fields mean unspecified (null for color and font size, false otherwise).
  MdxInlineStyle({
    this.color,
    this.backgroundColor,
    this.fontSize,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
  });

  /// Text color (ARGB integer `0xAARRGGBB`). Null when unspecified.
  final int? color;

  /// Background color (ARGB integer `0xAARRGGBB`). Null when unspecified.
  final int? backgroundColor;

  /// Font size (logical pixels).
  final double? fontSize;

  /// Whether the text is bold.
  final bool bold;

  /// Whether the text is italic.
  final bool italic;

  /// Whether the text is underlined.
  final bool underline;

  /// Whether the text has a strikethrough.
  final bool strikethrough;

  /// True when nothing is specified.
  bool get isEmpty =>
      color == null &&
      backgroundColor == null &&
      fontSize == null &&
      !bold &&
      !italic &&
      !underline &&
      !strikethrough;

  @override
  List<Object?> get props => [
    color,
    backgroundColor,
    fontSize,
    bold,
    italic,
    underline,
    strikethrough,
  ];
}

/// A range with an inline style specified (such as `<span style="...">`).
final class MdxSpan extends MdxInline {
  /// Creates an inline that applies [style] to [children]. [children] holds an unmodifiable copy.
  MdxSpan(this.style, List<MdxInline> children) : children = _freeze(children);

  /// The text appearance to apply.
  final MdxInlineStyle style;

  /// The inlines the style covers.
  final List<MdxInline> children;

  @override
  List<Object?> get props => [style, children];
}

/// A link.
final class MdxLink extends MdxInline {
  /// Creates a link to [href]. [children] holds an unmodifiable copy.
  MdxLink({required this.href, required List<MdxInline> children, this.title})
    : children = _freeze(children);

  /// The link destination.
  final String href;

  /// The link title. Null if absent.
  final String? title;

  /// The inlines that make up the link text.
  final List<MdxInline> children;

  @override
  List<Object?> get props => [href, title, children];
}

/// An image. [width] and [height] are set only when specified on an HTML `<img>`.
final class MdxImage extends MdxInline {
  /// Creates an image of [src]. [alt], [title], [width] and [height] may be omitted.
  MdxImage({required this.src, this.alt, this.title, this.width, this.height});

  /// The image URL (the value before resolution).
  final String src;

  /// The alternative text. Null if absent.
  final String? alt;

  /// The image title. Null if absent.
  final String? title;

  /// The width specified in HTML (logical pixels). Null if absent.
  final double? width;

  /// The height specified in HTML (logical pixels). Null if absent.
  final double? height;

  @override
  List<Object?> get props => [src, alt, title, width, height];
}

// ---------------------------------------------------------------------------
// Block
// ---------------------------------------------------------------------------

/// Block element.
sealed class MdxBlock extends MdxNode {}

/// How a line is aligned. Used for table columns and the HTML `align` attribute.
enum MdxAlign {
  /// Left-aligned.
  left,

  /// Centered.
  center,

  /// Right-aligned.
  right,
}

/// A paragraph. [align] is set only when specified by the HTML `align` attribute.
final class MdxParagraph extends MdxBlock {
  /// Creates a paragraph of [inlines]. [inlines] holds an unmodifiable copy.
  MdxParagraph(List<MdxInline> inlines, {this.align})
    : inlines = _freeze(inlines);

  /// The inlines in the paragraph.
  final List<MdxInline> inlines;

  /// How the line is aligned. Null if unspecified.
  final MdxAlign? align;

  @override
  List<Object?> get props => [inlines, align];
}

/// A heading. [level] is 1 to 6.
final class MdxHeading extends MdxBlock {
  /// Creates a heading of [level]. [inlines] holds an unmodifiable copy.
  MdxHeading(this.level, List<MdxInline> inlines, {this.align})
    : inlines = _freeze(inlines);

  /// The heading level (1 to 6).
  final int level;

  /// The inlines in the heading.
  final List<MdxInline> inlines;

  /// How the line is aligned. Null if unspecified.
  final MdxAlign? align;

  @override
  List<Object?> get props => [level, inlines, align];
}

/// code block.
final class MdxCodeBlock extends MdxBlock {
  /// Creates a code block of [code]. [language] is the fence language name and
  /// [info] is the rest of the fence info string after it.
  MdxCodeBlock(this.code, {this.language, this.info});

  /// The full text of the code.
  final String code;

  /// The fence language name. Null if absent.
  final String? language;

  /// The fence info string after the language word, trimmed. Null if there is none.
  ///
  /// For ```` ```rust {1,3} ```` this is `{1,3}`.
  final String? info;

  @override
  List<Object?> get props => [code, language, info];
}

/// A blockquote.
final class MdxBlockquote extends MdxBlock {
  /// Creates a blockquote containing [blocks]. [blocks] holds an unmodifiable copy.
  MdxBlockquote(List<MdxBlock> blocks) : blocks = _freeze(blocks);

  /// The blocks in the quote.
  final List<MdxBlock> blocks;

  @override
  List<Object?> get props => [blocks];
}

/// A single list item. [checked] is non-null only for a task list.
final class MdxListItem extends MdxNode {
  /// Creates an item containing [blocks]. [blocks] holds an unmodifiable copy.
  MdxListItem(List<MdxBlock> blocks, {this.checked, this.markerOffset})
    : blocks = _freeze(blocks);

  /// The blocks in the item.
  final List<MdxBlock> blocks;

  /// The check state of a task list. Null for an item that is not a task list.
  final bool? checked;

  /// Where the `[ ]` / `[x]` marker of a task item starts: a UTF-16 offset in the source text
  /// that was handed to the parser (a chunk of the document, when an incremental parser
  /// splits it). Null for an item that is not a task, or when the position is unknown.
  ///
  /// This is a position hint, not part of the value: it is **not** part of `==` and `hashCode`.
  /// Two items that read the same but sit at different places in the document are equal, so
  /// text inserted before an unchanged block does not make the block look changed (the
  /// per-block Widget cache keeps working). Read the current position from the latest parse
  /// result, never from a cached older instance.
  final int? markerOffset;

  /// This item with [markerOffset] replaced.
  MdxListItem withMarkerOffset(int? offset) =>
      MdxListItem(blocks, checked: checked, markerOffset: offset);

  @override
  List<Object?> get props => [blocks, checked];
}

/// A bulleted or numbered list.
final class MdxList extends MdxBlock {
  /// Creates a list. [items] holds an unmodifiable copy.
  MdxList({
    required this.ordered,
    required List<MdxListItem> items,
    this.start = 1,
    this.tight = true,
  }) : items = _freeze(items);

  /// True for a numbered list.
  final bool ordered;

  /// The first number of a numbered list. Defaults to 1.
  final int start;

  /// True for a tight list: no item holds a paragraph block, so the items have no blank
  /// lines between them. Defaults to true for hand-built IR.
  final bool tight;

  /// The list items.
  final List<MdxListItem> items;

  @override
  List<Object?> get props => [ordered, start, tight, items];
}

/// The extent a single table cell occupies (HTML `colspan` and `rowspan`).
///
/// Both are at least 1 and at most [mdxMaxCellSpan].
typedef MdxCellSpan = ({int colSpan, int rowSpan});

/// The extent of a cell with nothing specified (1 x 1).
const MdxCellSpan mdxDefaultCellSpan = (colSpan: 1, rowSpan: 1);

/// The upper limit of [MdxCellSpan]. The parser clamps larger values to this value.
const mdxMaxCellSpan = 100;

bool _isValidSpan(MdxCellSpan span) =>
    span.colSpan >= 1 &&
    span.colSpan <= mdxMaxCellSpan &&
    span.rowSpan >= 1 &&
    span.rowSpan <= mdxMaxCellSpan;

/// Aligns [spans] to [length] entries (all 1 x 1 if empty; otherwise the count must match).
List<MdxCellSpan> _denseSpans(
  List<MdxCellSpan> spans,
  int length,
  String what,
) {
  if (spans.isEmpty) {
    return List.filled(length, mdxDefaultCellSpan);
  }
  if (spans.length != length) {
    throw ArgumentError.value(
      spans,
      what,
      'must be empty or have one entry per cell ($length)',
    );
  }
  for (final span in spans) {
    if (!_isValidSpan(span)) {
      throw ArgumentError.value(
        span,
        what,
        'spans must be between 1 and $mdxMaxCellSpan',
      );
    }
  }
  return spans;
}

/// table.
///
/// A GFM table has no spans. An HTML `<table>` can have `colSpan` / `rowSpan`.
/// A cell's content is a list of inlines; blocks inside a cell (lists or code) are
/// flattened into per-line text (doc/html.md).
///
/// When a cell extends into the rows below through `rowSpan`, the cells in those rows shift
/// to the right by that amount, as in HTML. So a row can have fewer cells than there are columns.
final class MdxTable extends MdxBlock {
  /// [headerSpans] and [rowSpans] are omitted for a table without spans.
  /// When passed, they must be as long as the number of cells in the header (row). A whole row may
  /// also be omitted (an empty list). All-1 x 1 spans are equal to omitting them.
  factory MdxTable({
    required List<MdxAlign?> alignments,
    required List<List<MdxInline>> header,
    required List<List<List<MdxInline>>> rows,
    List<MdxCellSpan> headerSpans = const [],
    List<List<MdxCellSpan>> rowSpans = const [],
  }) {
    if (rowSpans.isNotEmpty && rowSpans.length != rows.length) {
      throw ArgumentError.value(
        rowSpans,
        'rowSpans',
        'must be empty or have one entry per row (${rows.length})',
      );
    }
    var dense = <List<MdxCellSpan>>[
      for (var i = 0; i < rows.length; i++)
        _denseSpans(
          rowSpans.isEmpty ? const [] : rowSpans[i],
          rows[i].length,
          'rowSpans',
        ),
    ];
    var denseHeader = _denseSpans(headerSpans, header.length, 'headerSpans');
    final plain =
        denseHeader.every((s) => s == mdxDefaultCellSpan) &&
        dense.every((row) => row.every((s) => s == mdxDefaultCellSpan));
    if (plain) {
      denseHeader = const [];
      dense = const [];
    }
    return MdxTable._(alignments, header, rows, denseHeader, dense);
  }

  MdxTable._(
    List<MdxAlign?> alignments,
    List<List<MdxInline>> header,
    List<List<List<MdxInline>>> rows,
    List<MdxCellSpan> headerSpans,
    List<List<MdxCellSpan>> rowSpans,
  ) : alignments = _freeze(alignments),
      header = _freeze2(header),
      rows = _freeze3(rows),
      headerSpans = _freeze(headerSpans),
      rowSpans = _freeze2(rowSpans);

  /// The alignment of each column. Null if unspecified.
  final List<MdxAlign?> alignments;

  /// The inlines of each header cell.
  final List<List<MdxInline>> header;

  /// The inlines of each cell, per row.
  final List<List<List<MdxInline>>> rows;

  /// The span of each header cell. Empty for a table without spans.
  final List<MdxCellSpan> headerSpans;

  /// The span of each cell, per row. Empty for a table without spans.
  final List<List<MdxCellSpan>> rowSpans;

  /// True when at least one cell is not 1 x 1.
  bool get hasSpans => headerSpans.isNotEmpty || rowSpans.isNotEmpty;

  /// The span of the [column]-th header cell.
  MdxCellSpan headerSpanAt(int column) =>
      headerSpans.isEmpty ? mdxDefaultCellSpan : headerSpans[column];

  /// The span of the [index]-th cell in row [row].
  MdxCellSpan rowSpanAt(int row, int index) =>
      rowSpans.isEmpty ? mdxDefaultCellSpan : rowSpans[row][index];

  @override
  List<Object?> get props => [alignments, header, rows, headerSpans, rowSpans];
}

/// Horizontal rule.
final class MdxThematicBreak extends MdxBlock {
  @override
  List<Object?> get props => const [];
}

/// An HTML `<details>`.
///
/// [open] is true when the `open` attribute is present, and the block is first rendered expanded.
/// The state the user toggles is kept afterwards.
final class MdxDetails extends MdxBlock {
  /// Creates a `<details>` of [summary] and [blocks]. If [open] is true it starts expanded.
  MdxDetails({
    required List<MdxInline> summary,
    required List<MdxBlock> blocks,
    this.open = false,
  }) : summary = _freeze(summary),
       blocks = _freeze(blocks);

  /// The summary inlines that are always visible.
  final List<MdxInline> summary;

  /// The blocks shown when expanded.
  final List<MdxBlock> blocks;

  /// Whether it is first rendered expanded.
  final bool open;

  @override
  List<Object?> get props => [summary, blocks, open];
}

/// A named block with string attributes, created by an extension or by the parser.
///
/// [inlines] and [blocks] are the fallback shown when there is no builder: [inlines] is rendered
/// as a paragraph, followed by [blocks] stacked vertically. The parser creates the `media` block
/// for HTML `<video>`, `<audio>`, `<iframe>`, `<embed>` and `<object>` (read it with
/// `MarkdownXMedia.of`); extensions create the others.
final class MdxCustomBlock extends MdxBlock {
  /// Creates a custom block of [type]. [attributes], [inlines] and [blocks] hold unmodifiable copies.
  MdxCustomBlock(
    this.type, {
    Map<String, String> attributes = const {},
    List<MdxInline> inlines = const [],
    List<MdxBlock> blocks = const [],
  }) : attributes = Map<String, String>.unmodifiable(attributes),
       inlines = _freeze(inlines),
       blocks = _freeze(blocks);

  /// The name that distinguishes the kind of custom block.
  final String type;

  /// Arbitrary string values.
  final Map<String, String> attributes;

  /// The inlines drawn as a paragraph when there is no builder.
  final List<MdxInline> inlines;

  /// The blocks placed after [inlines] when there is no builder.
  final List<MdxBlock> blocks;

  @override
  List<Object?> get props => [type, attributes, inlines, blocks];
}
