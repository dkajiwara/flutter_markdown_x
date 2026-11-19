import 'dart:async';

import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:material_ui/material_ui.dart';

import 'external_libs.dart';
import 'sample.dart';

/// Number of characters appended at a time when simulating streaming.
const _streamChunkSize = 6;

/// Interval between appends when simulating streaming.
const _streamInterval = Duration(milliseconds: 16);

/// Opaque payloads (such as the base64 of a `data:` image) that a model would
/// emit as a few large tokens. Streaming them a few characters at a time would
/// keep the half-written image hidden for tens of seconds, so the demo jumps
/// over each payload in one step.
final _opaquePayload = RegExp(r';base64,[A-Za-z0-9+/=]+');

/// The next streamed length after [length]: [_streamChunkSize] characters
/// later, extended to the end of an opaque payload it would stop inside.
int _nextStreamLength(int length) {
  final next = (length + _streamChunkSize).clamp(0, sampleMarkdown.length);
  for (final match in _opaquePayload.allMatches(sampleMarkdown)) {
    if (next > match.start && next < match.end) return match.end;
  }
  return next;
}

/// Base for resolving relative image paths (a value for checking how the sample's images resolve).
const _imageDirectory = 'https://example.invalid/docs/';

const _pagePadding = EdgeInsets.all(16);
const _seedColor = Colors.indigo;

/// The bundled monospace font (JetBrains Mono, declared in pubspec.yaml). The web build draws with
/// CanvasKit, which cannot use system fonts, so `monospace` or `Menlo` would render proportionally
/// there. Bundling a font and putting it in `code` gives the same look on every platform.
const _monospaceFamily = 'JetBrainsMono';

/// The theme's style sheet with [_monospaceFamily] for inline code, code blocks, `<samp>` and
/// `<tt>` (they all read `MarkdownStyleSheet.code`) and the given [codeBlockOptions].
MarkdownStyleSheet exampleStyleSheet(
  ThemeData theme, {
  MarkdownXCodeBlockOptions? codeBlockOptions,
}) {
  final base = MarkdownStyleSheet.fromTheme(theme);
  return base.copyWith(
    code: base.code!.copyWith(
      fontFamily: _monospaceFamily,
      // A non-null fallback stops the package from adding its default monospace fallbacks.
      fontFamilyFallback: const ['monospace'],
    ),
    codeBlockOptions: codeBlockOptions,
  );
}

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_markdown_x example',
      theme: ThemeData(colorSchemeSeed: _seedColor),
      darkTheme: ThemeData(
        colorSchemeSeed: _seedColor,
        brightness: Brightness.dark,
      ),
      home: const ExamplePage(),
    );
  }
}

class ExamplePage extends StatelessWidget {
  const ExamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('flutter_markdown_x'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Static'),
              Tab(text: 'Streaming'),
            ],
          ),
        ),
        body: const TabBarView(children: [_StaticTab(), _StreamingTab()]),
      ),
    );
  }
}

/// The citation transform is placed at top level so it is not recreated on every build.
final _citations = markdownXCitationExtension();

void _showLink(BuildContext context, String href) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(href)));
}

class _StaticTab extends StatefulWidget {
  const _StaticTab();

  @override
  State<_StaticTab> createState() => _StaticTabState();
}

class _StaticTabState extends State<_StaticTab> {
  // The checkbox state is the Markdown text, so the app owns a mutable copy of the sample.
  String _data = sampleMarkdown;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: Markdown(
        data: _data,
        // Tapping a task list checkbox flips its `[ ]` / `[x]` in the text.
        onTapCheckbox: (task) => setState(() => _data = task.toggle(_data)),
        styleSheet: exampleStyleSheet(
          Theme.of(context),
          // Show the language name and a copy button on code blocks (off by default).
          codeBlockOptions: const MarkdownXCodeBlockOptions(
            showLanguage: true,
            showCopyButton: true,
          ),
        ),
        padding: _pagePadding,
        onTapLink: (text, href, title) => _showLink(context, href ?? text),
        imageDirectory: _imageDirectory,
        extensions: [
          _citations,
          markdownXEmojiExtension,
          ...externalLibExtensions,
        ],
        inlineBuilder: externalLibInlineBuilder,
        blockBuilder: externalLibBlockBuilder,
        onTapCitation: (id) => _showLink(context, 'citation: $id'),
        onTapImage: (image, resolved) =>
            _showLink(context, 'image: ${resolved ?? image.src}'),
      ),
    );
  }
}

/// Shows Markdown that is appended bit by bit, like an LLM response.
class _StreamingTab extends StatefulWidget {
  const _StreamingTab();

  @override
  State<_StreamingTab> createState() => _StreamingTabState();
}

class _StreamingTabState extends State<_StreamingTab> {
  Timer? _timer;
  int _length = 0;

  bool get _running => _timer != null;

  void _toggle() {
    if (_running) {
      _stop();
      return;
    }
    if (_length >= sampleMarkdown.length) _length = 0;
    _timer = Timer.periodic(_streamInterval, (_) {
      setState(() {
        _length = _nextStreamLength(_length);
      });
      if (_length >= sampleMarkdown.length) _stop();
    });
    setState(() {});
  }

  void _stop() {
    _timer?.cancel();
    setState(() => _timer = null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggle,
        icon: Icon(_running ? Icons.stop : Icons.play_arrow),
        label: Text(_running ? 'Stop' : 'Start'),
      ),
      body: Markdown(
        data: sampleMarkdown.substring(0, _length),
        // While appending, the tail is incomplete, so hide unfinished markers. Set to false when done.
        streaming: _length < sampleMarkdown.length,
        styleSheet: exampleStyleSheet(Theme.of(context)),
        padding: _pagePadding,
        extensions: [
          _citations,
          markdownXEmojiExtension,
          ...externalLibExtensions,
        ],
        inlineBuilder: externalLibInlineBuilder,
        blockBuilder: externalLibBlockBuilder,
        onTapCitation: (id) => _showLink(context, 'citation: $id'),
        onTapLink: (text, href, title) => _showLink(context, href ?? text),
      ),
    );
  }
}
