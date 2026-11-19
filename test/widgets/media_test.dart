// HTML media elements (doc/html.md): the `media` block, its typed reader, and how the default
// widgets, `builders` and `blockBuilder` handle it.
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

class _MediaBuilder extends MarkdownElementBuilder {
  final elements = <md.Element>[];

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    elements.add(element);
    return const Text('PLAYER');
  }
}

void main() {
  group('parser', () {
    test('a video element becomes a media block with a fallback link', () {
      final blocks = parseMarkdown(
        '<video src="https://e.com/v/clip.mp4" poster="p.jpg" width="640" '
        'height="360" controls>\nNo video support.\n</video>\n\nafter',
      );
      expect(blocks, [
        MdxCustomBlock(
          markdownXMediaType,
          attributes: {
            'kind': 'video',
            'src': 'https://e.com/v/clip.mp4',
            'poster': 'p.jpg',
            'width': '640',
            'height': '360',
          },
          inlines: [
            MdxLink(
              href: 'https://e.com/v/clip.mp4',
              children: [MdxText('clip.mp4')],
            ),
          ],
        ),
        MdxParagraph([MdxText('after')]),
      ]);
    });

    test('inline media in a paragraph is only the fallback link', () {
      expect(parseMarkdown('See <audio src="a.mp3" title="Song">x</audio>.'), [
        MdxParagraph([
          MdxText('See '),
          MdxLink(href: 'a.mp3', title: 'Song', children: [MdxText('Song')]),
          MdxText('.'),
        ]),
      ]);
    });

    test('a javascript: URL is not used', () {
      expect(parseMarkdown('<iframe src="javascript:alert(1)">fb</iframe>'), [
        MdxParagraph([MdxText('fb')]),
      ]);
    });
  });

  group('MarkdownXMedia.of', () {
    test('reads every attribute', () {
      final media = MarkdownXMedia.of(
        parseMarkdown(
          '<video controls width="640" height="360.5" title="Clip">'
          '<source src="a.webm" type="video/webm"></video>',
        ).single,
      )!;
      expect(media.kind, MarkdownXMediaKind.video);
      expect(media.src, 'a.webm');
      expect(media.uri, Uri.parse('a.webm'));
      expect(media.type, 'video/webm');
      expect(media.poster, isNull);
      expect(media.title, 'Clip');
      expect(media.width, 640);
      expect(media.height, 360.5);
    });

    test('reads each kind', () {
      for (final (source, kind) in [
        ('<audio src="a.mp3"></audio>', MarkdownXMediaKind.audio),
        ('<iframe src="f.html"></iframe>', MarkdownXMediaKind.iframe),
        ('<embed src="a.pdf">', MarkdownXMediaKind.embed),
        ('<object data="a.pdf"></object>', MarkdownXMediaKind.object),
      ]) {
        expect(
          MarkdownXMedia.of(parseMarkdown(source).single)?.kind,
          kind,
          reason: source,
        );
      }
    });

    test(
      'a non-numeric size is null and the raw value stays in attributes',
      () {
        final block = parseMarkdown('<iframe src="f" width="100%"></iframe>')
            .single;
        expect(MarkdownXMedia.of(block)!.width, isNull);
        expect((block as MdxCustomBlock).attributes['width'], '100%');
      },
    );

    test('returns null for other blocks and for a malformed media block', () {
      expect(MarkdownXMedia.of(MdxParagraph(const [])), isNull);
      expect(MarkdownXMedia.of(MdxCustomBlock('alert')), isNull);
      expect(
        MarkdownXMedia.of(
          MdxCustomBlock(markdownXMediaType, attributes: {'kind': 'video'}),
        ),
        isNull,
      );
      expect(
        MarkdownXMedia.of(
          MdxCustomBlock(
            markdownXMediaType,
            attributes: {'kind': 'flash', 'src': 'a'},
          ),
        ),
        isNull,
      );
    });

    test('uri is null for a URL that does not parse', () {
      final media = MarkdownXMedia.of(
        MdxCustomBlock(
          markdownXMediaType,
          attributes: {'kind': 'video', 'src': 'http://[bad'},
        ),
      )!;
      expect(media.src, 'http://[bad');
      expect(media.uri, isNull);
    });
  });

  group('widgets', () {
    testWidgets('by default the fallback link is shown and calls onTapLink', (
      tester,
    ) async {
      final taps = <(String, String?, String)>[];
      await tester.pumpWidget(
        _app(
          Markdown(
            data: '<video src="https://e.com/clip.mp4" title="Intro"></video>',
            onTapLink: (text, href, title) => taps.add((text, href, title)),
          ),
        ),
      );
      final link = find.textContaining('Intro');
      expect(link, findsOneWidget);
      await tester.tapAt(tester.getTopLeft(link) + const Offset(4, 4));
      expect(taps, [('Intro', 'https://e.com/clip.mp4', 'Intro')]);
    });

    testWidgets('builders["media"] receives the element and its attributes', (
      tester,
    ) async {
      final builder = _MediaBuilder();
      await tester.pumpWidget(
        _app(
          Markdown(
            data: '<embed src="doc.pdf" type="application/pdf">',
            builders: {markdownXMediaType: builder},
          ),
        ),
      );
      expect(find.text('PLAYER'), findsOneWidget);
      expect(find.textContaining('doc.pdf'), findsNothing);
      final element = builder.elements.single;
      expect(element.tag, markdownXMediaType);
      expect(element.attributes, {
        'kind': 'embed',
        'src': 'doc.pdf',
        'type': 'application/pdf',
      });
    });

    testWidgets('blockBuilder receives the media block', (tester) async {
      final seen = <MarkdownXMedia>[];
      await tester.pumpWidget(
        _app(
          Markdown(
            data: '> <audio src="a.mp3"></audio>',
            blockBuilder: (context, block, buildDefault) {
              final media = MarkdownXMedia.of(block);
              if (media == null) return null;
              seen.add(media);
              return Text('player:${media.src}');
            },
          ),
        ),
      );
      expect(find.text('player:a.mp3'), findsOneWidget);
      expect(seen.single.kind, MarkdownXMediaKind.audio);
    });
  });

  test(
    'incremental parsing matches the whole-document parse for every prefix',
    () {
      const source =
          '# Media\n\n<video controls poster="p.jpg">\n<source src="a.mp4" '
          'type="video/mp4">\nNo support\n</video>\n\ntext <audio src="b.mp3">'
          'x</audio> more\n\n<iframe src="https://e.com/embed/x">\n\n'
          'fallback\n\n</iframe>\n\n<embed src="c.pdf">\nafter\n\n'
          '<blockquote>\n<object data="d.pdf">fb</object>\n</blockquote>\n';
      final parser = IncrementalMarkdownParser();
      for (var end = 1; end <= source.length; end++) {
        final prefix = source.substring(0, end);
        expect(
          parser.parse(prefix),
          parseMarkdown(prefix),
          reason: 'prefix $end: $prefix',
        );
      }
    },
  );
}
