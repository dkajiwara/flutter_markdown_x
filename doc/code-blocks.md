# Code block rendering

This document covers the rendering of code blocks (fenced and indented) and inline code, the header (language name and copy button), and the built-in highlighter and themes.

## Header (language name and copy button)

By default no header is shown, which is the flutter_markdown look. Enable it with `MarkdownStyleSheet.codeBlockOptions` (an extra of this package; `MarkdownXCodeBlockOptions`).

```dart
MarkdownBody(
  data: markdown,
  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    codeBlockOptions: const MarkdownXCodeBlockOptions(
      showLanguage: true,
      showCopyButton: true,
    ),
  ),
);
```

| Option | Description |
| --- | --- |
| `showLanguage` | Shows the fence's language name (the first word of the info string) on the left of the header. Not shown for a code block without a language name |
| `showCopyButton` | Shows a button on the right of the header. Pressing it puts the whole code on the clipboard, and the icon changes to a check for `feedbackDuration` (default 2 seconds) |
| `copyTooltip` | String for the tooltip and the spoken label. If null, `MaterialLocalizations.copyButtonLabel` (the device language) |
| `copiedTooltip` | Tooltip after copying. Defaults to `Copied` |

- Like the code body, the header is always LTR, with the language name on the left and the button on the right. This does not change in RTL documents.
- The header is excluded from selection and copy (`SelectionContainer.disabled`). The string copied by selecting everything in a `SelectionArea` contains neither the language name nor the button text.
- The button is an `IconButton`, so it can be focused with Tab and pressed with Enter or Space. The tooltip is the spoken name.
- Even for a code block over 200 lines that is split across several `Text` widgets, the button copies the whole original code (including newlines at chunk boundaries, exactly as in the source).
- Horizontal scrolling applies to the code body only; the header does not move.

### Override priority

Evaluation order is `blockBuilder`, then `builders` (`pre` or `code`, flutter_markdown's `MarkdownElementBuilder`), then the default rendering (see [extensions.md](extensions.md)). A `pre` or `code` builder's widget replaces the scrolling code text only; the container (decoration, padding) and the header stay. A `blockBuilder` result replaces the whole block, header included. To change only the header's appearance, return your own widget from `blockBuilder` (`block is MdxCodeBlock`).

A flutter_markdown-style `code` builder works unchanged:

```dart
class CodeElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final language = element.attributes['class']?.substring('language-'.length);
    return Text(element.textContent, style: preferredStyle, key: ValueKey(language));
  }
}

MarkdownBody(data: markdown, builders: {'code': CodeElementBuilder()});
```

## Monospace font

The default fonts for code (inline code, code blocks, kbd) are as follows.

- `fontFamily`: `monospace`
- `fontFamilyFallback`: `Menlo`, `Consolas`, `Roboto Mono`, `Courier New`, `monospace`

On the web, some environments do not resolve a font named `monospace`, so each OS's monospace font is listed, with the generic `monospace` last. To change it, replace `MarkdownStyleSheet.code`. `test/style/code_font_test.dart` checks, on the VM and in Chrome (`sh tool/chrome_test.sh`), that a monospace family is included in the text styles of inline code and code blocks. Which font is actually used depends on the fonts installed in the browser and OS.

### Monospace on the web

Flutter's web build draws text with CanvasKit, which cannot use the fonts installed on the system, so `monospace`, `Menlo` and the other names above are not available there and code is drawn in a proportional font. The package does not ship a font. To get monospace on the web (and an identical look on every platform), bundle one in your app and set it in the style sheet. The example app does this with [JetBrains Mono](https://www.jetbrains.com/lp/mono/) (SIL OFL 1.1, license in `example/fonts/OFL.txt`):

```yaml
# pubspec.yaml
flutter:
  fonts:
    - family: JetBrainsMono
      fonts:
        - asset: fonts/JetBrainsMono-Regular.ttf
        - asset: fonts/JetBrainsMono-Bold.ttf
          weight: 700
```

```dart
final base = MarkdownStyleSheet.fromTheme(Theme.of(context));
final sheet = base.copyWith(
  code: base.code!.copyWith(
    fontFamily: 'JetBrainsMono',
    // A non-null fallback list keeps the default fallbacks above from being added.
    fontFamilyFallback: const ['monospace'],
  ),
);
```

`code` is used for inline code, code blocks, `<samp>`, `<tt>` and `<kbd>`, so one setting covers all of them. See `example/lib/main.dart`.

## Languages

The built-in highlighter (`highlightCode`) has no per-language grammar; it only distinguishes comments, strings, numbers, and keywords with regular expressions. Language names are case-insensitive.

| Languages | Names (aliases) |
| --- | --- |
| Dart | `dart` |
| JavaScript, TypeScript | `javascript`, `js`, `jsx`, `mjs`, `typescript`, `ts`, `tsx` |
| Java, Kotlin, Scala, C#, Swift, Go, Rust | `java`, `kotlin` / `kt`, `scala`, `csharp` / `cs` / `c#`, `swift`, `go` / `golang`, `rust` / `rs` |
| C, C++, Objective-C | `c` / `h`, `cpp` / `c++` / `cc` / `hpp`, `objc` / `objective-c` / `objectivec` |
| Python, Ruby, PHP, Perl, Lua, R | `python` / `py`, `ruby` / `rb`, `php`, `perl` / `pl`, `lua`, `r` |
| shell | `bash`, `sh`, `shell`, `zsh`, `powershell` / `pwsh` / `ps1`, `dockerfile` / `docker`, `makefile` / `make`, `cmake` |
| Config and data | `json`, `jsonc` / `json5`, `yaml` / `yml`, `toml`, `ini` / `conf` / `properties`, `graphql` / `gql`, `sql` |
| Markup and style | `html` / `htm` / `xhtml` / `vue`, `xml` / `svg` / `plist`, `css`, `scss` / `less` |
| Documents | `markdown` / `md`, `diff` / `patch` |

- For html and xml, tag names use the keyword color, attribute values the string color, and entity references the number color. For css, `#fff` and `4px` use the number color.
- For diff, added lines use the string color, removed lines the keyword color, and heading lines such as `@@` the comment color. For markdown, headings, fences, and emphasis use the keyword color, and inline code uses the string color.
- Unsupported languages get no coloring and are shown as a plain `Text`.
- For stricter coloring, pass a `syntaxHighlighter:` (flutter_markdown's `SyntaxHighlighter`, `TextSpan format(String source)`). When it is non-null the built-in highlighter is not used and flutter_markdown's semantics apply (one trailing newline is removed and the span is drawn as is). The interface has no language argument; a language-aware replacement goes through `builders['pre']` / `builders['code']` (the `class="language-x"` attribute) or `blockBuilder` (`MdxCodeBlock.language`). `highlightCode(code, language)` (token list, `MdxCodeToken`) is exported if you want to reuse the built-in tokenizer.
- With the constructor `MarkdownStyleSheet(...)` and no `codeSyntax`, code is not highlighted (flutter_markdown's plain look). `copyWith` cannot set a field back to null, so to turn highlighting off on a `fromTheme` sheet pass a `syntaxHighlighter` that returns `TextSpan(text: source, style: sheet.code)`.

### Performance

The regular expressions are written so that an unclosed comment or string stops at the end of the line, and even a very long single line is scanned in linear time. `test/style/highlighter_languages_test.dart` processes pathological inputs of about 100,000 characters (runs of quotes, `/*`, `<!--`, and so on) for each major language, and checks that the original is reproduced and that processing finishes within 2 seconds. For how code blocks over 200 lines are split into `Text` widgets, and for measurements on macOS, see `doc/performance.md`.

## Themes

Pick the color scheme with `MarkdownStyleSheet.codeSyntax` (`MarkdownXSyntaxColors`). By default, `fromTheme`, `fromCupertinoTheme`, and `largeFromTheme` choose `light` or `dark` (GitHub-like) from the `Theme` brightness.

| Name | Constant | Background and text color |
| --- | --- | --- |
| `github-light` | `MarkdownXSyntaxColors.light` | Not specified (`codeblockDecoration` and `code` of the sheet) |
| `github-dark` | `MarkdownXSyntaxColors.dark` | Not specified |
| `monokai` | `MarkdownXSyntaxColors.monokai` | Specified |
| `solarized-light` | `MarkdownXSyntaxColors.solarizedLight` | Specified |
| `solarized-dark` | `MarkdownXSyntaxColors.solarizedDark` | Specified |

```dart
MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
  codeSyntax: MarkdownXSyntaxColors.themes['monokai'],
);
```

A theme with `background` and `foreground` also overrides the code block's background and text color (the inline code background stays that of `code`). Build your own color scheme with `MarkdownXSyntaxColors(keyword:, string:, comment:, number:, background:, foreground:)`.

## Limitations

- There are four token kinds: keyword, string, comment, and number. Type names and function names are not colored.
- Only the first word of the fence's info string is used as the language name. A title such as in `dart title="a.dart"` is not shown in the header. The rest of the info string (`title="a.dart"`) is kept in `MdxCodeBlock.info` (IR version 3) for builders.
- The header's appearance (padding, colors, icons) cannot be changed. To change it, use `blockBuilder`.
