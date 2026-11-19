/// Placement and layout of tables with `colspan` / `rowspan`.
///
/// Flutter's [Table] cannot span cells, so only tables with spans are drawn with this
/// custom layout. Tables without spans (including GFM tables) stay as [Table].
// Named parameters cannot be private, so the render object assigns them in the initializer list.
// ignore_for_file: prefer_initializing_formals
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../ir/nodes.dart';

/// The position of one cell in the grid.
class SpanCellPlacement {
  /// Creates it from the cell position and spans.
  const SpanCellPlacement({
    required this.row,
    required this.column,
    required this.rowSpan,
    required this.colSpan,
  });

  /// The row of the cell (0-based). If there is a header, the header is row 0.
  final int row;

  /// The column of the cell (0-based).
  final int column;

  /// The number of rows the cell spans, after clamping so it does not exceed the bottom of the table.
  final int rowSpan;

  /// The number of columns the cell spans, after clamping so it does not exceed the column count.
  final int colSpan;

  @override
  bool operator ==(Object other) =>
      other is SpanCellPlacement &&
      other.row == row &&
      other.column == column &&
      other.rowSpan == rowSpan &&
      other.colSpan == colSpan;

  @override
  int get hashCode => Object.hash(row, column, rowSpan, colSpan);
}

/// Places the cells of [table] in a grid using the same rules as HTML.
///
/// The header row (if any) is row 0, followed by the body rows. In each row, going from the left,
/// each cell goes into the first column not blocked by a `rowspan` from an earlier row. Spans that
/// overflow the bottom of the table or the column count are clamped. The result is in cell reading order
/// (header from the left, then body row by row), matching the order of [MdxTable.header] and [MdxTable.rows].
({List<SpanCellPlacement> cells, int rows, int columns}) placeSpanCells(
  MdxTable table,
) {
  final hasHeader = table.header.isNotEmpty;
  final rowCount = table.rows.length + (hasHeader ? 1 : 0);
  final occupied = List.generate(rowCount, (_) => <bool>[]);
  final cells = <SpanCellPlacement>[];

  void place(int row, int cellCount, MdxCellSpan Function(int) spanAt) {
    var column = 0;
    for (var i = 0; i < cellCount; i++) {
      final span = spanAt(i);
      while (column < occupied[row].length && occupied[row][column]) {
        column++;
      }
      final rowSpan = math.min(span.rowSpan, rowCount - row);
      final end = column + span.colSpan;
      for (var r = row; r < row + rowSpan; r++) {
        while (occupied[r].length < end) {
          occupied[r].add(false);
        }
        for (var c = column; c < end; c++) {
          occupied[r][c] = true;
        }
      }
      cells.add(
        SpanCellPlacement(
          row: row,
          column: column,
          rowSpan: rowSpan,
          colSpan: span.colSpan,
        ),
      );
      column = end;
    }
  }

  var row = 0;
  if (hasHeader) {
    place(row++, table.header.length, table.headerSpanAt);
  }
  for (var r = 0; r < table.rows.length; r++) {
    place(row++, table.rows[r].length, (i) => table.rowSpanAt(r, i));
  }
  final columns = occupied.fold<int>(0, (m, row) => math.max(m, row.length));
  return (cells: cells, rows: rowCount, columns: columns);
}

/// A table that lays out [children] at the positions in [placements]. The children are in reading order
/// and there must be as many as [placements].
///
/// A column's width is the maximum natural width of the cells that occupy only that column. When
/// a cell spanning several columns is wider, the shortfall is divided equally among the spanned columns. Row heights
/// follow the same idea, with the shortfall added to the last spanned row. (An approximation of CSS table layout.)
class SpanTable extends MultiChildRenderObjectWidget {
  /// Creates a table that lays out [children] at the positions in [placements].
  const SpanTable({
    super.key,
    required this.placements,
    required this.rows,
    required this.columns,
    required this.borderColor,
    required super.children,
  });

  /// The position of each cell. In the same order and count as [children].
  final List<SpanCellPlacement> placements;

  /// The number of rows (including the header).
  final int rows;

  /// The number of columns.
  final int columns;

  /// The color of the cell borders.
  final Color borderColor;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderSpanTable(
    placements: placements,
    rows: rows,
    columns: columns,
    borderColor: borderColor,
    textDirection: Directionality.of(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderSpanTable renderObject) {
    renderObject
      ..placements = placements
      ..rows = rows
      ..columns = columns
      ..borderColor = borderColor
      ..textDirection = Directionality.of(context);
  }
}

class _SpanParentData extends ContainerBoxParentData<RenderBox> {}

/// The result of measuring.
class _Metrics {
  _Metrics(this.columnWidths, this.rowHeights);

  final List<double> columnWidths;
  final List<double> rowHeights;

  double get width => columnWidths.fold(0, (a, b) => a + b);
  double get height => rowHeights.fold(0, (a, b) => a + b);
}

/// The RenderObject that handles layout and painting of [SpanTable].
class RenderSpanTable extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SpanParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SpanParentData> {
  /// Creates it with the same values as the [SpanTable] arguments. [textDirection] is the direction columns are laid out.
  RenderSpanTable({
    required List<SpanCellPlacement> placements,
    required int rows,
    required int columns,
    required Color borderColor,
    required TextDirection textDirection,
  }) : _placements = placements,
       _rows = rows,
       _columns = columns,
       _borderColor = borderColor,
       _textDirection = textDirection;

  List<SpanCellPlacement> _placements;
  set placements(List<SpanCellPlacement> value) {
    if (listEquals(_placements, value)) return;
    _placements = value;
    markNeedsLayout();
  }

  int _rows;
  set rows(int value) {
    if (_rows == value) return;
    _rows = value;
    markNeedsLayout();
  }

  int _columns;
  set columns(int value) {
    if (_columns == value) return;
    _columns = value;
    markNeedsLayout();
  }

  Color _borderColor;
  set borderColor(Color value) {
    if (_borderColor == value) return;
    _borderColor = value;
    markNeedsPaint();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SpanParentData) {
      child.parentData = _SpanParentData();
    }
  }

  List<RenderBox> get _cells {
    final result = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      result.add(child);
      child = childAfter(child);
    }
    return result;
  }

  /// If the number of children does not match placements, the missing / extra ones are ignored.
  int get _count => math.min(_placements.length, childCount);

  /// Adds the shortfall of cells spanning several columns (rows) to the spanned range.
  static void _distribute(
    List<double> sizes,
    int start,
    int span,
    double needed, {
    required bool toLast,
  }) {
    var current = 0.0;
    for (var i = start; i < start + span; i++) {
      current += sizes[i];
    }
    final extra = needed - current;
    if (extra <= 0) return;
    if (toLast) {
      sizes[start + span - 1] += extra;
    } else {
      final share = extra / span;
      for (var i = start; i < start + span; i++) {
        sizes[i] += share;
      }
    }
  }

  double _spanSize(List<double> sizes, int start, int span) {
    var total = 0.0;
    for (var i = start; i < start + span; i++) {
      total += sizes[i];
    }
    return total;
  }

  List<double> _columnWidths() {
    final widths = List<double>.filled(_columns, 0);
    final cells = _cells;
    // Decide the single-column cells first, then add what spanning cells still need.
    for (var pass = 0; pass < 2; pass++) {
      for (var i = 0; i < _count; i++) {
        final p = _placements[i];
        if ((p.colSpan == 1) != (pass == 0)) continue;
        final natural = cells[i].getMaxIntrinsicWidth(double.infinity);
        _distribute(widths, p.column, p.colSpan, natural, toLast: false);
      }
    }
    return widths;
  }

  /// Measures the cell with [layoutChild], fitted to the column width.
  _Metrics _measure(
    Size Function(RenderBox child, BoxConstraints) layoutChild,
  ) {
    final widths = _columnWidths();
    final heights = List<double>.filled(_rows, 0);
    final cells = _cells;
    for (var pass = 0; pass < 2; pass++) {
      for (var i = 0; i < _count; i++) {
        final p = _placements[i];
        if ((p.rowSpan == 1) != (pass == 0)) continue;
        final width = _spanSize(widths, p.column, p.colSpan);
        final size = layoutChild(
          cells[i],
          BoxConstraints(minWidth: width, maxWidth: width),
        );
        _distribute(heights, p.row, p.rowSpan, size.height, toLast: true);
      }
    }
    return _Metrics(widths, heights);
  }

  /// The x of the leading edge of [span] columns starting at column [column]. In RTL, counted from the right edge.
  double _offset(List<double> sizes, int start, int span, double total) {
    final before = _spanSize(sizes, 0, start);
    return _textDirection == TextDirection.rtl
        ? total - before - _spanSize(sizes, start, span)
        : before;
  }

  Offset _cellOffset(_Metrics m, SpanCellPlacement p) => Offset(
    _offset(m.columnWidths, p.column, p.colSpan, m.width),
    _spanSize(m.rowHeights, 0, p.row),
  );

  @override
  void performLayout() {
    final metrics = _measure(
      (child, constraints) =>
          (child..layout(constraints, parentUsesSize: true)).size,
    );
    final cells = _cells;
    for (var i = 0; i < _count; i++) {
      final p = _placements[i];
      final width = _spanSize(metrics.columnWidths, p.column, p.colSpan);
      final height = _spanSize(metrics.rowHeights, p.row, p.rowSpan);
      final child = cells[i];
      child.layout(BoxConstraints.tight(Size(width, height)));
      (child.parentData! as _SpanParentData).offset = _cellOffset(metrics, p);
    }
    // Leftover children that are not placed go at an invisible position.
    for (var i = _count; i < cells.length; i++) {
      cells[i].layout(BoxConstraints.tight(Size.zero));
      (cells[i].parentData! as _SpanParentData).offset = Offset.zero;
    }
    size = constraints.constrain(Size(metrics.width, metrics.height));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final metrics = _measure((child, c) => child.getDryLayout(c));
    return constraints.constrain(Size(metrics.width, metrics.height));
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _Metrics(_columnWidths(), const []).width;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _Metrics(_columnWidths(), const []).width;

  @override
  double computeMinIntrinsicHeight(double width) =>
      _measure((child, c) => child.getDryLayout(c)).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
    if (_count == 0) return;
    // The frame of each cell. Edges of adjacent cells overlap at the same position, so the line looks like one.
    final paint = Paint()
      ..color = _borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final cells = _cells;
    for (var i = 0; i < _count; i++) {
      final child = cells[i];
      final data = child.parentData! as _SpanParentData;
      context.canvas.drawRect((offset + data.offset) & child.size, paint);
    }
  }
}
