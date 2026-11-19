# Alerts and citations

GitHub-style alerts (`> [!NOTE]` and similar) and AI chat source citations (`[1]`) are rendered with dedicated presentations. Both are implemented with the mechanisms in [extensions.md](extensions.md) (alerts use a source transform plus a post-parse IR transform; citations use an IR transform), and the parser is unchanged. The result is the same on every platform.

## GitHub alerts

```markdown
> [!NOTE]
> Supplementary information.

> [!WARNING]
> Content that needs attention.
```

The five kinds `NOTE`, `TIP`, `IMPORTANT`, `WARNING`, and `CAUTION` are drawn with a per-kind icon, color, and title. The marker is case-insensitive.

### Enabling alerts

Widgets enable alerts by default. Pass `alerts: false` to render plain
block quotes. Including `md.AlertBlockSyntax` in `blockSyntaxes` or
`extensionSet` enables alerts even with `alerts: false`.

The implementation is `markdownXAlertsExtension`. The widget prepends it to `extensions` before parsing (it is not added twice if the user already put the same value in `extensions`). When you only want the IR, use it as follows.

```dart
final ext = [markdownXAlertsExtension];
final blocks = applyMarkdownXExtensions(
  parseMarkdown(applyMarkdownXSourceTransforms(source, ext)),
  ext,
);
```

Alerts use a source transform (`transformSource`) that runs before parsing, so when you process only the IR you must also go through `applyMarkdownXSourceTransforms`. A source that does not go through it has no marker, so it does not become an alert (it stays a quote).

### IR

A `MdxBlockquote` is replaced with `MdxCustomBlock('alert', attributes: {'kind': 'note'}, blocks: remaining blocks)`. `kind` is one of `note`, `tip`, `important`, `warning`, `caution` (`MarkdownXAlertKind.name`). The inlines after the marker in the marker paragraph remain as a body paragraph. A quote with only a marker becomes an alert with no body. The transform also applies inside nested quotes, list items, and `details`.

### Detection rules (same as GitHub)

- A quote becomes an alert when its first line consists only of `[!kind]` and trailing whitespace (including the two or more spaces of a hard break). `kind` is case-insensitive. This also applies to nested quotes (`> > [!TIP]`) and quotes inside list items (`- > [!TIP]`)
- A form with text following on the same line (`> [!NOTE] text`) is not an alert. It becomes an ordinary quote containing `[!NOTE] text` as text
- It is not an alert from the second line of a quote onward (`> a\n> [!NOTE]`, including lazy continuation), in the second or later paragraph, when text or emphasis precedes the marker (`> a [!NOTE]`, `> **[!NOTE]**`), or inside a fence, an indented code block, or inline code

In the IR, `> [!NOTE]\n> text` is `MdxText('[!NOTE]')`, `MdxSoftBreak`, `MdxText('text')`. Whether a line is the first line of a quote, a lazy continuation, or a literal text line still cannot be told from the IR, so the detection is split into two stages. When the IR transform builds the alert, it drops the soft break (or hard break) that ends the marker line. After the marker, the IR transform drops the soft break (or hard break) that ends the marker line.

1. `transformSource` looks for a marker-only line as the first line of a quote and appends one private-use character (U+E001, `alertSourceMarker`) right after the `]`. Inside fences and indented code blocks, and from the second line of a quote onward (including lazy continuation), nothing is changed. The transform depends only on lines and blank lines, so applying it per chunk or to the whole text gives the same result
2. The IR transform turns only markers carrying the mark into alerts, and removes the mark. If a mark remains in an unexpected position (code, heading, table, link, second or later paragraph, and so on), the IR transform removes it too. `MarkdownXExtension.transformRoot` also removes marks on top-level blocks, so the mark never appears in the IR, rendering, selection, copy, or semantics

When the alert extension is not used (`alerts: false`), `transformSource` does not run, so no mark is added.

### Appearance

- A rule on the start side (`BorderDirectional`), a light background, an icon, a title, and the body. Under RTL, the rule and icon are on the right
- Colors, icons, and titles come from `MarkdownStyleSheet.alerts` (`MarkdownXAlertStyle`). When the theme is dark, `MarkdownXAlertStyle.dark` is used; otherwise `.light` (GitHub's colors)
- The title string (`label`) can be replaced per kind. Translation is done through the style

```dart
final style = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
  alerts: MarkdownXAlertStyle.light.copyWith(
    note: const MarkdownXAlertKindStyle(
      color: Color(0xFF0969DA),
      icon: Icons.info_outline,
      label: 'Memo',
    ),
  ),
);
```

`alerts` is an extra field of `MarkdownStyleSheet` (null means light or dark by the theme brightness). The style sheet is compared by value, so building it inside `build()` does not redraw unchanged blocks.

### Replacing the rendering

The type `alert` can be replaced with `blockBuilder` (`MdxCustomBlock.type == markdownXAlertType`; get the kind with `markdownXAlertKindOf(block)`). Calling `buildDefault()` lets you wrap the default rendering. The default widget is exposed as `MdxAlertView`.

### Accessibility, selection, and copy

- The title is drawn as text, so it becomes the spoken label (such as `Note`). The icon is decorative and is excluded from reading. The whole alert is grouped into a single `Semantics(container: true)`
- Selection and copy include the title, so the copied text alone shows the alert kind (the `Note` line, then the body, in that order). The icon is not included

### Streaming

With `streaming: true`, while the first line of a quote is a partially written marker (`> [`, `> [!NO`, `> [!NOTE]`), that line is hidden. Even when `[!NOTE]` is complete, text may still follow on the same line, so the line stays hidden until a newline arrives. When the newline arrives, it appears as an alert. This avoids the flicker where `[!NO` shows as raw text and then switches to an alert.

- Only the first line of a quote (where the previous line is not a quote) is hidden
- This clean-up happens at the source stage, so the same line is hidden even with `alerts: false`
- The alert title does not appear until the line after the marker arrives (a one-line delay)
- `transformSource` does not add a mark to a trailing marker line without a newline during streaming (that line is hidden by the clean-up). Once the newline arrives, the mark is added and it becomes an alert
- If text arrives on the same line, as in `> [!NOTE] text`, it does not become an alert and is an ordinary quote (it was hidden before the text arrived, so there is no flicker from alert to quote)

## Citations

AI chat source citations are converted into chips. This is an opt-in extension (it is not enabled by default because `[1]` is also used in ordinary prose).

```dart
// Keep it in a top-level or a field instead of creating it on every build.
final _citations = markdownXCitationExtension();

Markdown(
  data: answer,
  extensions: [_citations],
  onTapCitation: (id) => openSource(id), // the app resolves the target
);
```

### Targets and IR

The default patterns are as follows.

| Input | Result |
|---|---|
| `[1]` | id `1` |
| `[1, 2]` | ids `1` and `2` (two chips in one inline) |
| `【3†source】` | id `3` (ChatGPT format; everything after `†` is discarded) |

It is replaced with `MdxCustomInline('citation', attributes: {'id': '1', 'ids': '1,2'}, children: [MdxText('[1, 2]')])`. `id` is the first id, and `ids` is all ids joined with commas (get a `List<String>` with `markdownXCitationIds(inline)`). `children` is the original text.

- Only digit-only `[1]` is matched. `[a1]`, `[]`, and `[1a]` are not
- Inside code spans, code blocks, image alt text, and link text is excluded. A `[1]` that the parser made a reference link (a `[1]: https://…` definition exists) stays a link. Only a `[1]` with no definition remains as text and becomes a citation
- Inside emphasis and headings is matched
- The pattern can be replaced with `markdownXCitationExtension(pattern: RegExp(...))`. The first group that matched (or the whole match if none) is the id, and it can be split on `,`, `、`, and `;` into multiple ids. When you pass a pattern, a new instance is returned every time, so keep and reuse the returned value (when omitted, the same instance is returned)

### Callback and builder

| Argument | Type | Role |
|---|---|---|
| `onTapCitation` | `void Function(String id)` | Called when a chip is tapped. If null, the chip is not interactive |
| `citationBuilder` | `InlineSpan? Function(BuildContext, List<String> ids, TextStyle style)` | Replaces the chip. Returning null gives the default chip |

Both are available on `Markdown`, `SliverMarkdown`, and `MarkdownBody`. You can also replace the `MdxCustomInline` of type `citation` with `inlineBuilder` (evaluation order: `inlineBuilder`, `citationBuilder`, default). flutter_markdown-style `builders` see a citation as an element with the tag `citation` and the attributes `id` and `ids`; an alert is a `div` with `class="markdown-alert markdown-alert-<kind>"`.

### Default rendering

- Small text at 0.75 times the surrounding text is placed in a rounded chip. Color and scale come from the `citation` extra of `MarkdownStyleSheet` (`MarkdownXCitationStyle`)
- Semantics is `Citation 1` (translatable with `MarkdownXCitationStyle.semanticsLabel`). It is a button when `onTapCitation` is set, and just a label otherwise (included in the paragraph's spoken text)
- Keyboard: when `onTapCitation` is set, the chip is an ordinary `Focus`; Tab moves through them in order (a border appears while focused), and Enter or Space activates it. This is a separate mechanism from link focus ([accessibility.md](accessibility.md)), and Tab moves in widget tree order
- Selection and copy: only the chip's id is copied (`[` and `]` are not included)

### Streaming

With `streaming: true`, a partially written trailing citation (`[1`, `[1,`, `[1, 2`, `【1†sou`) is hidden. A complete `[1]` becomes a chip at that point. This is an exception to the existing policy (`[text` is shown as text only), limited to digit-only partial forms. As a result, even in documents that do not use citations, `[1` is hidden while the text ends with `[1` (it is shown once `[1]` arrives or other characters follow so it is no longer digit-only).

## Limitations

- `> [!NOTE] text`, with text on the same line, is also not an alert (see above)
- The original Markdown string is not kept in the IR, so an escaped `\[1\]` cannot be distinguished from `[1]`. Escaping it still produces a citation
- The citation chip is sized to the text and does not meet the minimum touch target size (48 dp). When a larger target is needed, replace it with `citationBuilder`
- A `[1]` with a reference link definition is a link and does not become a citation. When the AI output contains a definition of the form `[1]: url`, it is shown as a link instead of a citation
- The alert body is drawn in the normal body text color, not the quote color (`blockquoteText`)
