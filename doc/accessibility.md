# Selection, copy, accessibility, and RTL

## Summary

- Text selection and copy are enabled with `SelectionArea`. Either the app places a `SelectionArea` above the widget, or you pass `selectable: true` to `Markdown` or `MarkdownBody`.
- Copied text separates blocks with a newline and cells in the same table row with a tab. List markers (`•`, `1.`) are placed before the body text. A code block is copied exactly as the source, including across chunk boundaries.
- Superscript, subscript, inline code, and link text are copied in their original positions. Image alt text is not copied.
- Links can be focused in order with Tab and Shift+Tab and opened with Enter or Space. They are exposed to semantics as links.
- The `details` summary is a button, and its expanded state is included in semantics. It can also be toggled from the keyboard (Tab, Enter, Space).
- Under RTL (`Directionality` is `TextDirection.rtl`), list markers, the quote rule, the `details` arrow, and table columns are laid out from the right. Only code blocks always read left to right.

## Selection and copy

### Enabling it

```dart
// The app places a SelectionArea (recommended; the whole screen becomes one selection range).
SelectionArea(child: Markdown(data: text));

// Simple option
Markdown(data: text, selectable: true);
MarkdownBody(data: text, selectable: true);
```

- `selectable` defaults to `false`. When true, the widget only wraps itself in a `SelectionArea`; selection does not extend to other widgets. Do not set it when an ancestor already has a `SelectionArea`.
- `SliverMarkdown` is a sliver and has no `selectable`. Wrap the `CustomScrollView` in a `SelectionArea`.
- Outside a `SelectionArea`, no selection-related widgets or State objects are created.

### flutter_markdown's selection callbacks

`onSelectionChanged`, `onTapText`, and `contextMenuBuilder` exist with flutter_markdown's names and apply when `selectable` is true. The selection model differs from flutter_markdown, which draws one `SelectableText` per text block; this package uses one `SelectionArea` for the whole document ([flutter_markdown_compat.md](flutter_markdown_compat.md#22-markdownwidget-constructor-parameters)).

- `onSelectionChanged(text, selection, cause)`: `text` is the selected plain text and `selection` covers all of it, so `text.substring(selection.start, selection.end) == text`. `cause` is always `null`. It is not called when the selection is cleared or empty.
- `onTapText`: called when text is tapped. A tap on a link goes to the link (`onTapLink`) instead.
- `contextMenuBuilder`: the default is the platform toolbar, and `null` disables the menu. A custom `EditableTextContextMenuBuilder` cannot be honored (a `SelectionArea` needs a `SelectableRegionContextMenuBuilder`); it is reported once through `FlutterError.reportError` and the default menu is used. To customize the menu, wrap the widget in your own `SelectionArea(contextMenuBuilder: ...)` instead of passing `selectable`.

### Rules for the copied text

| Target | Copied text |
|---|---|
| Between blocks (paragraph, heading, list, table, code, quote, details) | Separated by a single newline. No blank line is inserted |
| Selecting within a single block | No extra leading or trailing newline |
| List items | `• body` or `1. body`. One space between marker and body. Items are separated by newlines |
| Task list | Body text only. The checkbox state is not text |
| Table | Cells in the same row are separated by a tab, rows by a newline. The header follows the same rule |
| Code block | Identical to the source. No newline is added or lost at the boundaries of 200-line chunks |
| Superscript and subscript | The characters are included as-is in their original position (`H<sub>2</sub>O` becomes `H2O`) |
| Inline code and links | Text only (the URL is not included) |
| Images | Nothing, including alt text. The same applies to the fallback shown when loading fails |
| Footnote back-link `↩` | Included (see the limitations below) |
| Nesting (a list inside a quote, etc.) | The same rules are applied recursively |

The mechanism: each block is wrapped in a selection container (`SelectionContainer`), and a separator is prepended to its own text only when "something earlier within the same parent has been selected". Flutter's selection concatenates adjacent `Text` widgets without a separator, so without this separator, paragraphs would run together like `ab`.

### Selection while streaming

No exception is thrown when `data` is updated. The following rules are verified by tests.

- The selection in a block whose content has not changed is kept. Appending a block at the end keeps the selection in earlier blocks.
- The selection in a block whose content changed (such as the last block being appended to) is cleared, because the widget content changes. A newly added block is not selected.
- No exception is thrown when a selected block disappears.

### Limitations

- `Markdown` and `SliverMarkdown` build blocks lazily, so blocks that are far from the screen and not yet built are not included in "select all". To copy the whole document, use `MarkdownBody` (which builds every block), or pass the original `data` from your own copy button. A selected block is kept even if scrolling takes an already-built block out of view (this is Flutter's behavior).
- The footnote back-link `↩` is selected and copied as a trailing character of the body. To exclude it, remove it from the copied string in your app.
- Empty table cells do not emit a separating tab either (`a | | c` becomes `a\tc`).
- Text inside a custom widget returned by `blockBuilder`, `builders`, or `sizedImageBuilder` is copied if that widget supports selection, and block-level separators are added.
- To copy image alt text, return a `Text` or similar from `sizedImageBuilder`.
- Superscript and subscript are drawn toward the top and bottom edges of the line. This is not an exact offset from the baseline (a position-shifting `Transform` would break the selection order and put the copied characters in the wrong place).
- Flutter's selection applies registrations after the next frame. When the nesting is deep and the screen is idle, the registration does not reach the upper levels and select-all becomes empty (confirmed on Flutter 3.47). The selection container works around this by requesting one frame per registration. No frame is requested outside a `SelectionArea`.

## Keyboard operation and semantics

### Links

- A paragraph that contains links (including headings and table cells) has one `Focus`. Entering the paragraph with Tab focuses the first link; entering with Shift+Tab focuses the last link.
- Within a paragraph, Tab and Shift+Tab move through the links one by one; at either end, focus moves on as usual (to the previous or next paragraph or widget).
- A focused link gets a background color (the link color at 0.2 opacity).
- Enter, numpad Enter, and Space call `onTapLink` (or jump to `#id`), the same as a tap.
- A paragraph without links has no `Focus`.
- Each link is exposed to semantics as a link (`isLink`, with the link text as its label and a tap action). Screen reader interaction uses Flutter's `RenderParagraph` features.
- An inline replaced by `inlineBuilder` gets no link handling (existing behavior) and does not receive focus.

### details

- The summary is a button, and its `expanded` state (open or closed) is included in semantics.
- It can be focused with Tab and toggled with Enter or Space.

### Other elements

| Element | Semantics |
|---|---|
| Heading | header |
| Image (default rendering) | An image labeled with the alt text. An image with empty alt is not read aloud. The label is kept even if loading fails. The label of an image replaced via `sizedImageBuilder` or `imageBuilder` is the app's responsibility. Loading and error displays are excluded, and a tap action is added when `onTapImage` is set ([images.md](images.md)) |
| Task list checkbox | The checked state (true or false). With `onTapCheckbox` it also has a tap action, can take keyboard focus (Tab; Space, Enter and numpad Enter toggle it; a focus ring is drawn) and the focus stays on the task after the toggle rebuilds it. The app's `checkboxBuilder` widget is wrapped the same way, and its own semantics are replaced by the checkbox node ([syntax.md](syntax.md#toggling-task-checkboxes)) |
| Table | The text of each cell is read one by one, in row and column order. `SemanticsRole.table` is not used (Flutter requires nodes that represent rows, but `Table` has no row widgets) |

## RTL

When `Directionality` is `TextDirection.rtl`, elements are laid out as a mirror image of LTR.

| Element | Rendering under RTL |
|---|---|
| Paragraph, heading | Aligned to the right edge (`TextAlign.start`). Left or right explicitly set with HTML `align` stays left or right |
| List marker | On the right. The body is offset to the left by `listIndent`. The task list checkbox is also on the right |
| Quote | The rule and padding are on the right (`BorderDirectional`, `EdgeInsetsDirectional`) |
| Table | The first column is at the right edge. Column alignment stays as specified in Markdown (left or right) |
| Code block | Always LTR. Both the text and horizontal scrolling start from the left edge |
| details | The arrow is on the right, and flips to point left when closed. The opened content is inset from the right by `listIndent` |
| Copy order | Markers and cells are both ordered right to left (logical order) |

Positions are verified with rects for both LTR and RTL in `test/widgets/rtl_test.dart`.

## Performance impact

- Outside a `SelectionArea`: each block makes just one `SelectionContainer.maybeOf` call, and no widgets or State objects are added. Only paragraphs with links hold one `Focus` and one `FocusNode`.
- Inside a `SelectionArea`: each block (plus list markers and items, table cells, and chunks of code beyond 200 lines) holds one `SelectionContainer` and one delegate. In flutter_test in debug mode, the first build of a `MarkdownBody` with 3,000 blocks (1,500 paragraphs and 1,500 lists) took about 0.6 to 1.3 seconds without a `SelectionArea` and about 0.9 to 1.2 seconds with one (the variance is large). `Markdown` builds only on-screen blocks, so this difference is proportional to the number of on-screen blocks.
- Registration of top-level block selections is gathered into one intermediary (a registry) inside `Markdown` and `MarkdownBody`. When copying, each block checks the blocks above it from the back (it ends in one step if a selected block is adjacent).
