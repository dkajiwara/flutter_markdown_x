# flutter_markdown compatible API (reference)

This reference compares the public API with flutter_markdown 0.7.7+1 and
flutter_markdown_plus 1.0.12. See the [migration guide](migration.md) for setup
and examples.

## Sources and citation format

Every behavior below was read from the package sources in the local pub cache. Citations use these prefixes:

| Prefix | Path |
|---|---|
| `fm:` | `~/.pub-cache/hosted/pub.dev/flutter_markdown-0.7.7+1/lib/src/` |
| `fmp:` | `~/.pub-cache/hosted/pub.dev/flutter_markdown_plus-1.0.12/lib/src/` |
| `md:` | `~/.pub-cache/hosted/pub.dev/markdown-7.3.1/lib/src/` |
| (none) | this repository |

For example, `fm:widget.dart:375` is line 375 of flutter_markdown 0.7.7+1's `lib/src/widgets/widget.dart`.

The compatibility target is the **union** of flutter_markdown 0.7.7+1 and flutter_markdown_plus 1.0.12 (the maintained fork). Where the two disagree, the choice is stated in the row.

## Contents

1. [Summary and unsupported list](#1-summary-and-unsupported-list)
2. [Complete symbol and parameter table](#2-complete-symbol-and-parameter-table)
3. [Extensions to `MarkdownStyleSheet` and the widgets](#3-extensions-to-markdownstylesheet-and-the-widgets)
4. [Behavior notes](#4-behavior-notes)
5. [How compatibility is tested](#5-how-compatibility-is-tested)
6. [Material library (Flutter 3.50)](#material-library-flutter-350)

---

## 1. Summary and unsupported list

### Summary

- `MarkdownWidget`, `Markdown`, `MarkdownBody`, `MarkdownStyleSheet`, `MarkdownElementBuilder`, `MarkdownPaddingBuilder`, `SyntaxHighlighter`, all typedefs, enums, and value classes of flutter_markdown get the same names, signatures, and defaults.
- `package:markdown` comes back as a regular dependency, **for types only** (`md.Element`, `md.Text`, `md.ExtensionSet`, `md.BlockSyntax`, `md.InlineSyntax`). Parsing stays in Rust. For `builders` and `paddingBuilders`, the IR is converted to `md.Element` lazily, only for subtrees that contain a registered tag ([4a](#4a-builders-and-paddingbuilders)).
- Behaviors that flutter_markdown has (soft line breaks, tight vs loose lists) are carried by the IR, so `softLineBreak` and list spacing work as in flutter_markdown ([4c](#4c-soft-line-breaks-and-tight-lists)).
- The per-block cache and the append/streaming performance (`doc/performance.md`) survive the typical flutter_markdown usage (style sheet, builders map, and closures created inside `build()`) through value equality on `MarkdownStyleSheet` and a State relay for callbacks ([4f](#4f-cache-invalidation-with-flutter_markdown-style-call-sites)).

### UNSUPPORTED (cannot be matched)

| Symbol or behavior | Why | What happens instead |
|---|---|---|
| `MarkdownBuilder` (class) | It is an `md.NodeVisitor` that turns a full `package:markdown` AST into widgets (`fm:builder.dart:128-270`). This package never has that AST, and providing the class would mean shipping a second renderer next to the IR renderer, without the per-block cache | Not exported. Use `MarkdownBody` / `Markdown`, or subclass `MarkdownWidget` |
| `MarkdownBuilderDelegate` (interface) | Only meaningful as the delegate of `MarkdownBuilder` (`fm:builder.dart:104-121`) | Not exported |
| Custom `blockSyntaxes` / `inlineSyntaxes` (`md.BlockSyntax`, `md.InlineSyntax` subclasses) | The parser is the bundled Rust `pulldown-cmark`; Dart syntax objects cannot run inside it | Accepted for compile compatibility. Built-in syntax types that the Rust parser already covers are no-ops. Any other syntax is reported once through `FlutterError.reportError`, pointing to `MarkdownXExtension` ([4b](#4b-extensionset-blocksyntaxes-and-inlinesyntaxes)). Never silently ignored |
| `ExtensionSet.commonMark` / `ExtensionSet.none` turning GFM off | The Rust parser's options are fixed (`native/src/lib.rs:41-45`); exposing them would change the C ABI | Accepted, no effect: GFM stays on (tables, strikethrough, task lists, footnotes, autolinks still render) |
| `gitHubWeb` emoji (`:smile:`) | Not a parser feature | Supported: `gitHubWeb` and `md.EmojiSyntax()` in `inlineSyntaxes` enable `markdownXEmojiExtension`, an IR transform with `EmojiSyntax`'s pattern and table ([4b](#4b-extensionset-blocksyntaxes-and-inlinesyntaxes)) |
| `gitHubWeb` color swatches | Not implemented by the Rust parser | Accepted, no effect (rendered as text). Header ids and alerts of `gitHubWeb` are supported |
| Raw HTML shown as literal text | flutter_markdown parses with `encodeHtml: false` (`fm:widget.dart:395-400`) and `InlineHtmlSyntax` produces text, so `<b>x</b>` is displayed verbatim. This package interprets an HTML allowlist (`doc/html.md`) | Known difference, intentional |
| `MarkdownWidget.build(context, children)` receiving exactly flutter_markdown's widget tree | The children are this package's block widgets, not flutter_markdown's `Wrap`/`Column` trees | The list shape is kept (blocks separated by `SizedBox(height: blockSpacing)`, `fm:builder.dart:794-801`); the block widgets themselves differ |
| `onSelectionChanged` per-block `TextSelection` and `SelectionChangedCause` | flutter_markdown uses one `SelectableText` per text block (`fm:builder.dart:1048-1059`); this package uses one `SelectionArea` for the document, which reports a `SelectedContent` without offsets or cause | Adapted with a documented invariant ([2.2](#22-markdownwidget-constructor-parameters)): `cause` is always null |
| `contextMenuBuilder` (plus) with a custom function | Its type is `EditableTextContextMenuBuilder` (`fmp:widget.dart:263-277`), which needs an `EditableTextState`; `SelectionArea` takes a `SelectableRegionContextMenuBuilder` | Only the default and `null` are honored; a custom function is reported once and the default menu is used |
| Global accumulation of block tags | flutter_markdown appends every `isBlockElement()` builder key to a global list forever (`fm:builder.dart:253-257`, same in `fmp:builder.dart:198-202`) | Not replicated; block-ness is per widget |
| Builder for `table` being discarded | flutter_markdown overwrites a `table` builder's result with its own table (`fm:builder.dart:514-535`) | Not replicated; the builder's widget is used |
| Default image error display (empty `SizedBox`) | `fm:_functions_io.dart:75-81` | Kept this package's behavior: alt text (accessibility, `doc/images.md`) |
| Implicit `file:` / CWD-relative image loading without `imageDirectory` | `fm:_functions_io.dart:42-69` loads any non-network src with `Image.file` | Local files are an opt-in (`imageDirectory` or `imageResolver`, see `doc/images.md` and [4d](#4d-images)); `imageDirectory` counts as opt-in |
| Path traversal out of `imageDirectory` (`../x.png`, absolute src, symlink to the outside) | Allowed: `imageDirectory + src` goes to `Image.file` unchecked | Rejected on dart:io: the file must lie strictly inside the normalized directory (symlinks resolved); also rejected for `http(s)` directories and on the web when the src climbs above the directory. The alt text is shown ([4d](#4d-images), `doc/images.md`) |
| Loose task list items showing a bullet | flutter_markdown and flutter_markdown_plus inspect only `li.children[0]` for the checkbox `input`, so the items of a loose task list (separated by blank lines) get a bullet. That is a bug against GFM | Checkboxes are rendered for loose task lists (GFM-correct, an intentional difference). The `input` builder sequence is identical to plus ([5](#5-how-compatibility-is-tested)) |
| Task list checkbox invisible in dark themes | `fromTheme` sets `checkbox` to `bodyMedium.copyWith(color: theme.primaryColor)`. In a dark theme `primaryColor` is nearly the scaffold color, so the icon disappears | `fromTheme` (and so `largeFromTheme`) uses `theme.colorScheme.primary`. `fromCupertinoTheme` keeps `primaryColor` (a system blue, visible on dark). `test/style/style_sheet_test.dart` excludes `checkbox` from the comparison with plus, asserts that only its color differs, and asserts a contrast of at least 3:1 against the dark scaffold | Intentional: do not reproduce flutter_markdown bugs |
| Blockquote box unreadable in dark themes | `fromTheme` uses `Colors.blue.shade100` for every brightness, under the theme's near-white body text (about 1.1:1) | In a dark theme the box is `colorScheme.surfaceContainerHighest`; a light theme keeps the flutter_markdown color. Tested for 4.5:1 text contrast | Intentional: do not reproduce flutter_markdown bugs |
| Footnote definitions without a rule | `package:markdown` emits no rule before the footnote section | One extra `hr` before the definitions (the Rust parser emits a thematic break); the rest of the sequence is identical |
| `MarkdownStyleSheet` subclass equality | flutter_markdown's `==` requires `runtimeType == MarkdownStyleSheet` (`fm:style_sheet.dart:724-726`) | Identical (a subclass is never equal); listed because it defeats caching for subclasses |

---

## 2. Complete symbol and parameter table

Classification:

- **Identical**: same name, type, default, and observable behavior.
- **Adapted**: same name and type; behavior reproduced by a different mechanism, with the difference stated.
- **Accepted, no effect**: compiles; has no effect, with the reason.
- **Unsupported**: not provided (see section 1).

### 2.1 Public symbols

flutter_markdown exports `builder.dart`, `style_sheet.dart`, and `widget.dart`. The `_functions_io.dart` / `_functions_web.dart` members (`kDefaultImageBuilder`, `kFallbackStyle`, `kDefaultImageErrorWidgetBuilder`, `ImageBuilder`) are imported by `widget.dart` but not exported, so they are not part of the public API.

| Symbol | Source | Class | Notes |
|---|---|---|---|
| `MarkdownWidget` | `fm:widget.dart:220-359` | Adapted | Abstract `StatefulWidget` with the same constructor. Subclasses override `build(BuildContext, List<Widget>?)`; see 2.2 for what `children` contains |
| `Markdown` | `fm:widget.dart:531-590` | Adapted | Same parameters and defaults. Implemented with `CustomScrollView` + `SliverMarkdown` (lazy per block) instead of `ListView(children:)` |
| `MarkdownBody` | `fm:widget.dart:475-520` | Identical | Same `Column` / single-child logic (`fm:widget.dart:509-519`) |
| `MarkdownStyleSheet` | `fm:style_sheet.dart:9-843` | Identical (+ extras) | All fields, factories, `copyWith`, `merge`, `styles`, `==`, `hashCode`. Extra fields in [section 3](#3-extensions-to-markdownstylesheet-and-the-widgets). Two bug fixes noted in 2.4 |
| `MarkdownStyleSheetBaseTheme` | `fm:widget.dart:165-174` | Identical | `material`, `cupertino`, `platform` |
| `MarkdownListItemCrossAxisAlignment` | `fm:widget.dart:177-208` | Identical | `baseline`, `start` |
| `BulletStyle` | `fm:widget.dart:92-98` | Identical | `orderedList`, `unorderedList` |
| `MarkdownBulletParameters` | `fm:widget.dart:71-87` | Identical | `index`, `style`, `nestLevel`; derivation in 2.9.4 |
| `MarkdownImageConfig` | `fm:builder.dart:54-78` | Identical | Not in plus 1.0.12. Non-const constructor, fields `uri`, `title`, `alt`, `width`, `height` |
| `MarkdownElementBuilder` | `fm:widget.dart:110-157` | Adapted | Same four methods; call protocol in 2.5 |
| `MarkdownPaddingBuilder` | `fm:widget.dart:617-624` | Adapted | Same two methods; semantics in 2.6 |
| `SyntaxHighlighter` | `fm:widget.dart:103-107` | Identical | `TextSpan format(String source)` |
| `TaskListSyntax` | `fm:widget.dart:595-614` | Accepted, no effect | Kept as a deprecated `md.InlineSyntax` subclass. Passing it in `inlineSyntaxes` is a silent no-op (task lists are native) |
| `MarkdownTapLinkCallback` | `fm:widget.dart:32-33` | Identical | `void Function(String text, String? href, String title)` |
| `MarkdownImageBuilder` | `fm:widget.dart:53-54` | Identical | `Widget Function(Uri uri, String? title, String? alt)`; see the argument-order note in 2.9.3 |
| `MarkdownSizedImageBuilder` | `fm:widget.dart:48` | Identical | `Widget Function(MarkdownImageConfig config)`. Not in plus |
| `MarkdownCheckboxBuilder` | `fm:widget.dart:59` | Identical | `Widget Function(bool value)` |
| `MarkdownBulletBuilder` | `fm:widget.dart:64-66` | Identical | `Widget Function(MarkdownBulletParameters parameters)` |
| `MarkdownOnSelectionChangedCallback` | `fm:widget.dart:24-25` | Identical (type) | `void Function(String? text, TextSelection selection, SelectionChangedCause? cause)`; invocation is Adapted (2.2) |
| `MarkdownBuilder` | `fm:builder.dart:128` | Unsupported | Section 1 |
| `MarkdownBuilderDelegate` | `fm:builder.dart:104` | Unsupported | Section 1 |

### 2.2 `MarkdownWidget` constructor parameters

Defaults from `fm:widget.dart:224-248`.

| Parameter | Type / default | Class | Behavior in flutter_markdown (source) | This package |
|---|---|---|---|---|
| `key` | `Key?` | Identical | | |
| `data` | `String`, required | Identical | Split with `LineSplitter`, parsed with `md.Document(encodeHtml: false)` (`fm:widget.dart:395-404`) | Parsed by Rust. Per-block reuse unchanged |
| `selectable` | `bool = false` | Adapted | Every text run becomes a `SelectableText.rich` (`fm:builder.dart:1048-1059`); selection cannot cross blocks | Wraps the widget in one `SelectionArea` (`doc/accessibility.md`). Selection can cross blocks; the copy rules in `doc/accessibility.md` apply. Do not combine with an ancestor `SelectionArea` |
| `styleSheet` | `MarkdownStyleSheet?` | Identical | Merged onto the fallback: `kFallbackStyle(context, styleSheetTheme).merge(styleSheet)` (`fm:widget.dart:388-391`) | Same merge. Compared with `==` for invalidation ([4f](#4f-cache-invalidation-with-flutter_markdown-style-call-sites)) |
| `styleSheetTheme` | `MarkdownStyleSheetBaseTheme? = material` (but `Markdown`/`MarkdownBody` pass `null`, `fm:widget.dart:482, 538`) | Identical | `null` and `material` → `fromTheme(Theme.of)`; `cupertino` → `fromCupertinoTheme(CupertinoTheme.of)`; `platform` → Cupertino on iOS/macOS (`fm:_functions_io.dart:91-103`) or when the web user agent contains `Mac OS X` (`fm:_functions_web.dart:97-104`), Material otherwise. The result gets `copyWith(textScaler: MediaQuery.textScalerOf(context))` (`fm:_functions_io.dart:105-107`) | Same, computed in `didChangeDependencies` and kept while it compares `==` |
| `syntaxHighlighter` | `SyntaxHighlighter?` | Adapted | Called for `pre` text through `formatText`: one trailing `\n` is removed, then `format(code)`; when null, `TextSpan(style: styleSheet.code, text: code)` (`fm:widget.dart:453-460`) | Non-null: identical call, the returned span is used verbatim. Null: the built-in highlighter colors tokens with the extra field `MarkdownStyleSheet.codeSyntax`; when that is null, the plain `code` style is used exactly as flutter_markdown does ([4g](#4g-syntax-highlighting-default)) |
| `onTapLink` | `MarkdownTapLinkCallback?` | Adapted | `onTapLink(text, href, title)` through a `TapGestureRecognizer` per link (`fm:widget.dart:441-451`); argument derivation in 2.9.1 | Same arguments. `#id` links that exist in the document are handled internally by default ([4e](#4e-internal-anchor-links)) |
| `onSelectionChanged` | `MarkdownOnSelectionChangedCallback?` | Adapted | Per `SelectableText`: `(span.text, selection, cause)` (`fm:builder.dart:1053-1056`). In 0.7.7+1 `text` is `TextSpan.text`, which is null when the span has children; plus passes `toPlainText()` (`fmp:builder.dart:1021`) | Called from `SelectionArea.onSelectionChanged` with `text` = selected plain text, `selection = TextSelection(baseOffset: 0, extentOffset: text.length)`, `cause = null`. The invariant users rely on, `text.substring(selection.start, selection.end)` is the selected text, holds. Null content → not called |
| `onTapText` | `VoidCallback?` | Adapted | `SelectableText.onTap` for every text run when `selectable` (`fm:builder.dart:1057`) | When `selectable` and non-null, each block text gets a `GestureDetector(onTap:)`; link recognizers inside the paragraph still win the gesture arena |
| `imageDirectory` | `String?` | Adapted | Prefix for non-network srcs in the default image builder only (2.9.3) | Same string semantics; also counts as the opt-in for relative file paths ([4d](#4d-images)) |
| `blockSyntaxes` | `List<md.BlockSyntax>?` | Accepted, no effect / reported | `md.Document(blockSyntaxes:)` | [4b](#4b-extensionset-blocksyntaxes-and-inlinesyntaxes) |
| `inlineSyntaxes` | `List<md.InlineSyntax>?` | Accepted, no effect / reported | `md.Document(inlineSyntaxes:)` | [4b](#4b-extensionset-blocksyntaxes-and-inlinesyntaxes) |
| `extensionSet` | `md.ExtensionSet?` (null → `gitHubFlavored`, `fm:widget.dart:398`) | Adapted | Selects syntaxes | [4b](#4b-extensionset-blocksyntaxes-and-inlinesyntaxes) |
| `imageBuilder` | `@Deprecated MarkdownImageBuilder?` (plus: not deprecated) | Identical | Called with `(uri, alt, title)` in 0.7.7+1 (`fm:builder.dart:688`) against the typedef order `(uri, title, alt)`; plus calls `(uri, title, alt)` (`fmp:builder.dart:641`) | Called in typedef order `(uri, title, alt)` (plus). Annotated `@Deprecated` like 0.7.7+1 |
| `sizedImageBuilder` | `MarkdownSizedImageBuilder?` | Identical | Takes precedence over `imageBuilder`; `assert(imageBuilder == null \|\| sizedImageBuilder == null)` (`fm:builder.dart:146-147`, `683-688`) | Same precedence and assert |
| `checkboxBuilder` | `MarkdownCheckboxBuilder?` | Identical | 2.9.4 | |
| `bulletBuilder` | `MarkdownBulletBuilder?` | Identical | 2.9.4 | |
| `builders` | `Map<String, MarkdownElementBuilder> = const {}` | Adapted | 2.5 | Through the lazy `md.Element` bridge ([4a](#4a-builders-and-paddingbuilders)) |
| `paddingBuilders` | `Map<String, MarkdownPaddingBuilder> = const {}` | Adapted | 2.6 | Same bridge |
| `fitContent` | `bool = false` (`MarkdownBody`: `true`) | Identical | Block `Column` cross axis `start` vs `stretch` (`fm:builder.dart:452-464`); list item `Row(mainAxisSize: min/max)` and `Flexible(fit: loose/tight)` (`fm:builder.dart:490-511`); `MarkdownBody` column cross axis (`fm:widget.dart:513-517`) | Same three effects |
| `listItemCrossAxisAlignment` | `= baseline` | Identical | `baseline` → `Row(crossAxisAlignment: baseline, textBaseline: alphabetic)`; `start` → `CrossAxisAlignment.start`, no baseline (`fm:builder.dart:492-499`) | Same; the default is `baseline` |
| `softLineBreak` | `bool = false` | Adapted | `false`: `' ?\n *'` is replaced by one space; `true`: text kept, so the newline renders as a line break (`fm:builder.dart:378-403`) | Soft breaks are `MdxSoftBreak` nodes in the IR. `false` → `' '`, `true` → `'\n'` ([4c](#4c-soft-line-breaks-and-tight-lists)) |
| `contextMenuBuilder` (plus only) | `EditableTextContextMenuBuilder? = _default` (`fmp:widget.dart:216, 263-277`) | Adapted (partial) | Passed to each `SelectableText` | `null` → `SelectionArea(contextMenuBuilder: null)`; the default sentinel → the `SelectionArea` default; a custom function → reported once, default used (section 1) |

`build(BuildContext context, List<Widget>? children)` (`fm:widget.dart:354-355`): for user subclasses, `children` is a lazily materialized, unmodifiable list with flutter_markdown's shape: `[block0, SizedBox(height: blockSpacing), block1, ...]`. `Markdown` and `MarkdownBody` do not go through it internally (they keep the lazy sliver and the cached column).

### 2.3 `Markdown` and `MarkdownBody` specific parameters

| Widget | Parameter | flutter_markdown | Class | This package |
|---|---|---|---|---|
| `Markdown` | `padding` | `EdgeInsets = const EdgeInsets.all(16.0)` (`fm:widget.dart:554`) passed to `ListView` | Identical | `SliverPadding(padding)`. Because it is never null, MediaQuery insets are not added (same as `ListView` with explicit padding). Type is `EdgeInsets`, as in flutter_markdown |
| `Markdown` | `controller` | `ScrollController?` | Identical | `CustomScrollView.controller` |
| `Markdown` | `physics` | `ScrollPhysics?` | Identical | `CustomScrollView.physics` |
| `Markdown` | `shrinkWrap` | `bool = false` | Identical | `CustomScrollView.shrinkWrap` |
| `Markdown` | `noScroll` (plus) | `bool = false`; `Column` of children each wrapped in `Padding(padding)` (`fmp:widget.dart:544, 567-580`) | Identical | Same (eager, like `MarkdownBody`) |
| `MarkdownBody` | `shrinkWrap` | `bool = true`; one child and `shrinkWrap` → returns `children.single`; else `Column(mainAxisSize: shrinkWrap ? min : max, crossAxisAlignment: fitContent ? start : stretch)` (`fm:widget.dart:498, 509-519`) | Identical | Same |
| `MarkdownBody` | `fitContent` | `= true` (`fm:widget.dart:499`) | Identical | |

### 2.4 `MarkdownStyleSheet`

#### Fields

All fields (`fm:style_sheet.dart:545-716`), plus plus's two additions. Every field is Identical in type and default. "Consumed by" says where the renderer reads it, matching flutter_markdown.

| Field | Type (default) | Consumed by (flutter_markdown source) |
|---|---|---|
| `a` | `TextStyle?` | Link text, merged onto the parent inline style (`styles['a']`) |
| `p` | `TextStyle?` | `styles['p']`, also `li`, `pre`, `table` (`fm:style_sheet.dart:77-98`) |
| `pPadding` | `EdgeInsets?` | Padding of the text `Wrap` of a top-level `p` only (`fm:builder.dart:984-1002`, `811-819`) |
| `code` | `TextStyle?` | Inline code; code-block text when there is no highlighter (`fm:widget.dart:459`) |
| `h1`…`h6` | `TextStyle?` | Heading text (`styles['hN']`) |
| `h1Padding`…`h6Padding` | `EdgeInsets?` | Padding of a top-level heading's text `Wrap` |
| `em`, `strong`, `del` | `TextStyle?` | Merged onto the parent inline style |
| `blockquote` | `TextStyle?` | Text inside a blockquote. 0.7.7+1: `blockquote.merge(inlineStyle)` (`fm:builder.dart:427-429`, so `p` wins); plus: the blockquote style is the root inline style (`fmp:builder.dart:746`). **This package follows plus** (the blockquote style takes effect) |
| `img` | `TextStyle?` | Only as `preferredStyle` for an `img` builder |
| `checkbox` | `TextStyle?` | Default checkbox icon size (`fontSize`) and color (`fm:builder.dart:706-713`) |
| `blockSpacing` | `double?` | `SizedBox(height:)` between sibling blocks at every level, including list items (`fm:builder.dart:794-801`) |
| `listIndent` | `double?` | Bullet column width = `listIndent + listBulletPadding.left + listBulletPadding.right` (`fm:builder.dart:501-505`) |
| `listBullet` | `TextStyle?` | Default bullet text |
| `listBulletPadding` | `EdgeInsets?` | Around the default bullet, the `bulletBuilder` result, and the default checkbox (not the `checkboxBuilder` result) (`fm:builder.dart:702-754`) |
| `tableHead` | `TextStyle?` | `th` text, merged onto `tableBody` (`styles['th']`) |
| `tableBody` | `TextStyle?` | `tr`/`td` text and the cell `DefaultTextStyle` (`fm:builder.dart:760-762`) |
| `tableHeadAlign` | `TextAlign?` | Default alignment of `th` without an `align` attribute; `td` defaults to `TextAlign.left` (`fm:builder.dart:592-605`) |
| `tablePadding` | `EdgeInsets?` | Padding of the horizontal scroll view, used only when `tableColumnWidth` is `FixedColumnWidth` or `IntrinsicColumnWidth` (`fm:builder.dart:515-535`) |
| `tableBorder` | `TableBorder?` | `Table.border`; plus clips to `tableBorder.borderRadius` (`fmp:builder.dart:603-613`) |
| `tableColumnWidth` | `TableColumnWidth?` | `Table.defaultColumnWidth`; Fixed/Intrinsic adds horizontal scroll |
| `tableScrollbarThumbVisibility` | `bool?` | `Scrollbar.thumbVisibility` of that scroll view |
| `tableCellsPadding` | `EdgeInsets?` | Cell padding (`fm:builder.dart:758-759`) |
| `tableCellsDecoration` | `Decoration?` | `TableRow.decoration` of rows whose 0-based index is even and non-zero (2nd, 4th, … body rows); the header row and the 1st body row get none (`fm:builder.dart:298-312`). plus: header row gets `tableHeadCellsDecoration ?? tableCellsDecoration`, even rows `tableCellsDecoration`, odd rows none (`fmp:builder.dart:247-256`). **This package follows plus** |
| `tableHeadCellsPadding` (plus) | `EdgeInsets?` | `th` padding, falls back to `tableCellsPadding` (`fmp:builder.dart:706-716`) |
| `tableHeadCellsDecoration` (plus) | `Decoration?` | Header row decoration (above) |
| `tableVerticalAlignment` | `TableCellVerticalAlignment = middle` | `Table.defaultVerticalAlignment` |
| `blockquotePadding` | `EdgeInsets?` | `DecoratedBox(blockquoteDecoration, Padding(blockquotePadding, …))` (`fm:builder.dart:536-544`) |
| `blockquoteDecoration` | `Decoration?` | Same |
| `codeblockPadding` | `EdgeInsets?` | Padding of the horizontal `SingleChildScrollView` of a code block (`fm:builder.dart:409-423`) |
| `codeblockDecoration` | `Decoration?` | `Container(clipBehavior: hardEdge, decoration:)` around the code block (`fm:builder.dart:545-550`) |
| `horizontalRuleDecoration` | `Decoration?` | `Container(decoration:)` with no child, so its height is the decoration's border width (`fm:builder.dart:551-552`) |
| `textAlign` | `WrapAlignment = start` | Alignment of a top-level `p` |
| `h1Align`…`h6Align` | `WrapAlignment = start` | Alignment of a top-level heading |
| `unorderedListAlign`, `orderedListAlign` | `= start` | Alignment of all text inside a top-level list |
| `blockquoteAlign` | `= start` | Alignment of all text inside a top-level blockquote |
| `codeblockAlign` | `= start` | Alignment of a top-level code block |
| `superscriptFontFeatureTag` | `String?` | Extra font feature for `sup` (`fm:builder.dart:613-638`) |
| `textScaleFactor` | `@Deprecated double?` | Converted to `TextScaler.linear` |
| `textScaler` | `TextScaler?` | Every `Text.rich` (`fm:builder.dart:1050, 1063`) |

"Top-level" above is exact: flutter_markdown chooses alignment and text padding from `_currentBlockTag`, which is the **outermost** block tag being visited (`_currentBlockTag ??= tag`, `fm:builder.dart:275`, reset at `644-646`). A paragraph inside a blockquote uses `blockquoteAlign` and no `pPadding`; text inside a list uses `unorderedListAlign` / `orderedListAlign`. The renderer passes the top-level block kind down to reproduce this. An HTML `align` attribute (this package only) overrides it.

`superscriptFontFeatureTag` and `sup`: flutter_markdown always renders `sup` text with `FontFeature.enable('sups')` plus the optional tag (`fm:builder.dart:613-638`), which most fonts ignore. This package keeps its visual superscript (`WidgetSpan`, smaller font, top-aligned) when the tag is null, and switches to flutter_markdown's font-feature rendering when it is non-null. Classified Adapted.

#### Factories and methods

| Member | Class | Exact behavior (source) |
|---|---|---|
| `MarkdownStyleSheet({...})` | Identical | Non-const. Builds `styles` with exactly these keys: `a`, `p`, `li`→p, `code`, `pre`→p, `h1`…`h6`, `em`, `strong`, `del`, `blockquote`, `img`, `table`→p, `th`→tableHead, `tr`→tableBody, `td`→tableBody (`fm:style_sheet.dart:77-98`). Any other tag (`sub`, `ul`, `hr`, …) has no style, so builders get `preferredStyle == null`. Asserts `textScaler == null \|\| textScaleFactor == null` |
| `fromTheme(ThemeData)` | Identical | Table below (`fm:style_sheet.dart:101-165`) |
| `fromCupertinoTheme(CupertinoThemeData)` | Identical | Base `textTheme.textStyle`; `a` uses `CupertinoColors.link` (dark/light); `code` monospace ×0.85; h1…h5 `w500` and size +10/+8/+6/+4/+2, h6 `w500`; `em`/`strong`/`del` on the base style; `checkbox` color `primaryColor`; `blockSpacing` 8; `listIndent` 24; `tablePadding` bottom 8; `tableBorder` `TableBorder.all(CupertinoColors.separator, width: 0)`; `tableCellsDecoration` `systemGrey6`; `blockquotePadding` all 16; `blockquoteDecoration` `systemGrey6` + left border `systemGrey4` width 4; `codeblockPadding` 8; `codeblockDecoration` `systemGrey6`; rule top border `systemGrey4` (`fm:style_sheet.dart:168-273`) |
| `largeFromTheme(ThemeData)` | Identical | Same as `fromTheme` except h1 `displayMedium`, h2 `displaySmall`, h3 `headlineMedium`, h4 `headlineSmall`, h5 `titleLarge`, h6 `titleMedium` (`fm:style_sheet.dart:279-342`) |
| `copyWith({...})` | Identical (one fix) | `x ?? this.x` for every field (`fm:style_sheet.dart:346-473`), **except** `tableScrollbarThumbVisibility`, which 0.7.7+1 and plus do not carry over (`fm:style_sheet.dart:446`). This package carries it over. `textScaler`/`textScaleFactor` exclusivity as in `409-412` |
| `merge(MarkdownStyleSheet?)` | Identical (one fix) | null → `this`. TextStyle fields `this.x!.merge(other.x)`; every other field `other.x` through `copyWith` (so null keeps the base) (`fm:style_sheet.dart:477-542`). flutter_markdown throws when a base TextStyle field is null (`a!`); this package merges null-safely (`this.x?.merge(other.x) ?? other.x`) |
| `styles` | Identical | Getter for the map above |
| `==` / `hashCode` | Identical (extended) | flutter_markdown **does** override both (`fm:style_sheet.dart:718-842`). `==` returns false for any subclass (`724-726`) and omits `tableScrollbarThumbVisibility` and `textScaleFactor`; `hashCode` includes `textScaleFactor` but omits `tableScrollbarThumbVisibility`. This package includes every field, including the extras, in both |

#### `MarkdownStyleSheet.fromTheme` exact mapping

From `fm:style_sheet.dart:101-165` (0.7.7+1). The plus values differ only where marked.

| Field | Value |
|---|---|
| `a` | `TextStyle(color: Colors.blue)` (no underline) |
| `p` | `textTheme.bodyMedium` |
| `pPadding`, `h1Padding`…`h6Padding` | `EdgeInsets.zero` |
| `code` | `bodyMedium.copyWith(backgroundColor: theme.cardTheme.color, fontFamily: 'monospace', fontSize: bodyMedium.fontSize * 0.85)` |
| `h1` / `h2` / `h3` | `headlineSmall` / `titleLarge` / `titleMedium` |
| `h4` / `h5` / `h6` | `bodyLarge` (all three) |
| `em` | `TextStyle(fontStyle: italic)` |
| `strong` | `TextStyle(fontWeight: bold)` |
| `del` | `TextStyle(decoration: lineThrough)` |
| `blockquote`, `img`, `listBullet`, `tableBody` | `bodyMedium` |
| `checkbox` | `bodyMedium.copyWith(color: theme.primaryColor)` |
| `blockSpacing` | `8.0` |
| `listIndent` | `24.0` |
| `listBulletPadding` | `EdgeInsets.only(right: 4)` |
| `tableHead` | `TextStyle(fontWeight: w600)` |
| `tableHeadAlign` | `TextAlign.center` |
| `tablePadding` | `EdgeInsets.only(bottom: 4.0)` |
| `tableBorder` | `TableBorder.all(color: theme.dividerColor)` |
| `tableColumnWidth` | `FlexColumnWidth()` |
| `tableCellsPadding` | `EdgeInsets.fromLTRB(16, 8, 16, 8)` |
| `tableCellsDecoration` | `BoxDecoration()` |
| `blockquotePadding` | `EdgeInsets.all(8.0)`. plus: `EdgeInsets.symmetric(horizontal: 12, vertical: 4)` (`fmp:style_sheet.dart:146`) |
| `blockquoteDecoration` | `BoxDecoration(color: Colors.blue.shade100, borderRadius: circular(2.0))`. plus: `color: colorScheme.surfaceContainerHighest`, `borderRadius: circular(3)`, left border `colorScheme.primary` width 3 (`fmp:style_sheet.dart:147-155`) |
| `codeblockPadding` | `EdgeInsets.all(8.0)` |
| `codeblockDecoration` | `BoxDecoration(color: theme.cardTheme.color ?? theme.cardColor, borderRadius: circular(2.0))` |
| `horizontalRuleDecoration` | `BoxDecoration(border: Border(top: BorderSide(width: 5.0, color: theme.dividerColor)))` |
| alignments, `tableVerticalAlignment` | constructor defaults |
| `textScaler`, `superscriptFontFeatureTag`, `tableScrollbarThumbVisibility` | null |

For the two blockquote fields this package uses the 0.7.7+1 constants (blue-100 fill, padding 8), except in dark themes (section 1). The extra fields get theme-derived values in all three factories ([section 3](#3-extensions-to-markdownstylesheet-and-the-widgets)).

### 2.5 `MarkdownElementBuilder` call protocol

All four methods keep their signatures (`fm:widget.dart:110-157`). The protocol below is what flutter_markdown does; the bridge in [4a](#4a-builders-and-paddingbuilders) reproduces it, in the same order, for every IR node whose tag has a registered builder.

Traversal is `md.Element.accept`: `visitElementBefore` returns a bool; only when true are children visited and `visitElementAfter` called (`md:ast.dart:42-51`).

| Step | flutter_markdown (source) | Notes |
|---|---|---|
| `builders[tag].visitElementBefore(element)` | Called when the element is entered, before any check, for block and inline tags alike (`fm:builder.dart:278-280`) | For an empty link, it is called and then `visitElementBefore` returns false, so children and `after` are skipped (`fm:builder.dart:320-325`) |
| `isBlockElement()` | `true` makes the tag a block tag (`fm:builder.dart:253-257`; plus checks per visit, `fmp:builder.dart:234, 385`) | For IR-derived tags the block/inline nature is fixed by the IR. It is honored for custom nodes (`MdxCustomBlock`/`MdxCustomInline`) and decides whether `visitText` is routed to the builder |
| `builders[blockTag].visitText(text, styles[blockTag])` | Called for **every** `md.Text` whose innermost enclosing block (`_blocks.last.tag`) has a builder, including text nested inside inline elements of that block (`fm:builder.dart:406-408`). The returned widget replaces the default text; **null drops the text** from the default rendering | Only block builders (`p`, `hN`, `pre`, `li`, `blockquote`, custom blocks, …) receive text. A `code` builder never does: code-block text is routed by the block tag `pre` |
| Inline `visitElementAfterWithContext(context, element, styles[tag], parent.style)` | `parent.style` is the merged style of the enclosing inline (`fm:builder.dart:565-578`). A non-null widget replaces the inline's children: 0.7.7+1 replaces only `children[0]` (siblings leak, issue #132); plus clears and adds (`fmp:builder.dart:513-519`) | **Follows plus** |
| Block `visitElementAfterWithContext(context, element, styles[tag], parentStyle)` | Result replaces the default `Column` of the block (`fm:builder.dart:466-472`); `parentStyle` is `_inlines.last.style` if inlines remain, otherwise null. plus always clears inlines first (`fmp:builder.dart:798`), so it is null | Always null (plus) |
| Wrapping of a block builder's result | `li` → still wrapped in the bullet/checkbox `Row`; `blockquote` → still wrapped in decoration + padding; `pre` → still wrapped in `codeblockDecoration`; `table` → **discarded** and replaced by the default table; `hr` → 0.7.7+1 discards it, plus keeps it (`fm:builder.dart:474-553`, `fmp:builder.dart:483-494`) | Same wrapping for `li`, `blockquote`, `pre`. `table` and `hr`: the builder's widget is used (plus for `hr`; a fix for `table`) |
| Inline builder for `a` | plus: when `builders` has `a`, no link recognizer is created or removed (`fmp:builder.dart:272, 556-558`) | **Follows plus**: a custom `a` builder owns tap handling |
| Widget merging | Returned `Text`, `RichText`, and `SelectableText` widgets are merged into the surrounding text run (`fm:builder.dart:869-932`); other widgets become separate `Wrap` children with `WrapCrossAlignment.center` | A returned `Text`/`RichText` is spliced as its `InlineSpan` into the paragraph's `Text.rich`; any other widget becomes a `WidgetSpan(alignment: PlaceholderAlignment.middle)` |

Order example for `` ```dart\nx\n``` `` with `builders: {'code': B}`:

1. `B.visitElementBefore(code)` (`pre` has no builder).
2. The text is rendered by the default `pre` path (`_blocks.last.tag == 'pre'`, `fm:builder.dart:409-423`) into the `code` inline.
3. `B.visitElementAfterWithContext(ctx, code, styles['code'], styles['pre'])`; its widget replaces the scroll view.
4. `pre` closes: the result is wrapped in `Container(decoration: codeblockDecoration)` (`fm:builder.dart:545-550`).

The same `B` is also called for inline `` `x` ``. Users tell the two apart with `element.attributes['class']` (`language-x`, fenced only, `md:block_syntaxes/fenced_code_block_syntax.dart:44-53`; indented blocks have no class, `md:block_syntaxes/code_block_syntax.dart:65`) or the trailing `\n` in `element.textContent` (both code block syntaxes append one, `fenced_code_block_syntax.dart:38-40`, `code_block_syntax.dart:54-59`). The bridge re-appends that `\n` (the IR strips it, `native/src/lib.rs:930-932`).

### 2.6 `MarkdownPaddingBuilder` semantics

| Step | flutter_markdown (source) | This package |
|---|---|---|
| `visitElementBefore(element)` | Called when an element with that tag is entered (`fm:builder.dart:282-284`) | Same, in traversal order. Builders may be stateful (`getPadding()` is called later) |
| `getPadding()` for block tags | Replaces the text padding of the anonymous text `Wrap` when the **outermost** block tag (`_currentBlockTag`) has a padding builder (`fm:builder.dart:811-819`). So `paddingBuilders['p']` affects only top-level paragraphs; `paddingBuilders['blockquote']` affects the text inside a top-level blockquote | Same rule |
| `getPadding()` for inline tags | Computed for every registered inline tag (`fm:builder.dart:559-563`) but **applied only to `img`** (`fm:builder.dart:579-588`) | Same: only `img` |
| `hr` | plus wraps the rule in `Padding(getPadding())` (`fmp:builder.dart:488-494`) | Same (plus) |

### 2.7 Typedefs and value classes

Covered in 2.1. `MarkdownImageConfig` and `MarkdownBulletParameters` are not `const`-comparable value types in flutter_markdown (no `==`); they stay that way.

### 2.8 flutter_markdown_plus 1.0.12 differences (public API)

Diffed file by file against 0.7.7+1.

| Item | plus 1.0.12 | Effect on this design |
|---|---|---|
| `MarkdownSizedImageBuilder`, `MarkdownImageConfig`, `sizedImageBuilder` | Absent | Provided (0.7.7+1) |
| `imageBuilder` | Not deprecated; called `(uri, title, alt)` (`fmp:builder.dart:641`) | Called `(uri, title, alt)`; annotated `@Deprecated` as in 0.7.7+1 |
| `contextMenuBuilder` | Added (`fmp:widget.dart:216, 263-277`) | Adapted (partial) |
| `Markdown.noScroll` | Added (`fmp:widget.dart:544, 567-580`) | Identical |
| `tableHeadCellsPadding`, `tableHeadCellsDecoration` | Added (`fmp:style_sheet.dart:47-48, 659-668`) | Identical |
| `fromTheme` / `largeFromTheme` blockquote | New padding and decoration (`fmp:style_sheet.dart:146-155, 327-336`) | Not followed (0.7.7+1 constants) |
| Blockquote text style | Root inline style (`fmp:builder.dart:746`) | Followed |
| Builder result replaces all inline children | `fmp:builder.dart:513-519` | Followed |
| `a` builder owns links | `fmp:builder.dart:272, 556-558` | Followed |
| `hr` builder and `hr` padding | `fmp:builder.dart:483-494` | Followed |
| Table border radius clip | `fmp:builder.dart:603-613` | Followed |
| Forced strut per text block | `StrutStyle(forceStrutHeight: true)` from the span's base style (`fmp:builder.dart:1000-1018`) | Not followed by default: it changes line height of mixed-size runs (inline math, citation chips). Listed as a visual difference |
| `onSelectionChanged` text | `toPlainText()` (`fmp:builder.dart:1021`) | The adapted callback passes plain text |
| Trailing inline flush at end of document | `_addAnonymousBlockIfNeeded()` after the loop (`fmp:builder.dart:211`) | Not applicable |

### 2.9 Extracted behaviors (reference)

#### 2.9.1 Links and `onTapLink`

From `fm:builder.dart:320-332, 355-365, 611-612`:

- `text` = `extractTextFromElement(a)`: concatenation of all descendant `md.Text` texts. A descendant element without children contributes `attributes['alt']` if it has attributes (an image → its alt; if `alt` is missing this yields the string `null`), or `''` if it has none (`br`). Soft line breaks appear as a raw `\n` in `text`, regardless of `softLineBreak` (trimming applies only to rendering, `fm:builder.dart:378-403`).
- `href` = `attributes['href']` (`String?`). The markdown package normalizes destinations with `Uri.encodeFull` after decoding (`md:util.dart:45-63`); the Rust side uses `uri::encode_full` (`native/src/uri.rs`), which keeps existing `%XX` escapes and reserved characters. Equal for ordinary URLs; byte-level differences for unusual inputs are listed as known differences.
- `title` = `attributes['title'] ?? ''`: **empty string, never null**, when the link has no title.
- A link with no children (`[](u)`) returns `false` from `visitElementBefore`: nothing is rendered and nothing is tappable.
- An image inside a link is wrapped in `GestureDetector(onTap: recognizer.onTap)`, so tapping the image fires the link (`fm:builder.dart:693-699`). This package does the same for the default image view and for `imageBuilder` / `sizedImageBuilder` widgets. If `onTapImage` is also set, it runs first and `onTapLink` second: both fire, the image callback does not suppress the link. A link owned by an `a` builder has no tap, so neither has its image.
- Footnotes (markdown 7.3.1): a reference is `sup.footnote-ref > a[href="#fn-x"][id="fnref-x"]` with text `1` (`md:inline_syntaxes/footnote_ref_syntax.dart:69-73`), so `onTapLink('1', '#fn-x', '')`. A backref is `a.footnote-backref[href="#fnref-x"]` with text `↩` (`md:document.dart:177-192`).
- Internal `#id` links are forwarded to `onTapLink` like any other link; flutter_markdown never scrolls. This package's default is in [4e](#4e-internal-anchor-links).

#### 2.9.2 `href` / `title` mapping from the IR

`MdxLink.href` → `href`; `MdxLink.title ?? ''` → `title`; text extracted from the IR children with the rules above (`MdxImage` → `alt`, `MdxLineBreak` → `''`, `MdxSoftBreak` → `\n`, custom inline → its children).

#### 2.9.3 Images

`_buildImage(src, title, alt)` (`fm:builder.dart:659-700`):

1. `parts = src.split('#')`. `path = parts.first`. If exactly two parts and `parts.last.split('x')` has two entries, `width = double.tryParse(...)`, `height = double.tryParse(...)`. So `![a](x.png#100x50)` sizes the image and `x.png#a#b` does not.
2. `uri = Uri.tryParse(path)`; null → `SizedBox()`.
3. `sizedImageBuilder(MarkdownImageConfig(uri:, alt:, title:, width:, height:))`, else `imageBuilder(uri, …)`, else `kDefaultImageBuilder(uri, imageDirectory, width, height)`.

The uri passed to `sizedImageBuilder` / `imageBuilder` is **not** resolved with `imageDirectory`; only the default builder uses it. `alt` is always present for Markdown images (`md:inline_syntaxes/image_syntax.dart:27-35`); `title` only when given.

The IR keeps `#` in `MdxImage.src` (`native/src/lib.rs:829-839` with `uri::encode_full`, `#` is reserved), so the same split works. Superset: when the fragment has no size and `MdxImage.width`/`height` came from an HTML `<img>`, those values fill `MarkdownImageConfig.width`/`height`.

`kDefaultImageBuilder` (`fm:_functions_io.dart:20-71`, web `fm:_functions_web.dart:21-78`):

| scheme | io | web |
|---|---|---|
| `http`, `https` | `Image.network(uri)` | same |
| `data` | `image/*` → `Image.memory(bytes)`; `text/*` → `Text(contentAsString())`; other → `SizedBox()` (`110-124`) | same |
| `resource` | `Image.asset(uri.path)` | same |
| anything else | `fileUri = imageDirectory != null ? Uri.parse(imageDirectory + uri.toString()) : uri` (string concatenation, **no separator**); http(s) → network; else `Image.file(File.fromUri(fileUri))` | `fileUri = Uri.parse(p.join(imageDirectory, uri))`; http(s) → network; else `Image.network(p.join(p.current, fileUri))` (relative to the page) |

All errors render `SizedBox()` (`kDefaultImageErrorWidgetBuilder`, `fm:_functions_io.dart:75-81`). How this package differs is in [4d](#4d-images).

#### 2.9.4 Checkboxes and bullets

From `fm:builder.dart:477-513, 702-754` and `md:block_syntaxes/list_syntax.dart:246-316`:

- The markdown package inserts `input[type=checkbox]` (plus `checked="true"` only when checked) as the first child of `li`, or as the first child of the item's first `p` for loose lists (`list_syntax.dart:255-270, 319-327`). `li` gets `class="task-list-item"`; the list gets `class="contains-task-list"` (`313-315`). No `disabled` attribute (only the deprecated `TaskListSyntax` sets it, `fm:widget.dart:607-610`).
- flutter_markdown checks only `li.children[0]`: if it is an element with `type == checkbox`, it renders `_buildCheckbox(attributes.containsKey('checked'))`; otherwise a bullet (`fm:builder.dart:483-489`). Consequence: **loose task lists show a bullet in flutter_markdown and flutter_markdown_plus** (verified against both packages), although the `input` element is present and its builder is called. This package shows the checkbox: the Rust parser reports the task marker of loose items (pulldown-cmark emits it inside the item's first paragraph), the item has `checked` set, `checkboxBuilder` is called instead of `bulletBuilder`, and the `input` builder is called with the same sequence as plus. The difference is intentional: the source asks for a checkbox.
- The `input` element itself is visited as an inline element: an `input` builder is called and its widget is inserted into the item text.
- `checkboxBuilder(checked)`: result used as is (no padding). Default: `Padding(listBulletPadding, Icon(checked ? Icons.check_box : Icons.check_box_outline_blank, size: checkbox.fontSize, color: checkbox.color))`.
- `bulletBuilder(MarkdownBulletParameters(index:, style:, nestLevel:))`, wrapped in `Padding(listBulletPadding)`:
  - `index` = `_blocks.last.nextListIndex` read while building the bullet. It starts at `int.parse(start) - 1` when the list has a `start` attribute, else 0 (`fm:builder.dart:290-293, 314-317`), and is incremented after each item is added (`fm:builder.dart:800`). `start` is only emitted for ordered lists with a start other than 1 (`list_syntax.dart:308-311`). So `index = (orderedStart - 1) + itemPosition` for ordered lists and `itemPosition` for unordered lists. From the IR: `ordered ? start - 1 + i : i`.
  - `style` = `unorderedList` for `ul`, `orderedList` for `ol`.
  - `nestLevel` = `_listIndents.length - 1`: number of enclosing `ul`/`ol` minus one (0 for a top-level list). Blockquotes do not reset it.
- Default bullets: unordered `Text('•', textAlign: center, style: listBullet)`; ordered `Text('${index + 1}.', textAlign: right, style: listBullet)`.
- `li` row: `SizedBox(width: listIndent + listBulletPadding.horizontal, child: bullet)` + `Flexible(fit: fitContent ? loose : tight, child: content)`.

#### 2.9.5 Code blocks

`pre > code[class="language-<first word of info>"]` with text `code + '\n'` (`md:block_syntaxes/fenced_code_block_syntax.dart:29-62`); `pre[data-metadata]` holds the rest of the info string. The rendered block is `Container(clipBehavior: hardEdge, decoration: codeblockDecoration, child: Scrollbar(SingleChildScrollView(horizontal, padding: codeblockPadding, child: Text.rich(formatText(code)))))` (`fm:builder.dart:409-423, 545-550`).

#### 2.9.6 Tables

`table > thead > tr > th[align]` and `tbody > tr > td[align]`; `align` is `left`, `center`, or `right` (`md:block_syntaxes/table_syntax.dart:42-70, 178-186`). Empty `td` gets `md.Text('')` (`fm:builder.dart:336-343`). Cells: `TableCell(Padding(tableCellsPadding, DefaultTextStyle(tableBody, textAlign:, Wrap(alignment:, children))))` (`fm:builder.dart:756-775`).

#### 2.9.7 Footnotes and alerts in the markdown package

- Footnote definitions: `section.footnotes > ol > li[id="fn-x"]`, appended to the document (`md:document.dart:135-151`). `section` is a block tag (`fm:builder.dart:31`).
- Alerts (`gitHubWeb` only): `div.markdown-alert.markdown-alert-<kind> > p.markdown-alert-title` + children (`md:block_syntaxes/alert_block_syntax.dart:106-110`). `div` is not a block tag in flutter_markdown.

---
## 3. Extensions to `MarkdownStyleSheet` and the widgets

### Extra style sheet fields

`MarkdownStyleSheet` has a few fields that flutter_markdown does not. They cover features of this package (highlighting, alerts, citations, `==mark==`).

| Field | Type | When null |
|---|---|---|
| `mark` | `TextStyle?` | `TextStyle(backgroundColor: colorScheme.tertiaryContainer)` at render time; the factories set it. Not added to `styles` (the map keeps flutter_markdown's 19 keys, so a `mark` builder gets `preferredStyle == null`, as it would in flutter_markdown) |
| `codeSyntax` | `MarkdownXSyntaxColors?` | No built-in highlighting (flutter_markdown look). The factories set light or dark colors by brightness. A non-null `background` replaces the color of `codeblockDecoration` when it is a `BoxDecoration`; `foreground` sets the code text color ([4g](#4g-syntax-highlighting-default)) |
| `codeBlockOptions` | `MarkdownXCodeBlockOptions?` | No code block header |
| `alerts` | `MarkdownXAlertStyle?` | Light or dark by `Theme.of(context).brightness` at render time |
| `citation` | `MarkdownXCitationStyle?` | Derived from `colorScheme.secondaryContainer` |
| `listItemSpacing` | `double?` | `blockSpacing`, which is what flutter_markdown does (list items are sibling blocks, `fm:builder.dart:794-801`). An override only |

Rules for the extras:

- Nullable; null means the default in the table (derived at render time).
- Included in the constructor, `copyWith`, `merge` (other wins when non-null), `==`, and `hashCode`.
- Set by `fromTheme`, `fromCupertinoTheme`, and `largeFromTheme` to theme-derived values. The flutter_markdown fields of these factories keep flutter_markdown's exact values.
- Documented on the class under a "flutter_markdown_x extensions" heading.

Tags without a flutter_markdown style field (`u`, `small`, `big`, `sub`, `sup`, `kbd`, `samp`, `tt`, `abbr`, `acronym`) are styled relative to the parent text: `kbd` uses `code`, `cite` / `dfn` / `var` use `em`, and `samp` / `tt` use the font family of `code` without its background. `small` is 1 / 1.2 of the parent and `big` 1.2 times (CSS `smaller` / `larger`). Emphasis uses `em`, strong `strong`, strikethrough `del`, the checkbox icon `checkbox`, list markers `listBullet`, and the table header weight `tableHead`.

`MarkdownXDefaults` holds the constants that have no style-sheet field (`codeChunkLines`, `maxImageExtent`, script and small scales, the code font fallback list).

### Extra widget parameters

These parameters have no flutter_markdown equivalent and come after the flutter_markdown parameters.

| Parameter | Notes |
|---|---|
| `SliverMarkdown` (widget) | Same parameters as `MarkdownWidget` minus scrolling and `selectable` |
| `imageResolver`, `imageLoadingBuilder`, `imageErrorBuilder`, `onTapImage` | Apply to the default image path only |
| `blockBuilder`, `inlineBuilder` | IR-typed builders, no `md.Element` conversion, evaluated before `builders` |
| `extensions`, `alerts`, `citationBuilder`, `onTapCitation`, `markdownController`, `handleAnchorLinks`, `streaming` | See the feature documents in `doc/` |
| `onTapCheckbox: void Function(MarkdownXTask)?` | Makes task checkboxes interactive; the app rewrites its `data` with `MarkdownXTask.toggle`. `null` (default) keeps flutter_markdown's display-only checkboxes. Builders still see the unchanged `input` element, and `checkboxBuilder` widgets are wrapped, not replaced ([syntax.md](syntax.md#toggling-task-checkboxes)) |

Image priority: `inlineBuilder` (`inline is MdxImage`), then `builders['img']`, then `sizedImageBuilder` / `imageBuilder`, then `imageResolver`, then the default resolver. The flutter_markdown builders never return null and get no context; `inlineBuilder` has a context and a null fallback.

`highlightCode` (the built-in highlighter) is exported ([4g](#4g-syntax-highlighting-default)). Language-aware customization goes through `builders['pre']` / `builders['code']` or `blockBuilder` (`block is MdxCodeBlock`), because flutter_markdown's `SyntaxHighlighter` interface has no language argument.

---

## 4. Behavior notes

The rules below say what this package does where flutter_markdown's behavior cannot be reproduced one to one, or where a different behavior is intended, and why.

### 4a. `builders` and `paddingBuilders`

`markdown: ^7.3.1` is a regular dependency. The lower bound comes from the classes used: `AlertBlockSyntax` exists since 7.2.0, and `pre[data-metadata]` is emitted since 7.3.1. It equals flutter_markdown_plus's constraint and is inside flutter_markdown 0.7.7+1's `^7.1.1`, so an app can hold either package next to this one. Only `ast.dart` types and `ExtensionSet` are used; `package:markdown` is not re-exported (flutter_markdown does not re-export it either, and users import it `as md`).

The renderer converts the IR to `md.Element` lazily:

- The registered tag set is `builders.keys ∪ paddingBuilders.keys`. If it is empty, the conversion never happens.
- A cached bit set per IR block says which tags occur in its subtree. A block with no registered tag renders through the IR renderer only.
- A block that contains a registered tag gets a fresh `md.Element` subtree on each build of that block (flutter_markdown and user builders mutate elements, e.g. `fm:builder.dart:339-343, 479-481`). The whole subtree of such a block is converted.
- The builder methods run in the 2.5 order in a pre-pass inside the block's `build`, so the `BuildContext` passed to builders belongs to that block, inherited dependencies a builder reads (`Theme.of(context)`) rebuild it, and it reruns only when the block rebuilds. The pre-pass is needed because Flutter builds a parent widget before its children, so a parent's `visitElementAfter` could not run after its children's. It walks the elements with a port of `MarkdownBuilder`'s `visitElementBefore` / `visitText` / `visitElementAfter` (including the outermost block tag, the inline style stack, and the anonymous text block for padding builders) and records the returned widgets by IR node; the renderer then reads them.

**Tag mapping (every IR node).**

| IR node | md tag | Attributes | Children |
|---|---|---|---|
| `MdxParagraph` | `p` | `align` (this package only, when set) | inlines |
| `MdxHeading(level)` | `h1`…`h6` | `align` (extra). `generatedId` = the GitHub-compatible heading id (`doc/navigation.md`, without the `-1` de-duplication suffix) when `extensionSet` is `gitHubWeb` (like `HeaderWithIdSyntax`, `md:block_syntaxes/header_with_id_syntax.dart:10-17`) | inlines |
| `MdxCodeBlock` | `pre` > `code` | `pre[data-metadata]` = rest of the info string; `code[class="language-<language>"]` when a language exists | `md.Text(code + '\n')` when code is non-empty |
| `MdxBlockquote` | `blockquote` | | blocks |
| `MdxList` | `ul` / `ol` | `start` when ordered and `start != 1`; `class="contains-task-list"` when any item is a task | `li` items |
| `MdxListItem` | `li` | `class="task-list-item"` for tasks | Tight list: paragraphs are unwrapped into the `li`, with `md.Text('\n')` inserted before a paragraph whose previous sibling is an element, except in task-list items (`md:block_syntaxes/list_syntax.dart:279-306`). Loose: blocks as is. Task: `input[type=checkbox]` (`checked="true"` when checked) first in `li` (tight) or first in the first `p` (loose) |
| `MdxTable` | `table` > `thead` > `tr` > `th`; `tbody` > `tr` > `td` | `align` on cells with an alignment; `colspan`/`rowspan` when not 1 (extra) | `tbody` omitted when there are no rows (`md:block_syntaxes/table_syntax.dart:66`) |
| `MdxThematicBreak` | `hr` | | |
| `MdxDetails` | `details` > `summary` | `open` when open | summary inlines, then blocks |
| `MdxCustomBlock(alert)` | `div` | `class="markdown-alert markdown-alert-<kind>"` | `p.markdown-alert-title` with the title text, then blocks (`md:block_syntaxes/alert_block_syntax.dart:106-110`) |
| `MdxCustomBlock(math)` | `math` | `tex`, `display`, and the other IR attributes | `md.Text(tex)` |
| `MdxCustomBlock(mermaid)` | `mermaid` | `source` (and `pending` while streaming) | `p` with inlines (none), then the original code block as `pre` > `code` (so `builders['code']` still sees `class="language-mermaid"` when no Mermaid builder replaces it; without the extension, nothing changes) |
| `MdxCustomBlock(other)` | `<type>` | IR attributes | `p` with inlines (if any), then blocks |
| footnote tail (the ordered list that `doc/navigation.md` identifies as the footnotes) | `section.footnotes` > `ol` > `li[id="fn-<label>"]` | | The preceding `hr` stays a separate `hr` (known difference: markdown emits no rule) |
| `MdxText` | `md.Text` | | Adjacent `MdxText` and `MdxSoftBreak` are merged into one `md.Text` (the markdown package keeps the newline inside the text node) |
| `MdxSoftBreak` | inside `md.Text` as `\n` | | |
| `MdxLineBreak` | `br` | | |
| `MdxStyled(strong/emphasis/strikethrough)` | `strong` / `em` / `del` | | |
| `MdxStyled(code)` | `code` | | `md.Text` |
| `MdxStyled(keyboard/mark/underline/small/subscript/superscript)` | `kbd` / `mark` / `u` / `small` / `sub` / `sup` | | |
| `MdxStyled(cite/definition/variable/sample/teletype/big)` | `cite` / `dfn` / `var` / `samp` / `tt` / `big` | | The original HTML tag name; `preferredStyle` is null (the style sheet has no field for them) |
| `MdxStyled(abbreviation/acronym)` | `abbr` / `acronym` | `title` when present | The original HTML tag name. `q`, `bdi`, `bdo` and `wbr` have no element: the parser already turned them into text (quotation marks, bidi controls, U+200B) |
| footnote reference (superscript link to `#fn-*`) | `sup.footnote-ref` > `a` | `a[href="#fn-x"][id="fnref-x"]` | `md.Text('1')` |
| footnote backref (`#fnref-*` link) | `a.footnote-backref` | `href` | `md.Text('↩')` |
| `MdxLink` | `a` | `href`; `title` when present | inlines |
| `MdxImage` | `img` | `src` (raw, including `#WxH`), `alt` (always), `title` when present; `width`/`height` when from HTML (extra) | none |
| `MdxSpan` | `span` | `style` reconstructed from `MdxInlineStyle` (`color: #rrggbb[aa]; background-color: …; font-size: Npx; font-weight: bold; font-style: italic; text-decoration: underline line-through`) | inlines |
| `MdxCustomInline(citation)` | `citation` | `id`, `ids` | children |
| `MdxCustomInline(math)` | `math` | `tex`, `display`, `raw`, `pending` | `md.Text(tex)` |
| `MdxCustomInline(other)` | `<type>` | IR attributes | children |

A `MarkdownXInlineSyntax` that builds `MdxCustomInline('sub', children: …)` makes an existing `builders: {'sub': SubscriptBuilder()}` work unchanged, because the bridge uses `type` as the tag.

Other details of the bridge:

- A returned `Text` or `RichText` is spliced into the paragraph's `Text.rich` as its span (its `key` is lost, as in flutter_markdown, which rebuilds the merged text). Any other widget is a `WidgetSpan(alignment: middle)`. Block results replace the block: for `li` the content next to the bullet, for `blockquote` the content inside the decoration and padding, for `pre`/`code` the scrolling text inside the code block container, for `td`/`th` the content of the cell, for `summary` the summary text; `ul`, `ol`, `table`, `hr`, paragraphs, headings, `details`, alerts and custom blocks are replaced as a whole. `input` builder results are shown before the text of the item's first paragraph.
- `thead`, `tbody`, `tr` and the inner list of `section`: builders are called (protocol and padding), but their results are not displayed (the IR renderer has no widget for a row). A `section` builder (footnote definitions) replaces the whole list.
- `visitText` for text that has no counterpart IR node (the `'\n'` that tight lists insert between paragraphs, the alert title) is called, but its result is ignored.
- `isBlockElement()` of a builder for an inline tag (for example a custom inline) makes it a block frame for text routing, padding flushes and `visitText`, but its result is still placed inline: the IR renderer does not split a paragraph.
- `blockBuilder` / `inlineBuilder` (extras) run first, but they do not short-circuit the bridge: element builders of a block are visited before `blockBuilder` decides to replace it.
- The footnote definitions are detected as an ordered list whose items all end with the back reference link.

`MarkdownBuilder` / `MarkdownBuilderDelegate` are unsupported (section 1).

### 4b. `extensionSet`, `blockSyntaxes`, and `inlineSyntaxes`

All three are accepted for compile compatibility. GFM is always on: the Rust parser runs with tables, strikethrough, task lists, and footnotes (`native/src/lib.rs:41-45`), GFM autolinks (`native/src/autolink.rs`), and the HTML allowlist. Custom syntaxes are reported rather than ignored silently or thrown, so content never disappears without a signal and a migrating app does not crash on the first frame.

| `extensionSet` | flutter_markdown (`md:extension_set.dart`) | This package |
|---|---|---|
| `null` (default) | `gitHubFlavored` (`fm:widget.dart:398`) | Same as `gitHubFlavored` |
| `gitHubFlavored` | fenced code, tables, task lists (ordered and unordered), footnotes; inline HTML, strikethrough, autolink extension | Identical feature set |
| `gitHubWeb` | gitHubFlavored + header ids, setext header ids, alerts, emoji, color swatches | Header ids: `generatedId` on `hN` elements (GitHub-compatible ids, `doc/navigation.md`; the anchors work in any mode). Alerts: enabled (on by default). Emoji: supported (`markdownXEmojiExtension` is added to the effective extensions; the result is plain text, as `EmojiSyntax` produces a `md.Text`, so builders see it as text). Color swatches: accepted, no effect |
| `commonMark` | fenced code + inline HTML only (no tables, strikethrough, task lists, footnotes, autolinks) | Accepted, no effect: GFM constructs still render. Not reported (content is never lost) |
| `none` | no extensions | Same as `commonMark` |
| a custom `md.ExtensionSet(...)` | its syntaxes | Its syntaxes are treated like `blockSyntaxes` / `inlineSyntaxes` below |

The four built-in sets (`none`, `commonMark`, `gitHubFlavored`, `gitHubWeb`) are recognized by identity and never classified. Syntaxes in `blockSyntaxes`, `inlineSyntaxes` and a custom `ExtensionSet` are classified by exact `runtimeType` (a user subclass of a built-in syntax is reported):

- **No-op (natively supported):** `FencedCodeBlockSyntax`, `TableSyntax`, `UnorderedListWithCheckboxSyntax`, `OrderedListWithCheckboxSyntax`, `FootnoteDefSyntax`, `InlineHtmlSyntax`, `StrikethroughSyntax`, `AutolinkExtensionSyntax`, `HeaderWithIdSyntax`, `SetextHeaderWithIdSyntax`, and the deprecated `TaskListSyntax`. `AlertBlockSyntax` turns alerts on even when `alerts: false`. `HeaderWithIdSyntax` / `SetextHeaderWithIdSyntax` (or `gitHubWeb`) gives headings a `generatedId` in the elements that builders receive.
- **`EmojiSyntax`** (in `inlineSyntaxes`, a custom set, or `gitHubWeb`): supported. The widget adds `markdownXEmojiExtension` to the effective extensions ([extensions.md](extensions.md#emoji-shortcodes)); it is not reported.
- **Anything else** (user subclasses, `ColorSwatchSyntax`, …): reported through `FlutterError.reportError` with library `flutter_markdown_x`, once per `runtimeType` per isolate (a chat list with many `MarkdownBody` widgets reports once; `resetReportedSyntaxes()` resets this for tests). The report happens in `initState` and when one of the three parameters changes identity. The message names the type and says: "The parser of flutter_markdown_x is Rust; package:markdown syntaxes do not run. Port it to a MarkdownXExtension (MarkdownXInlineSyntax, transformBlock, or transformSource); see doc/flutter_markdown_compat.md." The document still renders without that syntax.

`commonMark` / `none` are not honored because the Rust parser options are fixed (honoring them would need a C ABI change and per-option cache keys for a rarely used setting).

### 4c. Soft line breaks and tight lists

The IR carries what `softLineBreak` and list spacing need:

- **Soft line break.** A soft break is an `MdxSoftBreak` inline node (not text). The renderer draws `' '`, or `'\n'` when `softLineBreak` is true. Image alt text, heading ids (`doc/navigation.md`) and alert marker stripping treat it as a single space; `inlineSyntaxes` patterns of a `MarkdownXExtension` see it as one `' '` of glue between adjacent text, so a match across a line (`[1,\n2]`) works. Selection copy produces the text as rendered.
- **Tight lists.** `MdxList.tight` says whether any item contains a paragraph. Tight items are unwrapped into the `li` in the `md.Element` bridge (4a).
- **Code block info string.** `MdxCodeBlock.info` is the text after the first word of the fence info string, trimmed. It is exposed as `pre[data-metadata]` and is available to `blockBuilder`.

`tight` and `info` are kept by `applyMarkdownXExtensions`, the alert transform, and the footnote backref pass. The IR layout is described in `doc/native-abi.md`.

### 4d. Images

How the default image resolution relates to flutter_markdown's default image builder:

| Case | flutter_markdown | This package |
|---|---|---|
| `http`/`https` | network | same |
| `data:image/*` | memory | same |
| `data:text/*` | `Text(contentAsString())` | the text is rendered |
| `data:` other mime | `SizedBox()` | error display (alt text) |
| `resource:<path>` | `Image.asset(uri.path)` | `resource:` is an alias of this package's `asset:` in `markdownXDefaultImageProvider` (leading slashes stripped, so `resource:///a.png` also works) |
| relative or other scheme, `imageDirectory != null` | io: `Uri.parse(imageDirectory + src)` (concatenation); web: `p.join` | Same string semantics per platform. If the result is http(s) → network. Otherwise (io) → `FileImage`: **a non-null `imageDirectory` is the explicit opt-in to read files for srcs resolved under it**. **The file must be strictly inside `imageDirectory`** (normalized, percent-decoded once, symlinks resolved, Windows separators and drive letters handled); `../`, an absolute src, a link to the outside, and a directory without a trailing separator (`/img` + `a.png` is the sibling `/imga.png`) show the error display. flutter_markdown allows all of them. For `http(s)` directories and on the web a `..` that climbs above the directory is not requested either |
| relative, `imageDirectory == null`, io | `Image.file(File.fromUri(uri))` (relative to the process CWD) | Not loaded (untrusted Markdown must not read device files); error display |
| relative, `imageDirectory == null`, web | `Image.network(p.join(p.current, src))` | resolved against `Uri.base` (same-origin HTTP, no local file access) |
| absolute `file:` src | `Image.file` | Not loaded unless `imageResolver` opts in with `markdownXFileImageProvider`. With `imageDirectory` set, a src that is already absolute (`file:` scheme) is **not** covered by the opt-in |
| any error | `SizedBox()` | alt text (accessibility) |

Only a src without a scheme is joined with `imageDirectory`; a src with another scheme (`ftp:`, `file:`) is never concatenated (flutter_markdown would build a garbage path from it). The `#WxH` suffix and any other `#` fragment are removed before resolving, so `x.png#100x50` requests `x.png` and the resolver sees no fragment.

There is no `baseUri`: `imageDirectory` uses flutter_markdown's concatenation semantics, not `Uri.resolve` (with `Uri.resolve`, `/img` + `a.png` would be `/a.png` instead of `/imga.png`, and a migrating app would see different files). Apps that need RFC 3986 resolution use `imageResolver`. `sizedImageBuilder` / `imageBuilder` receive the unresolved uri (flutter_markdown semantics), and their widgets get none of the loading, error, or `onTapImage` handling.

`file:` and working-directory images are not loaded implicitly, because that would let untrusted Markdown (for example LLM output) read device files. See [images.md](images.md).

### 4e. Internal anchor links

`handleAnchorLinks` (extra, default `true`): a `#id` link whose id exists in the document scrolls there and does **not** call `onTapLink`; a `#id` that does not exist, a bare `#`, and every other link call `onTapLink(text, href, title)` exactly as flutter_markdown does.

flutter_markdown never scrolls, so a migrating app's `onTapLink` is typically `launchUrl(Uri.parse(href))`, for which an in-document `#id` is a dead or broken tap. Intercepting only ids that resolve means the callback still sees everything it could act on, footnote references and backrefs work out of the box, and `handleAnchorLinks: false` restores byte-exact flutter_markdown behavior. The behavioral comparison tests run with `handleAnchorLinks: false`.

### 4f. Cache invalidation with flutter_markdown-style call sites

flutter_markdown apps build `MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(...)`, `builders: {'code': CodeElementBuilder()}`, and closures inside `build()`. Comparing these by identity would rebuild every block on each parent rebuild and break the append/streaming performance (`doc/performance.md`). flutter_markdown itself only re-parses when `data` or `styleSheet` (by `==`) changes, or when an inherited dependency changes (`fm:widget.dart:366-379`); builder and callback instance changes take effect at the next re-parse. This package keeps that spirit with finer granularity:

1. `MarkdownStyleSheet` has value `==`/`hashCode` over every field including extras (2.4). The State keeps the **effective** sheet (fallback merged with `widget.styleSheet`) and replaces the instance only when `widget.styleSheet != old` or a fallback input changed; replacing it invalidates all blocks.
2. Callbacks without render output are routed through State and **never** invalidate: `onTapLink`, `onTapText`, `onSelectionChanged`, `onTapImage`, `onTapCitation`, `contextMenuBuilder`, `onTapCheckbox` (only null ↔ non-null invalidates, because it makes checkboxes interactive). The relay calls the current widget's function at event time.
3. Render-affecting objects and closures are also read through the relay (the newest instance is used whenever a block builds), but only their **shape** invalidates:
   - `builders` and `paddingBuilders`: the key set and each key's `runtimeType` (and `isBlockElement()` for custom tags).
   - `syntaxHighlighter`: `runtimeType` (null counts as a type).
   - `imageBuilder`, `sizedImageBuilder`, `checkboxBuilder`, `bulletBuilder`, `imageResolver`, `imageLoadingBuilder`, `imageErrorBuilder`, `blockBuilder`, `inlineBuilder`, `citationBuilder`: null ↔ non-null only (every closure of one signature has the same `runtimeType`, so type is meaningless).
4. The scope exposes a stable relay object plus a render generation counter, and dependents update only when the counter changes.

What **does** invalidate:

| Change | Effect |
|---|---|
| `data` | Re-parse; only changed blocks rebuild (block state preservation, `doc/performance.md`) |
| `extensions` (instance identity), `alerts`, `streaming`, syntaxes that toggle alerts | Re-parse |
| effective style sheet (`widget.styleSheet` by `==`; `Theme`/`CupertinoTheme` by `==`; `MediaQuery` text scaler; `styleSheetTheme`) | All blocks |
| `selectable`, `softLineBreak`, `fitContent`, `listItemCrossAxisAlignment`, `imageDirectory`, `extensionSet` (its effective flags), `handleAnchorLinks` | All blocks |
| key set / `runtimeType` of `builders` or `paddingBuilders`; `syntaxHighlighter.runtimeType`; null ↔ non-null of a render closure | All blocks |
| Inherited widgets a builder reads in its `visit*` methods | Only the blocks that called it (normal Flutter dependency tracking) |

What does **not** invalidate: a new instance of the same builder type, a new closure with the same nullness, a new callback. Consequence: a same-type builder constructed with different configuration in `build()` (for example `CodeBuilder(dark: isDark)`) takes effect for blocks as they rebuild for other reasons (the streaming tail always does), not for unchanged blocks. This is the same class of staleness as flutter_markdown's. The remedy is to read configuration from `Theme.of(context)` inside the builder, or to change the widget `key`.

### 4g. Syntax highlighting default

When `syntaxHighlighter` is non-null, flutter_markdown semantics apply exactly. When it is null, the built-in highlighter (`highlightCode`, which knows the fence language) colors tokens with the extra `codeSyntax`. The three factories set `codeSyntax` (light or dark by brightness), so code blocks are highlighted by default. Because `copyWith` cannot set a field back to null, an app that wants flutter_markdown's plain code either builds the sheet with the constructor (no `codeSyntax`) or passes a `syntaxHighlighter` that returns `TextSpan(text: source, style: styleSheet.code)`.

### 4h. Default appearance

The fallback sheet is flutter_markdown's `fromTheme` verbatim (2.4): 8 px block spacing, blue links, a 5 px divider rule, a blue-100 blockquote (in dark themes a surface fill, section 1). The extras keep this package's visuals for alerts, citations, code headers, and highlighting. Alerts are on by default under the default `gitHubFlavored` set, where flutter_markdown shows a plain blockquote. Starting from flutter_markdown's look means the import swap does not restyle an app.

---

## 5. How compatibility is tested

The [import swap test](../test/flutter_markdown/import_swap_test.dart) exercises
the shared API. The [comparison suite](../test/flutter_markdown/plus_comparison_test.dart)
checks builder and callback behavior against flutter_markdown_plus, with alerts
and internal anchor handling disabled. The suite records expected differences,
summarized in the [migration guide](migration.md#3-behavior-differences).

## Material library (Flutter 3.50)

`MarkdownStyleSheet.fromTheme` and `largeFromTheme` take `material_ui`'s
`ThemeData`. `fromCupertinoTheme` takes `cupertino_ui`'s
`CupertinoThemeData`. Install the theme with those packages' widgets so the
Markdown renderer can read it.

Apps using the SDK's Material widgets can pass a `MarkdownStyleSheet` directly.
Otherwise, Markdown uses the default `material_ui` theme. See the
[migration steps](migration.md#1-swap-the-import) for imports and theme setup.
