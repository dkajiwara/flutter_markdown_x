import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_markdown_x/math.dart';
import 'package:flutter_markdown_x/mermaid.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

import 'media.dart';

// Keep these at top level: the extensions and builders are compared by identity
// for caching, so they must not be recreated on every build.

/// Math drawn by flutter_math_fork.
final markdownMath = MarkdownXMath(
  builder: (context, tex, {required display, required style}) => Math.tex(
    tex,
    mathStyle: display ? MathStyle.display : MathStyle.text,
    textStyle: style,
    // On a syntax error, show the original in red (do not throw).
    onErrorFallback: (error) =>
        Text(tex, style: style.copyWith(color: Colors.red)),
  ),
);

/// Mermaid diagrams drawn by mermaid_flutter.
final markdownMermaid = MarkdownXMermaid(
  builder: (context, source) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: MermaidDiagram(
      source: source,
      // Follow the app's light or dark theme instead of Mermaid's default
      // (light) colors. `MaterialMermaidTheme.fromTheme` takes a ThemeData of
      // the deprecated SDK Material library, not material_ui's, so pick the
      // Mermaid theme by brightness.
      theme: Theme.of(context).brightness == Brightness.dark
          ? core.MermaidTheme.darkTheme
          : core.MermaidTheme.defaultTheme,
      errorBuilder: (context, error) => Text(
        'Diagram error: $error',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ),
  ),
);

/// The extensions of both, for `Markdown(extensions: ...)`.
final externalLibExtensions = [
  markdownMath.extension,
  markdownMermaid.extension,
];

/// Math is only inline here; Mermaid only has blocks.
final MarkdownXInlineBuilder externalLibInlineBuilder =
    markdownMath.inlineBuilder;

/// Each builder returns null for blocks it does not own, so they compose with `??`.
Widget? externalLibBlockBuilder(
  BuildContext context,
  MdxBlock block,
  Widget Function() buildDefault,
) =>
    markdownMath.blockBuilder(context, block, buildDefault) ??
    markdownMermaid.blockBuilder(context, block, buildDefault) ??
    mediaBlockBuilder(context, block, buildDefault);
