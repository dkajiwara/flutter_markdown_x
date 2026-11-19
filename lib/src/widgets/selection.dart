import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// The default separator between blocks when a selection is copied.
const mdxSelectionBlockSeparator = '\n';

/// The separator between cells in the same table row.
const mdxSelectionCellSeparator = '\t';

/// The separator between a list marker and the item body.
const mdxSelectionMarkerSeparator = ' ';

/// Wraps [child] in a [SelectionBlock] only when inside a [SelectionArea].
///
/// Without a selection mechanism it returns [child] as-is, so there is no
/// extra Widget, State, or delegate when selection is not used.
Widget selectionBlock(
  BuildContext context,
  Widget child, {
  String separator = mdxSelectionBlockSeparator,
}) => SelectionContainer.maybeOf(context) == null
    ? child
    : SelectionBlock(separator: separator, child: child);

/// Wraps the whole document and mediates the selection registration of top-level blocks.
///
/// Top-level blocks (such as children of a lazily built sliver) register through
/// a registrar that Flutter puts in between, so they cannot see the list of their
/// siblings directly. So registrations are collected here per document, and the
/// scope answers "is there a selected block above me?".
/// It adds nothing outside a [SelectionArea].
class DocumentSelectionScope extends StatefulWidget {
  /// Creates a scope that wraps [child].
  const DocumentSelectionScope({super.key, required this.child});

  /// The Widget to wrap (the whole document).
  final Widget child;

  @override
  State<DocumentSelectionScope> createState() => _DocumentSelectionScopeState();
}

class _DocumentSelectionScopeState extends State<DocumentSelectionScope> {
  _DocumentRegistrar? _registrar;

  @override
  Widget build(BuildContext context) {
    final parent = SelectionContainer.maybeOf(context);
    if (parent == null) return widget.child;
    var registrar = _registrar;
    if (registrar == null || !identical(registrar.parent, parent)) {
      registrar = _registrar = _DocumentRegistrar(parent);
    }
    return _DocumentLedgerScope(
      registrar: registrar,
      child: SelectionRegistrarScope(registrar: registrar, child: widget.child),
    );
  }
}

class _DocumentLedgerScope extends InheritedWidget {
  const _DocumentLedgerScope({required this.registrar, required super.child});

  final _DocumentRegistrar registrar;

  @override
  bool updateShouldNotify(_DocumentLedgerScope oldWidget) =>
      !identical(registrar, oldWidget.registrar);
}

/// Remembers the registered top-level blocks while mediating registration to the parent registrar.
final class _DocumentRegistrar implements SelectionRegistrar {
  _DocumentRegistrar(this.parent);

  final SelectionRegistrar parent;
  final Set<Selectable> _members = {};

  /// The registered blocks in top-to-bottom order, with their positions. Discarded when registrations change.
  List<Selectable>? _sorted;
  Map<Selectable, int>? _indices;

  @override
  void add(Selectable selectable) {
    _members.add(selectable);
    _sorted = null;
    parent.add(selectable);
    _requestFrame();
  }

  @override
  void remove(Selectable selectable) {
    _members.remove(selectable);
    _sorted = null;
    parent.remove(selectable);
  }

  static double _top(Selectable selectable) => _bounds(selectable).top;

  /// Whether any block above [self] has a selected part.
  bool hasSelectionAbove(Selectable self) {
    var sorted = _sorted;
    if (sorted == null) {
      sorted = _members.toList()..sort((a, b) => _top(a).compareTo(_top(b)));
      _sorted = sorted;
      _indices = {for (var i = 0; i < sorted.length; i++) sorted[i]: i};
    }
    final index = _indices![self];
    if (index == null) return false;
    for (var i = index - 1; i >= 0; i--) {
      if (_hasSelection(sorted[i])) return true;
    }
    return false;
  }
}

Rect _bounds(Selectable selectable) {
  final boxes = selectable.boundingBoxes;
  var rect = boxes.first;
  for (var i = 1; i < boxes.length; i++) {
    rect = rect.expandToInclude(boxes[i]);
  }
  return MatrixUtils.transformRect(selectable.getTransformTo(null), rect);
}

/// The unit that gets [separator] prepended when a selection is copied.
///
/// Flutter's selection concatenates the characters of adjacent Text widgets with
/// no separator. When each block is wrapped in this container, [separator] is
/// added before its own characters only when "an earlier part within the same
/// parent is selected". So selecting only inside one block adds no extra newline,
/// and no separator is added at the start or end.
///
/// The order of siblings is decided by reversing the horizontal order in
/// right-to-left (RTL) writing direction.
class SelectionBlock extends StatefulWidget {
  /// Creates a Widget that wraps [child] as a selection unit.
  const SelectionBlock({
    super.key,
    this.separator = mdxSelectionBlockSeparator,
    required this.child,
  });

  /// The string added before its own characters when an earlier sibling is selected.
  final String separator;

  /// The Widget wrapped as a selection unit.
  final Widget child;

  @override
  State<SelectionBlock> createState() => _SelectionBlockState();
}

class _SelectionBlockState extends State<SelectionBlock> {
  _BlockSelectionDelegate? _delegate;
  _RecordingRegistrar? _registrar;

  @override
  void dispose() {
    _delegate?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registrar = SelectionContainer.maybeOf(context);
    if (registrar == null) return widget.child;
    // Recreate only when the parent registrar changes (this re-registers).
    var proxy = _registrar;
    if (proxy == null || !identical(proxy.parent, registrar)) {
      proxy = _registrar = _RecordingRegistrar(registrar);
    }
    final delegate = _delegate ??= _BlockSelectionDelegate();
    delegate
      ..separator = widget.separator
      ..registrar = proxy
      ..ledger = context
          .dependOnInheritedWidgetOfExactType<_DocumentLedgerScope>()
          ?.registrar
      ..textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    return SelectionContainer(
      registrar: proxy,
      delegate: delegate,
      child: widget.child,
    );
  }
}

/// Remembers the [Selectable] (this container itself) registered with the parent registrar.
///
/// Used to find out which one of the parent's `selectables` is itself.
final class _RecordingRegistrar implements SelectionRegistrar {
  _RecordingRegistrar(this.parent);

  final SelectionRegistrar parent;

  /// This container itself, as registered with the parent.
  Selectable? self;

  @override
  void add(Selectable selectable) {
    self = selectable;
    parent.add(selectable);
    _requestFrame();
  }

  @override
  void remove(Selectable selectable) {
    if (identical(self, selectable)) self = null;
    parent.remove(selectable);
  }
}

/// The parent delegate that receives a registration applies it (updating the
/// selectable range) after the next frame. With deep nesting, each level's
/// application waits for the previous level's frame, so when the screen is
/// still it does not reach the upper levels (select-all ends up empty). A frame
/// is requested on every registration so the chain of applications does not
/// stall. It is called only inside the selection mechanism.
void _requestFrame() => SchedulerBinding.instance.scheduleFrame();

/// The upper limit of the position difference for treating items as the same row vertically (the same value as Flutter's selection).
const _verticalThreshold = 3.0;

/// Characters that only steer line breaking and bidirectional layout and show nothing: the zero
/// width space (`<wbr>`), and the bidi isolates, embeddings and overrides (`<bdi>`, `<bdo>`).
/// Browsers copy none of the generated effects of these tags, so copying drops them too.
final _invisible = RegExp('[\u200B\u202A-\u202E\u2066-\u2069]');

bool _hasSelection(Selectable selectable) {
  final range = selectable.getSelection();
  return range != null && range.startOffset != range.endOffset;
}

final class _BlockSelectionDelegate extends StaticSelectionContainerDelegate {
  String separator = mdxSelectionBlockSeparator;
  _RecordingRegistrar? registrar;
  _DocumentRegistrar? ledger;
  TextDirection textDirection = TextDirection.ltr;

  /// A cache of this container's position within the parent's `selectables`. Searched again if it is off.
  int _index = -1;

  @override
  void add(Selectable selectable) {
    super.add(selectable);
    _requestFrame();
  }

  @override
  SelectedContent? getSelectedContent() {
    var content = super.getSelectedContent();
    if (content != null && _invisible.hasMatch(content.plainText)) {
      content = SelectedContent(
        plainText: content.plainText.replaceAll(_invisible, ''),
      );
    }
    if (content == null || content.plainText.isEmpty || separator.isEmpty) {
      return content;
    }
    if (!_hasEarlierSelection()) return content;
    return SelectedContent(plainText: '$separator${content.plainText}');
  }

  bool _hasEarlierSelection() {
    final proxy = registrar;
    final self = proxy?.self;
    final parent = proxy?.parent;
    if (self == null) return false;
    // A nested block is a sibling of the parent block, and a top-level block (with a
    // keep-alive registrar in between) is looked up in the document's registry.
    if (parent is! MultiSelectableSelectionContainerDelegate) {
      return (parent is _DocumentRegistrar ? parent : ledger)
              ?.hasSelectionAbove(self) ??
          false;
    }
    final siblings = parent.selectables;
    if (_index < 0 ||
        _index >= siblings.length ||
        !identical(siblings[_index], self)) {
      _index = siblings.indexWhere((s) => identical(s, self));
    }
    for (var i = _index - 1; i >= 0; i--) {
      if (_hasSelection(siblings[i])) return true;
    }
    return false;
  }

  @override
  Comparator<Selectable> get compareOrder => _compareScreenOrder;

  /// The on-screen order (top to bottom, and start to end within the same row). It
  /// matches Flutter's default order, but in RTL it reverses the horizontal order within the same row.
  int _compareScreenOrder(Selectable a, Selectable b) {
    final rectA = _bounds(a);
    final rectB = _bounds(b);
    final sameRow =
        (rectA.top - rectB.top < _verticalThreshold &&
            rectA.bottom - rectB.bottom > -_verticalThreshold) ||
        (rectB.top - rectA.top < _verticalThreshold &&
            rectB.bottom - rectA.bottom > -_verticalThreshold);
    if (!sameRow) {
      if ((rectA.top - rectB.top).abs() > _verticalThreshold) {
        return rectA.top > rectB.top ? 1 : -1;
      }
      return rectA.bottom > rectB.bottom ? 1 : -1;
    }
    // When one horizontally contains the other, the containing one comes first.
    if (rectA.left - rectB.left < precisionErrorTolerance &&
        rectA.right - rectB.right > -precisionErrorTolerance) {
      return -1;
    }
    if (rectB.left - rectA.left < precisionErrorTolerance &&
        rectB.right - rectA.right > -precisionErrorTolerance) {
      return 1;
    }
    final rtl = textDirection == TextDirection.rtl;
    final delta = rtl ? rectB.right - rectA.right : rectA.left - rectB.left;
    if (delta.abs() > precisionErrorTolerance) return delta > 0 ? 1 : -1;
    return rectA.right > rectB.right ? 1 : -1;
  }
}
