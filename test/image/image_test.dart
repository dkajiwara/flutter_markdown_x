import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/selection_harness.dart';

/// 1x1 PNG.
final _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

/// Provider that never finishes loading (to check the loading display).
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

/// Provider that always fails.
class _FailingProvider extends ImageProvider<_FailingProvider> {
  @override
  Future<_FailingProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _FailingProvider key,
    ImageDecoderCallback decode,
  ) =>
      OneFrameImageStreamCompleter(Future<ImageInfo>.error(StateError('boom')));
}

/// Provider that returns a prebuilt image as is.
class _LoadedProvider extends ImageProvider<_LoadedProvider> {
  _LoadedProvider(this.image);
  final ui.Image image;

  @override
  Future<_LoadedProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _LoadedProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(SynchronousFuture(ImageInfo(image: image)));
}

/// Provider whose image arrives when [completer] completes (an asynchronous load).
class _DeferredProvider extends ImageProvider<_DeferredProvider> {
  _DeferredProvider(this.completer);
  final Completer<ImageInfo> completer;

  @override
  Future<_DeferredProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _DeferredProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(completer.future);
}

Widget _app(Widget child, {double width = 400}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: SingleChildScrollView(child: child),
      ),
    ),
  ),
);

Size _imageBoxSize(WidgetTester tester) {
  // Rendered size of the WidgetSpan containing the image (or the loading / error display).
  final box = tester.renderObject<RenderBox>(find.byType(MdxImageView));
  return box.size;
}

void main() {
  group('markdownXResolveImageUri', () {
    test('absolute URI is kept as is', () {
      expect(
        markdownXResolveImageUri(
          'https://b.example/x.png',
          'https://a.example/docs/',
        ),
        Uri.parse('https://b.example/x.png'),
      );
    });

    test('relative path is appended to imageDirectory as a plain string', () {
      const dir = 'https://a.example/docs/guide/';
      expect(
        markdownXResolveImageUri('img/a.png', dir),
        Uri.parse('https://a.example/docs/guide/img/a.png'),
      );
      expect(
        markdownXResolveImageUri('../a.png', dir),
        Uri.parse('https://a.example/docs/guide/../a.png'),
      );
      // `/a.png` is a plain string append off the web and a root-relative path for `p.join` on the
      // web (flutter_markdown does the same per platform; test/image/web_image_test.dart).
      expect(
        markdownXResolveImageUri('/a.png', dir),
        Uri.parse(
          kIsWeb
              ? 'https://a.example/a.png'
              : 'https://a.example/docs/guide//a.png',
        ),
      );
    });

    test('relative path without imageDirectory is returned as relative', () {
      final uri = markdownXResolveImageUri('img/a.png', null);
      expect(uri, isNotNull);
      expect(uri!.hasScheme, isFalse);
      expect(uri.path, 'img/a.png');
    });

    test('empty, whitespace-only, or unparseable strings give null', () {
      expect(markdownXResolveImageUri('', null), isNull);
      expect(markdownXResolveImageUri('   ', 'https://a/'), isNull);
      expect(markdownXResolveImageUri('http://[bad', null), isNull);
    });

    test('surrounding whitespace is ignored', () {
      expect(
        markdownXResolveImageUri(' a.png ', 'https://a.example/'),
        Uri.parse('https://a.example/a.png'),
      );
    });
  });

  group('markdownXDefaultImageProvider', () {
    test('http and https give NetworkImage', () {
      final http = markdownXDefaultImageProvider(Uri.parse('http://a/x.png'));
      final https = markdownXDefaultImageProvider(Uri.parse('https://a/x.png'));
      expect(http, isA<NetworkImage>());
      expect((http! as NetworkImage).url, 'http://a/x.png');
      expect(https, isA<NetworkImage>());
    });

    test('data URI (base64, percent encoding) gives MemoryImage', () {
      final b64 = markdownXDefaultImageProvider(
        Uri.parse('data:image/png;base64,${base64Encode(_tinyPng)}'),
      );
      expect(b64, isA<MemoryImage>());
      expect((b64! as MemoryImage).bytes, _tinyPng);
      final plain = markdownXDefaultImageProvider(
        Uri.parse('data:image/svg+xml,%3Csvg%2F%3E'),
      );
      expect(plain, isA<MemoryImage>());
      expect(utf8.decode((plain! as MemoryImage).bytes), '<svg/>');
    });

    test('malformed data URI gives null (no exception)', () {
      expect(
        markdownXDefaultImageProvider(
          Uri(scheme: 'data', path: 'image/png;base64,@@@'),
        ),
        isNull,
      );
    });

    test('asset: gives AssetImage (leading / removed)', () {
      final triple = markdownXDefaultImageProvider(
        Uri.parse('asset:///images/a.png'),
      );
      expect(triple, isA<AssetImage>());
      expect((triple! as AssetImage).assetName, 'images/a.png');
      final opaque = markdownXDefaultImageProvider(
        Uri.parse('asset:images/b.png'),
      );
      expect((opaque! as AssetImage).assetName, 'images/b.png');
    });

    test('empty asset path gives null', () {
      expect(markdownXDefaultImageProvider(Uri.parse('asset:///')), isNull);
    });

    test(
      'default resolver does not read file: (local file display is opt-in)',
      () {
        expect(
          markdownXDefaultImageProvider(Uri.parse('file:///tmp/a.png')),
          isNull,
        );
      },
    );

    test('markdownXFileImageProvider gives FileImage only off the web, null on the web', () {
      final provider = markdownXFileImageProvider(
        Uri.parse('file:///tmp/a.png'),
      );
      if (kIsWeb) {
        expect(provider, isNull);
      } else {
        expect(provider, isA<FileImage>());
        // The platform's form of the path (`\tmp\a.png` on Windows).
        expect(
          (provider! as FileImage).file.path,
          Uri.parse('file:///tmp/a.png').toFilePath(),
        );
      }
    });

    test('unsupported scheme and scheme-less URI give null', () {
      expect(markdownXDefaultImageProvider(Uri.parse('ftp://a/x.png')), isNull);
      expect(markdownXDefaultImageProvider(Uri.parse('img/a.png')), isNull);
      expect(markdownXDefaultImageProvider(Uri.parse('')), isNull);
    });
  });

  group('markdownXNormalizeImageSize', () {
    test('valid values are kept as is', () {
      final s = markdownXNormalizeImageSize(120, 80);
      expect((s.width, s.height), (120.0, 80.0));
    });

    test('NaN, infinity, negative and 0 are dropped (the valid one is kept if only one is valid)', () {
      for (final bad in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -5.0,
        0.0,
        -0.0,
      ]) {
        final w = markdownXNormalizeImageSize(bad, 50);
        expect((w.width, w.height), (null, 50.0), reason: '$bad');
        final h = markdownXNormalizeImageSize(50, bad);
        expect((h.width, h.height), (50.0, null), reason: '$bad');
        final both = markdownXNormalizeImageSize(bad, bad);
        expect((both.width, both.height), (null, null), reason: '$bad');
      }
    });

    test('null stays null', () {
      final s = markdownXNormalizeImageSize(null, null);
      expect((s.width, s.height), (null, null));
    });

    test(
      'values above the limit are clamped; with both, the aspect ratio is kept',
      () {
        const max = MarkdownXDefaults.maxImageExtent;
        final one = markdownXNormalizeImageSize(1e12, null);
        expect((one.width, one.height), (max, null));
        final both = markdownXNormalizeImageSize(max * 4, max * 2);
        expect((both.width, both.height), (max, max / 2));
        final tall = markdownXNormalizeImageSize(max * 2, max * 8);
        expect((tall.width, tall.height), (max / 4, max));
      },
    );

    test(
      'an extremely small positive value still becomes a finite positive value',
      () {
        final s = markdownXNormalizeImageSize(double.minPositive, 1e300);
        expect(s.width == null || (s.width!.isFinite && s.width! >= 0), isTrue);
        expect(s.height!.isFinite && s.height! > 0, isTrue);
      },
    );
  });

  group('resolution and precedence', () {
    testWidgets('resolver receives the URI resolved with imageDirectory', (
      tester,
    ) async {
      final seen = <Uri>[];
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '![a](img/a.png) ![b](https://c.example/b.png)',
            imageDirectory: 'https://a.example/docs/',
            imageResolver: (uri, image) {
              seen.add(uri);
              return _PendingProvider();
            },
          ),
        ),
      );
      expect(seen, [
        Uri.parse('https://a.example/docs/img/a.png'),
        Uri.parse('https://c.example/b.png'),
      ]);
    });

    testWidgets('re-resolves when imageDirectory changes', (tester) async {
      final seen = <Uri>[];
      ImageProvider? resolver(Uri uri, MdxImage image) {
        seen.add(uri);
        return _PendingProvider();
      }

      Widget body(String base) => _app(
        MarkdownBody(
          data: '![a](a.png)',
          imageDirectory: base,
          imageResolver: resolver,
        ),
      );
      await tester.pumpWidget(body('https://one.example/'));
      await tester.pumpWidget(body('https://two.example/'));
      expect(seen.last, Uri.parse('https://two.example/a.png'));
    });

    testWidgets(
      'relative path without imageDirectory is passed to resolver as relative',
      (tester) async {
        Uri? seen;
        await tester.pumpWidget(
          _app(
            MarkdownBody(
              data: '![a](img/a.png)',
              imageResolver: (uri, image) {
                seen = uri;
                return _PendingProvider();
              },
            ),
          ),
        );
        expect(seen!.hasScheme, isFalse);
        expect(seen!.path, 'img/a.png');
      },
    );

    testWidgets('an inlineBuilder image takes precedence over resolver', (
      tester,
    ) async {
      var resolverCalls = 0;
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '![a](https://a.example/a.png)',
            inlineBuilder: (c, inline, style, buildDefault) =>
                inline is MdxImage
                ? const WidgetSpan(child: Icon(Icons.star))
                : null,
            imageResolver: (uri, image) {
              resolverCalls++;
              return _PendingProvider();
            },
          ),
        ),
      );
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(resolverCalls, 0);
    });

    testWidgets('falls through to resolver when inlineBuilder returns null', (
      tester,
    ) async {
      var resolverCalls = 0;
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '![a](https://a.example/a.png)',
            inlineBuilder: (c, inline, style, buildDefault) => null,
            imageResolver: (uri, image) {
              resolverCalls++;
              return _PendingProvider();
            },
          ),
        ),
      );
      expect(resolverCalls, 1);
    });

    testWidgets('uses the default resolver when resolver returns null', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '![a](https://a.example/a.png)',
            imageResolver: (uri, image) => null,
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<NetworkImage>());
    });

    testWidgets('rendering continues and shows error when resolver throws', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: 'before ![alt text](https://a.example/a.png) after',
            imageResolver: (uri, image) => throw StateError('bad'),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('alt text'), findsOneWidget);
    });

    testWidgets('data URI is rendered with MemoryImage', (tester) async {
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '![dot](data:image/png;base64,${base64Encode(_tinyPng)})',
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<MemoryImage>());
    });

    testWidgets(
      'scheme-less relative path without imageDirectory shows error (no exception)',
      (tester) async {
        await tester.pumpWidget(
          _app(const MarkdownBody(data: '![the alt](img/a.png)')),
        );
        expect(tester.takeException(), isNull);
        if (kIsWeb) {
          // On the web a relative src is requested from the page (Uri.base), as in
          // flutter_markdown; test/image/web_image_test.dart covers it.
          expect(find.byType(Image), findsOneWidget);
        } else {
          expect(find.text('the alt'), findsOneWidget);
          expect(find.byType(Image), findsNothing);
        }
      },
    );

    testWidgets('unsupported scheme also shows error', (tester) async {
      await tester.pumpWidget(
        _app(const MarkdownBody(data: '![ftp alt](ftp://a/x.png)')),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('ftp alt'), findsOneWidget);
    });

    testWidgets('link href is not resolved with imageDirectory', (
      tester,
    ) async {
      String? tapped;
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '[go](page.html)',
            imageDirectory: 'https://a.example/',
            onTapLink: (text, href, title) => tapped = href,
          ),
        ),
      );
      await tester.tapAt(
        tester.getTopLeft(find.byType(RichText).first) + const Offset(4, 4),
      );
      expect(tapped, 'page.html');
    });

    testWidgets(
      'imageDirectory and resolver also work in Markdown and SliverMarkdown',
      (tester) async {
        final seen = <Uri>[];
        ImageProvider? resolver(Uri uri, MdxImage image) {
          seen.add(uri);
          return _PendingProvider();
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Markdown(
                data: '![a](a.png)',
                imageDirectory: 'https://m.example/',
                imageResolver: resolver,
              ),
            ),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  SliverMarkdown(
                    data: '![a](a.png)',
                    imageDirectory: 'https://s.example/',
                    imageResolver: resolver,
                  ),
                ],
              ),
            ),
          ),
        );
        expect(seen, [
          Uri.parse('https://m.example/a.png'),
          Uri.parse('https://s.example/a.png'),
        ]);
      },
    );
  });

  group('loading and error', () {
    testWidgets('default loading is an empty area of the declared size', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '<img src="https://a.example/a.png" width="40" height="20">',
            imageResolver: (uri, image) => _PendingProvider(),
          ),
        ),
      );
      expect(_imageBoxSize(tester), const Size(40, 20));
    });

    testWidgets('imageLoadingBuilder is used only while loading', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '![a](https://a.example/a.png)',
            imageResolver: (uri, image) => _PendingProvider(),
            imageLoadingBuilder: (context, image) =>
                Text('loading ${image.src}'),
          ),
        ),
      );
      expect(find.text('loading https://a.example/a.png'), findsOneWidget);
    });

    testWidgets(
      'the loading display goes away and becomes the image once loaded',
      (tester) async {
        final image = (await tester.runAsync(
          () => createTestImage(width: 8, height: 4),
        ))!;
        await tester.pumpWidget(
          _app(
            MarkdownBody(
              data: '![a](https://a.example/a.png)',
              imageResolver: (uri, i) => _LoadedProvider(image),
              imageLoadingBuilder: (context, i) => const Text('loading'),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('loading'), findsNothing);
        expect(find.byType(RawImage), findsOneWidget);
      },
    );

    testWidgets('imageErrorBuilder receives the failed image and the error', (
      tester,
    ) async {
      Object? seen;
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '![alt](https://a.example/a.png)',
            imageResolver: (uri, image) => _FailingProvider(),
            imageErrorBuilder: (context, image, error) {
              seen = error;
              return Text('failed ${image.alt}');
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.text('failed alt'), findsOneWidget);
      expect(seen, isA<StateError>());
    });

    testWidgets(
      'imageErrorBuilder is also used for images that cannot be resolved',
      (tester) async {
        await tester.pumpWidget(
          _app(
            MarkdownBody(
              data: '![alt](ftp://a/x.png)',
              imageErrorBuilder: (context, image, error) => const Text('E'),
            ),
          ),
        );
        expect(find.text('E'), findsOneWidget);
      },
    );

    testWidgets('default error is alt; src if there is no alt', (tester) async {
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '![alt text](https://a.example/a.png) <img src="https://a.example/b.png">',
            imageResolver: (uri, image) => _FailingProvider(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('alt text'), findsOneWidget);
      expect(find.text('https://a.example/b.png'), findsOneWidget);
    });

    testWidgets(
      'alt is announced exactly once in loading, error, and loaded states',
      (tester) async {
        final handle = tester.ensureSemantics();
        final loaded = (await tester.runAsync(
          () => createTestImage(width: 8, height: 4),
        ))!;
        for (final provider in <ImageProvider>[
          _PendingProvider(),
          _FailingProvider(),
          _LoadedProvider(loaded),
        ]) {
          await tester.pumpWidget(
            _app(
              MarkdownBody(
                data: 'x ![a red dot](https://a.example/a.png) y',
                imageResolver: (uri, image) => provider,
                imageLoadingBuilder: (c, i) => const Text('loading'),
                imageErrorBuilder: (c, i, e) => const Text('error'),
              ),
            ),
          );
          await tester.pump();
          expect(
            find.semantics.byLabel(RegExp('a red dot')).evaluate(),
            hasLength(1),
            reason: '$provider',
          );
          expect(find.semantics.byLabel('loading').evaluate(), isEmpty);
          expect(find.semantics.byLabel('error').evaluate(), isEmpty);
        }
        handle.dispose();
      },
    );
  });

  group('fade in', () {
    Finder fade() => find.descendant(
      of: find.byType(MdxImageView),
      matching: find.byType(FadeTransition),
    );

    Future<void> pumpDeferred(
      WidgetTester tester, {
      MarkdownStyleSheet? styleSheet,
      bool disableAnimations = false,
    }) async {
      final image = (await tester.runAsync(
        () => createTestImage(width: 8, height: 4),
      ))!;
      final completer = Completer<ImageInfo>();
      if (disableAnimations) {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
      }
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '![a](https://a.example/a.png)',
            styleSheet: styleSheet,
            imageResolver: (uri, i) => _DeferredProvider(completer),
          ),
        ),
      );
      completer.complete(ImageInfo(image: image));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('an image that loads asynchronously fades in', (tester) async {
      await pumpDeferred(tester);
      final transition = tester.widget<FadeTransition>(fade());
      expect(transition.opacity.value, lessThan(1));
      await tester.pump(MarkdownXDefaults.imageFadeInDuration);
      expect(transition.opacity.value, 1);
    });

    testWidgets('imageFadeInDuration sets the duration', (tester) async {
      const duration = Duration(milliseconds: 600);
      await pumpDeferred(
        tester,
        styleSheet: MarkdownStyleSheet(imageFadeInDuration: duration),
      );
      final transition = tester.widget<FadeTransition>(fade());
      await tester.pump(duration ~/ 2);
      expect(transition.opacity.value, inExclusiveRange(0, 1));
      await tester.pump(duration);
      expect(transition.opacity.value, 1);
    });

    testWidgets('Duration.zero turns the fade off', (tester) async {
      await pumpDeferred(
        tester,
        styleSheet: MarkdownStyleSheet(imageFadeInDuration: Duration.zero),
      );
      expect(fade(), findsNothing);
    });

    testWidgets('no fade when the platform asks to reduce animations', (
      tester,
    ) async {
      await pumpDeferred(tester, disableAnimations: true);
      expect(fade(), findsNothing);
    });

    testWidgets('an image that is available synchronously does not fade', (
      tester,
    ) async {
      final image = (await tester.runAsync(
        () => createTestImage(width: 8, height: 4),
      ))!;
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '![a](https://a.example/a.png)',
            imageResolver: (uri, i) => _LoadedProvider(image),
          ),
        ),
      );
      await tester.pump();
      expect(fade(), findsNothing);
    });
  });

  group('dimension normalization and layout', () {
    Future<void> pumpHtml(WidgetTester tester, String attrs) =>
        tester.pumpWidget(
          _app(
            MarkdownBody(
              data: 'a <img src="https://a.example/a.png" $attrs> b',
              imageResolver: (uri, image) => _PendingProvider(),
            ),
          ),
        );

    testWidgets(
      'NaN, infinity, negative, 0 and huge values do not throw and give a finite size',
      (tester) async {
        for (final attrs in [
          'width="NaN" height="NaN"',
          'width="Infinity" height="-Infinity"',
          'width="-10" height="-20"',
          'width="0" height="0"',
          'width="1e308" height="1e308"',
          'width="1e308"',
          'height="1e308"',
          'width="NaN" height="30"',
          'width="30" height="Infinity"',
          'width="5e-324" height="5e-324"',
        ]) {
          await pumpHtml(tester, attrs);
          expect(tester.takeException(), isNull, reason: attrs);
          final size = _imageBoxSize(tester);
          expect(
            size.width.isFinite && size.height.isFinite,
            isTrue,
            reason: attrs,
          );
          expect(size.width <= 400, isTrue, reason: attrs);
        }
      },
    );

    testWidgets(
      'a size larger than the available width is shrunk, keeping the aspect ratio',
      (tester) async {
        final image = (await tester.runAsync(
          () => createTestImage(width: 2, height: 1),
        ))!;
        await tester.pumpWidget(
          _app(
            MarkdownBody(
              data: '<img src="https://a.example/a.png" width="800" height="400">',
              imageResolver: (uri, i) => _LoadedProvider(image),
            ),
            width: 200,
          ),
        );
        await tester.pump();
        final size = _imageBoxSize(tester);
        expect(size.width, 200);
        expect(size.height, 100);
      },
    );

    testWidgets('a size that fits the available width is kept as is', (
      tester,
    ) async {
      await pumpHtml(tester, 'width="100" height="50"');
      expect(_imageBoxSize(tester), const Size(100, 50));
    });

    testWidgets('extreme sizes do not throw inside table cells', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '| a |\n|---|\n| <img src="https://a.example/a.png" width="1e308" height="NaN"> |',
            imageResolver: (uri, image) => _PendingProvider(),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('tap and selection', () {
    testWidgets('onTapImage receives the image and the resolved URI', (
      tester,
    ) async {
      MdxImage? tappedImage;
      Uri? tappedUri;
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '![alt](img/a.png "title")',
            imageDirectory: 'https://a.example/docs/',
            imageResolver: (uri, image) => _PendingProvider(),
            imageLoadingBuilder: (c, i) =>
                const SizedBox(width: 40, height: 40),
            onTapImage: (image, resolved) {
              tappedImage = image;
              tappedUri = resolved;
            },
          ),
        ),
      );
      await tester.tap(find.byType(MdxImageView));
      expect(tappedImage!.src, 'img/a.png');
      expect(tappedImage!.alt, 'alt');
      expect(tappedImage!.title, 'title');
      expect(tappedUri, Uri.parse('https://a.example/docs/img/a.png'));
    });

    testWidgets(
      'an image showing error can also be tapped (resolved may be null)',
      (tester) async {
        var taps = 0;
        Uri? resolved = Uri.parse('x:');
        await tester.pumpWidget(
          _app(
            MarkdownBody(
              data: '![alt](ftp://a/x.png)',
              onTapImage: (image, uri) {
                taps++;
                resolved = uri;
              },
            ),
          ),
        );
        await tester.tap(find.text('alt'));
        expect(taps, 1);
        expect(resolved, Uri.parse('ftp://a/x.png'));
      },
    );

    testWidgets(
      'without onTapImage, taps are not consumed and semantics has no tap',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _app(
            MarkdownBody(
              data: '![alt](https://a.example/a.png)',
              imageResolver: (uri, image) => _PendingProvider(),
            ),
          ),
        );
        expect(find.byType(GestureDetector), findsNothing);
        expect(
          find.semantics.byLabel('alt').evaluate().single,
          isSemantics(isImage: true, hasTapAction: false),
        );
        handle.dispose();
      },
    );

    testWidgets('with onTapImage, the image semantics gets a tap action', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          MarkdownBody(
            data: '![alt](https://a.example/a.png)',
            imageResolver: (uri, image) => _PendingProvider(),
            onTapImage: (image, uri) {},
          ),
        ),
      );
      expect(
        find.semantics.byLabel('alt').evaluate().single,
        isSemantics(isImage: true, hasTapAction: true),
      );
      handle.dispose();
    });

    testWidgets(
      'taps still arrive when selectable, and copied text excludes the image alt',
      (tester) async {
        final probe = ClipboardProbe();
        mockClipboard(tester, probe);
        var taps = 0;
        await tester.pumpWidget(
          _app(
            MarkdownBody(
              data: 'before ![alt text](https://a.example/a.png) after',
              selectable: true,
              imageResolver: (uri, image) => _PendingProvider(),
              imageLoadingBuilder: (c, i) =>
                  const SizedBox(width: 40, height: 40),
              onTapImage: (image, uri) => taps++,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(MdxImageView));
        expect(taps, 1);
        final copied = await selectAllAndCopy(
          tester,
          probe,
          find.descendant(
            of: find.byType(SelectionArea),
            matching: find.byType(RichText),
          ),
        );
        expect(copied, isNot(contains('alt text')));
        expect(copied, contains('before'));
        expect(copied, contains('after'));
      },
    );
  });

  group('scope updates', () {
    testWidgets(
      'a new resolver instance alone does not re-resolve; adding or removing one does',
      (tester) async {
        var calls = 0;
        ImageProvider? first(Uri uri, MdxImage image) {
          calls++;
          return _PendingProvider();
        }

        ImageProvider? second(Uri uri, MdxImage image) {
          calls += 100;
          return _PendingProvider();
        }

        Widget build(MarkdownXImageResolver? r) =>
            _app(MarkdownBody(data: '![a](https://a/a.png)', imageResolver: r));
        await tester.pumpWidget(build(first));
        await tester.pumpWidget(build(first));
        expect(calls, 1);
        // Callbacks are read through the relay and are not compared by identity.
        await tester.pumpWidget(build(second));
        expect(calls, 1);
        // Removing and adding a resolver changes what blocks render, so they rebuild.
        await tester.pumpWidget(build(null));
        await tester.pumpWidget(build(second));
        expect(calls, 101);
      },
    );

    testWidgets('repaints when a loading builder is added or removed', (
      tester,
    ) async {
      Widget build(String? label) => _app(
        MarkdownBody(
          data: '![a](https://a/a.png)',
          imageResolver: (uri, image) => _PendingProvider(),
          imageLoadingBuilder: label == null ? null : (c, i) => Text(label),
        ),
      );
      await tester.pumpWidget(build('one'));
      expect(find.text('one'), findsOneWidget);
      // A new closure with the same nullness does not invalidate built blocks.
      await tester.pumpWidget(build('two'));
      expect(find.text('one'), findsOneWidget);
      await tester.pumpWidget(build(null));
      expect(find.text('one'), findsNothing);
      await tester.pumpWidget(build('two'));
      expect(find.text('two'), findsOneWidget);
    });
  });
}
