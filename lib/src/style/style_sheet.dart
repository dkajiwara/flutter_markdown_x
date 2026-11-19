// Parts of this file are derived from flutter_markdown and flutter_markdown_plus
// (Copyright 2013 The Flutter Authors, BSD-3-Clause). See LICENSE.

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import 'extension_style.dart';
import 'style.dart';

/// Defines which [TextStyle], padding, decoration, and alignment to use for which Markdown
/// element.
///
/// The fields, factories, `copyWith`, `merge`, and [styles] follow `flutter_markdown`'s
/// `MarkdownStyleSheet`, so a style sheet written for that package works unchanged.
///
/// ## flutter_markdown_x extensions
///
/// These fields have no `flutter_markdown` counterpart. All of them are optional, and the three
/// factories set them to values derived from the theme.
///
/// * [mark]: the style of `<mark>`.
/// * [codeSyntax]: the colors of the built-in syntax highlighter. When null, code blocks are drawn
///   with [code] only.
/// * [codeBlockOptions]: the code block header (language name and copy button). When null, there
///   is no header.
/// * [alerts]: the appearance of GitHub alerts. When null, it follows the brightness of the theme.
/// * [citation]: the appearance of citation chips. When null, it is derived from the color scheme.
/// * [listItemSpacing]: the spacing between list items. When null, [blockSpacing] is used.
/// * [imageFadeInDuration]: how long an image that loads asynchronously fades in. When null,
///   [MarkdownXDefaults.imageFadeInDuration] is used; [Duration.zero] turns the fade off.
///
/// Two style sheets are equal when every field, including the extensions, is equal. A subclass is
/// never equal to a [MarkdownStyleSheet].
class MarkdownStyleSheet {
  /// Creates an explicit mapping of [TextStyle] objects to Markdown elements.
  MarkdownStyleSheet({
    this.a,
    this.p,
    this.pPadding,
    this.code,
    this.h1,
    this.h1Padding,
    this.h2,
    this.h2Padding,
    this.h3,
    this.h3Padding,
    this.h4,
    this.h4Padding,
    this.h5,
    this.h5Padding,
    this.h6,
    this.h6Padding,
    this.em,
    this.strong,
    this.del,
    this.blockquote,
    this.img,
    this.checkbox,
    this.blockSpacing,
    this.listIndent,
    this.listBullet,
    this.listBulletPadding,
    this.tableHead,
    this.tableBody,
    this.tableHeadAlign,
    this.tablePadding,
    this.tableBorder,
    this.tableColumnWidth,
    this.tableScrollbarThumbVisibility,
    this.tableCellsPadding,
    this.tableCellsDecoration,
    this.tableHeadCellsPadding,
    this.tableHeadCellsDecoration,
    this.tableVerticalAlignment = TableCellVerticalAlignment.middle,
    this.blockquotePadding,
    this.blockquoteDecoration,
    this.codeblockPadding,
    this.codeblockDecoration,
    this.horizontalRuleDecoration,
    this.textAlign = WrapAlignment.start,
    this.h1Align = WrapAlignment.start,
    this.h2Align = WrapAlignment.start,
    this.h3Align = WrapAlignment.start,
    this.h4Align = WrapAlignment.start,
    this.h5Align = WrapAlignment.start,
    this.h6Align = WrapAlignment.start,
    this.unorderedListAlign = WrapAlignment.start,
    this.orderedListAlign = WrapAlignment.start,
    this.blockquoteAlign = WrapAlignment.start,
    this.codeblockAlign = WrapAlignment.start,
    this.superscriptFontFeatureTag,
    @Deprecated('Use textScaler instead.') this.textScaleFactor,
    TextScaler? textScaler,
    this.mark,
    this.codeSyntax,
    this.codeBlockOptions,
    this.alerts,
    this.citation,
    this.listItemSpacing,
    this.imageFadeInDuration,
  }) : assert(
         textScaler == null || textScaleFactor == null,
         'textScaleFactor is deprecated and cannot be specified when textScaler is specified.',
       ),
       textScaler =
           textScaler ??
           // Only textScaler is used internally, so convert the factor to a linear scaler.
           (textScaleFactor == null
               ? null
               : TextScaler.linear(textScaleFactor)),
       _styles = <String, TextStyle?>{
         'a': a,
         'p': p,
         'li': p,
         'code': code,
         'pre': p,
         'h1': h1,
         'h2': h2,
         'h3': h3,
         'h4': h4,
         'h5': h5,
         'h6': h6,
         'em': em,
         'strong': strong,
         'del': del,
         'blockquote': blockquote,
         'img': img,
         'table': p,
         'th': tableHead,
         'tr': tableBody,
         'td': tableBody,
       };

  /// Creates a [MarkdownStyleSheet] from the [TextStyle]s in the provided [ThemeData].
  factory MarkdownStyleSheet.fromTheme(ThemeData theme) {
    assert(theme.textTheme.bodyMedium?.fontSize != null);
    return MarkdownStyleSheet(
      a: const TextStyle(color: Colors.blue),
      p: theme.textTheme.bodyMedium,
      pPadding: EdgeInsets.zero,
      code: theme.textTheme.bodyMedium!.copyWith(
        backgroundColor: theme.cardTheme.color,
        fontFamily: 'monospace',
        fontSize: theme.textTheme.bodyMedium!.fontSize! * 0.85,
      ),
      h1: theme.textTheme.headlineSmall,
      h1Padding: EdgeInsets.zero,
      h2: theme.textTheme.titleLarge,
      h2Padding: EdgeInsets.zero,
      h3: theme.textTheme.titleMedium,
      h3Padding: EdgeInsets.zero,
      h4: theme.textTheme.bodyLarge,
      h4Padding: EdgeInsets.zero,
      h5: theme.textTheme.bodyLarge,
      h5Padding: EdgeInsets.zero,
      h6: theme.textTheme.bodyLarge,
      h6Padding: EdgeInsets.zero,
      em: const TextStyle(fontStyle: FontStyle.italic),
      strong: const TextStyle(fontWeight: FontWeight.bold),
      del: const TextStyle(decoration: TextDecoration.lineThrough),
      blockquote: theme.textTheme.bodyMedium,
      img: theme.textTheme.bodyMedium,
      // Not `theme.primaryColor` (flutter_markdown): in a dark theme it is almost black, so the
      // checkbox disappeared. `colorScheme.primary` is the accent in both brightnesses.
      checkbox: theme.textTheme.bodyMedium!.copyWith(
        color: theme.colorScheme.primary,
      ),
      blockSpacing: 8.0,
      listIndent: 24.0,
      listBullet: theme.textTheme.bodyMedium,
      listBulletPadding: const EdgeInsets.only(right: 4),
      tableHead: const TextStyle(fontWeight: FontWeight.w600),
      tableBody: theme.textTheme.bodyMedium,
      tableHeadAlign: TextAlign.center,
      tablePadding: const EdgeInsets.only(bottom: 4.0),
      tableBorder: TableBorder.all(color: theme.dividerColor),
      tableColumnWidth: const FlexColumnWidth(),
      tableCellsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      tableCellsDecoration: const BoxDecoration(),
      blockquotePadding: const EdgeInsets.all(8.0),
      blockquoteDecoration: BoxDecoration(
        // The light-blue box of flutter_markdown stays in a light theme. In a dark theme the body
        // text is near-white on it (contrast about 1.1:1), so use a raised dark surface instead.
        color: theme.brightness == Brightness.dark
            ? theme.colorScheme.surfaceContainerHighest
            : Colors.blue.shade100,
        borderRadius: BorderRadius.circular(2.0),
      ),
      codeblockPadding: const EdgeInsets.all(8.0),
      codeblockDecoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.cardColor,
        borderRadius: BorderRadius.circular(2.0),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(width: 5.0, color: theme.dividerColor)),
      ),
      mark: TextStyle(backgroundColor: theme.colorScheme.tertiaryContainer),
      codeSyntax: theme.brightness == Brightness.dark
          ? MarkdownXSyntaxColors.dark
          : MarkdownXSyntaxColors.light,
      alerts: theme.brightness == Brightness.dark
          ? MarkdownXAlertStyle.dark
          : MarkdownXAlertStyle.light,
      citation: MarkdownXCitationStyle(
        background: theme.colorScheme.secondaryContainer,
        foreground: theme.colorScheme.onSecondaryContainer,
      ),
    );
  }

  /// Creates a [MarkdownStyleSheet] from the [TextStyle]s in the provided [CupertinoThemeData].
  factory MarkdownStyleSheet.fromCupertinoTheme(CupertinoThemeData theme) {
    assert(theme.textTheme.textStyle.fontSize != null);
    final dark = theme.brightness == Brightness.dark;
    return MarkdownStyleSheet(
      a: theme.textTheme.textStyle.copyWith(
        color: dark
            ? CupertinoColors.link.darkColor
            : CupertinoColors.link.color,
      ),
      p: theme.textTheme.textStyle,
      pPadding: EdgeInsets.zero,
      code: theme.textTheme.textStyle.copyWith(
        fontFamily: 'monospace',
        fontSize: theme.textTheme.textStyle.fontSize! * 0.85,
      ),
      h1: theme.textTheme.textStyle.copyWith(
        fontWeight: FontWeight.w500,
        fontSize: theme.textTheme.textStyle.fontSize! + 10,
      ),
      h1Padding: EdgeInsets.zero,
      h2: theme.textTheme.textStyle.copyWith(
        fontWeight: FontWeight.w500,
        fontSize: theme.textTheme.textStyle.fontSize! + 8,
      ),
      h2Padding: EdgeInsets.zero,
      h3: theme.textTheme.textStyle.copyWith(
        fontWeight: FontWeight.w500,
        fontSize: theme.textTheme.textStyle.fontSize! + 6,
      ),
      h3Padding: EdgeInsets.zero,
      h4: theme.textTheme.textStyle.copyWith(
        fontWeight: FontWeight.w500,
        fontSize: theme.textTheme.textStyle.fontSize! + 4,
      ),
      h4Padding: EdgeInsets.zero,
      h5: theme.textTheme.textStyle.copyWith(
        fontWeight: FontWeight.w500,
        fontSize: theme.textTheme.textStyle.fontSize! + 2,
      ),
      h5Padding: EdgeInsets.zero,
      h6: theme.textTheme.textStyle.copyWith(fontWeight: FontWeight.w500),
      h6Padding: EdgeInsets.zero,
      em: theme.textTheme.textStyle.copyWith(fontStyle: FontStyle.italic),
      strong: theme.textTheme.textStyle.copyWith(fontWeight: FontWeight.bold),
      del: theme.textTheme.textStyle.copyWith(
        decoration: TextDecoration.lineThrough,
      ),
      blockquote: theme.textTheme.textStyle,
      img: theme.textTheme.textStyle,
      checkbox: theme.textTheme.textStyle.copyWith(color: theme.primaryColor),
      blockSpacing: 8,
      listIndent: 24,
      listBullet: theme.textTheme.textStyle,
      listBulletPadding: const EdgeInsets.only(right: 4),
      tableHead: theme.textTheme.textStyle.copyWith(
        fontWeight: FontWeight.w600,
      ),
      tableBody: theme.textTheme.textStyle,
      tableHeadAlign: TextAlign.center,
      tablePadding: const EdgeInsets.only(bottom: 8),
      tableBorder: TableBorder.all(color: CupertinoColors.separator, width: 0),
      tableColumnWidth: const FlexColumnWidth(),
      tableCellsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      tableCellsDecoration: BoxDecoration(
        color: dark
            ? CupertinoColors.systemGrey6.darkColor
            : CupertinoColors.systemGrey6.color,
      ),
      blockquotePadding: const EdgeInsets.all(16),
      blockquoteDecoration: BoxDecoration(
        color: dark
            ? CupertinoColors.systemGrey6.darkColor
            : CupertinoColors.systemGrey6.color,
        border: Border(
          left: BorderSide(
            color: dark
                ? CupertinoColors.systemGrey4.darkColor
                : CupertinoColors.systemGrey4.color,
            width: 4,
          ),
        ),
      ),
      codeblockPadding: const EdgeInsets.all(8),
      codeblockDecoration: BoxDecoration(
        color: dark
            ? CupertinoColors.systemGrey6.darkColor
            : CupertinoColors.systemGrey6.color,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: dark
                ? CupertinoColors.systemGrey4.darkColor
                : CupertinoColors.systemGrey4.color,
          ),
        ),
      ),
      mark: TextStyle(
        backgroundColor:
            (dark
                    ? CupertinoColors.systemYellow.darkColor
                    : CupertinoColors.systemYellow.color)
                .withValues(alpha: 0.4),
      ),
      codeSyntax: dark
          ? MarkdownXSyntaxColors.dark
          : MarkdownXSyntaxColors.light,
      alerts: dark ? MarkdownXAlertStyle.dark : MarkdownXAlertStyle.light,
      citation: dark
          ? MarkdownXCitationStyle.dark
          : MarkdownXCitationStyle.light,
    );
  }

  /// Creates a [MarkdownStyleSheet] from the [TextStyle]s in the provided [ThemeData].
  ///
  /// This factory uses larger fonts for the headings than [MarkdownStyleSheet.fromTheme].
  factory MarkdownStyleSheet.largeFromTheme(ThemeData theme) {
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      h1: theme.textTheme.displayMedium,
      h2: theme.textTheme.displaySmall,
      h3: theme.textTheme.headlineMedium,
      h4: theme.textTheme.headlineSmall,
      h5: theme.textTheme.titleLarge,
      h6: theme.textTheme.titleMedium,
    );
  }

  /// Creates a [MarkdownStyleSheet] based on the current style, with the provided parameters
  /// overridden.
  MarkdownStyleSheet copyWith({
    TextStyle? a,
    TextStyle? p,
    EdgeInsets? pPadding,
    TextStyle? code,
    TextStyle? h1,
    EdgeInsets? h1Padding,
    TextStyle? h2,
    EdgeInsets? h2Padding,
    TextStyle? h3,
    EdgeInsets? h3Padding,
    TextStyle? h4,
    EdgeInsets? h4Padding,
    TextStyle? h5,
    EdgeInsets? h5Padding,
    TextStyle? h6,
    EdgeInsets? h6Padding,
    TextStyle? em,
    TextStyle? strong,
    TextStyle? del,
    TextStyle? blockquote,
    TextStyle? img,
    TextStyle? checkbox,
    double? blockSpacing,
    double? listIndent,
    TextStyle? listBullet,
    EdgeInsets? listBulletPadding,
    TextStyle? tableHead,
    TextStyle? tableBody,
    TextAlign? tableHeadAlign,
    EdgeInsets? tablePadding,
    TableBorder? tableBorder,
    TableColumnWidth? tableColumnWidth,
    bool? tableScrollbarThumbVisibility,
    EdgeInsets? tableCellsPadding,
    Decoration? tableCellsDecoration,
    EdgeInsets? tableHeadCellsPadding,
    Decoration? tableHeadCellsDecoration,
    TableCellVerticalAlignment? tableVerticalAlignment,
    EdgeInsets? blockquotePadding,
    Decoration? blockquoteDecoration,
    EdgeInsets? codeblockPadding,
    Decoration? codeblockDecoration,
    Decoration? horizontalRuleDecoration,
    WrapAlignment? textAlign,
    WrapAlignment? h1Align,
    WrapAlignment? h2Align,
    WrapAlignment? h3Align,
    WrapAlignment? h4Align,
    WrapAlignment? h5Align,
    WrapAlignment? h6Align,
    WrapAlignment? unorderedListAlign,
    WrapAlignment? orderedListAlign,
    WrapAlignment? blockquoteAlign,
    WrapAlignment? codeblockAlign,
    String? superscriptFontFeatureTag,
    @Deprecated('Use textScaler instead.') double? textScaleFactor,
    TextScaler? textScaler,
    TextStyle? mark,
    MarkdownXSyntaxColors? codeSyntax,
    MarkdownXCodeBlockOptions? codeBlockOptions,
    MarkdownXAlertStyle? alerts,
    MarkdownXCitationStyle? citation,
    double? listItemSpacing,
    Duration? imageFadeInDuration,
  }) {
    assert(
      textScaler == null || textScaleFactor == null,
      'textScaleFactor is deprecated and cannot be specified when textScaler is specified.',
    );
    // When either of textScaler and textScaleFactor is given, pass null for the other instead of
    // the previous value, since only one of them is allowed.
    final newTextScaler =
        textScaler ?? (textScaleFactor == null ? this.textScaler : null);
    // ignore: deprecated_member_use_from_same_package
    final previousFactor = this.textScaleFactor;
    final nextTextScaleFactor =
        textScaleFactor ?? (textScaler == null ? previousFactor : null);
    return MarkdownStyleSheet(
      a: a ?? this.a,
      p: p ?? this.p,
      pPadding: pPadding ?? this.pPadding,
      code: code ?? this.code,
      h1: h1 ?? this.h1,
      h1Padding: h1Padding ?? this.h1Padding,
      h2: h2 ?? this.h2,
      h2Padding: h2Padding ?? this.h2Padding,
      h3: h3 ?? this.h3,
      h3Padding: h3Padding ?? this.h3Padding,
      h4: h4 ?? this.h4,
      h4Padding: h4Padding ?? this.h4Padding,
      h5: h5 ?? this.h5,
      h5Padding: h5Padding ?? this.h5Padding,
      h6: h6 ?? this.h6,
      h6Padding: h6Padding ?? this.h6Padding,
      em: em ?? this.em,
      strong: strong ?? this.strong,
      del: del ?? this.del,
      blockquote: blockquote ?? this.blockquote,
      img: img ?? this.img,
      checkbox: checkbox ?? this.checkbox,
      blockSpacing: blockSpacing ?? this.blockSpacing,
      listIndent: listIndent ?? this.listIndent,
      listBullet: listBullet ?? this.listBullet,
      listBulletPadding: listBulletPadding ?? this.listBulletPadding,
      tableHead: tableHead ?? this.tableHead,
      tableBody: tableBody ?? this.tableBody,
      tableHeadAlign: tableHeadAlign ?? this.tableHeadAlign,
      tablePadding: tablePadding ?? this.tablePadding,
      tableBorder: tableBorder ?? this.tableBorder,
      tableColumnWidth: tableColumnWidth ?? this.tableColumnWidth,
      // flutter_markdown drops this field here; it is carried over like every other field.
      tableScrollbarThumbVisibility:
          tableScrollbarThumbVisibility ?? this.tableScrollbarThumbVisibility,
      tableCellsPadding: tableCellsPadding ?? this.tableCellsPadding,
      tableCellsDecoration: tableCellsDecoration ?? this.tableCellsDecoration,
      tableHeadCellsPadding:
          tableHeadCellsPadding ?? this.tableHeadCellsPadding,
      tableHeadCellsDecoration:
          tableHeadCellsDecoration ?? this.tableHeadCellsDecoration,
      tableVerticalAlignment:
          tableVerticalAlignment ?? this.tableVerticalAlignment,
      blockquotePadding: blockquotePadding ?? this.blockquotePadding,
      blockquoteDecoration: blockquoteDecoration ?? this.blockquoteDecoration,
      codeblockPadding: codeblockPadding ?? this.codeblockPadding,
      codeblockDecoration: codeblockDecoration ?? this.codeblockDecoration,
      horizontalRuleDecoration:
          horizontalRuleDecoration ?? this.horizontalRuleDecoration,
      textAlign: textAlign ?? this.textAlign,
      h1Align: h1Align ?? this.h1Align,
      h2Align: h2Align ?? this.h2Align,
      h3Align: h3Align ?? this.h3Align,
      h4Align: h4Align ?? this.h4Align,
      h5Align: h5Align ?? this.h5Align,
      h6Align: h6Align ?? this.h6Align,
      unorderedListAlign: unorderedListAlign ?? this.unorderedListAlign,
      orderedListAlign: orderedListAlign ?? this.orderedListAlign,
      blockquoteAlign: blockquoteAlign ?? this.blockquoteAlign,
      codeblockAlign: codeblockAlign ?? this.codeblockAlign,
      superscriptFontFeatureTag:
          superscriptFontFeatureTag ?? this.superscriptFontFeatureTag,
      // ignore: deprecated_member_use_from_same_package
      textScaleFactor: nextTextScaleFactor,
      textScaler: newTextScaler,
      mark: mark ?? this.mark,
      codeSyntax: codeSyntax ?? this.codeSyntax,
      codeBlockOptions: codeBlockOptions ?? this.codeBlockOptions,
      alerts: alerts ?? this.alerts,
      citation: citation ?? this.citation,
      listItemSpacing: listItemSpacing ?? this.listItemSpacing,
      imageFadeInDuration: imageFadeInDuration ?? this.imageFadeInDuration,
    );
  }

  /// Returns a new style sheet that combines this one with [other].
  ///
  /// Text styles are merged ([TextStyle.merge]); every other field is replaced by the value of
  /// [other] when it is non-null. A null [other] returns this style sheet. Unlike
  /// `flutter_markdown`, a text style that is null in this style sheet does not throw: it takes
  /// the value of [other].
  MarkdownStyleSheet merge(MarkdownStyleSheet? other) {
    if (other == null) {
      return this;
    }
    return copyWith(
      a: _mergeStyle(a, other.a),
      p: _mergeStyle(p, other.p),
      pPadding: other.pPadding,
      code: _mergeStyle(code, other.code),
      h1: _mergeStyle(h1, other.h1),
      h1Padding: other.h1Padding,
      h2: _mergeStyle(h2, other.h2),
      h2Padding: other.h2Padding,
      h3: _mergeStyle(h3, other.h3),
      h3Padding: other.h3Padding,
      h4: _mergeStyle(h4, other.h4),
      h4Padding: other.h4Padding,
      h5: _mergeStyle(h5, other.h5),
      h5Padding: other.h5Padding,
      h6: _mergeStyle(h6, other.h6),
      h6Padding: other.h6Padding,
      em: _mergeStyle(em, other.em),
      strong: _mergeStyle(strong, other.strong),
      del: _mergeStyle(del, other.del),
      blockquote: _mergeStyle(blockquote, other.blockquote),
      img: _mergeStyle(img, other.img),
      checkbox: _mergeStyle(checkbox, other.checkbox),
      blockSpacing: other.blockSpacing,
      listIndent: other.listIndent,
      listBullet: _mergeStyle(listBullet, other.listBullet),
      listBulletPadding: other.listBulletPadding,
      tableHead: _mergeStyle(tableHead, other.tableHead),
      tableBody: _mergeStyle(tableBody, other.tableBody),
      tableHeadAlign: other.tableHeadAlign,
      tablePadding: other.tablePadding,
      tableBorder: other.tableBorder,
      tableColumnWidth: other.tableColumnWidth,
      tableScrollbarThumbVisibility: other.tableScrollbarThumbVisibility,
      tableCellsPadding: other.tableCellsPadding,
      tableCellsDecoration: other.tableCellsDecoration,
      tableHeadCellsPadding: other.tableHeadCellsPadding,
      tableHeadCellsDecoration: other.tableHeadCellsDecoration,
      tableVerticalAlignment: other.tableVerticalAlignment,
      blockquotePadding: other.blockquotePadding,
      blockquoteDecoration: other.blockquoteDecoration,
      codeblockPadding: other.codeblockPadding,
      codeblockDecoration: other.codeblockDecoration,
      horizontalRuleDecoration: other.horizontalRuleDecoration,
      textAlign: other.textAlign,
      h1Align: other.h1Align,
      h2Align: other.h2Align,
      h3Align: other.h3Align,
      h4Align: other.h4Align,
      h5Align: other.h5Align,
      h6Align: other.h6Align,
      unorderedListAlign: other.unorderedListAlign,
      orderedListAlign: other.orderedListAlign,
      blockquoteAlign: other.blockquoteAlign,
      codeblockAlign: other.codeblockAlign,
      // ignore: deprecated_member_use_from_same_package
      textScaleFactor: other.textScaleFactor,
      superscriptFontFeatureTag: other.superscriptFontFeatureTag,
      // Only one of textScaler and textScaleFactor can be passed. When other has a
      // textScaleFactor, its textScaler was derived from it and must be ignored.
      // ignore: deprecated_member_use_from_same_package
      textScaler: other.textScaleFactor == null ? other.textScaler : null,
      mark: _mergeStyle(mark, other.mark),
      codeSyntax: other.codeSyntax,
      codeBlockOptions: other.codeBlockOptions,
      alerts: other.alerts,
      citation: other.citation,
      listItemSpacing: other.listItemSpacing,
      imageFadeInDuration: other.imageFadeInDuration,
    );
  }

  static TextStyle? _mergeStyle(TextStyle? base, TextStyle? other) =>
      base == null ? other : base.merge(other);

  /// The [TextStyle] of links (`a`).
  final TextStyle? a;

  /// The [TextStyle] of paragraphs (`p`). Also the style of `li`, `pre`, and `table`.
  final TextStyle? p;

  /// The padding around the text of a top-level paragraph.
  final EdgeInsets? pPadding;

  /// The [TextStyle] of inline code. Also the style of the text of a code block that has no
  /// syntax highlighting.
  final TextStyle? code;

  /// The [TextStyle] of `h1`.
  final TextStyle? h1;

  /// The padding around the text of a top-level `h1`.
  final EdgeInsets? h1Padding;

  /// The [TextStyle] of `h2`.
  final TextStyle? h2;

  /// The padding around the text of a top-level `h2`.
  final EdgeInsets? h2Padding;

  /// The [TextStyle] of `h3`.
  final TextStyle? h3;

  /// The padding around the text of a top-level `h3`.
  final EdgeInsets? h3Padding;

  /// The [TextStyle] of `h4`.
  final TextStyle? h4;

  /// The padding around the text of a top-level `h4`.
  final EdgeInsets? h4Padding;

  /// The [TextStyle] of `h5`.
  final TextStyle? h5;

  /// The padding around the text of a top-level `h5`.
  final EdgeInsets? h5Padding;

  /// The [TextStyle] of `h6`.
  final TextStyle? h6;

  /// The padding around the text of a top-level `h6`.
  final EdgeInsets? h6Padding;

  /// The [TextStyle] of emphasis (`em`).
  final TextStyle? em;

  /// The [TextStyle] of strong emphasis (`strong`).
  final TextStyle? strong;

  /// The [TextStyle] of deleted text (`del`).
  final TextStyle? del;

  /// The [TextStyle] of the text inside a blockquote.
  final TextStyle? blockquote;

  /// The [TextStyle] given to an `img` element builder as its preferred style.
  final TextStyle? img;

  /// The [TextStyle] of the default checkbox: its `fontSize` is the icon size and its `color` is
  /// the icon color.
  final TextStyle? checkbox;

  /// The vertical space between sibling blocks.
  final double? blockSpacing;

  /// The width of the bullet column of a list item, before [listBulletPadding] is added.
  final double? listIndent;

  /// The [TextStyle] of the default bullet.
  final TextStyle? listBullet;

  /// The padding around the default bullet and the default checkbox.
  final EdgeInsets? listBulletPadding;

  /// The [TextStyle] of table header cells (`th`), merged onto [tableBody].
  final TextStyle? tableHead;

  /// The [TextStyle] of table body cells (`td`).
  final TextStyle? tableBody;

  /// The default [TextAlign] of table header cells that have no alignment of their own.
  final TextAlign? tableHeadAlign;

  /// The padding of the horizontal scroll view of a table.
  ///
  /// Used only when [tableColumnWidth] is a [FixedColumnWidth] or an [IntrinsicColumnWidth].
  final EdgeInsets? tablePadding;

  /// The [TableBorder] of tables.
  final TableBorder? tableBorder;

  /// The default [TableColumnWidth] of tables.
  ///
  /// A [FixedColumnWidth] or an [IntrinsicColumnWidth] makes the table scroll horizontally.
  final TableColumnWidth? tableColumnWidth;

  /// Whether the scrollbar of a horizontally scrolling table always shows its thumb.
  final bool? tableScrollbarThumbVisibility;

  /// The padding of table cells.
  final EdgeInsets? tableCellsPadding;

  /// The [Decoration] of the even-numbered body rows of a table (the 2nd, 4th, and so on), and of
  /// the header row when [tableHeadCellsDecoration] is null.
  final Decoration? tableCellsDecoration;

  /// The padding of table header cells. When null, [tableCellsPadding] is used.
  final EdgeInsets? tableHeadCellsPadding;

  /// The [Decoration] of the header row of a table. When null, [tableCellsDecoration] is used.
  final Decoration? tableHeadCellsDecoration;

  /// The vertical alignment of table cells.
  final TableCellVerticalAlignment tableVerticalAlignment;

  /// The padding inside a blockquote.
  final EdgeInsets? blockquotePadding;

  /// The [Decoration] of a blockquote.
  final Decoration? blockquoteDecoration;

  /// The padding inside a code block.
  final EdgeInsets? codeblockPadding;

  /// The [Decoration] of a code block.
  final Decoration? codeblockDecoration;

  /// The [Decoration] of a horizontal rule. Its height is the width of the decoration's border.
  final Decoration? horizontalRuleDecoration;

  /// The alignment of the text of a top-level paragraph.
  final WrapAlignment textAlign;

  /// The alignment of the text of a top-level `h1`.
  final WrapAlignment h1Align;

  /// The alignment of the text of a top-level `h2`.
  final WrapAlignment h2Align;

  /// The alignment of the text of a top-level `h3`.
  final WrapAlignment h3Align;

  /// The alignment of the text of a top-level `h4`.
  final WrapAlignment h4Align;

  /// The alignment of the text of a top-level `h5`.
  final WrapAlignment h5Align;

  /// The alignment of the text of a top-level `h6`.
  final WrapAlignment h6Align;

  /// The alignment of the text of a top-level unordered list.
  final WrapAlignment unorderedListAlign;

  /// The alignment of the text of a top-level ordered list.
  final WrapAlignment orderedListAlign;

  /// The alignment of the text of a top-level blockquote.
  final WrapAlignment blockquoteAlign;

  /// The alignment of a top-level code block.
  final WrapAlignment codeblockAlign;

  /// The text scaler applied to every piece of text.
  final TextScaler? textScaler;

  /// The text scale factor.
  @Deprecated('Use textScaler instead.')
  final double? textScaleFactor;

  /// An extra font feature tag enabled for superscript text, in addition to `sups`.
  ///
  /// When null, superscript is drawn as smaller raised text. When set, superscript text is drawn
  /// with the font features instead.
  final String? superscriptFontFeatureTag;

  /// Extension. The [TextStyle] of `<mark>`. When null, a background of
  /// [ColorScheme.tertiaryContainer] is used.
  final TextStyle? mark;

  /// Extension. The colors of the built-in syntax highlighter of code blocks.
  ///
  /// When null, code blocks are drawn with [code] only. A non-null
  /// [MarkdownXSyntaxColors.background] replaces the color of [codeblockDecoration] when it is a
  /// [BoxDecoration], and [MarkdownXSyntaxColors.foreground] sets the text color of code.
  final MarkdownXSyntaxColors? codeSyntax;

  /// Extension. The header of code blocks (language name and copy button). When null, there is no
  /// header.
  final MarkdownXCodeBlockOptions? codeBlockOptions;

  /// Extension. The appearance of GitHub alerts. When null, it follows the brightness of the theme.
  final MarkdownXAlertStyle? alerts;

  /// Extension. The appearance of citation chips. When null, it is derived from the color scheme.
  final MarkdownXCitationStyle? citation;

  /// Extension. The vertical space between list items. When null, [blockSpacing] is used.
  final double? listItemSpacing;

  /// Extension. How long an image that loads asynchronously (not from the image cache) fades in.
  ///
  /// When null, [MarkdownXDefaults.imageFadeInDuration] is used. [Duration.zero] turns the fade
  /// off. There is no fade either when the platform asks to reduce animations
  /// ([MediaQueryData.disableAnimations]) or for widgets from `sizedImageBuilder`, `imageBuilder`
  /// and `builders['img']`.
  final Duration? imageFadeInDuration;

  /// A map from tag name to [TextStyle].
  ///
  /// It has exactly these keys: `a`, `p`, `li`, `code`, `pre`, `h1` to `h6`, `em`, `strong`,
  /// `del`, `blockquote`, `img`, `table`, `th`, `tr`, and `td`. Other tags have no style.
  Map<String, TextStyle?> get styles => _styles;
  final Map<String, TextStyle?> _styles;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (runtimeType != MarkdownStyleSheet ||
        other.runtimeType != MarkdownStyleSheet) {
      return false;
    }
    return other is MarkdownStyleSheet && _sameFields(other);
  }

  bool _sameFields(MarkdownStyleSheet other) {
    final mine = _fields;
    final theirs = other._fields;
    for (var i = 0; i < mine.length; i++) {
      if (mine[i] != theirs[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_fields);

  /// Every field in a fixed order, for [==] and [hashCode].
  List<Object?> get _fields => <Object?>[
    a,
    p,
    pPadding,
    code,
    h1,
    h1Padding,
    h2,
    h2Padding,
    h3,
    h3Padding,
    h4,
    h4Padding,
    h5,
    h5Padding,
    h6,
    h6Padding,
    em,
    strong,
    del,
    blockquote,
    img,
    checkbox,
    blockSpacing,
    listIndent,
    listBullet,
    listBulletPadding,
    tableHead,
    tableBody,
    tableHeadAlign,
    tablePadding,
    tableBorder,
    tableColumnWidth,
    tableScrollbarThumbVisibility,
    tableCellsPadding,
    tableCellsDecoration,
    tableHeadCellsPadding,
    tableHeadCellsDecoration,
    tableVerticalAlignment,
    blockquotePadding,
    blockquoteDecoration,
    codeblockPadding,
    codeblockDecoration,
    horizontalRuleDecoration,
    textAlign,
    h1Align,
    h2Align,
    h3Align,
    h4Align,
    h5Align,
    h6Align,
    unorderedListAlign,
    orderedListAlign,
    blockquoteAlign,
    codeblockAlign,
    superscriptFontFeatureTag,
    textScaler,
    // ignore: deprecated_member_use_from_same_package
    textScaleFactor,
    mark,
    codeSyntax,
    codeBlockOptions,
    alerts,
    citation,
    listItemSpacing,
    imageFadeInDuration,
  ];
}
