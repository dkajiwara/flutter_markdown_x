// Blocks keep their cache when a parent rebuilds with flutter_markdown style call sites: a style
// sheet, a builders map and closures created inside build().
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_markdown_x/src/widgets/renderer.dart'
    show debugMdxBlockBuildCount;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

const _doc =
    '# Title\n\nFirst paragraph.\n\n- a\n- b\n\n```dart\nvar x = 1;\n```\n\n> quote\n';
const _blocks = 5;

class _CountingBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => null;
}

class _OtherBuilder extends MarkdownElementBuilder {}

class _Host extends StatefulWidget {
  const _Host({super.key, this.sliver = false});

  final bool sliver;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int ticks = 0;
  String data = _doc;
  double spacing = 10;
  bool extraBuilder = false;
  bool withSizedImage = false;

  void rebuild(VoidCallback change) => setState(change);

  @override
  Widget build(BuildContext context) {
    // Everything below is created anew on every build, as typical flutter_markdown code does.
    final sheet = MarkdownStyleSheet.fromTheme(Theme.of(context))
        .copyWith(blockSpacing: spacing);
    final builders = <String, MarkdownElementBuilder>{
      'code': _CountingBuilder(),
      if (extraBuilder) 'em': _OtherBuilder(),
    };
    void onTap(String text, String? href, String title) {}
    Widget imageBuilder(MarkdownImageConfig config) => const SizedBox();
    Widget checkbox(bool value) => const SizedBox();
    Widget bullet(MarkdownBulletParameters p) => const SizedBox();
    return widget.sliver
        ? Markdown(
            data: data,
            styleSheet: sheet,
            builders: builders,
            paddingBuilders: {'p': _PaddingBuilder()},
            onTapLink: onTap,
            sizedImageBuilder: withSizedImage ? imageBuilder : null,
            checkboxBuilder: checkbox,
            bulletBuilder: bullet,
            onTapText: () {},
          )
        : MarkdownBody(
            data: data,
            styleSheet: sheet,
            builders: builders,
            paddingBuilders: {'p': _PaddingBuilder()},
            onTapLink: onTap,
            sizedImageBuilder: withSizedImage ? imageBuilder : null,
            checkboxBuilder: checkbox,
            bulletBuilder: bullet,
          );
  }
}

class _PaddingBuilder extends MarkdownPaddingBuilder {}

Future<GlobalKey<_HostState>> _pump(
  WidgetTester tester, {
  bool sliver = false,
}) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final key = GlobalKey<_HostState>();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: sliver
            ? _Host(key: key, sliver: true)
            : SingleChildScrollView(child: _Host(key: key)),
      ),
    ),
  );
  return key;
}

void main() {
  for (final sliver in [false, true]) {
    final name = sliver ? 'Markdown' : 'MarkdownBody';
    group(name, () {
      testWidgets('parent rebuilds with inline objects rebuild no block', (
        tester,
      ) async {
        final key = await _pump(tester, sliver: sliver);
        final before = debugMdxBlockBuildCount;
        expect(before, greaterThanOrEqualTo(_blocks));
        for (var i = 0; i < 10; i++) {
          key.currentState!.rebuild(() => key.currentState!.ticks++);
          await tester.pump();
        }
        expect(debugMdxBlockBuildCount, before);
      });

      testWidgets('appending a paragraph builds only the new block', (
        tester,
      ) async {
        final key = await _pump(tester, sliver: sliver);
        final before = debugMdxBlockBuildCount;
        key.currentState!.rebuild(
          () => key.currentState!.data = '$_doc\nnew paragraph\n',
        );
        await tester.pump();
        expect(debugMdxBlockBuildCount - before, 1);
      });

      testWidgets('a changed blockSpacing rebuilds every block once', (
        tester,
      ) async {
        final key = await _pump(tester, sliver: sliver);
        final before = debugMdxBlockBuildCount;
        key.currentState!.rebuild(() => key.currentState!.spacing = 20);
        await tester.pump();
        expect(debugMdxBlockBuildCount - before, greaterThanOrEqualTo(_blocks));
        final after = debugMdxBlockBuildCount;
        key.currentState!.rebuild(() => key.currentState!.ticks++);
        await tester.pump();
        expect(debugMdxBlockBuildCount, after);
      });

      testWidgets('a new builders key rebuilds every block', (tester) async {
        final key = await _pump(tester, sliver: sliver);
        final before = debugMdxBlockBuildCount;
        key.currentState!.rebuild(() => key.currentState!.extraBuilder = true);
        await tester.pump();
        expect(debugMdxBlockBuildCount - before, greaterThanOrEqualTo(_blocks));
      });

      testWidgets('a closure turning null or non-null rebuilds every block', (
        tester,
      ) async {
        final key = await _pump(tester, sliver: sliver);
        final before = debugMdxBlockBuildCount;
        key.currentState!.rebuild(
          () => key.currentState!.withSizedImage = true,
        );
        await tester.pump();
        expect(debugMdxBlockBuildCount - before, greaterThanOrEqualTo(_blocks));
      });
    });
  }
}
