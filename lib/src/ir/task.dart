/// The task a checkbox of a task list stands for, and the helper that flips it in the Markdown text.
///
/// A task list checkbox is not widget state: it is the `[ ]` or `[x]` in the Markdown source. So
/// the widget only reports a tap ([MarkdownXTask]), and the app rewrites its own `data` with
/// [MarkdownXTask.toggle]. It does not depend on Flutter, so it also works under `dart run`.
library;

/// The length of a task marker: `[ ]`, `[x]` or `[X]`.
const _markerLength = 3;

/// The type of the `onTapCheckbox` callback: [task] is the task list item that was tapped.
typedef MarkdownXCheckboxCallback = void Function(MarkdownXTask task);

/// One task list item that was tapped, with where its marker sits in the Markdown source.
///
/// ```dart
/// Markdown(
///   data: data,
///   onTapCheckbox: (task) => setState(() => data = task.toggle(data)),
/// )
/// ```
///
/// The positions are UTF-16 offsets into the `data` the widget has parsed at the moment of the
/// tap (the same unit as `String.substring`), whatever the line endings or non-ASCII text before
/// the task, and also while `streaming` is true.
final class MarkdownXTask {
  /// Creates a task. Apps normally receive it from `onTapCheckbox`.
  const MarkdownXTask({
    required this.checked,
    required this.index,
    required this.markerStart,
  });

  /// Whether the task is checked in the data that was parsed (the state before the toggle).
  final bool checked;

  /// The 0-based order of this task item among all task items shown in the document, in
  /// document order. It counts nested items and items inside blockquotes.
  final int index;

  /// The UTF-16 offset in `data` of the `[` of the marker.
  final int markerStart;

  /// The UTF-16 offset in `data` just after the `]` of the marker.
  int get markerEnd => markerStart + _markerLength;

  /// Whether [data] still has a marker for this task at [markerStart]: `[ ]` for an unchecked task,
  /// `[x]` or `[X]` for a checked one.
  bool matches(String data) {
    if (markerStart < 0 || markerEnd > data.length) return false;
    if (data.codeUnitAt(markerStart) != 0x5B ||
        data.codeUnitAt(markerEnd - 1) != 0x5D) {
      return false;
    }
    final mark = data.codeUnitAt(markerStart + 1);
    return checked ? (mark == 0x78 || mark == 0x58) : mark == 0x20;
  }

  /// Returns [data] with this task's marker flipped: `[ ]` becomes `[x]` and `[x]` / `[X]` becomes `[ ]`.
  ///
  /// Only the three characters of the marker change. When [data] no longer has the expected
  /// marker at [markerStart] (the text was edited after the tap target was built, or the task
  /// was already toggled), nothing is changed and [data] itself is returned: a stale tap never
  /// corrupts the text. Compare with `identical` or `==` to tell whether anything changed.
  String toggle(String data) {
    if (!matches(data)) return data;
    return data.replaceRange(markerStart, markerEnd, checked ? '[ ]' : '[x]');
  }

  @override
  bool operator ==(Object other) =>
      other is MarkdownXTask &&
      other.checked == checked &&
      other.index == index &&
      other.markerStart == markerStart;

  @override
  int get hashCode => Object.hash(checked, index, markerStart);

  @override
  String toString() =>
      'MarkdownXTask(checked: $checked, index: $index, markerStart: $markerStart)';
}
