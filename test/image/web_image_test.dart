@TestOn('browser')
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_x/src/image/image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('web image paths (flutter_markdown _functions_web)', () {
    test('imageDirectory is joined with p.join, not concatenated', () {
      expect(
        markdownXResolveImageUri('a.png', '/img'),
        Uri.parse('/img/a.png'),
      );
      expect(
        markdownXResolveImageUri('a.png', '/img/'),
        Uri.parse('/img/a.png'),
      );
    });

    test('a relative src is requested from the page (p.current)', () {
      final provider = markdownXLocalImageProvider(
        Uri.parse('img/a.png'),
        imageDirectory: null,
        src: 'img/a.png',
      );
      expect(provider, isA<NetworkImage>());
      expect((provider! as NetworkImage).url, p.join(p.current, 'img/a.png'));
      expect((provider as NetworkImage).url, startsWith(Uri.base.origin));
    });

    test('a relative src under imageDirectory is requested from the page', () {
      final uri = markdownXResolveImageUri('a.png', '/img')!;
      final provider = markdownXLocalImageProvider(
        uri,
        imageDirectory: '/img',
        src: 'a.png',
      );
      expect((provider! as NetworkImage).url, p.join(p.current, '/img/a.png'));
    });

    test('a src that leaves imageDirectory is rejected', () {
      bool escapes(String src) => markdownXImageEscapesDirectory(
        '/img/',
        src,
        resolved: markdownXResolveImageUri(src, '/img/')!,
      );
      expect(escapes('../a.png'), isTrue);
      expect(escapes('%2e%2e/a.png'), isTrue);
      expect(escapes('/a.png'), isTrue);
      expect(escapes('x/../a.png'), isFalse);
    });

    test('file: is never read on the web', () {
      expect(
        markdownXLocalImageProvider(
          Uri.parse('file:///tmp/a.png'),
          imageDirectory: 'file:///tmp/',
          src: 'a.png',
        ),
        isNull,
      );
      expect(
        markdownXFileImageProvider(Uri.parse('file:///tmp/a.png')),
        isNull,
      );
    });

    test('resource:, data:text/* and #WxH behave as on other platforms', () {
      final asset = markdownXDefaultImageProvider(
        Uri.parse('resource:a/b.png'),
      );
      expect((asset! as AssetImage).assetName, 'a/b.png');
      expect(markdownXDataImageText(Uri.parse('data:text/plain,hi')), 'hi');
      final s = markdownXParseImageSource('x.png#10x20');
      expect((s.path, s.width, s.height), ('x.png', 10.0, 20.0));
    });
  });
}
