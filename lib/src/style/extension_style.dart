import 'package:material_ui/material_ui.dart';

import '../extensions/alerts.dart';

/// The appearance of one alert kind.
@immutable
class MarkdownXAlertKindStyle {
  /// Creates the appearance of one alert kind from [color], [icon] and [label].
  const MarkdownXAlertKindStyle({
    required this.color,
    required this.icon,
    required this.label,
  });

  /// The color of the start-side border, icon and title. The background is a lighter tint of this color.
  final Color color;

  /// The icon shown before the title. It is decorative, so it is excluded from semantics and selection.
  final IconData icon;

  /// The title text. Also used as the semantics label. Replace it with a translated string.
  final String label;

  /// Returns a copy with only the given fields replaced.
  MarkdownXAlertKindStyle copyWith({
    Color? color,
    IconData? icon,
    String? label,
  }) => MarkdownXAlertKindStyle(
    color: color ?? this.color,
    icon: icon ?? this.icon,
    label: label ?? this.label,
  );

  @override
  bool operator ==(Object other) =>
      other is MarkdownXAlertKindStyle &&
      other.color == color &&
      other.icon == icon &&
      other.label == label;

  @override
  int get hashCode => Object.hash(color, icon, label);
}

/// The appearance of GitHub alerts. Holds the color, icon and title for each kind.
@immutable
class MarkdownXAlertStyle {
  /// Creates the alert appearance from the per-kind appearances.
  const MarkdownXAlertStyle({
    required this.note,
    required this.tip,
    required this.important,
    required this.warning,
    required this.caution,
    this.backgroundOpacity = 0.08,
    this.borderWidth = 4.0,
  });

  /// For light backgrounds (the colors of GitHub's light theme).
  static const light = MarkdownXAlertStyle(
    note: MarkdownXAlertKindStyle(
      color: Color(0xFF0969DA),
      icon: Icons.info_outline,
      label: 'Note',
    ),
    tip: MarkdownXAlertKindStyle(
      color: Color(0xFF1A7F37),
      icon: Icons.lightbulb_outline,
      label: 'Tip',
    ),
    important: MarkdownXAlertKindStyle(
      color: Color(0xFF8250DF),
      icon: Icons.announcement_outlined,
      label: 'Important',
    ),
    warning: MarkdownXAlertKindStyle(
      color: Color(0xFF9A6700),
      icon: Icons.warning_amber_outlined,
      label: 'Warning',
    ),
    caution: MarkdownXAlertKindStyle(
      color: Color(0xFFCF222E),
      icon: Icons.report_outlined,
      label: 'Caution',
    ),
  );

  /// For dark backgrounds (the colors of GitHub's dark theme).
  static const dark = MarkdownXAlertStyle(
    note: MarkdownXAlertKindStyle(
      color: Color(0xFF4493F8),
      icon: Icons.info_outline,
      label: 'Note',
    ),
    tip: MarkdownXAlertKindStyle(
      color: Color(0xFF3FB950),
      icon: Icons.lightbulb_outline,
      label: 'Tip',
    ),
    important: MarkdownXAlertKindStyle(
      color: Color(0xFFAB7DF8),
      icon: Icons.announcement_outlined,
      label: 'Important',
    ),
    warning: MarkdownXAlertKindStyle(
      color: Color(0xFFD29922),
      icon: Icons.warning_amber_outlined,
      label: 'Warning',
    ),
    caution: MarkdownXAlertKindStyle(
      color: Color(0xFFF85149),
      icon: Icons.report_outlined,
      label: 'Caution',
    ),
  );

  /// The appearance of `[!NOTE]`.
  final MarkdownXAlertKindStyle note;

  /// The appearance of `[!TIP]`.
  final MarkdownXAlertKindStyle tip;

  /// The appearance of `[!IMPORTANT]`.
  final MarkdownXAlertKindStyle important;

  /// The appearance of `[!WARNING]`.
  final MarkdownXAlertKindStyle warning;

  /// The appearance of `[!CAUTION]`.
  final MarkdownXAlertKindStyle caution;

  /// The opacity of the border color used for the background. 0 means no background.
  final double backgroundOpacity;

  /// The width of the start-side border (logical pixels).
  final double borderWidth;

  /// The appearance of [kind].
  MarkdownXAlertKindStyle of(MarkdownXAlertKind kind) => switch (kind) {
    MarkdownXAlertKind.note => note,
    MarkdownXAlertKind.tip => tip,
    MarkdownXAlertKind.important => important,
    MarkdownXAlertKind.warning => warning,
    MarkdownXAlertKind.caution => caution,
  };

  /// Returns a copy with only the given fields replaced.
  MarkdownXAlertStyle copyWith({
    MarkdownXAlertKindStyle? note,
    MarkdownXAlertKindStyle? tip,
    MarkdownXAlertKindStyle? important,
    MarkdownXAlertKindStyle? warning,
    MarkdownXAlertKindStyle? caution,
    double? backgroundOpacity,
    double? borderWidth,
  }) => MarkdownXAlertStyle(
    note: note ?? this.note,
    tip: tip ?? this.tip,
    important: important ?? this.important,
    warning: warning ?? this.warning,
    caution: caution ?? this.caution,
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    borderWidth: borderWidth ?? this.borderWidth,
  );

  @override
  bool operator ==(Object other) =>
      other is MarkdownXAlertStyle &&
      other.note == note &&
      other.tip == tip &&
      other.important == important &&
      other.warning == warning &&
      other.caution == caution &&
      other.backgroundOpacity == backgroundOpacity &&
      other.borderWidth == borderWidth;

  @override
  int get hashCode => Object.hash(
    note,
    tip,
    important,
    warning,
    caution,
    backgroundOpacity,
    borderWidth,
  );
}

/// A function that builds the semantics label of a citation.
typedef MarkdownXCitationLabel = String Function(String id);

String _defaultCitationLabel(String id) => 'Citation $id';

/// The appearance of a citation chip.
@immutable
class MarkdownXCitationStyle {
  /// Creates the citation chip appearance from the chip colors, font size and semantics.
  const MarkdownXCitationStyle({
    required this.background,
    required this.foreground,
    this.fontScale = 0.75,
    this.semanticsLabel = _defaultCitationLabel,
  });

  /// For light backgrounds.
  static const light = MarkdownXCitationStyle(
    background: Color(0xFFE3E8EF),
    foreground: Color(0xFF1F2937),
  );

  /// For dark backgrounds.
  static const dark = MarkdownXCitationStyle(
    background: Color(0xFF3A4150),
    foreground: Color(0xFFE5E7EB),
  );

  /// The background color of the chip.
  final Color background;

  /// The text color of the ID inside the chip.
  final Color foreground;

  /// The chip's font size as a ratio of the surrounding font size.
  final double fontScale;

  /// The semantics label. Replace it with a translated string.
  final MarkdownXCitationLabel semanticsLabel;

  /// Returns a copy with only the given fields replaced.
  MarkdownXCitationStyle copyWith({
    Color? background,
    Color? foreground,
    double? fontScale,
    MarkdownXCitationLabel? semanticsLabel,
  }) => MarkdownXCitationStyle(
    background: background ?? this.background,
    foreground: foreground ?? this.foreground,
    fontScale: fontScale ?? this.fontScale,
    semanticsLabel: semanticsLabel ?? this.semanticsLabel,
  );

  @override
  bool operator ==(Object other) =>
      other is MarkdownXCitationStyle &&
      other.background == background &&
      other.foreground == foreground &&
      other.fontScale == fontScale &&
      other.semanticsLabel == semanticsLabel;

  @override
  int get hashCode =>
      Object.hash(background, foreground, fontScale, semanticsLabel);
}
