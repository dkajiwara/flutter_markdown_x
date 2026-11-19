// Parts of this file are derived from flutter_markdown and flutter_markdown_plus
// (Copyright 2013 The Flutter Authors, BSD-3-Clause). See LICENSE.

import 'package:flutter/widgets.dart';

/// Called when the user changes the selection of a selectable document.
///
/// [text] is the selected plain text and [selection] covers it (`TextSelection(baseOffset: 0,
/// extentOffset: text.length)`), so `text.substring(selection.start, selection.end)` is the
/// selected text. [cause] is always null because the selection is owned by one
/// [SelectionArea] for the whole document, which does not report it.
typedef MarkdownOnSelectionChangedCallback = void Function(
  String? text,
  TextSelection selection,
  SelectionChangedCause? cause,
);

/// Signature for callbacks used by [MarkdownWidget] when the user taps a link.
///
/// [text] is the text of the link, [href] is the destination (`null` when the link has none) and
/// [title] is the title of the link (the empty string when there is none).
typedef MarkdownTapLinkCallback = void Function(
  String text,
  String? href,
  String title,
);

/// Signature for custom image widget builders that receive the full image configuration.
typedef MarkdownSizedImageBuilder = Widget Function(MarkdownImageConfig config);

/// Signature for custom image widget builders.
///
/// The [uri] is the image source as written in the document (it is not resolved against
/// [MarkdownWidget.imageDirectory]).
typedef MarkdownImageBuilder = Widget Function(
  Uri uri,
  String? title,
  String? alt,
);

/// Signature for custom checkbox widget builders. [value] is true for a checked task.
typedef MarkdownCheckboxBuilder = Widget Function(bool value);

/// Signature for custom bullet widget builders.
typedef MarkdownBulletBuilder = Widget Function(
  MarkdownBulletParameters parameters,
);

/// Holds the data a [MarkdownBulletBuilder] needs to build a bullet.
class MarkdownBulletParameters {
  /// Creates the parameters of one bullet.
  const MarkdownBulletParameters({
    required this.index,
    required this.style,
    required this.nestLevel,
  });

  /// The zero-based position of the item in its list, offset by `start - 1` for an ordered list
  /// that does not start at 1.
  final int index;

  /// The kind of list the bullet belongs to.
  final BulletStyle style;

  /// The number of enclosing lists (0 for a top-level list).
  final int nestLevel;
}

/// The kind of list a bullet belongs to.
enum BulletStyle {
  /// An ordered (numbered) list.
  orderedList,

  /// An unordered (bulleted) list.
  unorderedList,
}

/// Holds the configuration of one image in a document.
class MarkdownImageConfig {
  /// Creates the configuration of one image.
  MarkdownImageConfig({
    required this.uri,
    this.title,
    this.alt,
    this.width,
    this.height,
  });

  /// The URI of the image.
  final Uri uri;

  /// The title of the image.
  final String? title;

  /// The alternative text of the image.
  final String? alt;

  /// The requested width of the image.
  final double? width;

  /// The requested height of the image.
  final double? height;
}

/// Creates a formatted [TextSpan] for a string.
///
/// Used by [MarkdownWidget] to color the contents of code blocks.
abstract class SyntaxHighlighter {
  // ignore: one_member_abstracts
  /// Returns the formatted [TextSpan] for the given [source].
  TextSpan format(String source);
}

/// Specifies which theme [MarkdownStyleSheet] is created from.
enum MarkdownStyleSheetBaseTheme {
  /// Creates a style sheet from the Material theme.
  material,

  /// Creates a style sheet from the Cupertino theme.
  cupertino,

  /// Creates a style sheet from the theme of the current platform: Cupertino on iOS and macOS,
  /// Material elsewhere.
  ///
  /// The platform is [defaultTargetPlatform], so on the web it follows the user agent.
  platform,
}

/// The strategies for aligning a list marker with the content of its item on the cross axis.
enum MarkdownListItemCrossAxisAlignment {
  /// Uses [CrossAxisAlignment.baseline] for the row of the bullet and the item, so the bullet
  /// lines up with the first line of the text.
  ///
  /// [RenderFlex] does not support intrinsic height measurements with this alignment.
  baseline,

  /// Uses [CrossAxisAlignment.start] for the row of the bullet and the item.
  ///
  /// Intrinsic height measurements work, but the bullet may not line up with the text of
  /// items that start with a larger font.
  start,
}
