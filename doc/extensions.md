# Builders and syntax extensions

This document covers replacing the rendering (builders) and adding custom syntax (extensions).

flutter_markdown's own extension points keep working: `builders` and `paddingBuilders` (with `package:markdown`'s `md.Element`), `sizedImageBuilder`, `checkboxBuilder`, `bulletBuilder`, and `syntaxHighlighter` are bridged from the IR ([flutter_markdown_compat.md](flutter_markdown_compat.md#4a-builders-and-paddingbuilders)). `blockSyntaxes`, `inlineSyntaxes` and `extensionSet` are accepted for compile compatibility, but custom `md.BlockSyntax` / `md.InlineSyntax` subclasses cannot run inside the Rust parser; they are reported once and `MarkdownXExtension` below is their replacement. The IR-level `blockBuilder`, `inlineBuilder` and `MarkdownXExtension` are extras of this package.

## Overview

```text
Markdown ─ parser (Rust) ─▶ IR ─ extension (IR transform) ─▶ IR' ─ renderer ─▶ Widget
                                                                        │
                                  blockBuilder / inlineBuilder, then builders / sizedImageBuilder / ...
```

- New syntax is added with an extension that transforms the parsed IR. The parser is not touched
- Rendering is replaced with builders, which are called at render time
- Both are passed as arguments of `Markdown`, `MarkdownBody` and `SliverMarkdown`

## Block builder

```dart
typedef MarkdownXBlockBuilder = Widget? Function(
  BuildContext context,
  MdxBlock block,
  Widget Function() buildDefault,
);
```

- Returning null gives the default rendering
- `buildDefault` is a function that creates the default widget. If you do not call it, the default widget is never created. When you only replace, there is no waste; call it only when you wrap the default in a frame (calling it any number of times gives the same appearance)
- The decision is made inside `MdxBlockView.build`. As a result, it is also called for blocks inside quotes, list items, and details, and every block such as headings, quotes, lists, tables, and code blocks can be replaced
- `buildDefault` is lazy because passing a `Widget` directly would create the default widget every time, even for a block that gets replaced
- The evaluation order is `blockBuilder` → `builders` (flutter_markdown's `MarkdownElementBuilder` by tag, for example `code`; see below) → default. A block for which `blockBuilder` returned null goes on to the element builders. A code block is replaced through `blockBuilder` (`block is MdxCodeBlock`) or `builders['pre']` / `builders['code']`
- A table cell is a sequence of inlines, not a block, so the content of a cell is replaced with the inline builder

```dart
Widget? heading(BuildContext context, MdxBlock block, Widget Function() buildDefault) {
  if (block is! MdxHeading) return null;
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: buildDefault(),
  );
}
```

Nested context such as the text color inside a quote is not passed to the builder. Only the default widget (`buildDefault`) reflects that context.

## Inline builder

```dart
typedef MarkdownXInlineBuilder = InlineSpan? Function(
  BuildContext context,
  MdxInline inline,
  TextStyle style,
  InlineSpan Function() buildDefault,
);
```

- It is called for every inline, including body text, emphasis, links, images, and custom inlines. This is the same in paragraphs, headings, table cells, and the details summary
- `style` is the text style actually applied at that position. It does not include the inline's own decoration (the bold of emphasis or the color of a link)
- `buildDefault` creates the default span. For child inlines, this builder is called again
- The return value may be a `TextSpan` or a `WidgetSpan`. Null gives the default rendering
- A span replaced inside a link gets no tap handling. If needed, attach a recognizer on the builder side
- An image for which the inline builder returned null is rendered through `builders['img']`, then `sizedImageBuilder` / `imageBuilder`. After that it goes to `imageResolver`, then the default resolver ([images.md](images.md))

## flutter_markdown builders

`builders` maps a tag name to a `MarkdownElementBuilder` and `paddingBuilders` maps a tag to a `MarkdownPaddingBuilder`, exactly as in flutter_markdown:

```dart
MarkdownBody(
  data: markdown,
  builders: {'code': CodeElementBuilder()},
  paddingBuilders: {'p': ZeroPadding()},
);
```

The IR is converted to `md.Element` only for blocks that contain a registered tag, so documents without builders pay nothing. The tags and attributes are those of `package:markdown` (`pre` > `code` with `class="language-x"`, `a` with `href` and `title`, `img`, the task list `input`, `th` / `td` with `align`, footnote `sup` / `a`). An `MdxCustomInline` or `MdxCustomBlock` is exposed under its `type` as the tag name, so a flutter_markdown builder for a custom syntax works unchanged once the syntax is ported to a `MarkdownXExtension`. The call protocol and every tag are in [flutter_markdown_compat.md](flutter_markdown_compat.md#25-markdownelementbuilder-call-protocol); `blockBuilder` and `inlineBuilder` run first.

## Mermaid diagrams

The optional `package:flutter_markdown_x/mermaid.dart` turns ```` ```mermaid ```` fences into an `MdxCustomBlock('mermaid')` and lets the app plug in a renderer with `MarkdownXMermaid(builder: ...)` (`extension` and `blockBuilder`, like math). It is a worked use of `transformSource` with the `streaming` flag plus `transformBlock`. See [mermaid.md](mermaid.md).

## Approach to custom syntax

Custom inlines and blocks are implemented as parser-independent transforms of the parsed IR.

```dart
final mention = MarkdownXExtension(
  inlineSyntaxes: [
    MarkdownXInlineSyntax(
      pattern: RegExp(r'@(\w+)'),
      build: (match) => MdxCustomInline(
        'mention',
        attributes: {'name': match[1]!},
        children: [MdxText(match[0]!)],
      ),
    ),
  ],
);
```

### Why the parser gets no new syntax

There is no mechanism for adding syntax to the parser (the equivalent of `InlineSyntax` in the `markdown` package). A flutter_markdown app that passes `inlineSyntaxes` or `blockSyntaxes` gets one `FlutterError.reportError` per syntax type, pointing here. Built-in syntax types the parser already covers (`TableSyntax`, `StrikethroughSyntax`, `AutolinkExtensionSyntax`, and so on) are no-ops, `HeaderWithIdSyntax` / `ExtensionSet.gitHubWeb` give headings ids, and `AlertBlockSyntax` turns alerts on. The only parser is the Rust implementation, and it is not modified for extensions. With IR transforms, the result is the same over FFI and over WebAssembly.

### IR nodes

- `MdxCustomInline(type, {attributes, children})`
- `MdxCustomBlock(type, {attributes, inlines, blocks})`

Like the other nodes, both are immutable and comparable by value. `attributes` holds an unmodifiable copy, and Map order does not affect equality. `children`, `inlines`, and `blocks` are the fallback rendering used when there is no builder, and are rendered like ordinary inlines and blocks. Even without a builder, the text is not lost.

The parser never creates custom nodes. They appear only as the result of applying an extension.

### Inline transform rules

- The target is `MdxText`. Adjacent `MdxText` nodes are concatenated before matching
- Code spans (`MdxStyleKind.code`, `keyboard`), code blocks, image alt text, and link hrefs are excluded
- Inside link text is a target only when `MarkdownXInlineSyntax(applyInsideLinks: true)` is specified. The text of an autolink (the URL itself) never is
- When `build` returns text, it is merged into the adjacent text
- `MarkdownXInlineSyntax(rescanAfterRejected: true)` resumes one character after the start of a match that `build` rejected (default: after the match)
- Inside emphasis, `<span>`, and so on is processed recursively
- When there are multiple syntaxes, the earliest match wins. At the same position, registration order applies (extension order, then the order of `inlineSyntaxes` within it)
- A zero-length match and a match for which `build` returned null are ignored
- The inline returned by `build` is not transformed again

### Block transform

`MarkdownXExtension(transformBlock: ...)` receives a block after its children (nested blocks and inline transforms) have been processed. Return a new block to replace it, or null to leave it as is. It is also called for nested blocks (inside quotes, list items, and details).

```dart
final note = MarkdownXExtension(
  transformBlock: (block) {
    if (block is MdxParagraph && block.inlines.first case MdxText(:final text)
        when text.startsWith('NOTE: ')) {
      return MdxCustomBlock('note', inlines: [
        MdxText(text.substring(6)),
        ...block.inlines.skip(1),
      ]);
    }
    return null;
  },
);
```

### Use without widgets

```dart
final blocks = applyMarkdownXExtensions(parseMarkdown(source), [mention]);
```

This gives the same result as the widget. Subtrees with no change are returned as the same instance, and if nothing changes, the input list itself is returned.

### Source transform (`transformSource`)

Notation that breaks when CommonMark interprets it first (math's `\\`, `\{`, `_`, and so on) cannot be restored from the IR after parsing. Such extensions use `MarkdownXExtension(transformSource: ..., transformInline: ...)` to move the notation into a code span before parsing and restore it after parsing. Math ([math.md](math.md)) uses this approach.

```dart
typedef MarkdownXSourceTransform = String Function(String source, {required bool streaming});
typedef MarkdownXInlineTransform = MdxInline? Function(MdxInline inline);
```

- `transformSource` transforms the source string before parsing. The parser receives the transformed source (the parser is not touched)
- The transform is applied per chunk (`splitChunks`). Chunks are split only after blank lines, so for notation that does not cross a blank line, the IR matches the result of applying it to the whole text. The function must be pure (the chunk cache key is the original source). The parser does not apply it twice to already-transformed source
- `streaming` says whether the last chunk is still being generated. It is applied before the tail repair (`doc/streaming.md`), so an extension can protect the content of the escaped notation from the repair
- `transformInline` receives every inline other than text (including those inside code spans, links, and emphasis), after its children have been processed. It also targets code spans, which `inlineSyntaxes` does not, so use it to restore an escaped code span. Returning null means no transform
- `transformRoot` receives the whole sequence of top-level blocks after all blocks have been processed. `transformBlock` does not know the parent and children are processed before parents, so use this for the top-level cleanup of mechanisms where the parent cleans up (such as removing the alert mark). With `IncrementalMarkdownParser`, it is called per chunk
- To apply it without a widget, use `applyMarkdownXSourceTransforms(source, extensions)`

### Built-in extensions

GitHub alerts (`markdownXAlertsExtension`, enabled by default), citations (`markdownXCitationExtension`, opt-in), and emoji shortcodes (`markdownXEmojiExtension`, opt-in; enabled by `gitHubWeb` and `EmojiSyntax`) are implemented with this mechanism. See [alerts-and-citations.md](alerts-and-citations.md) for a worked example.

### Emoji shortcodes

`markdownXEmojiExtension` replaces GitHub shortcodes such as `:smile:` and `:+1:` with the emoji. It uses the `emojis` table and the exact rules of `package:markdown`'s `EmojiSyntax`: the pattern is `:([a-z0-9_+-]+):`, so it is lower case only, and an unknown shortcode (`:nope:`) stays text. After a rejected shortcode the scan resumes one character later, so `:foo:smile:` gives `:foo` and the emoji.

- It is off by default, like flutter_markdown. It turns on by itself for `extensionSet: md.ExtensionSet.gitHubWeb` and for `md.EmojiSyntax()` in `inlineSyntaxes` (neither is reported as unsupported). Otherwise pass `extensions: [markdownXEmojiExtension]`.
- The result is plain text merged into the surrounding text, not a custom node. `EmojiSyntax` also produces a `md.Text`, so `builders` see the emoji inside the text, and selection, copy, semantics, and heading text contain the emoji character.
- Inline code, code blocks, link destinations, image alt text, and autolinks (a URL shown as its own text) are untouched. Link text and emphasis are converted, as in `package:markdown`. Math is protected by the math extension.
- Heading slugs follow GitHub: the emoji character is dropped, so `# Hi :tada:` has the id `hi-` (flutter_markdown's `gitHubWeb` builds its id from the unconverted text, giving `hi-tada`).
- Streaming: a half-typed `:smi` stays literal until the closing `:` arrives, then it turns into the emoji. Nothing needs hiding, and every prefix is stable. Because plain text such as `10:30:45` or `a:b:c` can also contain a valid shortcode (`:b:` is an emoji), conversion happens wherever the pattern and table agree, as with `EmojiSyntax`.
- Changing the effective extension list (for example switching `extensionSet`) re-parses the document.

## Caching and invalidation

- `IncrementalMarkdownParser.parse(source, extensions: ...)` caches the transformed result per chunk. The same instance is returned for the same chunk
- If the `extensions` list differs from the previous one (any element is a different instance, the order differs, or the length differs), the chunk cache is discarded
- `Markdown`, `MarkdownBody` and `SliverMarkdown` re-parse when the instances in `extensions` change, even if `data` is the same
- `blockBuilder`, `inlineBuilder`, `sizedImageBuilder`, `imageResolver` and the other render closures are read through the widget's relay: the newest closure is used whenever a block builds, and only a change between null and non-null redraws all blocks. `builders` and `paddingBuilders` invalidate by their key set and the `runtimeType` of each builder. So flutter_markdown-style objects created inside `build()` (a builders map, a closure) do not reprocess unchanged blocks. A same-type builder built with different configuration takes effect for blocks as they rebuild; read configuration from `Theme.of(context)` inside the builder or change the widget `key` ([flutter_markdown_compat.md](flutter_markdown_compat.md#4f-cache-invalidation-with-flutter_markdown-style-call-sites))
- `extensions` is different: keep `MarkdownXExtension` instances in top-level values, fields, or `const`. A new instance on every build re-parses everything every time

## Limitations

- `inlineSyntaxes` and `transformBlock` operate on the IR, so the original Markdown string is not visible. For example, an escaped `\@foo` is already resolved to the text `@foo` at parse time and cannot be distinguished from `@foo`. Syntax that must respect escapes should be handled before parsing with `transformSource` (math is an example)
- `inlineSyntaxes` match only within a single sequence of inlines (a paragraph, heading, or cell). Notation spanning multiple lines or paragraphs (such as `$$ ... $$`) or crossing emphasis or link boundaries (such as `@` followed by emphasis) cannot be handled on the IR side alone. It can be handled by escaping with `transformSource` (except notation spanning blank lines, because of chunk splitting)
- The inside of a code span is not transformed. Conversely, custom syntax cannot be used inside a code span
- `transformBlock` sees only IR blocks. Notation the parser has already turned into another structure (a list or a quote) cannot be restored to its original form
- A span returned by a builder inside a link gets no tap handling
- Extensions only add to the IR and do not change the parser's behavior (CommonMark interpretation)
