import 'package:flutter/services.dart';
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/selection_harness.dart';

/// The theme with localized text sizes, as `MaterialApp` provides.
ThemeData _localized(ThemeData theme) =>
    ThemeData.localize(theme, Typography.englishLike2021);

MarkdownStyleSheet _style({
  bool language = true,
  bool copy = true,
  Duration feedback = const Duration(seconds: 2),
}) => MarkdownStyleSheet.fromTheme(_localized(ThemeData())).copyWith(
  codeBlockOptions: MarkdownXCodeBlockOptions(
    showLanguage: language,
    showCopyButton: copy,
    feedbackDuration: feedback,
  ),
);

Widget _app(
  String markdown, {
  MarkdownStyleSheet? styleSheet,
  bool selectable = false,
  TextDirection direction = TextDirection.ltr,
  MarkdownXBlockBuilder? blockBuilder,
}) => MaterialApp(
  home: Directionality(
    textDirection: direction,
    child: Scaffold(
      body: SingleChildScrollView(
        child: MarkdownBody(
          data: markdown,
          styleSheet: styleSheet,
          selectable: selectable,
          blockBuilder: blockBuilder,
        ),
      ),
    ),
  ),
);

const _code = 'void main() {\n  print(1);\n}';
const _md = '```dart\n$_code\n```';

void main() {
  testWidgets('no header by default', (tester) async {
    await tester.pumpWidget(_app(_md));
    expect(find.byIcon(Icons.copy), findsNothing);
    expect(find.text('dart'), findsNothing);
    expect(const MarkdownXCodeBlockOptions().showCopyButton, isFalse);
    expect(const MarkdownXCodeBlockOptions().showLanguage, isFalse);
  });

  testWidgets(
    'shows the language name and a copy button, and pressing it copies the source',
    (tester) async {
      final probe = ClipboardProbe();
      mockClipboard(tester, probe);
      await tester.pumpWidget(_app(_md, styleSheet: _style()));
      expect(find.text('dart'), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsOneWidget);
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();
      expect(probe.text, _code);
      // Success feedback: the icon changes and reverts after a while.
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byIcon(Icons.copy), findsOneWidget);
    },
  );

  testWidgets('language name only or button only can also be chosen', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_md, styleSheet: _style(copy: false)));
    expect(find.text('dart'), findsOneWidget);
    expect(find.byIcon(Icons.copy), findsNothing);
    await tester.pumpWidget(_app(_md, styleSheet: _style(language: false)));
    expect(find.text('dart'), findsNothing);
    expect(find.byIcon(Icons.copy), findsOneWidget);
  });

  testWidgets(
    'no language-name-only header for a code block without a language name',
    (tester) async {
      await tester.pumpWidget(
        _app('```\nabc\n```', styleSheet: _style(copy: false)),
      );
      expect(find.byType(IconButton), findsNothing);
      expect(find.text(''), findsNothing);
    },
  );

  testWidgets(
    'the button has a label and tooltip and can be pressed by keyboard',
    (tester) async {
      final probe = ClipboardProbe();
      mockClipboard(tester, probe);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(_md, styleSheet: _style()));
      expect(find.byTooltip('Copy'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(IconButton)),
        matchesSemantics(
          tooltip: 'Copy',
          isButton: true,
          hasTapAction: true,
          isEnabled: true,
          hasEnabledState: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(probe.text, _code);
      await tester.pump(const Duration(seconds: 3));
      handle.dispose();
    },
  );

  testWidgets('copies the whole text even for huge code split into chunks', (
    tester,
  ) async {
    final probe = ClipboardProbe();
    mockClipboard(tester, probe);
    final code = [for (var i = 0; i < 450; i++) 'var v$i = $i;'].join('\n');
    await tester.pumpWidget(_app('```dart\n$code\n```', styleSheet: _style()));
    await tester.tap(find.byIcon(Icons.copy));
    await tester.pump();
    expect(probe.text, code);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the header is not included in selection copy', (tester) async {
    final probe = ClipboardProbe();
    mockClipboard(tester, probe);
    await tester.pumpWidget(
      selectionApp(MarkdownBody(data: _md, styleSheet: _style())),
    );
    await tester.pumpAndSettle();
    final copied = await selectAllAndCopy(
      tester,
      probe,
      find.byType(MarkdownBody),
    );
    expect(copied, _code);

    // The header is not mixed in even for code over 200 lines (split into chunks).
    final long = [for (var i = 0; i < 450; i++) 'var v$i = $i;'].join('\n');
    await tester.pumpWidget(
      selectionApp(
        MarkdownBody(data: '```dart\n$long\n```', styleSheet: _style()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      await selectAllAndCopy(tester, probe, find.byType(MarkdownBody)),
      long,
    );
  });

  testWidgets('header and code stay LTR even in RTL', (tester) async {
    await tester.pumpWidget(
      _app(_md, styleSheet: _style(), direction: TextDirection.rtl),
    );
    final label = tester.getTopLeft(find.text('dart'));
    final button = tester.getTopLeft(find.byIcon(Icons.copy));
    expect(label.dx, lessThan(button.dx));
  });

  testWidgets('code can scroll horizontally', (tester) async {
    final long = 'x' * 400;
    await tester.pumpWidget(_app('```dart\n$long\n```', styleSheet: _style()));
    final horizontal = tester
        .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .where((w) => w.scrollDirection == Axis.horizontal);
    expect(horizontal, hasLength(1));
  });

  testWidgets(
    'blockBuilder is evaluated first and no header is added; null keeps the header',
    (tester) async {
      await tester.pumpWidget(
        _app(
          _md,
          styleSheet: _style(),
          blockBuilder: (context, block, buildDefault) =>
              block is MdxCodeBlock ? const Text('custom') : null,
        ),
      );
      expect(find.text('custom'), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsNothing);
      // A changed builder closure does not invalidate cached blocks, so start over.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _app(
          _md,
          styleSheet: _style(),
          blockBuilder: (context, block, buildDefault) => null,
        ),
      );
      expect(find.text('custom'), findsNothing);
      expect(find.byIcon(Icons.copy), findsOneWidget);
    },
  );
}
