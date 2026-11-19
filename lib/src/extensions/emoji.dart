/// GitHub emoji shortcodes (`:smile:` becomes the emoji) as an IR transform.
///
/// It follows `package:markdown`'s `EmojiSyntax`, which flutter_markdown enables with
/// `ExtensionSet.gitHubWeb`: the same pattern (`:([a-z0-9_+-]+):`, lower case only),
/// the same `emojis` table, and unknown shortcodes are left as text. The result is
/// plain text, exactly like `EmojiSyntax` (a `md.Text` node), so selection, copy,
/// semantics and builders see the emoji character. This file does not depend on
/// Flutter. See doc/extensions.md.
library;

import 'package:markdown/markdown.dart' as md;

import '../ir/nodes.dart';
import 'extension.dart';

MdxInline? _build(Match match) {
  final emoji = md.emojis[match[1]!];
  return emoji == null ? null : MdxText(emoji);
}

/// An opt-in extension that replaces GitHub emoji shortcodes such as `:smile:` and `:+1:`
/// with the emoji.
///
/// It is enabled automatically when flutter_markdown would enable it: with
/// `extensionSet: md.ExtensionSet.gitHubWeb` or `md.EmojiSyntax()` in `inlineSyntaxes`.
/// Otherwise add it to `extensions`. Code spans, code blocks, link destinations and
/// image alt text are untouched; link text is converted, as in `package:markdown`.
final MarkdownXExtension markdownXEmojiExtension = MarkdownXExtension(
  inlineSyntaxes: [
    MarkdownXInlineSyntax(
      pattern: RegExp(r':([a-z0-9_+-]+):'),
      build: _build,
      applyInsideLinks: true,
      // `:foo:smile:` still converts `:smile:`, as `EmojiSyntax` does after rejecting `:foo:`.
      rescanAfterRejected: true,
    ),
  ],
);
