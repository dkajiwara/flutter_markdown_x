import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Receives the contents of Clipboard.setData.
class ClipboardProbe {
  String? text;
}

/// Replaces the platform-channel Clipboard and puts the copied string into [probe].
void mockClipboard(WidgetTester tester, ClipboardProbe probe) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        probe.text = (call.arguments as Map)['text'] as String?;
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

/// Selects all in the [SelectionArea] that is an ancestor of [inside], and returns the copied string.
Future<String?> selectAllAndCopy(
  WidgetTester tester,
  ClipboardProbe probe,
  Finder inside,
) async {
  final context = tester.element(inside.first);
  probe.text = null;
  Actions.invoke(
    context,
    const SelectAllTextIntent(SelectionChangedCause.keyboard),
  );
  await tester.pump();
  return copySelection(tester, probe, inside);
}

/// Copies the current selection and returns the copied string.
Future<String?> copySelection(
  WidgetTester tester,
  ClipboardProbe probe,
  Finder inside,
) async {
  probe.text = null;
  Actions.invoke(tester.element(inside.first), CopySelectionTextIntent.copy);
  await tester.pump();
  return probe.text;
}

/// Places [child] inside a scrollable parent and wraps it in a [SelectionArea].
Widget selectionApp(Widget child, {bool scroll = true}) => MaterialApp(
  home: Scaffold(
    body: SelectionArea(
      child: scroll ? SingleChildScrollView(child: child) : child,
    ),
  ),
);
