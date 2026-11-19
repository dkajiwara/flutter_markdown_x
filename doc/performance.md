# Append performance, slivers, and limits for huge blocks

> **How to read the numbers in this document**: All measurements are of the current implementation (the Rust parser) on macOS desktop in profile mode, taken on 2026-11-16. They are single runs, not statistics over multiple runs. The measurement conditions are collected in ["Measurement conditions"](#measurement-conditions) below.

## Summary

- `SliverMarkdown` can be placed alongside other slivers in a parent `CustomScrollView`. `Markdown` uses `CustomScrollView` + `SliverMarkdown` internally, so parsing, caching, State preservation, and table-of-contents navigation (including unbuilt blocks) share the same implementation.
- Appending (streaming) has a fast path. If the new document only appends to the end of the previous one, it resumes from the previous scan state and carries over the results of settled chunks and the widget entries. The number of characters scanned and parsed in one update does not depend on the size of the document; it is determined by the last line and the size of the open chunk.
- The measured values below were taken on macOS desktop in profile mode. They are not values from a real smartphone.
- We measured the limits for huge single blocks. Only huge code blocks are split for rendering (a 10,000-line block takes about 0.4 seconds for its first frame). Lists and tables are not built lazily within a block, so we give their limits as numbers.

## SliverMarkdown

```dart
CustomScrollView(slivers: [
  SliverAppBar(title: Text('Chat')),
  SliverPadding(
    padding: EdgeInsets.all(16),
    sliver: SliverMarkdown(
      data: reply,
      streaming: true,
      markdownController: controller,
    ),
  ),
  SliverToBoxAdapter(child: Footer()),
])
```

- The arguments are the same as `MarkdownWidget` (everything `Markdown` takes) minus the scroll-related ones (`padding`, `controller`, `physics`, `shrinkWrap`, `selectable`). Add padding with `SliverPadding`. `SliverMarkdown` has no flutter_markdown equivalent.
- Each top-level block is built lazily with `SliverList.builder`. The block key (the occurrence token) is passed to `findChildIndexCallback`, so State such as details does not shift on insertion at the start or on reordering.
- `markdownController.jumpToAnchor` moves the parent `Scrollable`. Even if the target is unbuilt, it approaches it by estimating an offset from the positions of built blocks. It also works when another sliver comes first, because the estimate uses an offset relative to `RenderAbstractViewport`.
- `Markdown` follows flutter_markdown: `padding` defaults to `EdgeInsets.all(16)`, and `Markdown` is a `StatelessWidget` over the inner `SliverMarkdown`, which holds the State.
- `MarkdownBody` remains a non-scrolling widget and builds every block at once.

## flutter_markdown-style call sites keep the cache

flutter_markdown apps build the style sheet, the `builders` map, and the callbacks inside `build()`. Here that does not rebuild unchanged blocks: `MarkdownStyleSheet` has value equality, callbacks and render closures are read through a relay on the widget, and `builders` / `paddingBuilders` invalidate only by their key set and runtime types ([flutter_markdown_compat.md](flutter_markdown_compat.md#4f-cache-invalidation-with-flutter_markdown-style-call-sites)). `test/flutter_markdown/cache_test.dart` rebuilds a parent ten times with a fresh `fromTheme(...).copyWith(...)` sheet, a new `code` builder, a new padding builder, and new closures, and asserts that builders run once per `code` element and that no block rebuilds; appending a paragraph builds only the new block.

The profile-mode numbers below use the flutter_markdown-compatible widget API (`Markdown` / `SliverMarkdown`, `MarkdownStyleSheet`). The "flutter_markdown call site" rows in the frame-time table measure the call site described above: the parent rebuilds on every append with an inline `MarkdownStyleSheet.fromTheme(Theme.of(context))` and an inline `builders` map, and frame times stay flat.

## Fast path for appending

### Design

A naive update would scan the whole document, rebuild every chunk string, reorganize the cache of all chunks, and rebuild the list of all blocks and the widget entries. The fast path instead works as follows.

| Layer | Work when appending |
|---|---|
| Check | Verify that the new document starts with the previous document by comparing against the whole previous document (memcmp; see the remainder below) |
| Scan | Resume from the state just before the previous last line (open fence, HTML depth, definition count, and so on). The number of characters scanned is from the last line onward |
| Chunk | Carry over settled chunks and their blocks in place. Rebuild only the open chunk at the end |
| Parse | Pass only the last chunk to the parser. Rebuild all chunks only when the link reference definitions change |
| Widget | Keep entries and indexes within the range of `reusedBlockPrefix` (the number of leading blocks that are the same instances as before) returned by the parser, and reconcile only the tail |

The scan is a state machine that proceeds from start to end, and the handling of a line is determined only by "the state before that line" and "that line". So resuming from the state just before the previous last line (which may be incomplete) matches the result of scanning the whole document. Tests confirm that this matches rescanning the whole text on every append (see below).

In the following cases the fast path is not used and all chunks are handled together (the result always matches a full parse).

- Updates that are not appends (edits in the middle, shrinking, full replacement).
- A change of extensions.
- Documents where link reference definitions or footnotes (`[^1]:`) cannot be safely split out, HTML comments, and documents containing `<?` (the whole document is parsed).
- When link reference definitions are added or removed (all chunks are rebuilt, supplemented with the new definitions). An append that does not change the definitions stays on the fast path.

### The work is bounded

`IncrementalMarkdownParser` counts the characters scanned (`debugScannedChars`) and the characters passed to the parser (`debugParsedChars`) (for measurement and tests; not public API). `flutter test benchmark/append_work_benchmark_test.dart` outputs the maximum over 100 appends at various document sizes. One append is about 60 characters, and a paragraph settles every 10 appends.

| Sections | Document characters | Characters scanned per append (max) | Characters passed to parse per append (max) | Characters in the document (a full scan) |
|---:|---:|---:|---:|---:|
| 20 | 12,592 | 502 | 502 | 12,592 |
| 100 | 43,152 | 502 | 502 | 43,152 |
| 500 | 199,552 | 502 | 502 | 199,552 |
| 2,500 | 995,052 | 502 | 502 | 995,052 |

Even when the document grows about 80 times, the work per append stays at 502 characters (determined by the size of the open paragraph). `test/parser/incremental_append_test.dart` asserts that the scan and parse character counts do not grow even when the document grows 20 times.

### Remaining O(n) work

- The check for whether it is an append compares against the whole previous document (memcmp), which is proportional to the document size. About 80 microseconds at 400 KB.
- The parser copies and returns the result list (a pointer copy proportional to the block count).
- When a `markdownController` is attached, the table-of-contents index is rebuilt on every update (it scans all blocks).
- When one chunk is huge (for example, in the middle of one long code fence), that whole chunk is parsed every time. Only the scan resumes from the last line.

### Measurements (profile mode, macOS desktop)

Time per append for the parser alone (synchronous), average. We measure `IncrementalMarkdownParser.parse(..., streaming: true)` by appending 60 characters to the document 200 times.

| Document characters | Time per append (average) |
|---:|---:|
| 20,000 | 0.04 ms |
| 100,000 | 0.09 ms |
| 400,000 | 0.21 ms |

The time stays under 0.3 ms even at 400,000 characters. The remaining growth comes from the memcmp above and GC.

Whole widget (a `Markdown` that follows the bottom, `streaming: true`, 200 appends). Frame times are the build, raster, and totalSpan from `FrameTiming`, with one append per frame.

| Document characters | Call site | Frames | Build avg / p90 / max (ms) | Raster avg / p90 / max (ms) | Total p90 / p99 / max (ms) | Frames over 16.7 ms |
|---:|---|---:|---|---|---|---:|
| 20,000 | Default style sheet | 251 | 0.82 / 1.35 / 2.04 | 0.55 / 0.83 / 3.54 | 2.08 / 2.62 / 5.09 | 0 |
| 100,000 | Default style sheet | 242 | 1.23 / 1.81 / 5.18 | 0.78 / 1.14 / 3.05 | 2.69 / 5.00 / 8.29 | 0 |
| 400,000 | Default style sheet | 238 | 0.70 / 1.03 / 4.09 | 0.48 / 0.86 / 5.03 | 1.66 / 6.34 / 6.85 | 0 |
| 20,000 | flutter_markdown call site | 276 | 0.72 / 1.39 / 3.40 | 0.52 / 0.85 / 3.79 | 2.18 / 3.27 / 5.34 | 0 |
| 100,000 | flutter_markdown call site | 238 | 1.02 / 1.73 / 2.91 | 0.55 / 0.81 / 2.24 | 2.62 / 3.50 / 3.59 | 0 |
| 400,000 | flutter_markdown call site | 238 | 0.61 / 0.78 / 6.39 | 0.39 / 0.69 / 1.76 | 1.35 / 2.42 / 7.55 | 0 |

"Default style sheet" is `Markdown` with the default style sheet. "flutter_markdown call site" is the same widget where the parent is rebuilt on every append (`setState`) and creates `MarkdownStyleSheet.fromTheme(Theme.of(context))` and a `builders: {'code': ...}` map inline; the cache rules (value equality for the style sheet, key set and runtime types for builders) keep it equal to the default call site: averages and p90 are the same or lower at every size, and no frame exceeds 16.7 ms. The worst-frame and p99 values at 400,000 characters (6 to 7.5 ms) are single frames out of about 240 (p90 stayed at 1.7 ms or lower) and stay well under one frame (16.7 ms). Tail values vary between runs, so treat them as indicative only.

For appends to a 400,000-character document (about 1,500 sections), the average build time is 0.6 to 0.7 ms and the worst frame is under 8 ms.

Memory (`ProcessInfo.currentRss`, before appending → after 200 appends), default style sheet: 20,000 characters 166 → 161 MB, 100,000 characters 198 → 200 MB, 400,000 characters 584 → 131 MB (the "before" value includes memory from the earlier case waiting to be released). The flutter_markdown call site: 144 → 147 MB, 251 → 231 MB, 379 → 357 MB. No RSS growth from appending was observed (within the range of fluctuation from GC timing). The process peak (maxRss) for the 400,000-character case was 611 to 614 MB; it includes the effect of scenarios run earlier in the same process.

### Measurement conditions

- Machine: Apple M5 (`sysctl -n machdep.cpu.brand_string`), 24 GB of memory, macOS 27.0 (Build 26A428), 10 logical CPUs. Measured on 2026-11-16.
- Flutter 3.47.5 (stable), Dart 3.13.4. `flutter run --profile -d macos` (AOT, profile mode).
- The parser is the Rust implementation.
- The document is `buildDocument` in `benchmark/document.dart` (a repetition of headings, paragraphs, lists, code, tables, and quotes). One section is about 400 characters and 6 blocks.
- Appends are 60 characters at a time, 200 times (assuming a few tokens received at a time). Like a chat, it calls `jumpTo` to the bottom on each append.
- The commands to run are in "How to reproduce" below. 
- These are values from a single run, not statistics over multiple runs; tails (worst frame, p99) and single-shot parse times vary by tens of percent or more between runs. The frame count includes dropped callbacks and is around 220-280.
- We measured macOS desktop, not a real smartphone. The iOS simulator does not support profile mode, so it cannot be measured. Smartphone CPUs and GPUs are slower than a desktop, so treat absolute values only as a guide, and look at how time grows with document size.
- Frame times use the `FrameTiming` values. `appendToFrameEndMs` (wall-clock time from setState to the end of the frame) is not published, because it is distorted when the window is not in front.

### How to reproduce

```sh
cd example
flutter run --profile -d macos -t ../benchmark/profile_app.dart \
  --dart-define=MDX_BENCH_SCENARIOS=stream,stream-compat,blocks
```

`stream-compat` is the flutter_markdown-style call site (parent rebuilt on every append with an inline style sheet and builders map). If the window is not in front (`Failed to foreground app`), frames stop and the run stalls; bring the app to the front (for example with `osascript`) to let it continue.

The results are printed to standard output as `MDX_BENCH {json}` lines, and the app exits when finished. `MDX_BENCH_SCALE=small` switches to smaller sizes. The amount of work (character counts) can be reproduced with `flutter test benchmark/append_work_benchmark_test.dart`.

## Task list offsets and the cache

Making task checkboxes interactive needs the position of each `[ ]` marker in the source, but a position changes whenever text is inserted before the block, and the block cache is keyed by value. So the positions are kept out of equality:

- The Rust parser reports the byte offset of the marker in the IR. The decoder turns it into a UTF-16 offset in the text that was parsed (`MdxListItem.markerOffset`, **not** part of `==` / `hashCode`).
- `IncrementalMarkdownParser` stores the offset relative to the chunk (subtracting the definitions put in front of it). A chunk is cached by its text, so the cached blocks stay valid wherever the chunk moves. When a source transform (math, alerts, mermaid) or the streaming repair changed the chunk, the original chunk text is parsed once more to get exact marker positions, and the two task lists are paired in order (only chunks that contain `[ ]`, `[x]` or `[X]` pay this).
- The absolute position is resolved at tap time: the State finds the top-level block of the tapped checkbox, takes the task from the newest parse (the widget of a block can be older than the block) and adds `blockSourceStart`, the current start of the block's chunk.

So inserting text before a task list rebuilds nothing but the new blocks, and the next tap still reports the right offsets (`test/tasks/task_widget_test.dart`).

## Limits for huge single blocks

Lazy building is per top-level block. Inside one block (list items, table rows, code lines), everything is built together when that block is built. The values below are for giving `Markdown` a document consisting of a single block (macOS desktop, profile, same conditions as above). "Worst frame" is the `FrameTiming.totalSpan` of the frame (build + raster) right after the content is given. For frames after the first (scrolling), the p90 was 2 to 4 ms at every size.

| Block | Size | Markdown characters | Parse | Worst frame | RSS (before → after) |
|---|---:|---:|---:|---:|---|
| list (emphasis and inline code in each item) | 1,000 items | 35,889 | 5.6 ms | 90.0 ms | 206 → 257 MB |
| list | 5,000 items | 183,889 | 23.8 ms | 311 ms | 249 → 478 MB |
| list | 20,000 items | 748,889 | 56.6 ms | 1,193 ms | 119 → 1,294 MB |
| table (4 columns) | 250 rows | 10,057 | 2.6 ms | 69.9 ms | (see below) |
| table | 1,000 rows | 41,557 | 4.0 ms | 105 ms | 158 → 296 MB |
| table | 3,000 rows | 133,128 | 20.7 ms | 264 ms | 294 → 606 MB |
| code (dart, about 60 characters per line) | 1,000 lines | 59,571 | 0.35 ms | 68.7 ms | 593 → 631 MB |
| code | 10,000 lines | 635,571 | 5.8 ms | 393 ms | 530 → 834 MB |
| code | 50,000 lines | 3,355,571 | 23.5 ms | 1,778 ms | 795 → 1,833 MB |

Worst-frame values were measured on 2026-11-16. The parse and RSS columns are single-shot values from a separate run under the same conditions. The single-shot `parseMs` values vary by several times between runs (for example code 1,000 lines: 7.5 ms and 0.95 ms; GC from the previous case lands in it), and the 50,000-line code case varies between about 1.7 and 2.4 seconds in the worst frame, so read these as rough guides.

RSS is affected by memory from the previous scenario waiting to be released, so read it only as a rough guide to the increment (we omit it for the 250-row table because the release of the preceding 20,000-item list overlapped and made it appear to fall from 1,276 to 155 MB).

### Limits we decided on

- **Code block**: Laying out the whole text in a single `Text` grows close to the square of the line count, so a code block exceeding `MarkdownXDefaults.codeChunkLines` (200) lines is split into `Text` widgets of 200 lines each, stacked vertically. Line height and color are the same as without splitting. It takes about 0.4 seconds at 10,000 lines and 1.8 seconds at 50,000 lines (layout is proportional to the line count). The time for syntax coloring is small (32 ms for 10,000 lines / 635,571 characters, measured with JIT), so we set no limit for coloring.
- **Table**: Even with `IntrinsicColumnWidth` unchanged, time grew linearly at about 0.15 ms per row up to 3,000 rows (4 columns). We did not change the column-width approach. The guideline is up to 1,000 rows (worst frame about 160 ms). Beyond that, split it up or use your own display through `blockBuilder`.
- **List**: It uses about 0.06 to 0.1 ms and about 50 to 60 KB of RSS per item. The guideline is up to 1,000 items (worst frame about 100 ms). It reaches 0.33 seconds at 5,000 items, and 1.3 seconds and about 1.2 GB at 20,000 items. We have not implemented lazy building inside a block (it would need to stay consistent with nested lists, anchors, and the State of details). For a long list, splitting it into multiple blocks with blank lines and headings lets the lazy building per top-level block take effect.
- These numbers are desktop values. On a smartphone the same block takes longer and memory is tighter.

## Verification

- `test/parser/incremental_append_test.dart`: confirms that the fast path result matches a full parse. It covers fences, HTML, lists, tables, link reference definitions, footnotes, HTML comments and `<?`, the benchmark document, and the example samples, with one-character appends and random-width appends, with and without `streaming`. It also checks mixes of appends with edits, shrinking, and full replacement, reuse of settled block instances, the bound on the amount of work (it does not grow when the document grows 20 times), and the fallback when definitions are added.
- `test/widgets/sliver_markdown_test.dart`: lazy building alongside other slivers, the State of details and scroll position on append, insertion at the start, `jumpToAnchor` to an unbuilt heading, `#id` links, `streaming`, and `Markdown` padding compatibility.
- `test/widgets/code_block_chunk_test.dart`: splitting of huge code blocks, and that the content does not change.
- Disabling the append fast path (`canResume` always false) makes the work-amount test and the instance-reuse test fail.
