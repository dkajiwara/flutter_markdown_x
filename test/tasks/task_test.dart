import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MarkdownXTask.toggle', () {
    const data = '- [ ] a\n- [x] b\n- [X] c\n';

    test('checks an unchecked marker', () {
      const task = MarkdownXTask(checked: false, index: 0, markerStart: 2);
      expect(task.markerEnd, 5);
      expect(task.toggle(data), '- [x] a\n- [x] b\n- [X] c\n');
    });

    test('unchecks a lowercase or uppercase marker', () {
      const lower = MarkdownXTask(checked: true, index: 1, markerStart: 10);
      expect(lower.toggle(data), '- [ ] a\n- [ ] b\n- [X] c\n');
      const upper = MarkdownXTask(checked: true, index: 2, markerStart: 18);
      expect(upper.toggle(data), '- [ ] a\n- [x] b\n- [ ] c\n');
    });

    test('leaves everything outside the marker alone', () {
      const task = MarkdownXTask(checked: false, index: 0, markerStart: 5);
      final text = '日本語\n\n- [ ] é 😀\r\n- [x] z';
      final start = text.indexOf('[ ]');
      final moved = MarkdownXTask(
        checked: task.checked,
        index: 0,
        markerStart: start,
      );
      expect(moved.toggle(text), text.replaceFirst('[ ]', '[x]'));
    });

    test('returns data unchanged when it no longer has a marker there', () {
      const task = MarkdownXTask(checked: false, index: 0, markerStart: 2);
      // Text was inserted before the marker.
      const edited = 'X\n- [ ] a\n';
      expect(identical(task.toggle(edited), edited), isTrue);
      // The marker is gone.
      const gone = '- a\n';
      expect(identical(task.toggle(gone), gone), isTrue);
    });

    test(
      'returns data unchanged when the marker state differs from the task',
      () {
        // The data was toggled elsewhere after the tap target was built.
        const task = MarkdownXTask(checked: false, index: 0, markerStart: 2);
        const checked = '- [x] a\n';
        expect(identical(task.toggle(checked), checked), isTrue);
      },
    );

    test('returns data unchanged for out-of-range or unknown offsets', () {
      const past = MarkdownXTask(checked: false, index: 0, markerStart: 100);
      expect(past.toggle(data), data);
      const negative = MarkdownXTask(checked: false, index: 0, markerStart: -1);
      expect(negative.toggle(data), data);
      const half = MarkdownXTask(checked: false, index: 0, markerStart: 6);
      expect(half.toggle(data), data);
    });

    test('toggling twice restores a lowercase marker', () {
      const task = MarkdownXTask(checked: false, index: 0, markerStart: 2);
      final once = task.toggle(data);
      const back = MarkdownXTask(checked: true, index: 0, markerStart: 2);
      expect(back.toggle(once), data);
    });
  });

  test('MarkdownXTask has value equality', () {
    const a = MarkdownXTask(checked: true, index: 1, markerStart: 4);
    const b = MarkdownXTask(checked: true, index: 1, markerStart: 4);
    const c = MarkdownXTask(checked: false, index: 1, markerStart: 4);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
    expect(a.toString(), contains('index: 1'));
  });
}
