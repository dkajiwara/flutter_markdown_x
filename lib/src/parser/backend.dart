/// The entry point of the parser that converts Markdown to the IR.
///
/// The only parser is the bundled Rust implementation. It is called through
/// `dart:ffi` on FFI-capable platforms and through WebAssembly on the web. When it
/// is unavailable, [parseMarkdown] throws [MarkdownXParserUnavailableException]
/// (see doc/parser.md).
library;

export 'parser_status.dart';
export 'backend_ffi.dart'
    if (dart.library.js_interop) 'backend_web.dart'
    show
        initializeParser,
        isNativeParserActive,
        markdownXParserDiagnostics,
        parseMarkdown,
        parserRevision;
