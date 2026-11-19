# flutter_markdown_x_example

An app that shows `flutter_markdown_x` through the same API as `flutter_markdown`:

* **Static** tab: `Markdown` with `MarkdownStyleSheet.fromTheme(...).copyWith(...)`, `onTapLink(text, href, title)`, `imageDirectory`, and the extras of this package (a code block header, citations, `onTapImage`) over `lib/sample.dart`.
* **Streaming** tab: the same document appended a few characters at a time with `streaming: true`, like an LLM response.

```sh
flutter run            # pick a device
flutter run -d chrome  # web (the WebAssembly parser is loaded as a package asset)
```
