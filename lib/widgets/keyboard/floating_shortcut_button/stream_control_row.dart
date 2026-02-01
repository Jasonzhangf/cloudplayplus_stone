part of floating_shortcut_button;

class _StreamControlRow extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPickMode;
  final VoidCallback onPickModeAndTarget;
  final VoidCallback onPickTarget;
  final VoidCallback onQuickNextScreen;
  final ValueChanged<QuickStreamTarget> onApplyFavorite;
  final VoidCallback onAddFavorite;
  final void Function(int slot, _FavoriteAction action) onFavoriteAction;

  const _StreamControlRow({
    required this.enabled,
    required this.onPickMode,
    required this.onPickModeAndTarget,
    required this.onPickTarget,
    required this.onQuickNextScreen,
    required this.onApplyFavorite,
    required this.onAddFavorite,
    required this.onFavoriteAction,
  });

  @override
  Widget build(BuildContext context) {
    final quick = QuickTargetService.instance;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PillButton(
            icon: Icons.movie_filter,
            label: '模式',
            enabled: enabled,
            onTap: onPickMode,
          ),
          const SizedBox(width: 4),
          ValueListenableBuilder<StreamMode>(
            valueListenable: quick.mode,
            builder: (context, mode, _) {
              final label = mode == StreamMode.desktop
                  ? '桌面'
                  : mode == StreamMode.window
                      ? '窗口'
                      : 'iTerm2';
              return _PillButton(
                icon: mode == StreamMode.desktop
                    ? Icons.desktop_windows
                    : mode == StreamMode.window
                        ? Icons.window
                        : Icons.terminal,
                label: label,
                enabled: enabled,
                onTap: onPickModeAndTarget,
              );
            },
          ),
          const SizedBox(width: 4),
          _PillButton(
            icon: Icons.list_alt,
            label: '选择',
            enabled: enabled,
            onTap: onPickTarget,
          ),
          const SizedBox(width: 4),
          ValueListenableBuilder<StreamMode>(
            valueListenable: quick.mode,
            builder: (context, mode, _) {
              if (mode != StreamMode.desktop) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PillButton(
                    icon: Icons.monitor,
                    label: '切屏',
                    enabled: enabled,
                    onTap: onQuickNextScreen,
                  ),
                  const SizedBox(width: 4),
                ],
              );
            },
          ),
          ValueListenableBuilder<List<QuickStreamTarget?>>(
            valueListenable: quick.favorites,
            builder: (context, favorites, _) {
              final entries = <(int slot, QuickStreamTarget target)>[];
              for (int i = 0; i < favorites.length; i++) {
                final t = favorites[i];
                if (t == null) continue;
                entries.add((i, t));
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<QuickStreamTarget?>(
                    valueListenable: quick.lastTarget,
                    builder: (context, current, __) {
                      bool isSame(QuickStreamTarget a, QuickStreamTarget b) {
                        if (a.mode != b.mode) return false;
                        if (a.windowId != null || b.windowId != null) {
                          return a.windowId != null &&
                              b.windowId != null &&
                              a.windowId == b.windowId;
                        }
                        return a.id == b.id;
                      }

                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final e in entries) ...[
                            _FavoriteButton(
                              slot: e.$1,
                              target: e.$2,
                              enabled: enabled,
                              selected: current != null && isSame(current, e.$2),
                              onTap: () => onApplyFavorite(e.$2),
                              onLongPress: () => _showFavoriteMenu(
                                context,
                                slot: e.$1,
                                onAction: onFavoriteAction,
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                        ],
                      );
                    },
                  ),
                  _IconPillButton(
                    icon: Icons.add,
                    enabled: enabled,
                    tooltip: '添加快捷切换（在列表里长按保存）',
                    onTap: onAddFavorite,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static void _showFavoriteMenu(
    BuildContext context, {
    required int slot,
    required void Function(int slot, _FavoriteAction action) onAction,
  }) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('编辑名称'),
                onTap: () {
                  Navigator.pop(context);
                  onAction(slot, _FavoriteAction.rename);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('删除快捷'),
                onTap: () {
                  Navigator.pop(context);
                  onAction(slot, _FavoriteAction.delete);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
