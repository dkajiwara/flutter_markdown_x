// MarkdownBody keeps the same widget structure for one block and for several, so the state of
// a block (such as an opened details) survives a stream growing from one block to two.
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _details = '<details>\n<summary>More</summary>\n\nhidden\n\n</details>';

class _Host extends StatefulWidget {
  const _Host({super.key});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String data = _details;

  void update(String value) => setState(() => data = value);

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(body: MarkdownBody(data: data)),
  );
}

void main() {
  testWidgets('details stays open when one block becomes two and back', (
    tester,
  ) async {
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_Host(key: key));
    expect(find.text('hidden'), findsNothing);
    await tester.tap(find.text('More'));
    await tester.pump();
    expect(find.text('hidden'), findsOneWidget);

    key.currentState!.update('$_details\n\nmore\n');
    await tester.pump();
    expect(find.text('more'), findsOneWidget);
    expect(find.text('hidden'), findsOneWidget);

    key.currentState!.update(_details);
    await tester.pump();
    expect(find.text('more'), findsNothing);
    expect(find.text('hidden'), findsOneWidget);
  });
}
