/// Serializes the IR (`MdxBlock` / `MdxInline`) into a form close to the expected
/// CommonMark / GFM HTML. For conformance checks only; not used by the library itself.
///
/// A soft break is written as `\n`, and the paragraphs of a tight list (`MdxList.tight`) are
/// not wrapped in `<p>`, as in CommonMark's HTML renderer.
///
/// `q`, `bdi`, `bdo` and `wbr` are not IR nodes: the parser turns them into their generated text
/// (quotation marks, bidi controls, U+200B), which is written as text. A block `<hr>` is an
/// `MdxThematicBreak` and is written as `<hr />`.
library;

import 'package:flutter_markdown_x/src/ir/nodes.dart';

/// Turns [blocks] into an HTML string.
String blocksToHtml(List<MdxBlock> blocks) {
  final out = StringBuffer();
  for (final block in blocks) {
    _block(block, out);
  }
  return out.toString();
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

void _inlines(Iterable<MdxInline> inlines, StringBuffer out) {
  for (final inline in inlines) {
    _inline(inline, out);
  }
}

String? _styleTag(MdxStyleKind kind) => switch (kind) {
  MdxStyleKind.strong => 'strong',
  MdxStyleKind.emphasis => 'em',
  MdxStyleKind.strikethrough => 'del',
  MdxStyleKind.code => 'code',
  MdxStyleKind.underline => 'u',
  MdxStyleKind.mark => 'mark',
  MdxStyleKind.subscript => 'sub',
  MdxStyleKind.superscript => 'sup',
  MdxStyleKind.keyboard => 'kbd',
  MdxStyleKind.small => 'small',
  MdxStyleKind.cite => 'cite',
  MdxStyleKind.definition => 'dfn',
  MdxStyleKind.variable => 'var',
  MdxStyleKind.sample => 'samp',
  MdxStyleKind.teletype => 'tt',
  MdxStyleKind.big => 'big',
  MdxStyleKind.abbreviation => 'abbr',
  MdxStyleKind.acronym => 'acronym',
};

/// Dynamically extracts `children` / `inlines` / `blocks` from an unknown node.
/// So that adding a type to the IR in another change does not crash; children are just emitted.
List<Object?> _dynamicChildren(Object node) {
  final dynamic d = node;
  for (final read in <List<Object?> Function()>[
    () => d.children as List<Object?>,
    () => d.inlines as List<Object?>,
    () => d.blocks as List<Object?>,
  ]) {
    try {
      return read();
      // A type without that field raises NoSuchMethodError.
      // ignore: avoid_catching_errors
    } on NoSuchMethodError {
      continue;
    } on TypeError {
      continue;
    }
  }
  return const [];
}

void _unknown(Object node, StringBuffer out) {
  for (final child in _dynamicChildren(node)) {
    if (child is MdxInline) {
      _inline(child, out);
    } else if (child is MdxBlock) {
      _block(child, out);
    }
  }
}

void _inline(MdxInline node, StringBuffer out) {
  if (node is MdxText) {
    out.write(_escape(node.text));
  } else if (node is MdxLineBreak) {
    out.write('<br />\n');
  } else if (node is MdxSoftBreak) {
    out.write('\n');
  } else if (node is MdxStyled) {
    final tag = _styleTag(node.kind);
    if (tag == null) {
      _inlines(node.children, out);
    } else {
      final title = node.title;
      out.write(title == null ? '<$tag>' : '<$tag title="${_escape(title)}">');
      _inlines(node.children, out);
      out.write('</$tag>');
    }
  } else if (node is MdxSpan) {
    out.write('<span>');
    _inlines(node.children, out);
    out.write('</span>');
  } else if (node is MdxLink) {
    out.write('<a href="${_escape(node.href)}"');
    if (node.title != null) out.write(' title="${_escape(node.title!)}"');
    out.write('>');
    _inlines(node.children, out);
    out.write('</a>');
  } else if (node is MdxImage) {
    out.write(
      '<img src="${_escape(node.src)}" alt="${_escape(node.alt ?? '')}"',
    );
    if (node.title != null) out.write(' title="${_escape(node.title!)}"');
    out.write(' />');
  } else {
    _unknown(node, out);
  }
}

String _alignAttr(MdxAlign? align) =>
    align == null ? '' : ' align="${align.name}"';

void _cell(
  String tag,
  MdxAlign? align,
  List<MdxInline> inlines,
  StringBuffer o,
) {
  o.write('<$tag${_alignAttr(align)}>');
  _inlines(inlines, o);
  o.write('</$tag>\n');
}

void _block(MdxBlock node, StringBuffer out) {
  if (node is MdxParagraph) {
    out.write('<p>');
    _inlines(node.inlines, out);
    out.write('</p>\n');
  } else if (node is MdxHeading) {
    out.write('<h${node.level}>');
    _inlines(node.inlines, out);
    out.write('</h${node.level}>\n');
  } else if (node is MdxCodeBlock) {
    final lang = node.language;
    final cls = lang == null || lang.isEmpty
        ? ''
        : ' class="language-${_escape(lang)}"';
    // The IR drops one trailing newline of code by convention, so restore it for the output format.
    final code = node.code.isEmpty ? node.code : '${node.code}\n';
    out.write('<pre><code$cls>${_escape(code)}</code></pre>\n');
  } else if (node is MdxBlockquote) {
    out.write('<blockquote>\n');
    for (final b in node.blocks) {
      _block(b, out);
    }
    out.write('</blockquote>\n');
  } else if (node is MdxList) {
    final tag = node.ordered ? 'ol' : 'ul';
    final start = node.ordered && node.start != 1
        ? ' start="${node.start}"'
        : '';
    out.write('<$tag$start>\n');
    for (final item in node.items) {
      out.write('<li>');
      if (item.checked != null) {
        out.write(
          '<input${item.checked! ? ' checked=""' : ''} disabled="" type="checkbox"> ',
        );
      }
      final blocks = item.blocks;
      if (!node.tight || blocks.isEmpty || blocks.first is! MdxParagraph) {
        out.write('\n');
      }
      for (var i = 0; i < blocks.length; i++) {
        final b = blocks[i];
        if (node.tight && b is MdxParagraph) {
          _inlines(b.inlines, out);
          if (i < blocks.length - 1) out.write('\n');
        } else {
          _block(b, out);
        }
      }
      out.write('</li>\n');
    }
    out.write('</$tag>\n');
  } else if (node is MdxTable) {
    out.write('<table>\n<thead>\n<tr>\n');
    for (var i = 0; i < node.header.length; i++) {
      _cell(
        'th',
        i < node.alignments.length ? node.alignments[i] : null,
        node.header[i],
        out,
      );
    }
    out.write('</tr>\n</thead>\n');
    if (node.rows.isNotEmpty) {
      out.write('<tbody>\n');
      for (final row in node.rows) {
        out.write('<tr>\n');
        for (var i = 0; i < row.length; i++) {
          _cell(
            'td',
            i < node.alignments.length ? node.alignments[i] : null,
            row[i],
            out,
          );
        }
        out.write('</tr>\n');
      }
      out.write('</tbody>\n');
    }
    out.write('</table>\n');
  } else if (node is MdxThematicBreak) {
    out.write('<hr />\n');
  } else if (node is MdxDetails) {
    out.write('<details>\n<summary>');
    _inlines(node.summary, out);
    out.write('</summary>\n');
    for (final b in node.blocks) {
      _block(b, out);
    }
    out.write('</details>\n');
  } else {
    _unknown(node, out);
  }
}
