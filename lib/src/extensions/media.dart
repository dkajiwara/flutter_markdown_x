/// Reads the `media` block that the parser creates for HTML `<video>`, `<audio>`, `<iframe>`,
/// `<embed>` and `<object>`.
///
/// The package ships no player. Without a builder the block shows its fallback link (tapping it
/// calls `onTapLink`). Apps render a player through `blockBuilder` with [MarkdownXMedia.of], or
/// through `builders['media']`. See doc/html.md.
/// This file does not depend on Flutter.
library;

import '../ir/nodes.dart';

/// The [MdxCustomBlock.type] of a media block.
const markdownXMediaType = 'media';

/// The attribute that holds the element name ([MarkdownXMediaKind.name]).
const markdownXMediaKindAttribute = 'kind';

/// The attribute that holds the URL (`src`, or `data` for `<object>`).
const markdownXMediaSrcAttribute = 'src';

/// The HTML element a media block was written as. [name] is the tag name and the `kind` value.
enum MarkdownXMediaKind {
  /// `<video>`.
  video,

  /// `<audio>`.
  audio,

  /// `<iframe>`.
  iframe,

  /// `<embed>`.
  embed,

  /// `<object>`.
  object,
}

/// The typed attributes of a media block.
final class MarkdownXMedia {
  const MarkdownXMedia._({
    required this.kind,
    required this.src,
    this.type,
    this.poster,
    this.title,
    this.width,
    this.height,
  });

  /// Reads [block] if it is a media block with a known `kind` and a `src`, or returns null.
  static MarkdownXMedia? of(MdxBlock block) {
    if (block is! MdxCustomBlock || block.type != markdownXMediaType) {
      return null;
    }
    final attributes = block.attributes;
    final kindName = attributes[markdownXMediaKindAttribute];
    final src = attributes[markdownXMediaSrcAttribute];
    if (src == null || src.isEmpty) return null;
    for (final kind in MarkdownXMediaKind.values) {
      if (kind.name != kindName) continue;
      return MarkdownXMedia._(
        kind: kind,
        src: src,
        type: attributes['type'],
        poster: attributes['poster'],
        title: attributes['title'],
        width: double.tryParse(attributes['width'] ?? ''),
        height: double.tryParse(attributes['height'] ?? ''),
      );
    }
    return null;
  }

  /// The element it was written as.
  final MarkdownXMediaKind kind;

  /// The URL as written (from `src`, the first usable `<source src>`, or `<object data>`).
  /// `javascript:`, `vbscript:` and `data:` URLs never reach a media block.
  final String src;

  /// [src] parsed as a [Uri], or null when it does not parse.
  Uri? get uri => Uri.tryParse(src);

  /// The MIME type from `type` (of the element, or of the chosen `<source>`).
  final String? type;

  /// The `poster` image URL of a `<video>`.
  final String? poster;

  /// The `title` attribute.
  final String? title;

  /// The `width` attribute as a number, or null when absent or not a plain number (such as `100%`).
  final double? width;

  /// The `height` attribute as a number, or null when absent or not a plain number.
  final double? height;
}
