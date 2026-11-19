# Images

This document covers image resolution, loading, failure, and tap behavior. It applies to `Markdown`, `MarkdownBody`, and `SliverMarkdown`.

The rules follow flutter_markdown's default image builder, with two deliberate differences: a failed image shows its alt text (flutter_markdown shows nothing), and local files are only read when you opt in (flutter_markdown reads `file:` and working-directory paths implicitly). The row-by-row comparison is [flutter_markdown_compat.md](flutter_markdown_compat.md#4d-images).

## Flow

```text
src ─ remove #fragment (#WxH sets the size) ─ resolve with imageDirectory ─▶ Uri ─ imageResolver ─▶ ImageProvider ─ Image ─▶ image
 │                                                │            │ (null goes to the default resolver)  ├ loading ─▶ imageLoadingBuilder
 │                                                │            └ exception / null                     └ failure ─▶ imageErrorBuilder
 └ empty / unparsable ────────────────────────────┴───────────────────────────────────────────────────▶ imageErrorBuilder
```

## Arguments

| Argument | Type | Role |
|---|---|---|
| `imageDirectory` | `String?` | flutter_markdown's base directory for relative paths. Also the opt-in to read local files below it (see [Local files](#local-files)) |
| `sizedImageBuilder` | `MarkdownSizedImageBuilder?` | flutter_markdown's `(MarkdownImageConfig) → Widget`. Replaces the whole image widget |
| `imageBuilder` | `MarkdownImageBuilder?` | Deprecated in flutter_markdown 0.7.7+1: `(Uri, String? title, String? alt) → Widget`. `sizedImageBuilder` wins when both are given |
| `imageResolver` | `MarkdownXImageResolver?` | `(Uri uri, MdxImage image) → ImageProvider?`. Returning null falls through to the default resolver |
| `imageLoadingBuilder` | `MarkdownXImageLoadingBuilder?` | `(BuildContext, MdxImage) → Widget`. The display while loading |
| `imageErrorBuilder` | `MarkdownXImageErrorBuilder?` | `(BuildContext, MdxImage, Object error) → Widget`. The display when the image cannot be shown |
| `onTapImage` | `MarkdownXImageTapCallback?` | `(MdxImage image, Uri? resolved)`. Called when the default image display is tapped |

`imageResolver`, `imageLoadingBuilder`, `imageErrorBuilder`, and `onTapImage` are extras of this package; they apply to the default image display only.

## Priority

For each image, the first one that applies in the following order is used.

1. When `inlineBuilder` returned an `InlineSpan` (images are also called as inlines)
2. When `builders['img']` (a flutter_markdown `MarkdownElementBuilder`) returned a widget
3. When `sizedImageBuilder` (or the deprecated `imageBuilder`) is given. Its widget replaces the whole image: resolution, loading, error display, and `onTapImage` do not apply. The builder receives the **unresolved** `Uri` (the src without the `#` fragment, not joined with `imageDirectory`), as in flutter_markdown. Inside a link, tapping the widget still taps the link
4. When `imageResolver` returned an `ImageProvider`
5. The default resolver (`markdownXDefaultImageProvider`)

## The src

- The `#` fragment is removed before anything else, so `x.png#100x50` requests `x.png`, and the resolver and the builders never see a fragment. A fragment of the form `#WxH` (exactly one `#` and one `x`) sets the width and height, which is flutter_markdown's `![alt](x.png#100x50)` syntax. Each side parses on its own (`#100x` is 100 wide); anything else carries no size.
- An empty or unparsable src has no URI and results in the error display (the resolver is not called).
- Dimensions from `#WxH` or from HTML `<img width= height=>` are normalized (see [Size normalization](#size-normalization)).

## Default resolver

`markdownXDefaultImageProvider(Uri)` converts as follows. A URI it cannot use returns null instead of throwing.

| scheme | Result |
|---|---|
| `http`, `https` | `NetworkImage` |
| `data:image/*` | `MemoryImage` (both base64 and percent encoding) |
| `data:text/*` | Not an image: the decoded text is shown as a `Text` (what flutter_markdown does) |
| `data:` with another media type | null (error display) |
| `asset`, `resource` | `AssetImage`. `asset:///images/a.png`, `asset:images/a.png`, and flutter_markdown's `resource:images/a.png` all become `images/a.png`. A package asset is written `asset:///packages/<package>/images/a.png` |
| `file` | null. **Local files are not read by default** (see below) |
| Others | null |

`asset:` is a convention of this package, not a standard URI scheme (`resource:` is flutter_markdown's alias for it). A relative path without a scheme is not implicitly regarded as an asset. To use assets, write `asset:` or `resource:` explicitly or map them in `imageResolver`.

## Relative paths and `imageDirectory`

A src without a scheme is joined with `imageDirectory` the way flutter_markdown does on each platform:

| Platform | Join |
|---|---|
| Not web | String concatenation: `imageDirectory + src`. `'https://a.example/docs/'` + `'img/a.png'` is `https://a.example/docs/img/a.png`, and `'/img'` + `'a.png'` is `/imga.png` (so end the directory with `/`) |
| Web | `p.join(imageDirectory, src)`: `'https://a.example/docs/guide/'` + `'/a.png'` is `https://a.example/a.png` |

- Only a src **without a scheme** is joined. A src with another scheme (`ftp:`, `file:`) is never concatenated.
- If the result has an `http` or `https` scheme, it is loaded over the network.
- A relative src with **no** `imageDirectory`:
  - off the web it is passed to `imageResolver` as a relative `Uri` without a scheme. The default resolver does not load it (flutter_markdown would call `Image.file` relative to the process directory), so it shows the error display;
  - on the web it is requested from the page, resolved against `Uri.base` (same-origin HTTP, as flutter_markdown does with `p.join(p.current, src)`).
- `imageDirectory` is a string and is concatenated, not resolved as a URI. For RFC 3986 resolution, resolve in `imageResolver`: `(uri, image) => NetworkImage(Uri.parse('https://a.example/docs/').resolveUri(uri).toString())`.
- **Link hrefs are not resolved.** `onTapLink` receives the string as written.

## Local files

Local files are not read by default so that untrusted Markdown (such as AI output) cannot display files on the device. This is a deliberate difference from flutter_markdown, which loads any non-network src with `Image.file`.

- **A non-null `imageDirectory` is the opt-in** for the files below it: a relative src is joined with it, and if the result is not an `http(s)` URL (off the web) it is loaded with a `FileImage`, **only when the file lies strictly inside that directory**. An `imageDirectory` that itself uses the `file:` scheme (`file:///app/docs/`) works too.
- **Path traversal is rejected.** The src is appended to `imageDirectory` as a string (flutter_markdown's rule), percent-decoded once, and both the directory and the result are normalized and compared as paths. These show the error display (the alt text) and never throw:
  - `../private/photo.png`, `sub/../../x.png`, `%2e%2e/x.png`, and on Windows `..\x.png` and `..%5cx.png`;
  - an absolute src (`/etc/x.png`, `C:\x.png`, `\\server\share\x.png`) and a NUL character;
  - a symbolic link inside the directory that points outside (or a link that cannot be resolved): existing paths are resolved with `resolveSymbolicLinksSync` on both sides before comparing;
  - an `imageDirectory` without a trailing separator, because `'/app/docs'` + `'a.png'` is `/app/docsa.png`, a sibling of the directory (end the directory with `/`).
- Paths that stay inside (`sub/../a.png`, `a%20b.png`) load. The path is checked when the image is resolved; a file replaced by a link afterwards is not detected. This is a guard against untrusted Markdown, not a sandbox: files that are reachable inside the directory are still shown, and an `imageResolver` you write sees the unchecked URI (`/app/docs/../private/photo.png`) and is responsible for its own checks.
- **Network and web.** For an `http(s)` `imageDirectory`, and for any relative src on the web, a src that climbs above the starting directory (`../x.png`, `%2e%2e/x.png`, `%252e%252e/x.png`, `..\x.png`) is not requested by the default resolver, so it cannot reach another path of the same server. On the web a root-relative src (`/a.png`) is rejected too (`p.join` would discard the directory). Without an `imageDirectory`, a relative src on the web is still requested from the page as in flutter_markdown.
- An **absolute `file:` src is not covered** by that opt-in. To load it, call `markdownXFileImageProvider(uri)` from `imageResolver`:

```dart
Markdown(
  data: markdown,
  imageResolver: (uri, image) => markdownXFileImageProvider(uri),
);
```

- `markdownXFileImageProvider` always returns null on the web.
- Note that fetching an arbitrary `http` URL is allowed. To restrict the allowed schemes, have `imageResolver` return, for URIs outside the allowed set, an image that does not fall through to the default resolver (for example, a one-pixel transparent image) or a provider that produces an error.

## Loading and error

- loading: the default is an empty area of the declared size (see below). An image without a size has size 0, and the layout changes after loading. You can place a placeholder with `imageLoadingBuilder`
- error: the default is the **alt text** (or the src if there is no alt). flutter_markdown shows an empty `SizedBox` here; the alt text keeps the image's meaning visible and readable. Network failures, decode failures, resolver exceptions, and unresolvable URIs all show the same thing. The cause can be told apart with the `error` argument of `imageErrorBuilder`
- For an image with a declared size, the loading and error displays are placed inside that area (anything that overflows is clipped). The layout does not change before and after loading

## Fade-in

The default display fades an image in when it finishes loading: 200 ms with an ease-out curve (`MarkdownXDefaults.imageFadeInDuration`, `MarkdownXDefaults.imageFadeInCurve`).

- `MarkdownStyleSheet.imageFadeInDuration` changes the duration; `Duration.zero` turns the fade off
- An image that is already in Flutter's image cache (for example a block built again after scrolling) is shown at once, without a fade
- There is no fade when the platform asks to reduce animations (`MediaQueryData.disableAnimations`)
- A later frame of an animated image (GIF, WebP) does not fade again
- Widgets from `sizedImageBuilder`, `imageBuilder`, `builders['img']` and `inlineBuilder` are not faded

## Size normalization

`width` and `height` come from `#WxH` or from the HTML `<img width= height=>`. The values are not validated when they enter the IR, so NaN, infinity, negative, 0, and huge values are possible. `markdownXNormalizeImageSize` normalizes them as follows, so the layout never throws.

- NaN, infinity, and values of 0 or less are discarded (treated as not specified)
- Values over `MarkdownXDefaults.maxImageExtent` (8192) are rounded down. When both are present, the aspect ratio is kept
- When the aspect ratio is too extreme to represent, only the width is kept
- When both are valid and larger than the available width, the image is shrunk keeping its aspect ratio (it is never enlarged)
- When only one is given, that value is fixed and the other follows the image's aspect ratio. If it exceeds the available width, it shrinks under the usual constraints of `Image`

## Tap

- An image inside a link (`[![alt](a.png)](https://example.com)`) taps the link: `onTapLink` receives the image's alt text as the link text, the href and the title, as in flutter_markdown. This works for the default display and for the widget of `sizedImageBuilder` / `imageBuilder`
- Only when `onTapImage` is passed (or the image is in a link), the default image display gets a tap area, a pointer cursor (click), and a semantics tap action. `onTapImage` is called first, then the link. Nothing is added otherwise
- The loading and failure displays can also be tapped. `resolved` is the resolved `Uri`, and null when src is empty or similar
- Taps reach the image even inside text selection (`SelectionArea`). The image remains excluded from selection and copy (alt is not copied either), and selection of other text is unaffected

## Accessibility

The alt text is read aloud once, as an image, by the outer `Semantics` (an image with empty alt is not read). The image, loading, and error displays are excluded from reading, so the semantics of widgets returned by `imageLoadingBuilder` and `imageErrorBuilder` are not used. When `onTapImage` is set, a tap action is added to the same node. See [accessibility.md](accessibility.md) for details.

## Rebuilding

The widget redraws all blocks when `imageDirectory` changes, or when `imageResolver`, `imageLoadingBuilder`, `imageErrorBuilder`, `sizedImageBuilder`, or `imageBuilder` change between null and non-null. A new closure of the same shape does not redraw (the newest one is used the next time a block builds), so flutter_markdown-style closures created in `build()` are fine. `onTapImage` goes through a relay on the widget side and never redraws (except null to non-null). The per-image resolution result (including decoding of data URIs) is reused as long as the image, `imageDirectory`, and the resolver do not change. See [flutter_markdown_compat.md](flutter_markdown_compat.md#4f-cache-invalidation-with-flutter_markdown-style-call-sites).

## Limitations

- Image dimensions can be specified with `#WxH` in the src or HTML `<img>`
- HTTP headers cannot be attached to the default `NetworkImage`. When authentication is needed, return `NetworkImage(url, headers: ...)` from `imageResolver`
- SVG cannot be shown by the default display, because Flutter's `Image` does not decode it (it results in the error display). See [SVG images](#svg-images)
- `<picture>` and `srcset` are not handled

## SVG images

SVG images, such as the badges at the top of a README, need an SVG renderer. The package does not depend on one; the app adds one, for example [`flutter_svg`](https://pub.dev/packages/flutter_svg). Animated GIF and WebP need nothing: the default display decodes them.

For images inside links (the usual `[![build](https://example.com/badge.svg)](https://example.com/ci)` badge), use `sizedImageBuilder`: tapping its widget still taps the link. It replaces every image, so it also builds the images that are not SVG:

```dart
import 'package:flutter_svg/flutter_svg.dart';

bool _isSvg(Uri uri) => uri.path.toLowerCase().endsWith('.svg');

Markdown(
  data: readme,
  onTapLink: (text, href, title) => launchUrl(Uri.parse(href!)),
  sizedImageBuilder: (config) {
    final url = config.uri.toString();
    final label = Text(config.alt ?? url);
    if (_isSvg(config.uri)) {
      return SvgPicture.network(
        url,
        width: config.width,
        height: config.height,
        semanticsLabel: config.alt,
        placeholderBuilder: (context) => const SizedBox.shrink(),
        errorBuilder: (context, error, stackTrace) => label,
      );
    }
    return Image.network(
      url,
      width: config.width,
      height: config.height,
      errorBuilder: (context, error, stackTrace) => label,
    );
  },
);
```

`config.uri` is the src as written: it is not joined with `imageDirectory`, and the default resolver (data URIs, assets, the local-file rules) does not run. When the document has relative or non-network images, resolve them in the builder too.

To keep the default display for everything except SVG, return a span for SVG images only from `inlineBuilder` and null otherwise. A span returned there gets no link tap, so this suits SVG images that are not inside links:

```dart
Markdown(
  data: markdown,
  inlineBuilder: (context, inline, style, buildDefault) {
    if (inline is! MdxImage || !_isSvg(Uri.parse(inline.src))) return null;
    return WidgetSpan(
      child: SvgPicture.network(
        inline.src,
        width: inline.width,
        height: inline.height,
        semanticsLabel: inline.alt,
      ),
    );
  },
);
```
