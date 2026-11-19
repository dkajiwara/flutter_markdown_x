/// Math (an optional extension). Use it from `package:flutter_markdown_x/math.dart`.
///
/// It does not depend on any math rendering library. The app passes a widget such as
/// `flutter_math_fork` through [MarkdownXMathBuilder]. Without a builder, the TeX source is shown
/// in monospace. See doc/math.md for the approach and limitations.
library;

import 'package:material_ui/material_ui.dart';

import 'extension.dart';
import 'math_source.dart';
import '../ir/nodes.dart';
import '../widgets/renderer.dart';

/// A function that builds a math widget.
///
/// - [tex]: The TeX without the delimiters (`$`, `\(`). Surrounding whitespace is trimmed.
/// - [display]: Whether it is a math block on its own line (`$$...$$`, `\[...\]`). `$$...$$` in the middle of a paragraph is also true.
/// - [style]: The text style at that position. Using its `fontSize` and `color` for the math keeps it
///   aligned with the surrounding text. `fontSize` is the value before the text scale is applied. A widget that
///   applies the `MediaQuery` text scaler itself, like `Text` or `Math.tex`, can take it as is and
///   gets scaled. A widget that does not scale (such as `CustomPaint`) must apply
///   `MediaQuery.textScalerOf(context).scale(style.fontSize!)` itself.
///
/// Must not throw on math syntax errors (use the library's onError equivalent).
typedef MarkdownXMathBuilder = Widget Function(
  BuildContext context,
  String tex, {
  required bool display,
  required TextStyle style,
});

/// The `type` of math [MdxCustomInline] and [MdxCustomBlock].
const markdownXMathType = 'math';

/// The shared instance of the math transform ([protectMath] and IR restoration) with `$...$`, `$$...$$`, `\(...\)` and `\[...\]`
/// all enabled.
///
/// Extensions are cached by instance identity, so reuse it. To limit the delimiters,
/// use `dollar` and `bracket` of [MarkdownXMath].
final markdownXMathExtension = _extension(dollar: true, bracket: true);

MarkdownXExtension _extension({required bool dollar, required bool bracket}) =>
    MarkdownXExtension(
      transformSource: (source, {required streaming}) => protectMath(
        source,
        streaming: streaming,
        dollar: dollar,
        bracket: bracket,
      ),
      transformInline: _restore,
      // Restore escapes left in text the parser does not interpret as inline, such as inside `<summary>`.
      inlineSyntaxes: [_leftoverSyntax],
      transformBlock: _toBlock,
    );

final _leftoverSyntax = MarkdownXInlineSyntax(
  pattern: RegExp('`$mathMarker([mp])([^`]*)`'),
  build: (match) => _mathInline(match[1]!, match[2]!),
);

/// Turns an escaped code span back into a math inline.
MdxInline? _restore(MdxInline inline) {
  if (inline is! MdxStyled || inline.kind != MdxStyleKind.code) return null;
  if (inline.children.length != 1) return null;
  final child = inline.children.single;
  if (child is! MdxText) return null;
  final text = child.text;
  if (text.length < 3 || !text.startsWith(mathMarker)) return null;
  return _mathInline(text[1], text.substring(2));
}

MdxInline? _mathInline(String kind, String payload) {
  if (kind != mathKindComplete && kind != mathKindPending) return null;
  final raw = decodeMathPayload(payload);
  final pending = kind == mathKindPending;
  final parsed = _unwrap(raw, pending: pending);
  if (parsed == null) return null;
  // What to show when there is no builder. For an unfinished one, show only the TeX without delimiters.
  final shown = pending ? parsed.tex : raw;
  return MdxCustomInline(
    markdownXMathType,
    attributes: {
      'tex': parsed.tex,
      'display': parsed.display ? 'true' : 'false',
      'raw': raw,
      if (pending) 'pending': 'true',
    },
    children: shown.isEmpty
        ? const []
        : [
            MdxStyled(MdxStyleKind.code, [MdxText(shown)]),
          ],
  );
}

({String tex, bool display})? _unwrap(String raw, {required bool pending}) {
  String open;
  String close;
  bool display;
  if (raw.startsWith(r'$$')) {
    (open, close, display) = (r'$$', r'$$', true);
  } else if (raw.startsWith(r'$')) {
    (open, close, display) = (r'$', r'$', false);
  } else if (raw.startsWith(r'\[')) {
    (open, close, display) = (r'\[', r'\]', true);
  } else if (raw.startsWith(r'\(')) {
    (open, close, display) = (r'\(', r'\)', false);
  } else {
    return null;
  }
  var inner = raw.substring(open.length);
  if (!pending) {
    if (!inner.endsWith(close)) return null;
    inner = inner.substring(0, inner.length - close.length);
  }
  return (tex: inner.trim(), display: display);
}

/// Turns a paragraph containing only one math expression (display) into a block.
MdxBlock? _toBlock(MdxBlock block) {
  if (block is MdxCodeBlock) {
    // Restore escapes left in a code block, which should be exempt from escaping, to the original characters (a safety net).
    final code = restoreMathMarkers(block.code);
    return identical(code, block.code)
        ? null
        : MdxCodeBlock(code, language: block.language, info: block.info);
  }
  if (block is! MdxParagraph) return null;
  MdxCustomInline? math;
  for (final inline in block.inlines) {
    if (inline is MdxCustomInline && inline.type == markdownXMathType) {
      if (math != null) return null;
      math = inline;
    } else if (inline is MdxSoftBreak) {
      continue;
    } else if (inline is! MdxText || inline.text.trim().isNotEmpty) {
      return null;
    }
  }
  if (math == null || math.attributes['display'] != 'true') return null;
  return MdxCustomBlock(
    markdownXMathType,
    attributes: math.attributes,
    inlines: math.children,
  );
}

/// A bundle of math settings. Holds the extension and the rendering builder.
///
/// ```dart
/// final math = MarkdownXMath(builder: (context, tex, {required display, required style}) =>
///     Math.tex(tex, mathStyle: display ? MathStyle.display : MathStyle.text, textStyle: style));
///
/// Markdown(
///   data: text,
///   extensions: [math.extension],
///   inlineBuilder: math.inlineBuilder,
///   blockBuilder: math.blockBuilder,
/// );
/// ```
///
/// Reuse it as a field or top-level value instead of recreating it on every build
/// (the identity of the extension and builder is used for cache decisions).
class MarkdownXMath {
  /// If [builder] is null, the TeX source is shown in monospace.
  ///
  /// If [dollar] is false, `$...$` and `$$...$$` are not treated as math; if [bracket] is false,
  /// `\(...\)` and `\[...\]` are not. `\[` and `\(` are also symbol escapes in CommonMark,
  /// so set [bracket] to false for such documents.
  MarkdownXMath({this.builder, bool dollar = true, bool bracket = true})
    : extension = dollar && bracket
          ? markdownXMathExtension
          : _extension(dollar: dollar, bracket: bracket),
      inlineBuilder = _inlineBuilder(builder),
      blockBuilder = _blockBuilder(builder);

  /// The builder that draws math. If null, the TeX source is shown in monospace.
  final MarkdownXMathBuilder? builder;

  /// The extension to pass to `Markdown(extensions: [...])`.
  final MarkdownXExtension extension;

  /// Pass it to `Markdown(inlineBuilder: ...)`. It returns null for non-math inlines,
  /// so you can compose it by calling your own builder first.
  final MarkdownXInlineBuilder inlineBuilder;

  /// Pass it to `Markdown(blockBuilder: ...)`. It returns null for non-math blocks.
  final MarkdownXBlockBuilder blockBuilder;
}

bool _isMath(MdxNode node) => switch (node) {
  MdxCustomInline() => node.type == markdownXMathType,
  MdxCustomBlock() => node.type == markdownXMathType,
  _ => false,
};

MarkdownXInlineBuilder _inlineBuilder(MarkdownXMathBuilder? builder) {
  return (context, inline, style, buildDefault) {
    if (builder == null || inline is! MdxCustomInline || !_isMath(inline)) {
      return null;
    }
    // Unfinished math is not passed to the builder (partial TeX would be a syntax error); show the source instead.
    if (inline.attributes['pending'] == 'true') return null;
    final tex = inline.attributes['tex'] ?? '';
    final display = inline.attributes['display'] == 'true';
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: _MathAtom(
        tex: tex,
        raw: inline.attributes['raw'] ?? tex,
        child: Builder(
          builder: (context) =>
              builder(context, tex, display: display, style: style),
        ),
      ),
    );
  };
}

MarkdownXBlockBuilder _blockBuilder(MarkdownXMathBuilder? builder) {
  return (context, block, buildDefault) {
    if (block is! MdxCustomBlock || !_isMath(block)) return null;
    return _MathBlock(block: block, builder: builder);
  };
}

/// Handles semantics and selection/copy for one math expression.
///
/// The semantics label is the TeX source; the contents of the math widget are not read aloud.
/// For selection and copy, the math widget is excluded from selection and a transparent copy of the source
/// (with delimiters), stretched to the same size, is overlaid. What is copied is the source as written, with its delimiters.
/// Nothing is overlaid outside a `SelectionArea`.
class _MathAtom extends StatelessWidget {
  const _MathAtom({required this.tex, required this.raw, required this.child});

  final String tex;
  final String raw;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    var visual = child;
    if (SelectionContainer.maybeOf(context) != null) {
      visual = Stack(
        children: [
          SelectionContainer.disabled(child: child),
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.fill,
              child: Text(
                raw,
                style: const TextStyle(color: Color(0x00000000)),
              ),
            ),
          ),
        ],
      );
    }
    return Semantics(label: tex, excludeSemantics: true, child: visual);
  }
}

/// Display math. Scrolls horizontally when wider than the available width and is centered when narrower.
class _MathBlock extends StatelessWidget {
  const _MathBlock({required this.block, required this.builder});

  final MdxCustomBlock block;
  final MarkdownXMathBuilder? builder;

  @override
  Widget build(BuildContext context) {
    final sheet = MdxScope.of(context).relay.styleSheet;
    final tex = block.attributes['tex'] ?? '';
    final raw = block.attributes['raw'] ?? tex;
    final pending = block.attributes['pending'] == 'true';
    final Widget content;
    if (builder == null || pending) {
      // Show the source. Unfinished math does not show delimiters.
      final shown = pending ? tex : raw;
      content = Semantics(
        label: tex,
        excludeSemantics: true,
        child: Text(shown, style: sheet.code, textScaler: sheet.textScaler),
      );
    } else {
      final base = DefaultTextStyle.of(context).style.merge(sheet.p);
      content = _MathAtom(
        tex: tex,
        raw: raw,
        child: Builder(
          builder: (context) =>
              builder!(context, tex, display: true, style: base),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: constraints.hasBoundedWidth ? constraints.maxWidth : 0,
          ),
          child: Center(child: content),
        ),
      ),
    );
  }
}
