import 'package:cloudplayplus/models/shortcut.dart';
import 'package:cloudplayplus/utils/shortcut/shortcut_order_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ShortcutItem item(
    String id,
    int order, {
    bool enabled = true,
  }) {
    return ShortcutItem(
      id: id,
      label: id,
      icon: '',
      keys: [ShortcutKey(key: id, keyCode: id)],
      platform: ShortcutPlatform.windows,
      enabled: enabled,
      order: order,
    );
  }

  test('reorder preserves non-visible slot positions', () {
    final shortcuts = [
      item('A', 1, enabled: true),
      item('B', 2, enabled: true),
      item('C', 3, enabled: false), // hidden/non-visible slot
      item('D', 4, enabled: true),
    ];

    final updated = reorderShortcutsPreservingHiddenSlots(
      shortcuts: shortcuts,
      visibleIds: {'A', 'B', 'D'},
      oldVisibleIndex: 2, // D
      newVisibleIndex: 1, // move to be between A and B
    );

    final idsByOrder = (List<ShortcutItem>.from(updated)
          ..sort((a, b) => a.order.compareTo(b.order)))
        .map((s) => s.id)
        .toList();

    // C stays at the same slot (index 2) while visible items reorder around it.
    expect(idsByOrder, ['A', 'D', 'C', 'B']);
  });

  test('reorder supports insert-at-end semantics', () {
    final shortcuts = [
      item('A', 1),
      item('B', 2),
      item('C', 3),
    ];

    final updated = reorderShortcutsPreservingHiddenSlots(
      shortcuts: shortcuts,
      visibleIds: {'A', 'B', 'C'},
      oldVisibleIndex: 0, // A
      newVisibleIndex: 3, // insert at end
    );

    final idsByOrder = (List<ShortcutItem>.from(updated)
          ..sort((a, b) => a.order.compareTo(b.order)))
        .map((s) => s.id)
        .toList();

    expect(idsByOrder, ['B', 'C', 'A']);
  });
}
