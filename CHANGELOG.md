## 0.1.0

Initial release.

**A drop-in replacement for `flutter_markdown` and `flutter_markdown_plus`.** Swap the import (`package:flutter_markdown/flutter_markdown.dart` to `package:flutter_markdown_x/flutter_markdown_x.dart`) and keep your code: `Markdown`, `MarkdownBody`, `MarkdownWidget`, `MarkdownStyleSheet`, `MarkdownElementBuilder`, `MarkdownPaddingBuilder`, `SyntaxHighlighter`, every typedef and every constructor parameter of flutter_markdown 0.7.7+1 and flutter_markdown_plus 1.0.12 have the same names, signatures, and defaults. Builders run with flutter_markdown's call protocol on `package:markdown` elements, and the default look is `MarkdownStyleSheet.fromTheme`. Two things need attention when migrating: the widgets follow the theme of `package:material_ui` (an app that stays on `package:flutter/material.dart` gets the default theme unless it passes `styleSheet:`), and custom `md.BlockSyntax` / `md.InlineSyntax` subclasses do not run in the Rust parser (port them to `MarkdownXExtension`). What differs is listed below, in [doc/migration.md](doc/migration.md) (guide) and in [doc/flutter_markdown_compat.md](doc/flutter_markdown_compat.md) (reference).

### Compatibility with flutter_markdown

* Widgets `Markdown`, `MarkdownBody`, `MarkdownWidget` with all parameters of flutter_markdown and flutter_markdown_plus, plus `SliverMarkdown`.
* `MarkdownStyleSheet` with every field and factory (`fromTheme`, `fromCupertinoTheme`, `largeFromTheme`, `copyWith`, `merge`) and value equality, so a style sheet built inside `build()` does not invalidate cached blocks.
* `builders` and `paddingBuilders` use flutter_markdown's call protocol and `md.Element` tags and attributes. The IR is converted to `md.Element` lazily, only for blocks that contain a registered tag.
* `blockSyntaxes`, `inlineSyntaxes` and `extensionSet` are accepted. Syntaxes the parser covers are no-ops, and any other syntax is reported once through `FlutterError.reportError` with a pointer to `MarkdownXExtension`.
* Built on `package:material_ui` and `package:cupertino_ui` (the public API uses their `ThemeData` / `CupertinoThemeData`). `package:markdown` is a dependency for types only.
* Not provided: `MarkdownBuilder` and `MarkdownBuilderDelegate`.

### Parser

* One parser for every platform: a bundled Rust parser, called through FFI on iOS, Android, macOS, Linux, and Windows and as WebAssembly on Web. Prebuilt binaries are included, so consuming apps need no Rust toolchain, and a normal `flutter build web` works without extra flags or manual initialization.
* CommonMark 0.31.2 and GFM 0.29 conformance is measured by `test/conformance` ([doc/conformance.md](doc/conformance.md)).
* The native C ABI is version 2 and the binary IR is version 6. The decoder rejects truncated or corrupt data as `MdxIrFormatException`, and a panic or an oversized length returns null instead of crashing the process ([doc/native-abi.md](doc/native-abi.md)).
* While the parser is unavailable (missing binary, ABI mismatch, or on Web, WASM not yet loaded) the widgets show the raw Markdown source and switch once it is ready; `parseMarkdown` throws `MarkdownXParserUnavailableException` ([doc/parser.md](doc/parser.md), [doc/web-wasm.md](doc/web-wasm.md)).

### Rendering and extensions

* GitHub alerts (`> [!NOTE]` and so on) and citations, enabled by default (`alerts: false` renders a plain blockquote) ([doc/alerts-and-citations.md](doc/alerts-and-citations.md)).
* Optional math (`package:flutter_markdown_x/math.dart`) and Mermaid (`package:flutter_markdown_x/mermaid.dart`) extensions. The core depends on no math or diagram library; the app supplies the renderer ([doc/math.md](doc/math.md), [doc/mermaid.md](doc/mermaid.md)).
* GitHub emoji shortcodes (`markdownXEmojiExtension`).
* An allowlisted HTML subset interpreted instead of shown as text: inline formatting, `<details>`, `<table>` with `colspan` / `rowspan`, `align` and `style` attributes. Any other tag is shown as text, as written, as in flutter_markdown ([doc/html.md](doc/html.md)).
* Decodes common HTML named character references in text and attributes, including `&copy;`, `&mdash;`, and `&euro;`.
* Renders HTML block quotes and nested ordered and unordered lists, including positive `ol start` values.
* Displays an HTML table caption as a paragraph immediately before its table.
* Turns HTML `<video>`, `<audio>`, `<iframe>`, `<embed>` and `<object>` into a `media` block read with `MarkdownXMedia.of`. No player is bundled: by default a link to the URL is shown, and apps render a player or viewer through `blockBuilder` or `builders['media']` ([doc/html.md](doc/html.md#media-elements)).
* Code blocks with built-in syntax highlighting for common languages, several color themes (`MarkdownXSyntaxColors`), and an optional header with language name and copy button (`MarkdownXCodeBlockOptions`) ([doc/code-blocks.md](doc/code-blocks.md)).
* `blockBuilder`, `inlineBuilder` and post-parse IR transforms (`MarkdownXExtension`, `MdxCustomInline`, `MdxCustomBlock`) for custom syntax, with the same results on every platform ([doc/extensions.md](doc/extensions.md)).
* Supported syntax is listed in [doc/syntax.md](doc/syntax.md).

### Streaming and performance

* `streaming: true` tidies unfinished syntax at the end of text that is still being generated (unclosed emphasis, partial links, images, tables, and fences) ([doc/streaming.md](doc/streaming.md)).
* Incremental parsing with a per-block widget cache. A pure append resumes from the last line of the previous scan, so the work per update does not depend on the document size. Block state survives prepend, reorder, and delete.
* `SliverMarkdown` builds lazily per block inside a `CustomScrollView`; `Markdown` uses it internally ([doc/performance.md](doc/performance.md)).

### Navigation

* GitHub-compatible heading ids, `#id` links handled by the widget, footnote round trips, and a table of contents through `markdownXHeadings`, `markdownXAnchors` and `MarkdownXController` (`headings`, `jumpToAnchor`, `scrollToHeading`). Navigation reaches blocks that are not yet built and never moves horizontal ancestors such as a `TabBarView` ([doc/navigation.md](doc/navigation.md)).

### Images

* `imageDirectory`, `sizedImageBuilder` and `imageBuilder` as in flutter_markdown, plus `imageResolver`, `imageLoadingBuilder`, `imageErrorBuilder` and `onTapImage`. An unusable src never throws; the alt text is shown instead ([doc/images.md](doc/images.md)).
* Images that load asynchronously fade in (200 ms; `MarkdownStyleSheet.imageFadeInDuration`, `Duration.zero` turns it off). Cached images and platforms that reduce animations show them at once. SVG images can be shown through `sizedImageBuilder` or `inlineBuilder` with an SVG renderer ([doc/images.md](doc/images.md#svg-images)).
* Local files are loaded only when they lie strictly inside the normalized `imageDirectory` (percent-decoding, Windows separators, absolute paths and symbolic links that point outside are handled), so untrusted Markdown cannot read other files. A `..` that climbs above an `http(s)` `imageDirectory` is not requested. `file:` images need an explicit opt-in through `imageResolver` with `markdownXFileImageProvider`.

### Selection, accessibility, and RTL

* `selectable` wraps the content in one `SelectionArea`; copied text is separated per block and by tabs between table cells. Links are reachable with Tab and Shift+Tab and open with Enter and Space, `details` summaries are buttons that expose their state, and layout follows the text direction ([doc/accessibility.md](doc/accessibility.md)).

### Task lists

* `onTapCheckbox` reports a tap as a `MarkdownXTask`; the app rewrites its own `data` with `task.toggle(data)`.

### Diagnostics

* `markdownXParserDiagnostics()` returns why the parser is unavailable, the ABI and IR versions, and build information.

### Differences from flutter_markdown

Intentional, all listed with their reasons in [doc/migration.md](doc/migration.md):

* Raw HTML (an allowlist) is interpreted instead of shown as text.
* Footnotes draw one extra horizontal rule before the definitions.
* Loose task lists (items separated by blank lines) render checkboxes, as GFM specifies; flutter_markdown_plus shows a bullet there because of a bug.
* A failed or unusable image shows its alt text instead of an empty `SizedBox` (`imageErrorBuilder` replaces it).
* `file:` and working-directory images are not loaded implicitly, because Markdown can be untrusted. A non-null `imageDirectory` is the opt-in for the files below it; `imageResolver` with `markdownXFileImageProvider` opts in for `file:`.
* `onSelectionChanged` reports the selected text of the whole document, with a selection that covers it and a `null` cause, and is not called when the selection is cleared.
* `contextMenuBuilder` honors the default and `null`; a custom function is reported once and the default menu is used.
* Custom block and inline syntaxes do not run in the Rust parser (reported once; port them to `MarkdownXExtension`). `ExtensionSet.commonMark` and `ExtensionSet.none` do not turn GFM off, and the color swatches of `gitHubWeb` are not rendered.
* A `table` builder's widget is used (flutter_markdown discards it). `MarkdownBody` always lays blocks out in a `Column`, so block state survives a stream growing from one block to two.
* GitHub alerts and built-in syntax highlighting are on by default (flutter_markdown shows a plain blockquote and plain code).
* The task list checkbox uses `colorScheme.primary` and the blockquote box `colorScheme.surfaceContainerHighest`, so both stay visible in dark themes.
* `MarkdownStyleSheet.copyWith` carries `tableScrollbarThumbVisibility` over, and `merge` accepts a null base style.
