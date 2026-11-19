// Parts of this file are derived from flutter_markdown and flutter_markdown_plus
// (Copyright 2013 The Flutter Authors, BSD-3-Clause). See LICENSE.

import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;

/// An interface for building the widget of a tag.
///
/// Register implementations by tag name in [MarkdownWidget.builders].
abstract class MarkdownElementBuilder {
  /// Returns true for a tag that is a block (the default is false).
  bool isBlockElement() => false;

  /// Called when an element has been reached, before its children are visited.
  void visitElementBefore(md.Element element) {}

  /// Called when a text node has been reached.
  ///
  /// [preferredStyle] is the style of this tag from [MarkdownWidget.styleSheet], if any.
  /// Return null when no widget is needed.
  Widget? visitText(md.Text text, TextStyle? preferredStyle) => null;

  /// Called when an element has been reached, after its children are visited.
  ///
  /// [preferredStyle] is the style of this tag from [MarkdownWidget.styleSheet], if any, and
  /// [parentStyle] is the style of the parent element, if it has one. Return null when no widget
  /// is needed.
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    // The deprecated hook stays reachable so that builders written against it keep working.
    // ignore: deprecated_member_use_from_same_package
    return visitElementAfter(element, preferredStyle);
  }

  /// Called when an element has been reached, after its children are visited.
  @Deprecated('Use visitElementAfterWithContext() instead.')
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) =>
      null;
}

/// An interface for adding padding around the widget of a tag.
///
/// Register implementations by tag name in [MarkdownWidget.paddingBuilders].
abstract class MarkdownPaddingBuilder {
  /// Called when an element has been reached, before its children are visited.
  void visitElementBefore(md.Element element) {}

  /// Returns the padding to apply to the element that was just visited.
  EdgeInsets getPadding() => EdgeInsets.zero;
}

/// Parses task list items (`[ ]` and `[x]`).
///
/// The parser handles task lists natively, so passing this to
/// [MarkdownWidget.inlineSyntaxes] has no effect.
@Deprecated(
  'Use [OrderedListWithCheckBoxSyntax] or [UnorderedListWithCheckBoxSyntax]',
)
class TaskListSyntax extends md.InlineSyntax {
  /// Creates a new instance.
  @Deprecated(
    'Use [OrderedListWithCheckBoxSyntax] or [UnorderedListWithCheckBoxSyntax]',
  )
  TaskListSyntax() : super(_pattern);

  static const String _pattern = r'^ *\[([ xX])\] +';

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final el = md.Element.withTag('input');
    el.attributes['type'] = 'checkbox';
    el.attributes['disabled'] = 'true';
    el.attributes['checked'] = '${match[1]!.trim().isNotEmpty}';
    parser.addNode(el);
    return true;
  }
}
