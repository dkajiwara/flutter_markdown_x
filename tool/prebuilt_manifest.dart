// Records and checks the correspondence between the binaries in prebuilt/ and the Rust sources that built them.
//
//   dart run tool/prebuilt_manifest.dart --write   # update the manifest after a build
//   dart run tool/prebuilt_manifest.dart --check   # detect inconsistencies in CI
//
// Bit-for-bit reproducibility of the binaries is not guaranteed (it can vary by toolchain and host).
// Only the following two things are guaranteed.
// - The manifest's source hash matches the current Rust sources, Cargo.lock, toolchain spec,
//   and build scripts (the sources were not changed without updating the binaries).
// - Each binary's SHA-256 matches the manifest (no binary was swapped on its own).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const _manifestPath = 'prebuilt/manifest.json';
const _prebuiltDirectory = 'prebuilt';
const _nativeSourceDirectory = 'native/src';

/// Inputs other than the sources that affect the binary's contents.
const _extraInputs = [
  'native/Cargo.toml',
  'native/Cargo.lock',
  'rust-toolchain.toml',
  'tool/build_native.sh',
  'tool/build_wasm.sh',
];

const _binaryExtensions = {'.so', '.dylib', '.wasm', '.dll'};

void main(List<String> args) {
  final write = args.contains('--write');
  final check = args.contains('--check');
  if (write == check) {
    stderr.writeln(
      'usage: dart run tool/prebuilt_manifest.dart --write|--check',
    );
    exit(64);
  }
  final current = _currentManifest();
  final file = File(_manifestPath);
  if (write) {
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(current)}\n',
    );
    stdout.writeln('wrote $_manifestPath');
    return;
  }
  if (!file.existsSync()) {
    stderr.writeln('$_manifestPath is missing. Create it with --write.');
    exit(1);
  }
  final recorded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final problems = _compare(recorded, current);
  if (problems.isEmpty) {
    stdout.writeln('prebuilt binaries match $_manifestPath');
    return;
  }
  for (final problem in problems) {
    stderr.writeln('- $problem');
  }
  stderr.writeln(
    'After changing the Rust sources, run sh tool/build_native.sh and sh tool/build_wasm.sh, then '
    'run dart run tool/prebuilt_manifest.dart --write.',
  );
  exit(1);
}

Map<String, Object?> _currentManifest() => {
  'sourceSha256': _sourceHash(),
  'binaries': {
    for (final file in _binaries())
      _relative(file.path): sha256.convert(file.readAsBytesSync()).toString(),
  },
};

List<String> _compare(Map<String, Object?> recorded, Map<String, Object?> now) {
  final problems = <String>[];
  if (recorded['sourceSha256'] != now['sourceSha256']) {
    problems.add(
      'The Rust sources changed after the manifest was created (the binaries may be stale)',
    );
  }
  final before = (recorded['binaries'] as Map?)?.cast<String, Object?>() ?? {};
  final after = (now['binaries'] as Map).cast<String, Object?>();
  for (final path in {...before.keys, ...after.keys}.toList()..sort()) {
    if (!after.containsKey(path)) {
      problems.add('$path was not found');
    } else if (!before.containsKey(path)) {
      problems.add('$path is not in the manifest');
    } else if (before[path] != after[path]) {
      problems.add('The SHA-256 of $path differs from the manifest');
    }
  }
  return problems;
}

/// SHA-256 of the input files sorted by path, concatenated with path and content separated.
String _sourceHash() {
  final files = [
    ...Directory(_nativeSourceDirectory)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.rs')),
    for (final path in _extraInputs)
      if (File(path).existsSync()) File(path),
  ]..sort((a, b) => _relative(a.path).compareTo(_relative(b.path)));
  final bytes = BytesBuilder(copy: false);
  for (final file in files) {
    bytes
      ..add(utf8.encode(_relative(file.path)))
      ..addByte(0)
      // Keep the hash stable regardless of line-ending differences (checkout settings).
      ..add(utf8.encode(file.readAsStringSync().replaceAll('\r\n', '\n')))
      ..addByte(0);
  }
  return sha256.convert(bytes.takeBytes()).toString();
}

List<File> _binaries() =>
    Directory(_prebuiltDirectory)
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) => _binaryExtensions.any((ext) => file.path.endsWith(ext)),
        )
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

String _relative(String path) =>
    path.replaceAll(r'\', '/').replaceFirst(RegExp(r'^\./'), '');
