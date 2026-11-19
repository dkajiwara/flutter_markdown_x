import 'package:material_ui/material_ui.dart';

import '../image/image.dart';
import '../ir/nodes.dart';
import '../style/style.dart';
import 'renderer.dart';

/// The default image display. Handles resolution, loading, error, and tap.
///
/// The alt text is read aloud once by the outer [Semantics] and is not included in
/// the text that gets copied. The loading and error displays and the image's own
/// semantics are excluded.
class MdxImageView extends StatefulWidget {
  /// Creates a Widget that displays [image].
  const MdxImageView({
    super.key,
    required this.image,
    required this.textStyle,
    this.onTapLink,
  });

  /// The image to display.
  final MdxImage image;

  /// The text style used for the default error display (alt).
  final TextStyle textStyle;

  /// The tap of the link this image sits in, if any. Tapping the image triggers it, as in
  /// flutter_markdown. When `onTapImage` is also set, it runs first.
  final VoidCallback? onTapLink;

  @override
  State<MdxImageView> createState() => _MdxImageViewState();
}

class _MdxImageViewState extends State<MdxImageView> {
  Uri? _uri;
  ImageProvider? _provider;
  String? _text;
  Object? _failure;

  // Resolution is redone only when the inputs change (the data URI decode and the
  // provider instance are not recreated on every rebuild).
  MdxImage? _resolvedImage;
  String? _resolvedDirectory;
  MarkdownXImageResolver? _resolvedWith;
  bool _hasResolved = false;

  void _resolve(MdxRelay scope) {
    if (_hasResolved &&
        _resolvedImage == widget.image &&
        _resolvedDirectory == scope.imageDirectory &&
        _resolvedWith == scope.imageResolver) {
      return;
    }
    _hasResolved = true;
    _resolvedImage = widget.image;
    _resolvedDirectory = scope.imageDirectory;
    _resolvedWith = scope.imageResolver;
    _provider = null;
    _text = null;
    _failure = null;
    // The fragment (`#WxH`) is not part of the request.
    final source = markdownXParseImageSource(widget.image.src);
    _uri = markdownXResolveImageUri(source.path, scope.imageDirectory);
    final uri = _uri;
    if (uri == null) {
      _failure = UnsupportedError('Invalid image source: ${widget.image.src}');
      return;
    }
    try {
      _provider = scope.imageResolver?.call(uri, widget.image);
      if (_provider == null &&
          scope.imageDirectory != null &&
          !_hasScheme(source.path) &&
          markdownXImageEscapesDirectory(
            scope.imageDirectory!,
            source.path,
            resolved: uri,
          )) {
        // The default resolver never requests a URL outside imageDirectory.
        _failure = UnsupportedError(
          'Image path escapes imageDirectory: ${source.path}',
        );
        return;
      }
      _provider ??= markdownXDefaultImageProvider(uri);
      if (_provider == null) {
        _text = markdownXDataImageText(uri);
        if (_text == null && !_hasScheme(source.path)) {
          // An explicit imageDirectory is the opt-in to read files strictly below it.
          _provider = markdownXLocalImageProvider(
            uri,
            imageDirectory: scope.imageDirectory,
            src: source.path,
          );
        }
      }
    } on Object catch (error) {
      _failure = error;
      return;
    }
    if (_provider == null && _text == null) {
      _failure = UnsupportedError('Unsupported image source: $uri');
    }
  }

  static bool _hasScheme(String path) =>
      Uri.tryParse(path.trim())?.hasScheme ?? false;

  @override
  Widget build(BuildContext context) {
    final scope = MdxScope.of(context).relay;
    _resolve(scope);
    final image = widget.image;
    final source = markdownXParseImageSource(image.src);
    final size = markdownXNormalizeImageSize(
      source.width ?? image.width,
      source.height ?? image.height,
    );
    final alt = image.alt;
    final hasLabel = alt != null && alt.isNotEmpty;
    final onTapImage = scope.onTapImage;
    final onTapLink = widget.onTapLink;
    final uri = _uri;
    final VoidCallback? onTap = onTapImage == null && onTapLink == null
        ? null
        : () {
            onTapImage?.call(image, uri);
            onTapLink?.call();
          };

    Widget content;
    final provider = _provider;
    final text = _text;
    if (text != null) {
      // data:text/* is shown as text, like flutter_markdown; it has no size.
      return Semantics(
        label: text,
        excludeSemantics: true,
        onTap: onTap,
        child: _tappable(onTap, Text(text, style: widget.textStyle)),
      );
    } else if (provider == null) {
      content = _error(context, scope, _failure ?? 'unknown');
    } else {
      final fadeIn =
          scope.styleSheet.imageFadeInDuration ??
          MarkdownXDefaults.imageFadeInDuration;
      final fades =
          fadeIn > Duration.zero && !MediaQuery.disableAnimationsOf(context);
      content = Image(
        image: provider,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
        frameBuilder: (context, child, frame, synchronous) {
          if (frame == null && !synchronous) return _loading(context, scope);
          // An image from the cache is shown at once; only a load fades in.
          if (synchronous || !fades) return child;
          return _FadeIn(duration: fadeIn, child: child);
        },
        errorBuilder: (context, error, stackTrace) =>
            _error(context, scope, error),
      );
    }
    content = _sized(content, size.width, size.height);
    content = _tappable(onTap, content);
    return Semantics(
      image: hasLabel,
      label: hasLabel ? alt : null,
      onTap: onTap,
      excludeSemantics: true,
      child: SelectionContainer.disabled(child: content),
    );
  }

  static Widget _tappable(VoidCallback? onTap, Widget child) {
    if (onTap == null) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    );
  }

  Widget _loading(BuildContext context, MdxRelay scope) {
    final builder = scope.imageLoadingBuilder;
    return builder == null
        ? const SizedBox.shrink()
        : builder(context, widget.image);
  }

  Widget _error(BuildContext context, MdxRelay scope, Object error) {
    final builder = scope.imageErrorBuilder;
    if (builder != null) return builder(context, widget.image, error);
    return Text(widget.image.alt ?? widget.image.src, style: widget.textStyle);
  }

  /// Fits it into the area of the declared dimensions. When both are given, it
  /// shrinks while preserving the aspect ratio to fit the available width (the loading and error displays use the same area).
  Widget _sized(Widget child, double? width, double? height) {
    if (width != null && height != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: AspectRatio(
          aspectRatio: width / height,
          child: ClipRect(child: SizedBox.expand(child: child)),
        ),
      );
    }
    if (width == null && height == null) return child;
    return SizedBox(width: width, height: height, child: child);
  }
}

/// Fades [child] in once, when it is first built.
///
/// Later frames of an animated image keep the same state, so they do not fade again.
class _FadeIn extends StatefulWidget {
  const _FadeIn({required this.duration, required this.child});

  final Duration duration;
  final Widget child;

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..forward();

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: MarkdownXDefaults.imageFadeInCurve,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}
