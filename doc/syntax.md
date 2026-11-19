# Supported syntax

This page summarizes the syntax `flutter_markdown_x` interprets in a single table. The numbers come from the measurements in [conformance.md](conformance.md) (2026-11-15: 652 CommonMark 0.31.2 examples and 24 GFM 0.29 extension examples). The only parser is the bundled Rust implementation, so syntax is interpreted identically on every platform ([parser.md](parser.md)).

The "Support" column means:

- ◎: enabled by default.
- ○: enabled, with differences from the spec (see the notes).
- Extension: disabled by default; enabled by passing an extension.
- Unsupported: not interpreted, and left as plain text (or intentionally dropped).

The syntax set is fixed. flutter_markdown's `extensionSet` is accepted, but `ExtensionSet.commonMark` and `ExtensionSet.none` do not turn GFM (tables, strikethrough, task lists, footnotes, autolinks) off, and custom `md.BlockSyntax` / `md.InlineSyntax` subclasses do not run (they are reported once; use `MarkdownXExtension`, [extensions.md](extensions.md)).

## Block

| Syntax | Example | Support | Notes |
|---|---|---|---|
| ATX heading | `## Heading` | ◎ | 18 / 18. Gets a GitHub-compatible ID ([navigation.md](navigation.md)) |
| Setext heading | `===` on the line after the heading text | ◎ | 27 / 27 (tolerant) |
| Paragraph and soft line break | consecutive lines | ◎ | A soft break is `MdxSoftBreak`. It renders as one space |
| Hard line break | two trailing spaces, `\`, or `<br>` at the end of a line | ○ | 13 of 15. The differences involve raw HTML |
| Thematic break | `---` | ◎ | 16 of 19 (strict); 19 of 19 in tolerant mode |
| Block quote | `> quote` | ◎ | 25 / 25 (tolerant) |
| Bullet and ordered list | `- a` / `1. a` | ○ | Keeps the start number and `MdxList.tight`. Nesting is supported. Tight and loose lists look the same (flutter_markdown spaces list items by `blockSpacing`); builders see the tight form (paragraphs unwrapped into the `li`) like `package:markdown` |
| Task list (GFM) | `- [x] done` | ◎ | `MdxListItem.checked`. 2 / 2 (tolerant). The checked state is exposed to semantics ([accessibility.md](accessibility.md)). With `onTapCheckbox` the checkbox can be toggled: the app rewrites its `data` with `MarkdownXTask.toggle` ([Toggling task checkboxes](#toggling-task-checkboxes)). Items of a loose list (separated by blank lines) keep their checkbox, as on GitHub; flutter_markdown_plus shows a bullet there ([migration.md](migration.md)) |
| Fenced code block | ```` ```dart ```` | ◎ | 29 / 29. Keeps the language name. See [code-blocks.md](code-blocks.md) for the vocabulary |
| Indented code block | four-space indent | ◎ | 12 / 12 (tolerant) |
| Code syntax highlighting | fence with a language name | ○ | Lightweight regex-based coloring. Replaceable through `MarkdownStyleSheet.codeSyntax` and `syntaxHighlighter` ([code-blocks.md](code-blocks.md)) |
| Table (GFM) | `\| a \| b \|` and `\|---\|---\|` | ◎ | 8 / 8. Keeps column alignment. See [performance.md](performance.md) for guidance on very large tables |
| Link reference definition | `[id]: https://…` | ◎ | 26 of 27. An update that adds or removes definitions triggers a full parse |
| Footnote | `[^1]` and `[^1]: body` | ○ | Converted to superscript links plus a trailing thematic break and ordered list. Jumping between reference and definition is supported ([navigation.md](navigation.md)). A document containing footnotes is fully parsed instead of incrementally parsed |
| HTML block | `<details>`, `<table>`, `<pre>`, `<hr>`, and others | ○ | Only allowed tags are interpreted as elements. Of 44 CommonMark HTML block examples, 3 match strictly; the differences are by design ([html.md](html.md)) |
| `<details>` / `<summary>` | `<details open>` | ◎ | `MdxDetails`. `open` makes it start expanded. The open/closed state is preserved |
| HTML media | `<video>`, `<audio>`, `<iframe>`, `<embed>`, `<object>` | ○ | A `media` block (`MarkdownXMedia.of`). No player is bundled: by default a link to the URL is shown, and the app plugs in a player through `blockBuilder` or `builders['media']` ([html.md](html.md#media-elements)) |
| HTML table | `colspan` / `rowspan` in `<table>` | ○ | Only tables with spans use a dedicated layout. Blocks inside cells are flattened to text ([html.md](html.md)) |
| GitHub alert | `> [!NOTE]` | ◎ | Enabled by default in `Markdown`, `MarkdownBody`, and `SliverMarkdown` (disable with `alerts: false`; flutter_markdown shows a plain quote). Only for block quotes that start with a marker-only line ([alerts-and-citations.md](alerts-and-citations.md)) |
| Math block | `$$ x^2 $$`, `\[ x^2 \]` | Extension | `package:flutter_markdown_x/math.dart` ([math.md](math.md)) |
| Mermaid diagram | ```` ```mermaid ```` | Extension | `package:flutter_markdown_x/mermaid.dart`. Shown as a normal code block unless the app supplies a renderer ([mermaid.md](mermaid.md)) |

## Inline

| Syntax | Example | Support | Notes |
|---|---|---|---|
| Emphasis and strong emphasis | `*a*`, `**a**`, `_a_` | ◎ | 129 of 132. The differences involve raw HTML |
| Strikethrough (GFM) | `~~a~~` | ◎ | 2 / 2 |
| Inline code | `` `a` `` | ◎ | 21 of 22 |
| Link and reference link | `[text](url "title")`, `[text][id]` | ◎ | 86 of 90. A `#id` link jumps to the heading's position by default ([navigation.md](navigation.md)) |
| Image | `![alt](src "title")` | ◎ | 22 / 22. See [images.md](images.md) for how images are loaded |
| Autolink | `<https://…>` | ◎ | 16 of 19 |
| Autolink (GFM) | `www.example.com`, `https://…`, bare email addresses | ◎ | GFM Autolinks 11 / 11 |
| Backslash escape and entity | `\*`, `&amp;`, `&#35;` | ◎ | 12 / 13 and 15 / 17 |
| Inline HTML | `<b>`, `<kbd>`, `<sub>`, `<mark>`, `<u>`, `<small>`, `<big>`, `<cite>`, `<abbr title>`, `<q>`, `<bdi>`, `<bdo>`, `<wbr>`, `<img width>`, `<font color>`, `style` attributes, and others | ○ | Only allowlisted tags are interpreted. Other tags are shown as written; `<script>` and `<style>` are dropped together with their content ([html.md](html.md)) |
| Inline math | `$x$`, `\(x\)` | Extension | Currency such as `$5 and $10` is not treated as math ([math.md](math.md)) |
| Citation | `[1]`, `[1, 2]`, `【1†source】` | Extension | Pass `markdownXCitationExtension()` in `extensions`. Rendered as a chip ([alerts-and-citations.md](alerts-and-citations.md)) |
| Emoji shortcode | `:smile:` | Extension (opt-in) | Left as plain text unless `markdownXEmojiExtension` is passed, or `ExtensionSet.gitHubWeb` / `md.EmojiSyntax()` asks for it, as in flutter_markdown ([extensions.md](extensions.md#emoji-shortcodes)). Color swatches of `gitHubWeb` are accepted and have no effect |
| Arbitrary raw HTML output | `<form>`, `<link>`, `<style>` | Unsupported (intentional) | For safety and conversion to widgets. Shown as text, or dropped (`<style>`) |

## Handling of in-progress (streaming) text

With `streaming: true`, only the last block at the end is normalized before parsing. Completed blocks are unaffected, and the result with `streaming: false` is the same as a normal parse. See [streaming.md](streaming.md) for details and the list of transitions where the display can change.

| Trailing state | Example | Display |
|---|---|---|
| Unclosed emphasis, strikethrough, or inline code | `**bold` | Closed with the intended decoration |
| Partial link | `[text](https://exa` | Text only |
| Partial image, HTML tag, footnote reference, or a line consisting only of a leading marker | `![a](ht`, `<b` | Hidden |
| Partially written table | header row only | A header-only table |
| Fence language name | ```` ```da ```` | Not shown until the opening line is terminated by a newline |
| Partially written alert or citation | `> [!NO`, `[1` | Hidden |
| Unclosed math (extension) | `$$ x` | Hides the delimiters and shows the TeX in monospace. A single `$` stays literal |

## Relationship to spec conformance

- CommonMark 0.31.2: strict 591 / 652 (90.6%), tolerant 591 / 652 (90.6%). GFM extensions: strict 23 / 24, tolerant 23 / 24.
- Most of the remaining differences stem from the policy of interpreting raw HTML as elements (flutter_markdown shows raw HTML as text). There were 0 errors in pure Markdown syntax that are not caused by raw HTML. See [conformance.md](conformance.md) for the classification.
- These measurements cover the examples in the corpus. They do not guarantee conformance for all Markdown outside the corpus.

## Related documents

- [html.md](html.md): scope of HTML support
- [extensions.md](extensions.md): `MarkdownXExtension`, `blockBuilder`, `inlineBuilder`, and the flutter_markdown `builders` for adding custom syntax
- [migration.md](migration.md) and [flutter_markdown_compat.md](flutter_markdown_compat.md): the flutter_markdown compatible API and its differences
- [parser.md](parser.md): parser availability and diagnostics

## Toggling task checkboxes

The checked state of a task is the `[ ]` or `[x]` in the Markdown text, so the widgets do not keep it. They report a tap and the app rewrites its own `data`:

```dart
Markdown(
  data: data,
  onTapCheckbox: (task) => setState(() => data = task.toggle(data)),
)
```

`onTapCheckbox` (`void Function(MarkdownXTask task)`) is accepted by `Markdown`, `MarkdownBody`, `SliverMarkdown` and `MarkdownWidget`. Without it the checkboxes are display-only, as before.

`MarkdownXTask` is an immutable value:

| Member | Meaning |
|---|---|
| `checked` | Whether the task is checked in the `data` that was parsed (the state before the toggle) |
| `index` | 0-based order of the task item among all task items shown in the document (nested items and items in blockquotes count) |
| `markerStart`, `markerEnd` | UTF-16 offsets in `data` of the `[` and just after the `]` of the marker (`data.substring(markerStart, markerEnd)` is `[ ]`, `[x]` or `[X]`) |
| `toggle(data)` | `data` with the marker flipped (`[ ]` becomes `[x]`, `[x]` / `[X]` becomes `[ ]`); only these three characters change |
| `matches(data)` | Whether `data` still has the expected marker at that place |

`toggle` never throws and never corrupts text. If `data` no longer has the expected marker at `markerStart` (it was edited after the tap, or the task was already toggled), it returns `data` itself, unchanged. Check `identical(result, data)` if you need to know.

The offsets are positions in the original text you passed as `data`, also with CRLF line endings, non-ASCII text before the task, reference definitions, and the math, alert, citation, emoji and mermaid extensions. With `streaming: true` the unfinished last part can be tapped as well; the task refers to the `data` of the moment of the tap. A task whose position is unknown (a custom `MarkdownXExtension` rebuilt its list item without `MdxListItem.markerOffset`) is not interactive.

How the positions stay correct: the Rust parser records the byte offset of every task marker. The incremental parser keeps them relative to the chunk that holds the block, mapped back to the original chunk text when a source transform changed it, and the widget adds the chunk's current start at tap time. The offsets are not part of the equality of `MdxListItem`, so inserting text before a task list moves the offsets but does not rebuild the list block ([performance.md](performance.md)).

