import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../style/style.dart';

/// The header placed above a code block (language name and copy button).
///
/// Excluded from selection and copy (`SelectionContainer.disabled`). Regardless of text direction,
/// the language name is on the left and the button on the right (because the code body is always LTR).
class CodeBlockHeader extends StatefulWidget {
  /// Creates the header.
  const CodeBlockHeader({
    super.key,
    required this.options,
    required this.language,
    required this.code,
    required this.color,
    required this.textStyle,
  });

  /// Settings for what the header shows (language name, copy button, display after copying).
  final MarkdownXCodeBlockOptions options;

  /// The language name shown in the header. Not shown if null or empty.
  final String? language;

  /// The full text the copy button puts on the clipboard (the whole text even if drawn in chunks).
  final String code;

  /// The color of the language name and the copy button.
  final Color color;

  /// The text style of the language name. The color is overridden by [color].
  final TextStyle textStyle;

  /// Whether a header needs to be shown, based on [options] and [language].
  static bool isNeeded(MarkdownXCodeBlockOptions options, String? language) =>
      options.showCopyButton ||
      (options.showLanguage && language != null && language.isNotEmpty);

  @override
  State<CodeBlockHeader> createState() => _CodeBlockHeaderState();
}

class _CodeBlockHeaderState extends State<CodeBlockHeader> {
  Timer? _timer;
  bool _copied = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    _timer?.cancel();
    setState(() => _copied = true);
    _timer = Timer(widget.options.feedbackDuration, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    final language = widget.language;
    final label =
        options.showLanguage && language != null && language.isNotEmpty
        ? language
        : null;
    final tooltip = _copied
        ? options.copiedTooltip
        : options.copyTooltip ??
              MaterialLocalizations.of(context).copyButtonLabel;
    return SelectionContainer.disabled(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: Row(
              children: [
                if (label != null)
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: widget.textStyle.copyWith(
                        color: widget.color,
                        height: 1.2,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (options.showCopyButton)
                  Semantics(
                    liveRegion: true,
                    child: IconButton(
                      onPressed: _copy,
                      tooltip: tooltip,
                      iconSize: 16,
                      color: widget.color,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(_copied ? Icons.check : Icons.copy),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
