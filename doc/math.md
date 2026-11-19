# Math (optional extension)

Inline math (`$x^2$`, `\(x^2\)`) and block math (`$$ ... $$`, `\[ ... \]`) are provided as an optional extension. The core `flutter_markdown_x` does not depend on any math rendering library. Only apps that use it import `package:flutter_markdown_x/math.dart` and pass their own rendering widget, such as one from `flutter_math_fork`.

Math has no flutter_markdown equivalent; it is an extra of this package. It works together with flutter_markdown-style `builders`, which see a math node as an element with the tag `math` (attributes `tex` and `display`).

## Summary

- The entry point is `package:flutter_markdown_x/math.dart`. The core (`flutter_markdown_x.dart`) does not import this file, so apps that do not use math are unaffected in dependencies and build
- Rendering is done by a `MarkdownXMathBuilder` that the app passes. If it is not passed, the original TeX is shown in a monospace font
- The approach is "move math into a code span before parsing, and turn it back into an IR math node after parsing" (see below; transforming the IR after parsing alone would corrupt the TeX)
- Currency (`$5 and $10`) is distinguished with pandoc's rules
- Selection and copy give the original TeX with delimiters, and the semantics label is the original TeX
- During streaming, an unclosed `$$`, `\[`, or `\(` hides the delimiters and shows the TeX in monospace. A lone `$` stays as text

## Usage

```dart
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_markdown_x/math.dart';

// Keep it in a field or top-level and reuse it (creating it on every build re-parses every time).
final math = MarkdownXMath(
  builder: (context, tex, {required display, required style}) => Text(tex, style: style),
);

Markdown(
  data: text,
  extensions: [math.extension],
  inlineBuilder: math.inlineBuilder,
  blockBuilder: math.blockBuilder,
);
```

- `MarkdownXMath()` (without a builder) also works. Math is shown as the original TeX (with delimiters) in monospace. Block math scrolls horizontally
- Passing only `extensions: [markdownXMathExtension]` still detects math and shows the original in monospace (scrolling and selection formatting are features available when `blockBuilder` is passed)
- When you have your own `inlineBuilder` and `blockBuilder`, call `math.inlineBuilder` first and proceed to your own handling if it returns null. It returns null for inlines and blocks that are not math
- `MarkdownXMath(dollar: false)` stops `$...$` and `$$...$$` from becoming math, and `MarkdownXMath(bracket: false)` stops `\(...\)` and `\[...\]` from becoming math. `\[` and `\(` are also symbol escapes in CommonMark, so for documents that write escaped square brackets such as `\[note\]`, use `bracket: false`

### Builder contract

```dart
typedef MarkdownXMathBuilder = Widget Function(
  BuildContext context,
  String tex, {
  required bool display,
  required TextStyle style,
});
```

- `tex`: the TeX without delimiters. Leading and trailing whitespace is removed. Newlines in multi-line math are kept
- `display`: whether it is math on its own line (`$$`, `\[`). A `$$x$$` in the middle of a paragraph is also true (and is still drawn as inline in that case)
- `style`: the text style actually applied at that position (inside a heading, the heading size). `fontSize` is the value before the text scale is applied
- Do not throw an exception on syntax errors. Use the library's onError and fallback features
- The builder is not called for math that is still being written (pending, below)

### Example: connecting flutter_math_fork

The core does not depend on `flutter_math_fork`. Add it to the app's `pubspec.yaml` yourself. The `example/` app does exactly this (version 0.7.4) in `example/lib/external_libs.dart`, and the code below is that code.

```yaml
dependencies:
  flutter_markdown_x: ^…
  flutter_math_fork: 0.7.4
```

```dart
import 'package:flutter_markdown_x/math.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:material_ui/material_ui.dart';

final math = MarkdownXMath(
  builder: (context, tex, {required display, required style}) => Math.tex(
    tex,
    mathStyle: display ? MathStyle.display : MathStyle.text,
    textStyle: style,
    // On a syntax error, show the original in red (do not throw).
    onErrorFallback: (error) =>
        Text(tex, style: style.copyWith(color: Colors.red)),
  ),
);
```

`Math.tex` applies the `MediaQuery` text scaler itself, so passing `style` as-is gives scaling. When you return a widget that does not scale, such as a `CustomPaint`, multiply by `MediaQuery.textScalerOf(context).scale(style.fontSize!)` yourself. This was compiled and run in the example app (iOS simulator and widget tests), where inline and block formulas render with flutter_math_fork's own fonts.

## Syntax

| Kind | Notation | Notes |
|---|---|---|
| inline | `$x^2$` | See below for distinguishing from currency. Can span line breaks within a paragraph |
| inline | `\(x^2\)` | No whitespace rules |
| block | `$$ ... $$` | When it is the whole of a paragraph. May be multi-line |
| block | `\[ ... \]` | Same as above |
| inline (display) | `$$x$$` in the middle of a sentence | Drawn as an inline with `display: true` |

- It can also be used inside headings, table cells, lists, quotes, the summary and body of `details`, and the text of emphasis and links
- Block math is still a block inside list items and quotes (`- $$x$$`, `> $$x$$`)
- Math spanning a blank line is not created (if there is a blank line between `$$` and `$$`, it is not math)
- For adjacent math (`$a$$b$`, `\(a\)\(b\)`), only the first becomes math. The second stays as text. If you put whitespace between them, both become math
- Math next to a backtick (`` `$x$ ``, `` $x$` ``) is not treated as math
- Inside inline code, code blocks, fences, indented code blocks, link destinations, image alt text, autolinks, URLs, inline HTML attributes, and reference definitions, text is not treated as math
- Write a `$` inside math as `\$`. A `\$` outside math becomes a literal `$`

## Distinguishing from currency symbols

`$...$` follows pandoc's rules.

1. The character right after the opening `$` is not whitespace
2. The first (unescaped) `$` after the opening `$` is the closing candidate. It is math only when the character right before the candidate is not whitespace and the character right after is not a digit
3. If the candidate does not satisfy the conditions, the opening `$` stays as text (later `$` are not searched)
4. It does not cross blank lines

| Input | Result |
|---|---|
| `$5 and $10` | Not math (whitespace right before the closing `$`) |
| `costs $5.` / `US$10` / `US$10 to US$20` | Not math |
| `$ x $` / `$x $` / `$ x$` | Not math |
| `$` / `$$` / `$$ $$` | Not math |
| `\$x\$` | Literal `$x$` |
| `$x$` / `$2^n$` / `$5$` | Math |
| `It costs $5 and $x$ is a var` | Only `$x$` is math |
| `$a$1` | Not math, because a digit follows the closing `$` |
| `とても$x$です` | Math (surrounded by Japanese text, with no spaces) |

`$$...$$`, `\(...\)`, and `\[...\]` have no whitespace rules (they are not math only when the content is empty).

### Limitations

Pandoc's rules cannot separate currency from math perfectly. Inputs like the following are mistaken for math.

- Cases such as `価格は$5です。$x$`, where the `$` after the amount satisfies the closing conditions as the opening of the next math (`5です。` becomes math). In documents where this misidentification matters, write the currency `$` as `\$`
- Math whose content starts with a digit right after the `$` (`$2x$`) cannot be distinguished from currency and becomes math if the conditions are satisfied

## Approach: escape before parsing

The extension protects TeX in temporary code spans before Markdown parsing and
restores it as math nodes afterward. This preserves backslashes, emphasis
characters, HTML-like text, and line breaks. The transform runs per chunk
because math cannot cross blank lines. The cache still keys on the original
source. See [Source transforms](extensions.md#source-transform-transformsource)
for the extension API.

## IR

```dart
MdxCustomInline('math', attributes: {
  'tex': r'x^2',
  'display': 'false',          // 'true' means display
  'raw': r'$x^2$',             // the original, with the delimiters as written
  // 'pending': 'true',        // only while being written during streaming
}, children: [MdxStyled(code, [MdxText(r'$x^2$')])]);

MdxCustomBlock('math', attributes: {...same...}, inlines: [...]);
```

- `children` and `inlines` are the display used when there is no builder (the original with delimiters, as code)
- A paragraph with exactly one math expression whose `display` is `'true'` becomes an `MdxCustomBlock`. Otherwise it stays inline
- Combining `applyMarkdownXSourceTransforms(source, [markdownXMathExtension])` with `applyMarkdownXExtensions` gives the same IR without using a widget

## Streaming

With `streaming: true`, unclosed math in the last block is displayed as follows ([streaming.md](streaming.md)).

| State at the end | Display |
|---|---|
| Unclosed `$x_1 + y` (a single `$`) | Stays as text, because it cannot be distinguished from currency. The appearance changes at the moment it closes and becomes math |
| Unclosed `$$ ...`, `\[ ...` | A block (`pending`) that hides the delimiters and shows the TeX being written in monospace. The builder is not called (partial TeX would be a syntax error) |
| Unclosed `\( ...` | An inline of the same kind |
| Closed math | Drawn by the builder |

- The escape is done before the tail repair (`markdownXRepairStreamingTail`). This is so that `_` and `*` in TeX are not misread as unclosed emphasis and completed
- When the result of the repair takes the form of math (for example, hiding an unclosed backtick after `$x$`), it is escaped again
- Before a single-`$` math expression closes, a `*` inside it can briefly look like emphasis (the `*` in `$a*b` is unclosed emphasis, so it can be a target of the repair). Once it closes, the display is correct as math
- With `streaming: false`, nothing happens to unclosed math (it stays as text)

## Selection, copy, semantics, and scale

- **Copy**: inside a `SelectionArea`, math becomes the original TeX with the delimiters as written (`$x_1$`, `\(x\)`, `$$a$$`, `\[a\]`). Block math is separated from other blocks by newlines ([accessibility.md](accessibility.md)). The builder's widget is excluded from selection, and transparent original text stretched to the same size is overlaid to handle selection highlighting and copy. Nothing is overlaid outside a `SelectionArea`
- **semantics**: the label is the original TeX (without delimiters). The content of the builder's widget is not read. Inline math is joined with the surrounding text into the label of a single paragraph (`text x^2 text`). Block math becomes an independent label
- **scale**: the `style.fontSize` passed to the builder is the size of the surrounding text (the value before the text scale is applied). `Text` and `Math.tex` apply the `MediaQuery` text scaler themselves, so passing `style` scales them, without double scaling. If you return a widget that does not scale, multiply it yourself
- **Width**: block math scrolls horizontally when it exceeds the width (`SingleChildScrollView`). When there is room to spare, it is centered. Inline math does not wrap (a long inline math expression can exceed the line width)

## Limitations

- The escaping is an approximate scan over the source string. It does not reproduce CommonMark's full context (the exact boundaries of code blocks inside lists, the inside of HTML blocks, and so on). If an escaped expression ends up in a code block, the transform restores the original text
- `$x$` inside an HTML block (`<div>`, `<p>`, and so on) is handled by turning an escape left in the text back into math, because the parser does not interpret inlines there. Inside HTML attributes (`<span title="$x$">`) is not transformed
- Reference definition lines (`[ref]: …`) are not searched for math
- For multi-line math inside a quote, only continuation lines that have a `>` have it removed. The indentation of continuation lines of a list item remains as whitespace inside the TeX (which has no meaning in TeX)
- A document that uses `\(` and `\[` as CommonMark escapes should use `bracket: false`. A sentence in square brackets enclosed with `\[` and `\]` becomes math
- Misdetection of the currency `$` is as described in the limitations above
- Rendering quality (the supported TeX range and fonts) depends on the rendering library the app chooses

## Tests

[The math tests](../test/extensions/math_test.dart) cover delimiter detection,
currency, TeX preservation, streaming, and rendering.
