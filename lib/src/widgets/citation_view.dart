import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../style/extension_style.dart';

/// The default citation display. Puts each id in a small rounded chip and lays the chips out in a row.
///
/// When [onTap] is given, the chips can be operated by tap and keyboard (focus
/// with Tab, activate with Enter or Space) and their semantics are a button.
/// Without it they are not interactive and only the label is read aloud.
/// The label is decided by [MarkdownXCitationStyle.semanticsLabel].
/// The chips are sized small to match the text, so they do not meet the minimum touch target size.
class MdxCitationChips extends StatelessWidget {
  /// Creates a Widget that lays out a chip for each of [ids].
  const MdxCitationChips({
    super.key,
    required this.ids,
    required this.textStyle,
    required this.style,
    this.onTap,
  });

  /// The IDs of the citations to display. One chip is drawn per ID.
  final List<String> ids;

  /// The text style surrounding the chips. The chip font size is this scaled by a factor.
  final TextStyle textStyle;

  /// The chip colors and label settings.
  final MarkdownXCitationStyle style;

  /// Called with the ID when a chip is tapped. Null means the chips are not interactive.
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < ids.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _CitationChip(
              id: ids[i],
              textStyle: textStyle,
              style: style,
              onTap: onTap,
            ),
          ),
      ],
    );
  }
}

class _CitationChip extends StatefulWidget {
  const _CitationChip({
    required this.id,
    required this.textStyle,
    required this.style,
    required this.onTap,
  });

  final String id;
  final TextStyle textStyle;
  final MarkdownXCitationStyle style;
  final ValueChanged<String>? onTap;

  @override
  State<_CitationChip> createState() => _CitationChipState();
}

class _CitationChipState extends State<_CitationChip> {
  bool _focused = false;

  void _activate() => widget.onTap?.call(widget.id);

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.space)) {
      _activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final base = widget.textStyle.fontSize ?? 14;
    final tappable = widget.onTap != null;
    Widget chip = Container(
      padding: EdgeInsets.symmetric(horizontal: base * 0.4),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(base),
        border: _focused
            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
            : null,
      ),
      child: Text(
        widget.id,
        style: widget.textStyle.copyWith(
          color: style.foreground,
          fontSize: base * style.fontScale,
          height: 1.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    if (tappable) {
      chip = Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: _onKeyEvent,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _activate,
            child: chip,
          ),
        ),
      );
    }
    return Semantics(
      label: style.semanticsLabel(widget.id),
      button: tappable,
      onTap: tappable ? _activate : null,
      excludeSemantics: true,
      child: chip,
    );
  }
}
