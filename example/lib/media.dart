import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:video_player/video_player.dart';

/// The MIME type of a PDF document.
const _pdfType = 'application/pdf';

/// The file extension of a PDF document.
const _pdfExtension = '.pdf';

/// The scheme of a bundled asset in a media `src` (`asset:assets/sample.pdf`).
const _assetScheme = 'asset';

/// The height of the first-page preview of a PDF.
const _pdfPreviewHeight = 280.0;

/// The aspect ratio of the preview (A4 portrait).
const _pdfPreviewAspectRatio = 210 / 297;

/// The widest a video is laid out, so it stays a part of the document on wide screens.
const _videoMaxWidth = 640.0;

/// The aspect ratio of the video area before the video reports its own.
const _defaultVideoAspectRatio = 16 / 9;

/// Media blocks (`<video>`, `<audio>`, `<iframe>`, `<embed>`, `<object>`).
///
/// Videos play with video_player and PDFs are shown with pdfrx. Other media keep
/// the package's fallback link, with an icon for their kind.
Widget? mediaBlockBuilder(
  BuildContext context,
  MdxBlock block,
  Widget Function() buildDefault,
) {
  final media = MarkdownXMedia.of(block);
  if (media == null) return null;
  final uri = Uri.tryParse(media.src);
  if (uri != null && _isPdf(media, uri)) {
    return _PdfBlock(uri: uri, title: media.title);
  }
  if (uri != null && media.kind == MarkdownXMediaKind.video) {
    return _VideoBlock(uri: uri, title: media.title);
  }
  return Row(
    children: [
      Icon(_iconFor(media.kind), size: 20),
      const SizedBox(width: 8),
      Expanded(child: buildDefault()),
    ],
  );
}

bool _isPdf(MarkdownXMedia media, Uri uri) =>
    media.type == _pdfType || uri.path.toLowerCase().endsWith(_pdfExtension);

IconData _iconFor(MarkdownXMediaKind kind) => switch (kind) {
  MarkdownXMediaKind.video => Icons.movie_outlined,
  MarkdownXMediaKind.audio => Icons.audiotrack_outlined,
  MarkdownXMediaKind.iframe => Icons.web_asset_outlined,
  MarkdownXMediaKind.embed ||
  MarkdownXMediaKind.object => Icons.attach_file_outlined,
};

/// The first page of a PDF, shown in the document. Tapping it opens the whole PDF in a
/// full-screen viewer, so the viewer's scrolling never competes with the document's.
/// `asset:` sources are read from the app bundle.
class _PdfBlock extends StatelessWidget {
  const _PdfBlock({required this.uri, this.title});

  final Uri uri;
  final String? title;

  bool get _isAsset => uri.scheme == _assetScheme;

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(title ?? uri.pathSegments.last)),
          body: _isAsset ? PdfViewer.asset(uri.path) : PdfViewer.uri(uri),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget firstPage(BuildContext context, PdfDocument? document) =>
        PdfPageView(document: document, pageNumber: 1);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(
        height: _pdfPreviewHeight,
        child: AspectRatio(
          aspectRatio: _pdfPreviewAspectRatio,
          child: Material(
            elevation: 1,
            child: InkWell(
              onTap: () => _open(context),
              child: _isAsset
                  ? PdfDocumentViewBuilder.asset(uri.path, builder: firstPage)
                  : PdfDocumentViewBuilder.uri(uri, builder: firstPage),
            ),
          ),
        ),
      ),
    );
  }
}

/// A video that starts loading when its play button is tapped, so scrolling past it
/// downloads nothing.
class _VideoBlock extends StatefulWidget {
  const _VideoBlock({required this.uri, this.title});

  final Uri uri;
  final String? title;

  @override
  State<_VideoBlock> createState() => _VideoBlockState();
}

class _VideoBlockState extends State<_VideoBlock> {
  VideoPlayerController? _controller;
  Object? _error;

  Future<void> _start() async {
    final controller = VideoPlayerController.networkUrl(widget.uri);
    setState(() => _controller = controller);
    try {
      await controller.initialize();
      await controller.play();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _videoMaxWidth),
      child: _player(context),
    ),
  );

  Widget _player(BuildContext context) {
    final controller = _controller;
    final colors = Theme.of(context).colorScheme;
    if (_error != null) {
      return Text(
        'The video could not be played: $_error',
        style: TextStyle(color: colors.error),
      );
    }
    if (controller == null) {
      return AspectRatio(
        aspectRatio: _defaultVideoAspectRatio,
        child: Material(
          color: colors.surfaceContainerHighest,
          child: InkWell(
            onTap: _start,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_circle_outline, size: 56),
                  if (widget.title case final title?) Text(title),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (!value.isInitialized) {
          return const AspectRatio(
            aspectRatio: _defaultVideoAspectRatio,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return AspectRatio(
          aspectRatio: value.aspectRatio,
          child: GestureDetector(
            onTap: value.isPlaying ? controller.pause : controller.play,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                VideoPlayer(controller),
                if (!value.isPlaying)
                  const Center(child: Icon(Icons.play_arrow, size: 56)),
                VideoProgressIndicator(controller, allowScrubbing: true),
              ],
            ),
          ),
        );
      },
    );
  }
}
