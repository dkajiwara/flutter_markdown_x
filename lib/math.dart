/// Math (an optional extension).
///
/// This is not imported by the main `flutter_markdown_x` library. Only apps that
/// use it do `import 'package:flutter_markdown_x/math.dart';`. It does not depend
/// on any math rendering library (such as `flutter_math_fork`); the app supplies
/// one through [MarkdownXMathBuilder]. See doc/math.md for usage and limitations.
library;

export 'src/extensions/math.dart'
    show
        MarkdownXMath,
        MarkdownXMathBuilder,
        markdownXMathExtension,
        markdownXMathType;
