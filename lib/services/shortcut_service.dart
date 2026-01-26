import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shortcut.dart';

/// 快捷键服务 - 负责快捷键设置的持久化存储
class ShortcutService {
  static const String _settingsKey = 'shortcut_settings';
  late SharedPreferences _prefs;
  ShortcutSettings _settings = ShortcutSettings();

  /// 单例
  static final ShortcutService _instance = ShortcutService._internal();
  factory ShortcutService() => _instance;
  ShortcutService._internal();

  /// 初始化
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadSettings();
  }

  /// 获取当前设置
  ShortcutSettings get settings => _settings;

  /// 加载设置
  Future<void> _loadSettings() async {
    try {
      final jsonStr = _prefs.getString(_settingsKey);
      if (jsonStr != null) {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        final loadedSettings = ShortcutSettings.fromJson(json);

        // 合并默认配置，确保新增的快捷键能显示出来
        final defaultShortcuts =
            getDefaultShortcuts(loadedSettings.currentPlatform);
        final loadedIds = loadedSettings.shortcuts.map((s) => s.id).toSet();

        final newShortcuts = List<ShortcutItem>.from(loadedSettings.shortcuts);
        for (final defaultShortcut in defaultShortcuts) {
          if (!loadedIds.contains(defaultShortcut.id)) {
            newShortcuts.add(defaultShortcut);
          }
        }

        // 按顺序排序
        newShortcuts.sort((a, b) => a.order.compareTo(b.order));

        _settings = loadedSettings.copyWith(shortcuts: newShortcuts);
      }
    } catch (e) {
      // 加载失败时使用默认设置
      _settings = ShortcutSettings();
    }
  }

  /// 保存设置
  Future<void> saveSettings(ShortcutSettings settings) async {
    try {
      _settings = settings;
      final jsonStr = jsonEncode(settings.toJson());
      await _prefs.setString(_settingsKey, jsonStr);
    } catch (e) {
      // 保存失败
    }
  }

  /// 切换平台
  Future<void> switchPlatform(ShortcutPlatform platform) async {
    final newSettings = ShortcutSettings(currentPlatform: platform);
    await saveSettings(newSettings);
  }

  /// 更新快捷键列表
  Future<void> updateShortcuts(List<ShortcutItem> shortcuts) async {
    final newSettings = _settings.copyWith(shortcuts: shortcuts);
    await saveSettings(newSettings);
  }

  /// 切换快捷键启用状态
  Future<void> toggleShortcut(String id) async {
    final newShortcuts = _settings.shortcuts.map((s) {
      if (s.id == id) {
        return s.copyWith(enabled: !s.enabled);
      }
      return s;
    }).toList();
    await updateShortcuts(newShortcuts);
  }

  /// 重置为默认设置
  Future<void> resetToDefault() async {
    await saveSettings(ShortcutSettings());
  }
}
