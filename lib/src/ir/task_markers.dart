/// Helpers over the task list items of the IR: where they are, and where their markers sit.
///
/// A task item is a [MdxListItem] whose `checked` is non-null. Items are visited in document
/// order: a list item before the items of the lists inside it. Nothing here depends on Flutter.
library;

import 'nodes.dart';

/// Calls [visit] for every task item of [blocks], in document order.
void mdxVisitTaskItems(
  Iterable<MdxBlock> blocks,
  void Function(MdxListItem item) visit,
) {
  for (final block in blocks) {
    switch (block) {
      case MdxBlockquote():
        mdxVisitTaskItems(block.blocks, visit);
      case MdxDetails():
        mdxVisitTaskItems(block.blocks, visit);
      case MdxCustomBlock():
        mdxVisitTaskItems(block.blocks, visit);
      case MdxList():
        for (final item in block.items) {
          if (item.checked != null) visit(item);
          mdxVisitTaskItems(item.blocks, visit);
        }
      case MdxParagraph() ||
          MdxHeading() ||
          MdxCodeBlock() ||
          MdxTable() ||
          MdxThematicBreak():
        break;
    }
  }
}

/// The task items of [blocks] in document order.
List<MdxListItem> mdxTaskItems(Iterable<MdxBlock> blocks) {
  final items = <MdxListItem>[];
  mdxVisitTaskItems(blocks, items.add);
  return items;
}

/// The number of task items in [blocks].
int mdxTaskCount(Iterable<MdxBlock> blocks) {
  var count = 0;
  mdxVisitTaskItems(blocks, (_) => count++);
  return count;
}

/// The position among the task items of [blocks] of [item] (by identity, else by value), or -1.
int mdxTaskOrdinal(Iterable<MdxBlock> blocks, MdxListItem item) {
  final items = mdxTaskItems(blocks);
  final byIdentity = items.indexWhere(
    (candidate) => identical(candidate, item),
  );
  return byIdentity >= 0 ? byIdentity : items.indexOf(item);
}

/// Returns [blocks] with the marker offset of the [i]-th task item replaced by `offsets[i]`.
///
/// [offsets] must have one entry per task item of [blocks] (a null entry marks an unknown
/// position). Unchanged subtrees keep their instances, so cached blocks stay identical.
List<MdxBlock> mdxWithTaskOffsets(List<MdxBlock> blocks, List<int?> offsets) =>
    _Offsetter(offsets).blocks(blocks);

final class _Offsetter {
  _Offsetter(this._offsets);

  final List<int?> _offsets;
  int _next = 0;

  List<MdxBlock> blocks(List<MdxBlock> list) {
    List<MdxBlock>? out;
    for (var i = 0; i < list.length; i++) {
      final mapped = block(list[i]);
      if (out == null && !identical(mapped, list[i])) {
        out = list.sublist(0, i);
      }
      out?.add(mapped);
    }
    return out ?? list;
  }

  MdxBlock block(MdxBlock block) {
    switch (block) {
      case MdxBlockquote():
        final inner = blocks(block.blocks);
        return identical(inner, block.blocks) ? block : MdxBlockquote(inner);
      case MdxDetails():
        final inner = blocks(block.blocks);
        return identical(inner, block.blocks)
            ? block
            : MdxDetails(
                summary: block.summary,
                blocks: inner,
                open: block.open,
              );
      case MdxCustomBlock():
        final inner = blocks(block.blocks);
        return identical(inner, block.blocks)
            ? block
            : MdxCustomBlock(
                block.type,
                attributes: block.attributes,
                inlines: block.inlines,
                blocks: inner,
              );
      case MdxList():
        var changed = false;
        final items = <MdxListItem>[];
        for (final item in block.items) {
          // The item's own marker comes before the items inside it.
          final offset = item.checked == null
              ? item.markerOffset
              : _offsets[_next++];
          final inner = blocks(item.blocks);
          if (offset == item.markerOffset && identical(inner, item.blocks)) {
            items.add(item);
          } else {
            changed = true;
            items.add(
              MdxListItem(inner, checked: item.checked, markerOffset: offset),
            );
          }
        }
        return changed
            ? MdxList(
                ordered: block.ordered,
                start: block.start,
                tight: block.tight,
                items: items,
              )
            : block;
      case MdxParagraph() ||
          MdxHeading() ||
          MdxCodeBlock() ||
          MdxTable() ||
          MdxThematicBreak():
        return block;
    }
  }
}
