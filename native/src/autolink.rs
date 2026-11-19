//! Turns bare URLs and email addresses into links (GFM extended autolink).
//!
//! pulldown-cmark does not support this, so it is done here on plain text.
//! Aims for the same results as `AutolinkExtensionSyntax` in Dart's `markdown` package.

use crate::ir::Inline;

const SCHEMES: [&str; 4] = ["https://", "http://", "ftp://", "www."];

/// The scheme added to links that start with `www.` and have no scheme.
const DEFAULT_SCHEME: &str = "http://";
const MAIL_SCHEME: &str = "mailto:";

/// Characters that may come right before a link. A link is not made after any other character.
const VALID_PRECEDING: [u8; 7] = [b'\n', b' ', b'*', b'_', b'~', b'(', b'>'];

/// Trailing punctuation that is not included in the link.
const TRAILING_PUNCTUATION: [u8; 8] = [b'?', b'!', b'.', b',', b':', b'*', b'_', b'~'];

/// Characters left as is without percent-encoding (the same set as Dart's `Uri.encodeFull`,
/// plus `"`, `<`, and `>`, which survive through entities in the Dart implementation).
const UNENCODED: &[u8] = b"-_.!~*'();/?:@&=+$,#\"<>";

fn is_domain_char(c: u8) -> bool {
    c.is_ascii_alphanumeric() || c == b'-'
}

fn is_domain_or_underscore(c: u8) -> bool {
    is_domain_char(c) || c == b'_'
}

fn is_email_local_char(c: u8) -> bool {
    is_domain_or_underscore(c) || c == b'.' || c == b'+'
}

fn scheme_length(bytes: &[u8]) -> Option<usize> {
    SCHEMES
        .iter()
        .find(|scheme| {
            bytes.len() >= scheme.len()
                && bytes[..scheme.len()].eq_ignore_ascii_case(scheme.as_bytes())
        })
        .map(|scheme| scheme.len())
}

/// Checks whether `rest` starts with a valid domain followed by at least one more character.
///
/// A valid domain consists of two or more parts separated by `.`, and the last two
/// cannot contain `_`.
fn starts_with_valid_domain(rest: &[u8]) -> bool {
    let mut position = 0;
    loop {
        let segment_end = position
            + rest[position..]
                .iter()
                .take_while(|c| is_domain_or_underscore(**c))
                .count();
        if segment_end == position || rest.get(segment_end) != Some(&b'.') {
            return false;
        }
        let has_underscore = rest[position..segment_end].contains(&b'_');
        let next = segment_end + 1;
        let next_is_domain = rest.get(next).is_some_and(|c| is_domain_char(*c));
        if !has_underscore && next_is_domain && next + 1 < rest.len() {
            return true;
        }
        position = next;
    }
}

/// Returns the length with the trailing `)` and entity-like `;` removed to the extent they are excluded from the link.
fn consumed_length(link: &str) -> usize {
    let bytes = link.as_bytes();
    let mut excluded = 0;
    if link.ends_with(')') {
        if link.contains('(') {
            let open = bytes.iter().filter(|c| **c == b'(').count();
            let close = bytes.iter().filter(|c| **c == b')').count();
            excluded = close.saturating_sub(open);
        } else {
            excluded = bytes.iter().rev().take_while(|c| **c == b')').count();
        }
    } else if link.ends_with(';') {
        let body = &bytes[..bytes.len() - 1];
        let name = body
            .iter()
            .rev()
            .take_while(|c| c.is_ascii_alphanumeric())
            .count();
        let ampersand = body.len().checked_sub(name + 1);
        if name > 0 && ampersand.is_some_and(|index| body[index] == b'&') {
            excluded = name + 2;
        }
    }
    link.len() - excluded
}

/// Returns the end of the URL starting at `start`. None if it is not a URL.
fn match_link(text: &str, start: usize) -> Option<usize> {
    let bytes = text.as_bytes();
    let scheme = scheme_length(&bytes[start..])?;
    let body = start + scheme;
    let run_end = body
        + text[body..]
            .find(|c: char| c.is_whitespace() || c == '<')
            .unwrap_or(text.len() - body);
    let mut end = run_end;
    while end > body && TRAILING_PUNCTUATION.contains(&bytes[end - 1]) {
        end -= 1;
    }
    if !starts_with_valid_domain(&bytes[body..end]) {
        return None;
    }
    Some(start + consumed_length(&text[start..end]))
}

/// Returns the end of the email address starting at `start`. None if it is not an email address.
fn match_email(text: &str, start: usize) -> Option<usize> {
    let bytes = text.as_bytes();
    let local_end = start
        + bytes[start..]
            .iter()
            .take_while(|c| is_email_local_char(**c))
            .count();
    if local_end == start || bytes.get(local_end) != Some(&b'@') {
        return None;
    }

    // The domain is a sequence of non-empty parts separated by `.`. Cut at the first empty part.
    let domain_start = local_end + 1;
    let mut end = domain_start;
    let mut segments = 0;
    loop {
        let segment_end = end
            + bytes[end..]
                .iter()
                .take_while(|c| is_domain_or_underscore(**c))
                .count();
        if segment_end == end {
            break;
        }
        segments += 1;
        end = segment_end;
        if bytes.get(end) != Some(&b'.') {
            break;
        }
        end += 1;
    }
    // It must end with an alphanumeric character.
    while end > domain_start && !bytes[end - 1].is_ascii_alphanumeric() {
        end -= 1;
    }
    let has_dot = bytes[domain_start..end].contains(&b'.');
    if segments < 2 || !has_dot {
        return None;
    }
    if matches!(bytes.get(end), Some(b'_' | b'-')) {
        return None;
    }
    Some(end)
}

fn encode_full(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for byte in text.bytes() {
        if byte.is_ascii_alphanumeric() || UNENCODED.contains(&byte) {
            out.push(byte as char);
        } else {
            out.push_str(&format!("%{byte:02X}"));
        }
    }
    out
}

fn link(text: &str, destination: &str) -> Inline {
    Inline::Link {
        href: encode_full(destination),
        title: None,
        children: vec![Inline::Text(text.to_string())],
    }
}

/// Turns the URLs and email addresses in `text` into links and passes them to `push` in order.
///
/// `start_allowed` says whether the start of `text` is a position where a URL may begin
/// (true right after an emphasis marker or an HTML tag, false right after code or a link).
pub fn autolink(text: String, start_allowed: bool, push: &mut dyn FnMut(Inline)) {
    let bytes = text.as_bytes();
    let may_contain = bytes.contains(&b'@')
        || text.contains("://")
        || bytes.windows(4).any(|w| w.eq_ignore_ascii_case(b"www."));
    if !may_contain {
        push(Inline::Text(text));
        return;
    }

    let mut flushed = 0;
    let mut position = 0;
    while position < bytes.len() {
        let preceded_ok = if position == 0 {
            start_allowed
        } else {
            VALID_PRECEDING.contains(&bytes[position - 1])
        };
        let found = if preceded_ok && text.is_char_boundary(position) {
            match_link(&text, position).map(|end| (end, false))
        } else {
            None
        }
        .or_else(|| {
            if is_email_local_char(bytes[position]) {
                match_email(&text, position).map(|end| (end, true))
            } else {
                None
            }
        });

        match found {
            Some((end, is_email)) if end > position => {
                if position > flushed {
                    push(Inline::Text(text[flushed..position].to_string()));
                }
                let matched = &text[position..end];
                if is_email {
                    push(link(matched, &format!("{MAIL_SCHEME}{matched}")));
                } else if matched.starts_with('w') {
                    push(link(matched, &format!("{DEFAULT_SCHEME}{matched}")));
                } else {
                    push(link(matched, matched));
                }
                flushed = end;
                position = end;
            }
            _ => position += 1,
        }
    }
    if flushed < text.len() {
        push(Inline::Text(text[flushed..].to_string()));
    }
}
