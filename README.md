# flutter_markdown_x

Render Markdown as Flutter widgets, with streaming support for generated text
and lazy rendering for long documents. The bundled Rust parser runs on Android,
iOS, Linux, macOS, Windows, and Web. Apps can use it without installing Rust.

[Live demo](https://dkajiwara.github.io/flutter_markdown_x/) ·
[Example app](example/) · [Changelog](CHANGELOG.md)

## Getting started

Requires Flutter 3.50.0 and Dart 3.14.0 or later. The example uses
[`material_ui`](https://pub.dev/packages/material_ui), whose theme the Markdown
widgets follow.

```sh
flutter pub add flutter_markdown_x material_ui
```

```dart
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  runApp(const MaterialApp(
    home: Scaffold(
      body: Markdown(data: '# Hello\n\nThis is **Markdown**.'),
    ),
  ));
}
```

Use `Markdown` for a scrollable document, `MarkdownBody` inside an existing
scroll view or chat bubble, and `SliverMarkdown` inside a `CustomScrollView`.
Set `streaming: true` while appending generated text.

Migrating from `flutter_markdown` or `flutter_markdown_plus`? The
[migration guide](doc/migration.md) covers the shared widget API, theme setup,
and differences such as custom syntax and raw HTML.

## Features

- [CommonMark and GFM syntax](doc/syntax.md), including tables, footnotes, and task lists.
- [Supported HTML](doc/html.md), including collapsible details and tables with row and column spans.
- [Streaming and incremental parsing](doc/streaming.md), with [performance measurements](doc/performance.md).
- [Heading links and table of contents](doc/navigation.md), plus [selection, accessibility, and RTL](doc/accessibility.md).
- [Code highlighting](doc/code-blocks.md) and [custom image loading](doc/images.md).
- [Custom builders and syntax extensions](doc/extensions.md), plus [alerts and citations](doc/alerts-and-citations.md), [math](doc/math.md), and [Mermaid](doc/mermaid.md).

See the [compatibility reference](doc/flutter_markdown_compat.md) for API details,
[conformance results](doc/conformance.md) for specification coverage, and the
[parser guide](doc/parser.md) for platform setup and diagnostics.

## Contributing

Issues and pull requests are welcome. For rendering bugs, include the Markdown
input, expected output, platform, and Flutter version.

Run `flutter analyze` and `flutter test` from the repository root. See the
[native build guide](doc/native-abi.md#rebuild-procedure) for changes to the Rust
parser.

## License

[MIT](LICENSE). The license file also contains notices for bundled dependencies.
