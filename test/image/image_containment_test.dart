// dart:io files and symlinks: the containment of local images below imageDirectory.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_markdown_x/src/image/image.dart';
import 'package:flutter_markdown_x/src/image/image_file_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  late Directory temp;
  late Directory allowed;
  late File outside;
  late String dir; // allowed directory with a trailing separator

  setUp(() {
    temp = Directory.systemTemp.createTempSync('mdx_contain_');
    allowed = Directory(p.join(temp.path, 'allowed'))..createSync();
    Directory(p.join(allowed.path, 'sub')).createSync();
    File(p.join(allowed.path, 'inside.png')).writeAsBytesSync([1]);
    File(p.join(allowed.path, 'sub', 'deep.png')).writeAsBytesSync([1]);
    outside = File(p.join(temp.path, 'outside.png'))..writeAsBytesSync([1]);
    dir = '${allowed.path}/';
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<void> expectRendersFallback(WidgetTester tester, String src) async {
    await tester.pumpWidget(
      _app(MarkdownBody(data: '![the alt]($src)', imageDirectory: dir)),
    );
    expect(tester.takeException(), isNull, reason: src);
    expect(find.byType(Image), findsNothing, reason: src);
    expect(find.text('the alt'), findsOneWidget, reason: src);
  }

  group('widgets: a src that leaves imageDirectory shows the alt text', () {
    testWidgets('../outside.png', (tester) async {
      await expectRendersFallback(tester, '../outside.png');
    });

    testWidgets('allowed/../../outside.png', (tester) async {
      await expectRendersFallback(tester, 'sub/../../outside.png');
    });

    testWidgets('percent-encoded dots', (tester) async {
      await expectRendersFallback(tester, '%2e%2e/outside.png');
    });

    testWidgets('an absolute path to the outside file', (tester) async {
      await expectRendersFallback(tester, outside.path);
    });

    testWidgets('a file: URI to the outside file', (tester) async {
      await expectRendersFallback(tester, outside.uri.toString());
    });

    testWidgets('a symlink inside the directory pointing outside', (
      tester,
    ) async {
      Link(p.join(allowed.path, 'link.png')).createSync(outside.path);
      await expectRendersFallback(tester, 'link.png');
    });

    testWidgets('a symlinked directory pointing outside', (tester) async {
      Link(p.join(allowed.path, 'dirlink')).createSync(temp.path);
      await expectRendersFallback(tester, 'dirlink/outside.png');
    });
  });

  group('widgets: files inside imageDirectory still load', () {
    testWidgets('plain, nested and dot-segment paths', (tester) async {
      for (final src in ['inside.png', 'sub/deep.png', 'sub/../inside.png']) {
        await tester.pumpWidget(
          _app(MarkdownBody(data: '![a]($src)', imageDirectory: dir)),
        );
        expect(find.byType(Image), findsOneWidget, reason: src);
        expect(
          ((tester.widget<Image>(find.byType(Image))).image as FileImage)
              .file
              .path,
          p.join(allowed.path, p.normalize(src)),
          reason: src,
        );
      }
    });

    testWidgets('a percent-encoded file name is decoded', (tester) async {
      File(p.join(allowed.path, 'a b.png')).writeAsBytesSync([1]);
      await tester.pumpWidget(
        _app(MarkdownBody(data: '![a](a%20b.png)', imageDirectory: dir)),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as FileImage).file.path,
        p.join(allowed.path, 'a b.png'),
      );
    });

    testWidgets('a file: imageDirectory is read as a file URI', (tester) async {
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '![a](inside.png)',
            imageDirectory: allowed.uri.toString(),
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as FileImage).file.path,
        p.join(allowed.path, 'inside.png'),
      );
    });

    testWidgets('a directory without a trailing separator is not a prefix', (
      tester,
    ) async {
      // flutter_markdown concatenates: `<dir>` + `inside.png` names a sibling of the directory,
      // which is outside it.
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '![the alt](inside.png)',
            imageDirectory: allowed.path,
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.text('the alt'), findsOneWidget);
    });
  });

  group('resolveContainedImagePath (posix)', () {
    final posix = p.Context(style: p.Style.posix, current: '/cwd');

    String? resolve(String base, String src) => resolveContainedImagePath(
      base,
      src,
      context: posix,
      resolveSymlinks: false,
    );

    test('allows strictly nested paths', () {
      expect(resolve('/app/docs/', 'a.png'), '/app/docs/a.png');
      expect(resolve('/app/docs/', 'x/../a.png'), '/app/docs/a.png');
      expect(resolve('/app/docs/', 'x/y/a.png?v=1'), '/app/docs/x/y/a.png');
    });

    test('rejects traversal, the directory itself, and siblings', () {
      expect(resolve('/app/docs/', '../private/photo.png'), isNull);
      expect(resolve('/app/docs/', 'x/../../private/photo.png'), isNull);
      expect(resolve('/app/docs/', '%2e%2e/private/photo.png'), isNull);
      expect(resolve('/app/docs/', '%2E%2E%2Fprivate'), isNull);
      expect(resolve('/app/docs/', '.'), isNull);
      expect(resolve('/app/docs/', ''), isNull);
      expect(resolve('/app/docs', 'a.png'), isNull);
      expect(resolve('/app/docs/', '../docs2/a.png'), isNull);
    });

    test('rejects absolute paths, NUL, and a non-file base scheme', () {
      expect(resolve('/app/docs/', '/etc/x.png'), isNull);
      expect(resolve('/app/docs/', r'C:\x.png'), isNull);
      expect(resolve('/app/docs/', 'a%00.png'), isNull);
      expect(resolve('ftp://h/d/', 'a.png'), isNull);
    });

    test('keeps a double-encoded dot as a literal file name', () {
      expect(
        resolve('/app/docs/', '%252e%252e/a.png'),
        '/app/docs/%2e%2e/a.png',
      );
    });

    test('a file: directory is converted to a path', () {
      expect(resolve('file:///app/docs/', 'a.png'), '/app/docs/a.png');
      expect(resolve('file:///app/docs/', '../a.png'), isNull);
    });

    test('a relative directory is relative to the context directory', () {
      expect(resolve('assets/', 'a.png'), '/cwd/assets/a.png');
      expect(resolve('assets/', '../a.png'), isNull);
    });

    test('a backslash is an ordinary character on posix', () {
      expect(
        resolve('/app/docs/', r'..\outside.png'),
        r'/app/docs/..\outside.png',
      );
    });
  });

  group('resolveContainedImagePath (windows path context)', () {
    final windows = p.Context(style: p.Style.windows, current: r'C:\cwd');

    String? resolve(String base, String src) => resolveContainedImagePath(
      base,
      src,
      context: windows,
      resolveSymlinks: false,
    );

    test('allows nested paths with either separator', () {
      expect(resolve(r'C:\app\docs\', 'img/a.png'), r'C:\app\docs\img\a.png');
      expect(resolve(r'C:\app\docs\', r'img\a.png'), r'C:\app\docs\img\a.png');
      expect(resolve('file:///C:/app/docs/', 'a.png'), r'C:\app\docs\a.png');
    });

    test('rejects backslash and encoded traversal', () {
      expect(resolve(r'C:\app\docs\', r'..\outside.png'), isNull);
      expect(resolve(r'C:\app\docs\', r'sub\..\..\outside.png'), isNull);
      expect(resolve(r'C:\app\docs\', '..%5coutside.png'), isNull);
      expect(resolve(r'C:\app\docs\', '%2e%2e/outside.png'), isNull);
    });

    test('rejects drive letters, root and UNC paths', () {
      expect(resolve(r'C:\app\docs\', r'D:\x.png'), isNull);
      expect(resolve(r'C:\app\docs\', 'D:x.png'), isNull);
      expect(resolve(r'C:\app\docs\', r'\x.png'), isNull);
      expect(resolve(r'C:\app\docs\', r'\\server\share\x.png'), isNull);
      expect(resolve(r'C:\app\docs\', '/x.png'), isNull);
    });

    test('compares case-insensitively', () {
      expect(resolve(r'C:\App\Docs\', 'a.png'), r'C:\App\Docs\a.png');
      expect(resolve(r'C:\app\docs\', r'..\DOCS\a.png'), r'C:\app\DOCS\a.png');
    });
  });

  group('resolveContainedImagePath (symlinks, real files)', () {
    test('rejects a link to the outside and allows a link inside', () {
      Link(p.join(allowed.path, 'out.png')).createSync(outside.path);
      Link(p.join(allowed.path, 'in.png'))
          .createSync(p.join(allowed.path, 'inside.png'));
      expect(resolveContainedImagePath(dir, 'out.png'), isNull);
      expect(
        resolveContainedImagePath(dir, 'in.png'),
        p.join(allowed.path, 'in.png'),
      );
    });

    test('rejects a dangling link', () {
      Link(p.join(allowed.path, 'dangling.png'))
          .createSync(p.join(temp.path, 'gone'));
      expect(resolveContainedImagePath(dir, 'dangling.png'), isNull);
    });

    test('allows an imageDirectory that is itself a symlink', () {
      final alias = p.join(temp.path, 'alias');
      Link(alias).createSync(allowed.path);
      expect(
        resolveContainedImagePath('$alias/', 'inside.png'),
        p.join(alias, 'inside.png'),
      );
      expect(resolveContainedImagePath('$alias/', '../outside.png'), isNull);
    });
  });

  group('network directories', () {
    test('a src that climbs above the directory escapes it', () {
      const base = 'https://a.example/docs/';
      final resolved = Uri.parse('${base}x');
      bool escapes(String src) =>
          markdownXImageEscapesDirectory(base, src, resolved: resolved);
      expect(escapes('../x.png'), isTrue);
      expect(escapes('a/../../x.png'), isTrue);
      expect(escapes('%2e%2e/x.png'), isTrue);
      expect(escapes('%252e%252e/x.png'), isTrue);
      expect(escapes(r'..\x.png'), isTrue);
      expect(escapes('a/../x.png'), isFalse);
      expect(escapes('a/b.png'), isFalse);
      expect(escapes('100%.png'), isFalse);
    });

    testWidgets('the default view does not request an escaping URL', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const MarkdownBody(
            data: '![the alt](../x.png)',
            imageDirectory: 'https://a.example/docs/',
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.text('the alt'), findsOneWidget);
    });

    testWidgets('a custom imageResolver still sees the unmodified URI', (
      tester,
    ) async {
      final seen = <Uri>[];
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '![the alt](../x.png)',
            imageDirectory: 'https://a.example/docs/',
            imageResolver: (uri, image) {
              seen.add(uri);
              return null;
            },
          ),
        ),
      );
      expect(seen, [Uri.parse('https://a.example/docs/../x.png')]);
    });
  });
}
