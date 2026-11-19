import 'package:flutter/foundation.dart';
import 'package:markdown/markdown.dart' as md;

import '../flutter_markdown/element_builder.dart';

/// The `runtimeType`s of the syntaxes that the Rust parser already covers.
final Set<Type> _nativeSyntaxes = {
  md.FencedCodeBlockSyntax,
  md.TableSyntax,
  md.UnorderedListWithCheckboxSyntax,
  md.OrderedListWithCheckboxSyntax,
  md.FootnoteDefSyntax,
  md.InlineHtmlSyntax,
  md.StrikethroughSyntax,
  md.AutolinkExtensionSyntax,
  md.HeaderWithIdSyntax,
  md.SetextHeaderWithIdSyntax,
  md.AlertBlockSyntax,
  // Replaced by the emoji extension, which the widget enables for it.
  md.EmojiSyntax,
  // ignore: deprecated_member_use_from_same_package
  TaskListSyntax,
};

/// The built-in extension sets. Their syntaxes are never reported, even those that are not
/// implemented (color swatches of `gitHubWeb`): the sets are documented as accepted.
bool _isBuiltInSet(md.ExtensionSet set) =>
    identical(set, md.ExtensionSet.gitHubFlavored) ||
    identical(set, md.ExtensionSet.gitHubWeb) ||
    identical(set, md.ExtensionSet.commonMark) ||
    identical(set, md.ExtensionSet.none);

final Set<Type> _reported = <Type>{};

/// Forgets which syntaxes were reported. For tests.
@visibleForTesting
void resetReportedSyntaxes() => _reported.clear();

/// Reports, once per `runtimeType` per isolate, every syntax that is neither built in nor handled
/// by the Rust parser (see doc/flutter_markdown_compat.md, section 5b). The document still renders
/// without that syntax.
void reportUnsupportedSyntaxes({
  md.ExtensionSet? extensionSet,
  List<md.BlockSyntax>? blockSyntaxes,
  List<md.InlineSyntax>? inlineSyntaxes,
}) {
  final syntaxes = <Object>[
    if (extensionSet != null && !_isBuiltInSet(extensionSet)) ...[
      ...extensionSet.blockSyntaxes,
      ...extensionSet.inlineSyntaxes,
    ],
    ...?blockSyntaxes,
    ...?inlineSyntaxes,
  ];
  for (final syntax in syntaxes) {
    final type = syntax.runtimeType;
    if (_nativeSyntaxes.contains(type) || !_reported.add(type)) continue;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: UnsupportedError(
          '$type is a package:markdown syntax, which does not run in '
          'flutter_markdown_x: its parser is Rust. The document is rendered '
          'without it. Port it to a MarkdownXExtension (MarkdownXInlineSyntax, '
          'transformBlock, or transformSource); see '
          'doc/flutter_markdown_compat.md.',
        ),
        library: 'flutter_markdown_x',
        context: ErrorDescription(
          'while reading blockSyntaxes, inlineSyntaxes or extensionSet',
        ),
      ),
    );
  }
}

bool _has(
  md.ExtensionSet? set,
  List<md.BlockSyntax>? blocks,
  bool Function(md.BlockSyntax) test,
) => (blocks?.any(test) ?? false) || (set?.blockSyntaxes.any(test) ?? false);

/// Whether the syntaxes turn GitHub alerts on (`AlertBlockSyntax`), even with `alerts: false`.
bool syntaxesEnableAlerts(md.ExtensionSet? set, List<md.BlockSyntax>? blocks) =>
    _has(set, blocks, (s) => s.runtimeType == md.AlertBlockSyntax);

/// Whether the syntaxes generate heading ids (`HeaderWithIdSyntax`, as in `gitHubWeb`).
bool syntaxesGenerateHeaderIds(
  md.ExtensionSet? set,
  List<md.BlockSyntax>? blocks,
) => _has(
  set,
  blocks,
  (s) =>
      s.runtimeType == md.HeaderWithIdSyntax ||
      s.runtimeType == md.SetextHeaderWithIdSyntax,
);

/// Whether the syntaxes turn emoji shortcodes on (`EmojiSyntax`, as in `gitHubWeb`).
bool syntaxesEnableEmoji(
  md.ExtensionSet? set,
  List<md.InlineSyntax>? inlines,
) =>
    (inlines?.any((s) => s.runtimeType == md.EmojiSyntax) ?? false) ||
    (set?.inlineSyntaxes.any((s) => s.runtimeType == md.EmojiSyntax) ?? false);
