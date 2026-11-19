/// Mermaid diagrams (an optional extension).
///
/// This is not imported by the main `flutter_markdown_x` library. Only apps that
/// use it do `import 'package:flutter_markdown_x/mermaid.dart';`. It does not depend
/// on any Mermaid rendering library; the app supplies one through
/// [MarkdownXMermaidBuilder]. See doc/mermaid.md for usage and limitations.
library;

export 'src/extensions/mermaid.dart'
    show
        MarkdownXMermaid,
        MarkdownXMermaidBuilder,
        markdownXMermaidExtension,
        markdownXMermaidType;
