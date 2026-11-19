# Mermaid (optional extension)

Fenced code blocks whose language is `mermaid` can be drawn as diagrams. The core `flutter_markdown_x` does not depend on any Mermaid rendering library and does not draw diagrams itself. It detects the blocks, and the app plugs in a renderer. Without a renderer, a Mermaid fence is shown exactly like any other code block.

Mermaid has no flutter_markdown equivalent; it is an extra of this package, modeled on [math.md](math.md).

## Summary

- The entry point is `package:flutter_markdown_x/mermaid.dart`. The core (`flutter_markdown_x.dart`) does not import it, so apps that do not use Mermaid are unaffected
- A fence with the language `mermaid` (case-insensitive, ```` ``` ```` or `~~~`, also inside quotes and lists; an info string such as ```` ```mermaid title ```` is allowed) becomes an `MdxCustomBlock('mermaid')` with the attribute `source` (the diagram text). The original code block is kept as its content, which is what is shown when there is no builder
- Rendering is done by a `MarkdownXMermaidBuilder` that the app passes
- While the fence is still open during streaming, the builder is not called; the code block is shown until the fence closes
- If the builder throws, the code block is shown and the error is reported once
- Selection and copy give the Mermaid source

## Usage

```dart
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_markdown_x/mermaid.dart';

// Keep it in a field or top-level and reuse it (creating it on every build re-parses every time).
final mermaid = MarkdownXMermaid(
  builder: (context, source) => MyDiagram(source),
);

Markdown(
  data: text,
  streaming: true, // for text that is still being generated
  extensions: [mermaid.extension],
  blockBuilder: mermaid.blockBuilder,
);
```

- `MarkdownXMermaid()` without a builder also works: Mermaid fences are shown as normal code blocks (same code header options, highlighting, selection, and `builders` bridging as any code block)
- `mermaid.blockBuilder` returns null for blocks that are not Mermaid diagrams, so compose it by calling it first and then your own `blockBuilder`
- `markdownXMermaidExtension` is the shared extension instance. Passing only `extensions: [markdownXMermaidExtension]` detects the blocks and shows the code blocks

### Builder contract

```dart
typedef MarkdownXMermaidBuilder = Widget Function(BuildContext context, String source);
```

- `source`: the text between the fence lines, without the trailing line break. The info string (`title` in ```` ```mermaid title ````) is not passed; it stays on the fallback code block
- The returned widget is placed as is. Size and scrolling are up to the widget (wrap it in `SingleChildScrollView` or `FittedBox` if diagrams can be wide)
- The builder is not called again for unchanged diagrams when text is appended after them (blocks are cached by value)

## Streaming

With `streaming: true`, a fence that is still open at the tail of the text is shown as a code block, and the builder is not called, because a half-written diagram is usually a syntax error and re-rendering on every token is expensive. When the closing fence arrives, the block switches to the builder once. A fence that is never closed (the stream ended) is drawn once the app turns `streaming` off.

How it works: the source transform of the extension (which receives the `streaming` flag, like math) finds a Mermaid fence still open at the end of the last chunk and adds a private marker word to its info string. The block transform removes the marker and sets `pending: true` on the custom block. Completed chunks are never touched, so the incremental parse cache is unaffected.

To draw partial diagrams anyway, use `MarkdownXMermaid(whileStreaming: true, builder: ...)`. The builder then also receives the source of a fence that is still open. This uses a different extension instance (`mermaid.extension`), so always pass `mermaid.extension` rather than `markdownXMermaidExtension`.

## Errors

If the builder function throws, the fallback code block is shown and the exception is reported once per diagram source with `FlutterError.reportError` (library `flutter_markdown_x`). The document keeps rendering. Only an exception thrown by the builder function itself is caught; one thrown later while the returned widget builds is handled by Flutter as usual (use the rendering library's own error handling, such as an `errorBuilder`).

## Precedence with flutter_markdown builders

- Without the extension, nothing changes: `builders['code']` sees `code` with `class="language-mermaid"` as for any language
- With the extension but no `MarkdownXMermaid.builder` (or while a fence is pending, or after a builder error), the fallback is an ordinary code block: `builders['pre']` / `builders['code']` run for it as before
- With a builder, the Mermaid builder wins for Mermaid blocks. `builders['code']` and `builders['pre']` still apply to all other code blocks. Because `builders` are bridged per top-level block, a `code` builder may still be invoked for the Mermaid block's code, but its widget is discarded
- The custom block is also visible to `builders` as the tag `mermaid` (attribute `source`)
- `blockBuilder` is evaluated before `builders`, so your own `blockBuilder` decides the order when you compose it with `mermaid.blockBuilder`

## Selection and accessibility

- Inside a `SelectionArea`, a rendered diagram is excluded from selection and a transparent copy of the source is overlaid, so selecting and copying yields the Mermaid source (without the fence lines). Outside a `SelectionArea` nothing is added
- The diagram has the semantics label `Mermaid diagram` (change it with `semanticLabel`). The source is not read aloud; a diagram widget that provides its own semantics keeps them (the label is not an `excludeSemantics` wrapper)
- The fallback code block behaves like any code block (header, copy button, selection)

## Example: connecting mermaid_flutter

This is an example of plugging a third-party renderer in, not a dependency of this package. flutter_markdown_x does not depend on `mermaid_flutter`, and this package does not guarantee its rendering quality, diagram type coverage, or performance. Add it to the app's `pubspec.yaml` yourself (`mermaid_flutter: 0.3.2`) and check its documentation for its current API.

The `example/` app uses it (see `example/lib/external_libs.dart`), and the code below is compiled and run there (widget tests, iOS simulator, web build).

```dart
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_markdown_x/mermaid.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

final mermaid = MarkdownXMermaid(
  builder: (context, source) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: MermaidDiagram(
      source: source,
      // Follow the app's light or dark theme. MaterialMermaidTheme.fromTheme
      // takes a ThemeData of the SDK Material library, not material_ui's, so
      // pick the Mermaid theme by brightness (add mermaid_core to your pubspec).
      theme: Theme.of(context).brightness == Brightness.dark
          ? core.MermaidTheme.darkTheme
          : core.MermaidTheme.defaultTheme,
      errorBuilder: (context, error) => Text(
        'Diagram error: $error',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ),
  ),
);

class Chat extends StatelessWidget {
  const Chat({super.key, required this.text, required this.streaming});

  final String text;
  final bool streaming;

  @override
  Widget build(BuildContext context) => MarkdownBody(
    data: text,
    streaming: streaming,
    extensions: [mermaid.extension],
    blockBuilder: mermaid.blockBuilder,
  );
}
```

Observed on an iOS simulator with `mermaid_flutter` 0.3.2: the small flowchart is laid out cleanly (boxes, a diamond, labeled edges, a back edge), and the diagram is left-aligned at its natural size. Without a `theme` it is drawn with Mermaid's default light colors on a white background, which stands out on a dark theme; `MaterialMermaidTheme.fromTheme(Theme.of(context))` (used above and in the example app) maps the diagram colors and text to the app's Material theme, so it matches in both brightness modes.

`MermaidDiagram` sizes itself to the diagram; the package also has `MermaidView` (pan and zoom, which needs a bounded height). Syntax errors are the renderer's concern (see its `errorBuilder`); an exception thrown directly by the builder falls back to the code block as described above.

## Limitations

- Only fenced code blocks are detected. Indented code and `<pre class="mermaid">` HTML are not
- Only the language word `mermaid` matches (`{.mermaid}` or `mermaid{...}` forms do not)
- The Mermaid source is not validated here; whether it is valid is up to the renderer
- With `applyMarkdownXExtensions` outside a widget, run `applyMarkdownXSourceTransforms` first (with `streaming: true` for a stream) as for math
