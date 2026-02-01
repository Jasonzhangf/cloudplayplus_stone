part of floating_shortcut_button;

class _TopRightActions extends StatelessWidget {
  final bool useSystemKeyboard;
  final bool showVirtualMouse;
  final VoidCallback onToggleMouse;
  final VoidCallback onToggleKeyboard;
  final VoidCallback? onPrevIterm2Panel;
  final VoidCallback? onNextIterm2Panel;
  final VoidCallback onDisconnect;
  final VoidCallback onClose;

  const _TopRightActions({
    required this.useSystemKeyboard,
    required this.showVirtualMouse,
    required this.onToggleMouse,
    required this.onToggleKeyboard,
    this.onPrevIterm2Panel,
    this.onNextIterm2Panel,
    required this.onDisconnect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final quick = QuickTargetService.instance;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('shortcutPanelKeyboardToggle'),
            icon: Icon(
              useSystemKeyboard
                  ? Icons.keyboard_alt_outlined
                  : Icons.keyboard_outlined,
            ),
            tooltip: useSystemKeyboard ? '手机键盘' : '电脑键盘',
            onPressed: onToggleKeyboard,
            iconSize: 18,
            padding: const EdgeInsets.all(0),
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            color: Colors.white.withValues(alpha: 0.92),
          ),
          const SizedBox(width: 2),
          IconButton(
            key: const Key('shortcutPanelMouseToggle'),
            icon: Icon(
              showVirtualMouse ? Icons.mouse : Icons.mouse_outlined,
            ),
            tooltip: showVirtualMouse ? '隐藏鼠标' : '显示鼠标',
            onPressed: onToggleMouse,
            iconSize: 18,
            padding: const EdgeInsets.all(0),
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            color: Colors.white.withValues(alpha: 0.92),
          ),
          const SizedBox(width: 2),
          ValueListenableBuilder<StreamMode>(
            valueListenable: quick.mode,
            builder: (context, mode, _) {
              if (mode != StreamMode.iterm2) return const SizedBox.shrink();
              final prev = onPrevIterm2Panel;
              final next = onNextIterm2Panel;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const Key('shortcutPanelPrevIterm2Panel'),
                    icon: const Icon(Icons.chevron_left),
                    tooltip: '上一个面板',
                    onPressed: prev,
                    iconSize: 18,
                    padding: const EdgeInsets.all(0),
                    constraints:
                        const BoxConstraints.tightFor(width: 26, height: 26),
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    key: const Key('shortcutPanelNextIterm2Panel'),
                    icon: const Icon(Icons.chevron_right),
                    tooltip: '下一个面板',
                    onPressed: next,
                    iconSize: 18,
                    padding: const EdgeInsets.all(0),
                    constraints:
                        const BoxConstraints.tightFor(width: 26, height: 26),
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                  const SizedBox(width: 2),
                ],
              );
            },
          ),
          IconButton(
            key: const Key('shortcutPanelDisconnect'),
            icon: const Icon(Icons.link_off),
            tooltip: '断开连接',
            onPressed: onDisconnect,
            iconSize: 18,
            padding: const EdgeInsets.all(0),
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            color: Colors.redAccent.withValues(alpha: 0.95),
          ),
          const SizedBox(width: 2),
          IconButton(
            key: const Key('shortcutPanelClose'),
            icon: const Icon(Icons.close),
            tooltip: '关闭快捷栏',
            onPressed: onClose,
            iconSize: 18,
            padding: const EdgeInsets.all(0),
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            color: Colors.white.withValues(alpha: 0.92),
          ),
        ],
      ),
    );
  }
}
