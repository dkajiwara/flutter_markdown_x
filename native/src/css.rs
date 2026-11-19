//! Reads only the supported declarations from an HTML `style` attribute.
//!
//! The supported declarations are documented in `doc/html.md`.

use crate::ir::InlineStyle;

const OPAQUE_ALPHA: u32 = 0xFF00_0000;
const HEX_RADIX: u32 = 16;
const MAX_CHANNEL: u32 = 255;
const PERCENT: f64 = 100.0;

/// A numeric `font-weight` at or above this is treated as bold.
const BOLD_WEIGHT_THRESHOLD: u32 = 600;

fn named_color(name: &str) -> Option<u32> {
    Some(match name {
        "black" => 0xFF00_0000,
        "silver" => 0xFFC0_C0C0,
        "gray" | "grey" => 0xFF80_8080,
        "white" => 0xFFFF_FFFF,
        "maroon" => 0xFF80_0000,
        "red" => 0xFFFF_0000,
        "purple" => 0xFF80_0080,
        "fuchsia" | "magenta" => 0xFFFF_00FF,
        "green" => 0xFF00_8000,
        "lime" => 0xFF00_FF00,
        "olive" => 0xFF80_8000,
        "yellow" => 0xFFFF_FF00,
        "navy" => 0xFF00_0080,
        "blue" => 0xFF00_00FF,
        "teal" => 0xFF00_8080,
        "aqua" | "cyan" => 0xFF00_FFFF,
        "orange" => 0xFFFF_A500,
        "pink" => 0xFFFF_C0CB,
        "brown" => 0xFFA5_2A2A,
        "gold" => 0xFFFF_D700,
        "transparent" => 0x0000_0000,
        _ => return None,
    })
}

fn parse_hex_color(hex: &str) -> Option<u32> {
    if !hex.bytes().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    // Expand the short forms (#rgb, #rgba) by repeating each digit twice.
    let expanded: String = match hex.len() {
        3 | 4 => hex.chars().flat_map(|digit| [digit, digit]).collect(),
        6 | 8 => hex.to_string(),
        _ => return None,
    };
    let value = u32::from_str_radix(&expanded, HEX_RADIX).ok()?;
    if expanded.len() == 6 {
        return Some(OPAQUE_ALPHA | value);
    }
    // CSS is #rrggbbaa, while ARGB has alpha first.
    Some(((value & MAX_CHANNEL) << 24) | (value >> 8))
}

fn parse_channel(text: &str) -> Option<u32> {
    let valid = (1..=3).contains(&text.len()) && text.bytes().all(|c| c.is_ascii_digit());
    if !valid {
        return None;
    }
    text.parse::<u32>().ok().map(|value| value.min(MAX_CHANNEL))
}

fn parse_alpha(text: &str) -> Option<u32> {
    let (number, is_percent) = match text.strip_suffix('%') {
        Some(number) => (number, true),
        None => (text, false),
    };
    let valid = !number.is_empty() && number.bytes().all(|c| c.is_ascii_digit() || c == b'.');
    if !valid {
        return None;
    }
    let value = number.parse::<f64>().ok()?;
    let ratio = if is_percent { value / PERCENT } else { value };
    Some((ratio.clamp(0.0, 1.0) * f64::from(MAX_CHANNEL)).round() as u32)
}

fn parse_rgb(text: &str) -> Option<u32> {
    let inner = text
        .strip_prefix("rgba(")
        .or_else(|| text.strip_prefix("rgb("))?
        .strip_suffix(')')?;
    let parts: Vec<&str> = inner
        .split(|c: char| c == ',' || c == '/' || c.is_whitespace())
        .filter(|part| !part.is_empty())
        .collect();
    if parts.len() != 3 && parts.len() != 4 {
        return None;
    }
    let red = parse_channel(parts[0])?;
    let green = parse_channel(parts[1])?;
    let blue = parse_channel(parts[2])?;
    let alpha = match parts.get(3) {
        Some(alpha) => parse_alpha(alpha)?,
        None => MAX_CHANNEL,
    };
    Some((alpha << 24) | (red << 16) | (green << 8) | blue)
}

/// Converts a CSS color to an ARGB integer. None if it cannot be interpreted.
pub fn parse_css_color(value: &str) -> Option<u32> {
    let text = value.trim().to_ascii_lowercase();
    if text.is_empty() {
        return None;
    }
    if let Some(hex) = text.strip_prefix('#') {
        return parse_hex_color(hex);
    }
    named_color(&text).or_else(|| parse_rgb(&text))
}

fn parse_pixels(value: &str) -> Option<f64> {
    let number = value.strip_suffix("px")?;
    let dots = number.bytes().filter(|c| *c == b'.').count();
    let valid = number.bytes().all(|c| c.is_ascii_digit() || c == b'.')
        && number.bytes().last().is_some_and(|c| c.is_ascii_digit())
        && dots <= 1;
    if !valid {
        return None;
    }
    number.parse::<f64>().ok()
}

/// Reads the text appearance from a `style` attribute value and a `<font color>` value.
/// None if nothing could be read.
pub fn parse_inline_style(css: Option<&str>, font_color: Option<&str>) -> Option<InlineStyle> {
    if css.is_none() && font_color.is_none() {
        return None;
    }
    let mut style = InlineStyle {
        color: font_color.and_then(parse_css_color),
        ..InlineStyle::default()
    };

    for declaration in css.unwrap_or("").split(';') {
        let Some((property, value)) = declaration.split_once(':') else {
            continue;
        };
        let property = property.trim().to_ascii_lowercase();
        let value = value.trim().to_ascii_lowercase();
        match property.as_str() {
            "color" => style.color = parse_css_color(&value).or(style.color),
            "background" | "background-color" => {
                style.background_color = parse_css_color(&value).or(style.background_color);
            }
            "font-size" => {
                if let Some(size) = parse_pixels(&value) {
                    style.font_size = Some(size);
                }
            }
            "font-weight" => {
                let numeric_bold = value.bytes().all(|c| c.is_ascii_digit())
                    && value
                        .parse::<u32>()
                        .is_ok_and(|weight| weight >= BOLD_WEIGHT_THRESHOLD);
                style.bold = value == "bold" || value == "bolder" || numeric_bold;
            }
            "font-style" => style.italic = value == "italic" || value == "oblique",
            "text-decoration" | "text-decoration-line" => {
                style.underline = value.contains("underline");
                style.strikethrough = value.contains("line-through");
            }
            _ => {}
        }
    }

    if style.is_empty() {
        None
    } else {
        Some(style)
    }
}
