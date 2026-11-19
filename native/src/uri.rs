//! URI destination encoding compatible with `markdown`'s
//! `normalizeLinkDestination` for Markdown links and images.

/// Characters left unescaped by Dart's `Uri.encodeFull`.
const URI_RESERVED: &[u8] = b"-_.!~*'();/?:@&=+$,#";

fn is_hex(byte: u8) -> bool {
    byte.is_ascii_hexdigit()
}

/// Encode a Markdown link or image destination like `markdown`'s
/// `normalizeLinkDestination`.
///
/// UTF-8 bytes outside Dart's `Uri.encodeFull` character set are percent
/// encoded with uppercase hex digits. Existing valid `%HH` escapes are kept
/// verbatim, as `normalizeLinkDestination` explicitly splits them out before
/// calling `Uri.encodeFull` on the remaining text. A malformed percent sign
/// is encoded as `%25`.
pub fn encode_full(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut encoded = String::with_capacity(input.len());
    let mut index = 0;

    while index < bytes.len() {
        let byte = bytes[index];

        if byte == b'%'
            && index + 2 < bytes.len()
            && is_hex(bytes[index + 1])
            && is_hex(bytes[index + 2])
        {
            encoded.push('%');
            encoded.push(bytes[index + 1] as char);
            encoded.push(bytes[index + 2] as char);
            index += 3;
            continue;
        }

        if byte.is_ascii_alphanumeric() || URI_RESERVED.contains(&byte) {
            encoded.push(byte as char);
        } else {
            encoded.push('%');
            encoded.push(hex_digit(byte >> 4));
            encoded.push(hex_digit(byte & 0x0f));
        }
        index += 1;
    }

    encoded
}

fn hex_digit(value: u8) -> char {
    match value {
        0..=9 => (b'0' + value) as char,
        _ => (b'A' + value - 10) as char,
    }
}

#[cfg(test)]
mod tests {
    use super::encode_full;

    #[test]
    fn preserves_dart_encode_full_uri_reserved_characters() {
        let reserved = "-_.!~*'();/?:@&=+$,#";
        assert_eq!(encode_full(reserved), reserved);
    }

    #[test]
    fn percent_encodes_utf8_bytes() {
        assert_eq!(encode_full("/föö"), "/f%C3%B6%C3%B6");
        assert_eq!(encode_full("a b"), "a%20b");
    }

    #[test]
    fn preserves_existing_percent_escapes_without_changing_case() {
        assert_eq!(encode_full("a%2Fb%2f%C3%B6"), "a%2Fb%2f%C3%B6");
    }

    #[test]
    fn escapes_percent_that_does_not_begin_a_hex_escape() {
        assert_eq!(encode_full("100% done%2"), "100%25%20done%252");
    }
}
