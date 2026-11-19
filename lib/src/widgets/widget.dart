import 'dart:async';
import 'dart:math';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';

import '../extensions/alerts.dart';
import '../parser/backend.dart' as selected;
import '../flutter_markdown/compat_types.dart';
import '../navigation/controller.dart';
import '../flutter_markdown/element_builder.dart';
import '../extensions/emoji.dart';
import '../extensions/extension.dart';
import '../image/image.dart';
import '../parser/incremental_parser.dart';
import '../navigation/navigation.dart';
import '../ir/nodes.dart';
import '../ir/task.dart';
import '../ir/task_markers.dart';
import '../parser/parser_status.dart';
import 'renderer.dart';
import 'selection.dart';
import '../style/style_sheet.dart';
import '../parser/syntax_compat.dart';

/// A base class for widgets that parse and display Markdown.
///
/// Supports CommonMark and GitHub Flavored Markdown. The constructor follows
/// `flutter_markdown`'s `MarkdownWidget`; the parameters after [softLineBreak] are extensions of
/// this package.
///
/// Parsing and building are lazy and cached per block: when [data] changes, only the blocks whose
/// content changed are rebuilt. Objects created inside `build()` (a style sheet, a builders map,
/// closures) do not invalidate the cache; see doc/performance.md.
///
/// While the parser (Rust) is unavailable (before the web WASM is initialized, a missing binary,
/// and so on), [data] is shown as the raw string. It switches automatically once the parser becomes
/// available, and if initialization fails, [MarkdownXParserUnavailableException] is reported once
/// through [FlutterError.reportError] (doc/parser.md).
///
/// See also:
///
///  * [Markdown], which is a scrolling container of Markdown.
///  * [MarkdownBody], which is a non-scrolling container of Markdown.
///  * [SliverMarkdown], which is a sliver of Markdown.
abstract class MarkdownWidget extends StatefulWidget {
  /// Creates a widget that parses and displays Markdown.
  const MarkdownWidget({
    super.key,
    required this.data,
    this.selectable = false,
    this.styleSheet,
    this.styleSheetTheme = MarkdownStyleSheetBaseTheme.material,
    this.syntaxHighlighter,
    this.onSelectionChanged,
    this.onTapLink,
    this.onTapText,
    this.contextMenuBuilder = _defaultContextMenuBuilder,
    this.imageDirectory,
    this.blockSyntaxes,
    this.inlineSyntaxes,
    this.extensionSet,
    @Deprecated('Use sizedImageBuilder instead') this.imageBuilder,
    this.sizedImageBuilder,
    this.checkboxBuilder,
    this.bulletBuilder,
    this.builders = const <String, MarkdownElementBuilder>{},
    this.paddingBuilders = const <String, MarkdownPaddingBuilder>{},
    this.fitContent = false,
    this.listItemCrossAxisAlignment =
        MarkdownListItemCrossAxisAlignment.baseline,
    this.softLineBreak = false,
    this.streaming = false,
    this.extensions = const [],
    this.alerts = true,
    this.markdownController,
    this.handleAnchorLinks = true,
    this.citationBuilder,
    this.onTapCitation,
    this.imageResolver,
    this.imageLoadingBuilder,
    this.imageErrorBuilder,
    this.onTapImage,
    this.blockBuilder,
    this.inlineBuilder,
    this.onTapCheckbox,
  });

  /// The Markdown to display.
  final String data;

  /// If true, wraps the document in one [SelectionArea] so text can be selected and copied.
  ///
  /// Defaults to false. Do not set it when an ancestor already is a [SelectionArea]. See
  /// doc/accessibility.md for the rules of the copied text.
  final bool selectable;

  /// The styles to use when displaying the Markdown.
  ///
  /// Merged onto the style sheet of the theme. If null, the styles are inferred from the current
  /// theme. Compared by value (`==`), so building it inside `build()` is fine.
  final MarkdownStyleSheet? styleSheet;

  /// Which theme the default style sheet is created from.
  ///
  /// Defaults to [MarkdownStyleSheetBaseTheme.material]; `null` behaves the same.
  final MarkdownStyleSheetBaseTheme? styleSheetTheme;

  /// The syntax highlighter used to color the text of code blocks.
  ///
  /// If null, the built-in highlighter colors tokens with [MarkdownStyleSheet.codeSyntax] (and the
  /// code is drawn with [MarkdownStyleSheet.code] only when that is null).
  final SyntaxHighlighter? syntaxHighlighter;

  /// Called when the selection changes and [selectable] is true.
  ///
  /// `text` is the selected plain text and `selection` covers all of it. `cause` is always null.
  /// It is not called when the selection is cleared.
  final MarkdownOnSelectionChangedCallback? onSelectionChanged;

  /// Called when the user taps a link with the link text, the destination and the title (empty
  /// when there is none).
  ///
  /// A `#id` link to a heading or footnote of the document is handled internally while
  /// [handleAnchorLinks] is true; every other link is passed here.
  final MarkdownTapLinkCallback? onTapLink;

  /// Called when the user taps text and [selectable] is true.
  final VoidCallback? onTapText;

  /// Builds the text selection toolbar when [selectable] is true.
  ///
  /// The default is the platform toolbar. `null` suppresses the toolbar. A custom function is
  /// reported once and the default toolbar is used, because [SelectionArea] needs a different
  /// builder type.
  final EditableTextContextMenuBuilder? contextMenuBuilder;

  static Widget _defaultContextMenuBuilder(
    BuildContext context,
    EditableTextState editableTextState,
  ) => AdaptiveTextSelectionToolbar.editableText(
    editableTextState: editableTextState,
  );

  /// The base directory holding images referenced by relative paths.
  ///
  /// It is prepended to the source as a string. A non-null value is also the opt-in to read local
  /// files below it; without it a relative path is not loaded.
  final String? imageDirectory;

  /// Custom block syntaxes of `package:markdown`.
  ///
  /// The parser is Rust, so these do not run. See doc/flutter_markdown_compat.md.
  final List<md.BlockSyntax>? blockSyntaxes;

  /// Custom inline syntaxes of `package:markdown`.
  ///
  /// The parser is Rust, so these do not run. See doc/flutter_markdown_compat.md.
  final List<md.InlineSyntax>? inlineSyntaxes;

  /// The `package:markdown` extension set. Defaults to [md.ExtensionSet.gitHubFlavored].
  ///
  /// GFM is always on in the Rust parser.
  final md.ExtensionSet? extensionSet;

  /// Builds the widget of an image from its URI, title and alt text.
  @Deprecated('Use sizedImageBuilder instead')
  final MarkdownImageBuilder? imageBuilder;

  /// Builds the widget of an image from its configuration. Takes precedence over [imageBuilder].
  final MarkdownSizedImageBuilder? sizedImageBuilder;

  /// Builds the widget of a task list checkbox.
  final MarkdownCheckboxBuilder? checkboxBuilder;

  /// Builds the widget of a list bullet.
  final MarkdownBulletBuilder? bulletBuilder;

  /// Builders of the widgets of certain tags, by tag name.
  final Map<String, MarkdownElementBuilder> builders;

  /// Padding builders of certain tags (block elements and `img`), by tag name.
  final Map<String, MarkdownPaddingBuilder> paddingBuilders;

  /// Whether to allow the widget to fit the child content.
  final bool fitContent;

  /// Controls the cross axis alignment of the bullet and the item content of lists.
  final MarkdownListItemCrossAxisAlignment listItemCrossAxisAlignment;

  /// When true, a soft line break (a newline inside a paragraph) is drawn as a line break.
  /// By default it is drawn as a space.
  final bool softLineBreak;

  /// When true, [data] is treated as still being generated, with an unfinished tail.
  ///
  /// Unfinished syntax at the end (unclosed emphasis, links, tables, and so on) is repaired so raw
  /// symbols are not visible. Set it back to false (the default) when generation finishes. See
  /// doc/streaming.md.
  final bool streaming;

  /// Custom syntaxes. Applied to the IR after parsing.
  ///
  /// If an element's instance changes, the text is parsed again even when [data] is the same. Keep
  /// them in a field or a `const` and reuse them.
  final List<MarkdownXExtension> extensions;

  /// When true (the default), GitHub alerts (`> [!NOTE]` and so on) get a dedicated display.
  ///
  /// With false, they become ordinary quotes that contain `[!NOTE]`. See
  /// doc/alerts-and-citations.md.
  final bool alerts;

  /// The controller used to get the table of contents and to navigate to headings and footnotes.
  ///
  /// Attach it to only one widget at a time.
  final MarkdownXController? markdownController;

  /// When true (the default), tapping a `#id` link scrolls to the heading or footnote with that id
  /// and [onTapLink] is not called. When the id is not in the document, or when this is false, the
  /// link is passed to [onTapLink].
  final bool handleAnchorLinks;

  /// Replaces how citations are displayed. Returning null gives the default chip.
  final MarkdownXCitationBuilder? citationBuilder;

  /// Called when a citation chip is tapped. When null, the chip is not interactive.
  final MarkdownXCitationCallback? onTapCitation;

  /// Creates an [ImageProvider] from the resolved URI. Returning null falls through to the default
  /// resolver. Applies to the default image display only.
  final MarkdownXImageResolver? imageResolver;

  /// The display while an image loads (default image display only).
  final MarkdownXImageLoadingBuilder? imageLoadingBuilder;

  /// The display for an image that could not be shown (default image display only).
  final MarkdownXImageErrorBuilder? imageErrorBuilder;

  /// Called when the default image display is tapped.
  final MarkdownXImageTapCallback? onTapImage;

  /// Replaces how blocks are displayed. It is also called for nested blocks, and a block for which
  /// it returns null gets the default display.
  final MarkdownXBlockBuilder? blockBuilder;

  /// Replaces how inlines are displayed. An inline for which it returns null gets the default
  /// display.
  final MarkdownXInlineBuilder? inlineBuilder;

  /// Called when a task list checkbox is tapped, or activated with Space or Enter. When null (the
  /// default), checkboxes are display-only.
  ///
  /// The checked state of a task is the `[ ]` / `[x]` in the Markdown text, so the widget does not
  /// keep it: it reports the tap and the app rewrites its own [data] with [MarkdownXTask.toggle]:
  ///
  /// ```dart
  /// Markdown(
  ///   data: data,
  ///   onTapCheckbox: (task) => setState(() => data = task.toggle(data)),
  /// )
  /// ```
  ///
  /// With a callback the checkbox is focusable, shows a focus ring, and is exposed to assistive
  /// technology as a checkbox with a tap action. This also applies to the widget that
  /// [checkboxBuilder] returns, which is wrapped, not replaced. A task whose position in [data]
  /// is unknown (an extension rebuilt its item) is not interactive.
  ///
  /// While [streaming] is true the unfinished last part can be tapped too. The task refers to the
  /// current [data], so toggling it is fine as long as the app keeps appending to the new text.
  ///
  /// The current closure is always called, and replacing it does not rebuild any block (only
  /// switching between null and non-null does). This is an extension; flutter_markdown has no
  /// such parameter (doc/flutter_markdown_compat.md).
  final MarkdownXCheckboxCallback? onTapCheckbox;

  /// Subclasses override this to display the given [children], which are the blocks of [data]
  /// separated by `SizedBox(height: blockSpacing)`.
  @protected
  Widget build(BuildContext context, List<Widget>? children);

  @override
  State<MarkdownWidget> createState() => _MarkdownWidgetState();
}

/// Implemented by widgets that display their blocks lazily in a sliver.
abstract interface class _SliverHost {
  /// Wraps the [sliver] of blocks, or returns null to use the eager `build` path.
  Widget? wrapSliver(BuildContext context, Widget sliver);
}

/// A non-scrolling widget that parses and displays Markdown.
///
/// Place it where the parent scrolls, such as a chat bubble. It builds all blocks at once, so use
/// [Markdown] for long documents.
class MarkdownBody extends MarkdownWidget {
  /// Creates a non-scrolling widget that parses and displays Markdown.
  const MarkdownBody({
    super.key,
    required super.data,
    super.selectable,
    super.styleSheet,
    super.styleSheetTheme = null,
    super.syntaxHighlighter,
    super.onSelectionChanged,
    super.onTapLink,
    super.onTapText,
    super.contextMenuBuilder,
    super.imageDirectory,
    super.blockSyntaxes,
    super.inlineSyntaxes,
    super.extensionSet,
    @Deprecated('Use sizedImageBuilder instead.') super.imageBuilder,
    super.sizedImageBuilder,
    super.checkboxBuilder,
    super.bulletBuilder,
    super.builders,
    super.paddingBuilders,
    super.listItemCrossAxisAlignment,
    this.shrinkWrap = true,
    super.fitContent = true,
    super.softLineBreak,
    super.streaming,
    super.extensions,
    super.alerts,
    super.markdownController,
    super.handleAnchorLinks,
    super.citationBuilder,
    super.onTapCitation,
    super.imageResolver,
    super.imageLoadingBuilder,
    super.imageErrorBuilder,
    super.onTapImage,
    super.blockBuilder,
    super.inlineBuilder,
    super.onTapCheckbox,
  });

  /// If true, the column takes the minimum height that wraps its content. Otherwise it expands to
  /// the maximum allowed height.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context, List<Widget>? children) {
    // Always a Column, even for one block: a different structure for one block would rebuild the
    // block (and lose the state of, for example, an opened details) when a stream grows to two.
    return Column(
      mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: fitContent
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.stretch,
      children: children!,
    );
  }
}

/// A scrolling widget that parses and displays Markdown.
///
/// It builds lazily per block, so even a long document builds only the blocks on screen. It is a
/// [SliverMarkdown] inside a [CustomScrollView]; to place Markdown next to other slivers, use
/// [SliverMarkdown] directly.
class Markdown extends MarkdownWidget implements _SliverHost {
  /// Creates a scrolling widget that parses and displays Markdown.
  const Markdown({
    super.key,
    required super.data,
    super.selectable,
    super.styleSheet,
    super.styleSheetTheme = null,
    super.syntaxHighlighter,
    super.onSelectionChanged,
    super.onTapLink,
    super.onTapText,
    super.contextMenuBuilder,
    super.imageDirectory,
    super.blockSyntaxes,
    super.inlineSyntaxes,
    super.extensionSet,
    @Deprecated('Use sizedImageBuilder instead.') super.imageBuilder,
    super.sizedImageBuilder,
    super.checkboxBuilder,
    super.bulletBuilder,
    super.builders,
    super.paddingBuilders,
    super.listItemCrossAxisAlignment,
    this.padding = const EdgeInsets.all(16.0),
    this.controller,
    this.physics,
    this.shrinkWrap = false,
    this.noScroll = false,
    super.fitContent,
    super.softLineBreak,
    super.streaming,
    super.extensions,
    super.alerts,
    super.markdownController,
    super.handleAnchorLinks,
    super.citationBuilder,
    super.onTapCitation,
    super.imageResolver,
    super.imageLoadingBuilder,
    super.imageErrorBuilder,
    super.onTapImage,
    super.blockBuilder,
    super.inlineBuilder,
    super.onTapCheckbox,
  });

  /// The amount of space by which to inset the children.
  final EdgeInsets padding;

  /// An object that can be used to control the position to which this scroll view is scrolled.
  final ScrollController? controller;

  /// How the scroll view should respond to user input.
  final ScrollPhysics? physics;

  /// Whether the extent of the scroll view in the scroll direction should be determined by the
  /// contents being viewed.
  final bool shrinkWrap;

  /// If true, the Markdown is rendered in a non-scrolling [Column] (all blocks at once) instead of
  /// a lazy scroll view. Use this when the widget is already inside a scrolling parent.
  final bool noScroll;

  @override
  Widget? wrapSliver(BuildContext context, Widget sliver) {
    if (noScroll) return null;
    return CustomScrollView(
      controller: controller,
      physics: physics,
      shrinkWrap: shrinkWrap,
      slivers: [SliverPadding(padding: padding, sliver: sliver)],
    );
  }

  @override
  Widget build(BuildContext context, List<Widget>? children) {
    if (noScroll) {
      return Column(
        children: [
          for (final child in children ?? const <Widget>[])
            Padding(padding: padding, child: child),
        ],
      );
    }
    return ListView(
      padding: padding,
      controller: controller,
      physics: physics,
      shrinkWrap: shrinkWrap,
      children: children!,
    );
  }
}

/// A sliver that displays Markdown. Place it in a parent [CustomScrollView] next to other slivers.
///
/// It builds lazily with a [SliverList] per block (top-level paragraph, list, table, and so on).
/// It has the parameters of [MarkdownWidget] except those of scrolling and `selectable` (a sliver
/// cannot be wrapped in a [SelectionArea]; wrap the [CustomScrollView] instead). Add padding by
/// wrapping it in a [SliverPadding].
///
/// ```dart
/// CustomScrollView(slivers: [
///   SliverAppBar(title: Text('Chat')),
///   SliverPadding(
///     padding: EdgeInsets.all(16),
///     sliver: SliverMarkdown(data: reply, streaming: true),
///   ),
/// ])
/// ```
///
/// The work of an update by appending (streaming) is decided by the size of the last chunk, not by
/// the whole document. The inside of a single top-level block is not built lazily (see
/// doc/performance.md for the limits of huge lists and tables).
class SliverMarkdown extends MarkdownWidget implements _SliverHost {
  /// Creates a sliver that displays Markdown.
  const SliverMarkdown({
    super.key,
    required super.data,
    super.styleSheet,
    super.styleSheetTheme = null,
    super.syntaxHighlighter,
    super.onTapLink,
    super.imageDirectory,
    super.blockSyntaxes,
    super.inlineSyntaxes,
    super.extensionSet,
    @Deprecated('Use sizedImageBuilder instead.') super.imageBuilder,
    super.sizedImageBuilder,
    super.checkboxBuilder,
    super.bulletBuilder,
    super.builders,
    super.paddingBuilders,
    super.listItemCrossAxisAlignment,
    super.fitContent,
    super.softLineBreak,
    super.streaming,
    super.extensions,
    super.alerts,
    super.markdownController,
    super.handleAnchorLinks,
    super.citationBuilder,
    super.onTapCitation,
    super.imageResolver,
    super.imageLoadingBuilder,
    super.imageErrorBuilder,
    super.onTapImage,
    super.blockBuilder,
    super.inlineBuilder,
    super.onTapCheckbox,
  });

  @override
  Widget? wrapSliver(BuildContext context, Widget sliver) => sliver;

  @override
  Widget build(BuildContext context, List<Widget>? children) =>
      SliverList(delegate: SliverChildListDelegate(children ?? const []));
}

/// Reported once per isolate when a custom context menu builder is given.
bool _reportedContextMenu = false;

/// Whether [a] and [b] register the same tags with builders of the same type.
bool _sameBuilderShape<T extends Object>(Map<String, T> a, Map<String, T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null || other.runtimeType != entry.value.runtimeType) {
      return false;
    }
    if (entry.value is MarkdownElementBuilder &&
        (entry.value as MarkdownElementBuilder).isBlockElement() !=
            (other as MarkdownElementBuilder).isBlockElement()) {
      return false;
    }
  }
  return true;
}

bool _sameNullness(Object? a, Object? b) => (a == null) == (b == null);

/// The shared State that holds the parse result and the widget cache of blocks.
///
/// It is also the [MdxRelay] of the blocks: they read the newest callbacks and closures from the
/// widget at build time, and only [_generation] (bumped by [_invalidateIfNeeded]) rebuilds them.
class _MarkdownWidgetState extends State<MarkdownWidget>
    implements MarkdownXNavigationHost, MdxRelay {
  final IncrementalMarkdownParser _parser = IncrementalMarkdownParser();
  String? _parsedData;
  bool _parsedStreaming = false;
  int? _parsedRevision;
  // When the parser is unavailable, show the raw Markdown as-is (doc/parser.md).
  bool _showsRawText = false;
  // Whether the reason it is unavailable has been reported. Reported only once until the parser becomes available.
  bool _reportedUnavailable = false;
  List<MarkdownXExtension> _parsedExtensions = const [];
  final List<_BlockEntry> _entries = [];
  List<MdxBlock> _blocks = const [];
  MarkdownXNavigationIndex? _navigation;
  MarkdownXController? _attachedController;
  List<MarkdownXHeading> _notifiedHeadings = const [];
  bool _notifyScheduled = false;
  int _jumpSerial = 0;
  final Map<_BlockEntry, int> _entryIndexes = {};

  /// Bumped when something that blocks render has changed (see doc/flutter_markdown_compat.md).
  int _generation = 0;
  MarkdownStyleSheet? _effectiveSheet;

  int get blockCount => _entries.length;

  @override
  MarkdownStyleSheet get styleSheet => _effectiveSheet!;
  @override
  bool get selectable => widget.selectable;
  @override
  bool get softLineBreak => widget.softLineBreak;
  @override
  bool get fitContent => widget.fitContent;
  @override
  MarkdownListItemCrossAxisAlignment get listItemCrossAxisAlignment =>
      widget.listItemCrossAxisAlignment;
  @override
  String? get imageDirectory => widget.imageDirectory;
  @override
  SyntaxHighlighter? get syntaxHighlighter => widget.syntaxHighlighter;
  @override
  // ignore: deprecated_member_use_from_same_package
  MarkdownImageBuilder? get imageBuilder => widget.imageBuilder;
  @override
  MarkdownSizedImageBuilder? get sizedImageBuilder => widget.sizedImageBuilder;
  @override
  MarkdownCheckboxBuilder? get checkboxBuilder => widget.checkboxBuilder;
  @override
  MarkdownBulletBuilder? get bulletBuilder => widget.bulletBuilder;
  @override
  Map<String, MarkdownElementBuilder> get builders => widget.builders;
  @override
  Map<String, MarkdownPaddingBuilder> get paddingBuilders =>
      widget.paddingBuilders;
  @override
  bool get generateHeaderIds =>
      syntaxesGenerateHeaderIds(widget.extensionSet, widget.blockSyntaxes);
  @override
  MarkdownXImageResolver? get imageResolver => widget.imageResolver;
  @override
  MarkdownXImageLoadingBuilder? get imageLoadingBuilder =>
      widget.imageLoadingBuilder;
  @override
  MarkdownXImageErrorBuilder? get imageErrorBuilder => widget.imageErrorBuilder;
  @override
  MarkdownXImageTapCallback? get onTapImage =>
      widget.onTapImage == null ? null : _handleTapImage;
  @override
  MarkdownXBlockBuilder? get blockBuilder => widget.blockBuilder;
  @override
  MarkdownXInlineBuilder? get inlineBuilder => widget.inlineBuilder;
  @override
  MarkdownXCitationBuilder? get citationBuilder => widget.citationBuilder;
  @override
  MarkdownXCitationCallback? get onTapCitation =>
      widget.onTapCitation == null ? null : _handleTapCitation;
  @override
  VoidCallback? get onTapText => widget.onTapText;
  @override
  bool get checkboxesTappable => widget.onTapCheckbox != null;

  String get data => widget.data;
  bool get streaming => widget.streaming;
  bool get alerts =>
      widget.alerts ||
      syntaxesEnableAlerts(widget.extensionSet, widget.blockSyntaxes);
  List<MarkdownXExtension> get extensions => widget.extensions;
  bool get handleAnchorLinks => widget.handleAnchorLinks;
  MarkdownXController? get markdownController => widget.markdownController;

  /// True when blocks are built lazily in a sliver.
  bool get isLazy => widget is _SliverHost;

  @override
  void initState() {
    super.initState();
    _reportSyntaxes();
    _syncController();
    _parse();
    unawaited(
      selected.initializeParser().then((_) {
        if (!mounted) return;
        // The success or failure of initialization is now decided, so switch away from the raw string display. On failure, it is reported once here.
        if (_showsRawText) {
          _parsedData = null;
          setState(_parse);
        } else if (_parsedRevision != selected.parserRevision) {
          setState(_parse);
        }
      }),
    );
  }

  @override
  void didUpdateWidget(MarkdownWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.extensionSet, oldWidget.extensionSet) ||
        !identical(widget.blockSyntaxes, oldWidget.blockSyntaxes) ||
        !identical(widget.inlineSyntaxes, oldWidget.inlineSyntaxes)) {
      _reportSyntaxes();
    }
    _syncController();
    _parse();
    _refreshStyleSheet();
    _invalidateIfNeeded(oldWidget);
  }

  @override
  void dispose() {
    _jumpSerial++;
    _attachedController?.detach(this);
    _attachedController = null;
    super.dispose();
  }

  void _reportSyntaxes() => reportUnsupportedSyntaxes(
    extensionSet: widget.extensionSet,
    blockSyntaxes: widget.blockSyntaxes,
    inlineSyntaxes: widget.inlineSyntaxes,
  );

  void _syncController() {
    final next = markdownController;
    if (identical(next, _attachedController)) return;
    _attachedController?.detach(this);
    _attachedController = next;
    next?.attach(this);
    _notifiedHeadings = const [];
    _navigation = null;
    _notifyHeadings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshStyleSheet();
  }

  /// Rebuilds the effective style sheet: the fallback of the theme merged with the user's sheet.
  /// The instance is replaced (and blocks rebuild) only when the result differs by value.
  void _refreshStyleSheet() {
    final fallback = _fallbackStyleSheet();
    final next = fallback.merge(widget.styleSheet);
    final previous = _effectiveSheet;
    if (previous == null) {
      _effectiveSheet = next;
    } else if (previous != next) {
      _effectiveSheet = next;
      _generation++;
    }
  }

  MarkdownStyleSheet _fallbackStyleSheet() {
    final baseTheme =
        widget.styleSheetTheme ?? MarkdownStyleSheetBaseTheme.material;
    final cupertino = switch (baseTheme) {
      MarkdownStyleSheetBaseTheme.cupertino => true,
      MarkdownStyleSheetBaseTheme.material => false,
      MarkdownStyleSheetBaseTheme.platform =>
        defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS,
    };
    final sheet = cupertino
        ? MarkdownStyleSheet.fromCupertinoTheme(CupertinoTheme.of(context))
        : MarkdownStyleSheet.fromTheme(Theme.of(context));
    return sheet.copyWith(
      textScaler: MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
    );
  }

  /// Bumps the generation when a change affects what blocks render.
  ///
  /// Callbacks are read through the relay at event time and never invalidate. Builders compare by
  /// key set and runtime type, closures by null versus non-null.
  void _invalidateIfNeeded(MarkdownWidget old) {
    final w = widget;
    if (w.selectable != old.selectable ||
        w.softLineBreak != old.softLineBreak ||
        w.fitContent != old.fitContent ||
        w.listItemCrossAxisAlignment != old.listItemCrossAxisAlignment ||
        w.imageDirectory != old.imageDirectory ||
        w.handleAnchorLinks != old.handleAnchorLinks ||
        syntaxesGenerateHeaderIds(w.extensionSet, w.blockSyntaxes) !=
            syntaxesGenerateHeaderIds(old.extensionSet, old.blockSyntaxes) ||
        w.syntaxHighlighter?.runtimeType !=
            old.syntaxHighlighter?.runtimeType ||
        !_sameBuilderShape(w.builders, old.builders) ||
        !_sameBuilderShape(w.paddingBuilders, old.paddingBuilders) ||
        // ignore: deprecated_member_use_from_same_package
        !_sameNullness(w.imageBuilder, old.imageBuilder) ||
        !_sameNullness(w.sizedImageBuilder, old.sizedImageBuilder) ||
        !_sameNullness(w.checkboxBuilder, old.checkboxBuilder) ||
        !_sameNullness(w.bulletBuilder, old.bulletBuilder) ||
        !_sameNullness(w.imageResolver, old.imageResolver) ||
        !_sameNullness(w.imageLoadingBuilder, old.imageLoadingBuilder) ||
        !_sameNullness(w.imageErrorBuilder, old.imageErrorBuilder) ||
        !_sameNullness(w.onTapImage, old.onTapImage) ||
        !_sameNullness(w.blockBuilder, old.blockBuilder) ||
        !_sameNullness(w.inlineBuilder, old.inlineBuilder) ||
        !_sameNullness(w.citationBuilder, old.citationBuilder) ||
        !_sameNullness(w.onTapCitation, old.onTapCitation) ||
        !_sameNullness(w.onTapCheckbox, old.onTapCheckbox) ||
        !_sameNullness(w.onTapText, old.onTapText)) {
      _generation++;
    }
  }

  /// [extensions] plus the built-in extensions that are enabled by default (alerts, and
  /// emoji when `gitHubWeb` or `EmojiSyntax` asks for it).
  ///
  /// The alert goes first (so a user's extension can see alert blocks).
  List<MarkdownXExtension> _effectiveExtensions() {
    final addAlerts = alerts && !extensions.contains(markdownXAlertsExtension);
    final addEmoji =
        syntaxesEnableEmoji(widget.extensionSet, widget.inlineSyntaxes) &&
        !extensions.contains(markdownXEmojiExtension);
    if (!addAlerts && !addEmoji) return extensions;
    return [
      if (addAlerts) markdownXAlertsExtension,
      if (addEmoji) markdownXEmojiExtension,
      ...extensions,
    ];
  }

  void _parse() {
    if (_parsedData == data &&
        _parsedStreaming == streaming &&
        _parsedRevision == selected.parserRevision &&
        sameExtensions(_parsedExtensions, _effectiveExtensions())) {
      return;
    }
    _parsedData = data;
    _parsedStreaming = streaming;
    final effective = _effectiveExtensions();
    _parsedExtensions = effective;
    List<MdxBlock> parsed;
    var reusedPrefix = 0;
    try {
      parsed = markdownXAddFootnoteBackrefs(
        _parser.parse(data, extensions: effective, streaming: streaming),
      );
      reusedPrefix = _parser.reusedBlockPrefix;
      _showsRawText = false;
      _reportedUnavailable = false;
    } on MarkdownXParserUnavailableException catch (error, stack) {
      // While the parser is unavailable, show the raw Markdown. There are no headings.
      parsed = const [];
      _showsRawText = true;
      _reportUnavailable(error, stack);
    }
    _parsedRevision = selected.parserRevision;
    _reconcileEntries(parsed, reusedPrefix);
    _blocks = parsed;
    _navigation = null;
    _notifyHeadings();
  }

  /// Updates [_entries] to match [parsed].
  ///
  /// On an append, the first [reusedPrefix] blocks are the same instances as last time, so their entries are kept as-is and only the changed tail is matched (the work is proportional to the size of the tail).
  ///
  /// Reuse occurrence tokens in document order. Equal duplicate blocks are
  /// matched to prior equal occurrences in order; their identity is inherently
  /// ambiguous when identical occurrences are inserted or removed.
  void _reconcileEntries(List<MdxBlock> parsed, int reusedPrefix) {
    var keep = min(reusedPrefix, min(_blocks.length, parsed.length));
    // A footnote backreference replaces the last block, so include that block in the matching.
    while (keep > 0 && !identical(parsed[keep - 1], _blocks[keep - 1])) {
      keep--;
    }
    final available = <MdxBlock, List<_BlockEntry>>{};
    final cursors = <MdxBlock, int>{};
    for (var i = keep; i < _entries.length; i++) {
      final entry = _entries[i];
      _entryIndexes.remove(entry);
      (available[entry.block] ??= []).add(entry);
    }
    _entries.length = keep;
    for (var i = keep; i < parsed.length; i++) {
      final entry = _reuseOrCreate(parsed[i], available, cursors);
      _entries.add(entry);
      _entryIndexes[entry] = i;
    }
  }

  MarkdownXNavigationIndex get _index =>
      _navigation ??= MarkdownXNavigationIndex.build(_blocks);

  /// If the headings changed, notify the controller after build.
  void _notifyHeadings() {
    final controller = _attachedController;
    if (controller == null || _notifyScheduled) return;
    if (_index.headings.length == _notifiedHeadings.length &&
        _sameHeadings(_index.headings, _notifiedHeadings)) {
      return;
    }
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!mounted || !identical(_attachedController, controller)) return;
      _notifiedHeadings = _index.headings;
      controller.notifyHeadingsChanged();
    });
  }

  static bool _sameHeadings(
    List<MarkdownXHeading> a,
    List<MarkdownXHeading> b,
  ) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _reportUnavailable(Object error, StackTrace stack) {
    // If the web WASM is still initializing, it will parse again after completion, so do not report.
    if (!selected.markdownXParserDiagnostics().initialized) return;
    if (_reportedUnavailable) return;
    _reportedUnavailable = true;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'flutter_markdown_x',
        context: ErrorDescription(
          'while parsing Markdown (showing the raw text instead)',
        ),
      ),
    );
  }

  _BlockEntry _reuseOrCreate(
    MdxBlock block,
    Map<MdxBlock, List<_BlockEntry>> available,
    Map<MdxBlock, int> cursors,
  ) {
    final matches = available[block];
    final cursor = cursors[block] ?? 0;
    if (matches == null || cursor >= matches.length) return _BlockEntry(block);
    cursors[block] = cursor + 1;
    return matches[cursor];
  }

  // Callbacks without render output are called through these methods, as of the moment of the event, so a new instance never rebuilds blocks.
  void _handleTapImage(MdxImage image, Uri? resolved) =>
      widget.onTapImage?.call(image, resolved);

  void _handleTapCitation(String id) => widget.onTapCitation?.call(id);

  /// The task whose checkbox should take the keyboard focus after the rebuild that a toggle causes.
  int? _focusTaskIndex;

  /// The task that [item] stands for in the newest parse. [owner] is the entry of the top-level block.
  ///
  /// The widget of a block can be older than the block (it is kept while the block stays equal), so
  /// the task is found by its place in that block and its position is read from the newest parse.
  MarkdownXTask? _taskOf(Object? owner, MdxListItem item) {
    if (owner is! _BlockEntry) return null;
    final index = _entryIndexes[owner];
    if (index == null) return null;
    return _parser.taskAt(_blocks, index, mdxTaskOrdinal([owner.block], item));
  }

  @override
  void handleTapCheckbox(
    Object? owner,
    MdxListItem item, {
    required bool keepFocus,
  }) {
    final callback = widget.onTapCheckbox;
    if (callback == null) return;
    final task = _taskOf(owner, item);
    if (task == null) return;
    if (keepFocus) {
      // The app is about to change data, which rebuilds the block and replaces the focused
      // checkbox. Hand the focus to its successor, and forget about it after the next frame.
      _focusTaskIndex = task.index;
      SchedulerBinding.instance
        ..addPostFrameCallback((_) => _focusTaskIndex = null)
        ..scheduleFrame();
    }
    callback(task);
  }

  @override
  bool takesCheckboxFocus(Object? owner, MdxListItem item) {
    final wanted = _focusTaskIndex;
    if (wanted == null) return false;
    if (_taskOf(owner, item)?.index != wanted) return false;
    _focusTaskIndex = null;
    return true;
  }

  @override
  void handleTapLink(String text, String? href, String title) {
    if (handleAnchorLinks && href != null && href.startsWith('#')) {
      final id = _findAnchorId(href.substring(1));
      if (id != null) {
        unawaited(
          jumpToAnchor(
            id,
            duration: Duration.zero,
            curve: Curves.ease,
            alignment: 0,
          ),
        );
        return;
      }
    }
    widget.onTapLink?.call(text, href, title);
  }

  /// Finds the target id from the href fragment. Allows percent encoding and differences in letter case (the same as GitHub).
  String? _findAnchorId(String fragment) {
    final anchors = _index.anchors;
    if (anchors.containsKey(fragment)) return fragment;
    String decoded;
    try {
      decoded = Uri.decodeComponent(fragment);
    } on ArgumentError {
      decoded = fragment;
    }
    if (anchors.containsKey(decoded)) return decoded;
    final lower = decoded.toLowerCase();
    return anchors.containsKey(lower) ? lower : null;
  }

  @override
  List<MarkdownXHeading> get headings => _index.headings;

  @override
  bool hasAnchor(String id) => _index.anchors.containsKey(id);

  /// The maximum number of attempts. Even if an estimation error overshoots, it converges in a few.
  static const _maxRevealAttempts = 100;

  /// The maximum number of consecutive waits while the position does not move (to wait for the range to update).
  static const _maxStalledAttempts = 3;

  @override
  Future<bool> jumpToAnchor(
    String id, {
    required Duration duration,
    required Curve curve,
    required double alignment,
  }) async {
    final anchor = _index.anchors[id];
    if (anchor == null) return false;
    final resolved = markdownXResolvePath(_blocks, anchor.path);
    if (resolved == null) return false;
    final serial = ++_jumpSerial;
    bool stale() => !mounted || serial != _jumpSerial;

    final entryElement = await _revealEntry(anchor.path.first, stale);
    if (entryElement == null || stale()) return false;

    // Open the `details` that lead to the target block.
    var current = entryElement;
    final chain = resolved.chain;
    for (var i = 0; i < chain.length; i++) {
      final view = mdxFindBlockView(current, chain[i]);
      if (view == null) return false;
      current = view;
      if (chain[i] is MdxDetails && (i < chain.length - 1)) {
        if (mdxOpenDetails(view)) {
          await WidgetsBinding.instance.endOfFrame;
          if (stale()) return false;
        }
      }
    }
    var target = current;
    final item = resolved.item;
    if (item != null) {
      target = mdxFindListItem(current, chain.last as MdxList, item) ?? current;
    }
    if (!target.mounted) return false;
    await _revealVertically(
      target,
      alignment: alignment,
      duration: duration,
      curve: curve,
    );
    return !stale();
  }

  /// Makes top-level block [index] get built and returns its Element (the view's Padding).
  ///
  /// When it is outside the lazily built range, it jumps repeatedly toward an offset estimated from the positions of the blocks already built.
  Future<Element?> _revealEntry(int index, bool Function() stale) async {
    if (index < 0 || index >= _entries.length) return null;
    var stalled = 0;
    for (var attempt = 0; attempt < _maxRevealAttempts; attempt++) {
      if (stale()) return null;
      final built = _builtEntries();
      final hit = built[index];
      if (hit != null) return hit;
      if (!isLazy) return null;
      final position = _scrollPosition();
      if (built.isEmpty || position == null) {
        // Before layout. Wait one frame, and give up if it is still not there.
        if (++stalled > _maxStalledAttempts) return null;
        await WidgetsBinding.instance.endOfFrame;
        continue;
      }
      final desired = _estimateOffset(built, index);
      final clamped = desired.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((clamped - position.pixels).abs() < 0.5) {
        if (++stalled > _maxStalledAttempts) return null;
      } else {
        stalled = 0;
        position.jumpTo(clamped);
      }
      await WidgetsBinding.instance.endOfFrame;
    }
    return null;
  }

  /// Built top-level block index to Element (the view's Padding).
  Map<int, Element> _builtEntries() {
    final built = <int, Element>{};
    void visit(Element element) {
      final key = element.widget.key;
      if (key is ValueKey<_BlockEntry>) {
        final index = _entryIndexes[key.value];
        if (index != null) built[index] = element;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return built;
  }

  /// Scrolls every vertical viewport that holds [target] so that it becomes visible.
  ///
  /// Unlike [Scrollable.ensureVisible], horizontal scrollables (a `TabBarView`, a `PageView`,
  /// a horizontal list) are left alone: moving them would change the page, not the position in
  /// the document.
  Future<void> _revealVertically(
    BuildContext target, {
    required double alignment,
    required Duration duration,
    required Curve curve,
  }) async {
    final object = target.findRenderObject();
    if (object == null || !object.attached) return;
    final animations = <Future<void>>[];
    var scrollable = Scrollable.maybeOf(target);
    while (scrollable != null) {
      if (_isVertical(scrollable)) {
        animations.add(
          scrollable.position.ensureVisible(
            object,
            alignment: alignment,
            duration: duration,
            curve: curve,
          ),
        );
      }
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
    await Future.wait(animations);
  }

  static bool _isVertical(ScrollableState scrollable) =>
      axisDirectionToAxis(scrollable.axisDirection) == Axis.vertical;

  /// The position of the vertical [Scrollable] that scrolls this Widget's document.
  ///
  /// [Markdown] owns its scroll view, which is below this State. The others use the nearest
  /// vertical ancestor; horizontal ones (a `TabBarView`, a `PageView`) are skipped.
  ScrollPosition? _scrollPosition() {
    final host = widget;
    if (host is Markdown && !host.noScroll) {
      ScrollPosition? inner;
      void visit(Element element) {
        if (inner != null) return;
        if (element is StatefulElement && element.state is ScrollableState) {
          inner = (element.state as ScrollableState).position;
          return;
        }
        element.visitChildren(visit);
      }

      context.visitChildElements(visit);
      return inner;
    }
    var scrollable = Scrollable.maybeOf(context);
    while (scrollable != null) {
      if (_isVertical(scrollable)) return scrollable.position;
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
    return null;
  }

  /// Estimates, from the average height of the built blocks, the offset at which the start of [index] comes to the start of the screen.
  double _estimateOffset(Map<int, Element> built, int index) {
    double offsetOf(int i) {
      final box = built[i]!.renderObject! as RenderBox;
      return RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
    }

    final indexes = built.keys.toList()..sort();
    final first = indexes.first;
    final last = indexes.last;
    final lastBox = built[last]!.renderObject! as RenderBox;
    final firstOffset = offsetOf(first);
    final lastOffset = offsetOf(last);
    final average =
        (lastOffset + lastBox.size.height - firstOffset) / (last - first + 1);
    return index > last
        ? lastOffset + (index - last) * average
        : firstOffset - (first - index) * average;
  }

  /// The scope that gives blocks access to the settings, around [child].
  Widget _scoped(Widget child) => MdxScope(
    relay: this,
    generation: _generation,
    child: DocumentSelectionScope(child: child),
  );

  /// The display while the parser is unavailable. Shows [data] as-is, in the paragraph style.
  Widget _rawText() => Text(
    data,
    key: const ValueKey('flutter_markdown_x.raw_text'),
    style: styleSheet.p,
    textScaler: styleSheet.textScaler,
  );

  /// A block of the lazy list, followed by the spacing to the next one.
  Widget _lazyBlock(int index) {
    final spacing = styleSheet.blockSpacing ?? 0;
    final entry = _entries[index];
    final isLast = index == _entries.length - 1;
    return Padding(
      key: ValueKey(entry),
      padding: EdgeInsets.only(bottom: isLast ? 0 : spacing),
      child: entry.view,
    );
  }

  /// The children of an eager build: blocks separated by `SizedBox(height: blockSpacing)`.
  List<Widget> _eagerChildren() {
    if (_showsRawText) return [_rawText()];
    final spacing = styleSheet.blockSpacing ?? 0;
    return [
      for (var i = 0; i < _entries.length; i++) ...[
        if (i > 0) SizedBox(height: spacing),
        KeyedSubtree(key: ValueKey(_entries[i]), child: _entries[i].view),
      ],
    ];
  }

  int? _indexForKey(Key key) {
    if (key is! ValueKey<_BlockEntry>) return null;
    return _entryIndexes[key.value];
  }

  @override
  Widget build(BuildContext context) {
    final host = widget;
    Widget? lazy;
    if (host is _SliverHost) {
      lazy = (host as _SliverHost).wrapSliver(
        context,
        _scoped(
          SliverList.builder(
            itemCount: _showsRawText ? 1 : blockCount,
            itemBuilder: (context, index) =>
                _showsRawText ? _rawText() : _lazyBlock(index),
            findChildIndexCallback: (key) => _indexForKey(key),
          ),
        ),
      );
    }
    // ignore: invalid_use_of_protected_member
    final body = lazy ?? _scoped(host.build(context, _eagerChildren()));
    return widget.selectable ? _selectionArea(body) : body;
  }

  Widget _selectionArea(Widget child) {
    final builder = widget.contextMenuBuilder;
    final isDefault = identical(
      builder,
      MarkdownWidget._defaultContextMenuBuilder,
    );
    if (builder != null && !isDefault && !_reportedContextMenu) {
      _reportedContextMenu = true;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: UnsupportedError(
            'A custom contextMenuBuilder is not supported: the selection of '
            'flutter_markdown_x is owned by one SelectionArea, which needs a '
            'SelectableRegionContextMenuBuilder. The default menu is used.',
          ),
          library: 'flutter_markdown_x',
        ),
      );
    }
    void changed(SelectedContent? content) {
      final text = content?.plainText;
      if (text == null || text.isEmpty) return;
      widget.onSelectionChanged?.call(
        text,
        TextSelection(baseOffset: 0, extentOffset: text.length),
        null,
      );
    }

    if (builder == null) {
      return SelectionArea(
        contextMenuBuilder: null,
        onSelectionChanged: changed,
        child: child,
      );
    }
    return SelectionArea(onSelectionChanged: changed, child: child);
  }
}

class _BlockEntry {
  _BlockEntry(this.block) {
    view = MdxBlockOwner(
      owner: this,
      child: MdxBlockView(key: ValueKey(this), block: block),
    );
  }

  final MdxBlock block;
  late final Widget view;
}
