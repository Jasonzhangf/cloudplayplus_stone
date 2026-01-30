/// 快捷键平台类型
enum ShortcutPlatform {
  windows,
  macos,
  linux,
}

/// 快捷键按键
class ShortcutKey {
  final String key;
  final String keyCode;

  ShortcutKey({required this.key, required this.keyCode});

  Map<String, dynamic> toJson() => {'key': key, 'keyCode': keyCode};

  factory ShortcutKey.fromJson(Map<String, dynamic> json) => ShortcutKey(
        key: json['key'] as String,
        keyCode: json['keyCode'] as String,
      );
}

/// 快捷键配置项
class ShortcutItem {
  final String id;
  final String label;
  final String icon;
  final List<ShortcutKey> keys;
  final ShortcutPlatform platform;
  final bool enabled;
  final int order;

  ShortcutItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.keys,
    required this.platform,
    this.enabled = true,
    required this.order,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'icon': icon,
        'keys': keys.map((k) => k.toJson()).toList(),
        'platform': platform.name,
        'enabled': enabled,
        'order': order,
      };

  factory ShortcutItem.fromJson(Map<String, dynamic> json) => ShortcutItem(
        id: json['id'] as String,
        label: json['label'] as String,
        icon: json['icon'] as String,
        keys: (json['keys'] as List)
            .map((k) => ShortcutKey.fromJson(k as Map<String, dynamic>))
            .toList(),
        platform: ShortcutPlatform.values.firstWhere(
          (p) => p.name == json['platform'] as String,
          orElse: () => ShortcutPlatform.windows,
        ),
        enabled: json['enabled'] as bool? ?? true,
        order: json['order'] as int? ?? 0,
      );

  ShortcutItem copyWith({
    String? id,
    String? label,
    String? icon,
    List<ShortcutKey>? keys,
    ShortcutPlatform? platform,
    bool? enabled,
    int? order,
  }) =>
      ShortcutItem(
        id: id ?? this.id,
        label: label ?? this.label,
        icon: icon ?? this.icon,
        keys: keys ?? this.keys,
        platform: platform ?? this.platform,
        enabled: enabled ?? this.enabled,
        order: order ?? this.order,
      );
}

/// 快捷键设置
class ShortcutSettings {
  final ShortcutPlatform currentPlatform;
  final List<ShortcutItem> shortcuts;

  ShortcutSettings({
    this.currentPlatform = ShortcutPlatform.windows,
    List<ShortcutItem>? shortcuts,
  }) : shortcuts = shortcuts ?? getDefaultShortcuts(currentPlatform);

  Map<String, dynamic> toJson() => {
        'currentPlatform': currentPlatform.name,
        'shortcuts': shortcuts.map((s) => s.toJson()).toList(),
      };

  factory ShortcutSettings.fromJson(Map<String, dynamic> json) {
    final platformName = json['currentPlatform'] as String? ?? 'windows';
    final platform = ShortcutPlatform.values.firstWhere(
      (p) => p.name == platformName,
      orElse: () => ShortcutPlatform.windows,
    );
    return ShortcutSettings(
      currentPlatform: platform,
      shortcuts: (json['shortcuts'] as List?)
              ?.map((s) => ShortcutItem.fromJson(s as Map<String, dynamic>))
              .toList() ??
          getDefaultShortcuts(platform),
    );
  }

  ShortcutSettings copyWith({
    ShortcutPlatform? currentPlatform,
    List<ShortcutItem>? shortcuts,
  }) =>
      ShortcutSettings(
        currentPlatform: currentPlatform ?? this.currentPlatform,
        shortcuts: shortcuts ?? this.shortcuts,
      );

  /// 获取当前平台的快捷键列表（按顺序排序，仅启用的）
  List<ShortcutItem> get enabledShortcuts =>
      shortcuts.where((s) => s.enabled).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
}

/// 获取平台的显示名称
String getPlatformDisplayName(ShortcutPlatform platform) {
  switch (platform) {
    case ShortcutPlatform.windows:
      return 'Windows';
    case ShortcutPlatform.macos:
      return 'macOS';
    case ShortcutPlatform.linux:
      return 'Linux';
  }
}

/// 格式化快捷键显示文本
String formatShortcutKeys(List<ShortcutKey> keys) {
  return keys.map((k) => k.key).join(' + ');
}

/// 获取默认快捷键列表
List<ShortcutItem> getDefaultShortcuts(ShortcutPlatform platform) {
  switch (platform) {
    case ShortcutPlatform.windows:
      return [
        ShortcutItem(
          id: 'arrow-left',
          label: '左',
          icon: '',
          keys: [ShortcutKey(key: '←', keyCode: 'ArrowLeft')],
          platform: platform,
          order: 1,
        ),
        ShortcutItem(
          id: 'arrow-right',
          label: '右',
          icon: '',
          keys: [ShortcutKey(key: '→', keyCode: 'ArrowRight')],
          platform: platform,
          order: 2,
        ),
        ShortcutItem(
          id: 'arrow-up',
          label: '上',
          icon: '',
          keys: [ShortcutKey(key: '↑', keyCode: 'ArrowUp')],
          platform: platform,
          order: 3,
        ),
        ShortcutItem(
          id: 'arrow-down',
          label: '下',
          icon: '',
          keys: [ShortcutKey(key: '↓', keyCode: 'ArrowDown')],
          platform: platform,
          order: 4,
        ),
        ShortcutItem(
          id: 'backspace',
          label: '退格',
          icon: '',
          keys: [ShortcutKey(key: 'Backspace', keyCode: 'Backspace')],
          platform: platform,
          order: 5,
        ),
        ShortcutItem(
          id: 'delete',
          label: '删除',
          icon: '',
          keys: [ShortcutKey(key: 'Del', keyCode: 'Delete')],
          platform: platform,
          order: 6,
        ),
        ShortcutItem(
          id: 'escape',
          label: 'Esc',
          icon: '',
          keys: [ShortcutKey(key: 'Esc', keyCode: 'Escape')],
          platform: platform,
          order: 7,
        ),
        ShortcutItem(
          id: 'shift-tab',
          label: 'Shift+Tab',
          icon: '',
          keys: [
            ShortcutKey(key: 'Shift', keyCode: 'ShiftLeft'),
            ShortcutKey(key: 'Tab', keyCode: 'Tab')
          ],
          platform: platform,
          order: 8,
        ),
        ShortcutItem(
          id: 'shift-enter',
          label: 'Shift+Enter',
          icon: '',
          keys: [
            ShortcutKey(key: 'Shift', keyCode: 'ShiftLeft'),
            ShortcutKey(key: 'Enter', keyCode: 'Enter')
          ],
          platform: platform,
          order: 9,
        ),
        ShortcutItem(
          id: 'delete-all',
          label: '全部删除',
          icon: '',
          keys: [
            ShortcutKey(key: 'Ctrl', keyCode: 'ControlLeft'),
            ShortcutKey(key: 'A', keyCode: 'KeyA'),
            ShortcutKey(key: 'Backspace', keyCode: 'Backspace'),
          ],
          platform: platform,
          order: 10,
        ),
        ShortcutItem(
          id: 'copy',
          label: '复制',
          icon: '',
          keys: [
            ShortcutKey(key: 'Ctrl', keyCode: 'ControlLeft'),
            ShortcutKey(key: 'C', keyCode: 'KeyC')
          ],
          platform: platform,
          order: 11,
        ),
        ShortcutItem(
          id: 'paste',
          label: '粘贴',
          icon: '',
          keys: [
            ShortcutKey(key: 'Ctrl', keyCode: 'ControlLeft'),
            ShortcutKey(key: 'V', keyCode: 'KeyV')
          ],
          platform: platform,
          order: 12,
        ),
        ShortcutItem(
          id: 'cut',
          label: '剪切',
          icon: '',
          keys: [
            ShortcutKey(key: 'Ctrl', keyCode: 'ControlLeft'),
            ShortcutKey(key: 'X', keyCode: 'KeyX')
          ],
          platform: platform,
          enabled: false,
          order: 13,
        ),
        ShortcutItem(
          id: 'select-all',
          label: '全选',
          icon: '',
          keys: [
            ShortcutKey(key: 'Ctrl', keyCode: 'ControlLeft'),
            ShortcutKey(key: 'A', keyCode: 'KeyA')
          ],
          platform: platform,
          order: 14,
        ),
        ShortcutItem(
          id: 'save',
          label: '保存',
          icon: '',
          keys: [
            ShortcutKey(key: 'Ctrl', keyCode: 'ControlLeft'),
            ShortcutKey(key: 'S', keyCode: 'KeyS')
          ],
          platform: platform,
          enabled: false,
          order: 15,
        ),
        ShortcutItem(
          id: 'find',
          label: '查找',
          icon: '',
          keys: [
            ShortcutKey(key: 'Ctrl', keyCode: 'ControlLeft'),
            ShortcutKey(key: 'F', keyCode: 'KeyF')
          ],
          platform: platform,
          enabled: false,
          order: 16,
        ),
        ShortcutItem(
          id: 'undo',
          label: '撤销',
          icon: '',
          keys: [
            ShortcutKey(key: 'Ctrl', keyCode: 'ControlLeft'),
            ShortcutKey(key: 'Z', keyCode: 'KeyZ')
          ],
          platform: platform,
          enabled: false,
          order: 17,
        ),
        ShortcutItem(
          id: 'alt-tab',
          label: '切换窗口',
          icon: '',
          keys: [
            ShortcutKey(key: 'Alt', keyCode: 'AltLeft'),
            ShortcutKey(key: 'Tab', keyCode: 'Tab')
          ],
          platform: platform,
          enabled: false,
          order: 18,
        ),
        ShortcutItem(
          id: 'lock',
          label: '锁屏',
          icon: '',
          keys: [
            ShortcutKey(key: 'Win', keyCode: 'MetaLeft'),
            ShortcutKey(key: 'L', keyCode: 'KeyL')
          ],
          platform: platform,
          enabled: false,
          order: 19,
        ),
        ShortcutItem(
          id: 'task-manager',
          label: '任务管理器',
          icon: '',
          keys: [
            ShortcutKey(key: 'Ctrl', keyCode: 'ControlLeft'),
            ShortcutKey(key: 'Shift', keyCode: 'ShiftLeft'),
            ShortcutKey(key: 'Esc', keyCode: 'Escape'),
          ],
          platform: platform,
          enabled: false,
          order: 20,
        ),
      ];

    case ShortcutPlatform.macos:
      return [
        ShortcutItem(
          id: 'arrow-left',
          label: '左',
          icon: '',
          keys: [ShortcutKey(key: '←', keyCode: 'ArrowLeft')],
          platform: platform,
          order: 1,
        ),
        ShortcutItem(
          id: 'arrow-right',
          label: '右',
          icon: '',
          keys: [ShortcutKey(key: '→', keyCode: 'ArrowRight')],
          platform: platform,
          order: 2,
        ),
        ShortcutItem(
          id: 'arrow-up',
          label: '上',
          icon: '',
          keys: [ShortcutKey(key: '↑', keyCode: 'ArrowUp')],
          platform: platform,
          order: 3,
        ),
        ShortcutItem(
          id: 'arrow-down',
          label: '下',
          icon: '',
          keys: [ShortcutKey(key: '↓', keyCode: 'ArrowDown')],
          platform: platform,
          order: 4,
        ),
        ShortcutItem(
          id: 'backspace',
          label: '退格',
          icon: '',
          keys: [ShortcutKey(key: 'Backspace', keyCode: 'Backspace')],
          platform: platform,
          order: 5,
        ),
        ShortcutItem(
          id: 'delete',
          label: '删除',
          icon: '',
          keys: [ShortcutKey(key: 'Del', keyCode: 'Delete')],
          platform: platform,
          order: 6,
        ),
        ShortcutItem(
          id: 'escape',
          label: 'Esc',
          icon: '',
          keys: [ShortcutKey(key: 'Esc', keyCode: 'Escape')],
          platform: platform,
          order: 7,
        ),
        ShortcutItem(
          id: 'shift-tab',
          label: 'Shift+Tab',
          icon: '',
          keys: [
            ShortcutKey(key: 'Shift', keyCode: 'ShiftLeft'),
            ShortcutKey(key: 'Tab', keyCode: 'Tab')
          ],
          platform: platform,
          order: 8,
        ),
        ShortcutItem(
          id: 'shift-enter',
          label: 'Shift+Enter',
          icon: '',
          keys: [
            ShortcutKey(key: 'Shift', keyCode: 'ShiftLeft'),
            ShortcutKey(key: 'Enter', keyCode: 'Enter')
          ],
          platform: platform,
          order: 9,
        ),
        ShortcutItem(
          id: 'delete-all',
          label: '全部删除',
          icon: '',
          keys: [
            ShortcutKey(key: 'Cmd', keyCode: 'MetaLeft'),
            ShortcutKey(key: 'A', keyCode: 'KeyA'),
            ShortcutKey(key: 'Backspace', keyCode: 'Backspace'),
          ],
          platform: platform,
          order: 10,
        ),
        ShortcutItem(
          id: 'copy',
          label: '复制',
          icon: '',
          keys: [
            ShortcutKey(key: 'Cmd', keyCode: 'MetaLeft'),
            ShortcutKey(key: 'C', keyCode: 'KeyC')
          ],
          platform: platform,
          order: 11,
        ),
        ShortcutItem(
          id: 'paste',
          label: '粘贴',
          icon: '',
          keys: [
            ShortcutKey(key: 'Cmd', keyCode: 'MetaLeft'),
            ShortcutKey(key: 'V', keyCode: 'KeyV')
          ],
          platform: platform,
          order: 12,
        ),
        ShortcutItem(
          id: 'cut',
          label: '剪切',
          icon: '',
          keys: [
            ShortcutKey(key: 'Cmd', keyCode: 'MetaLeft'),
            ShortcutKey(key: 'X', keyCode: 'KeyX')
          ],
          platform: platform,
          enabled: false,
          order: 13,
        ),
        ShortcutItem(
          id: 'select-all',
          label: '全选',
          icon: '',
          keys: [
            ShortcutKey(key: 'Cmd', keyCode: 'MetaLeft'),
            ShortcutKey(key: 'A', keyCode: 'KeyA')
          ],
          platform: platform,
          order: 14,
        ),
        ShortcutItem(
          id: 'save',
          label: '保存',
          icon: '',
          keys: [
            ShortcutKey(key: 'Cmd', keyCode: 'MetaLeft'),
            ShortcutKey(key: 'S', keyCode: 'KeyS')
          ],
          platform: platform,
          enabled: false,
          order: 15,
        ),
        ShortcutItem(
          id: 'find',
          label: '查找',
          icon: '',
          keys: [
            ShortcutKey(key: 'Cmd', keyCode: 'MetaLeft'),
            ShortcutKey(key: 'F', keyCode: 'KeyF')
          ],
          platform: platform,
          enabled: false,
          order: 16,
        ),
        ShortcutItem(
          id: 'undo',
          label: '撤销',
          icon: '',
          keys: [
            ShortcutKey(key: 'Cmd', keyCode: 'MetaLeft'),
            ShortcutKey(key: 'Z', keyCode: 'KeyZ')
          ],
          platform: platform,
          enabled: false,
          order: 17,
        ),
        ShortcutItem(
          id: 'cmd-tab',
          label: '切换窗口',
          icon: '',
          keys: [
            ShortcutKey(key: 'Cmd', keyCode: 'MetaLeft'),
            ShortcutKey(key: 'Tab', keyCode: 'Tab')
          ],
          platform: platform,
          enabled: false,
          order: 18,
        ),
        ShortcutItem(
          id: 'lock',
          label: '锁屏',
          icon: '',
          keys: [
            ShortcutKey(key: 'Ctrl', keyCode: 'ControlLeft'),
            ShortcutKey(key: 'Cmd', keyCode: 'MetaLeft'),
            ShortcutKey(key: 'Q', keyCode: 'KeyQ'),
          ],
          platform: platform,
          enabled: false,
          order: 19,
        ),
        ShortcutItem(
          id: 'screenshot',
          label: '截图',
          icon: '',
          keys: [
            ShortcutKey(key: 'Cmd', keyCode: 'MetaLeft'),
            ShortcutKey(key: 'Shift', keyCode: 'ShiftLeft'),
            ShortcutKey(key: '4', keyCode: 'Digit4'),
          ],
          platform: platform,
          enabled: false,
          order: 20,
        ),
      ];

    case ShortcutPlatform.linux:
      return [
        ShortcutItem(
          id: 'arrow-left',
          label: '左',
          icon: '',
          keys: [ShortcutKey(key: '←', keyCode: 'ArrowLeft')],
          platform: platform,
          order: 1,
        ),
        ShortcutItem(
          id: 'arrow-right',
          label: '右',
          icon: '',
          keys: [ShortcutKey(key: '→', keyCode: 'ArrowRight')],
          platform: platform,
          order: 2,
        ),
        ShortcutItem(
          id: 'arrow-up',
          label: '上',
          icon: '',
          keys: [ShortcutKey(key: '↑', keyCode: 'ArrowUp')],
          platform: platform,
          order: 3,
        ),
        ShortcutItem(
          id: 'arrow-down',
          label: '下',
          icon: '',
          keys: [ShortcutKey(key: '↓', keyCode: 'ArrowDown')],
          platform: platform,
          order: 4,
        ),
        ShortcutItem(
          id: 'backspace',
          label: '退格',
          icon: '',
          keys: [ShortcutKey(key: 'Backspace', keyCode: 'Backspace')],
          platform: platform,
          order: 5,
        ),
        ShortcutItem(
          id: 'delete',
          label: '删除',
          icon: '',
          keys: [ShortcutKey(key: 'Del', keyCode: 'Delete')],
          platform: platform,
          order: 6,
        ),
        ShortcutItem(
          id: 'escape',
          label: 'Esc',
          icon: '',
          keys: [ShortcutKey(key: 'Esc', keyCode: 'Escape')],
          platform: platform,
          order: 7,
        ),
        ShortcutItem(
          id: 'shift-tab',
          label: 'Shift+Tab',
          icon: '',
          keys: [
            ShortcutKey(key: 'Shift', keyCode: 'ShiftLeft'),
            ShortcutKey(key: 'Tab', keyCode: 'Tab')
          ],
          platform: platform,
          order: 8,
        ),
        ShortcutItem(
          id: 'shift-enter',
          label: 'Shift+Enter',
          icon: '',
          keys: [
            ShortcutKey(key: 'Shift', keyCode: 'ShiftLeft'),
            ShortcutKey(key: 'Enter', keyCode: 'Enter')
          ],
          platform: platform,
          order: 9,
        ),
        ShortcutItem(
          id: 'delete-all',
          label: '全部删除',
          icon: '',
          keys: [
            ShortcutKey(key: 'Ctrl', keyCode: 'ControlLeft'),
            ShortcutKey(key: 'A', keyCode: 'KeyA'),
            ShortcutKey(key: 'Backspace', keyCode: 'Backspace'),
          ],
          platform: platform,
          order: 10,
        ),
        ShortcutItem(
          id: 'copy',
          label: '复制',
          icon: '',
          keys: [
            ShortcutKey(key: 'Ctrl', keyCode: 'ControlLeft'),
            ShortcutKey(key: 'C', keyCode: 'KeyC')
          ],
          platform: platform,
          order: 11,
        ),
        ShortcutItem(
          id: 'paste',
          label: '粘贴',
          icon: '',
          keys: [
            ShortcutKey(key: 'Ctrl', keyCode: 'ControlLeft'),
            ShortcutKey(key: 'V', keyCode: 'KeyV')
          ],
          platform: platform,
          order: 12,
        ),
        ShortcutItem(
          id: 'cut',
          label: '剪切',
          icon: '',
          keys: [
            ShortcutKey(key: 'Ctrl', keyCode: 'ControlLeft'),
            ShortcutKey(key: 'X', keyCode: 'KeyX')
          ],
          platform: platform,
          enabled: false,
          order: 13,
        ),
        ShortcutItem(
          id: 'select-all',
          label: '全选',
          icon: '',
          keys: [
            ShortcutKey(key: 'Ctrl', keyCode: 'ControlLeft'),
            ShortcutKey(key: 'A', keyCode: 'KeyA')
          ],
          platform: platform,
          order: 14,
        ),
        ShortcutItem(
          id: 'save',
          label: '保存',
          icon: '',
          keys: [
            ShortcutKey(key: 'Ctrl', keyCode: 'ControlLeft'),
            ShortcutKey(key: 'S', keyCode: 'KeyS')
          ],
          platform: platform,
          enabled: false,
          order: 15,
        ),
        ShortcutItem(
          id: 'find',
          label: '查找',
          icon: '',
          keys: [
            ShortcutKey(key: 'Ctrl', keyCode: 'ControlLeft'),
            ShortcutKey(key: 'F', keyCode: 'KeyF')
          ],
          platform: platform,
          enabled: false,
          order: 16,
        ),
        ShortcutItem(
          id: 'undo',
          label: '撤销',
          icon: '',
          keys: [
            ShortcutKey(key: 'Ctrl', keyCode: 'ControlLeft'),
            ShortcutKey(key: 'Z', keyCode: 'KeyZ')
          ],
          platform: platform,
          enabled: false,
          order: 17,
        ),
        ShortcutItem(
          id: 'alt-tab',
          label: '切换窗口',
          icon: '',
          keys: [
            ShortcutKey(key: 'Alt', keyCode: 'AltLeft'),
            ShortcutKey(key: 'Tab', keyCode: 'Tab')
          ],
          platform: platform,
          enabled: false,
          order: 18,
        ),
        ShortcutItem(
          id: 'lock',
          label: '锁屏',
          icon: '',
          keys: [
            ShortcutKey(key: 'Super', keyCode: 'MetaLeft'),
            ShortcutKey(key: 'L', keyCode: 'KeyL')
          ],
          platform: platform,
          enabled: false,
          order: 19,
        ),
        ShortcutItem(
          id: 'terminal',
          label: '终端',
          icon: '',
          keys: [
            ShortcutKey(key: 'Ctrl', keyCode: 'ControlLeft'),
            ShortcutKey(key: 'Alt', keyCode: 'AltLeft'),
            ShortcutKey(key: 'T', keyCode: 'KeyT'),
          ],
          platform: platform,
          enabled: false,
          order: 20,
        ),
      ];
  }
}
