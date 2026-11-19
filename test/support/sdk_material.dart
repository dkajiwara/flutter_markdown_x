/// The SDK Material and Cupertino libraries, for the flutter_markdown_plus comparison tests only.
///
/// flutter_markdown_plus is built on `package:flutter/material.dart`, which is deprecated in favor
/// of `package:material_ui` / `package:cupertino_ui`. The two are separate copies of the same
/// classes, so a plus widget needs an SDK `Theme` and an SDK `ThemeData`. These imports (and their
/// `deprecated_member_use` ignores) are confined to this file; no other file in the repository
/// imports the SDK Material or Cupertino library. Painting and widgets types (`TextStyle`, `Color`,
/// `EdgeInsets`, `Decoration`, `TableBorder`, ...) are shared between the two copies, so the
/// resulting values compare directly.
library;

// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart' as sdk_cupertino;
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as sdk;
import 'package:material_ui/material_ui.dart';

/// The same theme in both Material copies.
typedef ThemePair = ({ThemeData ours, sdk.ThemeData theirs});

/// A theme with resolved font sizes, as `MaterialApp` provides to its descendants, built with the
/// same settings in `material_ui` (`ours`) and the SDK (`theirs`).
ThemePair themePair({
  Brightness brightness = Brightness.light,
  bool useMaterial3 = true,
}) {
  final ours = brightness == Brightness.dark
      ? ThemeData.dark(useMaterial3: useMaterial3)
      : ThemeData(useMaterial3: useMaterial3);
  final theirs = brightness == Brightness.dark
      ? sdk.ThemeData.dark(useMaterial3: useMaterial3)
      : sdk.ThemeData(useMaterial3: useMaterial3);
  return (
    ours: ThemeData.localize(ours, Typography.englishLike2021),
    theirs: sdk.ThemeData.localize(theirs, sdk.Typography.englishLike2021),
  );
}

/// The Cupertino theme of [brightness] in the SDK.
sdk_cupertino.CupertinoThemeData sdkCupertinoTheme(Brightness brightness) =>
    sdk_cupertino.CupertinoThemeData(brightness: brightness);

/// The `MaterialApp` of the SDK around [child], for flutter_markdown_plus.
Widget sdkMaterialApp(Widget child) => sdk.MaterialApp(
  home: sdk.Scaffold(body: SingleChildScrollView(child: child)),
);
