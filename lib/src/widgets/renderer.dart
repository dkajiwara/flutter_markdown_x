import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'alert_view.dart';
import '../extensions/alerts.dart';
import 'citation_view.dart';
import '../extensions/citations.dart';
import 'code_header.dart';
import '../flutter_markdown/compat_types.dart';
import '../flutter_markdown/element_builder.dart';
import '../style/extension_style.dart';
import '../style/highlighter.dart';
import '../image/image.dart';
import 'image_view.dart';
import '../flutter_markdown/md_bridge.dart';
import '../ir/nodes.dart';
import 'selection.dart';
import 'span_table.dart';
import '../style/style.dart';
import '../style/style_sheet.dart';

/// Builds the display for a citation (such as `[1]`). Returning null falls back to the default chip.
///
/// [ids] are the ids contained in one citation (`['1', '2']` for `[1, 2]`).
/// [style] is the text style applied at that position.
typedef MarkdownXCitationBuilder = InlineSpan? Function(
  BuildContext context,
  List<String> ids,
  TextStyle style,
);

/// Called when a citation chip is tapped. [id] is the referenced id (`1` for `[1]`).
typedef MarkdownXCitationCallback = void Function(String id);

/// Builds the widget for any block. Returning null falls back to the default display.
///
/// Also called for nested blocks (inside quotes, list items and details). [buildDefault]
/// builds the default widget; if it is not called, no default widget is created (when only
/// replacing, there is no waste; call it only to wrap the default in decoration). Calling it any number of times gives the same appearance.
typedef MarkdownXBlockBuilder = Widget? Function(
  BuildContext context,
  MdxBlock block,
  Widget Function() buildDefault,
);

/// Builds the [InlineSpan] for any inline. Returning null falls back to the default display.
///
/// [style] is the text style applied at the inline's position (excluding the inline's own
/// decoration). [buildDefault] builds the default span; this builder is called again for
/// child inlines. A span substituted inside a link does not get tap handling.
typedef MarkdownXInlineBuilder = InlineSpan? Function(
  BuildContext context,
  MdxInline inline,
  TextStyle style,
  InlineSpan Function() buildDefault,
);

/// The number of times [MdxBlockView] was built. Only counts in debug builds. For tests.
@visibleForTesting
int debugMdxBlockBuildCount = 0;

/// Gives block widgets access to the current settings of the owning widget.
///
/// Block widgets are cached and reused. They read settings through this object at build time,
/// so a newer closure or callback is used whenever a block builds, without the instance
/// change itself rebuilding anything. Only [MdxScope.generation] rebuilds blocks.
abstract interface class MdxRelay {
  /// The effective style sheet (the fallback of the theme merged with the user's sheet).
  MarkdownStyleSheet get styleSheet;

  /// Whether the document is selectable.
  bool get selectable;

  /// Whether `\n` is drawn for a soft line break (otherwise a space).
  bool get softLineBreak;

  /// Whether list items and block columns fit their content.
  bool get fitContent;

  /// How the list bullet is aligned with the item on the cross axis.
  MarkdownListItemCrossAxisAlignment get listItemCrossAxisAlignment;

  /// The directory prefixed to relative image sources.
  String? get imageDirectory;

  /// The syntax highlighter of code blocks, if any.
  SyntaxHighlighter? get syntaxHighlighter;

  /// The deprecated image builder.
  MarkdownImageBuilder? get imageBuilder;

  /// The image builder that receives the full configuration.
  MarkdownSizedImageBuilder? get sizedImageBuilder;

  /// The checkbox builder.
  MarkdownCheckboxBuilder? get checkboxBuilder;

  /// The bullet builder.
  MarkdownBulletBuilder? get bulletBuilder;

  /// Element builders by tag.
  Map<String, MarkdownElementBuilder> get builders;

  /// Padding builders by tag.
  Map<String, MarkdownPaddingBuilder> get paddingBuilders;

  /// Whether headings get a `generatedId` in the `md.Element`s given to builders (`gitHubWeb`).
  bool get generateHeaderIds;

  /// Image provider resolver.
  MarkdownXImageResolver? get imageResolver;

  /// Image loading builder.
  MarkdownXImageLoadingBuilder? get imageLoadingBuilder;

  /// Image error builder.
  MarkdownXImageErrorBuilder? get imageErrorBuilder;

  /// Image tap callback (routed, so the current one is used at event time).
  MarkdownXImageTapCallback? get onTapImage;

  /// Block builder.
  MarkdownXBlockBuilder? get blockBuilder;

  /// Inline builder.
  MarkdownXInlineBuilder? get inlineBuilder;

  /// Citation builder.
  MarkdownXCitationBuilder? get citationBuilder;

  /// Citation tap callback.
  MarkdownXCitationCallback? get onTapCitation;

  /// Text tap callback (only used when [selectable]).
  VoidCallback? get onTapText;

  /// Whether task list checkboxes react to taps (the app gave `onTapCheckbox`).
  bool get checkboxesTappable;

  /// Handles a tap on the checkbox of the task [item]. [owner] is what [MdxBlockOwner] gave for
  /// the top-level block that holds the item. [keepFocus] is true when the checkbox had keyboard
  /// focus: toggling changes the text, so the block is rebuilt and the focus has to be handed to
  /// the new checkbox of the same task (see [takesCheckboxFocus]).
  void handleTapCheckbox(
    Object? owner,
    MdxListItem item, {
    required bool keepFocus,
  });

  /// Whether the new checkbox of [item] should take the keyboard focus (right after a toggle made
  /// with the keyboard replaced the checkbox that had it).
  bool takesCheckboxFocus(Object? owner, MdxListItem item);

  /// Handles a tap on a link.
  void handleTapLink(String text, String? href, String title);
}

/// Passes the [MdxRelay] to block widgets and rebuilds them when [generation] changes.
class MdxScope extends InheritedWidget {
  /// Creates a scope.
  const MdxScope({
    super.key,
    required this.relay,
    required this.generation,
    required super.child,
  });

  /// The current settings.
  final MdxRelay relay;

  /// Bumped by the owner when something that blocks render has changed.
  final int generation;

  /// Returns the scope among the ancestors of [context] and depends on it.
  static MdxScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MdxScope>();
    assert(scope != null, 'MdxScope was not found among the ancestors');
    return scope!;
  }

  @override
  bool updateShouldNotify(MdxScope oldWidget) =>
      generation != oldWidget.generation || !identical(relay, oldWidget.relay);
}

/// Tells the widgets inside a top-level block which entry of the owning widget they belong to.
///
/// A block widget is cached and reused while its block stays equal, while the block's position in
/// the document and in the source text can change. So the owner is an opaque token that the
/// owning State maps to the block's current index when something in the block is tapped.
class MdxBlockOwner extends InheritedWidget {
  /// Creates a scope for the blocks under [child].
  const MdxBlockOwner({super.key, required this.owner, required super.child});

  /// The token of the top-level block.
  final Object owner;

  /// The token among the ancestors of [context], or null (a block shown on its own).
  static Object? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MdxBlockOwner>()?.owner;

  @override
  bool updateShouldNotify(MdxBlockOwner oldWidget) => false;
}

/// The outermost block kind that the text sits in (flutter_markdown's `_currentBlockTag`).
enum MdxRoot {
  /// A paragraph.
  p,

  /// Headings.
  h1,

  /// h2
  h2,

  /// h3
  h3,

  /// h4
  h4,

  /// h5
  h5,

  /// h6
  h6,

  /// An unordered list.
  ul,

  /// An ordered list.
  ol,

  /// A blockquote.
  blockquote,

  /// A code block.
  pre,

  /// Anything else (tables, details, custom blocks).
  other,
}

/// Where a block sits relative to the outermost block.
@immutable
class MdxBlockContext {
  /// Creates a context. A null [root] means the block is the outermost one.
  const MdxBlockContext({this.root, this.inQuote = false, this.listDepth = 0});

  /// The outermost block kind, or null for a top-level block.
  final MdxRoot? root;

  /// Whether the block is inside a blockquote (the blockquote style is the base text style).
  final bool inQuote;

  /// The number of enclosing lists.
  final int listDepth;

  /// The context of the children of a block of kind [self].
  MdxBlockContext descend(
    MdxRoot self, {
    bool quote = false,
    bool list = false,
  }) => MdxBlockContext(
    root: root ?? self,
    inQuote: inQuote || quote,
    listDepth: listDepth + (list ? 1 : 0),
  );
}

/// Renders a single [MdxBlock].
class MdxBlockView extends StatelessWidget {
  /// Creates a widget that renders [block].
  const MdxBlockView({
    super.key,
    required this.block,
    this.blockContext = const MdxBlockContext(),
  });

  /// The block to render.
  final MdxBlock block;

  /// Where the block sits (outermost block kind, blockquote, list depth).
  final MdxBlockContext blockContext;

  @override
  Widget build(BuildContext context) {
    assert(() {
      debugMdxBlockBuildCount++;
      return true;
    }());
    final relay = MdxScope.of(context).relay;
    // A top-level block that contains a tag with a registered builder runs the builders here;
    // nested blocks read the overlay of their top-level block. Without builders nothing is touched.
    MdOverlay? own;
    final MdOverlay? overlay;
    if (blockContext.root != null) {
      overlay = MdOverlayScope.maybeOf(context);
    } else if (relay.builders.isEmpty && relay.paddingBuilders.isEmpty) {
      overlay = null;
    } else {
      overlay = own = bridgeBlock(
        context: context,
        sheet: relay.styleSheet,
        builders: relay.builders,
        paddingBuilders: relay.paddingBuilders,
        block: block,
        headerIds: relay.generateHeaderIds,
      );
    }
    final result = _buildWithBlockBuilder(context, relay, overlay);
    return own == null ? result : MdOverlayScope(overlay: own, child: result);
  }

  Widget _buildWithBlockBuilder(
    BuildContext context,
    MdxRelay relay,
    MdOverlay? overlay,
  ) {
    final builder = relay.blockBuilder;
    if (builder == null) {
      return _selectable(context, _buildDefault(relay, overlay));
    }
    // Nested blocks also go through this build, so they can be replaced at any depth.
    Widget? built;
    final custom = builder(
      context,
      block,
      () => built ??= _buildDefault(relay, overlay),
    );
    return _selectable(
      context,
      custom ?? (built ??= _buildDefault(relay, overlay)),
    );
  }

  /// For selection and copy, wraps blocks in a container that separates them with newlines
  /// (only inside a SelectionArea; horizontal rules contain no text, so they are not wrapped).
  Widget _selectable(BuildContext context, Widget child) =>
      block is MdxThematicBreak ? child : selectionBlock(context, child);

  MdxRoot get _self {
    final block = this.block;
    return switch (block) {
      MdxParagraph() => MdxRoot.p,
      MdxHeading() => switch (block.level.clamp(1, 6)) {
        1 => MdxRoot.h1,
        2 => MdxRoot.h2,
        3 => MdxRoot.h3,
        4 => MdxRoot.h4,
        5 => MdxRoot.h5,
        _ => MdxRoot.h6,
      },
      MdxList() => block.ordered ? MdxRoot.ol : MdxRoot.ul,
      MdxBlockquote() => MdxRoot.blockquote,
      MdxCodeBlock() => MdxRoot.pre,
      _ => MdxRoot.other,
    };
  }

  Widget _buildDefault(MdxRelay relay, MdOverlay? overlay) {
    final sheet = relay.styleSheet;
    final block = this.block;
    final ctx = blockContext;
    final isRoot = ctx.root == null;
    final root = ctx.root ?? _self;
    // A builder's result replaces the whole block (blockquote, code block and list items keep
    // their wrapping and read the overlay themselves).
    final replaced = overlay?.blocks[block];
    switch (block) {
      case MdxParagraph():
        if (replaced != null) return replaced;
        return _textBlock(
          relay,
          block.inlines,
          sheet.p,
          root,
          block.align,
          overlay?.paddings[block] ?? (isRoot ? sheet.pPadding : null),
          leading: overlay?.leading[block],
        );
      case MdxHeading():
        final level = block.level.clamp(1, 6);
        return Semantics(
          header: true,
          child:
              replaced ??
              _textBlock(
                relay,
                block.inlines,
                _headingStyle(sheet, level),
                root,
                block.align,
                overlay?.paddings[block] ??
                    (isRoot ? _headingPadding(sheet, level) : null),
              ),
        );
      case MdxCodeBlock():
        return _CodeBlockView(block: block, root: root);
      case MdxBlockquote():
        return _BlockquoteView(
          block: block,
          blockContext: ctx.descend(MdxRoot.blockquote, quote: true),
        );
      case MdxList():
        if (replaced != null) return replaced;
        return _ListView(
          block: block,
          blockContext: ctx.descend(
            block.ordered ? MdxRoot.ol : MdxRoot.ul,
            list: true,
          ),
        );
      case MdxTable():
        return replaced ?? _TableView(block: block, blockContext: ctx);
      case MdxThematicBreak():
        final rule =
            replaced ?? Container(decoration: sheet.horizontalRuleDecoration);
        final padding = overlay?.paddings[block];
        return padding == null ? rule : Padding(padding: padding, child: rule);
      case MdxDetails():
        if (replaced != null) return replaced;
        return _DetailsView(
          block: block,
          blockContext: ctx.descend(MdxRoot.other),
        );
      case MdxCustomBlock():
        if (replaced != null) return replaced;
        if (block.type == markdownXAlertType) {
          return MdxAlertView(
            block: block,
            blockContext: ctx.descend(MdxRoot.other),
          );
        }
        return _CustomBlockView(
          block: block,
          blockContext: ctx.descend(MdxRoot.other),
        );
    }
  }

  Widget _textBlock(
    MdxRelay relay,
    List<MdxInline> inlines,
    TextStyle? tagStyle,
    MdxRoot root,
    MdxAlign? htmlAlign,
    EdgeInsets? padding, {
    Widget? leading,
  }) {
    final sheet = relay.styleSheet;
    final base =
        (blockContext.inQuote ? sheet.blockquote : tagStyle) ??
        const TextStyle();
    final align = htmlAlign != null
        ? _textAlign(htmlAlign)
        : _wrapToTextAlign(_rootAlignment(sheet, root));
    Widget text = _InlineText(
      inlines: inlines,
      style: base,
      textAlign: align,
      leading: leading,
    );
    if (align != null && align != TextAlign.start) {
      text = SizedBox(width: double.infinity, child: text);
    }
    if (padding != null && padding != EdgeInsets.zero) {
      text = Padding(padding: padding, child: text);
    }
    return text;
  }
}

TextStyle? _headingStyle(MarkdownStyleSheet s, int level) => switch (level) {
  1 => s.h1,
  2 => s.h2,
  3 => s.h3,
  4 => s.h4,
  5 => s.h5,
  _ => s.h6,
};

EdgeInsets? _headingPadding(MarkdownStyleSheet s, int level) => switch (level) {
  1 => s.h1Padding,
  2 => s.h2Padding,
  3 => s.h3Padding,
  4 => s.h4Padding,
  5 => s.h5Padding,
  _ => s.h6Padding,
};

WrapAlignment _rootAlignment(MarkdownStyleSheet s, MdxRoot root) =>
    switch (root) {
      MdxRoot.p => s.textAlign,
      MdxRoot.h1 => s.h1Align,
      MdxRoot.h2 => s.h2Align,
      MdxRoot.h3 => s.h3Align,
      MdxRoot.h4 => s.h4Align,
      MdxRoot.h5 => s.h5Align,
      MdxRoot.h6 => s.h6Align,
      MdxRoot.ul => s.unorderedListAlign,
      MdxRoot.ol => s.orderedListAlign,
      MdxRoot.blockquote => s.blockquoteAlign,
      MdxRoot.pre => s.codeblockAlign,
      MdxRoot.other => WrapAlignment.start,
    };

/// The closest [TextAlign] of a [WrapAlignment]. Null for the default (start).
TextAlign? _wrapToTextAlign(WrapAlignment a) => switch (a) {
  WrapAlignment.start => null,
  WrapAlignment.end => TextAlign.end,
  WrapAlignment.center => TextAlign.center,
  WrapAlignment.spaceBetween => TextAlign.justify,
  WrapAlignment.spaceAround => TextAlign.center,
  WrapAlignment.spaceEvenly => TextAlign.center,
};

/// Opacity of the background of a link that has keyboard focus.
const _focusedLinkAlpha = 0.2;

TextAlign? _textAlign(MdxAlign? align) => switch (align) {
  MdxAlign.left => TextAlign.left,
  MdxAlign.center => TextAlign.center,
  MdxAlign.right => TextAlign.right,
  null => null,
};

/// Lays out nested blocks vertically, separated by `blockSpacing`.
class _BlockColumn extends StatelessWidget {
  const _BlockColumn({required this.blocks, required this.blockContext});

  final List<MdxBlock> blocks;
  final MdxBlockContext blockContext;

  @override
  Widget build(BuildContext context) {
    final relay = MdxScope.of(context).relay;
    final gap = relay.styleSheet.blockSpacing ?? 0;
    return Column(
      crossAxisAlignment: relay.fitContent
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0 && gap > 0) SizedBox(height: gap),
          MdxBlockView(block: blocks[i], blockContext: blockContext),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Inline
// ---------------------------------------------------------------------------

/// The [Focus] debugLabel of a paragraph that contains links.
@visibleForTesting
const mdxLinkFocusLabel = 'MarkdownXLinks';

typedef _LinkTarget = ({String text, String? href, String title});

/// Renders a sequence of inlines as a single [Text.rich].
///
/// Uses one RenderObject per paragraph to keep the widget tree shallow.
/// Only a paragraph with links adds one [Focus], so that the links in the paragraph can be
/// operated by keyboard (select with Tab and Shift+Tab, open with Enter and Space).
class _InlineText extends StatefulWidget {
  const _InlineText({
    required this.inlines,
    required this.style,
    this.textAlign,
    this.leading,
  });

  final List<MdxInline> inlines;
  final TextStyle style;
  final TextAlign? textAlign;

  /// A widget shown before the text (the result of an `input` builder).
  final Widget? leading;

  @override
  State<_InlineText> createState() => _InlineTextState();
}

class _InlineTextState extends State<_InlineText> {
  final List<TapGestureRecognizer> _recognizers = [];

  /// The links drawn in the previous build (in document order).
  final List<_LinkTarget> _links = [];

  /// Node that receives keyboard focus. Only paragraphs with links have one.
  FocusNode? _focusNode;

  /// Index of the focused link, or -1 if none.
  int _focusedLink = -1;

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    _focusNode?.dispose();
    super.dispose();
  }

  void _onFocusChange(bool hasFocus) {
    setState(() {
      // When entering backwards with Shift+Tab, start from the last link.
      _focusedLink = !hasFocus || _links.isEmpty
          ? -1
          : HardwareKeyboard.instance.isShiftPressed
          ? _links.length - 1
          : 0;
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.tab) {
      // Links within a paragraph advance one at a time with Tab / Shift+Tab; at either end,
      // leave it to the normal focus traversal (adjacent paragraphs and widgets).
      final next =
          _focusedLink + (HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
      if (next < 0 || next >= _links.length) return KeyEventResult.ignored;
      setState(() => _focusedLink = next);
      return KeyEventResult.handled;
    }
    final activate =
        event is KeyDownEvent &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.space);
    if (activate && _focusedLink >= 0 && _focusedLink < _links.length) {
      final relay = context.getInheritedWidgetOfExactType<MdxScope>()?.relay;
      final link = _links[_focusedLink];
      relay?.handleTapLink(link.text, link.href, link.title);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    _links.clear();
    final relay = MdxScope.of(context).relay;
    final builder = _SpanBuilder(
      context,
      relay,
      _recognizers,
      links: _links,
      focusedLink: _focusedLink,
      overlay: MdOverlayScope.maybeOf(context),
    );
    final lead = widget.leading;
    Widget text = Text.rich(
      TextSpan(
        children: [
          if (lead != null)
            WidgetSpan(alignment: PlaceholderAlignment.middle, child: lead),
          ...builder.build(widget.inlines, widget.style, null),
        ],
      ),
      style: widget.style,
      textAlign: widget.textAlign,
      textScaler: relay.styleSheet.textScaler,
    );
    if (relay.selectable && relay.onTapText != null) {
      text = GestureDetector(onTap: () => relay.onTapText?.call(), child: text);
    }
    if (_links.isEmpty) return text;
    if (_focusedLink >= _links.length) {
      // When an update reduces the number of links, clamp to the last link and rebuild on the next frame.
      _focusedLink = _links.length - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    return Focus(
      focusNode: _focusNode ??= FocusNode(debugLabel: mdxLinkFocusLabel),
      debugLabel: mdxLinkFocusLabel,
      onFocusChange: _onFocusChange,
      onKeyEvent: _onKeyEvent,
      child: text,
    );
  }
}

/// The style of inline code: the sheet's `code`, with the monospace fallback fonts when it has none.
TextStyle _codeStyle(MarkdownStyleSheet sheet) {
  final code = sheet.code ?? const TextStyle();
  if (code.fontFamilyFallback != null) return code;
  return code.copyWith(
    fontFamily: code.fontFamily ?? MarkdownXDefaults.codeFontFamily,
    fontFamilyFallback: MarkdownXDefaults.codeFontFamilyFallback,
  );
}

/// Converts an [MdxInline] to an [InlineSpan].
class _SpanBuilder {
  _SpanBuilder(
    this._context,
    this._relay,
    this._recognizers, {
    required this.links,
    required this.focusedLink,
    this.overlay,
  });

  /// What builders returned for the block that is being drawn, if any.
  final MdOverlay? overlay;

  final BuildContext _context;
  final MdxRelay _relay;
  final List<TapGestureRecognizer> _recognizers;

  /// Receives the drawn links in document order.
  final List<_LinkTarget> links;

  /// Index of the link that has keyboard focus (-1 if none).
  final int focusedLink;

  MarkdownStyleSheet get _sheet => _relay.styleSheet;

  /// [effective] is the text style actually applied at that position.
  /// [recognizer] is non-null only inside a link.
  List<InlineSpan> build(
    List<MdxInline> inlines,
    TextStyle effective,
    GestureRecognizer? recognizer,
  ) => [for (final inline in inlines) _span(inline, effective, recognizer)];

  InlineSpan _span(
    MdxInline inline,
    TextStyle effective,
    GestureRecognizer? recognizer,
  ) {
    final replacement = _replacement(inline);
    if (replacement != null) return replacement;
    final builder = _relay.inlineBuilder;
    if (builder == null) return _defaultSpan(inline, effective, recognizer);
    InlineSpan? built;
    InlineSpan buildDefault() =>
        built ??= _defaultSpan(inline, effective, recognizer);
    return builder(_context, inline, effective, buildDefault) ?? buildDefault();
  }

  /// The span for a widget a builder returned. A [Text] or [RichText] joins the surrounding text
  /// (flutter_markdown merges them into the text run); any other widget is placed in the line.
  static InlineSpan _spanFor(Widget widget) {
    if (widget is Text) {
      final span = widget.textSpan ?? TextSpan(text: widget.data ?? '');
      return TextSpan(style: widget.style, children: [span]);
    }
    if (widget is RichText) return widget.text;
    return WidgetSpan(alignment: PlaceholderAlignment.middle, child: widget);
  }

  /// The span for an inline that an element builder replaced or whose text it took.
  InlineSpan? _replacement(MdxInline inline) {
    final overlay = this.overlay;
    if (overlay == null) return null;
    final widget = overlay.inlines[inline];
    if (widget != null) return _spanFor(widget);
    if (overlay.texts.containsKey(inline)) {
      final text = overlay.texts[inline];
      // A null result drops the text.
      return text == null ? const TextSpan() : _spanFor(text);
    }
    if (overlay.suppressed.contains(inline)) return const TextSpan();
    return null;
  }

  InlineSpan _defaultSpan(
    MdxInline inline,
    TextStyle effective,
    GestureRecognizer? recognizer,
  ) {
    switch (inline) {
      case MdxText():
        return _leaf(inline.text, recognizer);
      case MdxLineBreak():
        return _leaf('\n', recognizer);
      case MdxSoftBreak():
        return _leaf(_relay.softLineBreak ? '\n' : ' ', recognizer);
      case MdxLink():
        if (_relay.builders.containsKey('a')) {
          // A builder for `a` owns the links: no tap handling (flutter_markdown_plus).
          final linkStyle = _sheet.a ?? const TextStyle();
          return TextSpan(
            style: linkStyle,
            children: build(inline.children, effective.merge(linkStyle), null),
          );
        }
        final target = (
          text: _linkText(inline.children),
          href: inline.href as String?,
          title: inline.title ?? '',
        );
        final tap = TapGestureRecognizer()
          ..onTap = () =>
              _relay.handleTapLink(target.text, target.href, target.title);
        _recognizers.add(tap);
        final focused = links.length == focusedLink;
        links.add(target);
        final linkStyle = focused
            ? _focusedLinkStyle()
            : (_sheet.a ?? const TextStyle());
        return TextSpan(
          style: linkStyle,
          children: build(inline.children, effective.merge(linkStyle), tap),
        );
      case MdxImage():
        final image = _image(inline, effective, recognizer);
        final padding = overlay?.paddings[inline];
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: padding == null
              ? image
              : Padding(padding: padding, child: image),
        );
      case MdxStyled():
        return _styled(inline, effective, recognizer);
      case MdxCustomInline():
        if (inline.type == markdownXCitationType) {
          final ids = markdownXCitationIds(inline);
          if (ids.isNotEmpty) return _citation(ids, effective);
        }
        // If there is no builder or it returns null, draw the children as is.
        return TextSpan(
          children: build(inline.children, effective, recognizer),
        );
      case MdxSpan():
        final delta = _inlineStyle(inline.style);
        return TextSpan(
          style: delta,
          children: build(inline.children, effective.merge(delta), recognizer),
        );
    }
  }

  /// Citation. The chip is a [WidgetSpan], so even inside a link, the chip itself handles taps.
  InlineSpan _citation(List<String> ids, TextStyle effective) {
    final custom = _relay.citationBuilder?.call(_context, ids, effective);
    if (custom != null) return custom;
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: MdxCitationChips(
        ids: ids,
        textStyle: effective,
        style: _sheet.citation ?? _defaultCitation(),
        onTap: _relay.onTapCitation == null
            ? null
            : (id) => _relay.onTapCitation?.call(id),
      ),
    );
  }

  /// Appearance of a link that has keyboard focus (adds a background).
  TextStyle _focusedLinkStyle() {
    final link = _sheet.a ?? const TextStyle();
    return link.copyWith(
      backgroundColor:
          link.color?.withValues(alpha: _focusedLinkAlpha) ??
          Theme.of(_context).focusColor,
    );
  }

  /// The citation chip style when the sheet has none: derived from the color scheme.
  MarkdownXCitationStyle _defaultCitation() {
    final colors = Theme.of(_context).colorScheme;
    return MarkdownXCitationStyle(
      background: colors.secondaryContainer,
      foreground: colors.onSecondaryContainer,
    );
  }

  /// The text of a link as `onTapLink` receives it: the concatenated text of the children.
  static String _linkText(List<MdxInline> inlines) {
    final out = StringBuffer();
    void walk(List<MdxInline> list) {
      for (final inline in list) {
        switch (inline) {
          case MdxText():
            out.write(inline.text);
          case MdxSoftBreak():
            out.write('\n');
          case MdxLineBreak():
            break;
          case MdxImage():
            out.write(inline.alt ?? '');
          case MdxStyled():
            walk(inline.children);
          case MdxLink():
            walk(inline.children);
          case MdxSpan():
            walk(inline.children);
          case MdxCustomInline():
            walk(inline.children);
        }
      }
    }

    walk(inlines);
    return out.toString();
  }

  /// The widget of an image: a flutter_markdown image builder, or the default view. Inside a
  /// link ([recognizer] is the link's tap), tapping the image taps the link, as in flutter_markdown.
  Widget _image(
    MdxImage image,
    TextStyle effective,
    GestureRecognizer? recognizer,
  ) {
    final onTapLink = recognizer is TapGestureRecognizer
        ? recognizer.onTap
        : null;
    // ignore: deprecated_member_use_from_same_package
    final plain = _relay.imageBuilder;
    final sized = _relay.sizedImageBuilder;
    if (sized == null && plain == null) {
      return MdxImageView(
        image: image,
        textStyle: effective,
        onTapLink: onTapLink,
      );
    }
    final source = markdownXParseImageSource(image.src);
    final uri = Uri.tryParse(source.path);
    if (uri == null) return const SizedBox();
    final Widget child;
    if (sized != null) {
      child = sized(
        MarkdownImageConfig(
          uri: uri,
          alt: image.alt,
          title: image.title,
          width: source.width ?? image.width,
          height: source.height ?? image.height,
        ),
      );
    } else {
      child = plain!(uri, image.title, image.alt);
    }
    return onTapLink == null
        ? child
        : GestureDetector(onTap: onTapLink, child: child);
  }

  TextStyle _inlineStyle(MdxInlineStyle style) {
    final color = style.color;
    final backgroundColor = style.backgroundColor;
    final decorations = [
      if (style.underline) TextDecoration.underline,
      if (style.strikethrough) TextDecoration.lineThrough,
    ];
    return TextStyle(
      color: color == null ? null : Color(color),
      backgroundColor: backgroundColor == null ? null : Color(backgroundColor),
      fontSize: style.fontSize,
      fontWeight: style.bold ? FontWeight.w700 : null,
      fontStyle: style.italic ? FontStyle.italic : null,
      decoration: decorations.isEmpty
          ? null
          : TextDecoration.combine(decorations),
    );
  }

  // Recognizers are not inherited by child spans, so attach one to each leaf span.
  TextSpan _leaf(String text, GestureRecognizer? recognizer) => TextSpan(
    text: text,
    recognizer: recognizer,
    mouseCursor: recognizer == null ? null : SystemMouseCursors.click,
  );

  InlineSpan _styled(
    MdxStyled inline,
    TextStyle effective,
    GestureRecognizer? recognizer,
  ) {
    final TextStyle delta;
    switch (inline.kind) {
      case MdxStyleKind.subscript:
        return _script(inline, effective, recognizer, superscript: false);
      case MdxStyleKind.superscript:
        return _script(inline, effective, recognizer, superscript: true);
      case MdxStyleKind.strong:
        delta = _sheet.strong ?? const TextStyle(fontWeight: FontWeight.w700);
      case MdxStyleKind.emphasis:
      case MdxStyleKind.cite:
      case MdxStyleKind.definition:
      case MdxStyleKind.variable:
        // HTML default rendering: `cite, dfn, em, i, var { font-style: italic }`.
        delta = _sheet.em ?? const TextStyle(fontStyle: FontStyle.italic);
      case MdxStyleKind.strikethrough:
        delta =
            _sheet.del ??
            const TextStyle(decoration: TextDecoration.lineThrough);
      case MdxStyleKind.underline:
        delta = const TextStyle(decoration: TextDecoration.underline);
      case MdxStyleKind.code:
      case MdxStyleKind.keyboard:
        delta = _codeStyle(_sheet);
      case MdxStyleKind.mark:
        delta =
            _sheet.mark ??
            TextStyle(
              backgroundColor: Theme.of(_context).colorScheme.tertiaryContainer,
            );
      case MdxStyleKind.sample:
      case MdxStyleKind.teletype:
        // HTML default rendering: `samp, tt { font-family: monospace }`, no background box.
        final code = _codeStyle(_sheet);
        delta = TextStyle(
          fontFamily: code.fontFamily,
          fontFamilyFallback: code.fontFamilyFallback,
        );
      case MdxStyleKind.small:
        delta = TextStyle(
          fontSize: _fontSize(effective) * MarkdownXDefaults.smallFontScale,
        );
      case MdxStyleKind.big:
        delta = TextStyle(
          fontSize: _fontSize(effective) * MarkdownXDefaults.bigFontScale,
        );
      case MdxStyleKind.abbreviation:
      case MdxStyleKind.acronym:
        // HTML default rendering: `abbr[title], acronym[title] { text-decoration: dotted underline }`.
        final title = inline.title;
        delta = title == null || title.isEmpty
            ? const TextStyle()
            : const TextStyle(
                decoration: TextDecoration.underline,
                decorationStyle: TextDecorationStyle.dotted,
              );
    }
    return TextSpan(
      style: delta,
      children: build(inline.children, effective.merge(delta), recognizer),
    );
  }

  double _fontSize(TextStyle style) =>
      style.fontSize ?? MarkdownXDefaults.fallbackFontSize;

  /// Superscript and subscript. TextStyle cannot shift the baseline, so the shrunken text
  /// is put in a [WidgetSpan] and aligned to the top of the line (superscript) or the bottom
  /// (subscript). A Transform for shifting the position is not used (it would break the
  /// selection order and misplace the copied text).
  InlineSpan _script(
    MdxStyled inline,
    TextStyle effective,
    GestureRecognizer? recognizer, {
    required bool superscript,
  }) {
    final tag = _sheet.superscriptFontFeatureTag;
    if (superscript && tag != null) {
      // flutter_markdown draws superscript with font features.
      return TextSpan(
        style: TextStyle(
          fontFeatures: [
            const FontFeature.enable('sups'),
            FontFeature.enable(tag),
          ],
        ),
        children: build(inline.children, effective, recognizer),
      );
    }
    final fontSize = _fontSize(effective);
    final scriptStyle = effective.copyWith(
      fontSize: fontSize * MarkdownXDefaults.scriptFontScale,
    );
    return WidgetSpan(
      alignment: superscript
          ? PlaceholderAlignment.top
          : PlaceholderAlignment.bottom,
      child: Text.rich(
        TextSpan(children: build(inline.children, scriptStyle, recognizer)),
        style: scriptStyle,
        textScaler: _sheet.textScaler,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Block
// ---------------------------------------------------------------------------

class _CodeBlockView extends StatelessWidget {
  const _CodeBlockView({required this.block, required this.root});

  final MdxCodeBlock block;
  final MdxRoot root;

  @override
  Widget build(BuildContext context) {
    final relay = MdxScope.of(context).relay;
    final sheet = relay.styleSheet;
    final colors = sheet.codeSyntax;
    final highlighter = relay.syntaxHighlighter;
    var textStyle = (sheet.p ?? const TextStyle()).merge(_codeStyle(sheet));
    final foreground = colors?.foreground;
    if (foreground != null) textStyle = textStyle.copyWith(color: foreground);
    Decoration? decoration = sheet.codeblockDecoration;
    final background = colors?.background;
    if (background != null) {
      // The block background replaces the decoration color, so glyphs get none of their own.
      textStyle = textStyle.copyWith(backgroundColor: Colors.transparent);
      if (decoration is BoxDecoration) {
        decoration = decoration.copyWith(color: background);
      } else {
        decoration = BoxDecoration(color: background);
      }
    }
    final textAlign = _wrapToTextAlign(sheet.codeblockAlign);
    final Widget code;
    if (highlighter != null) {
      // flutter_markdown semantics: one trailing newline is removed, the span is used as is.
      final source = block.code.replaceAll(RegExp(r'\n$'), '');
      code = Text.rich(
        highlighter.format(source),
        style: textStyle,
        textAlign: textAlign,
        textScaler: sheet.textScaler,
      );
    } else {
      final tokens = colors == null
          ? null
          : highlightCode(block.code, block.language);
      code = _codeText(
        context,
        block.code,
        tokens,
        textStyle,
        colors,
        textAlign,
        sheet.textScaler,
      );
    }
    // A `pre` or `code` builder's widget replaces the scrolling text; the decoration stays.
    final body =
        MdOverlayScope.maybeOf(context)?.codes[block]?.body ??
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: sheet.codeblockPadding,
          child: code,
        );
    final options = sheet.codeBlockOptions ?? const MarkdownXCodeBlockOptions();
    final hasHeader = CodeBlockHeader.isNeeded(options, block.language);
    return Container(
      width: double.infinity,
      clipBehavior: Clip.hardEdge,
      decoration: decoration,
      // Code is always read left to right regardless of writing direction. Horizontal scrolling also starts at the left edge.
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: hasHeader
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: CodeBlockHeader(
                      options: options,
                      language: block.language,
                      code: block.code,
                      color:
                          foreground ??
                          Theme.of(context).colorScheme.onSurfaceVariant,
                      textStyle: textStyle,
                    ),
                  ),
                  body,
                ],
              )
            : body,
      ),
    );
  }

  /// Widget that displays code.
  ///
  /// Putting a huge string in a single `Text` makes layout time grow nearly with the square of
  /// the number of lines (about 15 seconds for 10,000 lines). Code longer than
  /// [MarkdownXDefaults.codeChunkLines] lines is split into `Text` widgets of that many lines
  /// each and stacked vertically (layout is then proportional to the line count). The appearance (line height, color) is the same as without splitting.
  Widget _codeText(
    BuildContext context,
    String code,
    List<MdxCodeToken>? tokens,
    TextStyle textStyle,
    MarkdownXSyntaxColors? colors,
    TextAlign? textAlign,
    TextScaler? textScaler,
  ) {
    TextSpan span(String text, MdxCodeTokenKind kind) =>
        TextSpan(text: text, style: _tokenStyle(kind, colors));
    final source = tokens ?? [MdxCodeToken(MdxCodeTokenKind.plain, code)];
    const chunkLines = MarkdownXDefaults.codeChunkLines;
    // Count the lines. The newline at a chunk boundary is not displayed (so no gap opens between lines).
    final chunks = <List<TextSpan>>[];
    var current = <TextSpan>[];
    var lines = 1;
    for (final token in source) {
      var rest = token.text;
      while (true) {
        final newline = rest.indexOf('\n');
        if (newline == -1) {
          if (rest.isNotEmpty) current.add(span(rest, token.kind));
          break;
        }
        if (lines == chunkLines) {
          if (newline > 0) {
            current.add(span(rest.substring(0, newline), token.kind));
          }
          chunks.add(current);
          current = <TextSpan>[];
          lines = 1;
        } else {
          current.add(span(rest.substring(0, newline + 1), token.kind));
          lines++;
        }
        rest = rest.substring(newline + 1);
      }
    }
    chunks.add(current);
    if (chunks.length == 1) {
      return tokens == null
          ? Text(
              code,
              style: textStyle,
              textAlign: textAlign,
              textScaler: textScaler,
            )
          : Text.rich(
              TextSpan(children: chunks.single),
              style: textStyle,
              textAlign: textAlign,
              textScaler: textScaler,
            );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The newline at a chunk boundary is not included in the Text, so add a
        // newline before the chunk when copying.
        for (final chunk in chunks)
          selectionBlock(
            context,
            Text.rich(
              TextSpan(children: chunk),
              style: textStyle,
              textAlign: textAlign,
              textScaler: textScaler,
            ),
          ),
      ],
    );
  }

  TextStyle? _tokenStyle(MdxCodeTokenKind kind, MarkdownXSyntaxColors? colors) {
    if (colors == null) return null;
    final color = switch (kind) {
      MdxCodeTokenKind.plain => null,
      MdxCodeTokenKind.keyword => colors.keyword,
      MdxCodeTokenKind.string => colors.string,
      MdxCodeTokenKind.comment => colors.comment,
      MdxCodeTokenKind.number => colors.number,
    };
    return color == null ? null : TextStyle(color: color);
  }
}

/// The [MdxCustomBlock] used when there is no builder. Lays out its inlines as a paragraph, followed by its blocks.
class _CustomBlockView extends StatelessWidget {
  const _CustomBlockView({required this.block, required this.blockContext});

  final MdxCustomBlock block;
  final MdxBlockContext blockContext;

  @override
  Widget build(BuildContext context) {
    final relay = MdxScope.of(context).relay;
    final sheet = relay.styleSheet;
    final paragraphStyle =
        (blockContext.inQuote ? sheet.blockquote : sheet.p) ??
        const TextStyle();
    final gap = sheet.blockSpacing ?? 0;
    return Column(
      crossAxisAlignment: relay.fitContent
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (block.inlines.isNotEmpty)
          _InlineText(inlines: block.inlines, style: paragraphStyle),
        if (block.inlines.isNotEmpty && block.blocks.isNotEmpty)
          SizedBox(height: gap),
        if (block.blocks.isNotEmpty)
          _BlockColumn(blocks: block.blocks, blockContext: blockContext),
      ],
    );
  }
}

class _BlockquoteView extends StatelessWidget {
  const _BlockquoteView({required this.block, required this.blockContext});

  final MdxBlockquote block;
  final MdxBlockContext blockContext;

  @override
  Widget build(BuildContext context) {
    final sheet = MdxScope.of(context).relay.styleSheet;
    return DecoratedBox(
      decoration: sheet.blockquoteDecoration ?? const BoxDecoration(),
      child: Padding(
        padding: sheet.blockquotePadding ?? EdgeInsets.zero,
        child:
            MdOverlayScope.maybeOf(context)?.contents[block] ??
            _BlockColumn(blocks: block.blocks, blockContext: blockContext),
      ),
    );
  }
}

const _bulletMarker = '•';
const _checkedIcon = Icons.check_box;
const _uncheckedIcon = Icons.check_box_outline_blank;

class _ListView extends StatelessWidget {
  const _ListView({required this.block, required this.blockContext});

  final MdxList block;

  /// The context of the item contents (already descended into this list).
  final MdxBlockContext blockContext;

  @override
  Widget build(BuildContext context) {
    final relay = MdxScope.of(context).relay;
    final sheet = relay.styleSheet;
    final items = block.items;
    final gap = sheet.listItemSpacing ?? sheet.blockSpacing ?? 0;
    final bulletPadding = sheet.listBulletPadding ?? EdgeInsets.zero;
    final alignStart =
        relay.listItemCrossAxisAlignment ==
        MarkdownListItemCrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: relay.fitContent
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0 && gap > 0) SizedBox(height: gap),
          _ListItemAnchor(
            list: block,
            index: i,
            child: Row(
              mainAxisSize: relay.fitContent
                  ? MainAxisSize.min
                  : MainAxisSize.max,
              textBaseline: alignStart ? null : TextBaseline.alphabetic,
              crossAxisAlignment: alignStart
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.baseline,
              children: [
                SizedBox(
                  width: (sheet.listIndent ?? 0) + bulletPadding.horizontal,
                  child: _marker(context, relay, items[i], i, bulletPadding),
                ),
                Flexible(
                  fit: relay.fitContent ? FlexFit.loose : FlexFit.tight,
                  // If there is a marker (text), copy it in the form "• body" or "1. body".
                  child: selectionBlock(
                    context,
                    MdOverlayScope.maybeOf(context)?.items[items[i]] ??
                        _BlockColumn(
                          blocks: items[i].blocks,
                          blockContext: blockContext,
                        ),
                    separator: items[i].checked == null
                        ? mdxSelectionMarkerSeparator
                        : mdxSelectionBlockSeparator,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _marker(
    BuildContext context,
    MdxRelay relay,
    MdxListItem item,
    int index,
    EdgeInsets bulletPadding,
  ) {
    final sheet = relay.styleSheet;
    final checked = item.checked;
    if (checked != null) {
      final builder = relay.checkboxBuilder;
      // Only a task whose place in the source is known can be toggled.
      final tappable = relay.checkboxesTappable && item.markerOffset != null;
      final owner = MdxBlockOwner.maybeOf(context);
      void tap(bool keepFocus) =>
          relay.handleTapCheckbox(owner, item, keepFocus: keepFocus);
      bool takesFocus() => relay.takesCheckboxFocus(owner, item);
      if (builder != null) {
        final custom = builder(checked);
        return tappable
            ? _TaskCheckbox(
                checked: checked,
                onTap: tap,
                takesFocus: takesFocus,
                child: custom,
              )
            : custom;
      }
      final style = sheet.checkbox;
      final icon = Icon(
        checked ? _checkedIcon : _uncheckedIcon,
        size: style?.fontSize,
        color: style?.color,
      );
      if (tappable) {
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: _TaskCheckbox(
            checked: checked,
            onTap: tap,
            takesFocus: takesFocus,
            focusColor: style?.color,
            child: Padding(padding: bulletPadding, child: icon),
          ),
        );
      }
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: bulletPadding,
          child: Semantics(
            checked: checked,
            excludeSemantics: true,
            child: icon,
          ),
        ),
      );
    }
    final bulletIndex = block.ordered ? block.start - 1 + index : index;
    final builder = relay.bulletBuilder;
    final Widget bullet;
    if (builder != null) {
      bullet = builder(
        MarkdownBulletParameters(
          index: bulletIndex,
          style: block.ordered
              ? BulletStyle.orderedList
              : BulletStyle.unorderedList,
          nestLevel: blockContext.listDepth - 1,
        ),
      );
    } else if (block.ordered) {
      bullet = Text(
        '${bulletIndex + 1}.',
        textAlign: TextAlign.end,
        style: sheet.listBullet,
        textScaler: sheet.textScaler,
      );
    } else {
      bullet = Text(
        _bulletMarker,
        textAlign: TextAlign.center,
        style: sheet.listBullet,
        textScaler: sheet.textScaler,
      );
    }
    return selectionBlock(
      context,
      Padding(padding: bulletPadding, child: bullet),
    );
  }
}

final _taskShortcuts = <ShortcutActivator, Intent>{
  const SingleActivator(LogicalKeyboardKey.space): const ActivateIntent(),
  const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
  const SingleActivator(LogicalKeyboardKey.numpadEnter): const ActivateIntent(),
};

/// Makes a task list checkbox interactive: a tap and Space / Enter call [onTap], it can take
/// keyboard focus (with a ring), and it is exposed as a checkbox with its state and a tap action.
///
/// It wraps the checkbox, whichever widget that is (the default icon or the app's
/// `checkboxBuilder` result), and replaces the semantics of what is inside it.
class _TaskCheckbox extends StatefulWidget {
  const _TaskCheckbox({
    required this.checked,
    required this.onTap,
    required this.takesFocus,
    required this.child,
    this.focusColor,
  });

  final bool checked;

  /// Called on a tap and on Space / Enter. The argument says whether the checkbox had the keyboard focus.
  final void Function(bool hadFocus) onTap;

  /// Asked once when the checkbox is created: whether it replaces the focused checkbox of the
  /// task that was just toggled with the keyboard (a toggle rebuilds the block).
  final bool Function() takesFocus;
  final Widget child;

  /// The color of the focus ring. The text color when null.
  final Color? focusColor;

  @override
  State<_TaskCheckbox> createState() => _TaskCheckboxState();
}

class _TaskCheckboxState extends State<_TaskCheckbox> {
  final FocusNode _node = FocusNode(debugLabel: 'flutter_markdown_x.task');
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    if (widget.takesFocus()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _node.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  void _activate() => widget.onTap(_node.hasFocus);

  @override
  Widget build(BuildContext context) {
    final ringColor =
        widget.focusColor ??
        DefaultTextStyle.of(context).style.color ??
        const Color(0xFF000000);
    return Semantics(
      container: true,
      checked: widget.checked,
      focusable: true,
      focused: _focused,
      onTap: _activate,
      excludeSemantics: true,
      child: FocusableActionDetector(
        focusNode: _node,
        mouseCursor: SystemMouseCursors.click,
        shortcuts: _taskShortcuts,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: _activate,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: _focused ? Border.all(color: ringColor, width: 2) : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _TableView extends StatelessWidget {
  const _TableView({required this.block, required this.blockContext});

  final MdxTable block;
  final MdxBlockContext blockContext;

  @override
  Widget build(BuildContext context) {
    final sheet = MdxScope.of(context).relay.styleSheet;
    final overlay = MdOverlayScope.maybeOf(context);
    final base =
        (blockContext.inQuote ? sheet.blockquote : sheet.tableBody) ??
        const TextStyle();
    final headerStyle = base.merge(sheet.tableHead);
    final width = sheet.tableColumnWidth ?? const FlexColumnWidth();
    if (block.hasSpans) {
      // Flutter's Table cannot span cells, so it is drawn with a custom layout (always scrolls).
      return _TableScroller(
        padding: sheet.tablePadding,
        thumbVisibility: sheet.tableScrollbarThumbVisibility,
        child: selectionBlock(
          context,
          _spanTable(context, sheet, base, headerStyle, overlay),
        ),
      );
    }
    final table = selectionBlock(
      context,
      Table(
        defaultColumnWidth: width,
        defaultVerticalAlignment: sheet.tableVerticalAlignment,
        border: sheet.tableBorder,
        children: [
          if (block.header.isNotEmpty)
            _row(
              context,
              block.header,
              headerStyle,
              sheet.tableHeadCellsPadding ?? sheet.tableCellsPadding,
              sheet.tableHeadCellsDecoration ?? sheet.tableCellsDecoration,
              header: true,
              sheet: sheet,
              overlay: overlay,
              rowIndex: -1,
            ),
          for (var i = 0; i < block.rows.length; i++)
            _row(
              context,
              block.rows[i],
              base,
              sheet.tableCellsPadding,
              i.isOdd ? sheet.tableCellsDecoration : null,
              header: false,
              sheet: sheet,
              overlay: overlay,
              rowIndex: i,
            ),
        ],
      ),
    );
    if (width is FixedColumnWidth || width is IntrinsicColumnWidth) {
      return _TableScroller(
        padding: sheet.tablePadding,
        thumbVisibility: sheet.tableScrollbarThumbVisibility,
        child: table,
      );
    }
    return table;
  }

  /// A single cell. When copying, cells within a row are separated by tabs and rows by newlines.
  Widget _cell(
    BuildContext context,
    List<MdxInline> inlines,
    TextStyle textStyle,
    EdgeInsets? padding,
    int column, {
    required bool firstInRow,
    required TextAlign defaultAlign,
    Widget? replacement,
  }) => selectionBlock(
    context,
    Padding(
      padding: padding ?? EdgeInsets.zero,
      // A td or th builder's widget replaces the content of the cell.
      child:
          replacement ??
          _InlineText(
            inlines: inlines,
            style: textStyle,
            textAlign:
                _textAlign(
                  column < block.alignments.length
                      ? block.alignments[column]
                      : null,
                ) ??
                defaultAlign,
          ),
    ),
    separator: firstInRow
        ? mdxSelectionBlockSeparator
        : mdxSelectionCellSeparator,
  );

  TableRow _row(
    BuildContext context,
    List<List<MdxInline>> cells,
    TextStyle textStyle,
    EdgeInsets? padding,
    Decoration? decoration, {
    required bool header,
    required MarkdownStyleSheet sheet,
    required MdOverlay? overlay,
    required int rowIndex,
  }) {
    final columnCount = block.alignments.length;
    return TableRow(
      decoration: decoration,
      children: [
        // Table requires every row to have the same number of columns, so pad the missing ones with empty cells.
        for (var i = 0; i < columnCount; i++)
          _cell(
            context,
            i < cells.length ? cells[i] : const [],
            textStyle,
            padding,
            i,
            firstInRow: i == 0,
            replacement: overlay?.cell(block, rowIndex, i),
            defaultAlign: header
                ? (sheet.tableHeadAlign ?? TextAlign.start)
                : TextAlign.start,
          ),
      ],
    );
  }

  Widget _spanTable(
    BuildContext context,
    MarkdownStyleSheet sheet,
    TextStyle cellStyle,
    TextStyle headerStyle,
    MdOverlay? overlay,
  ) {
    final grid = placeSpanCells(block);
    final children = <Widget>[];
    var index = 0;
    var lastRow = -1;
    var column = 0;
    var bodyRow = -1;
    void add(List<MdxInline> inlines, TextStyle textStyle, bool header) {
      final placement = grid.cells[index++];
      children.add(
        _cell(
          context,
          inlines,
          textStyle,
          header
              ? (sheet.tableHeadCellsPadding ?? sheet.tableCellsPadding)
              : sheet.tableCellsPadding,
          placement.column,
          firstInRow: placement.row != lastRow,
          replacement: overlay?.cell(block, header ? -1 : bodyRow, column),
          defaultAlign: header
              ? (sheet.tableHeadAlign ?? TextAlign.start)
              : TextAlign.start,
        ),
      );
      lastRow = placement.row;
      column++;
    }

    for (final cell in block.header) {
      add(cell, headerStyle, true);
    }
    for (final row in block.rows) {
      bodyRow++;
      column = 0;
      for (final cell in row) {
        add(cell, cellStyle, false);
      }
    }
    return SpanTable(
      placements: grid.cells,
      rows: grid.rows,
      columns: grid.columns,
      borderColor: sheet.tableBorder?.top.color ?? Colors.transparent,
      children: children,
    );
  }
}

/// A horizontal scroll view with a scrollbar for tables that are wider than the available width.
class _TableScroller extends StatefulWidget {
  const _TableScroller({
    required this.child,
    required this.padding,
    required this.thumbVisibility,
  });

  final Widget child;
  final EdgeInsets? padding;
  final bool? thumbVisibility;

  @override
  State<_TableScroller> createState() => _TableScrollerState();
}

class _TableScrollerState extends State<_TableScroller> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _controller,
    thumbVisibility: widget.thumbVisibility,
    child: SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      padding: widget.padding,
      child: widget.child,
    ),
  );
}

const _detailsOpenIcon = Icons.arrow_drop_down;
const _detailsClosedIcon = Icons.arrow_right;

class _DetailsView extends StatefulWidget {
  const _DetailsView({required this.block, required this.blockContext});

  final MdxDetails block;
  final MdxBlockContext blockContext;

  @override
  State<_DetailsView> createState() => _DetailsViewState();
}

class _DetailsViewState extends State<_DetailsView> {
  late bool _open = widget.block.open;

  /// Opens it if closed. Returns true if it was opened.
  bool openIfClosed() {
    if (_open) return false;
    setState(() => _open = true);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final relay = MdxScope.of(context).relay;
    final sheet = relay.styleSheet;
    final summaryStyle =
        (widget.blockContext.inQuote ? sheet.blockquote : sheet.p) ??
        const TextStyle();
    final fontSize =
        summaryStyle.fontSize ?? MarkdownXDefaults.fallbackFontSize;
    final indent = sheet.listIndent ?? 0;
    return Column(
      crossAxisAlignment: relay.fitContent
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The summary is a button. Include the expanded state in the screen-reader announcement.
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: [
                SizedBox(
                  width: indent,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    // arrow_right uses matchTextDirection, so its direction flips in RTL.
                    child: Icon(
                      _open ? _detailsOpenIcon : _detailsClosedIcon,
                      size: fontSize * (summaryStyle.height ?? 1),
                      color: summaryStyle.color,
                    ),
                  ),
                ),
                Expanded(
                  child:
                      MdOverlayScope.maybeOf(context)
                          ?.summaries[widget.block] ??
                      _InlineText(
                        inlines: widget.block.summary,
                        style: summaryStyle,
                      ),
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: indent,
              top: sheet.listItemSpacing ?? sheet.blockSpacing ?? 0,
            ),
            child: _BlockColumn(
              blocks: widget.block.blocks,
              blockContext: widget.blockContext,
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Finding the destination of internal links
// ---------------------------------------------------------------------------

/// A marker that makes the position of a list item findable as a destination. It does not change the appearance.
class _ListItemAnchor extends StatelessWidget {
  const _ListItemAnchor({
    required this.list,
    required this.index,
    required this.child,
  });

  final MdxList list;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// The first Element under [root] that satisfies [test]. [root] itself is not included.
Element? mdxFindElement(Element root, bool Function(Element) test) {
  Element? found;
  void visit(Element element) {
    if (found != null) return;
    if (test(element)) {
      found = element;
      return;
    }
    element.visitChildren(visit);
  }

  root.visitChildren(visit);
  return found;
}

/// The Element of the [MdxBlockView] that is rendering [block] (the same instance).
Element? mdxFindBlockView(Element root, MdxBlock block) => mdxFindElement(
  root,
  (e) =>
      e.widget is MdxBlockView &&
      identical((e.widget as MdxBlockView).block, block),
);

/// The Element of the [index]th item of [list].
Element? mdxFindListItem(Element root, MdxList list, int index) =>
    mdxFindElement(root, (e) {
      final widget = e.widget;
      return widget is _ListItemAnchor &&
          identical(widget.list, list) &&
          widget.index == index;
    });

/// If [blockView] is a `details` and closed, opens it. Returns true if it was opened.
bool mdxOpenDetails(Element blockView) {
  final inner = mdxFindElement(
    blockView,
    (e) => e is StatefulElement && e.state is _DetailsViewState,
  );
  if (inner is! StatefulElement) return false;
  return (inner.state as _DetailsViewState).openIfClosed();
}
