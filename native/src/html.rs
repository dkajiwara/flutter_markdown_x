//! Splits raw HTML in Markdown into tokens and assembles them into an inline tree.
//!
//! The supported tags and attributes are documented in `doc/html.md`. Tags not in the
//! allowlist are shown as written.

use crate::autolink::autolink;
use crate::css::parse_inline_style;
use crate::ir::{Block, Inline, StyleKind};
use std::ops::Range;

/// A token before the inline sequence is assembled.
pub enum Token {
    /// Plain text from Markdown. Adjacent ones are joined before searching for URLs.
    Markdown(String),
    /// Text from an HTML block. URLs are not searched for.
    Text(String),
    Open(String, Vec<(String, String)>),
    Close(String),
    /// An inline already converted from Markdown syntax.
    Node(Inline),
}

const LINK_TAG: &str = "a";
const LINE_BREAK_TAG: &str = "br";
const IMAGE_TAG: &str = "img";
const FONT_TAG: &str = "font";
const QUOTE_TAG: &str = "q";
const ISOLATE_TAG: &str = "bdi";
const OVERRIDE_TAG: &str = "bdo";
const WORD_BREAK_TAG: &str = "wbr";

/// Tags that carry a `title` and are kept as [`Inline::Titled`].
fn titled_kind(tag: &str) -> Option<StyleKind> {
    match tag {
        "abbr" => Some(StyleKind::Abbreviation),
        "acronym" => Some(StyleKind::Acronym),
        _ => None,
    }
}

// Generated content of the HTML Living Standard's default rendering (`quotes: auto`) and the
// Unicode bidirectional controls that express `unicode-bidi: isolate` / `bidi-override`.
const OUTER_QUOTE: (char, char) = ('\u{201C}', '\u{201D}');
const INNER_QUOTE: (char, char) = ('\u{2018}', '\u{2019}');
const ZERO_WIDTH_SPACE: char = '\u{200B}';
const FIRST_STRONG_ISOLATE: char = '\u{2068}';
const LEFT_TO_RIGHT_ISOLATE: char = '\u{2066}';
const RIGHT_TO_LEFT_ISOLATE: char = '\u{2067}';
const POP_DIRECTIONAL_ISOLATE: char = '\u{2069}';
const LEFT_TO_RIGHT_OVERRIDE: char = '\u{202D}';
const RIGHT_TO_LEFT_OVERRIDE: char = '\u{202E}';
const POP_DIRECTIONAL_FORMATTING: char = '\u{202C}';

/// HTML tags that have no closing tag. The opening tag alone completes them.
const VOID_TAGS: [&str; 13] = [
    "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track",
    "wbr",
];

fn style_kind(tag: &str) -> Option<StyleKind> {
    Some(match tag {
        "b" | "strong" => StyleKind::Strong,
        "i" | "em" => StyleKind::Emphasis,
        "s" | "del" | "strike" => StyleKind::Strikethrough,
        "code" => StyleKind::Code,
        "u" | "ins" => StyleKind::Underline,
        "mark" => StyleKind::Mark,
        "sub" => StyleKind::Subscript,
        "sup" => StyleKind::Superscript,
        "kbd" => StyleKind::Keyboard,
        "small" => StyleKind::Small,
        "cite" => StyleKind::Cite,
        "dfn" => StyleKind::Definition,
        "var" => StyleKind::Variable,
        "samp" => StyleKind::Sample,
        "tt" => StyleKind::Teletype,
        "big" => StyleKind::Big,
        _ => return None,
    })
}

// ---------------------------------------------------------------------------
// Entities and whitespace
// ---------------------------------------------------------------------------

const NBSP: char = '\u{00A0}';
const HEX_RADIX: u32 = 16;
const DECIMAL_RADIX: u32 = 10;

fn named_entity(name: &str) -> Option<char> {
    Some(match name {
        "amp" => '&',
        "lt" => '<',
        "gt" => '>',
        "quot" => '"',
        "apos" => '\'',
        "nbsp" => NBSP,
        "copy" => '©',
        "reg" => '®',
        "trade" => '™',
        "mdash" => '—',
        "ndash" => '–',
        "hellip" => '…',
        "laquo" => '«',
        "raquo" => '»',
        "ldquo" => '“',
        "rdquo" => '”',
        "lsquo" => '‘',
        "rsquo" => '’',
        "times" => '×',
        "divide" => '÷',
        "deg" => '°',
        "plusmn" => '±',
        "middot" => '·',
        "bull" => '•',
        "larr" => '←',
        "rarr" => '→',
        "uarr" => '↑',
        "darr" => '↓',
        "euro" => '€',
        "yen" => '¥',
        "pound" => '£',
        "cent" => '¢',
        "sect" => '§',
        "para" => '¶',
        _ => return None,
    })
}

fn entity_char(body: &str) -> Option<char> {
    let Some(number) = body.strip_prefix('#') else {
        return named_entity(body);
    };
    let code = match number.strip_prefix(['x', 'X']) {
        Some(hex) => u32::from_str_radix(hex, HEX_RADIX).ok()?,
        None => number
            .parse::<u32>()
            .ok()
            .filter(|_| number.chars().all(|c| c.is_digit(DECIMAL_RADIX)))?,
    };
    char::from_u32(code)
}

/// Turns `&amp;` and `&#39;` back into characters. Anything that cannot be interpreted is left as is.
pub fn decode_entities(text: &str) -> String {
    if !text.contains('&') {
        return text.to_string();
    }
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(start) = rest.find('&') {
        out.push_str(&rest[..start]);
        let after = &rest[start + 1..];
        let decoded = after.find(';').and_then(|end| {
            let body = &after[..end];
            let valid =
                !body.is_empty() && body.chars().all(|c| c.is_ascii_alphanumeric() || c == '#');
            if valid {
                entity_char(body).map(|c| (c, end))
            } else {
                None
            }
        });
        match decoded {
            Some((c, end)) => {
                out.push(c);
                rest = &after[end + 1..];
            }
            None => {
                out.push('&');
                rest = after;
            }
        }
    }
    out.push_str(rest);
    out
}

/// Turns a soft break (a newline and the whitespace around it) into a single space.
fn collapse_line_breaks(text: String) -> String {
    if !text.contains('\n') && !text.contains('\r') {
        return text;
    }
    let mut out = String::with_capacity(text.len());
    let mut skipping = false;
    let mut previous_was_line_break = false;
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\n' || c == '\r' {
            if c == '\r' && chars.peek() == Some(&'\n') {
                chars.next();
            }
            // A single source break replaces adjacent horizontal whitespace.
            // Preserve the space generated by the preceding newline so blank
            // lines remain distinct (`\n\n` becomes two spaces).
            if !previous_was_line_break {
                let kept = out.trim_end_matches([' ', '\t']).len();
                out.truncate(kept);
            }
            out.push(' ');
            skipping = true;
            previous_was_line_break = true;
        } else if skipping && (c == ' ' || c == '\t') {
            // Skip whitespace right after a newline.
        } else {
            skipping = false;
            previous_was_line_break = false;
            out.push(c);
        }
    }
    out
}

// ---------------------------------------------------------------------------
// Tokenizer
// ---------------------------------------------------------------------------

const COMMENT_OPEN: &str = "<!--";
const COMMENT_CLOSE: &str = "-->";

fn is_attribute_name_start(c: u8) -> bool {
    c.is_ascii_alphabetic() || c == b'_' || c == b':'
}

fn is_attribute_name_char(c: u8) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, b'-' | b'_' | b':' | b'.')
}

fn parse_attributes(source: &str) -> Vec<(String, String)> {
    let bytes = source.as_bytes();
    let mut attributes = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        if !is_attribute_name_start(bytes[i]) {
            i += 1;
            continue;
        }
        let name_start = i;
        while i < bytes.len() && is_attribute_name_char(bytes[i]) {
            i += 1;
        }
        let name = source[name_start..i].to_ascii_lowercase();

        let mut j = i;
        while j < bytes.len() && bytes[j].is_ascii_whitespace() {
            j += 1;
        }
        let mut value = "";
        if j < bytes.len() && bytes[j] == b'=' {
            j += 1;
            while j < bytes.len() && bytes[j].is_ascii_whitespace() {
                j += 1;
            }
            if j < bytes.len() && (bytes[j] == b'"' || bytes[j] == b'\'') {
                let quote = bytes[j] as char;
                let start = j + 1;
                match source[start..].find(quote) {
                    Some(len) => {
                        value = &source[start..start + len];
                        i = start + len + 1;
                    }
                    None => i = j + 1,
                }
            } else {
                let start = j;
                while j < bytes.len()
                    && !bytes[j].is_ascii_whitespace()
                    && !matches!(bytes[j], b'"' | b'\'' | b'=' | b'<' | b'>' | b'`')
                {
                    j += 1;
                }
                value = &source[start..j];
                i = j.max(i);
            }
        }
        attributes.push((name, decode_entities(value)));
    }
    attributes
}

/// Finds the `>` that ends an opening or closing tag. A `<` or `>` inside a quoted attribute
/// value is skipped. `from` is the position right after the tag name. None if the tag does not end
/// (a `<` appears first, or a quote is never closed).
fn find_tag_end(text: &str, from: usize) -> Option<usize> {
    let bytes = text.as_bytes();
    let mut i = from;
    // A quote starts an attribute value only when the preceding non-whitespace character is `=`.
    let mut value_expected = false;
    while i < bytes.len() {
        match bytes[i] {
            b'>' => return Some(i),
            b'<' => return None,
            quote @ (b'"' | b'\'') if value_expected => {
                i += 1 + text[i + 1..].find(quote as char)?;
                value_expected = false;
            }
            b'=' => value_expected = true,
            c if c.is_ascii_whitespace() => {}
            _ => value_expected = false,
        }
        i += 1;
    }
    None
}

/// Finds the end of a comment (the position after `-->`) starting right after `<!--`. As in HTML5,
/// `<!-->` and `<!--->` close as empty comments. An unclosed comment
/// treats the rest as comment (so nothing leaks into the body mid-stream).
fn comment_end(text: &str, body: usize) -> usize {
    let rest = &text[body..];
    if rest.starts_with('>') {
        return body + 1;
    }
    if rest.starts_with("->") {
        return body + 2;
    }
    match rest.find(COMMENT_CLOSE) {
        Some(end) => body + end + COMMENT_CLOSE.len(),
        None => text.len(),
    }
}

/// Tags interpreted by the inline builder or the block builder (`lib.rs`) other
/// than the [style_kind], [titled_kind], raw element and media tags. `doc/html.md` lists what each does.
const SUPPORTED_TAGS: [&str; 34] = [
    LINK_TAG,
    LINE_BREAK_TAG,
    IMAGE_TAG,
    FONT_TAG,
    QUOTE_TAG,
    ISOLATE_TAG,
    OVERRIDE_TAG,
    WORD_BREAK_TAG,
    "span",
    "p",
    "div",
    "center",
    "h1",
    "h2",
    "h3",
    "h4",
    "h5",
    "h6",
    "hr",
    "details",
    "summary",
    "table",
    "caption",
    "thead",
    "tbody",
    "tfoot",
    "tr",
    "th",
    "td",
    "blockquote",
    "ul",
    "ol",
    "li",
    "pre",
];

/// Whether `<name>` is interpreted. Any other tag is shown as written.
fn is_supported_tag(name: &str) -> bool {
    SUPPORTED_TAGS.contains(&name)
        || RAW_ELEMENT_TAGS.contains(&name)
        || MEDIA_TAGS.contains(&name)
        || MEDIA_CHILD_TAGS.contains(&name)
        || style_kind(name).is_some()
        || titled_kind(name).is_some()
}

/// Reads a tag or comment at the position of `<`. If it can be read, returns (end position, token).
/// For a comment, the token is None.
fn parse_tag(text: &str, lt: usize) -> Option<(usize, Option<Token>)> {
    let bytes = text.as_bytes();
    if text[lt..].starts_with(COMMENT_OPEN) {
        return Some((comment_end(text, lt + COMMENT_OPEN.len()), None));
    }

    let mut i = lt + 1;
    let closing = bytes.get(i) == Some(&b'/');
    if closing {
        i += 1;
    }
    let name_start = i;
    if !bytes.get(i).is_some_and(|c| c.is_ascii_alphabetic()) {
        return None;
    }
    while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'-') {
        i += 1;
    }
    let name = text[name_start..i].to_ascii_lowercase();

    let gt = find_tag_end(text, i)?;
    // Attributes must be empty or start with whitespace (only the `/` of `<br/>` is allowed).
    let rest = &text[i..gt];
    let starts_with_space = rest.chars().next().is_some_and(char::is_whitespace);
    if !rest.is_empty() && !starts_with_space && rest != "/" {
        return None;
    }
    if !is_supported_tag(&name) {
        // Not interpreted: shown as written, like flutter_markdown shows raw HTML.
        return Some((gt + 1, Some(Token::Text(text[lt..=gt].to_string()))));
    }
    let token = if closing {
        Token::Close(name)
    } else {
        Token::Open(name, parse_attributes(rest))
    };
    Some((gt + 1, Some(token)))
}

fn push_text(raw: &str, out: &mut Vec<Token>) {
    if raw.is_empty() {
        return;
    }
    // Normalize source soft breaks before entity decoding. A numeric character
    // reference such as `&#10;` is content and must not be mistaken for a
    // source line break (which would collapse adjacent references).
    let normalized = collapse_line_breaks(raw.to_string());
    out.push(Token::Text(decode_entities(&normalized)));
}

/// Splits a string containing raw HTML into tokens.
pub fn tokenize(text: &str, out: &mut Vec<Token>) {
    let mut position = 0;
    let mut search = 0;
    while let Some(offset) = text[search..].find('<') {
        let lt = search + offset;
        match parse_tag(text, lt) {
            Some((end, token)) => {
                push_text(&text[position..lt], out);
                if let Some(token) = token {
                    out.push(token);
                }
                position = end;
                search = end;
            }
            None => search = lt + 1,
        }
    }
    push_text(&text[position..], out);
}

// ---------------------------------------------------------------------------
// Elements whose content is not read as Markdown (pre / script / style / textarea)
// ---------------------------------------------------------------------------

/// Elements whose content is handled separately without tokenizing.
const RAW_ELEMENT_TAGS: [&str; 4] = ["pre", "script", "style", "textarea"];

/// Elements whose content is dropped (they are neither executed nor applied, so there is no point showing them as body text).
pub const DISCARDED_TAGS: [&str; 2] = ["script", "style"];

/// An element cut out as one chunk from its opening tag to its closing tag.
pub struct RawElement {
    pub tag: &'static str,
    pub attributes: Vec<(String, String)>,
    /// From the end of the opening tag to just before the closing tag.
    pub content: Range<usize>,
    /// From the start of the opening tag to the end of the closing tag.
    pub span: Range<usize>,
}

/// The end position up to the `>` that follows `</name`, and the start position of the closing tag.
fn find_closing_tag(text: &str, from: usize, name: &str) -> Option<(usize, usize)> {
    let lower = text[from..].to_ascii_lowercase();
    let needle = format!("</{name}");
    let mut offset = 0;
    while let Some(found) = lower[offset..].find(&needle) {
        let start = offset + found;
        let after = start + needle.len();
        let boundary = lower.as_bytes().get(after).copied();
        if boundary.is_none_or(|c| c == b'>' || c == b'/' || c.is_ascii_whitespace()) {
            let gt = lower[after..].find('>')?;
            return Some((from + start, from + after + gt + 1));
        }
        offset = after;
    }
    None
}

/// Finds the first [`RawElement`] in `text`.
///
/// When there is no closing tag, the rest is taken as the content only if the element starts at the
/// start of `text` (ignoring whitespace), because a CommonMark HTML block (type 1) continues to the
/// closing tag, or to the end of the document if there is none. One that is not at the start is treated as a normal tag
/// (for example a `<pre>` inside a `<table>`, where the block is cut at a blank line and the content arrives as Markdown).
pub fn find_raw_element(text: &str) -> Option<RawElement> {
    let mut search = 0;
    while let Some(offset) = text[search..].find('<') {
        let lt = search + offset;
        let Some((end, token)) = parse_tag(text, lt) else {
            search = lt + 1;
            continue;
        };
        search = end;
        let Some(Token::Open(name, attributes)) = token else {
            continue;
        };
        let Some(tag) = RAW_ELEMENT_TAGS.iter().find(|tag| **tag == name) else {
            continue;
        };
        match find_closing_tag(text, end, tag) {
            Some((close_start, close_end)) => {
                return Some(RawElement {
                    tag,
                    attributes,
                    content: end..close_start,
                    span: lt..close_end,
                });
            }
            None if text[..lt].trim().is_empty() => {
                return Some(RawElement {
                    tag,
                    attributes,
                    content: end..text.len(),
                    span: lt..text.len(),
                });
            }
            None => {}
        }
    }
    None
}

/// Extracts the code language (`language-x` / `lang-x`) from the `class` attribute.
fn language_from_class(attributes: &[(String, String)]) -> Option<String> {
    attribute(attributes, "class")?
        .split_whitespace()
        .find_map(|name| {
            name.strip_prefix("language-")
                .or_else(|| name.strip_prefix("lang-"))
        })
        .filter(|language| !language.is_empty())
        .map(str::to_string)
}

/// Drops one newline right after the opening tag and one newline at the end.
fn trim_code_newlines(code: &str) -> &str {
    let code = code
        .strip_prefix("\r\n")
        .or_else(|| code.strip_prefix('\n'))
        .unwrap_or(code);
    code.strip_suffix('\n')
        .map(|code| code.strip_suffix('\r').unwrap_or(code))
        .unwrap_or(code)
}

/// Turns the content of `<pre>` into plain code.
///
/// Inner tags are stripped (`<br>` becomes a newline) and entities are restored. One newline right after the opening tag is
/// ignored, as browsers do, and one trailing newline is dropped to match the code block convention.
/// The language is read from `<pre>` or from the `class` of the first inner `<code>`.
pub fn preformatted_code(
    content: &str,
    attributes: &[(String, String)],
) -> (String, Option<String>) {
    let mut language = language_from_class(attributes);
    let mut code = String::with_capacity(content.len());
    let mut position = 0;
    let mut search = 0;
    while let Some(offset) = content[search..].find('<') {
        let lt = search + offset;
        let Some((end, token)) = parse_tag(content, lt) else {
            search = lt + 1;
            continue;
        };
        code.push_str(&content[position..lt]);
        match token {
            Some(Token::Open(name, _)) if name == LINE_BREAK_TAG => code.push('\n'),
            Some(Token::Open(name, attributes)) if name == "code" && language.is_none() => {
                language = language_from_class(&attributes);
            }
            _ => {}
        }
        position = end;
        search = end;
    }
    code.push_str(&content[position..]);
    (
        trim_code_newlines(&decode_entities(&code)).to_string(),
        language,
    )
}

/// The content of `<textarea>`. Tags are the characters as written; only entities are restored.
pub fn textarea_text(content: &str) -> String {
    trim_code_newlines(&decode_entities(content)).to_string()
}

// ---------------------------------------------------------------------------
// Media elements (video / audio / iframe / embed / object)
// ---------------------------------------------------------------------------

/// Elements that become a `media` block, or a fallback link where only inlines fit.
const MEDIA_TAGS: [&str; 5] = ["video", "audio", "iframe", "embed", "object"];

/// Children of `video` / `audio` that are read (`source`) or consumed (`track`) with the element.
const MEDIA_CHILD_TAGS: [&str; 2] = [MEDIA_SOURCE_TAG, "track"];
const MEDIA_SOURCE_TAG: &str = "source";

/// The media element without content or closing tag.
const MEDIA_VOID_TAG: &str = "embed";

/// The element whose URL is in `data` rather than `src`.
const MEDIA_DATA_TAG: &str = "object";

/// The `type` of the custom block. Keep in sync with Dart's `markdownXMediaType`.
const MEDIA_BLOCK_TYPE: &str = "media";

/// URL schemes that are never kept: they run script or carry a whole document inline.
const UNSAFE_URL_SCHEMES: [&str; 3] = ["javascript", "vbscript", "data"];

/// What separates a URL scheme from its authority.
const AUTHORITY_PREFIX: &str = "://";

/// A media element read from its tokens.
pub struct Media {
    /// `kind`, `src`, then the optional attributes, in the order Dart documents them.
    attributes: Vec<(String, String)>,
    src: String,
    title: Option<String>,
}

/// The URL in `value` with surrounding whitespace removed, or None when it is empty or its
/// scheme is unsafe. Tabs and newlines inside the scheme are ignored, as browsers ignore them.
fn usable_url(value: &str) -> Option<String> {
    // Browsers strip leading and trailing C0 controls and spaces.
    let url = value.trim_matches(|c: char| c <= ' ');
    if url.is_empty() {
        return None;
    }
    if let Some(colon) = url.find(':') {
        let scheme: Vec<u8> = url.as_bytes()[..colon]
            .iter()
            .filter(|b| !matches!(b, b'\t' | b'\n' | b'\r'))
            .map(u8::to_ascii_lowercase)
            .collect();
        if UNSAFE_URL_SCHEMES
            .iter()
            .any(|unsafe_scheme| unsafe_scheme.as_bytes() == scheme)
        {
            return None;
        }
    }
    Some(url.to_string())
}

/// Percent-decodes `text`. Returns None when the result is not UTF-8.
fn percent_decode(text: &str) -> Option<String> {
    let bytes = text.as_bytes();
    let hex = |at: usize| bytes.get(at).and_then(|b| (*b as char).to_digit(HEX_RADIX));
    let mut out = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        match (bytes[index], hex(index + 1), hex(index + 2)) {
            (b'%', Some(high), Some(low)) => {
                out.push((high * HEX_RADIX + low) as u8);
                index += 3;
            }
            (byte, _, _) => {
                out.push(byte);
                index += 1;
            }
        }
    }
    String::from_utf8(out).ok()
}

/// The text of the fallback link: the title, else the last path segment of the URL
/// (percent-decoded when that gives UTF-8), else the URL itself.
fn media_label(src: &str, title: Option<&str>) -> String {
    if let Some(title) = title {
        return title.to_string();
    }
    let bytes = src.as_bytes();
    let end = bytes
        .iter()
        .position(|&b| b == b'?' || b == b'#')
        .unwrap_or(bytes.len());
    // The path starts after `scheme://authority`, so a bare host is not taken as a file name.
    let path = match src[..end].find(AUTHORITY_PREFIX) {
        Some(at) => {
            let authority = at + AUTHORITY_PREFIX.len();
            bytes[authority..end]
                .iter()
                .position(|&b| b == b'/')
                .map_or(end, |slash| authority + slash)
        }
        None => 0,
    };
    let name = bytes[path..end]
        .iter()
        .rposition(|&b| b == b'/')
        .map_or(path, |slash| path + slash + 1);
    if name == end {
        return src.to_string();
    }
    let segment = &src[name..end];
    percent_decode(segment).unwrap_or_else(|| segment.to_string())
}

impl Media {
    /// The fallback link: tapping it opens `src`.
    pub fn link(&self) -> Inline {
        Inline::Link {
            href: self.src.clone(),
            title: self.title.clone(),
            children: vec![Inline::Text(media_label(&self.src, self.title.as_deref()))],
        }
    }

    /// The `media` custom block, with the fallback link as its inlines.
    pub fn block(self) -> Block {
        let link = self.link();
        Block::Custom {
            kind: MEDIA_BLOCK_TYPE.to_string(),
            attributes: self.attributes,
            inlines: vec![link],
            blocks: Vec::new(),
        }
    }
}

/// A trimmed, non-empty attribute value.
fn present<'a>(attributes: &'a [(String, String)], name: &str) -> Option<&'a str> {
    attribute(attributes, name)
        .map(str::trim)
        .filter(|value| !value.is_empty())
}

/// Builds the media of the element `tag`. `source` is the first usable `<source>` inside it.
fn media_from(
    tag: &str,
    attributes: &[(String, String)],
    source: Option<(String, Option<String>)>,
) -> Option<Media> {
    let own = attribute(
        attributes,
        if tag == MEDIA_DATA_TAG { "data" } else { "src" },
    )
    .filter(|value| !value.trim().is_empty());
    let (src, source_type) = match own {
        Some(value) => (usable_url(value)?, None),
        None => source?,
    };
    let title = present(attributes, "title").map(str::to_string);
    let mut out = vec![
        ("kind".to_string(), tag.to_string()),
        ("src".to_string(), src.clone()),
    ];
    let media_type = present(attributes, "type")
        .map(str::to_string)
        .or(source_type);
    let poster = (tag == "video")
        .then(|| attribute(attributes, "poster").and_then(usable_url))
        .flatten();
    for (name, value) in [
        ("type", media_type),
        ("poster", poster),
        ("title", title.clone()),
        ("width", present(attributes, "width").map(str::to_string)),
        ("height", present(attributes, "height").map(str::to_string)),
    ] {
        if let Some(value) = value {
            out.push((name.to_string(), value));
        }
    }
    Some(Media {
        attributes: out,
        src,
        title,
    })
}

/// Reads the media element whose opening tag is `tokens[start]`.
///
/// Returns None when that token does not open a media element. Otherwise returns the media
/// (None when it has no usable URL) and the index to continue from. With a media, the element's
/// content is consumed up to its matching closing tag, or to the end of `tokens` when the tag is
/// not closed there. Without one, only the opening tag is consumed, so the fallback content
/// stays (the closing tag and any `<source>` are dropped later).
pub fn read_media(tokens: &[Token], start: usize) -> Option<(Option<Media>, usize)> {
    let Some(Token::Open(tag, attributes)) = tokens.get(start) else {
        return None;
    };
    if !MEDIA_TAGS.contains(&tag.as_str()) {
        return None;
    }
    if tag == MEDIA_VOID_TAG {
        return Some((media_from(tag, attributes, None), start + 1));
    }
    let mut depth = 1;
    let mut end = tokens.len();
    let mut source = None;
    for (index, token) in tokens.iter().enumerate().skip(start + 1) {
        match token {
            Token::Open(name, _) if name == tag => depth += 1,
            Token::Close(name) if name == tag => {
                depth -= 1;
                if depth == 0 {
                    end = index + 1;
                    break;
                }
            }
            Token::Open(name, source_attributes)
                if name == MEDIA_SOURCE_TAG && depth == 1 && source.is_none() =>
            {
                source = attribute(source_attributes, "src")
                    .and_then(usable_url)
                    .map(|src| (src, present(source_attributes, "type").map(str::to_string)));
            }
            _ => {}
        }
    }
    match media_from(tag, attributes, source) {
        Some(media) => Some((Some(media), end)),
        None => Some((None, start + 1)),
    }
}

/// If `tokens` hold one media element and only whitespace around it, returns that media.
/// A paragraph like `<video src="a.mp4"></video>` then becomes a media block, not a link.
pub fn standalone_media(tokens: &[Token]) -> Option<Media> {
    let blank = |token: &Token| match token {
        Token::Text(text) | Token::Markdown(text) => text.trim().is_empty(),
        Token::Node(Inline::SoftBreak) => true,
        _ => false,
    };
    let start = tokens.iter().position(|token| !blank(token))?;
    let (media, end) = read_media(tokens, start)?;
    let media = media?;
    tokens[end..].iter().all(blank).then_some(media)
}

// ---------------------------------------------------------------------------
// Assembling inlines
// ---------------------------------------------------------------------------

struct Frame {
    tag: String,
    attributes: Vec<(String, String)>,
    children: Vec<Inline>,
    /// For `q`: how many `q` elements enclose it (0 for the outermost).
    quote_depth: usize,
}

/// The `dir` attribute, if it is `ltr` or `rtl`.
fn direction(attributes: &[(String, String)]) -> Option<bool> {
    match attribute(attributes, "dir")?
        .trim()
        .to_ascii_lowercase()
        .as_str()
    {
        "ltr" => Some(false),
        "rtl" => Some(true),
        _ => None,
    }
}

/// The text that surrounds the content of `q`, `bdi` and `bdo`, if the tag adds any.
fn surround(frame: &Frame) -> Option<(char, char)> {
    match frame.tag.as_str() {
        QUOTE_TAG => Some(if frame.quote_depth.is_multiple_of(2) {
            OUTER_QUOTE
        } else {
            INNER_QUOTE
        }),
        ISOLATE_TAG if !frame.children.is_empty() => Some((
            match direction(&frame.attributes) {
                Some(false) => LEFT_TO_RIGHT_ISOLATE,
                Some(true) => RIGHT_TO_LEFT_ISOLATE,
                None => FIRST_STRONG_ISOLATE,
            },
            POP_DIRECTIONAL_ISOLATE,
        )),
        OVERRIDE_TAG if !frame.children.is_empty() => direction(&frame.attributes).map(|rtl| {
            (
                if rtl {
                    RIGHT_TO_LEFT_OVERRIDE
                } else {
                    LEFT_TO_RIGHT_OVERRIDE
                },
                POP_DIRECTIONAL_FORMATTING,
            )
        }),
        _ => None,
    }
}

pub fn attribute<'a>(attributes: &'a [(String, String)], name: &str) -> Option<&'a str> {
    attributes
        .iter()
        .find(|(key, _)| key == name)
        .map(|(_, value)| value.as_str())
}

/// Adjacent text is merged. This joins the gaps left by stripping unknown tags.
fn add_inline(target: &mut Vec<Inline>, node: Inline) {
    if let Inline::Text(text) = &node {
        if text.is_empty() {
            return;
        }
        if let Some(Inline::Text(previous)) = target.last_mut() {
            previous.push_str(text);
            return;
        }
    }
    target.push(node);
}

fn close_frame(frame: Frame, parent: &mut Vec<Inline>) {
    let style = parse_inline_style(
        attribute(&frame.attributes, "style"),
        if frame.tag == FONT_TAG {
            attribute(&frame.attributes, "color")
        } else {
            None
        },
    );
    // script / style are dropped together with their content.
    if DISCARDED_TAGS.contains(&frame.tag.as_str()) {
        return;
    }
    let href = attribute(&frame.attributes, "href").map(str::to_string);
    let title = attribute(&frame.attributes, "title").map(str::to_string);

    let surrounding = surround(&frame);
    let content = if let Some(kind) = style_kind(&frame.tag) {
        if frame.children.is_empty() {
            return;
        }
        vec![Inline::Styled(kind, frame.children)]
    } else if let Some(kind) = titled_kind(&frame.tag) {
        if frame.children.is_empty() {
            return;
        }
        vec![Inline::Titled(kind, title, frame.children)]
    } else if let Some((open, close)) = surrounding {
        let mut content = Vec::with_capacity(frame.children.len() + 2);
        add_inline(&mut content, Inline::Text(open.to_string()));
        for child in frame.children {
            add_inline(&mut content, child);
        }
        add_inline(&mut content, Inline::Text(close.to_string()));
        content
    } else if let (LINK_TAG, Some(href)) = (frame.tag.as_str(), href) {
        vec![Inline::Link {
            href,
            title,
            children: frame.children,
        }]
    } else {
        // Tags not in the allowlist are stripped, leaving only their content.
        frame.children
    };

    match style {
        Some(style) if !content.is_empty() => parent.push(Inline::Span(style, content)),
        _ => {
            for child in content {
                add_inline(parent, child);
            }
        }
    }
}

fn image_from_attributes(attributes: &[(String, String)]) -> Option<Inline> {
    let src = attribute(attributes, "src").filter(|src| !src.is_empty())?;
    let number = |name: &str| attribute(attributes, name).and_then(|v| v.parse::<f64>().ok());
    Some(Inline::Image {
        src: src.to_string(),
        alt: attribute(attributes, "alt").map(str::to_string),
        title: attribute(attributes, "title").map(str::to_string),
        width: number("width"),
        height: number("height"),
    })
}

fn trim_edges(inlines: &mut Vec<Inline>) {
    // A soft break at an edge is whitespace, like the space it replaced.
    loop {
        match inlines.first_mut() {
            Some(Inline::SoftBreak) => {
                inlines.remove(0);
            }
            Some(Inline::Text(text)) => {
                let trimmed = text.trim_start();
                if trimmed.is_empty() {
                    inlines.remove(0);
                    continue;
                }
                if trimmed.len() != text.len() {
                    *text = trimmed.to_string();
                }
                break;
            }
            _ => break,
        }
    }
    loop {
        match inlines.last_mut() {
            Some(Inline::SoftBreak) => {
                inlines.pop();
            }
            Some(Inline::Text(text)) => {
                let trimmed = text.trim_end();
                if trimmed.is_empty() {
                    inlines.pop();
                    continue;
                }
                let len = trimmed.len();
                text.truncate(len);
                break;
            }
            _ => break,
        }
    }
}

/// Whether the plain text that follows may start a URL.
///
/// The Dart implementation allows it when the character before the URL is an emphasis marker or `>`, and disallows it when it is code or the
/// closing marker of a link. This reproduces that from the token kind.
fn allows_link_after(node: &Inline) -> bool {
    match node {
        Inline::Styled(StyleKind::Code, _) | Inline::Link { .. } | Inline::Image { .. } => false,
        Inline::Text(text) => text
            .as_bytes()
            .last()
            .is_none_or(|c| matches!(c, b'\n' | b' ' | b'*' | b'_' | b'~' | b'(' | b'>')),
        _ => true,
    }
}

/// The inline tree being assembled.
struct InlineBuilder {
    stack: Vec<Frame>,
    /// Plain text from Markdown that is not yet finalized.
    markdown: String,
    /// Whether a URL may start at the start of the plain text.
    link_allowed: bool,
    autolink: bool,
}

impl InlineBuilder {
    fn top(&mut self) -> &mut Vec<Inline> {
        &mut self
            .stack
            .last_mut()
            .expect("root frame is never popped")
            .children
    }

    /// Finalizes the accumulated plain text, splitting it into links if needed.
    fn flush_markdown(&mut self) {
        if self.markdown.is_empty() {
            return;
        }
        let text = std::mem::take(&mut self.markdown);
        if !self.autolink {
            add_inline(self.top(), Inline::Text(text));
            return;
        }
        let allowed = self.link_allowed;
        let mut nodes = Vec::new();
        autolink(text, allowed, &mut |node| nodes.push(node));
        for node in nodes {
            add_inline(self.top(), node);
        }
    }

    fn close_top(&mut self) {
        let frame = self.stack.pop().expect("caller checked the stack depth");
        close_frame(frame, self.top());
    }

    fn add(&mut self, token: Token) {
        match token {
            Token::Markdown(text) => {
                self.markdown.push_str(&text);
                return;
            }
            Token::Text(text) => {
                self.flush_markdown();
                self.link_allowed = allows_link_after(&Inline::Text(text.clone()));
                add_inline(self.top(), Inline::Text(text));
                return;
            }
            Token::Node(node) => {
                self.flush_markdown();
                self.link_allowed = allows_link_after(&node);
                add_inline(self.top(), node);
                return;
            }
            Token::Open(tag, attributes) => {
                self.flush_markdown();
                if tag == LINE_BREAK_TAG {
                    self.top().push(Inline::LineBreak);
                } else if tag == WORD_BREAK_TAG {
                    add_inline(self.top(), Inline::Text(ZERO_WIDTH_SPACE.to_string()));
                } else if tag == IMAGE_TAG {
                    if let Some(image) = image_from_attributes(&attributes) {
                        self.top().push(image);
                    }
                } else if !VOID_TAGS.contains(&tag.as_str()) {
                    let quote_depth = self
                        .stack
                        .iter()
                        .filter(|frame| frame.tag == QUOTE_TAG)
                        .count();
                    self.stack.push(Frame {
                        tag,
                        attributes,
                        children: Vec::new(),
                        quote_depth,
                    });
                }
            }
            Token::Close(tag) => {
                self.flush_markdown();
                // Ignore a closing tag with no matching opening tag.
                if let Some(index) = self.stack.iter().rposition(|frame| frame.tag == tag) {
                    if index > 0 {
                        while self.stack.len() > index {
                            self.close_top();
                        }
                    }
                }
            }
        }
        // A URL may start right after an HTML tag (right after `>`).
        self.link_allowed = true;
    }
}

/// Turns a token sequence into an inline tree. HTML tags are matched with a stack.
///
/// When `trim` is true, whitespace at both ends is dropped. When `autolink` is true,
/// URLs in the plain text from Markdown are turned into links.
pub fn build_inlines(tokens: Vec<Token>, trim: bool, autolink: bool) -> Vec<Inline> {
    let mut builder = InlineBuilder {
        stack: vec![Frame {
            tag: String::new(),
            attributes: Vec::new(),
            children: Vec::new(),
            quote_depth: 0,
        }],
        markdown: String::new(),
        link_allowed: true,
        autolink,
    };
    let mut tokens = tokens;
    let mut index = 0;
    while index < tokens.len() {
        if let Some((media, next)) = read_media(&tokens, index) {
            // A media element is its fallback link; its content is dropped.
            if let Some(media) = media {
                builder.add(Token::Node(media.link()));
            }
            index = next;
            continue;
        }
        builder.add(std::mem::replace(
            &mut tokens[index],
            Token::Text(String::new()),
        ));
        index += 1;
    }
    builder.flush_markdown();
    // Close unclosed tags at the end.
    while builder.stack.len() > 1 {
        builder.close_top();
    }

    let mut result = builder
        .stack
        .pop()
        .map(|frame| frame.children)
        .unwrap_or_default();
    if trim {
        trim_edges(&mut result);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::{build_inlines, tokenize, Token};
    use crate::ir::{Inline, StyleKind};

    fn html_text(source: &str) -> Vec<Inline> {
        let mut tokens = Vec::<Token>::new();
        tokenize(source, &mut tokens);
        build_inlines(tokens, false, false)
    }

    #[test]
    fn common_named_entities_decode_in_text_and_attributes() {
        let names = "&copy;&reg;&trade;&mdash;&ndash;&hellip;&laquo;&raquo;&ldquo;&rdquo;&lsquo;&rsquo;&times;&divide;&deg;&plusmn;&middot;&bull;&larr;&rarr;&uarr;&darr;&euro;&yen;&pound;&cent;&sect;&para;";
        let decoded = "©®™—–…«»“”‘’×÷°±·•←→↑↓€¥£¢§¶";
        assert_eq!(super::decode_entities(names), decoded);
        assert_eq!(
            super::decode_entities("&unknown; &copy &amp;copy;"),
            "&unknown; &copy &copy;"
        );
        assert!(matches!(
            &html_text(&format!(r#"<img src="x.png" alt="{names}">"#))[..],
            [Inline::Image { alt: Some(alt), .. }] if alt == decoded
        ));
    }

    #[test]
    fn source_soft_breaks_collapse_but_entity_linefeeds_remain_content() {
        let source_break = html_text("foo\nbar");
        assert!(matches!(&source_break[..], [Inline::Text(text)] if text == "foo bar"));

        let blank_line = html_text("foo\n\nbar");
        assert!(matches!(&blank_line[..], [Inline::Text(text)] if text == "foo  bar"));

        let crlf_blank_line = html_text("foo\r\n\r\nbar");
        assert!(matches!(&crlf_blank_line[..], [Inline::Text(text)] if text == "foo  bar"));

        let entity_breaks = html_text("foo&#10;&#10;bar");
        assert!(matches!(&entity_breaks[..], [Inline::Text(text)] if text == "foo\n\nbar"));
    }

    #[test]
    fn empty_comments_are_dropped() {
        for source in ["a<!-->b", "a<!--->b", "a<!-- x -->b", "a<!---->b"] {
            let actual = html_text(source);
            assert!(
                matches!(&actual[..], [Inline::Text(text)] if text == "ab"),
                "{source}"
            );
        }
    }

    #[test]
    fn unterminated_comment_hides_the_rest_of_the_block() {
        let actual = html_text("a<!-- b");
        assert!(matches!(&actual[..], [Inline::Text(text)] if text == "a"));
    }

    #[test]
    fn quoted_attribute_values_may_contain_angle_brackets() {
        let actual = html_text("<span style=\"color:red\" title='a <b> c'>x</span>");
        assert!(matches!(
            &actual[..],
            [Inline::Span(style, children)]
                if style.color == Some(0xffff0000)
                    && matches!(&children[..], [Inline::Text(text)] if text == "x")
        ));
        let multiline =
            html_text("<a foo=\"bar\" bam = 'baz <em>\"</em>'\n_boolean zoop:33=zoop:33 />t");
        assert!(matches!(&multiline[..], [Inline::Text(text)] if text == "t"));
    }

    #[test]
    fn html_fixture_decodes_entities_inside_inline_style_attributes() {
        let actual = html_text("<span style=\"color:&#35;ff0000\">red</span>");
        assert!(matches!(
            &actual[..],
            [Inline::Span(style, children)]
                if style.color == Some(0xffff0000)
                    && matches!(&children[..], [Inline::Text(text)] if text == "red")
        ));
    }

    #[test]
    fn unsupported_tags_are_shown_as_written() {
        for source in [
            "Use List<String> here",
            "a <T> b",
            "x <foo>y</foo> z",
            "<section>a</section>",
            "<custom-card title=\"x &amp; y\">z</custom-card>",
            "<input type=\"checkbox\">",
        ] {
            assert_eq!(text_of(&html_text(source)), source);
        }
    }

    #[test]
    fn supported_tags_without_effect_still_drop_only_the_tag() {
        assert_eq!(text_of(&html_text("<span>a</span> <a>b</a>")), "a b");
    }

    fn text_of(inlines: &[Inline]) -> String {
        let mut out = String::new();
        for inline in inlines {
            match inline {
                Inline::Text(text) => out.push_str(text),
                Inline::Styled(_, children)
                | Inline::Titled(_, _, children)
                | Inline::Span(_, children)
                | Inline::Link { children, .. } => out.push_str(&text_of(children)),
                _ => {}
            }
        }
        out
    }

    #[test]
    fn phrasing_tags_keep_their_own_style_kind() {
        for (tag, kind) in [
            ("cite", StyleKind::Cite),
            ("dfn", StyleKind::Definition),
            ("var", StyleKind::Variable),
            ("samp", StyleKind::Sample),
            ("tt", StyleKind::Teletype),
            ("big", StyleKind::Big),
        ] {
            let actual = html_text(&format!("<{tag}>x</{tag}>"));
            assert!(
                matches!(&actual[..], [Inline::Styled(k, c)]
                    if *k as u8 == kind as u8 && matches!(&c[..], [Inline::Text(t)] if t == "x")),
                "{tag}"
            );
        }
    }

    #[test]
    fn abbr_and_acronym_keep_the_title() {
        let actual = html_text("<abbr title=\"World Health\">WHO</abbr><acronym>NB</acronym>");
        let [Inline::Titled(first, Some(title), _), Inline::Titled(second, None, _)] = &actual[..]
        else {
            panic!("expected two titled inlines");
        };
        assert_eq!(*first as u8, StyleKind::Abbreviation as u8);
        assert_eq!(title, "World Health");
        assert_eq!(*second as u8, StyleKind::Acronym as u8);
    }

    #[test]
    fn q_wraps_content_in_alternating_quotation_marks() {
        assert_eq!(text_of(&html_text("<q>a</q>")), "\u{201C}a\u{201D}");
        assert_eq!(
            text_of(&html_text("<q>a<q>b</q>c</q>")),
            "\u{201C}a\u{2018}b\u{2019}c\u{201D}"
        );
        assert_eq!(
            text_of(&html_text("<q>a<q>b<q>c</q></q></q>")),
            "\u{201C}a\u{2018}b\u{201C}c\u{201D}\u{2019}\u{201D}"
        );
        // Siblings restart at the outer level.
        assert_eq!(
            text_of(&html_text("<q>a</q><q>b</q>")),
            "\u{201C}a\u{201D}\u{201C}b\u{201D}"
        );
    }

    #[test]
    fn unclosed_q_is_closed_with_its_closing_quote() {
        assert_eq!(text_of(&html_text("<q>a")), "\u{201C}a\u{201D}");
        assert_eq!(text_of(&html_text("<q></q>")), "\u{201C}\u{201D}");
    }

    #[test]
    fn bdi_isolates_its_content() {
        assert_eq!(text_of(&html_text("<bdi>x</bdi>")), "\u{2068}x\u{2069}");
        assert_eq!(
            text_of(&html_text("<bdi dir=\"ltr\">x</bdi>")),
            "\u{2066}x\u{2069}"
        );
        assert_eq!(
            text_of(&html_text("<bdi dir=\"RTL\">x</bdi>")),
            "\u{2067}x\u{2069}"
        );
        assert_eq!(
            text_of(&html_text("<bdi dir=\"auto\">x</bdi>")),
            "\u{2068}x\u{2069}"
        );
        assert_eq!(text_of(&html_text("<bdi></bdi>")), "");
    }

    #[test]
    fn bdo_overrides_only_with_a_valid_dir() {
        assert_eq!(
            text_of(&html_text("<bdo dir=\"rtl\">x</bdo>")),
            "\u{202E}x\u{202C}"
        );
        assert_eq!(
            text_of(&html_text("<bdo dir=\"ltr\">x</bdo>")),
            "\u{202D}x\u{202C}"
        );
        assert_eq!(text_of(&html_text("<bdo>x</bdo>")), "x");
        assert_eq!(text_of(&html_text("<bdo dir=\"auto\">x</bdo>")), "x");
    }

    #[test]
    fn wbr_is_a_zero_width_space() {
        assert_eq!(text_of(&html_text("a<wbr>b<wbr/>c")), "a\u{200B}b\u{200B}c");
    }
}
