// The binary IR decoder must reject malformed input with MdxIrFormatException only.
// Does not depend on the native binary (uses the Dart-side encoder).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_markdown_x/src/parser/native/ir_decoder.dart';
import 'package:flutter_markdown_x/src/ir/nodes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ir_encoder.dart';

final _throwsIrFormat = throwsA(isA<MdxIrFormatException>());

List<MdxBlock> _expectedSample() => [
  MdxParagraph([
    MdxText('héllo 🎉'),
    MdxLineBreak(),
    MdxStyled(MdxStyleKind.strong, [MdxText('b')]),
    MdxSoftBreak(),
    MdxStyled(MdxStyleKind.cite, [MdxText('c')]),
    MdxStyled(MdxStyleKind.abbreviation, [MdxText('a')], title: 't'),
    MdxStyled(MdxStyleKind.acronym, [MdxText('n')]),
  ], align: MdxAlign.center),
  MdxHeading(3, [
    MdxLink(href: 'https://e.com', title: 'T', children: [MdxText('l')]),
    MdxImage(src: 'a.png', alt: 'alt', width: 10),
    MdxSpan(MdxInlineStyle(color: 0xff112233, fontSize: 12.5, bold: true), [
      MdxText('s'),
    ]),
  ]),
  MdxCodeBlock('final a = 1;', language: 'dart', info: '{1,3} title="x"'),
  MdxBlockquote([
    MdxParagraph([MdxText('q')]),
  ]),
  MdxList(
    ordered: true,
    start: 3,
    tight: false,
    items: [
      MdxListItem([MdxParagraph(const [])], checked: true),
      MdxListItem([MdxThematicBreak()]),
    ],
  ),
  MdxTable(
    alignments: [MdxAlign.left, null, MdxAlign.right],
    header: [
      [MdxText('a')],
      [MdxText('c')],
    ],
    rows: [
      [
        [MdxText('1')],
        [MdxText('2')],
        [MdxText('3')],
      ],
      [
        [MdxText('4')],
        [MdxText('5')],
      ],
    ],
    headerSpans: [(colSpan: 2, rowSpan: 1), (colSpan: 1, rowSpan: 1)],
    rowSpans: [
      [
        (colSpan: 1, rowSpan: 2),
        (colSpan: 1, rowSpan: 1),
        (colSpan: 1, rowSpan: 1),
      ],
      [],
    ],
  ),
  MdxThematicBreak(),
  MdxDetails(
    summary: [MdxText('sum')],
    blocks: [MdxParagraph(const [])],
    open: true,
  ),
  MdxCustomBlock(
    'media',
    attributes: {'kind': 'video', 'src': 'a.mp4'},
    inlines: [
      MdxLink(href: 'a.mp4', children: [MdxText('a.mp4')]),
    ],
    blocks: [MdxThematicBreak()],
  ),
];

/// Decodes [bytes]; returns null on success, or the exception for MdxIrFormatException.
/// Any other exception or error is rethrown as is (fails the test).
MdxIrFormatException? _tryDecode(Uint8List bytes) {
  try {
    decodeIr(bytes);
    return null;
  } on MdxIrFormatException catch (e) {
    return e;
  }
}

Uint8List _withByte(Uint8List source, int index, int value) =>
    Uint8List.fromList(source)..[index] = value;

void main() {
  final sample = encodeSampleDocument();

  group('valid input', () {
    test('restores the sample document', () {
      expect(decodeIr(sample), _expectedSample());
    });

    test('a header-only document with 0 blocks is empty', () {
      final bytes = Uint8List.fromList([...irHeader(), 0, 0, 0, 0]);
      expect(decodeIr(bytes), isEmpty);
    });

    test('reads a view with a nonzero offset', () {
      final padded = Uint8List(sample.length + 7)..setAll(3, sample);
      expect(
        decodeIr(Uint8List.sublistView(padded, 3, 3 + sample.length)),
        _expectedSample(),
      );
    });
  });

  group('task markers (IR v5)', () {
    // A list with one item each: unchecked at byte `a`, checked at byte `b`, and a plain one.
    Uint8List list(List<(int, int?)> items) {
      final b = IrBuilder()
        ..raw([0x4d, 0x44, 0x58, 0x49])
        ..u32(6)
        ..u32(1)
        ..u8(4)
        ..u8(0)
        ..u32(1)
        ..u8(1)
        ..u32(items.length);
      for (final (state, offset) in items) {
        b.u8(state);
        if (offset != null) b.u32(offset);
        b.u32(0);
      }
      return b.toBytes();
    }

    MdxListItem item(List<MdxBlock> blocks, int index) =>
        (blocks.single as MdxList).items[index];

    test('a task item carries its marker offset, converted to UTF-16', () {
      // "é" is 2 bytes and "😀" is 4 bytes (2 UTF-16 units).
      const source = 'é😀\n- [ ] a\n- [x] b';
      final first = utf8.encode('é😀\n- ').length;
      final second = utf8.encode('é😀\n- [ ] a\n- ').length;
      final bytes = list([(1, first), (2, second), (0, null)]);
      final blocks = decodeIr(bytes, source: source);
      expect(item(blocks, 0).checked, isFalse);
      expect(item(blocks, 0).markerOffset, source.indexOf('[ ]'));
      expect(item(blocks, 1).checked, isTrue);
      expect(item(blocks, 1).markerOffset, source.indexOf('[x]'));
      expect(item(blocks, 2).markerOffset, isNull);
    });

    test('offsets are not part of equality', () {
      const source = '- [ ] a\n\n\n- [ ] a';
      final a = item(decodeIr(list([(1, 2)]), source: source), 0);
      final b = item(decodeIr(list([(1, 12)]), source: source), 0);
      expect(a.markerOffset, isNot(b.markerOffset));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('without the source the offset is not exposed', () {
      expect(item(decodeIr(list([(1, 2)])), 0).markerOffset, isNull);
    });

    test('rejects an offset that does not point at a bracket', () {
      const source = '- [ ] a';
      expect(() => decodeIr(list([(1, 3)]), source: source), _throwsIrFormat);
    });

    test('rejects an offset that leaves no room for the marker', () {
      const source = '- [ ] a';
      expect(
        () => decodeIr(list([(1, source.length - 1)]), source: source),
        _throwsIrFormat,
      );
      expect(() => decodeIr(list([(1, 100)]), source: source), _throwsIrFormat);
    });

    test('rejects an offset inside a multi-byte character', () {
      const source = '😀[ ] a';
      expect(() => decodeIr(list([(1, 2)]), source: source), _throwsIrFormat);
    });

    test('a truncated offset is an error', () {
      final bytes = list([(1, 2)]);
      expect(
        () => decodeIr(Uint8List.sublistView(bytes, 0, bytes.length - 6)),
        _throwsIrFormat,
      );
    });

    test('rewriting any byte never leaks a non-format error', () {
      const source = '- [ ] a\n- [x] b';
      final bytes = list([(1, 2), (2, 10)]);
      for (var index = 0; index < bytes.length; index++) {
        for (var value = 0; value < 256; value++) {
          try {
            decodeIr(_withByte(bytes, index, value), source: source);
          } on MdxIrFormatException {
            // expected
          }
        }
      }
    });
  });

  group('custom block (IR v6)', () {
    Uint8List custom(
      String type,
      List<(String, String)> attributes, {
      int? attributeCount,
    }) {
      final b = IrBuilder()
        ..raw(irHeader())
        ..u32(1)
        ..u8(8)
        ..string(type)
        ..u32(attributeCount ?? attributes.length);
      for (final (key, value) in attributes) {
        b
          ..string(key)
          ..string(value);
      }
      return (b
            ..u32(0)
            ..u32(0))
          .toBytes();
    }

    test('restores type and attributes in order', () {
      final block =
          decodeIr(custom('media', [('src', 'a'), ('kind', 'audio')])).single
              as MdxCustomBlock;
      expect(block.type, 'media');
      expect(block.attributes, {'src': 'a', 'kind': 'audio'});
      expect(block.attributes.keys, ['src', 'kind']);
      expect(block.inlines, isEmpty);
      expect(block.blocks, isEmpty);
    });

    test('rejects a duplicate attribute name', () {
      expect(
        () => decodeIr(custom('media', [('src', 'a'), ('src', 'b')])),
        _throwsIrFormat,
      );
    });

    test('rejects an empty type', () {
      expect(() => decodeIr(custom('', [])), _throwsIrFormat);
    });

    test('rejects an attribute count beyond the remaining bytes', () {
      expect(
        () => decodeIr(custom('media', [], attributeCount: 1000)),
        _throwsIrFormat,
      );
    });
  });

  group('header', () {
    test('empty input', () {
      expect(() => decodeIr(Uint8List(0)), _throwsIrFormat);
    });

    test('wrong magic', () {
      expect(() => decodeIr(_withByte(sample, 0, 0x58)), _throwsIrFormat);
      expect(
        () =>
            decodeIr(Uint8List.fromList([0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0])),
        _throwsIrFormat,
      );
    });

    test('wrong IR version', () {
      expect(() => decodeIr(_withByte(sample, 4, 1)), _throwsIrFormat);
      expect(() => decodeIr(_withByte(sample, 4, 2)), _throwsIrFormat);
      expect(() => decodeIr(_withByte(sample, 4, 3)), _throwsIrFormat);
      expect(() => decodeIr(_withByte(sample, 4, 4)), _throwsIrFormat);
      expect(() => decodeIr(_withByte(sample, 4, 5)), _throwsIrFormat);
      expect(() => decodeIr(_withByte(sample, 4, 0)), _throwsIrFormat);
      expect(() => decodeIr(_withByte(sample, 7, 1)), _throwsIrFormat);
    });

    test('version message includes expected and actual values', () {
      final error = _tryDecode(_withByte(sample, 4, 9));
      expect(error, isNotNull);
      expect(error!.message, contains('9'));
      expect(error.message, contains('$mdxIrVersion'));
    });
  });

  group('truncation', () {
    test('every prefix raises MdxIrFormatException', () {
      for (var length = 0; length < sample.length; length++) {
        expect(
          () => decodeIr(Uint8List.sublistView(sample, 0, length)),
          _throwsIrFormat,
          reason: 'prefix $length/${sample.length}',
        );
      }
    });

    test('exception carries the offset', () {
      final error = _tryDecode(Uint8List.sublistView(sample, 0, 20));
      expect(error, isNotNull);
      expect(error!.offset, isNotNull);
      expect(error.offset, inInclusiveRange(0, 20));
    });
  });

  group('corruption', () {
    test(
      'rewriting any byte yields either MdxIrFormatException or success',
      () {
        for (var index = 0; index < sample.length; index++) {
          for (var value = 0; value < 256; value++) {
            // _tryDecode accepts only MdxIrFormatException.
            // A leaked RangeError or similar fails the test here.
            _tryDecode(_withByte(sample, index, value));
          }
        }
      },
    );

    test('rejects extra trailing bytes', () {
      expect(
        () => decodeIr(Uint8List.fromList([...sample, 0])),
        _throwsIrFormat,
      );
      expect(
        () => decodeIr(Uint8List.fromList([...sample, ...sample])),
        _throwsIrFormat,
      );
    });

    test('rejects a huge count without allocating', () {
      final huge = Uint8List.fromList([...irHeader(), 255, 255, 255, 255]);
      final stopwatch = Stopwatch()..start();
      expect(() => decodeIr(huge), _throwsIrFormat);
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test('rejects a count larger than the remaining bytes', () {
      // Block count is 2, but there is only one block.
      final bytes = Uint8List.fromList([...irHeader(), 2, 0, 0, 0, 6]);
      expect(() => decodeIr(bytes), _throwsIrFormat);
    });

    test('unknown block tag', () {
      final bytes = Uint8List.fromList([...irHeader(), 1, 0, 0, 0, 99]);
      expect(() => decodeIr(bytes), _throwsIrFormat);
    });

    test('unknown inline tag', () {
      final bytes = Uint8List.fromList([
        ...irHeader(), 1, 0, 0, 0, // 1 block
        0, 0, 1, 0, 0, 0, 99, // paragraph, align none, 1 inline, tag 99
      ]);
      expect(() => decodeIr(bytes), _throwsIrFormat);
    });

    test('style kind beyond the last value', () {
      final bytes = Uint8List.fromList([
        ...irHeader(), 1, 0, 0, 0, //
        0, 0, 1, 0, 0, 0, 2, 18, 0, 0, 0, 0, // styled, kind 18, no children
      ]);
      expect(() => decodeIr(bytes), _throwsIrFormat);
    });

    test('titled inline accepts only abbreviation and acronym kinds', () {
      Uint8List titled(int kind) => Uint8List.fromList([
        ...irHeader(), 1, 0, 0, 0, //
        0,
        0,
        1,
        0,
        0,
        0,
        7,
        kind,
        0,
        0,
        0,
        0,
        0, // titled, no title, no children
      ]);
      expect(decodeIr(titled(16)), isNotEmpty);
      expect(decodeIr(titled(17)), isNotEmpty);
      expect(() => decodeIr(titled(0)), _throwsIrFormat);
      expect(() => decodeIr(titled(10)), _throwsIrFormat);
      expect(() => decodeIr(titled(18)), _throwsIrFormat);
    });

    test('plain styled inline rejects the titled kinds', () {
      for (final kind in [16, 17]) {
        final bytes = Uint8List.fromList([
          ...irHeader(), 1, 0, 0, 0, //
          0, 0, 1, 0, 0, 0, 2, kind, 0, 0, 0, 0, //
        ]);
        expect(() => decodeIr(bytes), _throwsIrFormat);
      }
    });

    test('out-of-range align', () {
      final bytes = Uint8List.fromList([
        ...irHeader(), 1, 0, 0, 0, //
        0, 4, 0, 0, 0, 0, // paragraph, align 4
      ]);
      expect(() => decodeIr(bytes), _throwsIrFormat);
    });

    test('out-of-range heading level', () {
      for (final level in [0, 7, 255]) {
        final bytes = Uint8List.fromList([
          ...irHeader(), 1, 0, 0, 0, //
          1, level, 0, 0, 0, 0, 0,
        ]);
        expect(() => decodeIr(bytes), _throwsIrFormat, reason: 'level $level');
      }
    });

    test('out-of-range MdxStyleKind', () {
      final bytes = Uint8List.fromList([
        ...irHeader(), 1, 0, 0, 0, //
        0, 0, 1, 0, 0, 0, // paragraph, 1 inline
        2, MdxStyleKind.values.length, 0, 0, 0, 0,
      ]);
      expect(() => decodeIr(bytes), _throwsIrFormat);
    });

    test('out-of-range checked, and bool/presence bytes', () {
      // list: ordered=2 is invalid.
      final badOrdered = Uint8List.fromList([
        ...irHeader(), 1, 0, 0, 0, //
        4, 2, 1, 0, 0, 0, 1, 0, 0, 0, 0,
      ]);
      expect(() => decodeIr(badOrdered), _throwsIrFormat);
      // list item: checked=3 is invalid.
      final badChecked = Uint8List.fromList([
        ...irHeader(), 1, 0, 0, 0, //
        4, 0, 1, 0, 0, 0, 1, 1, 0, 0, 0, 3, 0, 0, 0, 0,
      ]);
      expect(() => decodeIr(badChecked), _throwsIrFormat);
      // code block: language presence flag of 2 is invalid.
      final badPresence = Uint8List.fromList([
        ...irHeader(), 1, 0, 0, 0, //
        2, 0, 0, 0, 0, 2, 0,
      ]);
      expect(() => decodeIr(badPresence), _throwsIrFormat);
    });

    test('table cell span is between 1 and mdxMaxCellSpan', () {
      Uint8List table(int colSpan, int rowSpan) {
        final b = IrBuilder()
          ..raw(irHeader())
          ..u32(1)
          ..u8(5) // table
          ..u32(1)
          ..u8(0) // one alignment
          ..u32(1) // one header cell
          ..u32(colSpan)
          ..u32(rowSpan)
          ..u32(0) // no inlines
          ..u32(0); // no rows
        return b.toBytes();
      }

      expect(decodeIr(table(1, 1)), hasLength(1));
      expect(decodeIr(table(mdxMaxCellSpan, mdxMaxCellSpan)), hasLength(1));
      for (final (colSpan, rowSpan) in [
        (0, 1),
        (1, 0),
        (mdxMaxCellSpan + 1, 1),
        (1, mdxMaxCellSpan + 1),
        (0xffffffff, 1),
      ]) {
        expect(
          () => decodeIr(table(colSpan, rowSpan)),
          _throwsIrFormat,
          reason: 'span $colSpan x $rowSpan',
        );
      }
    });

    test('soft break is tag 6 with no payload', () {
      final bytes = Uint8List.fromList([
        ...irHeader(), 1, 0, 0, 0, //
        0, 0, 3, 0, 0, 0, // paragraph, 3 inlines
        0, 1, 0, 0, 0, 97, // text "a"
        6, // soft break
        0, 1, 0, 0, 0, 98, // text "b"
      ]);
      expect(decodeIr(bytes), [
        MdxParagraph([MdxText('a'), MdxSoftBreak(), MdxText('b')]),
      ]);
      // A payload byte after the tag is read as the next inline, so it is an
      // unknown tag here.
      final extra = Uint8List.fromList([
        ...irHeader(), 1, 0, 0, 0, //
        0, 0, 1, 0, 0, 0, 6, 9,
      ]);
      expect(() => decodeIr(extra), _throwsIrFormat);
    });

    test('list tight is a bool after start', () {
      Uint8List list(int tight) => Uint8List.fromList([
        ...irHeader(), 1, 0, 0, 0, //
        4, 0, 1, 0, 0, 0, tight, 0, 0, 0, 0,
      ]);
      expect(decodeIr(list(1)), [MdxList(ordered: false, items: const [])]);
      expect(decodeIr(list(0)), [
        MdxList(ordered: false, tight: false, items: const []),
      ]);
      expect(() => decodeIr(list(2)), _throwsIrFormat);
      expect(() => decodeIr(list(255)), _throwsIrFormat);
    });

    test('code block info is an optional string after the language', () {
      Uint8List code(List<int> info) => Uint8List.fromList([
        ...irHeader(), 1, 0, 0, 0, //
        2, 0, 0, 0, 0, 0, ...info, // empty code, no language
      ]);
      expect(decodeIr(code([0])), [MdxCodeBlock('')]);
      expect(decodeIr(code([1, 1, 0, 0, 0, 120])), [
        MdxCodeBlock('', info: 'x'),
      ]);
      expect(() => decodeIr(code([2])), _throwsIrFormat);
      // Presence says a string follows, but the bytes end (truncation).
      expect(() => decodeIr(code([1])), _throwsIrFormat);
      expect(() => decodeIr(code([1, 5, 0, 0, 0, 120])), _throwsIrFormat);
      // Info is read as UTF-8.
      expect(() => decodeIr(code([1, 1, 0, 0, 0, 0xc3])), _throwsIrFormat);
    });

    test('details open is a bool', () {
      Uint8List details(int open) => Uint8List.fromList([
        ...irHeader(), 1, 0, 0, 0, //
        7, open, 0, 0, 0, 0, 0, 0, 0, 0,
      ]);
      expect(decodeIr(details(1)), [
        MdxDetails(summary: const [], blocks: const [], open: true),
      ]);
      expect(decodeIr(details(0)), [
        MdxDetails(summary: const [], blocks: const []),
      ]);
      expect(() => decodeIr(details(2)), _throwsIrFormat);
    });

    test('undefined flag bit on span', () {
      final bytes = Uint8List.fromList([
        ...irHeader(), 1, 0, 0, 0, //
        0, 0, 1, 0, 0, 0, // paragraph, 1 inline
        5, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, //
        0, 0, 0, 0, 0, 0, 0xf8, 0x7f, 0, 0, 0, 0,
      ]);
      expect(() => decodeIr(bytes), _throwsIrFormat);
    });

    test('invalid UTF-8', () {
      final bytes = Uint8List.fromList([
        ...irHeader(), 1, 0, 0, 0, //
        2, 2, 0, 0, 0, 0xc3, 0x28, 0, 0, // code: "\xc3(" is invalid
      ]);
      final error = _tryDecode(bytes);
      expect(error, isNotNull);
    });

    test('string length exceeds the remainder', () {
      final bytes = Uint8List.fromList([
        ...irHeader(), 1, 0, 0, 0, //
        2, 0xff, 0xff, 0xff, 0x7f, 65,
      ]);
      expect(() => decodeIr(bytes), _throwsIrFormat);
    });

    test('nesting depth the Dart parser handles can be decoded', () {
      // A fixed limit would make documents that Dart can render fail only on native.
      final deep = BytesBuilder();
      deep.add(irHeader());
      const depth = 2000;
      deep.add([1, 0, 0, 0]);
      for (var i = 0; i < depth; i++) {
        deep.add([3, 1, 0, 0, 0]);
      }
      deep.add([6]);
      expect(decodeIr(deep.toBytes()), hasLength(1));
    });

    test('too-deep nesting is rejected, not a StackOverflowError', () {
      final deep = BytesBuilder();
      deep.add(irHeader());
      const depth = 100000;
      deep.add([1, 0, 0, 0]);
      for (var i = 0; i < depth; i++) {
        deep.add([3, 1, 0, 0, 0]); // blockquote holds 1 block
      }
      deep.add([6]);
      expect(() => decodeIr(deep.toBytes()), _throwsIrFormat);
    });
  });
}
