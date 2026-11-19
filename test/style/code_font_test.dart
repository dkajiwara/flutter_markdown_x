import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// Runs on both the VM and Chrome (`flutter test --platform chrome`).

bool _isMonospace(TextStyle? style) {
  if (style == null) return false;
  final families = [?style.fontFamily, ...?style.fontFamilyFallback];
  return families.contains('monospace');
}

/// The theme with localized text sizes, as `MaterialApp` provides.
ThemeData _localized(ThemeData theme) =>
    ThemeData.localize(theme, Typography.englishLike2021);

void main() {
  test('the code font has a fallback that stays monospace on the Web too', () {
    final code = MarkdownStyleSheet.fromTheme(_localized(ThemeData())).code!;
    expect(code.fontFamily, 'monospace');
    // The sheet has no fallback of its own; the renderer adds this one (checked below).
    expect(code.fontFamilyFallback, isNull);
    expect(
      MarkdownXDefaults.codeFontFamilyFallback,
      containsAll(['Menlo', 'Consolas', 'Roboto Mono', 'Courier New']),
    );
    expect(MarkdownXDefaults.codeFontFamilyFallback.last, 'monospace');
  });

  testWidgets('code block and inline code text have a monospace family', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownBody(data: 'inline `code` here\n\n```\nblock\n```'),
        ),
      ),
    );
    final texts = tester.widgetList<RichText>(find.byType(RichText)).toList();
    final inline = texts.firstWhere(
      (w) => w.text.toPlainText().contains('inline'),
    );
    var found = false;
    List<String>? foundFallback;
    void walk(InlineSpan span) {
      if (span is TextSpan && _isMonospace(span.style)) {
        if (span.toPlainText() == 'code') {
          found = true;
          foundFallback = span.style?.fontFamilyFallback;
        }
      }
      span.visitDirectChildren((child) {
        walk(child);
        return true;
      });
    }

    walk(inline.text);
    expect(found, isTrue, reason: 'inline code');
    expect(foundFallback, MarkdownXDefaults.codeFontFamilyFallback);
    final block = texts.firstWhere((w) => w.text.toPlainText() == 'block');
    expect(_isMonospace(block.text.style), isTrue, reason: 'code block');
  });
}
