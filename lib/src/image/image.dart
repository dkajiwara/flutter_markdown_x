import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import 'image_file_stub.dart' if (dart.library.io) 'image_file_io.dart';
import '../ir/nodes.dart';
import '../style/style.dart';

/// Creates the [ImageProvider] for an image. Returning null falls through to the
/// default resolver ([markdownXDefaultImageProvider]).
///
/// [uri] is the src after resolution against [MarkdownWidget.imageDirectory]. A relative path
/// with no imageDirectory is passed as-is, as a relative URI without a scheme.
typedef MarkdownXImageResolver = ImageProvider? Function(
  Uri uri,
  MdxImage image,
);

/// Builds the Widget shown while an image is loading.
typedef MarkdownXImageLoadingBuilder = Widget Function(
  BuildContext context,
  MdxImage image,
);

/// Builds the Widget shown when an image could not be displayed. [error] is the
/// loading exception, or the reason it could not be resolved.
typedef MarkdownXImageErrorBuilder = Widget Function(
  BuildContext context,
  MdxImage image,
  Object error,
);

/// Called when an image is tapped. [resolved] is the resolved URI
/// (null when src is empty or cannot be parsed).
typedef MarkdownXImageTapCallback = void Function(
  MdxImage image,
  Uri? resolved,
);

/// The parts of an image `src` that flutter_markdown reads: the path before the first `#`
/// (the fragment is never part of the request) and the size of a `#WxH` suffix.
///
/// `![a](x.png#100x50)` is 100 by 50. A suffix needs exactly one `#` and exactly one `x`:
/// `x.png#a#b` and `x.png#1x2x3` carry no size, and each side parses on its own
/// (`#100x` is 100 wide). A side is `null` when absent or not a number.
({String path, double? width, double? height}) markdownXParseImageSource(
  String src,
) {
  final parts = src.split('#');
  double? width;
  double? height;
  if (parts.length == 2) {
    final dimensions = parts.last.split('x');
    if (dimensions.length == 2) {
      width = double.tryParse(dimensions[0]);
      height = double.tryParse(dimensions[1]);
    }
  }
  return (path: parts.first, width: width, height: height);
}

/// Resolves the image path [src] against [imageDirectory].
///
/// A URI that has a scheme is returned as-is. A relative path is joined to [imageDirectory] as
/// flutter_markdown does on each platform: appended as a plain string off the web (so `/img` and
/// `a.png` give `/imga.png`) and with `p.join` on the web (`/img/a.png`). Returns null
/// when src is empty or cannot be parsed. A relative path with no [imageDirectory] is returned
/// as a relative URI.
Uri? markdownXResolveImageUri(String src, String? imageDirectory) {
  final trimmed = src.trim();
  if (trimmed.isEmpty) return null;
  final Uri? uri;
  try {
    uri = Uri.tryParse(trimmed);
  } on Object {
    return null;
  }
  if (uri == null) return null;
  if (uri.hasScheme || imageDirectory == null) return uri;
  try {
    return Uri.tryParse(joinImageDirectory(imageDirectory, trimmed));
  } on Object {
    return null;
  }
}

/// Whether [src] climbs out of [directory] when a network URL is built from them, so that the
/// request would leave the directory's URL prefix.
///
/// [resolved] is the URI from [markdownXResolveImageUri]. The check applies only when the image
/// is requested over the network (an `http(s)` [resolved], or any relative src on the web).
/// It looks at [src] alone: the path is percent-decoded (repeatedly, up to three times, because a
/// server may decode again), `\` counts as a separator (browsers treat it as `/`), and a `..`
/// segment that rises above the starting point escapes. On the web a root-relative src (`/a.png`)
/// escapes too, since `p.join` discards the directory. Local files are checked by
/// [markdownXLocalImageProvider] instead.
bool markdownXImageEscapesDirectory(
  String directory,
  String src, {
  required Uri resolved,
}) {
  final network =
      kIsWeb ||
      resolved.scheme.toLowerCase() == 'http' ||
      resolved.scheme.toLowerCase() == 'https';
  if (!network) return false;
  var path = src.trim();
  final cut = path.indexOf(RegExp('[?#]'));
  if (cut >= 0) path = path.substring(0, cut);
  for (var i = 0; i < 3; i++) {
    try {
      final decoded = Uri.decodeComponent(path);
      if (decoded == path) break;
      path = decoded;
    } on ArgumentError {
      break;
    }
  }
  if (kIsWeb && (path.startsWith('/') || path.startsWith(r'\\'))) return true;
  var depth = 0;
  for (final segment in path.split(RegExp(r'[/\\]'))) {
    if (segment == '..') {
      if (--depth < 0) return true;
    } else if (segment.isNotEmpty && segment != '.') {
      depth++;
    }
  }
  return false;
}

/// The provider for an image whose src has no scheme, after the default resolver found nothing.
///
/// Off the web it is a [FileImage], and only for a file strictly inside [imageDirectory]
/// ([resolveContainedImagePath] in `image_file_io.dart`): a non-null `imageDirectory` is the
/// opt-in to read files below it (an `imageDirectory` with the `file:` scheme is read as a file
/// URI), and a src that leaves it (`..`, an absolute path, a symbolic link to the outside) is not
/// loaded. Without one the image is not loaded, so untrusted Markdown cannot read files relative
/// to the working directory. On the web it is a [NetworkImage] of the path resolved against the
/// page (`Uri.base`), which is same-origin HTTP. [src] is the path as written in the Markdown.
ImageProvider? markdownXLocalImageProvider(
  Uri uri, {
  required String? imageDirectory,
  required String src,
}) {
  try {
    return relativeImageProvider(uri, imageDirectory: imageDirectory, src: src);
  } on Object {
    return null;
  }
}

/// The default resolver. A URI it cannot use returns null instead of throwing.
///
/// | scheme | Result |
/// |---|---|
/// | `http`, `https` | [NetworkImage] |
/// | `data` | [MemoryImage] for an `image/*` media type (base64 and percent encoding); null otherwise (the view renders `text/*` as text) |
/// | `asset`, `resource` | [AssetImage] (`asset:///images/a.png` and `resource:images/a.png` become `images/a.png`) |
/// | `file` | null (local files are not read by default; see [markdownXFileImageProvider]) |
/// | other, or no scheme | null |
ImageProvider? markdownXDefaultImageProvider(Uri uri) {
  try {
    switch (uri.scheme.toLowerCase()) {
      case 'http':
      case 'https':
        if (uri.host.isEmpty) return null;
        return NetworkImage(uri.toString());
      case 'data':
        final data = uri.data;
        if (data == null || !data.mimeType.startsWith('image/')) return null;
        return MemoryImage(data.contentAsBytes());
      case 'asset':
      case 'resource':
        final name = uri.path.replaceFirst(RegExp('^/+'), '');
        return name.isEmpty ? null : AssetImage(name);
    }
  } on Object {
    return null;
  }
  return null;
}

/// The text of a `data:text/*` image, which flutter_markdown shows as a [Text]. Null for any
/// other URI.
String? markdownXDataImageText(Uri uri) {
  if (uri.scheme.toLowerCase() != 'data') return null;
  try {
    final data = uri.data;
    if (data == null || !data.mimeType.startsWith('text/')) return null;
    return data.contentAsString();
  } on Object {
    return null;
  }
}

/// Turns a `file:` [uri] into a [FileImage]. Null on the web.
///
/// To avoid showing files on the device from untrusted Markdown, the default
/// resolver does not handle `file:`. Apps that display local files call this
/// function from `imageResolver`.
ImageProvider? markdownXFileImageProvider(Uri uri) {
  if (uri.scheme.toLowerCase() != 'file') return null;
  try {
    return fileImageProvider(uri);
  } on Object {
    return null;
  }
}

/// Normalizes the specified image dimensions ([width] and [height]) to finite positive values.
///
/// NaN, infinity, and values at or below 0 are discarded and become null. A value
/// above [MarkdownXDefaults.maxImageExtent] is clamped: when both are given, both
/// are scaled down preserving the aspect ratio; when only one is given, it is capped at that value.
/// When the aspect ratio is so extreme that it cannot be represented, only width is kept.
({double? width, double? height}) markdownXNormalizeImageSize(
  double? width,
  double? height,
) {
  double? valid(double? v) => v != null && v.isFinite && v > 0 ? v : null;
  const max = MarkdownXDefaults.maxImageExtent;
  var w = valid(width);
  var h = valid(height);
  if (w != null && h != null) {
    final scale = [max / w, max / h, 1.0].reduce((a, b) => a < b ? a : b);
    w = valid(w * scale);
    h = valid(h * scale);
    if (w != null && h != null) {
      final ratio = w / h;
      if (!ratio.isFinite || ratio <= 0 || !(h / w).isFinite) h = null;
    }
  } else {
    if (w != null && w > max) w = max;
    if (h != null && h > max) h = max;
  }
  return (width: w, height: h);
}
