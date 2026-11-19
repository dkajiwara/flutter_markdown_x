import 'package:material_ui/material_ui.dart';

import '../extensions/alerts.dart';
import '../ir/nodes.dart';
import 'renderer.dart';
import '../style/extension_style.dart';
import '../style/style.dart';

/// The default alert view. Wraps the icon, title and body in a border on the start side in the kind's color and a light background.
///
/// The border and padding use [BorderDirectional] and [EdgeInsetsDirectional], so in RTL
/// they appear on the right. The title is drawn as text, so it is read aloud and included in selection and copy
/// (the icon is decorative and excluded).
class MdxAlertView extends StatelessWidget {
  /// Creates a widget that shows the alert in [block].
  const MdxAlertView({
    super.key,
    required this.block,
    this.blockContext = const MdxBlockContext(),
  });

  /// The alert block to show. The kind is determined by the `kind` attribute; unknown kinds are drawn as a note.
  final MdxCustomBlock block;

  /// Where the alert sits (for example inside a quote).
  final MdxBlockContext blockContext;

  @override
  Widget build(BuildContext context) {
    final sheet = MdxScope.of(context).relay.styleSheet;
    final alerts =
        sheet.alerts ??
        (Theme.of(context).brightness == Brightness.dark
            ? MarkdownXAlertStyle.dark
            : MarkdownXAlertStyle.light);
    final kind = markdownXAlertKindOf(block) ?? MarkdownXAlertKind.note;
    final k = alerts.of(kind);
    final paragraph =
        (blockContext.inQuote ? sheet.blockquote : sheet.p) ??
        const TextStyle();
    final fontSize = paragraph.fontSize ?? MarkdownXDefaults.fallbackFontSize;
    final spacing = sheet.blockSpacing ?? 0;

    return Semantics(
      container: true,
      child: Container(
        width: double.infinity,
        padding: MarkdownXDefaults.alertPadding,
        decoration: BoxDecoration(
          color: k.color.withValues(alpha: alerts.backgroundOpacity),
          border: BorderDirectional(
            start: BorderSide(color: k.color, width: alerts.borderWidth),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Icon(k.icon, size: fontSize * 1.25, color: k.color),
                ),
                SizedBox(width: fontSize * 0.5),
                Flexible(
                  child: Text(
                    k.label,
                    style: paragraph.copyWith(
                      color: k.color,
                      fontWeight: FontWeight.w600,
                    ),
                    textScaler: sheet.textScaler,
                  ),
                ),
              ],
            ),
            for (final child in block.blocks)
              Padding(
                padding: EdgeInsets.only(top: spacing * 0.5),
                child: MdxBlockView(block: child, blockContext: blockContext),
              ),
          ],
        ),
      ),
    );
  }
}
