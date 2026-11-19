# Display while streaming

This page describes the approach for displaying Markdown that is appended to bit by bit, such as an LLM response. While generation is in progress the end of the text is cut off, so parsing it as is would show an unclosed `**` or `[text](ht` as raw symbols, which then turn into decoration or a link on the next token. We distinguish in-progress from complete, and while in progress we normalize only the unfinished syntax at the end before displaying it.

## API

```dart
Markdown(data: partialAnswer, streaming: !isDone);
MarkdownBody(data: partialAnswer, streaming: !isDone);
SliverMarkdown(data: partialAnswer, streaming: !isDone);
```

`streaming` is an extra of this package; flutter_markdown has no equivalent, and a flutter_markdown call site works unchanged without it.

- `streaming` is a `bool` on `Markdown`, `MarkdownBody`, and `SliverMarkdown`, and defaults to `false` (complete).
- `MarkdownBody` always lays its blocks out in a `Column`, also for a single block, so the state of a block (for example an opened `details`) survives a stream that grows from one block to two.
- When `false`, the result is exactly the same as a normal parse with no normalization. Set it to `false` once generation finishes, and the final frame matches a full-document parse.
- You can also use `IncrementalMarkdownParser.parse(source, streaming: true)` and `markdownXRepairStreamingTail(String)`, which normalizes only the source.
- There is no settings object (policy object) to change the approach. Every added option adds verification work, so we provide only the single approach in the table below.

## Approach: normalize the end of the source before parsing

Only the part of the last chunk that corresponds to the last block is normalized. A chunk is the unit into which incremental parsing splits the document (`splitChunks`); the source of completed chunks is not touched.

```text
source ─ split into chunks ─▶ [completed chunks ...] [last chunk] ─ normalize tail only ─▶ parse (Rust)
```

We did not choose to post-process the IR. The reasons are:

- In CommonMark, an unclosed `**` enters the IR as literal characters. Restoring "this was an unfinished marker" on the IR side would require carrying the original positional relationships, which means processing the IR.
- If we normalize the source, what follows is ordinary Markdown, so the result is the same on every platform (FFI / WASM). Rust is unchanged.
- Source and IR of completed chunks are unchanged, so the incremental parse cache still works. The number of full re-parses is the same as before (the only addition is one scan of the last chunk).

The tradeoff is that the normalized source differs from the actual input. Heading IDs and footnote numbers are built from the normalized source, but because only the end is normalized, the settled portion does not change.

## Policy by syntax

| Trailing state | Policy | Example (input → displayed source) |
|---|---|---|
| Unclosed emphasis, strong, or strikethrough | Close with the intended decoration | `a **bol` → `a **bol**` |
| Closing marker partially written | Complete the closing marker | `**bold*` → `**bold**` |
| Opening marker with no content | Hide | `a **` → `a ` |
| Unclosed inline code | Close it. Hide if there is no content | `` `cod `` → `` `cod` ``, `` ` `` → empty |
| Partial link | Show text only (hide the parentheses and destination; not tappable) | `[text](htt` → `text`, `[text` → `text` |
| Partial image | Hide entirely (show neither alt nor destination) | `![alt](ur` → empty |
| Partial footnote reference | Hide | `a[^no` → `a` |
| Partial HTML tag or autolink | Hide | `x <span style="col` → `x ` |
| A lone `\` at the end of a line | Hide | `a\` → `a` |
| Unclosed fence | Show as a code block as is. However, the language name is not shown until the opening line is terminated by a newline, and a partially written closing fence (shorter than the opening) and trailing blank lines are not shown | ` ```da ` → ` ``` ` |
| Table row with only a header | Show as an empty table with just the header (the delimiter row is supplied) | `\| a \| b \|` → the same row plus `\| --- \| --- \|` |
| Partial table delimiter row | Complete it to match the header's column count | `\| -` after `\| a \| b \|` → `\| --- \| --- \|` |
| Table body row | Normalize only the inline content of the last cell. Hide a row consisting only of `\|` | `\| 1 \| **2` → `\| 1 \| **2**` |
| Final line consisting only of a leading marker (`-` `*` `+` `1.` `#` `>` `- [ ]`) | Hide | `-` after `- a` → `- a` |
| Final line of only `-` or `=` right after a paragraph | Hide (so it is not misread as a setext heading) | `---` after `Title` → stays a paragraph |
| Start of a partially written reference definition or footnote definition (`[foo]:`, `[^1]`) | Hide | `[foo]:` → empty |
| Unclosed math (`$$ ...`, `\[ ...`, `\( ...`; when using the [math.md](math.md) extension) | Hide the delimiters and show the partial TeX in monospace (the math builder is not called) | `$$\na_1 +` → `a_1 +` (monospace) |
| Unclosed ```` ```mermaid ```` fence (when using the [mermaid.md](mermaid.md) extension) | Shown as a code block; the Mermaid builder is called once the closing fence arrives | ```` ```mermaid\nA-->```` → code block |
| A single unclosed `$` (same) | Left as literal text (cannot be told apart from currency). Becomes math once closed | `値は $x_1 +` → unchanged |
| Partially written alert marker on the first line of a quote (`> [!NO`, `> [!NOTE]` before the newline) | Hide until the newline arrives | `> [!NO` → empty. See [alerts-and-citations.md](alerts-and-citations.md) for details |
| Partially written digits-only citation (`[1`, `[1, 2`, `【1†sou`) | Hide | `see [1` → `see ` |

Notes:

- Opening and closing of decoration is decided according to the CommonMark flanking rules (including Unicode whitespace and punctuation). Symbols that cannot open a run (`2 * 3`, `snake_case`, some symbols immediately before or after Japanese text) are left unchanged.
- If removing the trailing marker leaves a line of only a leading marker (`-<b` → `-`), that line is hidden as well.
- Inside block quotes, lists, and headings, the same rules apply to the body text with the leading marker removed.
- The contents of a fence (the code block body) and code blocks indented four or more characters are not normalized as inline.

## When nothing is normalized

Nothing is done to the following input.

- Completed blocks (all but the last block)
- Any input with `streaming: false`
- Complete syntax that reaches its closing marker (`**bold**`, `[a](b)`, a finished table)

Passing `streaming: true` for a finished document gives the same IR as a normal parse for representative documents (verified by tests). However, if a finished document contains a marker that meets the opening conditions but is not closed (such as the second `**` in `日本語**「強調」**です`), that marker is closed. Always switch back to `streaming: false` once generation finishes.

## Transitions where the display can change (tolerated layout shift)

In the transitions below, the appearance of settled blocks does not change, but the appearance of the last block does. In every case, preventing it entirely would delay the display or show an incorrect display for longer, so we tolerate it.

| Transition | What changes | Why it is tolerated |
|---|---|---|
| Emphasis, link, or code closes | The range of the trailing decoration grows. A link changes from text to a tappable link | The range only grows; height does not change apart from line wrapping |
| Content appears after an opening marker alone | Text appears after the hidden marker | Better than showing the raw marker |
| An image destination closes | An image appears where there was nothing, increasing height | An image cannot load until its destination is known. Showing the alt text first would swap from text to image, causing two shifts |
| A footnote reference closes (`[^1]`) and then the definition arrives | The reference stays as body text until the definition arrives. When the definition arrives it becomes a superscript link | The definition comes at the end of the document, so the reference cannot be decided earlier. An exception where an earlier block changes later |
| Reference link `[text][ref]` and its definition | Stays as text until the definition arrives, then becomes a link | Same as above. Reference definitions also change earlier blocks via later input |
| State ending in `[text]` | Looks like bracketed text. Becomes a link when `(` follows | Cannot be told apart from text such as `[1]`. Hiding the brackets would briefly turn `[1]` into `1` |
| Setext heading (`Title` and `---` on the next line) | A paragraph becomes a heading when the underline line gets its newline | It is shown as a paragraph until the underline line is fully written. There is only one transition to a heading |
| A table header becomes a table | Body rows are added to a header-only table | The table is shown from the header stage, so there is no shift from paragraph to table. However, a header not starting with `\|` (`a \| b`) is a paragraph until the delimiter row arrives |
| Table column count | When header cells increase, the delimiter row and columns increase | The column count is not decided until the header is fully written |
| Table body cell | The text of the last cell of the last row grows | The row is settled; only the text grows |
| A list becomes loose | Item spacing widens | It cannot be decided until the next item after a blank line arrives (the CommonMark definition) |
| A paragraph continues after a list or heading | The preceding paragraph does not change | Lists, headings, and quotes can interrupt a paragraph, so a settled paragraph does not change |
| A closing fence arrives | The end of the code block is settled, and the following body stops being code | Until the fence closes, all following lines are code (the CommonMark definition) |
| Fence language name | There is no language name until the opening line is terminated by a newline, and it is settled once the newline arrives | Avoids the language name changing one character at a time and the highlighting changing repeatedly |
| HTML `<details>`, `<blockquote>`, `<ul>` / `<ol>` | Until the closing tag arrives, the open element is shown as a block with its content (the following text stays inside it) | This is the parser's normal behavior |

## Stability of settled blocks

Blocks before the last block do not change as more input arrives (and the number of blocks does not decrease). This property is tested on every prefix of representative documents (emphasis, links, images, fences, tables, HTML, lists, headings, footnotes, Japanese). Exceptions where it does not hold:

- Footnote definitions and reference definitions: the block containing an earlier reference changes when the definition arrives.
- An underline directly after a paragraph (setext) and lazy continuation: these are changes inside the last block, so the block is not settled as a block. The last block can change.

## Tests

`test/parser/streaming_test.dart` verifies the following.

- Individual input and output of `markdownXRepairStreamingTail` (each row of the table above)
- Streaming every prefix of representative documents one character at a time, checking that no exception is thrown, that no raw symbols (`**`, `~~`, `` ` ``, `](`, `![`, `<`, the table `|`) are visible in the body, that no broken link or image destinations appear, that no empty heading, quote, or list item appears, that the fence language name does not appear partway, and that settled blocks do not change
- The final frame with `streaming: false` matches a full-document parse
- No exception on every prefix of inputs with randomly arranged symbols

## Limitations

- A bare URL (`www.example.com`) becomes a link even while partially written, and tapping it opens the partial URL. We cannot tell whether a URL is partial or complete, so it is not normalized.
- The logic for closing unclosed markers is a simplified version of the CommonMark emphasis rules (the rule of 3 is implemented). For pathological inputs with tangled delimiters, the parse after normalization can take an unexpected shape, in the same kind of CommonMark corner cases as the original input (`doc/conformance.md`).
- A table inside a block quote and a table inside a list are not treated as tables (the rows are only normalized).
- Trailing blank lines are not shown inside a fence. If only a blank line is added before the fence closes, the blank line is not displayed until the next line arrives.
- For input where a backtick follows immediately after a backslash-escaped backtick (`` \` ``), there is a known discrepancy where the parse takes an unexpected shape, and the normalized result can be the same.
