import 'package:material_ui/material_ui.dart';

/// Constants used by the renderer that have no [MarkdownStyleSheet] field.
abstract final class MarkdownXDefaults {
  /// Font family for code.
  static const codeFontFamily = 'monospace';

  /// Font fallbacks for code. Some browsers and environments have no `monospace` family on the Web,
  /// so this lists each OS's monospace font and ends with the generic `monospace`.
  static const codeFontFamilyFallback = <String>[
    'Menlo',
    'Consolas',
    'Roboto Mono',
    'Courier New',
    'monospace',
  ];

  /// The CSS `larger` / `smaller` step: Chrome and Firefox scale by 1.2.
  static const fontSizeStep = 1.2;

  /// Font size multiplier for `<small>` (CSS `smaller`), relative to the parent.
  static const smallFontScale = 1 / fontSizeStep;

  /// Font size multiplier for `<big>` (CSS `larger`), relative to the parent.
  static const bigFontScale = fontSizeStep;

  /// Font size multiplier for superscript and subscript, relative to the parent.
  static const scriptFontScale = 0.7;

  /// How far superscript and subscript are shifted from the baseline (ratio of the parent font size).
  ///
  /// Currently unused. Superscript is drawn toward the top of the line and subscript toward the bottom
  /// (shifting the position would break the selection order). Kept for compatibility.
  static const scriptShift = 0.35;

  /// How many lines of a code block are laid out per `Text`.
  /// Only code blocks with more lines than this are split.
  static const codeChunkLines = 200;

  /// Maximum width and height of an image (logical pixels). Larger specified values are clamped.
  static const maxImageExtent = 8192.0;

  /// How long an image that loads asynchronously takes to fade in, when
  /// [MarkdownStyleSheet.imageFadeInDuration] is null.
  static const imageFadeInDuration = Duration(milliseconds: 200);

  /// The curve of the image fade-in.
  static const imageFadeInCurve = Curves.easeOut;

  /// Inner padding of an alert (logical pixels).
  static const alertPadding = EdgeInsetsDirectional.fromSTEB(12, 9, 12, 9);

  /// Font size used when the font size is unknown (logical pixels).
  static const fallbackFontSize = 14.0;
}

/// Color scheme (theme) for syntax highlighting of code blocks.
///
/// When [background] and [foreground] are specified, the code block background and text color are
/// also determined by this theme (if null, [MarkdownStyleSheet.code] and the body text color).
@immutable
class MarkdownXSyntaxColors {
  /// Creates a syntax highlighting color scheme. [background] and [foreground] may be omitted.
  const MarkdownXSyntaxColors({
    required this.keyword,
    required this.string,
    required this.comment,
    required this.number,
    this.background,
    this.foreground,
  });

  /// Color scheme for light backgrounds.
  static const light = MarkdownXSyntaxColors(
    keyword: Color(0xFFCF222E),
    string: Color(0xFF0A3069),
    comment: Color(0xFF6E7781),
    number: Color(0xFF0550AE),
  );

  /// Color scheme for dark backgrounds.
  static const dark = MarkdownXSyntaxColors(
    keyword: Color(0xFFFF7B72),
    string: Color(0xFFA5D6FF),
    comment: Color(0xFF8B949E),
    number: Color(0xFF79C0FF),
  );

  /// Monokai-style dark color scheme (with background).
  static const monokai = MarkdownXSyntaxColors(
    keyword: Color(0xFFF92672),
    string: Color(0xFFE6DB74),
    comment: Color(0xFF75715E),
    number: Color(0xFFAE81FF),
    background: Color(0xFF272822),
    foreground: Color(0xFFF8F8F2),
  );

  /// Solarized Light-style color scheme (with background).
  static const solarizedLight = MarkdownXSyntaxColors(
    keyword: Color(0xFF859900),
    string: Color(0xFF2AA198),
    comment: Color(0xFF93A1A1),
    number: Color(0xFFD33682),
    background: Color(0xFFFDF6E3),
    foreground: Color(0xFF657B83),
  );

  /// Solarized Dark-style color scheme (with background).
  static const solarizedDark = MarkdownXSyntaxColors(
    keyword: Color(0xFF859900),
    string: Color(0xFF2AA198),
    comment: Color(0xFF586E75),
    number: Color(0xFFD33682),
    background: Color(0xFF002B36),
    foreground: Color(0xFF93A1A1),
  );

  /// Table that looks up built-in themes by name.
  static const themes = <String, MarkdownXSyntaxColors>{
    'github-light': light,
    'github-dark': dark,
    'monokai': monokai,
    'solarized-light': solarizedLight,
    'solarized-dark': solarizedDark,
  };

  /// Color of keywords.
  final Color keyword;

  /// Color of string literals.
  final Color string;

  /// Color of comments.
  final Color comment;

  /// Color of numeric literals.
  final Color number;

  /// Background of the code block. If null, [MarkdownStyleSheet.code].
  final Color? background;

  /// Default text color of code. If null, the body text color.
  final Color? foreground;

  /// Returns a copy with only the specified fields replaced.
  ///
  /// Passing null for [background] or [foreground] means "no replacement"
  /// (to reset to null, build a new instance with the constructor).
  MarkdownXSyntaxColors copyWith({
    Color? keyword,
    Color? string,
    Color? comment,
    Color? number,
    Color? background,
    Color? foreground,
  }) => MarkdownXSyntaxColors(
    keyword: keyword ?? this.keyword,
    string: string ?? this.string,
    comment: comment ?? this.comment,
    number: number ?? this.number,
    background: background ?? this.background,
    foreground: foreground ?? this.foreground,
  );

  @override
  bool operator ==(Object other) =>
      other is MarkdownXSyntaxColors &&
      other.keyword == keyword &&
      other.string == string &&
      other.comment == comment &&
      other.number == number &&
      other.background == background &&
      other.foreground == foreground;

  @override
  int get hashCode =>
      Object.hash(keyword, string, comment, number, background, foreground);
}

/// Settings for the code block header (language name and copy button).
///
/// By default neither is shown, keeping the previous appearance. The header is excluded from selection and copying.
@immutable
class MarkdownXCodeBlockOptions {
  /// Creates the code block header settings. By default neither is shown.
  const MarkdownXCodeBlockOptions({
    this.showLanguage = false,
    this.showCopyButton = false,
    this.copyTooltip,
    this.copiedTooltip = 'Copied',
    this.feedbackDuration = const Duration(seconds: 2),
  });

  /// Shows the fence language name in the header. Not shown for a code block without a language name.
  final bool showLanguage;

  /// Shows a button that copies the whole code to the clipboard (even for code split across multiple
  /// `Text`s when it exceeds 200 lines, the full text is copied).
  final bool showCopyButton;

  /// Tooltip and screen-reader label of the button. If null, `MaterialLocalizations.copyButtonLabel`.
  final String? copyTooltip;

  /// Tooltip and screen-reader label shown for [feedbackDuration] after copying.
  final String copiedTooltip;

  /// How long the icon stays changed after copying.
  final Duration feedbackDuration;

  /// Returns a copy with only the specified fields replaced.
  ///
  /// Passing null for [copyTooltip] means "no replacement".
  MarkdownXCodeBlockOptions copyWith({
    bool? showLanguage,
    bool? showCopyButton,
    String? copyTooltip,
    String? copiedTooltip,
    Duration? feedbackDuration,
  }) => MarkdownXCodeBlockOptions(
    showLanguage: showLanguage ?? this.showLanguage,
    showCopyButton: showCopyButton ?? this.showCopyButton,
    copyTooltip: copyTooltip ?? this.copyTooltip,
    copiedTooltip: copiedTooltip ?? this.copiedTooltip,
    feedbackDuration: feedbackDuration ?? this.feedbackDuration,
  );

  @override
  bool operator ==(Object other) =>
      other is MarkdownXCodeBlockOptions &&
      other.showLanguage == showLanguage &&
      other.showCopyButton == showCopyButton &&
      other.copyTooltip == copyTooltip &&
      other.copiedTooltip == copiedTooltip &&
      other.feedbackDuration == feedbackDuration;

  @override
  int get hashCode => Object.hash(
    showLanguage,
    showCopyButton,
    copyTooltip,
    copiedTooltip,
    feedbackDuration,
  );
}
