// The bridge from the IR to package:markdown's AST, for MarkdownWidget.builders and
// MarkdownWidget.paddingBuilders (doc/flutter_markdown_compat.md, sections 2.5, 2.6 and 5a).
//
// A top-level block that contains a tag with a registered builder is converted to a fresh
// `md.Element` tree (builders mutate elements). The tree is then walked with the call protocol of
// flutter_markdown's `MarkdownBuilder`: `visitElementBefore`, `visitText` and
// `visitElementAfterWithContext`, in the same order and with the same arguments. The widgets the
// builders return are recorded in an [MdOverlay], keyed by the IR node they replace; the IR
// renderer reads the overlay while it builds the block. A block without a registered tag, and
// every document without builders, never touches this file's conversion.
library;

import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;

import '../extensions/alerts.dart';
import 'element_builder.dart';
import '../extensions/math.dart';
import '../navigation/navigation.dart';
import '../ir/nodes.dart';
import '../style/style_sheet.dart';

/// The widgets that builders returned for one top-level block, keyed by the IR node (by identity)
/// they replace.
final class MdOverlay {
  /// Replaces a whole block: paragraph, heading, list, table, rule, details, custom block.
  final HashMap<Object, Widget> blocks = HashMap.identity();

  /// Replaces the content of a blockquote (the decoration and padding stay).
  final HashMap<Object, Widget> contents = HashMap.identity();

  /// Replaces the content of a list item (the bullet row stays).
  final HashMap<Object, Widget> items = HashMap.identity();

  /// Replaces an inline.
  final HashMap<Object, Widget> inlines = HashMap.identity();

  /// Replaces the summary text of a details.
  final HashMap<Object, Widget> summaries = HashMap.identity();

  /// The widget of an `input` builder, shown before the text of the first paragraph of an item.
  final HashMap<Object, Widget> leading = HashMap.identity();

  /// The result of `visitText` for the first node of a run of text nodes. A null value drops it.
  final HashMap<Object, Widget?> texts = HashMap.identity();

  /// The other nodes of a run whose text went to a builder.
  final HashSet<Object> suppressed = HashSet.identity();

  /// The padding of a text block (paragraph, heading), an image or a rule.
  final HashMap<Object, EdgeInsets> paddings = HashMap.identity();

  /// What builders returned for the body of a code block.
  final HashMap<Object, MdCodeOverlay> codes = HashMap.identity();

  final HashMap<Object, Map<String, Widget>> _cells = HashMap.identity();

  /// The widget that replaces the cell at [row] (-1 for the header) and [column] of [table].
  Widget? cell(MdxTable table, int row, int column) =>
      _cells[table]?['$row:$column'];

  void _putCell(MdxTable table, int row, int column, Widget widget) =>
      (_cells[table] ??= {})['$row:$column'] = widget;
}

/// What builders returned for the body of a code block.
final class MdCodeOverlay {
  /// The result of the `pre` builder.
  Widget? pre;

  /// The result of the `code` builder.
  Widget? code;

  /// Whether the text of the block went to a `pre` builder.
  bool textRouted = false;

  /// The widget the `pre` builder returned from `visitText` (null when it dropped the text).
  Widget? text;

  /// The widget that replaces the scrolling text of the block, or null to keep the default.
  Widget? get body =>
      pre ?? code ?? (textRouted ? (text ?? const SizedBox.shrink()) : null);
}

/// Passes the [MdOverlay] of a top-level block to the widgets below it.
class MdOverlayScope extends InheritedWidget {
  /// Creates a scope.
  const MdOverlayScope({
    super.key,
    required this.overlay,
    required super.child,
  });

  /// The overlay.
  final MdOverlay overlay;

  /// The overlay above [context], if any.
  static MdOverlay? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MdOverlayScope>()?.overlay;

  @override
  bool updateShouldNotify(MdOverlayScope oldWidget) =>
      !identical(overlay, oldWidget.overlay);
}

// ---------------------------------------------------------------------------
// Which tags a block contains
// ---------------------------------------------------------------------------

final Expando<Set<String>> _tagCache = Expando<Set<String>>('mdBridgeTags');

/// The tags that [block] produces (a superset is fine). Cached per block instance.
Set<String> mdBlockTags(MdxBlock block) =>
    _tagCache[block] ??= (_TagCollector().._block(block)).tags;

class _TagCollector {
  final Set<String> tags = {};

  void _block(MdxBlock block) {
    switch (block) {
      case MdxParagraph():
        tags.add('p');
        _inlines(block.inlines);
      case MdxHeading():
        tags.add('h${block.level.clamp(1, 6)}');
        _inlines(block.inlines);
      case MdxCodeBlock():
        tags.addAll(const ['pre', 'code']);
      case MdxBlockquote():
        tags.add('blockquote');
        block.blocks.forEach(_block);
      case MdxList():
        tags.addAll([block.ordered ? 'ol' : 'ul', 'li', 'section', 'p']);
        for (final item in block.items) {
          if (item.checked != null) tags.add('input');
          item.blocks.forEach(_block);
        }
      case MdxTable():
        tags.addAll(const ['table', 'thead', 'tbody', 'tr', 'th', 'td']);
        block.header.forEach(_inlines);
        for (final row in block.rows) {
          row.forEach(_inlines);
        }
      case MdxThematicBreak():
        tags.add('hr');
      case MdxDetails():
        tags.addAll(const ['details', 'summary']);
        _inlines(block.summary);
        block.blocks.forEach(_block);
      case MdxCustomBlock():
        tags.addAll(const ['div', 'p']);
        tags.add(block.type);
        _inlines(block.inlines);
        block.blocks.forEach(_block);
    }
  }

  void _inlines(List<MdxInline> list) {
    for (final inline in list) {
      switch (inline) {
        case MdxText():
        case MdxSoftBreak():
          break;
        case MdxLineBreak():
          tags.add('br');
        case MdxStyled():
          tags.addAll(['sup', 'a', _styleTag(inline.kind)]);
          _inlines(inline.children);
        case MdxLink():
          tags.add('a');
          _inlines(inline.children);
        case MdxImage():
          tags.add('img');
        case MdxSpan():
          tags.add('span');
          _inlines(inline.children);
        case MdxCustomInline():
          tags.add(inline.type);
          _inlines(inline.children);
      }
    }
  }
}

String _styleTag(MdxStyleKind kind) => switch (kind) {
  MdxStyleKind.strong => 'strong',
  MdxStyleKind.emphasis => 'em',
  MdxStyleKind.strikethrough => 'del',
  MdxStyleKind.code => 'code',
  MdxStyleKind.underline => 'u',
  MdxStyleKind.mark => 'mark',
  MdxStyleKind.subscript => 'sub',
  MdxStyleKind.superscript => 'sup',
  MdxStyleKind.keyboard => 'kbd',
  MdxStyleKind.small => 'small',
  MdxStyleKind.cite => 'cite',
  MdxStyleKind.definition => 'dfn',
  MdxStyleKind.variable => 'var',
  MdxStyleKind.sample => 'samp',
  MdxStyleKind.teletype => 'tt',
  MdxStyleKind.big => 'big',
  MdxStyleKind.abbreviation => 'abbr',
  MdxStyleKind.acronym => 'acronym',
};

// ---------------------------------------------------------------------------
// IR to md.Element
// ---------------------------------------------------------------------------

/// How the result of a builder is applied.
enum _Slot {
  /// Nothing to replace (nodes that have no counterpart in the IR renderer).
  none,
  whole,
  contents,
  item,
  pre,
  code,
  inline,
  cell,
  summary,
  input,
}

class _Ref {
  const _Ref(this.slot, this.ir, {this.row = 0, this.column = 0});

  final _Slot slot;
  final Object? ir;
  final int row;
  final int column;
}

/// `md.Node`s to the IR they came from.
class _Tree {
  final HashMap<md.Node, _Ref> refs = HashMap.identity();

  /// The paragraph that a node of an unwrapped (tight list) paragraph came from.
  final HashMap<md.Node, MdxBlock> owners = HashMap.identity();

  /// Elements that are blocks because the IR says so (details, alerts, custom blocks, ...).
  final HashSet<md.Element> forcedBlocks = HashSet.identity();

  /// Text nodes that hold the code of a code block.
  final HashMap<md.Text, MdxCodeBlock> codeText = HashMap.identity();

  /// Text nodes that are runs of IR text nodes.
  final HashMap<md.Text, List<MdxInline>> runs = HashMap.identity();
}

const _taskItemClass = 'task-list-item';
const _footnoteBackrefPrefix = '#fnref-';
const _footnoteRefPrefix = '#fn-';
const _backrefText = '↩';

class _Converter {
  _Converter({required this.headerIds});

  final bool headerIds;
  final _Tree tree = _Tree();

  T _ref<T extends md.Node>(
    T node,
    _Slot slot,
    Object? ir, {
    int row = 0,
    int column = 0,
  }) {
    tree.refs[node] = _Ref(slot, ir, row: row, column: column);
    return node;
  }

  // -- blocks ---------------------------------------------------------------

  List<md.Node> blocks(List<MdxBlock> list) => [for (final b in list) block(b)];

  md.Element block(MdxBlock b) {
    switch (b) {
      case MdxParagraph():
        final el = md.Element('p', inlines(b.inlines, owner: b));
        if (b.align != null) el.attributes['align'] = b.align!.name;
        return _ref(el, _Slot.whole, b);
      case MdxHeading():
        final level = b.level.clamp(1, 6);
        final el = md.Element('h$level', inlines(b.inlines, owner: b));
        if (b.align != null) el.attributes['align'] = b.align!.name;
        if (headerIds) el.generatedId = markdownXSlug(el.textContent);
        return _ref(el, _Slot.whole, b);
      case MdxCodeBlock():
        return _codeBlock(b);
      case MdxBlockquote():
        return _ref(
          md.Element('blockquote', blocks(b.blocks)),
          _Slot.contents,
          b,
        );
      case MdxList():
        return _list(b);
      case MdxTable():
        return _table(b);
      case MdxThematicBreak():
        return _ref(md.Element.empty('hr'), _Slot.whole, b);
      case MdxDetails():
        final summary = _ref(
          md.Element('summary', inlines(b.summary, owner: b)),
          _Slot.summary,
          b,
        );
        tree.forcedBlocks.add(summary);
        final el = md.Element('details', [summary, ...blocks(b.blocks)]);
        if (b.open) el.attributes['open'] = '';
        tree.forcedBlocks.add(el);
        return _ref(el, _Slot.whole, b);
      case MdxCustomBlock():
        return _customBlock(b);
    }
  }

  md.Element _codeBlock(MdxCodeBlock b) {
    final text = b.code.isEmpty ? null : md.Text('${b.code}\n');
    if (text != null) tree.codeText[text] = b;
    final code = md.Element('code', [?text]);
    final language = b.language;
    if (language != null && language.isNotEmpty) {
      code.attributes['class'] = 'language-$language';
    }
    final pre = md.Element('pre', [code]);
    // `info` is the rest of the info string after the language (IR v3).
    final metadata = b.info?.trim();
    if (metadata != null && metadata.isNotEmpty) {
      pre.attributes['data-metadata'] = metadata;
    }
    _ref(code, _Slot.code, b);
    return _ref(pre, _Slot.pre, b);
  }

  md.Element _customBlock(MdxCustomBlock b) {
    md.Element el;
    if (b.type == markdownXAlertType) {
      final kind = markdownXAlertKindOf(b) ?? MarkdownXAlertKind.note;
      final title = md.Element('p', [md.Text(_capitalize(kind.name))])
        ..attributes['class'] = 'markdown-alert-title';
      el = md.Element('div', [title, ...blocks(b.blocks)])
        ..attributes['class'] = 'markdown-alert markdown-alert-${kind.name}';
    } else if (b.type == markdownXMathType) {
      final tex = b.attributes['tex'] ?? '';
      el = md.Element('math', [md.Text(tex)])..attributes.addAll(b.attributes);
    } else {
      el = md.Element(b.type, [
        if (b.inlines.isNotEmpty) md.Element('p', inlines(b.inlines)),
        ...blocks(b.blocks),
      ])..attributes.addAll(b.attributes);
    }
    tree.forcedBlocks.add(el);
    return _ref(el, _Slot.whole, b);
  }

  static String _capitalize(String s) => s[0].toUpperCase() + s.substring(1);

  md.Element _list(MdxList l) {
    final footnotes = _isFootnoteList(l);
    final anyTask = l.items.any((i) => i.checked != null);
    final items = <md.Element>[
      for (final item in l.items) _item(l, item, footnotes),
    ];
    if (l.tight) _unwrapTight(items);
    final el = md.Element(l.ordered ? 'ol' : 'ul', items);
    if (l.ordered && l.start != 1) el.attributes['start'] = '${l.start}';
    if (anyTask) el.attributes['class'] = 'contains-task-list';
    _ref(el, _Slot.whole, l);
    if (!footnotes) return el;
    final section = md.Element('section', [el])
      ..attributes['class'] = 'footnotes';
    tree.forcedBlocks.add(section);
    return _ref(section, _Slot.whole, l);
  }

  md.Element _item(MdxList l, MdxListItem item, bool footnotes) {
    final children = blocks(item.blocks);
    final checked = item.checked;
    if (checked != null) {
      final first = item.blocks.isEmpty ? null : item.blocks.first;
      final input = md.Element.withTag('input')
        ..attributes['type'] = 'checkbox';
      if (checked) input.attributes['checked'] = 'true';
      _ref(input, _Slot.input, first is MdxParagraph ? first : null);
      final firstChild = children.isEmpty ? null : children.first;
      if (firstChild is md.Element && firstChild.tag == 'p') {
        firstChild.children!.insert(0, input);
      } else {
        children.insert(0, input);
      }
    }
    final li = md.Element('li', children);
    if (checked != null) li.attributes['class'] = _taskItemClass;
    if (footnotes) {
      final label = _backrefLabel(item);
      if (label != null) li.attributes['id'] = 'fn-$label';
    }
    return _ref(li, _Slot.item, item);
  }

  /// package:markdown strips the paragraph tags of the items of a tight list
  /// (`md:block_syntaxes/list_syntax.dart:279-306`). The loop is the same, including which node
  /// counts as the previous one.
  void _unwrapTight(List<md.Element> items) {
    for (final item in items) {
      final isTaskList = item.attributes['class'] == _taskItemClass;
      final children = item.children;
      if (children == null) continue;
      md.Node? lastNode;
      for (var i = 0; i < children.length; i++) {
        final child = children[i];
        if (child is md.Element && child.tag == 'p') {
          final content = child.children!;
          if (lastNode is md.Element && !isTaskList) {
            content.insert(0, md.Text('\n'));
          }
          children
            ..removeAt(i)
            ..insertAll(i, content);
        }
        lastNode = child;
      }
    }
  }

  md.Element _table(MdxTable t) {
    final columns = t.alignments.length;
    md.Element cell(
      String tag,
      List<MdxInline> content,
      int row,
      int column,
      MdxCellSpan span,
    ) {
      final el = md.Element(tag, inlines(content));
      final align = column < columns ? t.alignments[column] : null;
      if (align != null) el.attributes['align'] = align.name;
      if (span.colSpan != 1) el.attributes['colspan'] = '${span.colSpan}';
      if (span.rowSpan != 1) el.attributes['rowspan'] = '${span.rowSpan}';
      return _ref(el, _Slot.cell, t, row: row, column: column);
    }

    final children = <md.Node>[];
    if (t.header.isNotEmpty) {
      children.add(
        md.Element('thead', [
          md.Element('tr', [
            for (var c = 0; c < t.header.length; c++)
              cell('th', t.header[c], -1, c, t.headerSpanAt(c)),
          ]),
        ]),
      );
    }
    if (t.rows.isNotEmpty) {
      children.add(
        md.Element('tbody', [
          for (var r = 0; r < t.rows.length; r++)
            md.Element('tr', [
              for (var c = 0; c < t.rows[r].length; c++)
                cell('td', t.rows[r][c], r, c, t.rowSpanAt(r, c)),
              for (var c = t.rows[r].length; c < columns; c++)
                cell('td', const [], r, c, mdxDefaultCellSpan),
            ]),
        ]),
      );
    }
    return _ref(md.Element('table', children), _Slot.whole, t);
  }

  // -- footnotes ------------------------------------------------------------

  /// The footnote definitions at the end of a document: an ordered list whose items all end with
  /// the back reference link that [markdownXAddFootnoteBackrefs] adds.
  static bool _isFootnoteList(MdxList l) =>
      l.ordered &&
      l.items.isNotEmpty &&
      l.items.every((i) => _backrefLabel(i) != null);

  static bool _isBackref(MdxLink link) {
    if (!link.href.startsWith(_footnoteBackrefPrefix) ||
        link.children.length != 1) {
      return false;
    }
    final text = link.children.single;
    return text is MdxText && text.text == _backrefText;
  }

  static String? _backrefLabel(MdxListItem item) {
    if (item.blocks.isEmpty) return null;
    final last = item.blocks.last;
    if (last is! MdxParagraph || last.inlines.isEmpty) return null;
    final link = last.inlines.last;
    if (link is! MdxLink || !_isBackref(link)) return null;
    return link.href.substring(_footnoteBackrefPrefix.length);
  }

  // -- inlines --------------------------------------------------------------

  static bool _beforeBackref(List<MdxInline> list, int i) {
    if (i + 1 >= list.length) return false;
    final next = list[i + 1];
    return next is MdxLink && _isBackref(next);
  }

  /// Adjacent text and soft breaks become one `md.Text` (the newline stays inside the text, as in
  /// package:markdown).
  List<md.Node> inlines(List<MdxInline> list, {MdxBlock? owner}) {
    final out = <md.Node>[];
    var run = <MdxInline>[];
    void flush() {
      if (run.isEmpty) return;
      final text = md.Text(run.map((n) => n is MdxText ? n.text : '\n').join());
      tree.runs[text] = run;
      if (owner != null) tree.owners[text] = owner;
      out.add(text);
      run = <MdxInline>[];
    }

    for (var i = 0; i < list.length; i++) {
      final inline = list[i];
      if (inline is MdxText || inline is MdxSoftBreak) {
        // The space that the footnote back reference adds is its own text node in
        // package:markdown (`md:document.dart:177-192`).
        if (inline is MdxText &&
            inline.text == ' ' &&
            _beforeBackref(list, i)) {
          flush();
        }
        run.add(inline);
        continue;
      }
      flush();
      final el = inlineElement(inline);
      if (owner != null) tree.owners[el] = owner;
      out.add(el);
    }
    flush();
    return out;
  }

  md.Element inlineElement(MdxInline inline) {
    switch (inline) {
      case MdxText():
      case MdxSoftBreak():
        throw StateError('text runs are built by inlines()');
      case MdxLineBreak():
        return _ref(md.Element.empty('br'), _Slot.inline, inline);
      case MdxStyled():
        return _styled(inline);
      case MdxLink():
        final el = md.Element('a', inlines(inline.children));
        el.attributes['href'] = inline.href;
        final title = inline.title;
        if (title != null) el.attributes['title'] = title;
        if (_isBackref(inline)) el.attributes['class'] = 'footnote-backref';
        return _ref(el, _Slot.inline, inline);
      case MdxImage():
        final el = md.Element.empty('img');
        el.attributes['src'] = inline.src;
        el.attributes['alt'] = inline.alt ?? '';
        final title = inline.title;
        if (title != null) el.attributes['title'] = title;
        if (inline.width != null) el.attributes['width'] = '${inline.width}';
        if (inline.height != null) el.attributes['height'] = '${inline.height}';
        return _ref(el, _Slot.inline, inline);
      case MdxSpan():
        final el = md.Element('span', inlines(inline.children));
        final style = _styleAttribute(inline.style);
        if (style.isNotEmpty) el.attributes['style'] = style;
        return _ref(el, _Slot.inline, inline);
      case MdxCustomInline():
        final el = inline.type == markdownXMathType
            ? md.Element('math', [md.Text(inline.attributes['tex'] ?? '')])
            : md.Element(inline.type, inlines(inline.children));
        el.attributes.addAll(inline.attributes);
        return _ref(el, _Slot.inline, inline);
    }
  }

  md.Element _styled(MdxStyled inline) {
    final footnote = _footnoteReference(inline);
    if (footnote != null) {
      final link = inline.children.single as MdxLink;
      final a = md.Element('a', inlines(link.children));
      a.attributes['href'] = link.href;
      a.attributes['id'] = 'fnref-$footnote';
      final sup = md.Element('sup', [_ref(a, _Slot.inline, link)])
        ..attributes['class'] = 'footnote-ref';
      return _ref(sup, _Slot.inline, inline);
    }
    final el = md.Element(_styleTag(inline.kind), inlines(inline.children));
    final title = inline.title;
    if (title != null) el.attributes['title'] = title;
    return _ref(el, _Slot.inline, inline);
  }

  static String? _footnoteReference(MdxStyled inline) {
    if (inline.kind != MdxStyleKind.superscript ||
        inline.children.length != 1) {
      return null;
    }
    final link = inline.children.single;
    if (link is! MdxLink ||
        !link.href.startsWith(_footnoteRefPrefix) ||
        link.children.length != 1) {
      return null;
    }
    final text = link.children.single;
    if (text is! MdxText || int.tryParse(text.text) == null) return null;
    return link.href.substring(_footnoteRefPrefix.length);
  }

  static String _styleAttribute(MdxInlineStyle s) {
    String rgba(int argb) {
      final a = (argb >> 24) & 0xff;
      final rgb = (argb & 0xffffff).toRadixString(16).padLeft(6, '0');
      return a == 0xff
          ? '#$rgb'
          : '#$rgb${a.toRadixString(16).padLeft(2, '0')}';
    }

    final decorations = [
      if (s.underline) 'underline',
      if (s.strikethrough) 'line-through',
    ];
    final parts = [
      if (s.color != null) 'color: ${rgba(s.color!)}',
      if (s.backgroundColor != null)
        'background-color: ${rgba(s.backgroundColor!)}',
      if (s.fontSize != null) 'font-size: ${s.fontSize}px',
      if (s.bold) 'font-weight: bold',
      if (s.italic) 'font-style: italic',
      if (decorations.isNotEmpty) 'text-decoration: ${decorations.join(' ')}',
    ];
    return parts.join('; ');
  }
}

// ---------------------------------------------------------------------------
// The walk (flutter_markdown's MarkdownBuilder protocol)
// ---------------------------------------------------------------------------

const _blockTags = <String>{
  'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'blockquote', 'pre', 'ol',
  'ul', 'hr', 'table', 'thead', 'tbody', 'tr', 'section', //
};

class _Frame {
  _Frame(this.tag);

  final String? tag;
}

class _Walker implements md.NodeVisitor {
  _Walker({
    required this.context,
    required this.sheet,
    required this.builders,
    required this.paddingBuilders,
    required this.tree,
    required this.overlay,
  });

  final BuildContext context;
  final MarkdownStyleSheet sheet;
  final Map<String, MarkdownElementBuilder> builders;
  final Map<String, MarkdownPaddingBuilder> paddingBuilders;
  final _Tree tree;
  final MdOverlay overlay;

  final List<_Frame> _blocks = [_Frame(null)];
  // The merged style of each inline element that is open; the root entry is the block's.
  final List<TextStyle?> _inlines = [];
  bool _hasInlines = false;
  String? _currentBlockTag;
  bool _isInBlockquote = false;

  /// The paragraph or heading whose text is being collected (to attach a padding to it).
  MdxBlock? _ownerHint;
  MdxBlock? _flowOwner;

  Map<String, TextStyle?> get _styles => sheet.styles;

  bool _isBlockTag(String? tag) => _blockTags.contains(tag);

  bool _isBlock(md.Element e) =>
      _isBlockTag(e.tag) ||
      (builders[e.tag]?.isBlockElement() ?? false) ||
      tree.forcedBlocks.contains(e);

  void _addParentInlineIfNeeded(String? tag) {
    if (_hasInlines) return;
    _hasInlines = true;
    _flowOwner = _ownerHint;
    _inlines
      ..clear()
      ..add(
        _isInBlockquote
            ? sheet.blockquote
            : (tag != null ? _styles[tag] : null),
      );
  }

  /// flutter_markdown's `_addAnonymousBlockIfNeeded`: the text collected so far becomes a block,
  /// and the padding builder of the outermost block gets asked for its padding.
  void _flush() {
    if (!_hasInlines) return;
    final tag = _currentBlockTag;
    if (_isBlockTag(tag) && paddingBuilders.containsKey(tag)) {
      final padding = paddingBuilders[tag]!.getPadding();
      final owner = _flowOwner;
      if (owner != null) overlay.paddings[owner] = padding;
    }
    _hasInlines = false;
    _inlines.clear();
    _flowOwner = null;
  }

  @override
  bool visitElementBefore(md.Element element) {
    final tag = element.tag;
    _currentBlockTag ??= tag;
    builders[tag]?.visitElementBefore(element);
    paddingBuilders[tag]?.visitElementBefore(element);

    if (_isBlock(element)) {
      _flush();
      if (tag == 'blockquote') _isInBlockquote = true;
      final ir = tree.refs[element]?.ir;
      _ownerHint = ir is MdxParagraph || ir is MdxHeading
          ? ir as MdxBlock
          : null;
      _blocks.add(_Frame(tag));
    } else {
      if (tag == 'a' && !builders.containsKey('a')) {
        // An empty link is neither drawn nor tappable.
        if (_extractText(element) == null) return false;
      }
      _addParentInlineIfNeeded(_blocks.last.tag);
      if (tag == 'td' && (element.children?.isEmpty ?? false)) {
        element.children!.add(md.Text(''));
      }
      final owner = tree.owners[element];
      if (owner != null) _flowOwner ??= owner;
      final parent = _inlines.isEmpty ? null : _inlines.last;
      final own = _styles[tag];
      _inlines.add(parent != null ? parent.merge(own) : own);
    }
    return true;
  }

  /// `MarkdownBuilder.extractTextFromElement`.
  String? _extractText(md.Node node) {
    if (node is md.Element && (node.children?.isNotEmpty ?? false)) {
      return node.children!
          .map((c) => c is md.Text ? c.text : _extractText(c))
          .join();
    }
    return node is md.Element && node.attributes.isNotEmpty
        ? node.attributes['alt']
        : '';
  }

  @override
  void visitText(md.Text text) {
    final tag = _blocks.last.tag;
    if (tag == null) return;
    _addParentInlineIfNeeded(tag);
    final owner = tree.owners[text];
    if (owner != null) _flowOwner ??= owner;
    final builder = builders[tag];
    if (builder == null) return;
    final widget = builder.visitText(text, _styles[tag]);
    final code = tree.codeText[text];
    if (code != null) {
      (overlay.codes[code] ??= MdCodeOverlay())
        ..textRouted = true
        ..text = widget;
      return;
    }
    final run = tree.runs[text];
    if (run == null) return;
    overlay.texts[run.first] = widget;
    overlay.suppressed.addAll(run.skip(1));
  }

  @override
  void visitElementAfter(md.Element element) {
    final tag = element.tag;
    final ref = tree.refs[element];
    if (_isBlock(element)) {
      _flush();
      _blocks.removeLast();
      // The inline root is gone (flutter_markdown_plus clears it first), so the parent style is null.
      final widget = builders[tag]?.visitElementAfterWithContext(
        context,
        element,
        _styles[tag],
        null,
      );
      if (widget != null && ref != null) _store(ref, widget);
      if (tag == 'blockquote') _isInBlockquote = false;
      if (tag == 'hr' && paddingBuilders.containsKey(tag)) {
        final padding = paddingBuilders[tag]!.getPadding();
        if (ref?.ir != null) overlay.paddings[ref!.ir!] = padding;
      }
    } else {
      if (_inlines.isNotEmpty) _inlines.removeLast();
      if (_inlines.isEmpty) _hasInlines = false;
      final parentStyle = _inlines.isEmpty ? null : _inlines.last;
      final padding = paddingBuilders[tag]?.getPadding();
      final builder = builders[tag];
      if (builder != null) {
        final widget = builder.visitElementAfterWithContext(
          context,
          element,
          _styles[tag],
          parentStyle,
        );
        if (widget != null && ref != null) _store(ref, widget);
      } else if (tag == 'img' &&
          padding != null &&
          padding != EdgeInsets.zero) {
        if (ref?.ir != null) overlay.paddings[ref!.ir!] = padding;
      }
    }
    if (_currentBlockTag == tag) _currentBlockTag = null;
  }

  void _store(_Ref ref, Widget widget) {
    final ir = ref.ir;
    if (ir == null) return;
    switch (ref.slot) {
      case _Slot.none:
        break;
      case _Slot.whole:
        overlay.blocks[ir] = widget;
      case _Slot.contents:
        overlay.contents[ir] = widget;
      case _Slot.item:
        overlay.items[ir] = widget;
      case _Slot.pre:
        (overlay.codes[ir] ??= MdCodeOverlay()).pre = widget;
      case _Slot.code:
        (overlay.codes[ir] ??= MdCodeOverlay()).code = widget;
      case _Slot.inline:
        overlay.inlines[ir] = widget;
      case _Slot.cell:
        overlay._putCell(ir as MdxTable, ref.row, ref.column, widget);
      case _Slot.summary:
        overlay.summaries[ir] = widget;
      case _Slot.input:
        overlay.leading[ir] = widget;
    }
  }
}

/// The number of blocks the bridge converted and walked (debug builds only). For tests.
@visibleForTesting
int debugMdBridgeRuns = 0;

/// Runs the builders of [builders] and [paddingBuilders] over [block].
///
/// Returns null (and calls nothing) when [block] has no tag that a builder is registered for.
/// [headerIds] adds `generatedId` to headings, as `HeaderWithIdSyntax` does.
MdOverlay? bridgeBlock({
  required BuildContext context,
  required MarkdownStyleSheet sheet,
  required Map<String, MarkdownElementBuilder> builders,
  required Map<String, MarkdownPaddingBuilder> paddingBuilders,
  required MdxBlock block,
  bool headerIds = false,
}) {
  final tags = mdBlockTags(block);
  if (!builders.keys.any(tags.contains) &&
      !paddingBuilders.keys.any(tags.contains)) {
    return null;
  }
  assert(() {
    debugMdBridgeRuns++;
    return true;
  }());
  final converter = _Converter(headerIds: headerIds);
  final root = converter.block(block);
  final overlay = MdOverlay();
  root.accept(
    _Walker(
      context: context,
      sheet: sheet,
      builders: builders,
      paddingBuilders: paddingBuilders,
      tree: converter.tree,
      overlay: overlay,
    ),
  );
  return overlay;
}
