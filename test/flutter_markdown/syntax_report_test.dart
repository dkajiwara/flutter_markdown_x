// extensionSet, blockSyntaxes and inlineSyntaxes: built-in syntaxes are no-ops; any other syntax
// is reported once per runtimeType (doc/flutter_markdown_compat.md, section 5b).
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_markdown_x/src/parser/syntax_compat.dart'
    show resetReportedSyntaxes;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

class _MySyntax extends md.InlineSyntax {
  _MySyntax() : super(r'@@');

  @override
  bool onMatch(md.InlineParser parser, Match match) => false;
}

class _MyBlock extends md.BlockSyntax {
  const _MyBlock();

  @override
  RegExp get pattern => RegExp(r'^%%');

  @override
  md.Node parse(md.BlockParser parser) {
    parser.advance();
    return md.Text('');
  }
}

Future<List<FlutterErrorDetails>> _pump(
  WidgetTester tester,
  List<Widget> bodies,
) async {
  final reports = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = reports.add;
  try {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Column(children: bodies)),
      ),
    );
  } finally {
    FlutterError.onError = previous;
  }
  return reports;
}

void main() {
  setUp(resetReportedSyntaxes);

  testWidgets('built-in extension sets and syntaxes report nothing', (
    tester,
  ) async {
    final reports = await _pump(tester, [
      MarkdownBody(data: 'a', extensionSet: md.ExtensionSet.gitHubFlavored),
      MarkdownBody(data: 'a', extensionSet: md.ExtensionSet.gitHubWeb),
      MarkdownBody(data: 'a', extensionSet: md.ExtensionSet.commonMark),
      MarkdownBody(data: 'a', extensionSet: md.ExtensionSet.none),
      MarkdownBody(
        data: 'a',
        blockSyntaxes: const [md.TableSyntax(), md.FencedCodeBlockSyntax()],
        // ignore: deprecated_member_use
        inlineSyntaxes: [md.StrikethroughSyntax(), TaskListSyntax()],
      ),
    ]);
    expect(reports, isEmpty);
  });

  testWidgets('custom syntaxes are reported once per runtimeType', (
    tester,
  ) async {
    final reports = await _pump(tester, [
      MarkdownBody(
        data: 'a',
        inlineSyntaxes: [_MySyntax()],
        blockSyntaxes: const [_MyBlock()],
      ),
      MarkdownBody(data: 'b', inlineSyntaxes: [_MySyntax()]),
      MarkdownBody(
        data: 'c',
        extensionSet: md.ExtensionSet(
          const [_MyBlock()],
          [md.ColorSwatchSyntax()],
        ),
      ),
    ]);
    final messages = reports.map((r) => r.exception.toString()).toList();
    expect(messages.where((m) => m.contains('_MySyntax')), hasLength(1));
    expect(messages.where((m) => m.contains('_MyBlock')), hasLength(1));
    expect(
      messages.where((m) => m.contains('ColorSwatchSyntax')),
      hasLength(1),
    );
    expect(messages.first, contains('MarkdownXExtension'));
    expect(reports.first.library, 'flutter_markdown_x');
  });

  testWidgets('the document still renders without a custom syntax', (
    tester,
  ) async {
    await _pump(tester, [
      MarkdownBody(data: 'hello @@ world', inlineSyntaxes: [_MySyntax()]),
    ]);
    expect(find.textContaining('hello @@ world'), findsOneWidget);
  });

  testWidgets('AlertBlockSyntax turns alerts on even with alerts: false', (
    tester,
  ) async {
    await _pump(tester, [
      MarkdownBody(
        data: '> [!NOTE]\n> body\n',
        alerts: false,
        blockSyntaxes: const [md.AlertBlockSyntax()],
      ),
    ]);
    expect(find.byType(MdxAlertView), findsOneWidget);
  });
}
