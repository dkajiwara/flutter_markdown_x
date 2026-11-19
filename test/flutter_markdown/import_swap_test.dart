// The code of flutter_markdown's README and API docs, with only the import changed
// (doc/flutter_markdown_compat.md, section 6.1). The test passes when it compiles without errors
// and renders without exceptions.
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';

const _doc = '''
# Title

Text with *em*, **strong**, `code`, [a link](https://example.com "t") and an image
![alt](a.png#20x20 "title").

- [x] done
- [ ] todo
- plain

3. three
4. four

```dart
void main() {}
```

> quote

| a | b |
|:--|--:|
| 1 | 2 |

---
''';

// The custom code builder of the flutter_markdown README.
class CodeElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    var language = '';
    if (element.attributes['class'] != null) {
      final lg = element.attributes['class'] as String;
      language = lg.substring(9);
    }
    return Text(
      element.textContent,
      key: ValueKey('code-$language'),
      style: preferredStyle,
    );
  }
}

class ImgPadding extends MarkdownPaddingBuilder {
  @override
  EdgeInsets getPadding() => const EdgeInsets.all(4);
}

class ParagraphPadding extends MarkdownPaddingBuilder {
  @override
  EdgeInsets getPadding() => const EdgeInsets.only(bottom: 2);
}

class DartHighlighter extends SyntaxHighlighter {
  @override
  TextSpan format(String source) => TextSpan(
    text: source,
    style: const TextStyle(color: Colors.teal),
  );
}

// A user subclass of MarkdownWidget (flutter_markdown's documented extension point).
class CustomMarkdown extends MarkdownWidget {
  const CustomMarkdown({super.key, required super.data});

  @override
  Widget build(BuildContext context, List<Widget>? children) =>
      Column(key: const ValueKey('custom-build'), children: children!);
}

ThemeData _theme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold)));

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('Markdown with every parameter of the flutter_markdown docs', (
    tester,
  ) async {
    // Markdown builds its blocks lazily, so give it room for the whole document.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const SizedBox()));
    final theme = _theme(tester);
    final links = <String>[];
    final selections = <String?>[];
    await tester.pumpWidget(
      _app(
        Markdown(
          data: _doc,
          selectable: true,
          styleSheet: MarkdownStyleSheet.fromTheme(theme)
              .copyWith(blockSpacing: 12, p: const TextStyle(fontSize: 15)),
          styleSheetTheme: MarkdownStyleSheetBaseTheme.material,
          syntaxHighlighter: DartHighlighter(),
          onSelectionChanged: (text, selection, cause) => selections.add(text),
          onTapLink: (text, href, title) => links.add('$text|$href|$title'),
          onTapText: () {},
          contextMenuBuilder: null,
          imageDirectory: 'assets/',
          blockSyntaxes: const [],
          inlineSyntaxes: [
            // ignore: deprecated_member_use
            TaskListSyntax(),
          ],
          extensionSet: md.ExtensionSet.gitHubFlavored,
          checkboxBuilder: (checked) =>
              Icon(checked ? Icons.check : Icons.close),
          bulletBuilder: (parameters) => Text(
            '${parameters.index}${parameters.style.name}${parameters.nestLevel}',
          ),
          builders: {'code': CodeElementBuilder()},
          paddingBuilders: {'img': ImgPadding(), 'p': ParagraphPadding()},
          listItemCrossAxisAlignment:
              MarkdownListItemCrossAxisAlignment.baseline,
          padding: const EdgeInsets.all(8),
          controller: ScrollController(),
          physics: const ClampingScrollPhysics(),
          shrinkWrap: false,
          fitContent: true,
          softLineBreak: true,
          sizedImageBuilder: (config) => SizedBox(
            width: config.width,
            height: config.height,
            child: Text('${config.alt}'),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('code-dart')), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('alt'), findsOneWidget);
    await tester.tapOnText(find.textRange.ofSubstring('a link'));
    expect(links, ['a link|https://example.com|t']);
  });

  testWidgets('MarkdownBody with the deprecated imageBuilder', (tester) async {
    final calls = <Uri>[];
    await tester.pumpWidget(
      _app(
        MarkdownBody(
          data: _doc,
          // ignore: deprecated_member_use
          imageBuilder: (uri, title, alt) {
            calls.add(uri);
            return Text('img:$alt');
          },
          shrinkWrap: true,
        ),
      ),
    );
    expect(calls.single.toString(), 'a.png');
    expect(find.text('img:alt'), findsOneWidget);
  });

  testWidgets('the classic custom code builder renders the code', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        MarkdownBody(
          data: '```dart\nprint(1);\n```\n\nand `inline`\n',
          builders: {'code': CodeElementBuilder()},
        ),
      ),
    );
    expect(find.byKey(const ValueKey('code-dart')), findsOneWidget);
    expect(find.text('print(1);\n'), findsOneWidget);
    // The same builder is called for inline code, without a class attribute. Its Text joins the
    // surrounding text run, as in flutter_markdown, so the key does not survive.
    expect(find.textContaining('inline', findRichText: true), findsOneWidget);
  });

  testWidgets('style sheet factories, copyWith, merge and styles', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const SizedBox()));
    final theme = _theme(tester);
    final sheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      h1: const TextStyle(fontSize: 30),
      a: const TextStyle(color: Colors.red),
      blockquoteDecoration: const BoxDecoration(color: Colors.grey),
      codeblockPadding: const EdgeInsets.all(3),
      listIndent: 20,
      textScaler: const TextScaler.linear(1.1),
    );
    final merged = MarkdownStyleSheet.fromTheme(theme).merge(sheet);
    expect(merged.styles['a']?.color, Colors.red);
    expect(
      MarkdownStyleSheet.fromCupertinoTheme(const CupertinoThemeData()).h1,
      isNotNull,
    );
    expect(
      MarkdownStyleSheet.largeFromTheme(theme).h1!.fontSize,
      greaterThan(0),
    );
    await tester.pumpWidget(
      _app(
        MarkdownBody(
          data: _doc,
          styleSheet: sheet,
          styleSheetTheme: MarkdownStyleSheetBaseTheme.cupertino,
        ),
      ),
    );
    expect(find.text('Title'), findsOneWidget);
  });

  testWidgets('a MarkdownWidget subclass overrides build', (tester) async {
    await tester.pumpWidget(_app(const CustomMarkdown(data: _doc)));
    expect(find.byKey(const ValueKey('custom-build')), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
  });

  testWidgets('extensionSet values and noScroll', (tester) async {
    for (final set in [
      md.ExtensionSet.none,
      md.ExtensionSet.commonMark,
      md.ExtensionSet.gitHubFlavored,
      md.ExtensionSet.gitHubWeb,
    ]) {
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: Markdown(data: _doc, extensionSet: set, noScroll: true),
          ),
        ),
      );
      expect(find.text('Title'), findsOneWidget);
    }
  });
}
