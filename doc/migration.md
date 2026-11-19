# Migrating from flutter_markdown / flutter_markdown_plus

`flutter_markdown_x` is a drop-in replacement for [`flutter_markdown`](https://pub.dev/packages/flutter_markdown) and its maintained fork [`flutter_markdown_plus`](https://pub.dev/packages/flutter_markdown_plus). The widgets, the style sheet, the builder classes, and the callbacks keep the names, signatures, and defaults of flutter_markdown 0.7.7+1 and flutter_markdown_plus 1.0.12, so for most apps the migration is one line.

This guide lists what compiles unchanged, every behavior that differs, and how to port the few things that cannot work as before. The complete parameter-by-parameter reference is [flutter_markdown_compat.md](flutter_markdown_compat.md).

## Contents

1. [Swap the import](#1-swap-the-import)
2. [What compiles unchanged](#2-what-compiles-unchanged)
3. [Behavior differences](#3-behavior-differences)
4. [Porting what does not carry over](#4-porting-what-does-not-carry-over)
5. [What you gain](#5-what-you-gain)
6. [Platform setup](#6-platform-setup)

## 1. Swap the import

```yaml
# pubspec.yaml
dependencies:
  # flutter_markdown: ^0.7.7   (or flutter_markdown_plus)
  flutter_markdown_x: ^0.1.0
```

```dart
// Before
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
// After
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:material_ui/material_ui.dart';
```

flutter_markdown_x is built on `material_ui` and `cupertino_ui`, the packages that replace the deprecated `package:flutter/material.dart` and `package:flutter/cupertino.dart`. Their `ThemeData`, `Theme`, `MaterialApp` and so on are separate types from the SDK's, so migrating also means moving the app to `material_ui`: add `material_ui` (and `cupertino_ui` if you use Cupertino widgets) to the pubspec, replace the two imports in the files that use Material or Cupertino, and install the app theme with `material_ui`'s `MaterialApp`. `MarkdownStyleSheet.fromTheme(ThemeData)` takes `material_ui`'s `ThemeData`, and the widgets follow the `Theme` of `material_ui`. If the app stays on the SDK Material library, the Markdown widgets show the default theme and `fromTheme` does not compile with the SDK's `ThemeData`; pass an explicit `styleSheet:` built with the `MarkdownStyleSheet` constructor (its fields are shared `TextStyle` / `Color` types). Details: [Material library (Flutter 3.50)](flutter_markdown_compat.md#material-library-flutter-350).

Nothing else has to change:

```dart
// Unchanged code
Markdown(
  data: markdown,
  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    p: const TextStyle(fontSize: 16),
    blockSpacing: 12,
  ),
  onTapLink: (text, href, title) => launchUrl(Uri.parse(href!)),
  builders: {'code': CodeElementBuilder()},
);
```

The requirements are higher than flutter_markdown's: Flutter 3.50.0 or later (Dart 3.14.0 or later). The parser is a bundled Rust library; apps do not need Rust installed.

## 2. What compiles unchanged

- `MarkdownWidget`, `Markdown`, `MarkdownBody` with every constructor parameter of flutter_markdown 0.7.7+1 and of flutter_markdown_plus 1.0.12 (`selectable`, `styleSheet`, `styleSheetTheme`, `syntaxHighlighter`, `onSelectionChanged`, `onTapLink`, `onTapText`, `contextMenuBuilder`, `imageDirectory`, `blockSyntaxes`, `inlineSyntaxes`, `extensionSet`, `imageBuilder`, `sizedImageBuilder`, `checkboxBuilder`, `bulletBuilder`, `builders`, `paddingBuilders`, `fitContent`, `listItemCrossAxisAlignment`, `softLineBreak`, `shrinkWrap`, `padding`, `controller`, `physics`, `dragStartBehavior`, `noScroll`).
- `MarkdownStyleSheet` with all fields, `fromTheme`, `fromCupertinoTheme`, `largeFromTheme`, `copyWith`, `merge`, `styles`, and value equality. `MarkdownStyleSheetBaseTheme`.
- `MarkdownElementBuilder` (including the classic `code` builder that overrides `visitElementAfter`), `MarkdownPaddingBuilder`, `SyntaxHighlighter`, `MarkdownBulletParameters`, `BulletStyle`, `MarkdownImageConfig`, `MarkdownListItemCrossAxisAlignment`, and every typedef (`MarkdownTapLinkCallback`, `MarkdownCheckboxBuilder`, `MarkdownBulletBuilder`, and so on).
- `package:markdown` types in your own code (`md.Element`, `md.Text`, `md.ExtensionSet`, `md.BlockSyntax`, `md.InlineSyntax`). The package depends on `markdown` for these types only; parsing is Rust.

The call protocol of builders is the same: `visitElementBefore`, `visitText`, `visitElementAfterWithContext` (default: the deprecated `visitElementAfter`), `getPadding`, with the same `md.Element` tags and attributes (`code` inside `pre` with `class="language-x"`, `a` with `href` and `title`, `img` with `src`, `alt` and `title`, the task list `input`, `th` / `td` with `align`, and so on). `test/flutter_markdown/plus_comparison_test.dart` records the call sequences of both packages on the same documents and asserts that they agree, apart from the differences below.

## 3. Behavior differences

Rendering follows flutter_markdown, with these differences. Rows marked intentional are decisions, not gaps.

| Area | flutter_markdown / flutter_markdown_plus | flutter_markdown_x | Why |
|---|---|---|---|
| Raw HTML | Shown as literal text (`<b>x</b>` is displayed verbatim) | An allowlist is interpreted (`<br>`, `<sub>`, `<sup>`, `<kbd>`, `<mark>`, `<cite>`, `<abbr>`, `<q>`, `<details>`, `<table>`, `<pre>`, `style` colors); other tags are shown as literal text as in flutter_markdown, `<script>` and `<style>` are dropped ([html.md](html.md)) | Intentional |
| Footnotes | Definitions follow the text | One extra horizontal rule is drawn before the definitions; the rest (including the separate `' '` before the back reference) is identical | Intentional |
| Loose task lists (items separated by blank lines) | A bullet, because only `li.children[0]` is inspected (flutter_markdown_plus has this as a bug) | A checkbox, as GitHub renders them | Intentional: GFM-correct |
| Task list checkbox color (`MarkdownStyleSheet.fromTheme`, `largeFromTheme`) | `theme.primaryColor`, which is almost black in a dark theme, so the checkbox is invisible on a dark background | `theme.colorScheme.primary` (the same color as before in a default light Material 3 theme) | Intentional: fixes a flutter_markdown bug |
| Blockquote box in a dark theme (`fromTheme`) | A light-blue box (`Colors.blue.shade100`) under near-white text, about 1.1:1 contrast | `colorScheme.surfaceContainerHighest` in a dark theme; unchanged in a light theme | Intentional: fixes a flutter_markdown bug |
| Image that fails to load, or whose `src` is unusable | An empty `SizedBox` | The alt text (also the accessibility label); replaceable with `imageErrorBuilder` | Intentional ([images.md](images.md)) |
| `file:` and relative-path images | Loaded implicitly with `Image.file` (relative to the process directory) | Not loaded by default, because Markdown can be untrusted (LLM output). A non-null `imageDirectory` is the opt-in for the files below it; `imageResolver` with `markdownXFileImageProvider` opts in for `file:` | Intentional ([images.md](images.md)) |
| `imageDirectory` | `imageDirectory + src` as a string | The same string rule, but only for a `src` without a scheme (`ftp:` and `file:` sources are not joined) | Safer; same result for normal inputs |
| Relative `src` without `imageDirectory`, on web | `p.join(p.current, src)` | The same (resolved against the page URL) | Parity |
| `#id` links | Passed to `onTapLink` | A `#id` that exists in the document scrolls there (headings and footnotes) and does not call `onTapLink`; every other link is passed as before. `handleAnchorLinks: false` restores the old behavior | Extra |
| `onSelectionChanged` | One `SelectableText` per text block: per-block `TextSelection` and cause | One `SelectionArea` for the document: `text` is the selected plain text, `selection` covers all of it, `cause` is always `null`; not called when the selection is cleared | The selection model differs |
| `contextMenuBuilder` (plus) | Any `EditableTextContextMenuBuilder` | The default and `null` (no menu) are honored. A custom function is reported once through `FlutterError.reportError` and the default menu is used | `SelectionArea` needs a different builder type |
| Custom `blockSyntaxes` / `inlineSyntaxes` | Run by `package:markdown` | Not run (the parser is Rust). Built-in syntax types the parser already covers are no-ops; any other syntax is reported once per type through `FlutterError.reportError`, pointing to `MarkdownXExtension` | Never silently ignored |
| `ExtensionSet.commonMark` / `ExtensionSet.none` | Turn GFM off | No effect: GFM (tables, strikethrough, task lists, footnotes, autolinks) stays on | The Rust parser options are fixed |
| `ExtensionSet.gitHubWeb` emoji (`:smile:`) and `md.EmojiSyntax()` | Rendered | Rendered (`markdownXEmojiExtension` is enabled for them) | Implemented as an IR transform ([extensions.md](extensions.md#emoji-shortcodes)) |
| `ExtensionSet.gitHubWeb` color swatches | Rendered | Rendered as text. Header ids and alerts are supported | Not implemented |
| GitHub alerts (`> [!NOTE]`) | A plain blockquote | A dedicated alert (icon, color, title) under the default extension set. `alerts: false` gives the blockquote | Extra, on by default |
| `table` builder | The builder's result is replaced by flutter_markdown's own table | The builder's widget is used. `th` / `td` builders are called and their widget replaces the cell content (plus asserts here) | flutter_markdown discards it |
| `MarkdownWidget.build(context, children)` | `children` is flutter_markdown's `Wrap` / `Column` tree | `children` are this package's block widgets separated by `SizedBox(height: blockSpacing)`. A subclass that only lays them out works unchanged | Different internal tree |
| `MarkdownBody` structure | `Column` for several blocks, the block itself for one | Always a `Column` | Keeps block state when a stream grows from one block to two |
| Soft line breaks | A space (or `\n` with `softLineBreak: true`) | The same | Parity |
| Bullet builder call order | Called when the `li` closes (after nested lists) | Called when the item row is built (before the bullets of a nested list); the same calls | Internal order |
| Global block tag list | Every block tag of a `builders` key is appended to a global list forever | Block-ness is per widget | flutter_markdown leaks state |
| Syntax highlighting | None unless `syntaxHighlighter` is given | A lightweight built-in highlighter (colors from `MarkdownStyleSheet.codeSyntax`, set by the `fromTheme` factories) when `syntaxHighlighter` is null. A non-null `syntaxHighlighter` has flutter_markdown's exact semantics | Extra, on by default ([code-blocks.md](code-blocks.md)) |
| Superscript | `FontFeature.enable('sups')` | A raised, smaller `WidgetSpan` when `superscriptFontFeatureTag` is null | Works with fonts that lack `sups` |
| `MarkdownStyleSheet.copyWith` | Does not carry `tableScrollbarThumbVisibility` over | Carries it over | Bug fix |
| `MarkdownStyleSheet.merge` | Throws when a base `TextStyle` field is null | Treats it as the other value | Bug fix |
| `MarkdownBuilder`, `MarkdownBuilderDelegate` | Exported | Not exported (they need a full `package:markdown` AST, which this package never has). Use `MarkdownBody` / `Markdown`, or subclass `MarkdownWidget` | Different architecture |

Not changed, and worth knowing: `MarkdownStyleSheet` subclass instances are never equal to a plain sheet (as in flutter_markdown), which defeats the per-block cache for subclasses.

## 4. Porting what does not carry over

### Custom syntaxes

```dart
// Before: a package:markdown inline syntax
Markdown(
  data: text,
  inlineSyntaxes: [MentionSyntax()],
  builders: {'mention': MentionBuilder()},
);
```

`MentionSyntax` is reported once and the document renders without it. Port it to a `MarkdownXExtension`, which transforms the IR after parsing, so results are the same on every platform ([extensions.md](extensions.md)):

```dart
final mention = MarkdownXExtension(
  inlineSyntaxes: [
    MarkdownXInlineSyntax(
      pattern: RegExp(r'@(\w+)'),
      build: (match) => MdxCustomInline(
        'mention',
        attributes: {'user': match[1]!},
        children: [MdxText(match[0]!)],
      ),
    ),
  ],
);

Markdown(
  data: text,
  extensions: [mention], // keep it in a field and reuse it
  inlineBuilder: (context, inline, style, buildDefault) =>
      inline is MdxCustomInline && inline.type == 'mention'
      ? TextSpan(text: '@${inline.attributes['user']}', style: style)
      : null,
);
```

### Custom context menu

```dart
// Before
Markdown(data: text, selectable: true, contextMenuBuilder: myEditableTextBuilder);
// After: wrap the widget in your own SelectionArea instead
SelectionArea(
  contextMenuBuilder: (context, selectableRegionState) => myMenu(selectableRegionState),
  child: MarkdownBody(data: text),
);
```

### Reading the selection offsets

`onSelectionChanged` still reports the selected text. If you used the offsets of the original block, use your own `SelectionArea` and its `onSelectionChanged`, which receives `SelectedContent`.

### Local images

```dart
// Before: relative paths and file: URIs loaded implicitly
Markdown(data: text);

// After: opt in explicitly
Markdown(data: text, imageDirectory: '/path/to/docs/');
// or, for file: URIs
Markdown(
  data: text,
  imageResolver: (uri, image) => markdownXFileImageProvider(uri),
);
```

### Plain blockquotes and plain code

```dart
Markdown(data: text, alerts: false); // `> [!NOTE]` stays a blockquote

// A highlighter that returns the source as is gives flutter_markdown's plain code
class PlainHighlighter extends SyntaxHighlighter {
  PlainHighlighter(this.style);
  final TextStyle? style;

  @override
  TextSpan format(String source) => TextSpan(text: source, style: style);
}

Markdown(data: text, syntaxHighlighter: PlainHighlighter(sheet.code));
```

## 5. What you gain

See the [feature overview](../README.md#features) for streaming, lazy rendering,
navigation, and extensions.

## 6. Platform setup

The native binaries and WebAssembly parser are bundled with the package.
See the [parser guide](parser.md) and [Web setup](web-wasm.md#consumer-setup)
for initialization and direct parser calls.
