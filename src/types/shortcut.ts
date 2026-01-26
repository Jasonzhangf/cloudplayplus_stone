/**
 * 快捷键平台类型
 */
export type ShortcutPlatform = 'windows' | 'macos' | 'linux';

/**
 * 快捷键按键类型
 */
export interface ShortcutKey {
  /** 按键名称，如 'Ctrl', 'Shift', 'C' */
  key: string;
  /** 按键代码 */
  keyCode: string;
}

/**
 * 快捷键配置项
 */
export interface ShortcutItem {
  /** 唯一标识 */
  id: string;
  /** 显示名称 */
  label: string;
  /** 图标（emoji 或图标名称） */
  icon: string;
  /** 按键组合 */
  keys: ShortcutKey[];
  /** 适用平台 */
  platform: ShortcutPlatform;
  /** 是否启用 */
  enabled: boolean;
  /** 显示顺序 */
  order: number;
}

/**
 * 快捷键设置
 */
export interface ShortcutSettings {
  /** 当前选择的平台 */
  currentPlatform: ShortcutPlatform;
  /** 快捷键列表 */
  shortcuts: ShortcutItem[];
}

/**
 * 快捷键事件
 */
export interface ShortcutEvent {
  /** 快捷键ID */
  shortcutId: string;
  /** 按键组合 */
  keys: ShortcutKey[];
  /** 时间戳 */
  timestamp: number;
}

/**
 * 预设快捷键模板
 */
export const PRESET_SHORTCUTS: Record<ShortcutPlatform, ShortcutItem[]> = {
  windows: [
    {
      id: 'copy',
      label: '复制',
      icon: '📋',
      keys: [{ key: 'Ctrl', keyCode: 'ControlLeft' }, { key: 'C', keyCode: 'KeyC' }],
      platform: 'windows',
      enabled: true,
      order: 1,
    },
    {
      id: 'paste',
      label: '粘贴',
      icon: '📄',
      keys: [{ key: 'Ctrl', keyCode: 'ControlLeft' }, { key: 'V', keyCode: 'KeyV' }],
      platform: 'windows',
      enabled: true,
      order: 2,
    },
    {
      id: 'save',
      label: '保存',
      icon: '💾',
      keys: [{ key: 'Ctrl', keyCode: 'ControlLeft' }, { key: 'S', keyCode: 'KeyS' }],
      platform: 'windows',
      enabled: true,
      order: 3,
    },
    {
      id: 'find',
      label: '查找',
      icon: '🔍',
      keys: [{ key: 'Ctrl', keyCode: 'ControlLeft' }, { key: 'F', keyCode: 'KeyF' }],
      platform: 'windows',
      enabled: true,
      order: 4,
    },
    {
      id: 'undo',
      label: '撤销',
      icon: '↶',
      keys: [{ key: 'Ctrl', keyCode: 'ControlLeft' }, { key: 'Z', keyCode: 'KeyZ' }],
      platform: 'windows',
      enabled: true,
      order: 5,
    },
    {
      id: 'alt-tab',
      label: '切换窗口',
      icon: '🗔',
      keys: [{ key: 'Alt', keyCode: 'AltLeft' }, { key: 'Tab', keyCode: 'Tab' }],
      platform: 'windows',
      enabled: true,
      order: 6,
    },
    {
      id: 'lock',
      label: '锁屏',
      icon: '🔒',
      keys: [{ key: 'Win', keyCode: 'MetaLeft' }, { key: 'L', keyCode: 'KeyL' }],
      platform: 'windows',
      enabled: true,
      order: 7,
    },
    {
      id: 'task-manager',
      label: '任务管理器',
      icon: '⚡',
      keys: [
        { key: 'Ctrl', keyCode: 'ControlLeft' },
        { key: 'Shift', keyCode: 'ShiftLeft' },
        { key: 'Esc', keyCode: 'Escape' },
      ],
      platform: 'windows',
      enabled: true,
      order: 8,
    },
  ],
  macos: [
    {
      id: 'copy',
      label: '复制',
      icon: '📋',
      keys: [{ key: 'Cmd', keyCode: 'MetaLeft' }, { key: 'C', keyCode: 'KeyC' }],
      platform: 'macos',
      enabled: true,
      order: 1,
    },
    {
      id: 'paste',
      label: '粘贴',
      icon: '📄',
      keys: [{ key: 'Cmd', keyCode: 'MetaLeft' }, { key: 'V', keyCode: 'KeyV' }],
      platform: 'macos',
      enabled: true,
      order: 2,
    },
    {
      id: 'save',
      label: '保存',
      icon: '💾',
      keys: [{ key: 'Cmd', keyCode: 'MetaLeft' }, { key: 'S', keyCode: 'KeyS' }],
      platform: 'macos',
      enabled: true,
      order: 3,
    },
    {
      id: 'find',
      label: '查找',
      icon: '🔍',
      keys: [{ key: 'Cmd', keyCode: 'MetaLeft' }, { key: 'F', keyCode: 'KeyF' }],
      platform: 'macos',
      enabled: true,
      order: 4,
    },
    {
      id: 'undo',
      label: '撤销',
      icon: '↶',
      keys: [{ key: 'Cmd', keyCode: 'MetaLeft' }, { key: 'Z', keyCode: 'KeyZ' }],
      platform: 'macos',
      enabled: true,
      order: 5,
    },
    {
      id: 'cmd-tab',
      label: '切换窗口',
      icon: '🗔',
      keys: [{ key: 'Cmd', keyCode: 'MetaLeft' }, { key: 'Tab', keyCode: 'Tab' }],
      platform: 'macos',
      enabled: true,
      order: 6,
    },
    {
      id: 'lock',
      label: '锁屏',
      icon: '🔒',
      keys: [
        { key: 'Ctrl', keyCode: 'ControlLeft' },
        { key: 'Cmd', keyCode: 'MetaLeft' },
        { key: 'Q', keyCode: 'KeyQ' },
      ],
      platform: 'macos',
      enabled: true,
      order: 7,
    },
    {
      id: 'screenshot',
      label: '截图',
      icon: '📷',
      keys: [
        { key: 'Cmd', keyCode: 'MetaLeft' },
        { key: 'Shift', keyCode: 'ShiftLeft' },
        { key: '4', keyCode: 'Digit4' },
      ],
      platform: 'macos',
      enabled: true,
      order: 8,
    },
  ],
  linux: [
    {
      id: 'copy',
      label: '复制',
      icon: '📋',
      keys: [{ key: 'Ctrl', keyCode: 'ControlLeft' }, { key: 'C', keyCode: 'KeyC' }],
      platform: 'linux',
      enabled: true,
      order: 1,
    },
    {
      id: 'paste',
      label: '粘贴',
      icon: '📄',
      keys: [{ key: 'Ctrl', keyCode: 'ControlLeft' }, { key: 'V', keyCode: 'KeyV' }],
      platform: 'linux',
      enabled: true,
      order: 2,
    },
    {
      id: 'save',
      label: '保存',
      icon: '💾',
      keys: [{ key: 'Ctrl', keyCode: 'ControlLeft' }, { key: 'S', keyCode: 'KeyS' }],
      platform: 'linux',
      enabled: true,
      order: 3,
    },
    {
      id: 'find',
      label: '查找',
      icon: '🔍',
      keys: [{ key: 'Ctrl', keyCode: 'ControlLeft' }, { key: 'F', keyCode: 'KeyF' }],
      platform: 'linux',
      enabled: true,
      order: 4,
    },
    {
      id: 'undo',
      label: '撤销',
      icon: '↶',
      keys: [{ key: 'Ctrl', keyCode: 'ControlLeft' }, { key: 'Z', keyCode: 'KeyZ' }],
      platform: 'linux',
      enabled: true,
      order: 5,
    },
    {
      id: 'alt-tab',
      label: '切换窗口',
      icon: '🗔',
      keys: [{ key: 'Alt', keyCode: 'AltLeft' }, { key: 'Tab', keyCode: 'Tab' }],
      platform: 'linux',
      enabled: true,
      order: 6,
    },
    {
      id: 'lock',
      label: '锁屏',
      icon: '🔒',
      keys: [{ key: 'Super', keyCode: 'MetaLeft' }, { key: 'L', keyCode: 'KeyL' }],
      platform: 'linux',
      enabled: true,
      order: 7,
    },
    {
      id: 'terminal',
      label: '终端',
      icon: '💻',
      keys: [{ key: 'Ctrl', keyCode: 'ControlLeft' }, { key: 'Alt', keyCode: 'AltLeft' }, { key: 'T', keyCode: 'KeyT' }],
      platform: 'linux',
      enabled: true,
      order: 8,
    },
  ],
};

/**
 * 获取平台的显示名称
 */
export function getPlatformDisplayName(platform: ShortcutPlatform): string {
  const names: Record<ShortcutPlatform, string> = {
    windows: 'Windows',
    macos: 'macOS',
    linux: 'Linux',
  };
  return names[platform];
}

/**
 * 格式化快捷键显示文本
 */
export function formatShortcutKeys(keys: ShortcutKey[]): string {
  return keys.map((k) => k.key).join(' + ');
}
