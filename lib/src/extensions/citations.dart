/// Implements AI chat citation markers (`[1]`, `[1, 2]`, `【1†source】`) as an IR transform.
///
/// Each is replaced with `MdxCustomInline('citation', {'id': '1', 'ids': '1'})`.
/// The parser is left untouched, so every backend produces the same result.
/// This file does not depend on Flutter. See doc/alerts-and-citations.md for the
/// specification.
library;

import 'extension.dart';
import '../ir/nodes.dart';

/// The [MdxCustomInline.type] of a citation.
const markdownXCitationType = 'citation';

/// The default pattern: `[1]`, `[1, 2]`, and the ChatGPT-style `【1†source】`.
///
/// Reference links (where `[1]` has a definition) are turned into links by the
/// parser, so they never reach this pattern.
final _defaultPattern = RegExp(
  r'\[(\d{1,4}(?:\s*,\s*\d{1,4})*)\]|【\s*(\d{1,4})\s*†[^】]*】',
);

final _separator = RegExp(r'\s*[,，、;]\s*');

/// Returns the ids (in order of appearance) if [inline] is a citation, or an empty list otherwise.
List<String> markdownXCitationIds(MdxInline inline) {
  if (inline is! MdxCustomInline || inline.type != markdownXCitationType) {
    return const [];
  }
  final ids = inline.attributes['ids'] ?? inline.attributes['id'];
  if (ids == null || ids.isEmpty) return const [];
  return ids.split(',');
}

MdxInline? _build(Match match, bool isDefault) {
  // The default pattern uses whichever of its two groups matched; a custom
  // pattern uses the first group that matched (or the whole match if there is none) as the source of the ids.
  String? raw;
  for (var i = 1; i <= match.groupCount; i++) {
    raw = match.group(i);
    if (raw != null) break;
  }
  raw ??= isDefault ? null : match[0];
  if (raw == null) return null;
  final ids = [
    for (final id in raw.trim().split(_separator))
      if (id.isNotEmpty) id,
  ];
  if (ids.isEmpty) return null;
  return MdxCustomInline(
    markdownXCitationType,
    attributes: {'id': ids.first, 'ids': ids.join(',')},
    children: [MdxText(match[0]!)],
  );
}

final _defaultExtension = MarkdownXExtension(
  inlineSyntaxes: [
    MarkdownXInlineSyntax(
      pattern: _defaultPattern,
      build: (match) => _build(match, true),
    ),
  ],
);

/// An opt-in extension that converts citation markers into citations.
///
/// If [pattern] is omitted, it targets `[1]`, `[1, 2]`, and `【1†source】`.
/// When given, the first group that matched becomes the ids (several are allowed,
/// separated by `,` or `、`); with no group, the whole match becomes the id.
///
/// Omitting [pattern] returns the same instance every time. Cache invalidation
/// is decided by instance identity, so when you pass [pattern], keep the returned
/// value in a field or top-level variable and reuse it.
MarkdownXExtension markdownXCitationExtension({RegExp? pattern}) {
  if (pattern == null) return _defaultExtension;
  return MarkdownXExtension(
    inlineSyntaxes: [
      MarkdownXInlineSyntax(
        pattern: pattern,
        build: (match) => _build(match, false),
      ),
    ],
  );
}
