part of floating_shortcut_button;

class _FavoriteButton extends StatelessWidget {
  final int slot;
  final QuickStreamTarget? target;
  final bool enabled;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _FavoriteButton({
    required this.slot,
    required this.target,
    required this.enabled,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final label = target?.shortDisplayLabel() ?? '快捷';
    return InkWell(
      onTap: enabled ? onTap : null,
      onLongPress: enabled ? onLongPress : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: selected
              ? Colors.blueAccent.withValues(alpha: enabled ? 0.35 : 0.18)
              : Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(10),
          border: selected
              ? Border.all(
                  color: Colors.white.withValues(alpha: 0.40),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star,
              size: 12,
              color: selected
                  ? Colors.amber.withValues(alpha: enabled ? 1.0 : 0.55)
                  : Colors.amber.withValues(alpha: enabled ? 0.95 : 0.45),
            ),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 64),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(
                      alpha: enabled ? (selected ? 1.0 : 0.92) : 0.45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrowRow extends StatelessWidget {
  final ShortcutItem? left;
  final ShortcutItem? up;
  final ShortcutItem? down;
  final ShortcutItem? right;
  final ValueChanged<ShortcutItem> onShortcutPressed;

  const _ArrowRow({
    required this.left,
    required this.up,
    required this.down,
    required this.right,
    required this.onShortcutPressed,
  });

  @override
  Widget build(BuildContext context) {
    Widget buildKey(String label, ShortcutItem? shortcut) {
      return InkWell(
        onTap: shortcut == null ? null : () => onShortcutPressed(shortcut),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(
                alpha: shortcut == null ? 0.25 : 0.92,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        buildKey('←', left),
        const SizedBox(width: 4),
        buildKey('↑', up),
        const SizedBox(width: 4),
        buildKey('↓', down),
        const SizedBox(width: 4),
        buildKey('→', right),
      ],
    );
  }
}
