import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

List<MdxBlock> _alerts(String source) => applyMarkdownXExtensions(
  parseMarkdown(
    applyMarkdownXSourceTransforms(source, [markdownXAlertsExtension]),
  ),
  [markdownXAlertsExtension],
);

MdxBlock _alert(String kind, [List<MdxBlock> blocks = const []]) =>
    MdxCustomBlock(
      markdownXAlertType,
      attributes: {'kind': kind},
      blocks: blocks,
    );

MdxBlock _p(String text) => MdxParagraph([MdxText(text)]);

Widget _app(Widget child, {ThemeData? theme, TextDirection? direction}) =>
    MaterialApp(
      theme: theme,
      home: Directionality(
        textDirection: direction ?? TextDirection.ltr,
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  group('transform', () {
    for (final kind in MarkdownXAlertKind.values) {
      test('[!${kind.name.toUpperCase()}] becomes an alert', () {
        final marker = kind.name.toUpperCase();
        expect(_alerts('> [!$marker]\n> text'), [
          _alert(kind.name, [_p('text')]),
        ]);
      });
    }

    test('marker is case-insensitive', () {
      expect(_alerts('> [!note]\n> a'), [
        _alert('note', [_p('a')]),
      ]);
      expect(_alerts('> [!WaRnInG]\n> a'), [
        _alert('warning', [_p('a')]),
      ]);
    });

    test('a quote with only a marker becomes an alert with no body', () {
      expect(_alerts('> [!TIP]'), [_alert('tip')]);
    });

    test('blocks after the marker (paragraph, list) stay in the body', () {
      final blocks = _alerts('> [!NOTE]\n> a\n>\n> - b\n>\n> c');
      final alert = blocks.single as MdxCustomBlock;
      expect(alert.attributes['kind'], 'note');
      expect(alert.blocks.map((b) => b.runtimeType).toList(), [
        MdxParagraph,
        MdxList,
        MdxParagraph,
      ]);
    });

    test('a hard break at the end of the marker line is dropped', () {
      expect(_alerts('> [!NOTE]  \n> a'), [
        _alert('note', [_p('a')]),
      ]);
    });

    test('the inline after the marker stays in the body', () {
      final alert = _alerts('> [!NOTE]\n> **b** c').single as MdxCustomBlock;
      expect(alert.blocks.single, isA<MdxParagraph>());
      final inlines = (alert.blocks.single as MdxParagraph).inlines;
      expect(inlines.first, isA<MdxStyled>());
    });

    test(
      'text continuing on the same line is not an alert (same as GitHub)',
      () {
        expect(_alerts('> [!NOTE] x'), [
          MdxBlockquote([_p('[!NOTE] x')]),
        ]);
      },
    );

    test('input that is not an alert is returned unchanged', () {
      for (final source in [
        '> a [!NOTE]',
        '> text\n>\n> [!NOTE]',
        '> [!INFO]\n> a',
        '> [! NOTE]\n> a',
        '> **[!NOTE]**\n> a',
        '[!NOTE]\n\ntext',
        '- [!NOTE]\n',
        '> ```\n> [!NOTE]\n> ```',
        '> `[!NOTE]`',
      ]) {
        final parsed = parseMarkdown(source);
        expect(
          identical(
            applyMarkdownXExtensions(parsed, [markdownXAlertsExtension]),
            parsed,
          ),
          isTrue,
          reason: source,
        );
      }
    });

    test('becomes an alert inside nested quotes and lists', () {
      expect(_alerts('> > [!NOTE]\n> > a'), [
        MdxBlockquote([
          _alert('note', [_p('a')]),
        ]),
      ]);
      final list = _alerts('- > [!TIP]\n  > x').single as MdxList;
      expect(list.items.single.blocks, [
        _alert('tip', [_p('x')]),
      ]);
    });

    test('a quote after an alert stays a normal quote', () {
      final blocks = _alerts('> [!NOTE]\n> a\n\ntext\n\n> q');
      expect(blocks.length, 3);
      expect(blocks.last, isA<MdxBlockquote>());
    });
  });

  group('streaming', () {
    test('a partial marker is hidden until complete', () {
      const source = '> [!NOTE]';
      for (var i = 1; i <= source.length; i++) {
        final repaired = markdownXRepairStreamingTail(source.substring(0, i));
        expect(repaired, isNot(contains('[')), reason: source.substring(0, i));
        expect(repaired, isNot(contains('!')), reason: source.substring(0, i));
        final blocks = parseMarkdown(repaired);
        expect(
          _alerts(repaired).whereType<MdxCustomBlock>(),
          isEmpty,
          reason: source.substring(0, i),
        );
        expect(blocks.toString(), isNot(contains('[!')));
      }
    });

    test(
      'becomes an alert once the marker line is terminated by a newline',
      () {
        final repaired = markdownXRepairStreamingTail('> [!WARNING]\n');
        expect(_alerts(repaired).single, _alert('warning'));
        final next = markdownXRepairStreamingTail('> [!WARNING]\n> be');
        expect(_alerts(next).single, _alert('warning', [_p('be')]));
      },
    );

    test('partial lowercase and other-kind markers are also hidden', () {
      for (final s in ['> [!tip', '> [!IMPORT', '> [!cau', '> > [!NO']) {
        expect(markdownXRepairStreamingTail(s), isNot(contains('[!')));
      }
    });

    test(
      'the second and later quote lines and normal quotes are unchanged',
      () {
        const a = '> text\n> [!NO';
        expect(markdownXRepairStreamingTail(a), startsWith('> text\n>'));
        expect(markdownXRepairStreamingTail(a), contains('!NO'));
        const b = '> [link](u)';
        expect(markdownXRepairStreamingTail(b), b);
        const c = '> [x';
        expect(markdownXRepairStreamingTail(c), isNot(contains('[')));
      },
    );

    test('a completed document (last line is not a marker) is unchanged', () {
      const s = '> [!NOTE]\n> done';
      expect(markdownXRepairStreamingTail(s), s);
    });
  });

  group('widget', () {
    testWidgets('renders icon, title and body; semantics has a label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(const MarkdownBody(data: '> [!NOTE]\n> hello alert')),
      );
      expect(find.text('Note'), findsOneWidget);
      expect(find.text('hello alert'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Note')), findsOneWidget);
      // Rendered as an alert, not a quote (the rule uses the alert color).
      expect(find.textContaining('[!NOTE]'), findsNothing);
      handle.dispose();
    });

    testWidgets('every kind has its own title and icon', (tester) async {
      final style = MarkdownXAlertStyle.light;
      await tester.pumpWidget(
        _app(
          const MarkdownBody(
            data:
                '> [!NOTE]\n> a\n\n> [!TIP]\n> a\n\n> [!IMPORTANT]\n> a\n\n'
                '> [!WARNING]\n> a\n\n> [!CAUTION]\n> a',
          ),
        ),
      );
      for (final kind in MarkdownXAlertKind.values) {
        final k = style.of(kind);
        expect(find.text(k.label), findsOneWidget, reason: kind.name);
        expect(find.byIcon(k.icon), findsOneWidget, reason: kind.name);
      }
    });

    testWidgets('light uses the light color, dark uses the dark color', (
      tester,
    ) async {
      Future<Color?> iconColor(Brightness b) async {
        await tester.pumpWidget(
          _app(
            const MarkdownBody(data: '> [!WARNING]\n> a'),
            theme: ThemeData(brightness: b),
          ),
        );
        await tester.pumpAndSettle();
        return tester
            .widget<Icon>(find.byIcon(Icons.warning_amber_outlined))
            .color;
      }

      expect(
        await iconColor(Brightness.light),
        MarkdownXAlertStyle.light.warning.color,
      );
      expect(
        await iconColor(Brightness.dark),
        MarkdownXAlertStyle.dark.warning.color,
      );
    });

    testWidgets('in RTL the rule and icon are on the start (right) side', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const MarkdownBody(data: '> [!TIP]\n> a'),
          direction: TextDirection.rtl,
        ),
      );
      final icon = tester.getCenter(find.byIcon(Icons.lightbulb_outline));
      final title = tester.getCenter(find.text('Tip'));
      expect(icon.dx, greaterThan(title.dx));
      final box = tester.widget<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).border is BorderDirectional,
        ),
      );
      final border =
          (box.decoration! as BoxDecoration).border! as BorderDirectional;
      expect(border.start.width, greaterThan(0));
      expect(border.end, BorderSide.none);
    });

    testWidgets('style label, color and icon can be overridden', (
      tester,
    ) async {
      final base = MarkdownStyleSheet.fromTheme(
        ThemeData(textTheme: Typography.material2021().englishLike),
      );
      final style = base.copyWith(
        alerts: MarkdownXAlertStyle.light.copyWith(
          note: const MarkdownXAlertKindStyle(
            color: Color(0xFF123456),
            icon: Icons.star,
            label: 'メモ',
          ),
        ),
      );
      await tester.pumpWidget(
        _app(MarkdownBody(data: '> [!NOTE]\n> a', styleSheet: style)),
      );
      expect(find.text('メモ'), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.star)).color,
        const Color(0xFF123456),
      );
    });

    testWidgets('blockBuilder can replace type alert', (tester) async {
      Widget? builder(BuildContext c, MdxBlock block, Widget Function() d) {
        if (block is MdxCustomBlock && block.type == markdownXAlertType) {
          return Text('custom:${block.attributes['kind']}');
        }
        return null;
      }

      await tester.pumpWidget(
        _app(MarkdownBody(data: '> [!CAUTION]\n> a', blockBuilder: builder)),
      );
      expect(find.text('custom:caution'), findsOneWidget);
      expect(find.text('Caution'), findsNothing);
    });

    testWidgets(
      'with alerts: false it stays a quote containing [!NOTE] as before',
      (tester) async {
        await tester.pumpWidget(
          _app(const MarkdownBody(data: '> [!NOTE]\n> a', alerts: false)),
        );
        expect(find.text('[!NOTE] a'), findsOneWidget);
        expect(find.text('Note'), findsNothing);
      },
    );

    testWidgets(
      'a quote with text on the same line is not an alert and no marker is visible',
      (tester) async {
        await tester.pumpWidget(
          _app(const MarkdownBody(data: '> [!NOTE] a\n\n> [!TIP]\n> b')),
        );
        expect(find.text('[!NOTE] a'), findsOneWidget);
        expect(find.text('Note'), findsNothing);
        expect(find.text('Tip'), findsOneWidget);
        expect(find.textContaining('\uE001'), findsNothing);
      },
    );

    testWidgets('SliverMarkdown also produces alerts by default', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [SliverMarkdown(data: '> [!IMPORTANT]\n> a')],
            ),
          ),
        ),
      );
      expect(find.text('Important'), findsOneWidget);
    });

    testWidgets('a partial marker is not visible while streaming', (
      tester,
    ) async {
      const source = '> [!NOTE]\n> text';
      for (var i = 1; i <= source.length; i++) {
        await tester.pumpWidget(
          _app(MarkdownBody(data: source.substring(0, i), streaming: true)),
        );
        expect(find.textContaining('[!'), findsNothing, reason: '$i');
        expect(find.textContaining('!NO'), findsNothing, reason: '$i');
      }
    });
  });
}
