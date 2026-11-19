import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Color? _keywordColor(WidgetTester tester) {
  Color? color;
  for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
    w.text.visitChildren((span) {
      if (span is TextSpan && span.text == 'final') color = span.style?.color;
      return true;
    });
  }
  return color;
}

Widget _app(
  MarkdownStyleSheet? styleSheet, {
  Brightness brightness = Brightness.light,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Scaffold(
      body: MarkdownBody(
        data: '```dart\nfinal a = 1;\n```',
        styleSheet: styleSheet,
      ),
    ),
  );
}

/// The theme with localized text sizes, as `MaterialApp` provides.
ThemeData _localized(ThemeData theme) =>
    ThemeData.localize(theme, Typography.englishLike2021);

void main() {
  test('the built-in themes are all present', () {
    expect(
      MarkdownXSyntaxColors.themes.keys,
      containsAll([
        'github-light',
        'github-dark',
        'monokai',
        'solarized-light',
        'solarized-dark',
      ]),
    );
    expect(
      MarkdownXSyntaxColors.themes['github-light'],
      MarkdownXSyntaxColors.light,
    );
    expect(MarkdownXSyntaxColors.monokai.background, isNotNull);
    expect(MarkdownXSyntaxColors.light.background, isNull);
  });

  test('fromTheme picks the default theme from brightness', () {
    expect(
      MarkdownStyleSheet.fromTheme(
        _localized(ThemeData(brightness: Brightness.dark)),
      ).codeSyntax,
      MarkdownXSyntaxColors.dark,
    );
    expect(
      MarkdownStyleSheet.fromTheme(_localized(ThemeData())).codeSyntax,
      MarkdownXSyntaxColors.light,
    );
  });

  testWidgets(
    'choosing a theme via style.syntax changes the keyword color and background',
    (tester) async {
      await tester.pumpWidget(_app(null));
      expect(_keywordColor(tester), MarkdownXSyntaxColors.light.keyword);
      await tester.pumpWidget(_app(null, brightness: Brightness.dark));
      await tester.pumpAndSettle();
      expect(_keywordColor(tester), MarkdownXSyntaxColors.dark.keyword);
      final style = MarkdownStyleSheet.fromTheme(_localized(ThemeData()))
          .copyWith(codeSyntax: MarkdownXSyntaxColors.monokai);
      await tester.pumpWidget(_app(style));
      expect(_keywordColor(tester), MarkdownXSyntaxColors.monokai.keyword);
      final box = tester.widget<Container>(
        find
            .ancestor(
              of: find.byType(RichText),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (box.decoration! as BoxDecoration).color,
        MarkdownXSyntaxColors.monokai.background,
      );
    },
  );
}
