/// A Dart port of commonmark-spec's `test/normalize.py`.
///
/// Aligns whitespace folding, whitespace stripping around block tags, attribute ordering,
/// lowercasing of tag names, and entity decoding, so HTML can then be compared.
library;

const _blockTags = <String>{
  'article',
  'header',
  'aside',
  'hgroup',
  'blockquote',
  'hr',
  'iframe',
  'body',
  'li',
  'map',
  'button',
  'object',
  'canvas',
  'ol',
  'caption',
  'output',
  'col',
  'p',
  'colgroup',
  'pre',
  'dd',
  'progress',
  'div',
  'section',
  'dl',
  'table',
  'td',
  'dt',
  'tbody',
  'embed',
  'textarea',
  'fieldset',
  'tfoot',
  'figcaption',
  'th',
  'figure',
  'thead',
  'footer',
  'tr',
  'form',
  'ul',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'video',
  'script',
  'style',
  'details',
  'summary',
  'nav',
  'main',
  'address',
};

const _voidTags = <String>{'br', 'hr', 'img', 'input', 'col', 'meta', 'link'};

final _tagRe = RegExp(
  r'<!--(?:>|->|.*?-->)|<(/?)([a-zA-Z][a-zA-Z0-9-]*)((?:\s+[^\s=>/"'
  "'"
  r']+(?:\s*=\s*(?:"[^"]*"|'
  "'[^']*'"
  r'|[^\s>"'
  "'"
  r'=<`]+))?)*)\s*(/?)>',
  dotAll: true,
);
final _attrRe = RegExp(
  r'([^\s=>/"'
  "'"
  r']+)(?:\s*=\s*(?:"([^"]*)"|'
  "'([^']*)'"
  r'|([^\s>]+)))?',
);
final _entityRe = RegExp(r'&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z][a-zA-Z0-9]*);');
final _wsRe = RegExp(r'\s+');

const _named = <String, String>{
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
};

String _decode(String s) => s.replaceAllMapped(_entityRe, (m) {
  final body = m.group(1)!;
  if (body.startsWith('#')) {
    final hex = body.startsWith('#x') || body.startsWith('#X');
    final code = int.tryParse(
      body.substring(hex ? 2 : 1),
      radix: hex ? 16 : 10,
    );
    if (code == null || code > 0x10FFFF) return m.group(0)!;
    return String.fromCharCode(code);
  }
  return _named[body] ?? m.group(0)!;
});

/// Turns [html] into a canonical form for comparison.
///
/// When [tolerantLists] is true, removes `<p>` / `</p>` directly under `<li>`.
/// The IR does not distinguish tight / loose lists, so this setting ignores only that difference.
String normalizeHtml(String html, {bool tolerantLists = false}) {
  final out = StringBuffer();
  final stack = <String>[];
  var inPre = false;
  var stripLeading = true;

  void text(String raw) {
    var t = _decode(raw);
    if (!inPre) t = t.replaceAll(_wsRe, ' ');
    if (stripLeading && !inPre) t = t.trimLeft();
    if (t.isEmpty) return;
    out.write(t);
    stripLeading = false;
  }

  void trimTrailing() {
    if (inPre) return;
    final s = out.toString().trimRight();
    out
      ..clear()
      ..write(s);
  }

  var pos = 0;
  final buf = StringBuffer();
  void flushText() {
    if (buf.isNotEmpty) {
      text(buf.toString());
      buf.clear();
    }
  }

  for (final m in _tagRe.allMatches(html)) {
    buf.write(html.substring(pos, m.start));
    pos = m.end;
    final whole = m.group(0)!;
    if (whole.startsWith('<!--')) {
      // Comments are not kept in the output; the surrounding text is joined.
      continue;
    }
    final closing = m.group(1) == '/';
    final name = m.group(2)!.toLowerCase();
    final isVoid = _voidTags.contains(name);
    final dropP =
        tolerantLists &&
        name == 'p' &&
        (closing
            ? stack.length >= 2 && stack[stack.length - 2] == 'li'
            : stack.isNotEmpty && stack.last == 'li');
    flushText();
    final block = _blockTags.contains(name);
    if (closing) {
      if (stack.isNotEmpty && stack.last == name) stack.removeLast();
      if (dropP) {
        trimTrailing();
        stripLeading = true;
        continue;
      }
      if (block) trimTrailing();
      if (name == 'pre') inPre = false;
      out.write('</$name>');
      stripLeading = block;
      continue;
    }
    if (dropP) {
      stack.add(name);
      stripLeading = true;
      continue;
    }
    if (block) trimTrailing();
    final attrs = <String, String>{};
    for (final a in _attrRe.allMatches(m.group(3) ?? '')) {
      attrs[a.group(1)!.toLowerCase()] = _decode(
        a.group(2) ?? a.group(3) ?? a.group(4) ?? '',
      );
    }
    final keys = attrs.keys.toList()..sort();
    out.write('<$name');
    for (final k in keys) {
      out.write(' $k="${attrs[k]}"');
    }
    final selfClose = isVoid || m.group(4) == '/';
    out.write(selfClose ? ' />' : '>');
    if (!selfClose) stack.add(name);
    if (name == 'pre' && !selfClose) inPre = true;
    stripLeading = block;
  }
  buf.write(html.substring(pos));
  flushText();
  return out.toString().trim();
}
