import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

/// Turns a `file:` URI into a [FileImage].
ImageProvider? fileImageProvider(Uri uri) => FileImage(File.fromUri(uri));

/// Appends [src] to [directory] as a plain string, with no separator (flutter_markdown on
/// dart:io: `imageDirectory + uri.toString()`).
String joinImageDirectory(String directory, String src) => directory + src;

/// A relative image that is not an absolute `file:` URI. On dart:io it is a file, and only
/// when it lies strictly below [imageDirectory] ([resolveContainedImagePath]); without an
/// image directory the path would be relative to the process working directory, which is not
/// read. [src] is the path as written in the Markdown (without the `#` fragment).
ImageProvider? relativeImageProvider(
  Uri uri, {
  required String? imageDirectory,
  required String src,
}) {
  if (imageDirectory == null) return null;
  final path = resolveContainedImagePath(imageDirectory, src);
  return path == null ? null : FileImage(File(path));
}

/// The file that [src] names below [directory], or null when it is not a file strictly inside
/// that directory.
///
/// [src] is appended to [directory] as a plain string (flutter_markdown's rule, so a directory
/// without a trailing separator names a sibling and is rejected), after the `?` query is cut and
/// the percent-encoding is decoded once. The base and the result are then normalized
/// (`.` and `..` segments, repeated separators) and compared as paths: the result has to be
/// within the base. In addition:
///
/// - an absolute [src] (a root, a drive letter, a UNC path) and a NUL character are rejected;
/// - a `file:` [directory] is converted to a path; any other URI scheme is rejected;
/// - an existing path is resolved through symbolic links (nearest existing ancestor for a
///   missing file) on both sides, so a link inside the directory that points outside is
///   rejected, and so is a link that cannot be resolved.
///
/// [context] is the path style (the platform's by default; tests pass a Windows context).
/// Symbolic links are resolved on disk only when [resolveSymlinks] is true.
///
/// The returned path is the normalized lexical one. A file can still be replaced by a link between
/// this check and the read.
String? resolveContainedImagePath(
  String directory,
  String src, {
  p.Context? context,
  bool resolveSymlinks = true,
}) {
  final ctx = context ?? p.context;
  final windows = ctx.style == p.Style.windows;
  try {
    var relative = src.trim();
    final query = relative.indexOf('?');
    if (query >= 0) relative = relative.substring(0, query);
    try {
      relative = Uri.decodeFull(relative);
    } on ArgumentError {
      // Not valid percent-encoding: it is a literal file name.
    }
    if (relative.isEmpty ||
        relative.contains('\u0000') ||
        directory.contains('\u0000') ||
        _isAbsolute(ctx, relative)) {
      return null;
    }
    var base = directory;
    if (base.toLowerCase().startsWith('file:')) {
      base = Uri.parse(base).toFilePath(windows: windows);
    } else if (_hasUriScheme(base)) {
      return null;
    }
    final root = ctx.normalize(ctx.absolute(base));
    final candidate = ctx.normalize(ctx.absolute(base + relative));
    if (!ctx.isWithin(root, candidate)) return null;
    if (resolveSymlinks) {
      final realRoot = _canonical(ctx, root);
      final realCandidate = _canonical(ctx, candidate);
      if (realRoot == null ||
          realCandidate == null ||
          !ctx.isWithin(realRoot, realCandidate)) {
        return null;
      }
    }
    return candidate;
  } on Object {
    return null;
  }
}

bool _isAbsolute(p.Context ctx, String path) =>
    ctx.isAbsolute(path) ||
    ctx.rootPrefix(path).isNotEmpty ||
    path.startsWith('/') ||
    path.startsWith(r'\') ||
    RegExp(r'^[a-zA-Z]:').hasMatch(path);

/// A scheme longer than one character ("C:" is a drive letter).
bool _hasUriScheme(String path) =>
    RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]+:').hasMatch(path);

/// [path] with symbolic links resolved. For a path that does not exist, the nearest existing
/// ancestor is resolved and the missing names are appended. Null when an existing entry cannot
/// be resolved (a dangling link).
String? _canonical(p.Context ctx, String path) {
  var existing = path;
  final missing = <String>[];
  while (FileSystemEntity.typeSync(existing, followLinks: false) ==
      FileSystemEntityType.notFound) {
    final parent = ctx.dirname(existing);
    if (parent == existing) return path;
    missing.insert(0, ctx.basename(existing));
    existing = parent;
  }
  try {
    final real = File(existing).resolveSymbolicLinksSync();
    return ctx.normalize(ctx.joinAll([real, ...missing]));
  } on FileSystemException {
    return null;
  }
}
