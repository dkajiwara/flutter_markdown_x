# Heading IDs, internal links, table of contents, and footnotes

This page specifies navigating to headings, `#id` internal links, retrieving the table of contents, and round-trip footnote navigation.

## Overview

Heading IDs, the table of contents, and footnote navigation targets are computed in Dart from the parsed IR alone. They do not depend on the parser. The IR is unchanged (`mdx_ir_version` is not bumped).

```text
IR ─ add footnote back-links ─▶ IR' ─ heading IDs / target index ─▶ headings / anchors
```

## Heading IDs

A slug is built from the heading text using the same rules as GitHub.

1. Extract only the heading's text (strip emphasis, code, and links; use alt text for images; turn line breaks into spaces).
2. Trim leading and trailing whitespace and lowercase it.
3. Drop everything except letters, combining marks, digits, `-`, `_`, and spaces (Unicode letters such as Japanese are kept).
4. Replace each space with `-` (consecutive spaces become consecutive `-`).

Examples: `Hello, World!` becomes `hello-world`, and `第1章：概要` becomes `第1章概要`. A heading whose result is empty (such as `!!!`) becomes `section`, unlike GitHub.

For duplicate slugs, `-1`, `-2`, … are appended starting from the second occurrence in document order. If a generated ID collides with another heading's slug, the number is advanced until it is free (`# A`, `# A`, `# A 1` become `a`, `a-1`, `a-1-1`). Footnote IDs (described below) are reserved first, so heading slugs yield to them.

Explicit IDs in HTML such as `<h2 id="...">` are not handled, because the IR carries no attributes.

## Table of contents (TOC)

```dart
List<MarkdownXHeading> markdownXHeadings(List<MdxBlock> blocks);
Map<String, MarkdownXAnchor> markdownXAnchors(List<MdxBlock> blocks);
String markdownXSlug(String text);
```

- `MarkdownXHeading` has `id`, `level` (1 to 6), `text`, and `path`. It is comparable by value.
- Headings inside block quotes, lists, details, and custom blocks are also included, in document order.
- `path` is the route down through nesting, starting from the index of the top-level block. A block quote, details, or custom block adds one child block index; a list adds the item index followed by the index of the block within the item.
- `markdownXAnchors` is the list of IDs that can be navigated to, including headings and footnotes. The `kind` of a `MarkdownXAnchor` is `heading`, `footnote`, or `footnoteReference`.

## MarkdownXController

```dart
final controller = MarkdownXController();

Markdown(data: markdown, markdownController: controller);
MarkdownBody(data: markdown, markdownController: controller);

controller.headings;                          // List<MarkdownXHeading>
controller.hasAnchor('intro');                // bool
await controller.jumpToAnchor('intro');       // Future<bool>
await controller.scrollToHeading(heading);    // Future<bool>
```

- `Markdown.controller` is flutter_markdown's `ScrollController`. `markdownController` is a separate argument (an extra of this package).
- One controller can be attached to only one widget at a time.
- It is a `ChangeNotifier` and notifies only when the list of headings changes. Notification happens after build, so calling `setState` inside a listener is fine. Before it is attached and after it is detached, `headings` is empty.
- `jumpToAnchor(id, {duration, curve, alignment})` returns `true` if it navigated. It returns `false` if the id does not exist, no widget is attached, or the document or widget changed during construction. Do not include the `#`.
- Starting a new navigation ends any in-progress navigation with `false`.

### How navigation works

- `Markdown` builds blocks lazily. When the target block has not been built yet, it estimates an offset from the average height of the blocks built so far and jumps, repeating until the target block is built (up to 100 times). After it is built, it aligns to the exact position by revealing the block in each vertical scrollable.
- `MarkdownBody` has all blocks built already, so it moves the vertical parent scroll view.
- Only vertical scrollables are adjusted. Horizontal ancestors such as a `TabBarView`, a `PageView`, or a horizontal list are never moved, so tapping a link does not switch the tab or page. `Markdown` scrolls its own scroll view, not an outer one.
- Nested headings (inside block quotes, lists, and details) are also found and navigated to after the top-level block has been built.
- A heading inside a closed `details` opens the `details` before navigating. The open state remains afterward.

## Internal links

When a `[text](#id)` link is tapped, these rules apply.

1. If `handleAnchorLinks` is true (the default) and the id after `#` exists in the document, the widget navigates to that position and does not call `onTapLink`.
2. If the id does not exist, or `handleAnchorLinks: false`, the link is passed to `onTapLink(text, href, title)` unchanged, exactly as flutter_markdown does (which never scrolls to anchors).

The id is matched in this order: exact match, then the percent-decoded form, then the lowercased form (case-insensitive, as on GitHub). A link that is just `#` has an empty id and is passed to `onTapLink`. `handleAnchorLinks: false` restores flutter_markdown's behavior for every `#id` link; the comparison tests with flutter_markdown_plus run with it off.

## Footnotes

```markdown
Body text[^a].

[^a]: The footnote text.
```

The parser converts a reference into a superscript link (`#fn-a`, displayed as a number) and the definitions into a thematic break and an ordered list at the end of the document. The information needed for navigation is derived without changing the IR, as follows.

- Reference number N corresponds to the Nth item of the trailing list. The tail is treated as footnote definitions only when the set of reference numbers equals `1..item count` (otherwise it is treated as an ordinary list and no navigation targets are created).
- Tapping a reference (`#fn-a`) navigates to the definition's item (ID `fn-a`).
- A back-link `↩` (`#fnref-a`) to the first reference is appended to each definition. This is done in IR post-processing (inside `Markdown` and `MarkdownBody`) and does not change the result of `parseMarkdown`. The target is the block containing the first reference (a paragraph, a heading, a paragraph inside a block quote, and so on).
- Even with multiple references, the back-link goes only to the first one.

## Limitations

- Navigation targets are at block granularity. For a reference in the middle of a long paragraph, navigation goes to the start of the paragraph.
- When navigating to an unbuilt block in `Markdown`, it approaches the target using an estimate based on the average height of the built blocks. Documents with extremely uneven heights need more attempts, but it usually converges in a few. If it does not arrive after 100 attempts (in practice, also when the position stops changing), it returns `false`.
- Even when the target block has been replaced by a different widget through `blockBuilder`, navigation goes to that block's position. However, list-item markers are attached only to the standard list rendering, so when `blockBuilder` replaces a list, navigation to a footnote definition goes to the top of the whole list.
- When blocks with identical content appear in the tree multiple times as the same instance (for example, when an extension reuses the same IR), navigation goes to the first one.
- Explicit HTML `id` attributes and IDs on non-heading elements are not handled.
- The trailing footnote list is identified as "an ordered list immediately after a thematic break". If a user writes a list of that same shape at the end and there are footnote references whose numbers match, it is treated as footnotes.
- Footnotes with duplicate definitions (two definitions with the same label) have an existing discrepancy where the IR is not as expected (unrelated to this feature).
