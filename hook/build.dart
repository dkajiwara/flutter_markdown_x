// Registers the prebuilt native parser (`prebuilt/`) as a code asset
// bundled with the app.
//
// Rust is never compiled on the consumer side. If there is no binary for the target
// platform, nothing is registered: the widgets then show the raw Markdown and `parseMarkdown`
// throws `MarkdownXParserUnavailableException` (see doc/parser.md).
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// The name of the asset that `@Native` in `lib/src/parser/native/bindings.dart` refers to.
const _assetName = 'src/parser/native/bindings.dart';
const _libraryName = 'mdx_native';
const _prebuiltDirectory = 'prebuilt';

final _architectureNames = <Architecture, String>{
  Architecture.arm64: 'arm64',
  Architecture.x64: 'x64',
  Architecture.arm: 'arm',
};

/// The name of the directory holding the binary for the target platform. Null if unsupported.
String? _targetDirectory(CodeConfig code) {
  final architecture = _architectureNames[code.targetArchitecture];
  if (architecture == null) return null;
  switch (code.targetOS) {
    case OS.macOS:
      return 'macos-$architecture';
    case OS.android:
      return 'android-$architecture';
    case OS.iOS:
      final simulator = code.iOS.targetSdk == IOSSdk.iPhoneSimulator;
      return simulator ? 'ios-$architecture-sim' : 'ios-$architecture';
    case OS.linux:
      return 'linux-$architecture';
    case OS.windows:
      return 'windows-$architecture';
  }
  return null;
}

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    final directory = _targetDirectory(code);
    if (directory == null) return;

    final fileName = code.targetOS.dylibFileName(_libraryName);
    final file = input.packageRoot.resolve(
      '$_prebuiltDirectory/$directory/$fileName',
    );
    // Rerun the hook when a binary is added or updated later.
    output.dependencies.add(file);
    if (!File.fromUri(file).existsSync()) return;

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _assetName,
        linkMode: DynamicLoadingBundled(),
        file: file,
      ),
    );
  });
}
