import 'package:flutter_markdown_x/src/ir/nodes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copies and freezes inline and block child collections', () {
    final source = <MdxInline>[MdxText('before')];
    final node = MdxParagraph(source);
    final originalHash = node.hashCode;
    source.add(MdxText('after'));

    expect(node.hashCode, originalHash);
    expect(node, MdxParagraph([MdxText('before')]));
    expect(() => node.inlines.add(MdxText('mutate')), throwsUnsupportedError);

    final nested = <MdxInline>[MdxText('nested')];
    final nestedSource = <MdxInline>[MdxStyled(MdxStyleKind.strong, nested)];
    final parent = MdxParagraph(nestedSource);
    final nestedHash = parent.hashCode;
    nested.add(MdxText('changed'));
    expect(parent.hashCode, nestedHash);
    expect(
      parent,
      MdxParagraph([
        MdxStyled(MdxStyleKind.strong, [MdxText('nested')]),
      ]),
    );
  });

  test('freezes table collections at every level', () {
    final alignments = <MdxAlign?>[MdxAlign.center];
    final headerCell = <MdxInline>[MdxText('h')];
    final header = <List<MdxInline>>[headerCell];
    final rowCell = <MdxInline>[MdxText('v')];
    final row = <List<MdxInline>>[rowCell];
    final rows = <List<List<MdxInline>>>[row];
    final table = MdxTable(alignments: alignments, header: header, rows: rows);
    final hash = table.hashCode;

    alignments.add(MdxAlign.left);
    headerCell.add(MdxText('changed'));
    row.add(<MdxInline>[MdxText('extra')]);
    rows.add(<List<MdxInline>>[]);
    expect(table.hashCode, hash);
    expect(
      table,
      MdxTable(
        alignments: [MdxAlign.center],
        header: [
          [MdxText('h')],
        ],
        rows: [
          [
            [MdxText('v')],
          ],
        ],
      ),
    );
    expect(() => table.alignments.add(MdxAlign.right), throwsUnsupportedError);
    expect(() => table.header[0].add(MdxText('x')), throwsUnsupportedError);
    expect(() => table.rows[0][0].add(MdxText('x')), throwsUnsupportedError);
    expect(() => table.rows[0].add(<MdxInline>[]), throwsUnsupportedError);
  });

  group('table span', () {
    MdxTable table({
      List<MdxCellSpan> headerSpans = const [],
      List<List<MdxCellSpan>> rowSpans = const [],
    }) => MdxTable(
      alignments: [null, null],
      header: [
        [MdxText('a')],
        [MdxText('b')],
      ],
      rows: [
        [
          [MdxText('1')],
          [MdxText('2')],
        ],
      ],
      headerSpans: headerSpans,
      rowSpans: rowSpans,
    );

    const one = (colSpan: 1, rowSpan: 1);

    test('default is no span, same as all 1 x 1', () {
      final plain = table();
      expect(plain.hasSpans, isFalse);
      expect(plain.headerSpans, isEmpty);
      expect(plain.rowSpans, isEmpty);
      expect(plain.headerSpanAt(1), one);
      expect(plain.rowSpanAt(0, 1), one);
      // Explicit all 1 x 1 equals no span (canonical form).
      final explicit = table(
        headerSpans: [one, one],
        rowSpans: [
          [one, one],
        ],
      );
      expect(explicit, plain);
      expect(explicit.hashCode, plain.hashCode);
    });

    test('span has value equality and a defensive copy', () {
      final spans = [(colSpan: 2, rowSpan: 1), one];
      final rowSpans = [
        [one, (colSpan: 1, rowSpan: 3)],
      ];
      final spanned = table(headerSpans: spans, rowSpans: rowSpans);
      final hash = spanned.hashCode;
      spans.clear();
      rowSpans[0].clear();
      rowSpans.clear();
      expect(spanned.hashCode, hash);
      expect(spanned.hasSpans, isTrue);
      expect(spanned.headerSpanAt(0), (colSpan: 2, rowSpan: 1));
      expect(spanned.rowSpanAt(0, 1), (colSpan: 1, rowSpan: 3));
      expect(spanned, isNot(table()));
      expect(() => spanned.headerSpans.add(one), throwsUnsupportedError);
      expect(() => spanned.rowSpans[0].add(one), throwsUnsupportedError);
    });

    test('a span omitted per row becomes 1 x 1', () {
      final spanned = table(
        headerSpans: [(colSpan: 2, rowSpan: 1), one],
        rowSpans: [[]],
      );
      expect(spanned.rowSpanAt(0, 0), one);
    });

    test('a span that does not match the cell count is ArgumentError', () {
      expect(() => table(headerSpans: [one]), throwsArgumentError);
      expect(
        () => table(
          rowSpans: [
            [one],
            [one],
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => table(
          rowSpans: [
            [one],
          ],
        ),
        throwsArgumentError,
      );
    });

    test('a span of 0 or less is ArgumentError', () {
      expect(
        () => table(headerSpans: [(colSpan: 0, rowSpan: 1), one]),
        throwsArgumentError,
      );
      expect(
        () => table(headerSpans: [one, (colSpan: 1, rowSpan: -1)]),
        throwsArgumentError,
      );
    });
  });

  test('details open is part of equality', () {
    MdxDetails details({bool open = false}) => MdxDetails(
      summary: [MdxText('s')],
      blocks: [
        MdxParagraph([MdxText('b')]),
      ],
      open: open,
    );
    expect(details().open, isFalse);
    expect(details(open: true).open, isTrue);
    expect(details(open: true), details(open: true));
    expect(details(open: true), isNot(details()));
    expect(details(open: true).hashCode, isNot(details().hashCode));
  });
}
