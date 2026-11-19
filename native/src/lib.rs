//! Converts Markdown to the flutter_markdown_x IR and exposes it through a C ABI.
//!
//! Parsing is left to pulldown-cmark, and the IR is assembled in a single pass from its event stream.
//! This is the package's only parser; Dart decodes the IR in `lib/src/parser/native/ir_decoder.dart`.

mod autolink;
mod css;
mod html;
pub mod ir;
mod uri;

use html::{
    attribute, build_inlines, find_raw_element, preformatted_code, read_media, standalone_media,
    textarea_text, tokenize, Media, RawElement, Token,
};
use ir::{Align, Block, Cell, Inline, ListItem, StyleKind, Task, Writer, MAX_CELL_SPAN};
use pulldown_cmark::{Alignment, CodeBlockKind, Event, LinkType, OffsetIter, Options, Parser, Tag};
use std::ops::Range;

const DETAILS_TAG: &str = "details";
const SUMMARY_TAG: &str = "summary";
const TABLE_TAG: &str = "table";
const TABLE_CAPTION_TAG: &str = "caption";
const TABLE_ROW_TAG: &str = "tr";
const TABLE_HEADER_CELL_TAG: &str = "th";
const TABLE_CELL_TAG: &str = "td";
const TABLE_HEAD_TAG: &str = "thead";
const TABLE_SECTION_TAGS: [&str; 3] = [TABLE_HEAD_TAG, "tbody", "tfoot"];
const CENTER_TAG: &str = "center";
const RULE_TAG: &str = "hr";

/// HTML tags that pass the `align` attribute on to their inner blocks.
const ALIGN_CONTAINER_TAGS: [&str; 3] = ["p", "div", CENTER_TAG];

/// The default start number of a list.
const DEFAULT_LIST_START: u32 = 1;

/// The prefix added to the link target of a footnote reference.
const FOOTNOTE_HREF_PREFIX: &str = "#fn-";

/// Parses `source` and returns the sequence of top-level blocks.
pub fn parse(source: &str) -> Vec<Block> {
    let mut options = Options::empty();
    options.insert(Options::ENABLE_TABLES);
    options.insert(Options::ENABLE_STRIKETHROUGH);
    options.insert(Options::ENABLE_TASKLISTS);
    options.insert(Options::ENABLE_FOOTNOTES);
    let mut converter = Converter {
        source,
        events: Parser::new_ext(source, options).into_offset_iter(),
        last_range: 0..0,
        link_depth: 0,
        footnote_labels: Vec::new(),
        footnote_definitions: Vec::new(),
        task_marker: None,
    };
    let (mut blocks, _) = converter.blocks();
    converter.append_footnotes(&mut blocks);
    blocks
}

/// Parses `source` and returns the IR in the binary format with a header.
///
/// A document so large that the IR length does not fit in a `u32` gives [`ir::IrError::TooLarge`].
pub fn parse_to_bytes(source: &str) -> Result<Vec<u8>, ir::IrError> {
    let blocks = parse(source);
    let mut writer = Writer::with_capacity(source.len() * 2);
    writer.blocks(&blocks);
    writer.finish()
}

fn align_from_value(value: Option<&str>) -> Option<Align> {
    match value?.trim().to_ascii_lowercase().as_str() {
        "left" => Some(Align::Left),
        "center" => Some(Align::Center),
        "right" => Some(Align::Right),
        _ => None,
    }
}

/// If this is an HTML heading tag, returns its level.
fn html_heading_level(tag: &str) -> Option<u8> {
    match tag.as_bytes() {
        [b'h', digit @ b'1'..=b'6'] => Some(digit - b'0'),
        _ => None,
    }
}

enum HtmlContainer {
    Details {
        summary: Vec<Inline>,
        open: bool,
    },
    Quote,
    List {
        start: Option<u32>,
        items: Vec<ListItem>,
    },
    Item,
}

impl HtmlContainer {
    fn tag(&self) -> &'static str {
        match self {
            Self::Details { .. } => DETAILS_TAG,
            Self::Quote => "blockquote",
            Self::List { start: Some(_), .. } => "ol",
            Self::List { start: None, .. } => "ul",
            Self::Item => "li",
        }
    }
}

struct HtmlFrame {
    kind: HtmlContainer,
    blocks: Vec<Block>,
}

fn add_html_list_item(items: &mut Vec<ListItem>, blocks: Vec<Block>) {
    items.push(ListItem { blocks, task: None });
}

/// A closed cell.
struct HtmlCell {
    inlines: Vec<Inline>,
    is_header: bool,
    align: Option<Align>,
    colspan: u32,
    rowspan: u32,
}

/// The attributes of an open cell.
struct OpenCell {
    is_header: bool,
    align: Option<Align>,
    colspan: u32,
    rowspan: u32,
}

/// An HTML `<table>` being assembled.
#[derive(Default)]
struct HtmlTable {
    rows: Vec<Vec<HtmlCell>>,
    open_cell: Option<OpenCell>,
    caption: Vec<Inline>,
    caption_open: bool,
    /// Inside a `<thead>`. Cells inside are treated as headers even if they are `<td>`.
    in_head: bool,
}

/// The value of `colspan` / `rowspan`. A non-number or a value of 0 or less becomes 1, and a value above the limit is clamped to the limit.
/// (`rowspan="0"` means "to the last row" in HTML, but it is treated as 1 here.)
fn span_from_value(value: Option<&str>) -> u32 {
    value
        .and_then(|value| value.trim().parse::<u32>().ok())
        .map_or(1, |span| span.clamp(1, MAX_CELL_SPAN))
}

impl HtmlTable {
    /// None if there are no columns.
    ///
    /// Cell placement follows the same rules as HTML. Going left to right, a cell goes in the first column
    /// not blocked by a `rowspan` from an upper row. The column count is the maximum of the occupied widths.
    fn build(self) -> Option<Block> {
        let mut all: Vec<Vec<HtmlCell>> = self
            .rows
            .into_iter()
            .filter(|row| !row.is_empty())
            .collect();
        if all.is_empty() {
            return None;
        }
        let row_count = all.len();
        let mut occupied: Vec<Vec<bool>> = vec![Vec::new(); row_count];
        let mut first_row_starts = Vec::new();
        for (r, row) in all.iter_mut().enumerate() {
            let mut column = 0;
            for cell in row.iter_mut() {
                while occupied[r].get(column) == Some(&true) {
                    column += 1;
                }
                // A rowspan that goes past the bottom of the table is clamped to the remaining row count.
                cell.rowspan = cell.rowspan.min((row_count - r) as u32);
                for covered in occupied.iter_mut().skip(r).take(cell.rowspan as usize) {
                    let end = column + cell.colspan as usize;
                    if covered.len() < end {
                        covered.resize(end, false);
                    }
                    covered[column..end].fill(true);
                }
                if r == 0 {
                    first_row_starts.push(column);
                }
                column += cell.colspan as usize;
            }
        }
        let column_count = occupied.iter().map(Vec::len).max().unwrap_or(0);
        if column_count == 0 {
            return None;
        }
        let mut alignments = vec![Align::None; column_count];
        for (cell, start) in all[0].iter().zip(&first_row_starts) {
            if let Some(align) = cell.align {
                alignments[*start] = align;
            }
        }
        let has_header = all[0].iter().all(|cell| cell.is_header);
        let to_cell = |cell: HtmlCell| Cell {
            inlines: cell.inlines,
            colspan: cell.colspan,
            rowspan: cell.rowspan,
        };
        let header = if has_header {
            all.remove(0).into_iter().map(to_cell).collect()
        } else {
            Vec::new()
        };
        Some(Block::Table {
            alignments,
            header,
            rows: all
                .into_iter()
                .map(|row| row.into_iter().map(to_cell).collect())
                .collect(),
        })
    }
}

/// Assembles the blocks inside one container (the document, a blockquote, or a list item).
///
/// An HTML block containing a blank line arrives split into several events (the opening and
/// closing tags of `<details>` become separate blocks), so state is kept across blocks.
#[derive(Default)]
struct BlockBuilder {
    root: Vec<Block>,
    containers: Vec<HtmlFrame>,
    pending: Vec<Token>,
    /// The align of the open `<p>`, `<div>`, and `<center>`.
    aligns: Vec<Option<Align>>,
    /// The level and align of the open HTML heading tag.
    heading: Option<(u8, Option<Align>)>,
    table: Option<HtmlTable>,
}

impl BlockBuilder {
    fn current(&mut self) -> &mut Vec<Block> {
        match self.containers.last_mut() {
            Some(frame) => &mut frame.blocks,
            None => &mut self.root,
        }
    }

    fn align(&self) -> Align {
        self.aligns
            .iter()
            .rev()
            .find_map(|align| *align)
            .unwrap_or(Align::None)
    }

    fn table_text_open(&self) -> bool {
        self.table
            .as_ref()
            .is_some_and(|table| table.open_cell.is_some() || table.caption_open)
    }

    fn push(&mut self, block: Block) {
        self.flush_pending();
        self.current().push(block);
    }

    fn take_inlines(&mut self) -> Vec<Inline> {
        build_inlines(std::mem::take(&mut self.pending), true, true)
    }

    fn flush_pending(&mut self) {
        if self.pending.is_empty() {
            return;
        }
        if let Some(media) = standalone_media(&self.pending) {
            self.pending.clear();
            self.current().push(media.block());
            return;
        }
        let inlines = self.take_inlines();
        if !inlines.is_empty() {
            let align = self.align();
            self.current().push(Block::Paragraph(inlines, align));
        }
    }

    /// Cells and captions hold only inlines, so inner blocks are flattened.
    fn add_table_text(&mut self, tokens: Vec<Token>) {
        // Whitespace-only text, such as a newline right after an opening tag, does not count as content.
        let blank = self.pending.iter().all(|token| match token {
            Token::Text(text) | Token::Markdown(text) => text.trim().is_empty(),
            Token::Node(Inline::SoftBreak) => true,
            _ => false,
        });
        if blank {
            self.pending.clear();
        } else {
            self.pending.push(Token::Node(Inline::LineBreak));
        }
        self.pending.extend(tokens);
    }

    fn add_html(&mut self, text: &str) {
        let mut tokens = Vec::new();
        tokenize(text, &mut tokens);
        let mut index = 0;
        while index < tokens.len() {
            // A media element's content is skipped only within this HTML block's tokens, so an
            // unclosed one never swallows the blocks after it.
            if let Some((media, next)) = read_media(&tokens, index) {
                if let Some(media) = media {
                    self.add_media(media);
                }
                index = next;
                continue;
            }
            let token = std::mem::replace(&mut tokens[index], Token::Text(String::new()));
            index += 1;
            let handled = match &token {
                Token::Open(tag, attributes) => self.open(tag, attributes),
                Token::Close(tag) => self.close(tag),
                _ => false,
            };
            if handled {
                continue;
            }
            // Drop anything outside cells and captions, such as whitespace between rows.
            if self.table.is_some() && !self.table_text_open() {
                continue;
            }
            self.pending.push(token);
        }
    }

    /// A media element is a block of its own, except where only inlines fit (a table cell or
    /// caption, or an HTML heading), where its fallback link is used. Between table rows it is
    /// dropped like other text there.
    fn add_media(&mut self, media: Media) {
        if self.table_text_open() || (self.table.is_none() && self.heading.is_some()) {
            self.pending.push(Token::Node(media.link()));
        } else if self.table.is_none() {
            self.push(media.block());
        }
    }

    /// pulldown-cmark includes the source line terminator at the end of an
    /// HTML-block event. Markdown's HtmlBlockSyntax joins its lines without
    /// that structural boundary, so remove exactly one terminator before the
    /// shared HTML tokenizer sees it. Interior newlines remain content.
    fn add_html_block(&mut self, text: &str) {
        let content = text
            .strip_suffix("\r\n")
            .or_else(|| text.strip_suffix('\n'))
            .or_else(|| text.strip_suffix('\r'))
            .unwrap_or(text);
        let mut rest = content;
        while let Some(element) = find_raw_element(rest) {
            self.add_html(&rest[..element.span.start]);
            self.add_raw_element(rest, &element);
            rest = &rest[element.span.end..];
        }
        self.add_html(rest);
        self.end_html_block();
    }

    /// An HTML block ends at a blank line. Text it left behind (such as the text after an
    /// `<hr>` line) is a paragraph of its own, so it must not absorb the next block. Nothing is
    /// flushed while a `<div>`, `<details>`, heading or table is open, because those span blocks.
    fn end_html_block(&mut self) {
        if self.aligns.is_empty()
            && !self.in_details()
            && self.heading.is_none()
            && self.table.is_none()
        {
            self.flush_pending();
        }
    }

    /// `<pre>` / `<textarea>` content becomes plain code as is, and `<script>` / `<style>`
    /// are dropped with their content. Inside a table cell, code is also added to the cell as text.
    fn add_raw_element(&mut self, text: &str, element: &RawElement) {
        let content = &text[element.content.clone()];
        let (code, language) = match element.tag {
            "pre" => preformatted_code(content, &element.attributes),
            "textarea" => (textarea_text(content), None),
            _ => return,
        };
        if code.is_empty() || (self.table.is_some() && !self.table_text_open()) {
            return;
        }
        if self.table_text_open() {
            self.add_table_text(vec![Token::Text(code)]);
        } else {
            self.push(Block::CodeBlock {
                code,
                language,
                info: None,
            });
        }
    }

    /// Handles an opening tag that is treated as a block. Returns false if it was not handled.
    fn open(&mut self, tag: &str, attributes: &[(String, String)]) -> bool {
        if self.table.is_some() {
            return self.open_in_table(tag, attributes);
        }
        if tag == TABLE_TAG {
            self.flush_pending();
            self.table = Some(HtmlTable::default());
            return true;
        }
        let container = match tag {
            DETAILS_TAG => Some(HtmlContainer::Details {
                summary: Vec::new(),
                open: attribute(attributes, "open").is_some(),
            }),
            // Inside an HTML heading these tags are dropped and their content
            // stays in the heading, so a heading is never split into blocks.
            "blockquote" | "ul" | "ol" | "li" if self.heading.is_some() => None,
            "blockquote" => Some(HtmlContainer::Quote),
            "ul" | "ol" => Some(HtmlContainer::List {
                start: (tag == "ol").then(|| {
                    attribute(attributes, "start")
                        .and_then(|value| value.trim().parse::<u32>().ok())
                        .filter(|&value| value > 0)
                        .unwrap_or(DEFAULT_LIST_START)
                }),
                items: Vec::new(),
            }),
            "li" if self.prepare_list_item() => Some(HtmlContainer::Item),
            _ => None,
        };
        if let Some(kind) = container {
            self.flush_pending();
            self.containers.push(HtmlFrame {
                kind,
                blocks: Vec::new(),
            });
            return true;
        }
        if tag == SUMMARY_TAG && self.in_details() {
            self.flush_pending();
            return true;
        }
        if tag == RULE_TAG {
            self.flush_pending();
            self.current().push(Block::ThematicBreak);
            return true;
        }
        if ALIGN_CONTAINER_TAGS.contains(&tag) {
            self.flush_pending();
            self.aligns.push(if tag == CENTER_TAG {
                Some(Align::Center)
            } else {
                align_from_value(attribute(attributes, "align"))
            });
            return true;
        }
        if let Some(level) = html_heading_level(tag) {
            self.flush_pending();
            self.heading = Some((level, align_from_value(attribute(attributes, "align"))));
            return true;
        }
        false
    }

    fn open_in_table(&mut self, tag: &str, attributes: &[(String, String)]) -> bool {
        if tag == TABLE_CAPTION_TAG && !self.table_text_open() {
            if let Some(table) = &mut self.table {
                table.caption_open = true;
            }
            return true;
        }
        if tag == TABLE_ROW_TAG {
            self.close_caption();
            self.close_cell();
            if let Some(table) = &mut self.table {
                table.rows.push(Vec::new());
            }
            return true;
        }
        if tag == TABLE_HEADER_CELL_TAG || tag == TABLE_CELL_TAG {
            self.close_caption();
            self.close_cell();
            self.pending.clear();
            if let Some(table) = &mut self.table {
                if table.rows.is_empty() {
                    table.rows.push(Vec::new());
                }
                table.open_cell = Some(OpenCell {
                    is_header: tag == TABLE_HEADER_CELL_TAG || table.in_head,
                    align: align_from_value(attribute(attributes, "align")),
                    colspan: span_from_value(attribute(attributes, "colspan")),
                    rowspan: span_from_value(attribute(attributes, "rowspan")),
                });
            }
            return true;
        }
        if TABLE_SECTION_TAGS.contains(&tag) {
            self.close_caption();
            self.close_cell();
            if let Some(table) = &mut self.table {
                table.in_head = tag == TABLE_HEAD_TAG;
            }
            return true;
        }
        // Inside a cell, other tags are treated as inlines.
        false
    }

    /// Handles a closing tag that is treated as a block. Returns false if it was not handled.
    fn close(&mut self, tag: &str) -> bool {
        if self.table.is_some() {
            if tag == TABLE_CAPTION_TAG {
                self.close_caption();
                return true;
            }
            if tag == TABLE_HEADER_CELL_TAG || tag == TABLE_CELL_TAG || tag == TABLE_ROW_TAG {
                self.close_cell();
                return true;
            }
            if tag == TABLE_TAG {
                self.close_table();
                return true;
            }
            if TABLE_SECTION_TAGS.contains(&tag) {
                self.close_cell();
                if let Some(table) = &mut self.table {
                    table.in_head = false;
                }
                return true;
            }
            return false;
        }

        if tag == SUMMARY_TAG && self.in_details() {
            let inlines = self.take_inlines();
            if let Some(HtmlFrame {
                kind: HtmlContainer::Details { summary, .. },
                ..
            }) = self.containers.last_mut()
            {
                *summary = inlines;
            }
            return true;
        }
        if matches!(tag, DETAILS_TAG | "blockquote" | "ul" | "ol" | "li") {
            if let Some(index) = self
                .containers
                .iter()
                .rposition(|frame| frame.kind.tag() == tag)
            {
                // An unmatched </li> inside a nested list must not close the outer item.
                if tag == "li"
                    && self.containers[index + 1..]
                        .iter()
                        .any(|frame| matches!(frame.kind, HtmlContainer::List { .. }))
                {
                    return false;
                }
                self.close_containers_from(index);
                return true;
            }
        }
        if ALIGN_CONTAINER_TAGS.contains(&tag) {
            self.flush_pending();
            self.aligns.pop();
            return true;
        }
        if html_heading_level(tag).is_some() && self.heading.is_some() {
            self.close_heading();
            return true;
        }
        false
    }

    fn close_cell(&mut self) {
        let Some(cell) = self.table.as_mut().and_then(|t| t.open_cell.take()) else {
            return;
        };
        let inlines = self.take_inlines();
        if let Some(row) = self.table.as_mut().and_then(|t| t.rows.last_mut()) {
            row.push(HtmlCell {
                inlines,
                is_header: cell.is_header,
                align: cell.align,
                colspan: cell.colspan,
                rowspan: cell.rowspan,
            });
        }
    }

    fn close_caption(&mut self) {
        if !self
            .table
            .as_mut()
            .is_some_and(|table| std::mem::take(&mut table.caption_open))
        {
            return;
        }
        let inlines = self.take_inlines();
        if let Some(table) = &mut self.table {
            if table.caption.is_empty() {
                table.caption = inlines;
            }
        }
    }

    fn close_table(&mut self) {
        self.close_caption();
        self.close_cell();
        if let Some(mut table) = self.table.take() {
            let caption = std::mem::take(&mut table.caption);
            if !caption.is_empty() {
                let align = self.align();
                self.current().push(Block::Paragraph(caption, align));
            }
            if let Some(block) = table.build() {
                self.current().push(block);
            }
        }
    }

    fn close_heading(&mut self) {
        let Some((level, align)) = self.heading.take() else {
            return;
        };
        let inlines = self.take_inlines();
        let align = align.unwrap_or_else(|| self.align());
        self.current().push(Block::Heading(level, inlines, align));
    }

    fn in_details(&self) -> bool {
        self.containers
            .last()
            .is_some_and(|frame| matches!(frame.kind, HtmlContainer::Details { .. }))
    }

    /// A new item implicitly closes the preceding item of the nearest list.
    /// Preserve text outside explicit items as an implicit item.
    fn prepare_list_item(&mut self) -> bool {
        let Some(index) = self
            .containers
            .iter()
            .rposition(|frame| matches!(frame.kind, HtmlContainer::List { .. }))
        else {
            return false;
        };
        self.close_containers_from(index + 1);
        if let Some(HtmlFrame {
            kind: HtmlContainer::List { items, .. },
            blocks,
        }) = self.containers.last_mut()
        {
            if !blocks.is_empty() {
                add_html_list_item(items, std::mem::take(blocks));
            }
        }
        true
    }

    fn close_containers_from(&mut self, index: usize) {
        self.flush_pending();
        while self.containers.len() > index {
            let HtmlFrame { kind, blocks } = self.containers.pop().unwrap();
            let block = match kind {
                HtmlContainer::Details { summary, open } => Block::Details {
                    summary,
                    blocks,
                    open,
                },
                HtmlContainer::Quote => Block::Blockquote(blocks),
                HtmlContainer::List { start, mut items } => {
                    if !blocks.is_empty() {
                        add_html_list_item(&mut items, blocks);
                    }
                    Block::List {
                        ordered: start.is_some(),
                        start: start.unwrap_or(DEFAULT_LIST_START),
                        tight: true,
                        items,
                    }
                }
                HtmlContainer::Item => {
                    if let Some(HtmlFrame {
                        kind: HtmlContainer::List { items, .. },
                        ..
                    }) = self.containers.last_mut()
                    {
                        add_html_list_item(items, blocks);
                    }
                    continue;
                }
            };
            self.current().push(block);
        }
    }

    fn finish(mut self) -> Vec<Block> {
        // Close unclosed tags at the end (for example, mid-stream).
        self.close_heading();
        if self.table.is_some() {
            self.close_table();
        }
        self.close_containers_from(0);
        self.root
    }
}

fn inline_text(inlines: &[Inline], out: &mut String) {
    for inline in inlines {
        match inline {
            Inline::Text(text) => out.push_str(text),
            Inline::Styled(_, children)
            | Inline::Titled(_, _, children)
            | Inline::Span(_, children)
            | Inline::Link { children, .. } => inline_text(children, out),
            Inline::SoftBreak => out.push(' '),
            Inline::LineBreak | Inline::Image { .. } => {}
        }
    }
}

/// The bullet marker of a list.
const BULLET_PREFIX: &str = "\u{2022} ";

/// Extracts only the text inside a block, line by line. An HTML table cell can hold only inlines,
/// so blocks that go into a cell (lists, code, and so on) are flattened into these lines.
/// Decoration is lost, but no text is dropped.
fn block_lines(block: &Block, out: &mut Vec<String>) {
    match block {
        Block::Paragraph(inlines, _) | Block::Heading(_, inlines, _) => {
            let mut line = String::new();
            inline_text(inlines, &mut line);
            out.push(line);
        }
        Block::CodeBlock { code, .. } => out.extend(code.lines().map(str::to_string)),
        Block::Blockquote(blocks) => blocks.iter().for_each(|block| block_lines(block, out)),
        Block::List {
            ordered,
            start,
            items,
            ..
        } => {
            for (index, item) in items.iter().enumerate() {
                let marker = if *ordered {
                    format!("{}. ", u64::from(*start) + index as u64)
                } else {
                    BULLET_PREFIX.to_string()
                };
                let first = out.len();
                item.blocks.iter().for_each(|block| block_lines(block, out));
                match out.get_mut(first) {
                    Some(line) => line.insert_str(0, &marker),
                    None => out.push(marker.trim_end().to_string()),
                }
            }
        }
        Block::Table { header, rows, .. } => {
            for row in std::iter::once(header).chain(rows.iter()) {
                let mut line = String::new();
                for (index, cell) in row.iter().enumerate() {
                    if index > 0 {
                        line.push('\t');
                    }
                    inline_text(&cell.inlines, &mut line);
                }
                if !line.is_empty() {
                    out.push(line);
                }
            }
        }
        Block::Details {
            summary, blocks, ..
        } => {
            let mut line = String::new();
            inline_text(summary, &mut line);
            out.push(line);
            blocks.iter().for_each(|block| block_lines(block, out));
        }
        Block::Custom {
            inlines, blocks, ..
        } => {
            let mut line = String::new();
            inline_text(inlines, &mut line);
            out.push(line);
            blocks.iter().for_each(|block| block_lines(block, out));
        }
        Block::ThematicBreak => {}
    }
}

struct Converter<'a> {
    source: &'a str,
    events: OffsetIter<'a>,
    /// The range in the source of the event read just before.
    last_range: Range<usize>,
    /// The depth of nesting inside links. URLs are not autolinked inside a link.
    link_depth: usize,
    /// The labels of referenced footnotes, in order of appearance.
    footnote_labels: Vec<String>,
    footnote_definitions: Vec<(String, Vec<Block>)>,
    /// A task list marker read inside a paragraph (loose list items), until the paragraph ends.
    task_marker: Option<Task>,
}

impl<'a> Converter<'a> {
    fn autolink(&self) -> bool {
        self.link_depth == 0
    }

    fn next_event(&mut self) -> Option<Event<'a>> {
        let (event, range) = self.events.next()?;
        self.last_range = range;
        Some(event)
    }

    /// The task marker of the TaskListMarker event read just before: its state and where it starts.
    fn task(&self, checked: bool) -> Task {
        Task {
            checked,
            offset: self.last_range.start,
        }
    }

    /// Whether the Text event read just before came from an entity such as `&amp;`.
    fn last_text_is_entity(&self, text: &str) -> bool {
        let raw = &self.source[self.last_range.clone()];
        raw.len() != text.len() && raw.starts_with('&') && raw.ends_with(';')
    }

    /// Whether this text event contains an invalid angle autolink whose
    /// punctuation was backslash-escaped. Pulldown decodes the escape before
    /// the plain-text autolinker sees the event, so use its source range to
    /// avoid discovering an email or URL inside that literal text.
    fn last_text_contains_escaped_angle_autolink(&self) -> bool {
        let range = self.last_range.clone();
        let bytes = self.source.as_bytes();
        let raw = &bytes[range.clone()];
        // Pulldown may omit the escape marker from a text event's source range
        // and split the surrounding angle brackets into adjacent events. Find
        // the nearby pair in bounded byte windows around this event instead of
        // scanning the document prefix and suffix for every text event.
        let open = raw
            .iter()
            .position(|&byte| byte == b'<')
            .map(|offset| range.start + offset)
            .or_else(|| {
                let start = range.start.saturating_sub(512);
                bytes[start..range.start]
                    .iter()
                    .rposition(|&byte| byte == b'<')
                    .map(|offset| start + offset)
            });
        let Some(open) = open else {
            return false;
        };
        if open > range.start {
            return false;
        }
        let raw_start = open.saturating_add(1).max(range.start);
        let raw_end = range.end;
        let close = bytes[raw_start..raw_end]
            .iter()
            .position(|&byte| byte == b'>')
            .map(|offset| raw_start + offset)
            .or_else(|| {
                let end = range.end.saturating_add(512).min(bytes.len());
                bytes[range.end..end]
                    .iter()
                    .position(|&byte| byte == b'>')
                    .map(|offset| range.end + offset)
            });
        let Some(close) = close else {
            return false;
        };
        // Check ordering before subtraction; malformed text may contain `>`
        // before the nearest preceding `<`.
        if close < open || close - open > 512 {
            return false;
        }
        let candidate = &self.source[open..=close];
        let escaped_open = open > 0 && bytes[open - 1] == b'\\';
        let escaped_inside = candidate
            .as_bytes()
            .windows(2)
            .any(|pair| pair[0] == b'\\' && pair[1].is_ascii_punctuation());
        (escaped_open || escaped_inside)
            && (candidate.contains('@') || candidate.contains("://") || candidate.contains("www."))
    }

    /// Returns the blocks up to the end of the container, and the task marker of task list items.
    fn blocks(&mut self) -> (Vec<Block>, Option<Task>) {
        let (blocks, task, _) = self.blocks_with_paragraphs();
        (blocks, task)
    }

    /// Like [`Self::blocks`], and also reports whether a paragraph event appeared directly in this
    /// container. pulldown-cmark emits paragraphs inside list items only for loose lists.
    fn blocks_with_paragraphs(&mut self) -> (Vec<Block>, Option<Task>, bool) {
        let mut builder = BlockBuilder::default();
        let mut task = None;
        let mut saw_paragraph = false;

        while let Some(event) = self.next_event() {
            match event {
                Event::End(_) => break,
                Event::Start(Tag::Paragraph) => {
                    saw_paragraph = true;
                    let tokens = self.tokens_until_end();
                    // In a loose item the marker arrives inside the first paragraph.
                    if let Some(marker) = self.task_marker.take() {
                        task = task.or(Some(marker));
                    }
                    if builder.table_text_open() {
                        builder.add_table_text(tokens);
                        continue;
                    }
                    if let Some(media) = standalone_media(&tokens) {
                        builder.push(media.block());
                        continue;
                    }
                    let inlines = build_inlines(tokens, true, true);
                    builder.flush_pending();
                    if !inlines.is_empty() {
                        let align = builder.align();
                        builder.push(Block::Paragraph(inlines, align));
                    }
                }
                Event::Start(Tag::Heading { level, .. }) => {
                    let inlines = build_inlines(self.tokens_until_end(), true, true);
                    let align = builder.align();
                    Self::push_block(&mut builder, Block::Heading(level as u8, inlines, align));
                }
                Event::Start(Tag::BlockQuote(_)) => {
                    let (blocks, _) = self.blocks();
                    Self::push_block(&mut builder, Block::Blockquote(blocks));
                }
                Event::Start(Tag::CodeBlock(kind)) => {
                    let block = self.code_block(kind);
                    Self::push_block(&mut builder, block);
                }
                Event::Start(Tag::List(start)) => {
                    let block = self.list(start);
                    Self::push_block(&mut builder, block);
                }
                Event::Start(Tag::Table(alignments)) => {
                    let block = self.table(&alignments);
                    Self::push_block(&mut builder, block);
                }
                Event::Start(Tag::HtmlBlock) => {
                    let html = self.text_until_end();
                    builder.add_html_block(&html);
                }
                Event::Start(Tag::FootnoteDefinition(label)) => {
                    builder.flush_pending();
                    let (blocks, _) = self.blocks();
                    // When several definitions share a label, use the first one.
                    let defined = self
                        .footnote_definitions
                        .iter()
                        .any(|(existing, _)| existing.as_str() == &*label);
                    if !defined {
                        self.footnote_definitions
                            .push((label.into_string(), blocks));
                    }
                }
                Event::Html(html) => builder.add_html_block(&html),
                Event::Rule => Self::push_block(&mut builder, Block::ThematicBreak),
                Event::TaskListMarker(value) => task = Some(self.task(value)),
                Event::Start(
                    tag @ (Tag::Emphasis
                    | Tag::Strong
                    | Tag::Strikethrough
                    | Tag::Superscript
                    | Tag::Subscript
                    | Tag::Link { .. }
                    | Tag::Image { .. }),
                ) => self.inline_token(Event::Start(tag), &mut builder.pending),
                Event::Start(_) => {
                    // For an unsupported block, take in only the inner blocks.
                    let (blocks, _) = self.blocks();
                    builder.flush_pending();
                    builder.current().extend(blocks);
                }
                // Inlines that appear directly under a list item and the like.
                other => self.inline_token(other, &mut builder.pending),
            }
        }
        (builder.finish(), task, saw_paragraph)
    }

    /// Inside an HTML table cell, adds only the text to the cell; otherwise
    /// adds it as a block.
    fn push_block(builder: &mut BlockBuilder, block: Block) {
        if !builder.table_text_open() {
            builder.push(block);
            return;
        }
        let mut lines = Vec::new();
        block_lines(&block, &mut lines);
        for line in lines.into_iter().filter(|line| !line.is_empty()) {
            builder.add_table_text(vec![Token::Text(line)]);
        }
    }

    /// Turns the inlines up to the matching End into tokens.
    ///
    /// A nested Start reads through to its own End inside the recursion, so the
    /// first End that appears at this level is its own.
    fn tokens_until_end(&mut self) -> Vec<Token> {
        let mut tokens = Vec::new();
        while let Some(event) = self.next_event() {
            if matches!(event, Event::End(_)) {
                break;
            }
            self.inline_token(event, &mut tokens);
        }
        tokens
    }

    fn inlines_until_end(&mut self) -> Vec<Inline> {
        let tokens = self.tokens_until_end();
        build_inlines(tokens, false, self.autolink())
    }

    fn inline_token(&mut self, event: Event<'a>, out: &mut Vec<Token>) {
        match event {
            // An entity is not made part of a URL. Pass it on without joining it to plain text.
            Event::Text(text) if self.last_text_is_entity(&text) => {
                out.push(Token::Text(text.into_string()));
            }
            Event::Text(text) if self.last_text_contains_escaped_angle_autolink() => {
                out.push(Token::Text(text.into_string()));
            }
            Event::Text(text) => out.push(Token::Markdown(text.into_string())),
            Event::Code(code) => out.push(Token::Node(Inline::Styled(
                StyleKind::Code,
                vec![Inline::Text(code.into_string())],
            ))),
            // A soft break stays its own inline; the renderer decides how it looks.
            Event::SoftBreak => out.push(Token::Node(Inline::SoftBreak)),
            Event::HardBreak => out.push(Token::Node(Inline::LineBreak)),
            Event::InlineHtml(html) | Event::Html(html) => tokenize(&html, out),
            Event::TaskListMarker(value) => self.task_marker = Some(self.task(value)),
            Event::FootnoteReference(label) => {
                let node = self.footnote_reference(&label);
                out.push(Token::Node(node));
            }
            Event::Start(Tag::Emphasis) => self.styled(StyleKind::Emphasis, out),
            Event::Start(Tag::Strong) => self.styled(StyleKind::Strong, out),
            Event::Start(Tag::Strikethrough) => self.styled(StyleKind::Strikethrough, out),
            Event::Start(Tag::Superscript) => self.styled(StyleKind::Superscript, out),
            Event::Start(Tag::Subscript) => self.styled(StyleKind::Subscript, out),
            Event::Start(Tag::Link {
                link_type,
                dest_url,
                title,
                ..
            }) => {
                self.link_depth += 1;
                let children = self.inlines_until_end();
                self.link_depth -= 1;
                let destination = if link_type == LinkType::Email {
                    format!("mailto:{dest_url}")
                } else {
                    dest_url.into_string()
                };
                out.push(Token::Node(Inline::Link {
                    href: uri::encode_full(&destination),
                    title: non_empty(title.into_string()),
                    children,
                }));
            }
            Event::Start(Tag::Image {
                dest_url, title, ..
            }) => {
                let alt = self.text_until_end();
                out.push(Token::Node(Inline::Image {
                    src: uri::encode_full(&dest_url),
                    alt: Some(alt),
                    title: non_empty(title.into_string()),
                    width: None,
                    height: None,
                }));
            }
            Event::Start(_) => {
                // For an unsupported inline element, keep only its content.
                for child in self.inlines_until_end() {
                    out.push(Token::Node(child));
                }
            }
            _ => {}
        }
    }

    fn styled(&mut self, kind: StyleKind, out: &mut Vec<Token>) {
        let children = self.inlines_until_end();
        out.push(Token::Node(Inline::Styled(kind, children)));
    }

    /// Turns a footnote reference into a superscript link that shows its number. Numbers are in order of appearance.
    fn footnote_reference(&mut self, label: &str) -> Inline {
        let index = match self.footnote_labels.iter().position(|l| l == label) {
            Some(index) => index,
            None => {
                self.footnote_labels.push(label.to_string());
                self.footnote_labels.len() - 1
            }
        };
        Inline::Styled(
            StyleKind::Superscript,
            vec![Inline::Link {
                href: format!("{FOOTNOTE_HREF_PREFIX}{label}"),
                title: None,
                children: vec![Inline::Text((index + 1).to_string())],
            }],
        )
    }

    /// Appends the definitions of referenced footnotes at the end as a horizontal rule and a numbered list.
    fn append_footnotes(&mut self, blocks: &mut Vec<Block>) {
        let mut items = Vec::new();
        for label in &self.footnote_labels {
            let position = self
                .footnote_definitions
                .iter()
                .position(|(defined, _)| defined == label);
            if let Some(position) = position {
                let (_, definition) = self.footnote_definitions.swap_remove(position);
                items.push(ListItem {
                    blocks: definition,
                    task: None,
                });
            }
        }
        if items.is_empty() {
            return;
        }
        blocks.push(Block::ThematicBreak);
        blocks.push(Block::List {
            ordered: true,
            start: DEFAULT_LIST_START,
            // Footnote items hold paragraph blocks.
            tight: false,
            items,
        });
    }

    /// Concatenates only the text up to the matching End (image alt, code block content).
    fn text_until_end(&mut self) -> String {
        let mut text = String::new();
        let mut depth = 0usize;
        while let Some(event) = self.next_event() {
            match event {
                Event::Start(_) => depth += 1,
                Event::End(_) if depth == 0 => break,
                Event::End(_) => depth -= 1,
                Event::Text(part) | Event::Code(part) | Event::Html(part) => text.push_str(&part),
                Event::InlineHtml(part) => text.push_str(&part),
                Event::SoftBreak | Event::HardBreak => text.push(' '),
                _ => {}
            }
        }
        text
    }

    fn code_block(&mut self, kind: CodeBlockKind) -> Block {
        let (language, info) = match kind {
            CodeBlockKind::Fenced(info) => {
                let info = info.trim();
                match info.find(char::is_whitespace) {
                    Some(end) => (
                        Some(info[..end].to_string()),
                        non_empty(info[end..].trim().to_string()),
                    ),
                    None => (non_empty(info.to_string()), None),
                }
            }
            CodeBlockKind::Indented => (None, None),
        };
        let mut code = self.text_until_end();
        if code.ends_with('\n') {
            code.pop();
        }
        Block::CodeBlock {
            code,
            language,
            info,
        }
    }

    fn list(&mut self, start: Option<u64>) -> Block {
        let mut items = Vec::new();
        let mut tight = true;
        while let Some(event) = self.next_event() {
            match event {
                Event::Start(Tag::Item) => {
                    let (blocks, task, saw_paragraph) = self.blocks_with_paragraphs();
                    tight &= !saw_paragraph;
                    items.push(ListItem { blocks, task });
                }
                Event::End(_) => break,
                _ => {}
            }
        }
        Block::List {
            ordered: start.is_some(),
            start: start
                .and_then(|value| u32::try_from(value).ok())
                .unwrap_or(DEFAULT_LIST_START),
            tight,
            items,
        }
    }

    fn table(&mut self, alignments: &[Alignment]) -> Block {
        let mut header = Vec::new();
        let mut rows = Vec::new();
        while let Some(event) = self.next_event() {
            match event {
                Event::Start(Tag::TableHead) => header = self.table_cells(),
                Event::Start(Tag::TableRow) => rows.push(self.table_cells()),
                Event::End(_) => break,
                _ => {}
            }
        }
        Block::Table {
            alignments: alignments
                .iter()
                .map(|alignment| match alignment {
                    Alignment::None => Align::None,
                    Alignment::Left => Align::Left,
                    Alignment::Center => Align::Center,
                    Alignment::Right => Align::Right,
                })
                .collect(),
            header,
            rows,
        }
    }

    fn table_cells(&mut self) -> Vec<Cell> {
        let mut cells = Vec::new();
        while let Some(event) = self.next_event() {
            match event {
                Event::Start(Tag::TableCell) => {
                    cells.push(Cell::new(build_inlines(
                        self.tokens_until_end(),
                        true,
                        true,
                    )));
                }
                Event::End(_) => break,
                _ => {}
            }
        }
        cells
    }
}

fn non_empty(value: String) -> Option<String> {
    if value.is_empty() {
        None
    } else {
        Some(value)
    }
}

#[cfg(test)]
mod uri_destination_tests {
    use super::parse;
    use crate::ir::{Block, Inline};

    fn first_inline(markdown: &str) -> Inline {
        let blocks = parse(markdown);
        let Block::Paragraph(inlines, _) = &blocks[0] else {
            panic!("expected a paragraph");
        };
        match &inlines[0] {
            Inline::Link { href, .. } => Inline::Link {
                href: href.clone(),
                title: None,
                children: Vec::new(),
            },
            Inline::Image { src, .. } => Inline::Image {
                src: src.clone(),
                alt: None,
                title: None,
                width: None,
                height: None,
            },
            _ => panic!("expected link or image"),
        }
    }

    #[test]
    fn markdown_link_and_image_destinations_match_dart_uri_encoding() {
        assert!(matches!(
            first_inline("[x](/föö%2f?q=a%20b)"),
            Inline::Link { href, .. } if href == "/f%C3%B6%C3%B6%2f?q=a%20b"
        ));
        assert!(matches!(
            first_inline("![alt](</café image.png>)"),
            Inline::Image { src, .. } if src == "/caf%C3%A9%20image.png"
        ));
    }

    #[test]
    fn angle_email_autolink_gets_mailto_scheme() {
        assert!(matches!(
            first_inline("<john@example.com>"),
            Inline::Link { href, .. } if href == "mailto:john@example.com"
        ));
    }

    #[test]
    fn raw_html_link_attributes_keep_their_original_encoding() {
        let blocks = parse("<a href=\"/föö%2f\">x</a>");
        let Block::Paragraph(inlines, _) = &blocks[0] else {
            panic!("expected a paragraph");
        };
        assert!(matches!(
            &inlines[0],
            Inline::Link { href, .. } if href == "/föö%2f"
        ));
    }
}

#[cfg(test)]
mod commonmark_html_regressions {
    use super::{parse, Converter, Options, Parser};
    use crate::ir::{Block, Inline, StyleKind};

    fn flatten(inlines: &[Inline], text: &mut String) {
        for inline in inlines {
            match inline {
                Inline::Text(value) => text.push_str(value),
                Inline::Styled(_, children)
                | Inline::Titled(_, _, children)
                | Inline::Span(_, children)
                | Inline::Link { children, .. } => flatten(children, text),
                Inline::LineBreak => text.push('\n'),
                Inline::SoftBreak => text.push(' '),
                Inline::Image { .. } => {}
            }
        }
    }

    fn paragraph_text(markdown: &str) -> String {
        let blocks = parse(markdown);
        let Block::Paragraph(inlines, _) = &blocks[0] else {
            panic!("expected a paragraph");
        };
        let mut text = String::new();
        flatten(inlines, &mut text);
        text
    }

    #[test]
    fn unmatched_html_anchor_boundary_newline_is_not_a_child() {
        for source in [
            "<a href=\"/bar\\/)\">\n",
            "<a href=\"&ouml;&ouml;.html\">\n",
        ] {
            let blocks = parse(source);
            let Block::Paragraph(inlines, _) = &blocks[0] else {
                panic!("expected a paragraph");
            };
            assert!(matches!(
                &inlines[..],
                [Inline::Link { children, .. }] if children.is_empty()
            ));
        }
    }

    #[test]
    fn raw_html_paragraph_boundaries_do_not_create_empty_formatting_blocks() {
        let blocks = parse("<del>\n\n*foo*\n\n</del>\n");
        assert!(matches!(
            &blocks[..],
            [Block::Paragraph(inlines, _)]
                if matches!(&inlines[..], [Inline::Styled(StyleKind::Emphasis, _)])
        ));
    }

    #[test]
    fn raw_html_blank_lines_keep_one_space_per_source_newline() {
        assert_eq!(
            paragraph_text("<?php\n\n  echo '>';\n\n?>\n"),
            "<?php  echo '>';  ?>"
        );
        assert_eq!(
            paragraph_text("<![CDATA[\nreturn 1;\n\n  } else {\n\nreturn 0;\n]]>\n"),
            "<![CDATA[ return 1;  } else {  return 0; ]]>"
        );
    }

    #[test]
    fn table_html_block_boundary_does_not_leave_space_before_markdown_line_break() {
        let source = "<table><tr><td>\n<pre>\n**Hello**,\n\n_world_.\n</pre>\n</td></tr></table>\n";
        let blocks = parse(source);
        let Block::Table { rows, .. } = &blocks[0] else {
            panic!("expected a table");
        };
        assert!(matches!(
            &rows[0][0].inlines[..],
            [Inline::Text(text), Inline::LineBreak, Inline::Styled(StyleKind::Emphasis, _), Inline::Text(_)]
                if text == "**Hello**,"
        ));
    }

    #[test]
    fn escaped_punctuation_text_is_not_reinterpreted_as_an_autolink() {
        let blocks = parse("<foo\\+@bar.example.com>\n");
        let Block::Paragraph(inlines, _) = &blocks[0] else {
            panic!("expected a paragraph");
        };
        assert!(matches!(
            &inlines[..],
            [Inline::Text(text)] if text == "<foo+@bar.example.com>"
        ));
    }

    #[test]
    fn large_unicode_text_without_angle_brackets_remains_plain_and_complete() {
        let source = "*日本語* ".repeat(4_096);
        assert!(!source.contains('<') && !source.contains('>'));

        let blocks = parse(&source);
        let Block::Paragraph(inlines, _) = &blocks[0] else {
            panic!("expected a paragraph");
        };
        assert_eq!(
            inlines
                .iter()
                .filter(|inline| matches!(inline, Inline::Styled(StyleKind::Emphasis, _)))
                .count(),
            4_096
        );
        let mut actual = String::new();
        flatten(inlines, &mut actual);
        assert_eq!(actual, "日本語 ".repeat(4_096).trim_end());
    }

    #[test]
    fn greater_than_before_angle_bracket_does_not_underflow_pair_distance() {
        let source = ">foo\\+@bar.example.com<";
        let converter = Converter {
            source,
            events: Parser::new_ext(source, Options::empty()).into_offset_iter(),
            last_range: 0..source.len(),
            link_depth: 0,
            footnote_labels: Vec::new(),
            footnote_definitions: Vec::new(),
            task_marker: None,
        };

        assert!(!converter.last_text_contains_escaped_angle_autolink());
    }
}

// ---------------------------------------------------------------------------
// C ABI
// ---------------------------------------------------------------------------

#[cfg(any(target_arch = "wasm32", test))]
fn allocate_zeroed_bytes(len: usize) -> *mut u8 {
    let mut bytes = vec![0_u8; len].into_boxed_slice();
    let pointer = bytes.as_mut_ptr();
    std::mem::forget(bytes);
    pointer
}

/// Free a byte slice returned by [`allocate_zeroed_bytes`] or `mdx_parse`.
#[cfg(any(target_arch = "wasm32", test))]
unsafe fn deallocate_bytes(pointer: *mut u8, len: usize) {
    if pointer.is_null() {
        return;
    }
    // SAFETY: callers must pass the exact pointer and length from one of the
    // allocation functions above.
    drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(pointer, len)) });
}

/// Allocate a zero-initialized byte slice for the wasm caller.
///
/// # Safety
/// The returned pointer must be passed to `mdx_dealloc` with the same length.
#[cfg(target_arch = "wasm32")]
#[no_mangle]
pub extern "C" fn mdx_alloc(len: usize) -> *mut u8 {
    allocate_zeroed_bytes(len)
}

/// Free memory allocated by `mdx_alloc`.
///
/// # Safety
/// `pointer` and `len` must be the exact pair returned by `mdx_alloc`.
#[cfg(target_arch = "wasm32")]
#[no_mangle]
pub unsafe extern "C" fn mdx_dealloc(pointer: *mut u8, len: usize) {
    // SAFETY: this export forwards the caller's allocation pair unchanged.
    unsafe { deallocate_bytes(pointer, len) };
}

/// The C ABI version. Bump it when the promises about the names, arguments, return values,
/// ownership, or errors of the exported functions change, and keep it in sync with the Dart side
/// (`expectedMdxAbiVersion` in `lib/src/parser/native/ir_decoder.dart`). It is separate from the IR binary format version.
pub const ABI_VERSION: u32 = 2;

/// Returns the C ABI version that Dart expects. Exported on every target.
#[no_mangle]
pub extern "C" fn mdx_abi_version() -> u32 {
    ABI_VERSION
}

/// Returns the version of the IR binary format output ([`ir::IR_VERSION`]).
#[no_mangle]
pub extern "C" fn mdx_ir_version() -> u32 {
    ir::IR_VERSION
}

/// Returns a static NUL-terminated string that identifies this build.
///
/// The content is `<crate name> <crate version> abi=<ABI> ir=<IR>`. It must not be freed.
/// The version numbers match [`ABI_VERSION`] and [`ir::IR_VERSION`]
/// (checked by a test).
#[no_mangle]
pub extern "C" fn mdx_build_info() -> *const std::os::raw::c_char {
    BUILD_INFO.as_ptr().cast()
}

const BUILD_INFO: &str = concat!(
    env!("CARGO_PKG_NAME"),
    " ",
    env!("CARGO_PKG_VERSION"),
    " abi=2 ir=6\0"
);

/// Parses UTF-8 Markdown and returns the IR in the binary format with a header.
///
/// The caller releases the returned region by passing the pair of the return value and `*out_len`
/// to [`mdx_free`]. A successful IR is never empty because it has a header.
///
/// On failure it returns null and, if `out_len` is not null, writes 0 to `*out_len`.
/// Failure happens in any of these cases: `out_len` is null, `source` is null but `source_len` is not 0,
/// `source_len` exceeds `isize::MAX`, a panic occurred during parsing, or the IR is too large
/// to fit in a `u32`. A panic is caught with `catch_unwind`, but it cannot be caught
/// in a build whose profile has `panic = "abort"`, or on wasm32
/// (`doc/native-abi.md`). Invalid UTF-8 is accepted and replaced with U+FFFD.
///
/// # Safety
///
/// If `source` is not null it must point to a region readable for `source_len` bytes, and if `out_len` is not
/// null it must point to a writable `usize`.
#[no_mangle]
pub unsafe extern "C" fn mdx_parse(
    source: *const u8,
    source_len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    if out_len.is_null() {
        return std::ptr::null_mut();
    }
    // SAFETY: out_len is not null, and the caller guarantees it is writable.
    unsafe { *out_len = 0 };
    if source_len > isize::MAX as usize || (source.is_null() && source_len != 0) {
        return std::ptr::null_mut();
    }
    let bytes = if source_len == 0 {
        &[][..]
    } else {
        // SAFETY: not null, and the caller guarantees source_len bytes are readable.
        unsafe { std::slice::from_raw_parts(source, source_len) }
    };
    let result = std::panic::catch_unwind(|| {
        let text = String::from_utf8_lossy(bytes);
        parse_to_bytes(&text)
    });
    match result {
        Ok(Ok(ir)) => {
            let boxed = ir.into_boxed_slice();
            // SAFETY: we checked above that out_len is writable.
            unsafe { *out_len = boxed.len() };
            Box::into_raw(boxed).cast::<u8>()
        }
        Ok(Err(_)) | Err(_) => std::ptr::null_mut(),
    }
}

/// Releases a region returned by [`mdx_parse`].
///
/// Null does nothing.
///
/// # Safety
///
/// `pointer` and `len` must be exactly the pair of the pointer and `*out_len` that
/// [`mdx_parse`] returned on success (changing the length is undefined behavior).
/// Do not release the same region twice.
#[no_mangle]
pub unsafe extern "C" fn mdx_free(pointer: *mut u8, len: usize) {
    if pointer.is_null() {
        return;
    }
    // SAFETY: the pointer and length that mdx_parse made from a Box<[u8]>.
    drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(pointer, len)) });
}

#[cfg(test)]
mod abi_tests {
    use super::*;
    use std::ffi::CStr;

    fn parse_raw(source: &[u8]) -> (*mut u8, usize) {
        let mut len = usize::MAX;
        // SAFETY: source is a readable region and len is a writable usize.
        let pointer = unsafe { mdx_parse(source.as_ptr(), source.len(), &mut len) };
        (pointer, len)
    }

    #[test]
    fn versions_match_constants() {
        assert_eq!(mdx_abi_version(), 2);
        assert_eq!(mdx_ir_version(), 6);
        assert_eq!(mdx_abi_version(), ABI_VERSION);
        assert_eq!(mdx_ir_version(), ir::IR_VERSION);
    }

    #[test]
    fn build_info_is_static_nul_terminated_and_consistent() {
        // SAFETY: a static NUL-terminated string.
        let info = unsafe { CStr::from_ptr(mdx_build_info()) }
            .to_str()
            .unwrap();
        assert_eq!(
            info,
            format!(
                "{} {} abi={} ir={}",
                env!("CARGO_PKG_NAME"),
                env!("CARGO_PKG_VERSION"),
                ABI_VERSION,
                ir::IR_VERSION
            )
        );
    }

    #[test]
    fn empty_document_is_header_and_zero_blocks() {
        let (pointer, len) = parse_raw(b"");
        assert!(!pointer.is_null());
        // SAFETY: a region of len bytes returned by mdx_parse.
        let bytes = unsafe { std::slice::from_raw_parts(pointer, len) }.to_vec();
        assert_eq!(bytes, [b'M', b'D', b'X', b'I', 6, 0, 0, 0, 0, 0, 0, 0]);
        // SAFETY: pass back the pair returned by mdx_parse as is.
        unsafe { mdx_free(pointer, len) };
    }

    #[test]
    fn output_starts_with_header() {
        let (pointer, len) = parse_raw("# 見出し".as_bytes());
        assert!(!pointer.is_null());
        // SAFETY: a region of len bytes returned by mdx_parse.
        let bytes = unsafe { std::slice::from_raw_parts(pointer, len) };
        assert_eq!(&bytes[..4], b"MDXI");
        assert_eq!(&bytes[4..8], &6_u32.to_le_bytes());
        // SAFETY: pass back the pair returned by mdx_parse as is.
        unsafe { mdx_free(pointer, len) };
    }

    #[test]
    fn null_out_len_returns_null() {
        // SAFETY: when out_len is null, source is not read.
        let pointer = unsafe { mdx_parse(b"a".as_ptr(), 1, std::ptr::null_mut()) };
        assert!(pointer.is_null());
    }

    #[test]
    fn null_source_with_length_fails_and_zeroes_out_len() {
        let mut len = 123;
        // SAFETY: when source is null and the length is not 0, it fails without reading.
        let pointer = unsafe { mdx_parse(std::ptr::null(), 5, &mut len) };
        assert!(pointer.is_null());
        assert_eq!(len, 0);
    }

    #[test]
    fn null_source_with_zero_length_is_empty_document() {
        let mut len = 0;
        // SAFETY: when the length is 0, source is not read.
        let pointer = unsafe { mdx_parse(std::ptr::null(), 0, &mut len) };
        assert!(!pointer.is_null());
        assert_eq!(len, 12);
        // SAFETY: pass back the pair returned by mdx_parse as is.
        unsafe { mdx_free(pointer, len) };
    }

    #[test]
    fn oversize_source_length_fails() {
        let mut len = 1;
        // SAFETY: when the length exceeds isize::MAX, it fails without reading.
        let pointer = unsafe { mdx_parse(b"a".as_ptr(), usize::MAX, &mut len) };
        assert!(pointer.is_null());
        assert_eq!(len, 0);
    }

    #[test]
    fn invalid_utf8_is_replaced_not_rejected() {
        let (pointer, len) = parse_raw(&[b'a', 0xff, b'b']);
        assert!(!pointer.is_null());
        // SAFETY: pass back the pair returned by mdx_parse as is.
        unsafe { mdx_free(pointer, len) };
    }

    #[test]
    fn free_accepts_null() {
        // SAFETY: null does nothing.
        unsafe { mdx_free(std::ptr::null_mut(), 0) };
    }
}

#[cfg(test)]
mod ir_header_tests {
    use super::*;

    #[test]
    fn parse_to_bytes_has_header() {
        let bytes = parse_to_bytes("x").unwrap();
        assert_eq!(&bytes[..4], &ir::MAGIC);
        assert_eq!(&bytes[4..8], &ir::IR_VERSION.to_le_bytes());
    }
}

#[cfg(test)]
mod wasm_allocator_tests {
    use super::{allocate_zeroed_bytes, deallocate_bytes};

    #[test]
    fn allocation_is_zeroed_and_released_with_its_original_length() {
        let len = 4;
        let pointer = allocate_zeroed_bytes(len);
        assert!(!pointer.is_null());

        // SAFETY: the allocator returns `len` writable bytes, which are
        // inspected and modified before being freed with the same length.
        unsafe {
            let bytes = std::slice::from_raw_parts_mut(pointer, len);
            assert_eq!(bytes, &[0, 0, 0, 0]);
            bytes.copy_from_slice(&[1, 2, 3, 4]);
            deallocate_bytes(pointer, len);
        }
    }

    #[test]
    fn zero_length_allocation_can_be_released() {
        let pointer = allocate_zeroed_bytes(0);
        // SAFETY: pointer and its zero length are returned by the allocator.
        unsafe { deallocate_bytes(pointer, 0) };
    }
}

#[cfg(test)]
mod html_policy_tests {
    use super::parse;
    use crate::ir::{Align, Block, Cell, Inline};

    fn code_blocks(markdown: &str) -> Vec<(String, Option<String>)> {
        parse(markdown)
            .into_iter()
            .filter_map(|block| match block {
                Block::CodeBlock { code, language, .. } => Some((code, language)),
                _ => None,
            })
            .collect()
    }

    #[test]
    fn html_blockquote_and_nested_lists_reuse_markdown_blocks() {
        let html = "<blockquote><p>Intro</p><ol reversed start='3'><li value='99'>first<ul><li>nested</li></ul></li><li>second</li></ol></blockquote>";
        let blocks = parse(html);
        let [Block::Blockquote(quoted)] = blocks.as_slice() else {
            panic!("expected a quote");
        };
        let [Block::Paragraph(..), Block::List {
            ordered: true,
            start: 3,
            items,
            ..
        }] = quoted.as_slice()
        else {
            panic!("expected a paragraph and ordered list");
        };
        assert_eq!(items.len(), 2);
        assert!(
            matches!(items[0].blocks.as_slice(), [Block::Paragraph(..), Block::List { ordered: false, items, .. }] if items.len() == 1)
        );
        assert!(
            matches!(items[1].blocks.as_slice(), [Block::Paragraph(inlines, _)] if matches!(inlines.as_slice(), [Inline::Text(text)] if text == "second"))
        );
    }

    #[test]
    fn html_list_implicitly_closes_items_and_preserves_nested_containers() {
        let blocks = parse("<ul><li>one<li><details><summary>More</summary><blockquote>two</blockquote></details></ul>");
        let [Block::List { items, .. }] = blocks.as_slice() else {
            panic!("expected a list");
        };
        assert_eq!(items.len(), 2);
        assert!(matches!(items[0].blocks.as_slice(), [Block::Paragraph(..)]));
        assert!(
            matches!(items[1].blocks.as_slice(), [Block::Details { blocks, .. }] if matches!(blocks.as_slice(), [Block::Blockquote(..)]))
        );
    }

    #[test]
    fn html_heading_keeps_quote_and_list_tags_as_inline_content() {
        for source in [
            "<h2>Title <blockquote>q</blockquote></h2>",
            "<h2><ul><li>x</li></ul></h2>",
        ] {
            let blocks = parse(source);
            assert!(
                matches!(blocks.as_slice(), [Block::Heading { .. }]),
                "{source} should stay a single heading"
            );
        }
    }

    #[test]
    fn html_caption_precedes_the_table_and_preserves_inline_styles() {
        let blocks = parse("<blockquote><table><caption>Table <b>A</b></caption><tr><td>cell</td></tr></table></blockquote>");
        let [Block::Blockquote(quoted)] = blocks.as_slice() else {
            panic!("expected a quote");
        };
        let [Block::Paragraph(caption, _), Block::Table { rows, .. }] = quoted.as_slice() else {
            panic!("expected caption then table");
        };
        assert!(
            matches!(caption.as_slice(), [Inline::Text(text), Inline::Styled(crate::ir::StyleKind::Strong, _)] if text == "Table ")
        );
        assert_eq!(rows.len(), 1);
    }

    #[test]
    fn html_caption_stays_out_of_cells_and_closes_at_the_first_row() {
        let blocks = parse("<table><caption>Title\n\nMore\n<tr><td>Cell</td></tr></table>");
        let [Block::Paragraph(caption, _), Block::Table { rows, .. }] = blocks.as_slice() else {
            panic!("expected caption then table");
        };
        let mut text = String::new();
        super::inline_text(caption, &mut text);
        assert_eq!(text, "TitleMore");
        assert!(matches!(rows[0][0].inlines.as_slice(), [Inline::Text(text)] if text == "Cell"));
    }

    #[test]
    fn html_hr_block_is_a_thematic_break() {
        let blocks = parse("a\n\n<hr>\n\nb\n");
        assert!(matches!(
            &blocks[..],
            [
                Block::Paragraph(..),
                Block::ThematicBreak,
                Block::Paragraph(..)
            ]
        ));
        let blocks = parse("<hr/>\ntext\n");
        assert!(matches!(
            &blocks[..],
            [Block::ThematicBreak, Block::Paragraph(..)]
        ));
    }

    #[test]
    fn text_after_an_html_hr_does_not_absorb_the_next_html_block() {
        for source in ["<hr>\nfoo\n\n<p", "<hr>\nfoo\n\n<p>bar</p>"] {
            let blocks = parse(source);
            let paragraphs = blocks
                .iter()
                .filter(|block| matches!(block, Block::Paragraph(..)))
                .count();
            assert_eq!(paragraphs, 2, "{source}");
        }
    }

    #[test]
    fn inline_hr_in_the_middle_of_a_paragraph_is_dropped() {
        let blocks = parse("a <hr> b");
        let [Block::Paragraph(inlines, _)] = &blocks[..] else {
            panic!("expected a paragraph");
        };
        assert!(matches!(&inlines[..], [Inline::Text(text)] if text == "a  b"));
    }

    #[test]
    fn script_and_style_blocks_are_dropped_with_their_content() {
        for source in [
            "<script>\nfirst\n\nsecond\n</script>\n",
            "<style>\nh1 {color:red;}\n\np {color:blue;}\n</style>\n",
            "<script>\nunterminated\n",
            "<SCRIPT type=\"x\">alert(1)</SCRIPT>",
        ] {
            assert!(parse(source).is_empty(), "{source}");
        }
        let blocks = parse("<script>x</script>\n\nafter\n");
        assert!(matches!(&blocks[..], [Block::Paragraph(..)]));
    }

    #[test]
    fn inline_script_and_style_are_dropped_with_their_content() {
        let blocks = parse("a <script>alert(1)</script> b <style>p{}</style>c");
        let [Block::Paragraph(inlines, _)] = &blocks[..] else {
            panic!("expected a paragraph");
        };
        assert!(matches!(
            &inlines[..],
            [Inline::Text(text)] if text == "a  b c"
        ));
    }

    #[test]
    fn pre_block_becomes_a_literal_code_block() {
        assert_eq!(
            code_blocks("<pre>\n**not bold**\n\n  <b>x</b> &lt;y&gt;\n</pre>\n"),
            vec![("**not bold**\n\n  x <y>".to_string(), None)]
        );
    }

    #[test]
    fn pre_code_class_names_the_language() {
        assert_eq!(
            code_blocks("<pre><code class=\"language-rust\">fn main() {}\n</code></pre>"),
            vec![("fn main() {}".to_string(), Some("rust".to_string()))]
        );
        assert_eq!(
            code_blocks("<pre class=\"lang-dart\">var a;</pre>"),
            vec![("var a;".to_string(), Some("dart".to_string()))]
        );
    }

    #[test]
    fn unterminated_leading_pre_keeps_the_text_so_far() {
        assert_eq!(
            code_blocks("<pre>\nline 1\nline 2"),
            vec![("line 1\nline 2".to_string(), None)]
        );
    }

    #[test]
    fn text_after_a_pre_block_is_still_parsed() {
        let blocks = parse("<pre>\ncode\n</pre>\nokay\n");
        assert!(matches!(
            &blocks[..],
            [Block::CodeBlock { .. }, Block::Paragraph(..)]
        ));
    }

    #[test]
    fn textarea_block_is_literal_text() {
        assert_eq!(
            code_blocks("<textarea>\n*foo*\n\n_bar_ &amp;\n</textarea>\n"),
            vec![("*foo*\n\n_bar_ &".to_string(), None)]
        );
    }

    fn table(markdown: &str) -> (Vec<Align>, Vec<Cell>, Vec<Vec<Cell>>) {
        match parse(markdown).into_iter().next() {
            Some(Block::Table {
                alignments,
                header,
                rows,
            }) => (alignments, header, rows),
            _ => panic!("expected a table"),
        }
    }

    fn spans(cells: &[Cell]) -> Vec<(u32, u32)> {
        cells.iter().map(|c| (c.colspan, c.rowspan)).collect()
    }

    #[test]
    fn details_open_attribute_is_read() {
        let open = |source: &str| match &parse(source)[..] {
            [Block::Details { open, .. }] => *open,
            _ => panic!("expected details"),
        };
        assert!(open("<details open><summary>S</summary>\nx\n</details>"));
        assert!(open(
            "<details OPEN=\"\">\n<summary>S</summary>\nx\n</details>"
        ));
        assert!(!open("<details><summary>S</summary>\nx\n</details>"));
    }

    #[test]
    fn colspan_and_rowspan_are_read_with_thead_as_header() {
        let (alignments, header, rows) = table(
            "<table><thead><tr><th colspan=\"2\">H</th></tr></thead>\
             <tbody><tr><td rowspan=\"2\">A</td><td>B</td></tr><tr><td>C</td></tr></tbody></table>",
        );
        assert_eq!(alignments.len(), 2);
        assert_eq!(spans(&header), [(2, 1)]);
        assert_eq!(spans(&rows[0]), [(1, 2), (1, 1)]);
        assert_eq!(spans(&rows[1]), [(1, 1)]);
    }

    #[test]
    fn invalid_spans_are_one_and_large_spans_are_clamped() {
        let (_, _, rows) = table(
            "<table><tr><td colspan=\"0\">a</td><td colspan=\"x\" rowspan=\"-2\">b</td>\
             <td colspan=\"9999\" rowspan=\"500\">c</td><td rowspan=\"0\">d</td></tr></table>",
        );
        // rowspan is also clamped to the table's row count (1).
        assert_eq!(spans(&rows[0]), [(1, 1), (1, 1), (100, 1), (1, 1)]);
    }

    #[test]
    fn column_count_is_the_occupied_width() {
        let (alignments, _, _) =
            table("<table><tr><td colspan=\"3\">w</td></tr><tr><td>1</td><td>2</td></tr></table>");
        assert_eq!(alignments.len(), 3);
        // A column blocked by a rowspan shifts right by the cells in the lower row.
        let (alignments, _, rows) =
            table("<table><tr><td rowspan=\"2\">a</td><td>b</td></tr><tr><td>c</td></tr></table>");
        assert_eq!(alignments.len(), 2);
        assert_eq!(rows[1].len(), 1);
    }

    #[test]
    fn alignment_follows_the_start_column_of_spanned_cells() {
        let (alignments, _, _) =
            table("<table><tr><td colspan=\"2\">x</td><td align=\"right\">y</td></tr></table>");
        assert!(matches!(
            &alignments[..],
            [Align::None, Align::None, Align::Right]
        ));
    }

    #[test]
    fn lists_in_a_cell_become_marked_lines() {
        let (_, _, rows) = table("<table><tr><td>\n\n- one\n- two\n\n</td></tr></table>");
        assert!(matches!(
            &rows[0][0].inlines[..],
            [Inline::Text(a), Inline::LineBreak, Inline::Text(b)]
                if a == "\u{2022} one" && b == "\u{2022} two"
        ));
    }
}

#[cfg(test)]
mod ir_v3_tests {
    use super::parse;
    use crate::ir::{Block, Inline, StyleKind};

    fn paragraph(markdown: &str) -> Vec<Inline> {
        match parse(markdown).into_iter().next() {
            Some(Block::Paragraph(inlines, _)) => inlines,
            _ => panic!("expected a paragraph"),
        }
    }

    fn list_tight(markdown: &str) -> bool {
        match parse(markdown).into_iter().next() {
            Some(Block::List { tight, .. }) => tight,
            _ => panic!("expected a list"),
        }
    }

    fn code(markdown: &str) -> (Option<String>, Option<String>) {
        match parse(markdown).into_iter().next() {
            Some(Block::CodeBlock { language, info, .. }) => (language, info),
            _ => panic!("expected a code block"),
        }
    }

    #[test]
    fn soft_break_is_its_own_inline() {
        assert!(matches!(
            &paragraph("foo\nbar")[..],
            [Inline::Text(a), Inline::SoftBreak, Inline::Text(b)] if a == "foo" && b == "bar"
        ));
    }

    #[test]
    fn soft_break_inside_emphasis_stays_inside() {
        let inlines = paragraph("*a\nb*");
        let [Inline::Styled(StyleKind::Emphasis, children)] = &inlines[..] else {
            panic!("expected emphasis");
        };
        assert!(matches!(
            &children[..],
            [Inline::Text(_), Inline::SoftBreak, Inline::Text(_)]
        ));
    }

    #[test]
    fn hard_break_is_not_a_soft_break() {
        assert!(matches!(
            &paragraph("a\\\nb")[..],
            [Inline::Text(_), Inline::LineBreak, Inline::Text(_)]
        ));
    }

    #[test]
    fn image_alt_text_keeps_a_space_for_a_soft_break() {
        let inlines = paragraph("![a\nb](x.png)");
        assert!(matches!(
            &inlines[..],
            [Inline::Image { alt: Some(alt), .. }] if alt == "a b"
        ));
    }

    #[test]
    fn html_tags_pair_across_a_soft_break() {
        let inlines = paragraph("<b>x\ny</b>");
        let [Inline::Styled(StyleKind::Strong, children)] = &inlines[..] else {
            panic!("expected strong");
        };
        assert!(matches!(
            &children[..],
            [Inline::Text(_), Inline::SoftBreak, Inline::Text(_)]
        ));
        let inlines = paragraph("<b>x\n</b>y");
        assert!(matches!(&inlines[0], Inline::Styled(StyleKind::Strong, _)));
    }

    #[test]
    fn multiline_html_start_tag_is_one_event() {
        let inlines = paragraph("<span\nstyle=\"color:red\">x</span>");
        assert!(matches!(&inlines[..], [Inline::Span(..)]));
    }

    #[test]
    fn autolink_stops_at_a_soft_break() {
        let inlines = paragraph("see https://example.com\nnext");
        assert!(matches!(
            &inlines[..],
            [
                Inline::Text(_),
                Inline::Link { href, .. },
                Inline::SoftBreak,
                Inline::Text(next)
            ] if href == "https://example.com" && next == "next"
        ));
    }

    #[test]
    fn tight_and_loose_lists() {
        assert!(list_tight("- a\n- b\n"));
        assert!(!list_tight("- a\n\n- b\n"));
        assert!(!list_tight("1. a\n\n   b\n2. c\n"));
        assert!(list_tight("- a\n  - b\n  - c\n"));
    }

    #[test]
    fn nested_lists_have_their_own_tightness() {
        let blocks = parse("- a\n  - b\n\n  - c\n- d\n");
        let Block::List { tight, items, .. } = &blocks[0] else {
            panic!("expected a list");
        };
        assert!(*tight);
        let nested = items[0]
            .blocks
            .iter()
            .find_map(|block| match block {
                Block::List { tight, .. } => Some(*tight),
                _ => None,
            })
            .expect("nested list");
        assert!(!nested);
    }

    #[test]
    fn task_list_tightness() {
        assert!(list_tight("- [ ] a\n- [x] b\n"));
        assert!(!list_tight("- [ ] a\n\n- [x] b\n"));
    }

    fn list_checked(markdown: &str) -> Vec<Option<bool>> {
        match parse(markdown).into_iter().next() {
            Some(Block::List { items, .. }) => items
                .iter()
                .map(|item| item.task.map(|task| task.checked))
                .collect(),
            _ => panic!("expected a list"),
        }
    }

    #[test]
    fn loose_task_list_keeps_the_task_state() {
        assert_eq!(
            list_checked("- [ ] a\n\n- [x] b\n\n- c\n"),
            vec![Some(false), Some(true), None]
        );
        assert_eq!(
            list_checked("1. [x] a\n\n   more\n2. [ ] b\n"),
            vec![Some(true), Some(false)]
        );
    }

    #[test]
    fn tight_task_list_keeps_the_task_state() {
        assert_eq!(
            list_checked("- [ ] a\n- [x] b\n- c\n"),
            vec![Some(false), Some(true), None]
        );
    }

    #[test]
    fn nested_task_markers_stay_with_their_own_item() {
        let blocks = parse("- a\n\n  - [x] b\n\n- [ ] c\n");
        let Block::List { items, .. } = &blocks[0] else {
            panic!("expected a list");
        };
        assert_eq!(items[0].task, None);
        assert_eq!(items[1].task.map(|task| task.checked), Some(false));
        let nested = items[0].blocks.iter().find_map(|block| match block {
            Block::List { items, .. } => Some(items),
            _ => None,
        });
        assert_eq!(
            nested.map(|items| items[0].task.map(|task| task.checked)),
            Some(Some(true))
        );
    }

    #[test]
    fn footnote_list_is_loose() {
        let blocks = parse("a[^1]\n\n[^1]: note\n");
        assert!(matches!(
            blocks.last(),
            Some(Block::List { tight: false, .. })
        ));
    }

    #[test]
    fn fence_info_keeps_the_text_after_the_language() {
        assert_eq!(
            code("```rust {1,3} title=\"a b\"\nx\n```"),
            (
                Some("rust".to_string()),
                Some("{1,3} title=\"a b\"".to_string())
            )
        );
        assert_eq!(code("```rust\nx\n```"), (Some("rust".to_string()), None));
        assert_eq!(code("```\nx\n```"), (None, None));
        assert_eq!(code("    x"), (None, None));
        assert_eq!(
            code("```  js   hl=1  \nx\n```"),
            (Some("js".to_string()), Some("hl=1".to_string()))
        );
    }
}

#[cfg(test)]
mod task_marker_tests {
    use super::{parse, parse_to_bytes};
    use crate::ir::{Block, IR_VERSION};

    /// The task items of `blocks` in document order: the check state and the byte range of the marker.
    fn collect(blocks: &[Block], out: &mut Vec<(bool, usize)>) {
        for block in blocks {
            match block {
                Block::Blockquote(inner) => collect(inner, out),
                Block::Details { blocks, .. } => collect(blocks, out),
                Block::List { items, .. } => {
                    for item in items {
                        if let Some(task) = &item.task {
                            out.push((task.checked, task.offset));
                        }
                        collect(&item.blocks, out);
                    }
                }
                _ => {}
            }
        }
    }

    fn tasks(source: &str) -> Vec<(bool, usize)> {
        let mut out = Vec::new();
        collect(&parse(source), &mut out);
        out
    }

    /// The marker text each task points at.
    fn markers(source: &str) -> Vec<&str> {
        tasks(source)
            .into_iter()
            .map(|(_, offset)| &source[offset..offset + 3])
            .collect()
    }

    #[test]
    fn offsets_point_at_the_marker() {
        let source = "- [ ] a\n- [x] b\n- [X] c\n";
        assert_eq!(tasks(source), vec![(false, 2), (true, 10), (true, 18)]);
        assert_eq!(markers(source), vec!["[ ]", "[x]", "[X]"]);
    }

    #[test]
    fn loose_items_keep_the_offset() {
        let source = "- [ ] a\n\n- [x] b\n";
        assert_eq!(markers(source), vec!["[ ]", "[x]"]);
        assert_eq!(tasks(source), vec![(false, 2), (true, 11)]);
    }

    #[test]
    fn nested_quoted_and_ordered_items() {
        let source = "> - [ ] q\n> - [x] r\n\n1. [x] o\n   - [ ] n\n";
        assert_eq!(markers(source), vec!["[ ]", "[x]", "[x]", "[ ]"]);
        assert_eq!(
            tasks(source).iter().map(|t| t.0).collect::<Vec<_>>(),
            vec![false, true, true, false]
        );
    }

    #[test]
    fn offsets_are_byte_offsets_after_multibyte_text() {
        let source = "日本語\n\n- [ ] é\n- [x] 😀\n";
        assert_eq!(tasks(source)[0].1, "日本語\n\n- ".len());
        assert_eq!(markers(source), vec!["[ ]", "[x]"]);
    }

    #[test]
    fn crlf_offsets() {
        let source = "- [ ] a\r\n- [x] b\r\n";
        assert_eq!(markers(source), vec!["[ ]", "[x]"]);
        assert_eq!(tasks(source)[1].1, 11);
    }

    #[test]
    fn a_non_task_item_has_no_offset() {
        assert_eq!(tasks("- a\n- [ ] b\n- c\n").len(), 1);
        assert!(tasks("- [] a\n- [y] b\n").is_empty());
    }

    #[test]
    fn a_marker_inside_a_code_fence_is_not_a_task() {
        assert!(tasks("```\n- [ ] a\n```\n").is_empty());
    }

    #[test]
    fn ir_version_is_six_and_offsets_are_written() {
        assert_eq!(IR_VERSION, 6);
        let bytes = parse_to_bytes("- [x] a").expect("small document");
        assert_eq!(&bytes[4..8], &6u32.to_le_bytes());
        // list tag, ordered, start, tight, item count, checked = true, then the u32 marker offset.
        let list = 8 + 4;
        assert_eq!(bytes[list], 4);
        let item = list + 1 + 1 + 4 + 1 + 4;
        assert_eq!(bytes[item], 2);
        assert_eq!(&bytes[item + 1..item + 5], &2u32.to_le_bytes());
    }
}

#[cfg(test)]
mod media_tests {
    use super::parse;
    use crate::ir::{Block, Inline};

    /// The attributes of a `media` block, or None for any other block.
    fn media(block: &Block) -> Option<Vec<(&str, &str)>> {
        match block {
            Block::Custom {
                kind, attributes, ..
            } if kind == "media" => Some(
                attributes
                    .iter()
                    .map(|(key, value)| (key.as_str(), value.as_str()))
                    .collect(),
            ),
            _ => None,
        }
    }

    /// The attributes of the single `media` block of `source`.
    fn single_media(source: &str) -> Vec<(String, String)> {
        let blocks = parse(source);
        let [block] = blocks.as_slice() else {
            panic!("{source}: expected one block, got {}", blocks.len());
        };
        media(block)
            .unwrap_or_else(|| panic!("{source}: expected a media block"))
            .into_iter()
            .map(|(key, value)| (key.to_string(), value.to_string()))
            .collect()
    }

    fn pairs(expected: &[(&str, &str)]) -> Vec<(String, String)> {
        expected
            .iter()
            .map(|(key, value)| (key.to_string(), value.to_string()))
            .collect()
    }

    /// (href, title, text) of a link.
    fn link(inline: &Inline) -> Option<(&str, Option<&str>, String)> {
        match inline {
            Inline::Link {
                href,
                title,
                children,
            } => Some((href.as_str(), title.as_deref(), text(children))),
            _ => None,
        }
    }

    fn text(inlines: &[Inline]) -> String {
        let mut out = String::new();
        super::inline_text(inlines, &mut out);
        out
    }

    fn has_link(inlines: &[Inline]) -> bool {
        inlines.iter().any(|inline| match inline {
            Inline::Link { .. } => true,
            Inline::Styled(_, children)
            | Inline::Titled(_, _, children)
            | Inline::Span(_, children) => has_link(children),
            _ => false,
        })
    }

    fn paragraph_text(block: &Block) -> String {
        match block {
            Block::Paragraph(inlines, _) => {
                assert!(!has_link(inlines), "unexpected link");
                text(inlines)
            }
            _ => panic!("expected a paragraph"),
        }
    }

    #[test]
    fn video_block_keeps_its_attributes_and_drops_the_fallback_text() {
        let source = "<video src=\"clip.mp4\" poster=\"p.jpg\" width=\"640\" height=\"360\" controls>\nYour browser does not support video.\n</video>";
        let blocks = parse(source);
        let [Block::Custom {
            kind,
            attributes,
            inlines,
            blocks: children,
        }] = blocks.as_slice()
        else {
            panic!("expected one custom block");
        };
        assert_eq!(kind, "media");
        assert_eq!(
            attributes,
            &pairs(&[
                ("kind", "video"),
                ("src", "clip.mp4"),
                ("poster", "p.jpg"),
                ("width", "640"),
                ("height", "360"),
            ])
        );
        assert!(children.is_empty());
        let [fallback] = inlines.as_slice() else {
            panic!("expected one fallback inline");
        };
        assert_eq!(link(fallback), Some(("clip.mp4", None, "clip.mp4".into())));
    }

    #[test]
    fn video_without_src_uses_the_first_source_and_ignores_tracks() {
        let source = "<video controls>\n  <source src=\"a.webm\" type=\"video/webm\">\n  <source src=\"a.mp4\" type=\"video/mp4\">\n  <track src=\"sub.vtt\" kind=\"subtitles\">\n  Fallback text\n</video>";
        assert_eq!(
            single_media(source),
            pairs(&[("kind", "video"), ("src", "a.webm"), ("type", "video/webm")])
        );
    }

    #[test]
    fn a_source_with_an_unsafe_src_is_skipped() {
        let source =
            "<audio>\n<source src=\"javascript:alert(1)\">\n<source src=\"a.ogg\">\n</audio>";
        assert_eq!(
            single_media(source),
            pairs(&[("kind", "audio"), ("src", "a.ogg")])
        );
    }

    #[test]
    fn title_is_the_label_and_the_link_title() {
        let blocks =
            parse("<audio src=\"https://e.com/music/song.mp3\" title=\"Song\" controls></audio>");
        let [Block::Custom {
            attributes,
            inlines,
            ..
        }] = blocks.as_slice()
        else {
            panic!("expected one custom block");
        };
        assert_eq!(
            attributes,
            &pairs(&[
                ("kind", "audio"),
                ("src", "https://e.com/music/song.mp3"),
                ("title", "Song"),
            ])
        );
        assert_eq!(
            link(&inlines[0]),
            Some(("https://e.com/music/song.mp3", Some("Song"), "Song".into()))
        );
    }

    #[test]
    fn label_is_the_decoded_file_name_or_else_the_url() {
        for (src, label) in [
            ("https://e.com/a/song%20one.mp3?x=1#t=10", "song one.mp3"),
            ("https://www.youtube.com/embed/abc", "abc"),
            ("https://e.com/", "https://e.com/"),
            ("https://e.com", "https://e.com"),
            ("clip.mp4#t=5", "clip.mp4"),
            ("a%FF.mp4", "a%FF.mp4"),
        ] {
            let blocks = parse(&format!("<iframe src=\"{src}\"></iframe>"));
            let [Block::Custom { inlines, .. }] = blocks.as_slice() else {
                panic!("{src}: expected one custom block");
            };
            assert_eq!(link(&inlines[0]), Some((src, None, label.into())), "{src}");
        }
        // A blank title falls back to the file name.
        let blocks = parse("<video src=\"v/a.mp4\" title=\"  \"></video>");
        let [Block::Custom { inlines, .. }] = blocks.as_slice() else {
            panic!("expected one custom block");
        };
        assert_eq!(link(&inlines[0]), Some(("v/a.mp4", None, "a.mp4".into())));
    }

    #[test]
    fn iframe_embed_and_object_are_media() {
        assert_eq!(
            single_media("<iframe src=\"https://e.com/embed/x\" width=\"560\" height=\"315\" title=\"Player\" allowfullscreen></iframe>"),
            pairs(&[
                ("kind", "iframe"),
                ("src", "https://e.com/embed/x"),
                ("title", "Player"),
                ("width", "560"),
                ("height", "315"),
            ])
        );
        assert_eq!(
            single_media("<embed src=\"doc.pdf\" type=\"application/pdf\">"),
            pairs(&[
                ("kind", "embed"),
                ("src", "doc.pdf"),
                ("type", "application/pdf")
            ])
        );
        assert_eq!(
            single_media("<object data=\"file.pdf\" type=\"application/pdf\">\n<p>Get <a href=\"file.pdf\">the file</a>.</p>\n</object>"),
            pairs(&[("kind", "object"), ("src", "file.pdf"), ("type", "application/pdf")])
        );
    }

    #[test]
    fn embed_is_void_so_text_after_it_stays() {
        let blocks = parse("<embed src=\"a.pdf\">\nafter text");
        assert_eq!(blocks.len(), 2);
        assert!(media(&blocks[0]).is_some());
        assert_eq!(paragraph_text(&blocks[1]), "after text");
    }

    #[test]
    fn nested_elements_of_the_same_name_close_at_the_matching_tag() {
        let blocks = parse(
            "<object data=\"a.pdf\">\n<object data=\"b.swf\"></object>\nfallback\n</object>\nafter",
        );
        assert_eq!(blocks.len(), 2, "media and the text after it");
        assert_eq!(
            media(&blocks[0]),
            Some(vec![("kind", "object"), ("src", "a.pdf")])
        );
        assert_eq!(paragraph_text(&blocks[1]), "after");
    }

    #[test]
    fn without_a_usable_src_the_tag_is_dropped_and_the_fallback_kept() {
        for (source, expected) in [
            ("<video controls>\nNo video here\n</video>", "No video here"),
            (
                "<object type=\"application/pdf\">\nNo data\n</object>",
                "No data",
            ),
            (
                "<iframe src=\"javascript:alert(1)\">\nframe fallback\n</iframe>",
                "frame fallback",
            ),
            (
                "<video src=\" JaVa\tScRiPt:alert(1)\">\nscript\n</video>",
                "script",
            ),
            ("<embed src=\"vbscript:x\">\nafter", "after"),
            ("<iframe src=\"data:text/html,x\">\ndata\n</iframe>", "data"),
            ("<video src=\"\">\nempty\n</video>", "empty"),
        ] {
            let blocks = parse(source);
            let [block] = blocks.as_slice() else {
                panic!("{source}: expected one block, got {}", blocks.len());
            };
            assert_eq!(paragraph_text(block), expected, "{source}");
        }
    }

    #[test]
    fn an_unsafe_poster_is_dropped() {
        assert_eq!(
            single_media("<video src=\"a.mp4\" poster=\"javascript:x\"></video>"),
            pairs(&[("kind", "video"), ("src", "a.mp4")])
        );
    }

    #[test]
    fn inline_media_is_a_fallback_link_without_its_content() {
        let blocks = parse("Watch <video src=\"clip.mp4\">fallback</video> now");
        let [Block::Paragraph(inlines, _)] = blocks.as_slice() else {
            panic!("expected a paragraph");
        };
        assert_eq!(inlines.len(), 3);
        assert!(matches!(&inlines[0], Inline::Text(text) if text == "Watch "));
        assert_eq!(
            link(&inlines[1]),
            Some(("clip.mp4", None, "clip.mp4".into()))
        );
        assert!(matches!(&inlines[2], Inline::Text(text) if text == " now"));
    }

    #[test]
    fn unclosed_inline_media_drops_the_rest_of_the_paragraph_only() {
        let blocks = parse("a <video src=\"v.mp4\">fallback *x*\n\nnext");
        let [Block::Paragraph(first, _), second] = blocks.as_slice() else {
            panic!("expected two paragraphs");
        };
        assert_eq!(text(first), "a v.mp4");
        assert_eq!(paragraph_text(second), "next");
    }

    #[test]
    fn inline_media_without_a_usable_src_keeps_its_content() {
        let blocks = parse("a <video src=\"javascript:x\">b</video> c");
        let [block] = blocks.as_slice() else {
            panic!("expected one block");
        };
        assert_eq!(paragraph_text(block), "a b c");
    }

    #[test]
    fn a_paragraph_holding_only_media_becomes_a_media_block() {
        assert_eq!(
            single_media("<video src=\"a.mp4\" controls></video>"),
            pairs(&[("kind", "video"), ("src", "a.mp4")])
        );
        assert_eq!(
            single_media("<audio src=\"a.mp3\">fallback</audio>  "),
            pairs(&[("kind", "audio"), ("src", "a.mp3")])
        );
        let blocks = parse("- <video src=\"a.mp4\"></video>\n- text");
        let [Block::List { items, .. }] = blocks.as_slice() else {
            panic!("expected a list");
        };
        assert!(matches!(items[0].blocks.as_slice(), [block] if media(block).is_some()));
    }

    #[test]
    fn table_cell_and_caption_get_the_fallback_link_inline() {
        let blocks = parse("<table><caption><audio src=\"a.mp3\"></audio></caption><tr><td>See <video src=\"b.mp4\">fallback</video></td></tr></table>");
        let [Block::Paragraph(caption, _), Block::Table { rows, .. }] = blocks.as_slice() else {
            panic!("expected a caption paragraph and a table");
        };
        assert_eq!(link(&caption[0]), Some(("a.mp3", None, "a.mp3".into())));
        let cell = &rows[0][0].inlines;
        assert_eq!(text(cell), "See b.mp4");
        assert_eq!(link(&cell[1]), Some(("b.mp4", None, "b.mp4".into())));
    }

    #[test]
    fn media_between_table_rows_is_dropped() {
        let blocks = parse("<table><tr><td>x</td></tr><video src=\"a.mp4\">fb</video></table>");
        let [Block::Table { rows, .. }] = blocks.as_slice() else {
            panic!("expected only a table");
        };
        assert_eq!(rows.len(), 1);
    }

    #[test]
    fn html_heading_gets_the_fallback_link_inline() {
        let blocks = parse("<h2>Clip <video src=\"a.mp4\">fallback</video></h2>");
        let [Block::Heading(2, inlines, _)] = blocks.as_slice() else {
            panic!("expected a heading");
        };
        assert_eq!(text(inlines), "Clip a.mp4");
        assert!(link(&inlines[1]).is_some());
    }

    #[test]
    fn media_goes_inside_html_containers() {
        let blocks =
            parse("<blockquote>\n<p>Intro</p>\n<video src=\"a.mp4\">fb</video>\n</blockquote>");
        let [Block::Blockquote(quoted)] = blocks.as_slice() else {
            panic!("expected a quote");
        };
        assert!(
            matches!(quoted.as_slice(), [Block::Paragraph(..), block] if media(block).is_some())
        );

        let blocks = parse("<ul><li>one <iframe src=\"f.html\"></iframe> two</li></ul>");
        let [Block::List { items, .. }] = blocks.as_slice() else {
            panic!("expected a list");
        };
        let [Block::Paragraph(..), block, Block::Paragraph(..)] = items[0].blocks.as_slice() else {
            panic!("expected text, media, text");
        };
        assert!(media(block).is_some());

        let blocks = parse("<details><summary>S</summary><embed src=\"a.pdf\"></details>");
        let [Block::Details { blocks: inner, .. }] = blocks.as_slice() else {
            panic!("expected details");
        };
        assert!(matches!(inner.as_slice(), [block] if media(block).is_some()));
    }

    #[test]
    fn unclosed_block_media_ends_at_the_end_of_its_html_block() {
        let blocks = parse("<video src=\"a.mp4\">\nfallback\n\nNext paragraph");
        assert_eq!(blocks.len(), 2);
        assert!(media(&blocks[0]).is_some());
        assert_eq!(paragraph_text(&blocks[1]), "Next paragraph");

        let blocks = parse("<video src=\"a.mp4\">\nfallback");
        assert!(matches!(blocks.as_slice(), [block] if media(block).is_some()));

        // The close tag in a later block is ignored.
        let blocks = parse("<video src=\"a.mp4\">\n\nfallback\n\n</video>\n\nafter");
        assert_eq!(blocks.len(), 3);
        assert!(media(&blocks[0]).is_some());
        assert_eq!(paragraph_text(&blocks[1]), "fallback");
        assert_eq!(paragraph_text(&blocks[2]), "after");
    }

    #[test]
    fn media_tags_are_never_shown_as_text() {
        for source in [
            "<video>",
            "</video>",
            "<source src=\"a.mp4\">",
            "<track src=\"a.vtt\">",
            "a </audio> b",
        ] {
            for block in &parse(source) {
                if let Block::Paragraph(inlines, _) = block {
                    assert!(!text(inlines).contains('<'), "{source}");
                }
            }
        }
    }
}
