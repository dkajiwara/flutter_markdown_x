// A small Dart-side IR encoder for verifying the decoder without depending on native.
//
// The format follows `native/src/ir.rs` and `doc/native-abi.md`. Constants are written by
// hand rather than imported from the decoder, so they do not share its misunderstandings.
import 'dart:convert';
import 'dart:typed_data';

/// Bytes of an empty document with the IR header (magic and version).
Uint8List irHeader({int version = 6}) =>
    (IrBuilder()
          ..raw([0x4d, 0x44, 0x58, 0x49])
          ..u32(version))
        .toBytes();

final class IrBuilder {
  final _bytes = BytesBuilder();

  void raw(List<int> bytes) => _bytes.add(bytes);

  void u8(int value) => _bytes.addByte(value);

  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    _bytes.add(data.buffer.asUint8List());
  }

  void f64(double value) {
    final data = ByteData(8)..setFloat64(0, value, Endian.little);
    _bytes.add(data.buffer.asUint8List());
  }

  void optionalF64(double? value) => f64(value ?? double.nan);

  void string(String value) {
    final encoded = utf8.encode(value);
    u32(encoded.length);
    raw(encoded);
  }

  void optionalString(String? value) {
    if (value == null) {
      u8(0);
    } else {
      u8(1);
      string(value);
    }
  }

  /// A table cell: its spans, and a list of inlines with a single text.
  void tableCell(String text, {int colSpan = 1, int rowSpan = 1}) {
    u32(colSpan);
    u32(rowSpan);
    u32(1);
    u8(0);
    string(text);
  }

  Uint8List toBytes() => _bytes.toBytes();
}

/// IR of a document containing at least one node of every kind (with header).
///
/// Corresponds to the nodes returned by [buildExpectedBlocks] (test side).
Uint8List encodeSampleDocument() {
  final b = IrBuilder()
    ..raw([0x4d, 0x44, 0x58, 0x49])
    ..u32(6)
    ..u32(9); // number of top-level blocks

  // 0: paragraph (center) [text, line break, styled(strong, text), soft break,
  // styled(cite, text), titled(abbreviation, 't', text), titled(acronym, none, text)]
  b
    ..u8(0)
    ..u8(2)
    ..u32(7)
    ..u8(0)
    ..string('héllo 🎉')
    ..u8(1)
    ..u8(2)
    ..u8(0)
    ..u32(1)
    ..u8(0)
    ..string('b')
    ..u8(6)
    ..u8(2)
    ..u8(10)
    ..u32(1)
    ..u8(0)
    ..string('c')
    ..u8(7)
    ..u8(16)
    ..optionalString('t')
    ..u32(1)
    ..u8(0)
    ..string('a')
    ..u8(7)
    ..u8(17)
    ..optionalString(null)
    ..u32(1)
    ..u8(0)
    ..string('n');

  // 1: heading level 3, align none, [link, image, span]
  b
    ..u8(1)
    ..u8(3)
    ..u8(0)
    ..u32(3)
    ..u8(3)
    ..string('https://e.com')
    ..optionalString('T')
    ..u32(1)
    ..u8(0)
    ..string('l')
    ..u8(4)
    ..string('a.png')
    ..optionalString('alt')
    ..optionalString(null)
    ..optionalF64(10)
    ..optionalF64(null)
    ..u8(5)
    ..u8(0x01 | 0x04)
    ..u32(0xff112233)
    ..u32(0)
    ..optionalF64(12.5)
    ..u32(1)
    ..u8(0)
    ..string('s');

  // 2: code block
  b
    ..u8(2)
    ..string('final a = 1;')
    ..optionalString('dart')
    ..optionalString('{1,3} title="x"');

  // 3: blockquote [paragraph]
  b
    ..u8(3)
    ..u32(1)
    ..u8(0)
    ..u8(0)
    ..u32(1)
    ..u8(0)
    ..string('q');

  // 4: loose ordered list start 3, items: [checked true at byte 2, paragraph], [none, rule]
  b
    ..u8(4)
    ..u8(1)
    ..u32(3)
    ..u8(0) // tight = false
    ..u32(2)
    ..u8(2)
    ..u32(2) // marker byte offset (a task item only)
    ..u32(1)
    ..u8(0)
    ..u8(0)
    ..u32(0)
    ..u8(0)
    ..u32(1)
    ..u8(6);

  // 5: table: alignments [left, none, right]。
  // header is [a (colspan 2), c]; rows are [1 (rowspan 2), 2, 3] and [4, 5].
  b
    ..u8(5)
    ..u32(3)
    ..u8(1)
    ..u8(0)
    ..u8(3)
    ..u32(2)
    ..tableCell('a', colSpan: 2)
    ..tableCell('c')
    ..u32(2)
    ..u32(3)
    ..tableCell('1', rowSpan: 2)
    ..tableCell('2')
    ..tableCell('3')
    ..u32(2)
    ..tableCell('4')
    ..tableCell('5');

  // 6: thematic break
  b.u8(6);

  // 7: details (open)
  b
    ..u8(7)
    ..u8(1)
    ..u32(1)
    ..u8(0)
    ..string('sum')
    ..u32(1)
    ..u8(0)
    ..u8(0)
    ..u32(0);

  // 8: custom block 'media' {kind: video, src: a.mp4}, inlines [link], blocks [rule]
  b
    ..u8(8)
    ..string('media')
    ..u32(2)
    ..string('kind')
    ..string('video')
    ..string('src')
    ..string('a.mp4')
    ..u32(1)
    ..u8(3)
    ..string('a.mp4')
    ..optionalString(null)
    ..u32(1)
    ..u8(0)
    ..string('a.mp4')
    ..u32(1)
    ..u8(6);
  return b.toBytes();
}
