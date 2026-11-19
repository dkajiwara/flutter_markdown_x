/// Renders Markdown quickly as Flutter Widgets.
///
/// It converts in the order `Markdown → AST → IR → Widget` and never goes through
/// an HTML string. Inline HTML interprets only tags on the allowlist.
library;

export 'src/widgets/alert_view.dart' show MdxAlertView;
export 'src/extensions/alerts.dart'
    show
        MarkdownXAlertKind,
        markdownXAlertKindAttribute,
        markdownXAlertKindOf,
        markdownXAlertType,
        alertSourceMarker,
        markdownXAlertSource,
        markdownXAlertsExtension,
        markdownXTransformAlert;
export 'src/parser/backend.dart'
    show
        MarkdownXNativePlatform,
        MarkdownXParserDiagnostics,
        MarkdownXParserUnavailableException,
        initializeParser,
        isNativeParserActive,
        markdownXParserDiagnostics,
        parseMarkdown;
export 'src/widgets/citation_view.dart' show MdxCitationChips;
export 'src/extensions/citations.dart'
    show
        markdownXCitationExtension,
        markdownXCitationIds,
        markdownXCitationType;
export 'src/extensions/emoji.dart' show markdownXEmojiExtension;
export 'src/extensions/media.dart'
    show
        MarkdownXMedia,
        MarkdownXMediaKind,
        markdownXMediaKindAttribute,
        markdownXMediaSrcAttribute,
        markdownXMediaType;
export 'src/flutter_markdown/compat_types.dart';
export 'src/navigation/controller.dart' show MarkdownXController;
export 'src/flutter_markdown/element_builder.dart';
export 'src/extensions/extension.dart'
    show
        MarkdownXBlockTransform,
        MarkdownXExtension,
        MarkdownXInlineBuild,
        MarkdownXInlineSyntax,
        MarkdownXInlineTransform,
        MarkdownXRootTransform,
        MarkdownXSourceTransform,
        applyMarkdownXExtensions,
        applyMarkdownXSourceTransforms;
export 'src/style/extension_style.dart';
export 'src/style/highlighter.dart';
export 'src/parser/incremental_parser.dart' show IncrementalMarkdownParser;
export 'src/navigation/navigation.dart'
    show
        MarkdownXAnchor,
        MarkdownXAnchorKind,
        MarkdownXHeading,
        markdownXAnchors,
        markdownXHeadings,
        markdownXSlug;
export 'src/image/image.dart'
    show
        MarkdownXImageErrorBuilder,
        MarkdownXImageLoadingBuilder,
        MarkdownXImageResolver,
        MarkdownXImageTapCallback,
        markdownXDefaultImageProvider,
        markdownXFileImageProvider,
        markdownXNormalizeImageSize,
        markdownXResolveImageUri;
export 'src/widgets/image_view.dart' show MdxImageView;
export 'src/ir/nodes.dart';
export 'src/ir/task.dart';

export 'src/widgets/renderer.dart'
    show
        MarkdownXBlockBuilder,
        MarkdownXCitationBuilder,
        MarkdownXCitationCallback,
        MarkdownXInlineBuilder,
        MdxBlockContext,
        MdxRoot;
export 'src/parser/streaming.dart' show markdownXRepairStreamingTail;
export 'src/style/style.dart';
export 'src/style/style_sheet.dart';
export 'src/widgets/widget.dart';
