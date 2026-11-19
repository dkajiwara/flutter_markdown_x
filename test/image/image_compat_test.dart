@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_markdown_x/src/image/image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Provider that never finishes loading.
class _PendingProvider extends ImageProvider<_PendingProvider> {
  @override
  Future<_PendingProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _PendingProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
}

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 400, child: SingleChildScrollView(child: child)),
    ),
  ),
);

void main() {
  group('markdownXParseImageSource (flutter_markdown _buildImage rules)', () {
    test('a #WxH suffix gives the size and is removed from the path', () {
      final s = markdownXParseImageSource('x.png#100x50');
      expect((s.path, s.width, s.height), ('x.png', 100.0, 50.0));
    });

    test('anything but exactly one # and one x gives no size', () {
      for (final src in ['x.png#a#b', 'x.png#1x2x3', 'x.png#10', 'x.png']) {
        final s = markdownXParseImageSource(src);
        expect((s.width, s.height), (null, null), reason: src);
        expect(s.path, 'x.png', reason: src);
      }
    });

    test('each side parses on its own', () {
      final s = markdownXParseImageSource('x.png#100xabc');
      expect((s.width, s.height), (100.0, null));
      final t = markdownXParseImageSource('x.png#x50');
      expect((t.width, t.height), (null, 50.0));
    });

    test('three parts drop the fragments but not the path', () {
      final s = markdownXParseImageSource('x.png#1x2#3x4');
      expect((s.path, s.width, s.height), ('x.png', null, null));
    });
  });

  group('resource: and data:', () {
    test('resource: is an AssetImage of the path, leading slashes removed', () {
      final a = markdownXDefaultImageProvider(
        Uri.parse('resource:images/a.png'),
      );
      expect((a! as AssetImage).assetName, 'images/a.png');
      final b = markdownXDefaultImageProvider(
        Uri.parse('resource:///images/b.png'),
      );
      expect((b! as AssetImage).assetName, 'images/b.png');
      expect(markdownXDefaultImageProvider(Uri.parse('resource:')), isNull);
    });

    test('only image/* data URIs give a MemoryImage', () {
      expect(
        markdownXDefaultImageProvider(Uri.parse('data:image/png;base64,AAAA')),
        isA<MemoryImage>(),
      );
      expect(
        markdownXDefaultImageProvider(Uri.parse('data:text/plain,hi')),
        isNull,
      );
      expect(
        markdownXDefaultImageProvider(
          Uri.parse('data:application/octet-stream;base64,AAAA'),
        ),
        isNull,
      );
    });

    test('markdownXDataImageText reads text/* data URIs only', () {
      expect(
        markdownXDataImageText(Uri.parse('data:text/plain,hello%20world')),
        'hello world',
      );
      expect(
        markdownXDataImageText(Uri.parse('data:text/plain;base64,aGk=')),
        'hi',
      );
      // No media type defaults to text/plain, as in flutter_markdown.
      expect(markdownXDataImageText(Uri.parse('data:,plain')), 'plain');
      expect(markdownXDataImageText(Uri.parse('data:image/png,x')), isNull);
      expect(markdownXDataImageText(Uri.parse('https://a/x.png')), isNull);
    });

    testWidgets('a data:text/* image renders its text, not an image', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const MarkdownBody(data: '![alt](data:text/plain,hello%20there)')),
      );
      expect(find.text('hello there'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a data: image of another media type shows the alt', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const MarkdownBody(
            data: '![the alt](data:application/octet-stream;base64,AAAA)',
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.text('the alt'), findsOneWidget);
    });

    testWidgets('resource: loads through the asset bundle path', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const MarkdownBody(data: '![a](resource:images/a.png)')),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<AssetImage>());
      expect((image.image as AssetImage).assetName, 'images/a.png');
    });
  });

  group('#WxH in the default renderer', () {
    testWidgets('sizes the image and is not part of the request', (
      tester,
    ) async {
      final seen = <Uri>[];
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '![a](https://a.example/x.png#100x50)',
            imageResolver: (uri, image) {
              seen.add(uri);
              return _PendingProvider();
            },
          ),
        ),
      );
      expect(seen, [Uri.parse('https://a.example/x.png')]);
      expect(tester.getSize(find.byType(MdxImageView)), const Size(100, 50));
    });

    testWidgets('a malformed suffix gives no size but drops the fragment', (
      tester,
    ) async {
      final seen = <Uri>[];
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '![a](https://a.example/x.png#a#b)',
            imageResolver: (uri, image) {
              seen.add(uri);
              return _PendingProvider();
            },
          ),
        ),
      );
      expect(seen, [Uri.parse('https://a.example/x.png')]);
      expect(tester.getSize(find.byType(MdxImageView)).width, 0);
    });
  });

  group('imageDirectory on dart:io', () {
    test('is appended as a plain string, no separator', () {
      expect(markdownXResolveImageUri('a.png', '/img'), Uri.parse('/imga.png'));
      expect(
        markdownXResolveImageUri('a.png', '/img/'),
        Uri.parse('/img/a.png'),
      );
    });

    testWidgets('a relative src under imageDirectory reads that file', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const MarkdownBody(data: '![a](a.png)', imageDirectory: '/tmp/imgs/'),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<FileImage>());
      expect((image.image as FileImage).file.path, '/tmp/imgs/a.png');
    });

    testWidgets('concatenation without a separator leaves the directory', (
      tester,
    ) async {
      // flutter_markdown reads `/tmp/imgsa.png`; that is a sibling of `/tmp/imgs`, outside it, so
      // it is not loaded here (test/image/image_containment_test.dart).
      await tester.pumpWidget(
        _app(
          const MarkdownBody(
            data: '![alt text](a.png)',
            imageDirectory: '/tmp/imgs',
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.text('alt text'), findsOneWidget);
    });

    testWidgets('a relative src without imageDirectory is not loaded', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const MarkdownBody(data: '![alt text](a.png)')),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.text('alt text'), findsOneWidget);
    });

    testWidgets('an absolute file: src is not covered by imageDirectory', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const MarkdownBody(
            data: '![alt text](file:///tmp/a.png)',
            imageDirectory: '/tmp/imgs/',
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.text('alt text'), findsOneWidget);
    });

    testWidgets('imageDirectory that is http(s) gives a network image', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const MarkdownBody(
            data: '![a](x.png#10x10)',
            imageDirectory: 'https://a.example/d/',
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as NetworkImage).url, 'https://a.example/d/x.png');
    });
  });

  group('images inside links', () {
    const doc = '[![the alt](https://a.example/x.png)](https://l.example "T")';

    testWidgets('tapping the default image calls onTapLink', (tester) async {
      final links = <(String, String?, String)>[];
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: doc,
            handleAnchorLinks: false,
            imageResolver: (uri, image) => _PendingProvider(),
            imageLoadingBuilder: (c, i) =>
                const SizedBox(width: 40, height: 40),
            onTapLink: (text, href, title) => links.add((text, href, title)),
          ),
        ),
      );
      await tester.tap(find.byType(MdxImageView));
      expect(links, [('the alt', 'https://l.example', 'T')]);
    });

    testWidgets('onTapImage runs first, then onTapLink', (tester) async {
      final order = <String>[];
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: doc,
            imageResolver: (uri, image) => _PendingProvider(),
            imageLoadingBuilder: (c, i) =>
                const SizedBox(width: 40, height: 40),
            onTapImage: (image, uri) => order.add('image ${uri?.host}'),
            onTapLink: (text, href, title) => order.add('link $href'),
          ),
        ),
      );
      await tester.tap(find.byType(MdxImageView));
      expect(order, ['image a.example', 'link https://l.example']);
    });

    testWidgets('an image outside a link does not call onTapLink', (
      tester,
    ) async {
      var links = 0;
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '![a](https://a.example/x.png)',
            imageResolver: (uri, image) => _PendingProvider(),
            imageLoadingBuilder: (c, i) =>
                const SizedBox(width: 40, height: 40),
            onTapImage: (image, uri) {},
            onTapLink: (text, href, title) => links++,
          ),
        ),
      );
      await tester.tap(find.byType(MdxImageView));
      expect(links, 0);
    });

    testWidgets('a sizedImageBuilder widget is wrapped in the link tap', (
      tester,
    ) async {
      final links = <String?>[];
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: doc,
            handleAnchorLinks: false,
            sizedImageBuilder: (config) => const SizedBox(
              key: Key('custom'),
              width: 30,
              height: 30,
              child: ColoredBox(color: Colors.red),
            ),
            onTapLink: (text, href, title) => links.add(href),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('custom')));
      expect(links, ['https://l.example']);
    });

    testWidgets('an imageBuilder widget is wrapped in the link tap', (
      tester,
    ) async {
      final links = <String?>[];
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: doc,
            // ignore: deprecated_member_use
            imageBuilder: (uri, title, alt) => const SizedBox(
              key: Key('custom'),
              width: 30,
              height: 30,
              child: ColoredBox(color: Colors.red),
            ),
            onTapLink: (text, href, title) => links.add(href),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('custom')));
      expect(links, ['https://l.example']);
    });

    testWidgets('a builder for a owns the link, so the image has no tap', (
      tester,
    ) async {
      var links = 0;
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: doc,
            imageResolver: (uri, image) => _PendingProvider(),
            imageLoadingBuilder: (c, i) =>
                const SizedBox(width: 40, height: 40),
            onTapLink: (text, href, title) => links++,
            builders: {'a': _NoopBuilder()},
          ),
        ),
      );
      await tester.tap(find.byType(MdxImageView));
      expect(links, 0);
    });
  });
}

class _NoopBuilder extends MarkdownElementBuilder {}
