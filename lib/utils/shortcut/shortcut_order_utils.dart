import '../../models/shortcut.dart';

/// Reorders shortcuts by moving a "visible" shortcut from [oldVisibleIndex] to
/// [newVisibleIndex], while keeping non-visible shortcuts in their relative
/// positions.
///
/// This is useful for reordering the horizontal shortcut bar where only a
/// subset (e.g. enabled shortcuts excluding arrows) is shown.
List<ShortcutItem> reorderShortcutsPreservingHiddenSlots({
  required List<ShortcutItem> shortcuts,
  required Set<String> visibleIds,
  required int oldVisibleIndex,
  required int newVisibleIndex,
}) {
  if (oldVisibleIndex == newVisibleIndex) {
    return _renumberOrders(shortcuts);
  }

  final sorted = List<ShortcutItem>.from(shortcuts)
    ..sort((a, b) => a.order.compareTo(b.order));

  final visibleIndices = <int>[];
  for (int i = 0; i < sorted.length; i++) {
    if (visibleIds.contains(sorted[i].id)) {
      visibleIndices.add(i);
    }
  }

  if (visibleIndices.isEmpty) return _renumberOrders(sorted);
  if (oldVisibleIndex < 0 || oldVisibleIndex >= visibleIndices.length) {
    return _renumberOrders(sorted);
  }

  final clampedNew =
      newVisibleIndex.clamp(0, visibleIndices.length) as int; // allow == len
  final visible = [for (final idx in visibleIndices) sorted[idx]];

  int insertAt = clampedNew;
  if (insertAt > oldVisibleIndex) insertAt -= 1;

  final moved = visible.removeAt(oldVisibleIndex);
  visible.insert(insertAt.clamp(0, visible.length), moved);

  for (int j = 0; j < visibleIndices.length; j++) {
    sorted[visibleIndices[j]] = visible[j];
  }

  return _renumberOrders(sorted);
}

List<ShortcutItem> _renumberOrders(List<ShortcutItem> items) {
  final updated = <ShortcutItem>[];
  for (int i = 0; i < items.length; i++) {
    updated.add(items[i].copyWith(order: i + 1));
  }
  return updated;
}
