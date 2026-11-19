import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

/// The web has no local files, so `file:` is not handled.
ImageProvider? fileImageProvider(Uri uri) => null;

/// Joins [src] to [directory] with `p.join` (flutter_markdown on the web).
String joinImageDirectory(String directory, String src) =>
    p.join(directory, src);

/// A relative image on the web: requested from the page's own origin, as flutter_markdown does
/// (`Image.network(p.join(p.current, src))`). There is no local file access.
ImageProvider? relativeImageProvider(
  Uri uri, {
  required String? imageDirectory,
  required String src,
}) {
  if (uri.hasScheme) return null;
  return NetworkImage(p.join(p.current, uri.toString()));
}
