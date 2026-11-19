# HTML support

This document defines how this package handles HTML written inside Markdown.

The policy has three points.

- HTML is read as an extension of Markdown. Browser HTML is not reproduced. The `Markdown → AST → IR → Widget` flow is kept, with no WebView and no HTML strings in between.
- Only tags and attributes on the allowlist are interpreted. Any other tag is shown as text, exactly as written (as flutter_markdown shows raw HTML), so text such as `List<String>` or `<T>` is never lost.
- Elements that execute or apply something (`<script>`, `<style>`) are dropped together with their content.

The implementation is in `native/src/html.rs` and `native/src/lib.rs` (`BlockBuilder`), and only the Rust parser interprets HTML.

## Supported tags and attributes

### Inline

| Tag | Attributes | Result |
|---|---|---|
| `b` `strong` | | Bold |
| `i` `em` | | Italic |
| `s` `del` `strike` | | Strikethrough |
| `u` `ins` | | Underline |
| `code` | | Inline code |
| `kbd` | | Keyboard input display |
| `mark` | | Highlight |
| `sub` `sup` | | Subscript and superscript |
| `small` | | Small text (`font-size: smaller`, 1 / 1.2 of the parent) |
| `big` | | Large text (`font-size: larger`, 1.2 times the parent) |
| `cite` `dfn` `var` | | Italic (`cite, dfn, em, i, var { font-style: italic }`). They keep their own tag name for `builders` |
| `samp` `tt` | | Monospace font (`samp, tt { font-family: monospace }`), without the background box of `code` |
| `abbr` `acronym` | `title` | With a non-empty `title`, a dotted underline (`abbr[title], acronym[title] { text-decoration: dotted underline }`). Without it, plain text. The `title` is kept in `MdxStyled.title` and in the builders' element |
| `q` | | The content between quotation marks (`quotes: auto`): “ ” at the outer level, ‘ ’ one level in, alternating. Inserted as text. An empty `q` still shows its marks |
| `bdi` | `dir` | Isolated content: U+2068 (FSI) … U+2069 (PDI). `dir="ltr"` uses U+2066 (LRI), `dir="rtl"` uses U+2067 (RLI). Nothing is added for empty content |
| `bdo` | `dir` | Directional override: `dir="ltr"` U+202D (LRO), `dir="rtl"` U+202E (RLO), closed by U+202C (PDF). Without a valid `dir`, the content is kept as is |
| `wbr` | | A line break opportunity: U+200B (ZERO WIDTH SPACE) |
| `a` | `href`, `title` | Link. Without `href`, the tag is dropped and only the content is kept. The URL keeps its original notation |
| `br` | | Forced line break |
| `img` | `src`, `alt`, `title`, `width`, `height` | Image. Dropped if `src` is empty |
| `font` | `color` | Text color |
| `span` and the other tags on this page | `style` | Only the CSS declarations below are applied. `span` without `style` keeps only its content |

The declarations read from the `style` attribute are `color`, `background` / `background-color`, `font-size`, `font-weight` (`bold` or 600 and above), `font-style` (`italic` / `oblique`), and `text-decoration` (underline and strikethrough). Other declarations are ignored. For colors, it reads names (the main twenty or so), `#rgb` `#rgba` `#rrggbb` `#rrggbbaa`, and `rgb()` / `rgba()`.

### Block

| Tag | Attributes | Result |
|---|---|---|
| `p` `div` `center` | `align` | The alignment is passed on to the blocks inside (`center` is always centered). The tag itself acts as a paragraph separator |
| `h1` to `h6` | `align` | Heading |
| `details` | `open` | Collapsible. With `open`, it starts open |
| `summary` | | The heading line of `details` |
| `blockquote` | | Block quote, rendered like Markdown `>` |
| `ul` `ol` `li` | `start` on `ol` | Bulleted and numbered lists, including nested lists |
| `table` | | Table. See below |
| `caption` | | Inline content displayed as a paragraph immediately before its table |
| `tr` `th` `td` | `align`, `colspan`, `rowspan` on `th` / `td` | Rows and cells |
| `thead` `tbody` `tfoot` | | Sections. Cells in `thead` are treated as header |
| `hr` | | Thematic break (`MdxThematicBreak`), the same as `---` |
| `pre` | `class` | Verbatim code block. See below |
| `textarea` | | Verbatim code block |
| `video` `audio` | `src`, `poster` (video), `title`, `width`, `height`, `type` | A `media` block. See [Media elements](#media-elements) |
| `source` | `src`, `type` | Inside `video` / `audio` only: the first usable one gives the URL when the element has no `src` |
| `track` | | Inside `video` / `audio`; ignored |
| `iframe` `embed` | `src`, `title`, `width`, `height`, `type` | A `media` block |
| `object` | `data`, `title`, `width`, `height`, `type` | A `media` block |

## Media elements

`<video>`, `<audio>`, `<iframe>`, `<embed>` and `<object>` become
`MdxCustomBlock('media', attributes: …, inlines: [fallback link])`. The package
bundles no player and no PDF viewer.

- Attributes: `kind` (the tag name), `src` (for `object`, its `data`; for `video` and `audio` without `src`, the `src` of the first usable `<source>`), and, when present, `type` (of the element or of that `<source>`), `poster` (`video`), `title`, `width` and `height`. Values are kept as written, trimmed. `MarkdownXMedia.of(block)` reads them; `width` and `height` are numbers there only when the value is a plain number, and the raw string stays in `attributes`.
- URLs: entity references are decoded and surrounding whitespace is removed, as for `<a href>` and `<img src>`, and the URL keeps its notation otherwise. A `javascript:`, `vbscript:` or `data:` URL (in any letter case, ignoring tabs and newlines inside the scheme) is not used; such a `poster` is dropped.
- Without a usable URL, no media block is created: the tag is dropped and its fallback content is shown as text, so nothing is lost.
- Fallback link: its text is `title`, else the last path segment of the URL (percent-decoded), else the URL. Its target is the URL and its title is `title`. Without a builder the block renders this link as a paragraph, and tapping it calls `onTapLink(text, src, title)`.
- Content: the element's content (such as "Your browser does not support video") is skipped up to its matching closing tag. The search stays inside the same HTML block, or the same paragraph for inline media; when the closing tag does not appear there, the element ends there, so an unclosed or still-streaming `<video>` never hides the rest of the document. A closing tag that arrives later is ignored. `embed` has no content.
- Placement: in an HTML block the media block ends the current paragraph and goes into the enclosing HTML container (`blockquote`, `li`, `details`). A paragraph or list item that holds only one media element and whitespace (such as `<video src="a.mp4"></video>` on one line) is also a media block. Inside a Markdown paragraph with other text, an HTML table cell or caption, or an HTML heading, only the fallback link is placed inline. Between table rows it is dropped.

To show a player, return a widget for the block from `blockBuilder`. A sketch with `video_player` (not a dependency of this package):

```dart
Markdown(
  data: markdown,
  blockBuilder: (context, block, buildDefault) {
    final media = MarkdownXMedia.of(block);
    final uri = media?.uri;
    if (media == null || uri == null) return null;
    return switch (media.kind) {
      MarkdownXMediaKind.video => MyVideoPlayer(uri: uri, poster: media.poster),
      _ => null, // keep the fallback link
    };
  },
)
```

`MyVideoPlayer` is the app's widget, for example one that creates a
`VideoPlayerController.networkUrl(uri)` and shows a `VideoPlayer`. A
flutter_markdown-style builder registered as `builders['media']` receives
`md.Element('media')` with the same attributes.

## Character references

The HTML tokenizer decodes numeric references and selected named references in
text and attribute values. Names are case-sensitive and require a semicolon.
The supported names are `amp`, `lt`, `gt`, `quot`, `apos`, `nbsp`, `copy`,
`reg`, `trade`, `mdash`, `ndash`, `hellip`, `laquo`, `raquo`, `ldquo`,
`rdquo`, `lsquo`, `rsquo`, `times`, `divide`, `deg`, `plusmn`, `middot`,
`bull`, `larr`, `rarr`, `uarr`, `darr`, `euro`, `yen`, `pound`,
`cent`, `sect`, and `para`. Unknown names stay as written.

With Rust 1.93.0 and `sh tool/build_wasm.sh`, the original module measured
343,797 bytes. The selected names brought it to 344,630 bytes (+833 bytes,
0.24%). A prototype with a sorted table of all 2,125 semicolon-terminated HTML5
names, including multi-character values, measured 397,147 bytes (+53,350
bytes, 15.52%). The package uses the smaller set to limit the size of the
bundled parser.

## Tags outside the allowlist

A tag that is not listed on this page (`section`, `foo`, `String` in `List<String>`, a custom element, and so on) is shown as text exactly as written, both the opening and the closing tag. This is the same as flutter_markdown, which shows all raw HTML as text. The Markdown between the tags is interpreted as usual. To show such a tag as code, write it in backticks.

`script` and `style` are on the allowlist as tags that are dropped together with their content.

- An unclosed allowed tag is closed at the end of the paragraph or block. This is so that a half-written `<b>` is not visible as text during streaming. CommonMark outputs an unclosed tag as written, so this differs from the spec.
- A closing tag with no matching opening tag is ignored.
- A tag with quoted attribute values is read as a single tag, including any `<` and `>` inside the values.

## Phrasing tags of the HTML Living Standard

The inline tags above follow the default rendering of the HTML Living Standard (section 15, "Rendering": phrasing content, quotes and bidirectional text). Only the default rendering is reproduced; `class` and CSS are not.

- `cite`, `dfn`, `var`, `samp`, `tt`, `big`, `abbr` and `acronym` are IR decorations (`MdxStyleKind.cite`, `definition`, `variable`, `sample`, `teletype`, `big`, `abbreviation`, `acronym`; IR version 4). Each keeps its own kind, not `emphasis` or `code`, so that `builders` keyed by `cite`, `samp`, `abbr` and so on are called with the original tag name, and `abbr` / `acronym` keep their `title` (the attribute is added to the `md.Element`). The style of `cite`, `dfn` and `var` comes from the style sheet's `em`; `samp` and `tt` use the font family of `code` without its background or size.
- `q`, `bdi`, `bdo` and `wbr` are not IR nodes. The Rust parser inserts the generated characters as text, so no IR change is needed, and a builder keyed by these tags is not called. An unclosed `q` is closed at the end of the paragraph with its closing quote, like every unclosed tag.
- `<hr>` written as an HTML block is `MdxThematicBreak`. An `<hr>` in the middle of a paragraph (inline HTML), or inside a table cell, is dropped, like the other block tags (`<div>`, `<p>`) in that position.
- Copy: the quotation marks of `q` are part of the text and are copied (the IR cannot tell them from written text). The characters that show nothing, the zero width space and the bidi isolates, embeddings and overrides (U+200B, U+202A to U+202E, U+2066 to U+2069), are removed from the copied text of a `SelectionArea`, so `<wbr>`, `<bdi>` and `<bdo>` leave no trace in the clipboard. This also removes the same characters when they were written directly in the Markdown source.
- The `title` of `abbr` is not shown as a tooltip and does not change the semantics label; read it from `MdxStyled.title` or from a `builders` entry.

## Tags whose content is dropped

| Tag | Handling |
|---|---|
| `<script>…</script>` | Dropped together with its content |
| `<style>…</style>` | Dropped together with its content |
| HTML comment `<!-- … -->` | Dropped. `<!-->` and `<!--->` are also dropped as empty comments |
| Unclosed comment | The rest of that block is dropped (so half-written text does not appear in the body) |

`<script>` and `<style>` do not show their content as body text, whether written as a block or in the middle of a paragraph. An unclosed `<script>` drops everything to the end of the document if it is at the start of an HTML block, or to the end of the paragraph if it is in the middle of a paragraph.

## `<pre>` and `<textarea>`

The content is not interpreted as Markdown and becomes an `MdxCodeBlock`.

- Other tags inside `<pre>` are dropped (`<br>` becomes a newline), and entities are turned back into characters. One newline right after the opening tag and one trailing newline are ignored. Whitespace and blank lines are kept as they are.
- The language is read from `<pre class="language-x">`, or from the first `<code class="language-x">` inside it (`lang-x` also works). If not specified, there is no language and no highlighting (the same as a code block without a language).
- For `<textarea>`, the text written, including tags, is made into a code block as-is (only entities are restored).
- When there is no closing tag, the content runs to the end of the document only if the tag is at the start of an HTML block (so a half-written `<pre>` appears as partial code). One that is not at the start, such as in the middle of a `<table>` block, is treated as an ordinary tag.
- Inside a table cell, it does not become a code block and goes into the cell as text.
- When `<pre>` appears in the middle of a paragraph (arriving as inline HTML), only the tag is dropped and the content remains as ordinary inlines.
- Writing only `<code>` is still inline code, as before.

## `<details>`

- With the `open` attribute (whether or not it has a value), `MdxDetails.open` becomes true and it is rendered open initially.
- The state toggled by the user is kept regardless of `open`. This is the same even when the block moves because of appended content or reordering. It is treated as a different block from an otherwise identical block without `open`.
- Internal link navigation (`jumpToAnchor`) opens only closed `details`. Open ones are left unchanged.
- Without `<summary>`, the summary is empty.

## HTML block quotes and lists

HTML block quotes and lists use the same IR and renderer as their Markdown
counterparts. Quotes and list items can contain nested blocks. A new `li` or
the end of its enclosing list closes an unfinished item. A standalone `li`
keeps its text without creating a list.

For `ol start`, a positive integer up to 4,294,967,295 sets the first number.
A missing, invalid, zero, negative, or out-of-range value starts at 1.
`ol reversed` and `li value` are ignored. Quotes and lists written as raw
HTML inside a table cell do not create nested block structure.

## `<table>`

An HTML `<table>` becomes an `MdxTable`. It is the same type as a GFM table, and rendering is shared.

- header: the first row of `<thead>`, or the first row when all of its cells are `<th>`, is the header. Otherwise it is a table without a header. When `<thead>` has two or more rows, the second and later rows are treated as body rows.
- alignment: the `align` of the cells in the first row becomes the alignment of the column where that cell starts.
- The first non-empty `<caption>` is rendered as an ordinary paragraph immediately before the table. Inline formatting is kept. Caption text does not become a row or affect column sizing.
- `<colgroup>`, `<col>`, and other raw HTML text outside cells and captions are dropped.

### colspan and rowspan

`colspan` and `rowspan` become per-cell `MdxCellSpan` values (`MdxTable.headerSpans`, `rowSpans`).

- The value is an integer from 1 to 100. Non-numeric values, 0, and negative values are rounded to 1, and values over 100 are rounded to 100.
- `rowspan="0"` means "to the last row of the section" in HTML, but is treated as 1.
- A `rowspan` that exceeds the bottom of the table is rounded to the number of remaining rows.
- The number of columns is the maximum of the cells' occupied widths (the length of `MdxTable.alignments`). Cells in lower rows are placed skipping columns blocked by a `rowspan` from above. That is, the number of cells in a row can be smaller than the number of columns (the same rule as HTML).
- When all cells are 1 x 1, no span information is held (`MdxTable.hasSpans` is false).
- See [native-abi.md](native-abi.md) for the output IR format.

Rendering: a table without spans is drawn with Flutter's `Table`. Only a table with spans is drawn with a custom layout (`lib/src/widgets/span_table.dart`).

- A column's width is the maximum of the natural widths of the cells that occupy only that column. If a cell spanning several columns is not wide enough, the shortfall is divided equally among the spanned columns and added.
- Row height follows the same idea, and any shortfall is added to the last spanned row.
- This is an approximation of CSS table layout. Column widths specified with `width` or `%`, `border-collapse`, and `vertical-align` are not handled.
- When the width is insufficient, it scrolls horizontally, as with `Table` (columns are not shrunk).
- Under RTL, the columns are laid out from the right. Selection and copy separate cells with tabs and rows with newlines.

### Content inside cells

A cell holds only a sequence of inlines. Blocks written inside a cell are flattened to inlines without losing text.

| Content inside the cell | Result |
|---|---|
| Paragraph (including Markdown separated by blank lines) | Decoration is kept. Newline between paragraphs |
| `<br>` | Newline |
| Bulleted and numbered lists | One line per item, prefixed with `• ` or `1. `. Decoration is lost |
| Code block, `<pre>` | Text line by line. No decoration or highlighting |
| Quote, heading | Text only |
| Nested table | One line per row, cells separated by tabs |

Uses such as putting another table or a complex block inside a cell cannot be fully expressed with this approximation. If you need such a structure, use `blockBuilder` in your app, or write it as a Markdown table and paragraphs instead.

## Unsupported

The following are browser features and are not reproduced. Their tags are not on the allowlist, so they are shown as text.

- Loading external resources (`<link>`, and so on). Media elements are read as `media` blocks, but nothing is loaded or played unless the app supplies a builder
- Form elements (`<input>`, `<button>`, `<select>`, and so on; write task list checkboxes with the Markdown notation)
- Attributes such as `class`, `id`, and `on*`, `<style>` rules, and external CSS files
- CSS declarations other than those listed above, such as `display`, `position`, and `margin`

## Relation to CommonMark conformance

Many CommonMark HTML block and Raw HTML examples do not match the expected HTML because of the policy above (the spec outputs raw HTML, while this package interprets it as elements). The reasons and counts for the mismatches are classified in [conformance.md](conformance.md).

Some CommonMark HTML examples that do match are the result of the tokenizer rules below.

- A tag containing `<` or `>` inside a quoted attribute value is read as one tag (the `<a … bam = 'baz <em>"</em>'` in example 616).
- `<!-->` and `<!--->` are empty comments (example 626).
- An unclosed comment discards the rest of the document (or of the paragraph).

## Implementation guidelines

When extending HTML support, follow these rules.

1. If a new structure is needed, change the IR: update Rust's `ir.rs` and Dart's `nodes.dart`, `ir_decoder.dart`, and `test/support/ir_encoder.dart` together, and bump the IR version ([native-abi.md](native-abi.md)).
2. Round values in the parser, and also validate the range in the decoder (such as the 1 to 100 for spans).
3. Add a new tag to `SUPPORTED_TAGS` in `native/src/html.rs` (otherwise it is shown as text). For unknown values, fall back to ignoring them instead of throwing an exception.
4. Update the tables in this document together with `test/parser/html_test.dart`, `test/widgets/html_widget_test.dart`, and `html_policy_tests` in `native/src/lib.rs`.
