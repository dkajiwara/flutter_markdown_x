//! The flutter_markdown_x IR and its binary format.
//!
//! Corresponds to `lib/src/ir/nodes.dart` on the Dart side. The binary format is read by
//! `lib/src/parser/native/ir_decoder.dart`, so change both together.
//!
//! Format: a header comes first (the 4-byte magic [`MAGIC`] and the little-endian `u32`
//! IR version [`IR_VERSION`]), followed by the sequence of top-level blocks.
//! Integers are little endian. A string is a `u32` byte length followed by UTF-8.
//! An optional string is preceded by a `u8` presence flag. A sequence is preceded by its `u32` count.
//! Each sequence element occupies at least 1 byte. The decoder uses this to reject, before
//! allocating, a count larger than the remaining bytes as corrupt.
//!
//! See `doc/native-abi.md` for details and the versioning policy.

/// The magic placed at the start of the IR (ASCII `MDXI`).
pub const MAGIC: [u8; 4] = *b"MDXI";

/// The version of the IR binary format. Bump it when the format changes, and keep it in sync with the Dart decoder.
pub const IR_VERSION: u32 = 6;

/// The reason the IR could not be written.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IrError {
    /// A string or sequence length does not fit in a `u32` (4 GiB or more).
    TooLarge,
}

/// The kind of text decoration. Values match the index of Dart's `MdxStyleKind`.
#[derive(Clone, Copy)]
#[repr(u8)]
pub enum StyleKind {
    Strong = 0,
    Emphasis = 1,
    Strikethrough = 2,
    Code = 3,
    Underline = 4,
    Mark = 5,
    Subscript = 6,
    Superscript = 7,
    Keyboard = 8,
    Small = 9,
    Cite = 10,
    Definition = 11,
    Variable = 12,
    Sample = 13,
    Teletype = 14,
    Big = 15,
    Abbreviation = 16,
    Acronym = 17,
}

/// Line alignment. The value is its representation in the binary format.
#[derive(Clone, Copy)]
#[repr(u8)]
pub enum Align {
    None = 0,
    Left = 1,
    Center = 2,
    Right = 3,
}

/// Text appearance read from an HTML `style` attribute and the like. Colors are ARGB.
#[derive(Default)]
pub struct InlineStyle {
    pub color: Option<u32>,
    pub background_color: Option<u32>,
    pub font_size: Option<f64>,
    pub bold: bool,
    pub italic: bool,
    pub underline: bool,
    pub strikethrough: bool,
}

impl InlineStyle {
    pub fn is_empty(&self) -> bool {
        self.color.is_none()
            && self.background_color.is_none()
            && self.font_size.is_none()
            && !self.bold
            && !self.italic
            && !self.underline
            && !self.strikethrough
    }
}

pub enum Inline {
    Text(String),
    LineBreak,
    /// A soft line break (a source newline inside a paragraph).
    SoftBreak,
    Styled(StyleKind, Vec<Inline>),
    /// A decoration that carries a `title` (`abbr` and `acronym`).
    Titled(StyleKind, Option<String>, Vec<Inline>),
    Span(InlineStyle, Vec<Inline>),
    Link {
        href: String,
        title: Option<String>,
        children: Vec<Inline>,
    },
    Image {
        src: String,
        alt: Option<String>,
        title: Option<String>,
        width: Option<f64>,
        height: Option<f64>,
    },
}

/// Upper limit on the number of columns and rows one cell spans. HTML values are clamped to it.
/// Keep it in sync with Dart's `mdxMaxCellSpan`.
pub(crate) const MAX_CELL_SPAN: u32 = 100;

/// A table cell. `colspan` and `rowspan` are between 1 and [`MAX_CELL_SPAN`] inclusive.
pub struct Cell {
    pub inlines: Vec<Inline>,
    pub colspan: u32,
    pub rowspan: u32,
}

impl Cell {
    /// A 1 x 1 cell.
    pub fn new(inlines: Vec<Inline>) -> Self {
        Self {
            inlines,
            colspan: 1,
            rowspan: 1,
        }
    }
}

/// The task list marker (`[ ]`, `[x]`, `[X]`) at the start of a list item.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Task {
    pub checked: bool,
    /// The byte offset of the `[` in the parsed source. The marker spans 3 bytes.
    pub offset: usize,
}

pub struct ListItem {
    pub blocks: Vec<Block>,
    /// Set only for a task list item.
    pub task: Option<Task>,
}

pub enum Block {
    Paragraph(Vec<Inline>, Align),
    Heading(u8, Vec<Inline>, Align),
    CodeBlock {
        code: String,
        language: Option<String>,
        /// The text of the fence info string after the language word, trimmed. None if empty.
        info: Option<String>,
    },
    Blockquote(Vec<Block>),
    List {
        ordered: bool,
        start: u32,
        /// False when any item holds a paragraph block (a loose list).
        tight: bool,
        items: Vec<ListItem>,
    },
    Table {
        alignments: Vec<Align>,
        header: Vec<Cell>,
        rows: Vec<Vec<Cell>>,
    },
    ThematicBreak,
    Details {
        summary: Vec<Inline>,
        blocks: Vec<Block>,
        /// True when the `open` attribute is present.
        open: bool,
    },
    /// A block with a name and string attributes, decoded as Dart's `MdxCustomBlock`.
    /// `inlines` and `blocks` are the fallback rendered when no builder handles it.
    Custom {
        kind: String,
        attributes: Vec<(String, String)>,
        inlines: Vec<Inline>,
        blocks: Vec<Block>,
    },
}

// Block tags.
const BLOCK_PARAGRAPH: u8 = 0;
const BLOCK_HEADING: u8 = 1;
const BLOCK_CODE: u8 = 2;
const BLOCK_QUOTE: u8 = 3;
const BLOCK_LIST: u8 = 4;
const BLOCK_TABLE: u8 = 5;
const BLOCK_RULE: u8 = 6;
const BLOCK_DETAILS: u8 = 7;
const BLOCK_CUSTOM: u8 = 8;

// Inline tags.
const INLINE_TEXT: u8 = 0;
const INLINE_LINE_BREAK: u8 = 1;
const INLINE_STYLED: u8 = 2;
const INLINE_LINK: u8 = 3;
const INLINE_IMAGE: u8 = 4;
const INLINE_SPAN: u8 = 5;
const INLINE_SOFT_BREAK: u8 = 6;
const INLINE_TITLED: u8 = 7;

// Inline style flags. A color is meaningful only when its flag is set.
const STYLE_HAS_COLOR: u8 = 1 << 0;
const STYLE_HAS_BACKGROUND: u8 = 1 << 1;
const STYLE_BOLD: u8 = 1 << 2;
const STYLE_ITALIC: u8 = 1 << 3;
const STYLE_UNDERLINE: u8 = 1 << 4;
const STYLE_STRIKETHROUGH: u8 = 1 << 5;

// Task list item state.
const CHECKED_NONE: u8 = 0;
const CHECKED_FALSE: u8 = 1;
const CHECKED_TRUE: u8 = 2;

/// Writes the IR out in the binary format.
///
/// The header is written on creation. If a length does not fit in a `u32`, writing continues but
/// the result is discarded, and [`Writer::finish`] returns [`IrError::TooLarge`].
pub struct Writer {
    bytes: Vec<u8>,
    overflowed: bool,
}

impl Writer {
    pub fn with_capacity(capacity: usize) -> Self {
        let mut bytes = Vec::with_capacity(capacity.saturating_add(MAGIC.len() + 4));
        bytes.extend_from_slice(&MAGIC);
        bytes.extend_from_slice(&IR_VERSION.to_le_bytes());
        Self {
            bytes,
            overflowed: false,
        }
    }

    pub fn finish(self) -> Result<Vec<u8>, IrError> {
        if self.overflowed {
            Err(IrError::TooLarge)
        } else {
            Ok(self.bytes)
        }
    }

    fn u8(&mut self, value: u8) {
        self.bytes.push(value);
    }

    fn u32(&mut self, value: u32) {
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }

    fn len(&mut self, value: usize) {
        match u32::try_from(value) {
            Ok(value) => self.u32(value),
            Err(_) => {
                // Do not panic; report it as TooLarge from finish.
                self.overflowed = true;
                self.u32(0);
            }
        }
    }

    fn string(&mut self, value: &str) {
        self.len(value.len());
        self.bytes.extend_from_slice(value.as_bytes());
    }

    fn optional_string(&mut self, value: &Option<String>) {
        match value {
            Some(value) => {
                self.u8(1);
                self.string(value);
            }
            None => self.u8(0),
        }
    }

    /// An omitted number is represented as NaN.
    fn optional_f64(&mut self, value: Option<f64>) {
        self.bytes
            .extend_from_slice(&value.unwrap_or(f64::NAN).to_le_bytes());
    }

    pub fn blocks(&mut self, blocks: &[Block]) {
        self.len(blocks.len());
        for block in blocks {
            self.block(block);
        }
    }

    fn block(&mut self, block: &Block) {
        match block {
            Block::Paragraph(inlines, align) => {
                self.u8(BLOCK_PARAGRAPH);
                self.u8(*align as u8);
                self.inlines(inlines);
            }
            Block::Heading(level, inlines, align) => {
                self.u8(BLOCK_HEADING);
                self.u8(*level);
                self.u8(*align as u8);
                self.inlines(inlines);
            }
            Block::CodeBlock {
                code,
                language,
                info,
            } => {
                self.u8(BLOCK_CODE);
                self.string(code);
                self.optional_string(language);
                self.optional_string(info);
            }
            Block::Blockquote(blocks) => {
                self.u8(BLOCK_QUOTE);
                self.blocks(blocks);
            }
            Block::List {
                ordered,
                start,
                tight,
                items,
            } => {
                self.u8(BLOCK_LIST);
                self.u8(u8::from(*ordered));
                self.u32(*start);
                self.u8(u8::from(*tight));
                self.len(items.len());
                for item in items {
                    match item.task {
                        None => self.u8(CHECKED_NONE),
                        Some(task) => {
                            self.u8(if task.checked {
                                CHECKED_TRUE
                            } else {
                                CHECKED_FALSE
                            });
                            self.len(task.offset);
                        }
                    }
                    self.blocks(&item.blocks);
                }
            }
            Block::Table {
                alignments,
                header,
                rows,
            } => {
                self.u8(BLOCK_TABLE);
                self.len(alignments.len());
                for align in alignments {
                    self.u8(*align as u8);
                }
                self.cells(header);
                self.len(rows.len());
                for row in rows {
                    self.cells(row);
                }
            }
            Block::ThematicBreak => self.u8(BLOCK_RULE),
            Block::Details {
                summary,
                blocks,
                open,
            } => {
                self.u8(BLOCK_DETAILS);
                self.u8(u8::from(*open));
                self.inlines(summary);
                self.blocks(blocks);
            }
            Block::Custom {
                kind,
                attributes,
                inlines,
                blocks,
            } => {
                self.u8(BLOCK_CUSTOM);
                self.string(kind);
                self.len(attributes.len());
                for (key, value) in attributes {
                    self.string(key);
                    self.string(value);
                }
                self.inlines(inlines);
                self.blocks(blocks);
            }
        }
    }

    fn cells(&mut self, cells: &[Cell]) {
        self.len(cells.len());
        for cell in cells {
            self.u32(cell.colspan);
            self.u32(cell.rowspan);
            self.inlines(&cell.inlines);
        }
    }

    fn inlines(&mut self, inlines: &[Inline]) {
        self.len(inlines.len());
        for inline in inlines {
            self.inline(inline);
        }
    }

    fn inline(&mut self, inline: &Inline) {
        match inline {
            Inline::Text(text) => {
                self.u8(INLINE_TEXT);
                self.string(text);
            }
            Inline::LineBreak => self.u8(INLINE_LINE_BREAK),
            Inline::SoftBreak => self.u8(INLINE_SOFT_BREAK),
            Inline::Styled(kind, children) => {
                self.u8(INLINE_STYLED);
                self.u8(*kind as u8);
                self.inlines(children);
            }
            Inline::Titled(kind, title, children) => {
                self.u8(INLINE_TITLED);
                self.u8(*kind as u8);
                self.optional_string(title);
                self.inlines(children);
            }
            Inline::Span(style, children) => {
                self.u8(INLINE_SPAN);
                let mut flags = 0;
                for (enabled, flag) in [
                    (style.color.is_some(), STYLE_HAS_COLOR),
                    (style.background_color.is_some(), STYLE_HAS_BACKGROUND),
                    (style.bold, STYLE_BOLD),
                    (style.italic, STYLE_ITALIC),
                    (style.underline, STYLE_UNDERLINE),
                    (style.strikethrough, STYLE_STRIKETHROUGH),
                ] {
                    if enabled {
                        flags |= flag;
                    }
                }
                self.u8(flags);
                self.u32(style.color.unwrap_or(0));
                self.u32(style.background_color.unwrap_or(0));
                self.optional_f64(style.font_size);
                self.inlines(children);
            }
            Inline::Link {
                href,
                title,
                children,
            } => {
                self.u8(INLINE_LINK);
                self.string(href);
                self.optional_string(title);
                self.inlines(children);
            }
            Inline::Image {
                src,
                alt,
                title,
                width,
                height,
            } => {
                self.u8(INLINE_IMAGE);
                self.string(src);
                self.optional_string(alt);
                self.optional_string(title);
                self.optional_f64(*width);
                self.optional_f64(*height);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn header_is_magic_and_little_endian_version() {
        let bytes = Writer::with_capacity(0).finish().unwrap();
        assert_eq!(bytes, [b'M', b'D', b'X', b'I', 6, 0, 0, 0]);
    }

    #[test]
    fn custom_is_tag_8_with_type_attributes_inlines_and_blocks() {
        let mut writer = Writer::with_capacity(0);
        writer.blocks(&[Block::Custom {
            kind: "m".to_string(),
            attributes: vec![("k".to_string(), "v".to_string())],
            inlines: vec![Inline::Text("t".to_string())],
            blocks: vec![Block::ThematicBreak],
        }]);
        let bytes = writer.finish().unwrap();
        assert_eq!(BLOCK_CUSTOM, 8);
        // After header (8) + block count (4).
        assert_eq!(
            &bytes[12..],
            [
                BLOCK_CUSTOM,
                1,
                0,
                0,
                0,
                b'm', // type
                1,
                0,
                0,
                0, // attribute count
                1,
                0,
                0,
                0,
                b'k',
                1,
                0,
                0,
                0,
                b'v', // key, value
                1,
                0,
                0,
                0,
                INLINE_TEXT,
                1,
                0,
                0,
                0,
                b't', // inlines
                1,
                0,
                0,
                0,
                BLOCK_RULE, // blocks
            ]
        );
    }

    #[test]
    fn details_writes_the_open_flag_before_the_summary() {
        for (open, flag) in [(false, 0), (true, 1)] {
            let mut writer = Writer::with_capacity(0);
            writer.blocks(&[Block::Details {
                summary: Vec::new(),
                blocks: Vec::new(),
                open,
            }]);
            let bytes = writer.finish().unwrap();
            // `open` follows header (8) + block count (4) + tag (1).
            assert_eq!(bytes[12], BLOCK_DETAILS);
            assert_eq!(bytes[13], flag);
            assert_eq!(bytes.len(), 14 + 8);
        }
    }

    #[test]
    fn table_cell_writes_colspan_and_rowspan_before_its_inlines() {
        let mut writer = Writer::with_capacity(0);
        writer.blocks(&[Block::Table {
            alignments: vec![Align::None],
            header: vec![Cell {
                inlines: Vec::new(),
                colspan: 2,
                rowspan: 3,
            }],
            rows: Vec::new(),
        }]);
        let bytes = writer.finish().unwrap();
        // header (8) + block count (4) + tag (1) + column count (4) + align (1) + header cell count (4)
        let at = 8 + 4 + 1 + 4 + 1 + 4;
        assert_eq!(&bytes[at..at + 4], 2u32.to_le_bytes());
        assert_eq!(&bytes[at + 4..at + 8], 3u32.to_le_bytes());
        assert_eq!(&bytes[at + 8..at + 12], 0u32.to_le_bytes());
    }

    #[cfg(target_pointer_width = "64")]
    #[test]
    fn length_beyond_u32_is_too_large_not_a_panic() {
        let mut writer = Writer::with_capacity(0);
        writer.len(u32::MAX as usize + 1);
        assert_eq!(writer.finish(), Err(IrError::TooLarge));
    }

    #[test]
    fn length_at_u32_max_is_accepted() {
        let mut writer = Writer::with_capacity(0);
        writer.len(u32::MAX as usize);
        assert!(writer.finish().is_ok());
    }

    #[test]
    fn titled_is_tag_7_with_kind_title_and_children() {
        let mut writer = Writer::with_capacity(0);
        writer.blocks(&[Block::Paragraph(
            vec![Inline::Titled(
                StyleKind::Abbreviation,
                Some("t".to_string()),
                Vec::new(),
            )],
            Align::None,
        )]);
        let bytes = writer.finish().unwrap();
        let at = bytes.len() - 12;
        assert_eq!(
            &bytes[at..],
            [INLINE_TITLED, 16, 1, 1, 0, 0, 0, b't', 0, 0, 0, 0]
        );
        assert_eq!(INLINE_TITLED, 7);
    }

    #[test]
    fn soft_break_is_tag_6_without_payload() {
        let mut writer = Writer::with_capacity(0);
        writer.blocks(&[Block::Paragraph(vec![Inline::SoftBreak], Align::None)]);
        let bytes = writer.finish().unwrap();
        // header (8) + block count (4) + tag (1) + align (1) + inline count (4)
        let at = 8 + 4 + 1 + 1 + 4;
        assert_eq!(&bytes[at..], [INLINE_SOFT_BREAK]);
        assert_eq!(INLINE_SOFT_BREAK, 6);
    }

    #[test]
    fn list_writes_tight_after_start() {
        for (tight, flag) in [(false, 0), (true, 1)] {
            let mut writer = Writer::with_capacity(0);
            writer.blocks(&[Block::List {
                ordered: true,
                start: 7,
                tight,
                items: Vec::new(),
            }]);
            let bytes = writer.finish().unwrap();
            // header (8) + block count (4) + tag (1) + ordered (1) + start (4)
            let at = 8 + 4 + 1 + 1 + 4;
            assert_eq!(bytes[at], flag);
            assert_eq!(&bytes[at + 1..], 0u32.to_le_bytes());
        }
    }

    #[test]
    fn code_block_writes_info_after_language() {
        let mut writer = Writer::with_capacity(0);
        writer.blocks(&[Block::CodeBlock {
            code: String::new(),
            language: None,
            info: Some("x".to_string()),
        }]);
        let bytes = writer.finish().unwrap();
        // header (8) + block count (4) + tag (1) + code (4) + language presence (1)
        let at = 8 + 4 + 1 + 4 + 1;
        assert_eq!(&bytes[at..], [1, 1, 0, 0, 0, b'x']);
    }
}
