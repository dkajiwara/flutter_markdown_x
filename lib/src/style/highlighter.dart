/// A lightweight syntax highlighter for code blocks.
///
/// It has no per-language grammar and only recognizes comments, strings, numbers,
/// and keywords with regular expressions. If you need precision, replace it with
/// `MarkdownWidget.syntaxHighlighter`.
library;

/// The kind of a token.
enum MdxCodeTokenKind {
  /// Text that gets no color.
  plain,

  /// A reserved word of the language.
  keyword,

  /// A string literal.
  string,

  /// comment.
  comment,

  /// A numeric literal.
  number,
}

/// One piece of colored code.
final class MdxCodeToken {
  /// Creates a token.
  const MdxCodeToken(this.kind, this.text);

  /// The kind of the token.
  final MdxCodeTokenKind kind;

  /// The text of the token.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is MdxCodeToken && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => '${kind.name}(${text.replaceAll('\n', r'\n')})';
}

/// A function that splits code into tokens. Returns null for a language that gets no coloring.
///
/// Concatenating the `text` of the returned tokens must give back the original code.
typedef MarkdownXHighlighter = List<MdxCodeToken>? Function(
  String code,
  String? language,
);

const _neverMatches = '(?!)';
const _defaultNumber =
    r'\b0[xX][0-9a-fA-F_]+\b|\b\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?\b';
const _defaultWord = r'[A-Za-z_$][A-Za-z0-9_$]*';

final class _Language {
  _Language({
    required String keywords,
    this.lineComments = const ['//'],
    this.blockComment = const ('/*', '*/'),
    this.quotes = const ['"', "'"],
    this.multilineQuotes = const [],
    this.caseInsensitive = false,
    this.numberPattern = _defaultNumber,
    this.wordPattern = _defaultWord,
    this.wordIsKeyword = false,
    this.multiLine = false,
    this.commentPattern,
    this.stringPattern,
  }) : keywords = keywords.isEmpty ? const {} : keywords.split(' ').toSet();

  final Set<String> keywords;
  final List<String> lineComments;
  final (String, String)? blockComment;

  /// Quote characters of single-line strings.
  final List<String> quotes;

  /// Quote characters of strings that may span multiple lines.
  final List<String> multilineQuotes;
  final bool caseInsensitive;

  /// The number pattern. It varies per language, as with CSS colors (`#fff`) and units (`4px`).
  final String numberPattern;

  /// The identifier pattern. Change it for languages whose identifiers contain hyphens, such as CSS `font-size`.
  final String wordPattern;

  /// When true, everything that matches [wordPattern] becomes a keyword (HTML tags,
  /// removed lines of a diff, and so on).
  final bool wordIsKeyword;

  /// When true, `^` matches at the start of a line (diff, markdown).
  final bool multiLine;

  /// When given, it is used instead of the default comment and string patterns.
  final String? commentPattern;
  final String? stringPattern;

  late final RegExp pattern = _buildPattern();

  RegExp _buildPattern() {
    final comments = [
      if (blockComment case (final open, final close))
        '${RegExp.escape(open)}[\\s\\S]*?(?:${RegExp.escape(close)}|\$)',
      for (final marker in lineComments) '${RegExp.escape(marker)}[^\\n]*',
    ];
    final strings = [
      // An unclosed string runs to the end (to the end of the line for a single-line string).
      for (final quote in multilineQuotes)
        '${RegExp.escape(quote)}(?:\\\\[\\s\\S]|(?!${RegExp.escape(quote)})'
            '[\\s\\S])*(?:${RegExp.escape(quote)}|\$)',
      for (final quote in quotes)
        '${RegExp.escape(quote)}(?:\\\\.|[^\\\\\\n${RegExp.escape(quote)}])*'
            '${RegExp.escape(quote)}?',
    ];
    // A group name is required even for a language with no candidates, so put in a pattern that never matches.
    final comment =
        commentPattern ??
        (comments.isEmpty ? _neverMatches : comments.join('|'));
    final string =
        stringPattern ?? (strings.isEmpty ? _neverMatches : strings.join('|'));
    return RegExp(
      [
        '(?<comment>$comment)',
        '(?<string>$string)',
        '(?<number>$numberPattern)',
        '(?<word>$wordPattern)',
      ].join('|'),
      multiLine: multiLine,
    );
  }
}

const _cLikeKeywords =
    'if else for while do switch case default break continue return '
    'true false null new this class enum static const try catch finally throw';

final _dart = _Language(
  keywords:
      '$_cLikeKeywords abstract as assert async await base covariant deferred '
      'dynamic export extends extension external factory final get implements '
      'import in interface is late library mixin on operator part required '
      'rethrow sealed set show hide super sync typedef var void when with yield',
  multilineQuotes: const ['"""', "'''"],
);

final _javascript = _Language(
  keywords:
      '$_cLikeKeywords abstract any as async await boolean declare delete '
      'export extends from function get implements import in instanceof '
      'interface keyof let namespace never number of private protected public '
      'readonly set string super type typeof undefined unknown var void yield',
  multilineQuotes: const ['`'],
);

final _java = _Language(
  keywords:
      '$_cLikeKeywords abstract boolean byte char double extends final float '
      'implements import instanceof int interface long native package private '
      'protected public record short super synchronized throws var void '
      'volatile',
);

final _kotlin = _Language(
  keywords:
      '$_cLikeKeywords abstract as by companion constructor data fun import in '
      'init interface internal is lateinit object open override package '
      'private protected public sealed super suspend typealias val var when',
  multilineQuotes: const ['"""'],
);

final _swift = _Language(
  keywords:
      '$_cLikeKeywords actor any as associatedtype async await defer extension '
      'fileprivate func guard import in init inout internal is let nil open '
      'override private protocol public repeat self some struct super throws '
      'typealias var where',
  multilineQuotes: const ['"""'],
  quotes: const ['"'],
);

final _go = _Language(
  keywords:
      '$_cLikeKeywords chan defer fallthrough func go goto import interface '
      'map nil package range select struct type var',
  multilineQuotes: const ['`'],
);

final _rust = _Language(
  keywords:
      '$_cLikeKeywords as async await crate dyn extern fn impl in let loop '
      'match mod move mut pub ref self Self struct super trait type unsafe '
      'use where',
  // `'a` is also used for lifetimes, so single quotes are not treated as strings.
  quotes: const ['"'],
);

final _c = _Language(
  keywords:
      '$_cLikeKeywords auto bool char double extern float inline int long '
      'namespace nullptr private protected public short signed sizeof struct '
      'template typedef typename union unsigned using virtual void volatile',
);

final _csharp = _Language(
  keywords:
      '$_cLikeKeywords abstract as async await base bool byte char decimal '
      'double float foreach in int interface internal is long namespace '
      'object out override private protected public readonly ref sealed '
      'string struct using var virtual void',
);

final _python = _Language(
  keywords:
      'and as assert async await break class continue def del elif else '
      'except False finally for from global if import in is lambda None '
      'nonlocal not or pass raise return True try while with yield',
  lineComments: const ['#'],
  blockComment: null,
  multilineQuotes: const ['"""', "'''"],
);

final _ruby = _Language(
  keywords:
      'alias and begin break case class def do else elsif end ensure false '
      'for if in module next nil not or redo require rescue retry return '
      'self super then true unless until when while yield',
  lineComments: const ['#'],
  blockComment: null,
);

final _shell = _Language(
  keywords:
      'if then else elif fi for while until do done case esac in function '
      'return exit export local readonly set unset source',
  lineComments: const ['#'],
  blockComment: null,
);

final _yaml = _Language(
  keywords: 'true false null yes no on off',
  lineComments: const ['#'],
  blockComment: null,
);

final _json = _Language(
  keywords: 'true false null',
  lineComments: const [],
  blockComment: null,
  quotes: const ['"'],
);

final _sql = _Language(
  keywords:
      'select from where and or not null is in like between join inner left '
      'right outer on as group by order having limit offset insert into '
      'values update set delete create table alter drop index view primary '
      'key foreign references default unique distinct union all case when '
      'then else end exists true false',
  lineComments: const ['--'],
  quotes: const ["'"],
  caseInsensitive: true,
);

final _jsonc = _Language(keywords: 'true false null', quotes: const ['"']);

final _php = _Language(
  keywords:
      '$_cLikeKeywords abstract and array as callable echo elseif empty '
      'endfor endforeach endif endwhile extends final fn foreach function '
      'global implements include include_once instanceof interface isset list '
      'match namespace or print private protected public readonly require '
      'require_once trait unset use var xor yield',
  lineComments: const ['//', '#'],
);

final _scala = _Language(
  keywords:
      '$_cLikeKeywords abstract case extends final given implicit import lazy '
      'match object override package private protected sealed super trait type '
      'using val var with yield def',
  multilineQuotes: const ['"""'],
);

final _objc = _Language(
  keywords:
      '$_cLikeKeywords id nil self super void BOOL YES NO char int long short '
      'float double unsigned signed struct typedef enum extern static',
);

final _lua = _Language(
  keywords:
      'and break do else elseif end false for function goto if in local nil '
      'not or repeat return then true until while',
  lineComments: const ['--'],
  blockComment: ('--[[', ']]'),
);

final _perl = _Language(
  keywords:
      'my our local sub use no package require if elsif else unless while '
      'until for foreach return last next redo do eval die print',
  lineComments: const ['#'],
  blockComment: null,
);

final _r = _Language(
  keywords:
      'if else for while repeat function return break next TRUE FALSE NULL NA '
      'Inf NaN in library require',
  lineComments: const ['#'],
  blockComment: null,
);

final _powershell = _Language(
  keywords:
      'begin break catch class continue data do dynamicparam else elseif end '
      'exit filter finally for foreach from function if in param process '
      'return switch throw trap try until using var while',
  lineComments: const ['#'],
  blockComment: ('<#', '#>'),
  caseInsensitive: true,
  // Treat `$name` and hyphenated names such as `Write-Host` as a single word.
  wordPattern: r'\$?[A-Za-z_][A-Za-z0-9_]*(?:-[A-Za-z][A-Za-z0-9_]*)*',
);

final _graphql = _Language(
  keywords:
      'query mutation subscription fragment on type interface union enum '
      'input scalar schema extend directive implements true false null',
  lineComments: const ['#'],
  blockComment: null,
  multilineQuotes: const ['"""'],
  quotes: const ['"'],
);

final _dockerfile = _Language(
  keywords:
      'from run cmd label maintainer expose env add copy entrypoint volume '
      'user workdir arg onbuild stopsignal healthcheck shell as',
  lineComments: const ['#'],
  blockComment: null,
  caseInsensitive: true,
);

final _cmake = _Language(
  keywords:
      'if elseif else endif foreach endforeach while endwhile function '
      'endfunction macro endmacro set project add_executable add_library '
      'target_link_libraries include find_package option message',
  lineComments: const ['#'],
  blockComment: null,
  caseInsensitive: true,
);

final _makefile = _Language(
  keywords:
      'ifeq ifneq ifdef ifndef else endif include define endef export '
      'override .PHONY',
  lineComments: const ['#'],
  blockComment: null,
  wordPattern: r'\.?[A-Za-z_][A-Za-z0-9_]*',
);

final _ini = _Language(
  keywords: 'true false yes no on off',
  lineComments: const [';', '#'],
  blockComment: null,
);

final _css = _Language(
  keywords:
      'important inherit initial unset auto none and not only from to '
      '@media @import @font-face @keyframes @supports @charset',
  lineComments: const [],
  // Color `#fff`, `4px`, and `50%` in `a { b: c }` as numbers.
  numberPattern:
      r'#[0-9a-fA-F]{3,8}\b|(?<![\w-])\d[\d_]*(?:\.\d+)?(?:[a-zA-Z]+|%)?',
  wordPattern: r'@?[A-Za-z_-][A-Za-z0-9_-]*',
);

final _scss = _Language(
  keywords:
      'important inherit initial unset auto none and not only from to '
      '@media @import @mixin @include @extend @use @function @return @if '
      '@else @each @for',
  numberPattern:
      r'#[0-9a-fA-F]{3,8}\b|(?<![\w-])\d[\d_]*(?:\.\d+)?(?:[a-zA-Z]+|%)?',
  wordPattern: r'@?[A-Za-z_-][A-Za-z0-9_-]*',
);

/// HTML and XML. Tag names (`<a`, `</a`, `<?xml`) are keywords and attribute values are strings.
final _markup = _Language(
  keywords: '',
  commentPattern: r'<!--[\s\S]*?(?:-->|$)|<!\[CDATA\[[\s\S]*?(?:\]\]>|$)',
  stringPattern:
      r'"[^"\n]*"?|'
      "'[^'\\n]*'?",
  // Entity references (`&amp;`) get the same color as numbers.
  numberPattern: r'&#?\w{1,10};',
  wordPattern: r'</?[A-Za-z][\w:.-]*|<[!?][\w-]+',
  wordIsKeyword: true,
);

/// Unified diff. Added lines are strings, removed lines are keywords, and hunk headers are comments.
final _diff = _Language(
  keywords: '',
  commentPattern: r'^(?:\+\+\+|---|@@|diff |index )[^\n]*',
  stringPattern: r'^\+[^\n]*',
  numberPattern: _neverMatches,
  wordPattern: r'^-[^\n]*',
  wordIsKeyword: true,
  multiLine: true,
);

/// Markdown. Headings, fences, and emphasis are keywords, and inline code is a string.
final _markdown = _Language(
  keywords: '',
  commentPattern: r'<!--[\s\S]*?(?:-->|$)',
  stringPattern: r'`[^`\n]*`?',
  numberPattern: _neverMatches,
  wordPattern: r'^#{1,6} [^\n]*|^ {0,3}(?:```|~~~)[^\n]*|\*\*[^*\n]+\*\*',
  wordIsKeyword: true,
  multiLine: true,
);

final _languages = <String, _Language>{
  'jsonc': _jsonc,
  'json5': _jsonc,
  'php': _php,
  'scala': _scala,
  'objc': _objc,
  'objective-c': _objc,
  'objectivec': _objc,
  'lua': _lua,
  'perl': _perl,
  'pl': _perl,
  'r': _r,
  'powershell': _powershell,
  'pwsh': _powershell,
  'ps1': _powershell,
  'graphql': _graphql,
  'gql': _graphql,
  'dockerfile': _dockerfile,
  'docker': _dockerfile,
  'cmake': _cmake,
  'makefile': _makefile,
  'make': _makefile,
  'ini': _ini,
  'conf': _ini,
  'properties': _ini,
  'css': _css,
  'scss': _scss,
  'less': _scss,
  'html': _markup,
  'htm': _markup,
  'xml': _markup,
  'svg': _markup,
  'xhtml': _markup,
  'plist': _markup,
  'vue': _markup,
  'diff': _diff,
  'patch': _diff,
  'markdown': _markdown,
  'md': _markdown,
  'dart': _dart,
  'javascript': _javascript,
  'js': _javascript,
  'jsx': _javascript,
  'mjs': _javascript,
  'typescript': _javascript,
  'ts': _javascript,
  'tsx': _javascript,
  'java': _java,
  'kotlin': _kotlin,
  'kt': _kotlin,
  'swift': _swift,
  'go': _go,
  'golang': _go,
  'rust': _rust,
  'rs': _rust,
  'c': _c,
  'h': _c,
  'cpp': _c,
  'c++': _c,
  'cc': _c,
  'hpp': _c,
  'csharp': _csharp,
  'cs': _csharp,
  'c#': _csharp,
  'python': _python,
  'py': _python,
  'ruby': _ruby,
  'rb': _ruby,
  'bash': _shell,
  'sh': _shell,
  'shell': _shell,
  'zsh': _shell,
  'yaml': _yaml,
  'yml': _yaml,
  'toml': _yaml,
  'json': _json,
  'sql': _sql,
};

/// The built-in highlighter. Returns null for a language it does not support.
List<MdxCodeToken>? highlightCode(String code, String? language) {
  final definition = _languages[language?.toLowerCase()];
  if (definition == null) return null;

  final tokens = <MdxCodeToken>[];
  final plain = StringBuffer();
  void flushPlain() {
    if (plain.isEmpty) return;
    tokens.add(MdxCodeToken(MdxCodeTokenKind.plain, plain.toString()));
    plain.clear();
  }

  var position = 0;
  for (final match in definition.pattern.allMatches(code)) {
    final text = match[0]!;
    // An empty match does not advance, so skip it.
    if (text.isEmpty) continue;
    plain.write(code.substring(position, match.start));
    position = match.end;

    final MdxCodeTokenKind? kind;
    if (match.namedGroup('comment') != null) {
      kind = MdxCodeTokenKind.comment;
    } else if (match.namedGroup('string') != null) {
      kind = MdxCodeTokenKind.string;
    } else if (match.namedGroup('number') != null) {
      kind = MdxCodeTokenKind.number;
    } else {
      final word = definition.caseInsensitive ? text.toLowerCase() : text;
      kind = definition.wordIsKeyword || definition.keywords.contains(word)
          ? MdxCodeTokenKind.keyword
          : null;
    }

    if (kind == null) {
      plain.write(text);
    } else {
      flushPlain();
      tokens.add(MdxCodeToken(kind, text));
    }
  }
  plain.write(code.substring(position));
  flushPlain();
  return tokens;
}
