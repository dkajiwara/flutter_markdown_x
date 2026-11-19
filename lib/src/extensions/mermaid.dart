/// Mermaid diagrams (an optional extension). Use it from `package:flutter_markdown_x/mermaid.dart`.
///
/// It does not depend on any Mermaid rendering library. The app passes a widget through
/// [MarkdownXMermaidBuilder]. Without a builder, the fenced code block is shown as it is.
/// See doc/mermaid.md for the approach and limitations.
library;

import 'package:material_ui/material_ui.dart';

import 'extension.dart';
import '../ir/nodes.dart';
import '../widgets/renderer.dart';

/// A function that builds the widget of a Mermaid diagram.
///
/// [source] is the diagram text inside the fence, without the fence lines and without
/// the trailing line break. The builder is not called while the fence is still open
/// during streaming (unless `whileStreaming` is set).
///
/// If the builder throws, the code block is shown instead and the error is
/// reported once with `FlutterError.reportError`. Only an exception thrown by the builder
/// function itself is caught; one thrown later while the returned widget builds is not.
typedef MarkdownXMermaidBuilder = Widget Function(
  BuildContext context,
  String source,
);

/// The `type` of the Mermaid [MdxCustomBlock].
const markdownXMermaidType = 'mermaid';

/// The attribute that holds the diagram source.
const _sourceAttribute = 'source';

/// The attribute set to `true` while the fence is still open at the tail of a stream.
const _pendingAttribute = 'pending';

/// Placed as the first word of the info string of a still-open fence by the source
/// transform, and removed again by the block transform. One private-use character.
const _pendingMark = '';

/// The shared extension: ```` ```mermaid ```` blocks become Mermaid custom blocks, and an
/// unclosed one at the tail of a stream is marked pending.
///
/// Extensions are cached by instance identity, so reuse it.
const markdownXMermaidExtension = MarkdownXExtension(
  transformSource: _markPendingFence,
  transformBlock: _toBlock,
);

/// Like [markdownXMermaidExtension] but never marks a block pending (for `whileStreaming`).
const _eagerExtension = MarkdownXExtension(transformBlock: _toBlock);

/// The opening line of a fence (also inside quotes and lists). Mirrors the streaming repair.
final _fenceOpen = RegExp(
  r'^([ \t>]*(?:(?:[-*+]|\d{1,9}[.)])[ \t]+)*)(`{3,}(?=[^`]*$)|~{3,})',
);
final _quotePrefix = RegExp(r'^[\s>]+');
final _mermaidInfo = RegExp(r'^\s*mermaid(?=\s|$)(.*)$', caseSensitive: false);

/// Marks a mermaid fence that is still open at the end of the (streaming) [source].
String _markPendingFence(String source, {required bool streaming}) {
  if (!streaming || !source.contains(RegExp('mermaid', caseSensitive: false))) {
    return source;
  }
  final lines = source.split('\n');
  String? fence;
  var fenceLine = -1;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (fence != null) {
      final t = line.replaceFirst(_quotePrefix, '').trim();
      if (t.startsWith(fence) && t.replaceAll(fence[0], '').isEmpty) {
        fence = null;
      }
    } else {
      final open = _fenceOpen.firstMatch(line);
      if (open != null) {
        fence = open[2];
        fenceLine = i;
      }
    }
  }
  if (fence == null) return source;
  final line = lines[fenceLine];
  final open = _fenceOpen.firstMatch(line)!;
  final info = _mermaidInfo.firstMatch(line.substring(open.end));
  if (info == null) return source;
  final rest = info[1]!.trim();
  if (rest == _pendingMark || rest.startsWith('$_pendingMark ')) return source;
  lines[fenceLine] =
      '${open[0]} mermaid $_pendingMark${rest.isEmpty ? '' : ' $rest'}';
  return lines.join('\n');
}

/// Turns a mermaid code block into a custom block that keeps the code block as its content.
MdxBlock? _toBlock(MdxBlock block) {
  if (block is! MdxCodeBlock) return null;
  if (block.language?.toLowerCase() != markdownXMermaidType) return null;
  var info = block.info?.trim();
  var pending = false;
  if (info != null &&
      (info == _pendingMark || info.startsWith('$_pendingMark '))) {
    pending = true;
    info = info.substring(_pendingMark.length).trim();
    if (info.isEmpty) info = null;
  }
  final code = pending
      ? MdxCodeBlock(block.code, language: block.language, info: info)
      : block;
  return MdxCustomBlock(
    markdownXMermaidType,
    attributes: {
      _sourceAttribute: block.code
          .replaceAll('\r', '')
          .replaceFirst(_trailingBreaks, ''),
      if (pending) _pendingAttribute: 'true',
    },
    blocks: [code],
  );
}

final _trailingBreaks = RegExp(r'\n+$');

/// A bundle of Mermaid settings. Holds the extension and the block builder.
///
/// ```dart
/// final mermaid = MarkdownXMermaid(
///   builder: (context, source) => MyDiagram(source),
/// );
///
/// Markdown(
///   data: text,
///   extensions: [mermaid.extension],
///   blockBuilder: mermaid.blockBuilder,
/// );
/// ```
///
/// Reuse it as a field or top-level value instead of recreating it on every build
/// (the identity of the extension and builder is used for cache decisions).
class MarkdownXMermaid {
  /// If [builder] is null, mermaid fences are shown as normal code blocks.
  ///
  /// While a fence is still open at the tail of a stream, the code block is shown and
  /// [builder] is not called, because a half-written diagram is usually a syntax error.
  /// Set [whileStreaming] to true to call it for partial sources as well.
  ///
  /// [semanticLabel] is the screen-reader label of a rendered diagram.
  MarkdownXMermaid({
    this.builder,
    this.whileStreaming = false,
    this.semanticLabel = 'Mermaid diagram',
  }) : extension = whileStreaming ? _eagerExtension : markdownXMermaidExtension,
       blockBuilder = _blockBuilder(builder, semanticLabel);

  /// The builder that draws a diagram. If null, the code block is shown.
  final MarkdownXMermaidBuilder? builder;

  /// Whether the builder also receives the source of a fence that is still open during streaming.
  final bool whileStreaming;

  /// The screen-reader label of a rendered diagram.
  final String semanticLabel;

  /// The extension to pass to `Markdown(extensions: [...])`.
  final MarkdownXExtension extension;

  /// Pass it to `Markdown(blockBuilder: ...)`. It returns null for blocks that are not
  /// Mermaid diagrams, so you can compose it by calling your own builder after it.
  final MarkdownXBlockBuilder blockBuilder;
}

MarkdownXBlockBuilder _blockBuilder(
  MarkdownXMermaidBuilder? builder,
  String semanticLabel,
) {
  return (context, block, buildDefault) {
    if (builder == null ||
        block is! MdxCustomBlock ||
        block.type != markdownXMermaidType) {
      return null;
    }
    // A fence that is still open is shown as the code block (the default rendering).
    if (block.attributes[_pendingAttribute] == 'true') return null;
    return _MermaidView(
      source: block.attributes[_sourceAttribute] ?? '',
      builder: builder,
      semanticLabel: semanticLabel,
      fallback: buildDefault,
    );
  };
}

/// Calls the app's builder, falls back to the code block when it throws, and handles
/// semantics and selection/copy.
class _MermaidView extends StatefulWidget {
  const _MermaidView({
    required this.source,
    required this.builder,
    required this.semanticLabel,
    required this.fallback,
  });

  final String source;
  final MarkdownXMermaidBuilder builder;
  final String semanticLabel;
  final Widget Function() fallback;

  @override
  State<_MermaidView> createState() => _MermaidViewState();
}

class _MermaidViewState extends State<_MermaidView> {
  /// The source whose failure has already been reported.
  String? _reportedSource;

  @override
  Widget build(BuildContext context) {
    final Widget diagram;
    try {
      diagram = widget.builder(context, widget.source);
    } catch (error, stack) {
      if (_reportedSource != widget.source) {
        _reportedSource = widget.source;
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'flutter_markdown_x',
            context: ErrorDescription('while building a Mermaid diagram'),
          ),
        );
      }
      return widget.fallback();
    }
    _reportedSource = null;
    var visual = diagram;
    // For selection and copy, the diagram is excluded and a transparent copy of the source,
    // stretched to the same size, is overlaid. Nothing is overlaid outside a SelectionArea.
    if (SelectionContainer.maybeOf(context) != null) {
      visual = Stack(
        children: [
          SelectionContainer.disabled(child: diagram),
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.fill,
              child: Text(
                widget.source,
                style: const TextStyle(color: Color(0x00000000)),
              ),
            ),
          ),
        ],
      );
    }
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      child: visual,
    );
  }
}
