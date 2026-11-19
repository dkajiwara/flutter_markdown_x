/// Builds Markdown for benchmarks.
library;

/// Number of top-level blocks in one section (matches the template below).
const blocksPerSection = 6;

String _section(int index) =>
    '''
## Section $index

Paragraph $index with **bold**, *italic*, `code`, a [link](https://example.com/$index)
and inline HTML: H<sub>2</sub>O, <kbd>Ctrl</kbd> + <kbd>C</kbd>, <mark>mark</mark>.

- item one of $index
- item two with **bold**
  - nested item

```dart
void section$index() {
  print('section $index');
}
```

| name | value |
|------|------:|
| a$index | 1 |
| b$index | 2 |

> quote $index with *emphasis*

''';

/// Returns a document with [sections] sections.
String buildDocument(int sections) {
  final buffer = StringBuffer('# Benchmark document\n\n');
  for (var i = 0; i < sections; i++) {
    buffer.write(_section(i));
  }
  return buffer.toString();
}
