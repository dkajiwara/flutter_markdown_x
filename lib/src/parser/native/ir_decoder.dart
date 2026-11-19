/// Reads the binary IR returned by the native parser.
///
/// The format corresponds to `native/src/ir.rs`. Change both together.
/// See `doc/native-abi.md` for the spec and the versioning policy.
///
/// The input is not trusted. Corruption, truncation, unknown tags, out-of-range values, invalid UTF-8,
/// and leftover unread bytes all become [MdxIrFormatException]; `RangeError` and the like never leak out.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../ir/nodes.dart';

/// The magic at the start of the IR (ASCII `MDXI`).
const _magic = <int>[0x4d, 0x44, 0x58, 0x49];

/// The version of the binary IR format this decoder can read.
///
/// Keep in sync with Rust's `ir::IR_VERSION`. Bump it when the format changes.
const mdxIrVersion = 6;

/// The native C ABI version this package expects.
///
/// Keep in sync with Rust's `ABI_VERSION` (`mdx_abi_version()`).
const expectedMdxAbiVersion = 2;

/// The range of heading levels.
const _minHeadingLevel = 1;
const _maxHeadingLevel = 6;

/// The defined bits among the span flags.
const _styleFlagMask =
    _styleHasColor |
    _styleHasBackground |
    _styleBold |
    _styleItalic |
    _styleUnderline |
    _styleStrikethrough;

// Block tags.
const _blockParagraph = 0;
const _blockHeading = 1;
const _blockCode = 2;
const _blockQuote = 3;
const _blockList = 4;
const _blockTable = 5;
const _blockRule = 6;
const _blockDetails = 7;
const _blockCustom = 8;

// Inline tags.
const _inlineText = 0;
const _inlineLineBreak = 1;
const _inlineStyled = 2;
const _inlineLink = 3;
const _inlineImage = 4;
const _inlineSpan = 5;
const _inlineSoftBreak = 6;
const _inlineTitled = 7;

/// The style kinds written as a titled inline (and only those).
const _titledKinds = {MdxStyleKind.abbreviation, MdxStyleKind.acronym};

// Inline style flags. A color is meaningful only when its flag is set.
const _styleHasColor = 1 << 0;
const _styleHasBackground = 1 << 1;
const _styleBold = 1 << 2;
const _styleItalic = 1 << 3;
const _styleUnderline = 1 << 4;
const _styleStrikethrough = 1 << 5;

// The state of a task list item.
const _checkedNone = 0;
const _checkedTrue = 2;
const _checkedMax = 2;

/// Mapping from the binary representation of alignment (0 means unspecified) to [MdxAlign].
const _aligns = <MdxAlign?>[
  null,
  MdxAlign.left,
  MdxAlign.center,
  MdxAlign.right,
];

const _u32Size = 4;
const _f64Size = 8;

/// Thrown when the binary IR is invalid.
///
/// [offset] is the position in the bytes where the problem was found (0 is the start of the header).
final class MdxIrFormatException extends FormatException {
  /// Creates the exception from [message] and the problem position [offset].
  MdxIrFormatException(String message, int offset)
    : super(message, null, offset);

  @override
  String toString() => 'MdxIrFormatException: $message (offset $offset)';
}

/// Restores [bytes] (IR with a header) to a list of blocks.
///
/// Throws [MdxIrFormatException] on invalid input. It throws no other exceptions.
///
/// A task list item carries the UTF-8 byte offset of its marker in the parsed text. With
/// [source] (the text that was parsed) the offset is validated (the marker must fit in the
/// text, start on a character boundary at a `[`) and converted to a UTF-16 offset for
/// [MdxListItem.markerOffset]. Without [source] it is not exposed (null).
List<MdxBlock> decodeIr(Uint8List bytes, {String? source}) {
  final reader = _Reader(bytes, source)..header();
  try {
    final blocks = reader.blocks();
    reader.expectEnd();
    return blocks;
    // No fixed limit is placed on nesting depth. Documents at a depth the parser accepted
    // can be decoded, and only exhausting the stack becomes a format error.
    // ignore: avoid_catching_errors
  } on StackOverflowError {
    throw MdxIrFormatException(
      'nesting is too deep to decode',
      reader.position,
    );
  }
}

/// The length in bytes of a task marker (`[ ]`).
const _markerLength = 3;

/// Converts UTF-8 byte offsets into [_source] to UTF-16 offsets. Moving forward is cheap:
/// the position of the last conversion is kept, and only a backward request starts over.
final class _ByteOffsets {
  _ByteOffsets(this._source);

  final String _source;
  int _byte = 0;
  int _unit = 0;

  /// The UTF-16 offset of the character that starts at [byteOffset], or null when it is
  /// beyond the text or inside a character.
  int? unitOf(int byteOffset) {
    if (byteOffset < _byte) {
      _byte = 0;
      _unit = 0;
    }
    final length = _source.length;
    while (_byte < byteOffset && _unit < length) {
      final unit = _source.codeUnitAt(_unit);
      if (unit < 0x80) {
        _byte += 1;
        _unit += 1;
      } else if (unit < 0x800) {
        _byte += 2;
        _unit += 1;
      } else if (unit >= 0xD800 &&
          unit <= 0xDBFF &&
          _unit + 1 < length &&
          _isLowSurrogate(_source.codeUnitAt(_unit + 1))) {
        _byte += 4;
        _unit += 2;
      } else {
        // The rest of the BMP, and a lone surrogate (encoded as U+FFFD).
        _byte += 3;
        _unit += 1;
      }
    }
    return _byte == byteOffset && _unit < length ? _unit : null;
  }

  static bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
}

final class _Reader {
  _Reader(this._bytes, String? source)
    : _data = ByteData.sublistView(_bytes),
      _offsets = source == null ? null : _ByteOffsets(source),
      _source = source;

  final Uint8List _bytes;
  final _ByteOffsets? _offsets;
  final String? _source;
  final ByteData _data;
  int _position = 0;

  int get position => _position;

  int get _remaining => _bytes.length - _position;

  MdxIrFormatException _error(String message, [int? offset]) =>
      MdxIrFormatException(message, offset ?? _position);

  /// Checks that the next [count] bytes can be read.
  void _need(int count) {
    if (count > _remaining) {
      throw _error('truncated: need $count byte(s), $_remaining left');
    }
  }

  void header() {
    _need(_magic.length + _u32Size);
    for (var i = 0; i < _magic.length; i++) {
      if (_bytes[i] != _magic[i]) {
        throw _error('bad magic (not an MDXI binary IR)', i);
      }
    }
    _position = _magic.length;
    final version = _u32();
    if (version != mdxIrVersion) {
      throw _error(
        'unsupported IR version $version (expected $mdxIrVersion)',
        _magic.length,
      );
    }
  }

  void expectEnd() {
    if (_remaining != 0) {
      throw _error('$_remaining trailing byte(s) after the document');
    }
  }

  int _u8() {
    _need(1);
    return _bytes[_position++];
  }

  int _u32() {
    _need(_u32Size);
    final value = _data.getUint32(_position, Endian.little);
    _position += _u32Size;
    return value;
  }

  /// Reads the length of a sequence. Each element takes at least 1 byte, so a count larger than
  /// the remaining byte count is rejected as corruption before allocating.
  int _count() {
    final at = _position;
    final count = _u32();
    if (count > _remaining) {
      throw _error(
        'count $count exceeds the $_remaining remaining byte(s)',
        at,
      );
    }
    return count;
  }

  /// Reads a value from 0 to [limit] inclusive.
  int _enum(String what, int limit) {
    final value = _u8();
    if (value > limit) {
      throw _error('invalid $what $value', _position - 1);
    }
    return value;
  }

  bool _bool(String what) => _enum(what, 1) == 1;

  MdxAlign? _align() => _aligns[_enum('align', _aligns.length - 1)];

  /// An omitted number is represented as NaN.
  double? _optionalF64() {
    _need(_f64Size);
    final value = _data.getFloat64(_position, Endian.little);
    _position += _f64Size;
    return value.isNaN ? null : value;
  }

  String _string() {
    final length = _u32();
    _need(length);
    final start = _position;
    _position += length;
    try {
      return utf8.decode(Uint8List.sublistView(_bytes, start, _position));
    } on FormatException {
      throw _error('invalid UTF-8 in string', start);
    }
  }

  String? _optionalString() => _bool('presence flag') ? _string() : null;

  List<MdxBlock> blocks() =>
      List.generate(_count(), (_) => _block(), growable: false);

  List<MdxInline> _inlines() =>
      List.generate(_count(), (_) => _inline(), growable: false);

  /// One table row. Each cell is followed by its colspan, rowspan and inline sequence.
  ({List<List<MdxInline>> cells, List<MdxCellSpan> spans}) _cells() {
    final spans = <MdxCellSpan>[];
    final cells = List.generate(_count(), (_) {
      spans.add((colSpan: _span('colspan'), rowSpan: _span('rowspan')));
      return _inlines();
    }, growable: false);
    return (cells: cells, spans: spans);
  }

  int _span(String what) {
    final at = _position;
    final value = _u32();
    if (value < 1 || value > mdxMaxCellSpan) {
      throw _error('invalid $what $value (1..$mdxMaxCellSpan)', at);
    }
    return value;
  }

  /// Reads the byte offset of a task marker. With the source, validates it and returns the UTF-16 offset.
  int? _marker() {
    final at = _position;
    final byteOffset = _u32();
    final offsets = _offsets;
    final source = _source;
    if (offsets == null || source == null) return null;
    final unit = offsets.unitOf(byteOffset);
    if (unit == null ||
        unit + _markerLength > source.length ||
        source.codeUnitAt(unit) != 0x5B ||
        source.codeUnitAt(unit + _markerLength - 1) != 0x5D) {
      throw _error('invalid task marker offset $byteOffset', at);
    }
    return unit;
  }

  MdxBlock _block() => _readBlock();

  MdxInline _inline() => _readInline();

  MdxBlock _readBlock() {
    final tagAt = _position;
    final tag = _u8();
    switch (tag) {
      case _blockParagraph:
        final align = _align();
        return MdxParagraph(_inlines(), align: align);
      case _blockHeading:
        final level = _u8();
        if (level < _minHeadingLevel || level > _maxHeadingLevel) {
          throw _error('invalid heading level $level', _position - 1);
        }
        final align = _align();
        return MdxHeading(level, _inlines(), align: align);
      case _blockCode:
        final code = _string();
        final language = _optionalString();
        return MdxCodeBlock(code, language: language, info: _optionalString());
      case _blockQuote:
        return MdxBlockquote(blocks());
      case _blockList:
        final ordered = _bool('ordered flag');
        final start = _u32();
        final tight = _bool('tight flag');
        return MdxList(
          ordered: ordered,
          start: start,
          tight: tight,
          items: List.generate(_count(), (_) {
            final checked = _enum('checked state', _checkedMax);
            // A task item carries the byte offset of its marker.
            final markerOffset = checked == _checkedNone ? null : _marker();
            return MdxListItem(
              blocks(),
              checked: checked == _checkedNone ? null : checked == _checkedTrue,
              markerOffset: markerOffset,
            );
          }, growable: false),
        );
      case _blockTable:
        final alignments = List.generate(
          _count(),
          (_) => _align(),
          growable: false,
        );
        final header = _cells();
        final rows = List.generate(_count(), (_) => _cells(), growable: false);
        return MdxTable(
          alignments: alignments,
          header: header.cells,
          rows: [for (final row in rows) row.cells],
          headerSpans: header.spans,
          rowSpans: [for (final row in rows) row.spans],
        );
      case _blockRule:
        return MdxThematicBreak();
      case _blockDetails:
        final open = _bool('open flag');
        final summary = _inlines();
        return MdxDetails(summary: summary, blocks: blocks(), open: open);
      case _blockCustom:
        final typeAt = _position;
        final type = _string();
        if (type.isEmpty) throw _error('empty custom block type', typeAt);
        final attributes = <String, String>{};
        for (var i = _count(); i > 0; i--) {
          final keyAt = _position;
          final key = _string();
          final value = _string();
          if (attributes.containsKey(key)) {
            throw _error('duplicate custom block attribute "$key"', keyAt);
          }
          attributes[key] = value;
        }
        final inlines = _inlines();
        return MdxCustomBlock(
          type,
          attributes: attributes,
          inlines: inlines,
          blocks: blocks(),
        );
    }
    throw _error('unknown block tag $tag', tagAt);
  }

  MdxInline _readInline() {
    final tagAt = _position;
    final tag = _u8();
    switch (tag) {
      case _inlineText:
        return MdxText(_string());
      case _inlineLineBreak:
        return MdxLineBreak();
      case _inlineSoftBreak:
        return MdxSoftBreak();
      case _inlineStyled:
        final kindAt = _position;
        final kind = MdxStyleKind
            .values[_enum('style kind', MdxStyleKind.values.length - 1)];
        if (_titledKinds.contains(kind)) {
          throw _error('style kind $kind needs the titled inline', kindAt);
        }
        return MdxStyled(kind, _inlines());
      case _inlineTitled:
        final kindAt = _position;
        final kind = MdxStyleKind
            .values[_enum('style kind', MdxStyleKind.values.length - 1)];
        if (!_titledKinds.contains(kind)) {
          throw _error('style kind $kind cannot carry a title', kindAt);
        }
        final title = _optionalString();
        return MdxStyled(kind, _inlines(), title: title);
      case _inlineLink:
        final href = _string();
        final title = _optionalString();
        return MdxLink(href: href, title: title, children: _inlines());
      case _inlineImage:
        final src = _string();
        final alt = _optionalString();
        final title = _optionalString();
        final width = _optionalF64();
        return MdxImage(
          src: src,
          alt: alt,
          title: title,
          width: width,
          height: _optionalF64(),
        );
      case _inlineSpan:
        final flagsAt = _position;
        final flags = _u8();
        if (flags & ~_styleFlagMask != 0) {
          throw _error('undefined span flag bits $flags', flagsAt);
        }
        final color = _u32();
        final backgroundColor = _u32();
        final fontSize = _optionalF64();
        return MdxSpan(
          MdxInlineStyle(
            color: flags & _styleHasColor == 0 ? null : color,
            backgroundColor: flags & _styleHasBackground == 0
                ? null
                : backgroundColor,
            fontSize: fontSize,
            bold: flags & _styleBold != 0,
            italic: flags & _styleItalic != 0,
            underline: flags & _styleUnderline != 0,
            strikethrough: flags & _styleStrikethrough != 0,
          ),
          _inlines(),
        );
    }
    throw _error('unknown inline tag $tag', tagAt);
  }
}
