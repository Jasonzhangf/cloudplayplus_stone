# 快捷键功能实现指南

## 📋 已完成的工作

### 1. 数据模型 ✅
- **文件**：`lib/models/shortcut.dart`
- **功能**：
  - `ShortcutPlatform` 枚举：Windows/macOS/Linux 平台
  - `ShortcutKey` 类：单个按键信息
  - `ShortcutItem` 类：快捷键配置项
  - `ShortcutSettings` 类：快捷键设置
  - 预设快捷键模板（每个平台8个常用快捷键）

### 2. UI组件 ✅
- **文件**：`lib/widgets/keyboard/shortcut_bar.dart`
- **组件**：
  - `ShortcutBar`：快捷键条主组件
  - `_ShortcutButton`：快捷键按钮
  - `_ShortcutSettingsSheet`：设置弹窗（底部抽屉）
  - `_ShortcutTile`：设置列表项

### 3. 数据服务 ✅
- **文件**：`lib/services/shortcut_service.dart`
- **功能**：
  - 使用 `SharedPreferences` 持久化存储
  - 提供快捷键CRUD操作
  - 平台切换功能

### 4. 集成组件 ✅
- **文件**：`lib/widgets/keyboard/enhanced_keyboard_panel.dart`
- **功能**：
  - 将快捷键条集成到虚拟键盘上方
  - 处理快捷键按下事件
  - 键码映射转换

### 5. 设计文档 ✅
- **文件**：`docs/shortcut_bar_design.html`
- **内容**：
  - 视觉设计规范
  - 交互说明
  - 平台快捷键示例
  - 完整的UI/UX说明

---

## 🚀 集成步骤

### 第1步：安装依赖

确保 `pubspec.yaml` 包含以下依赖：

```yaml
dependencies:
  shared_preferences: ^2.0.0  # 用于数据持久化
  vk: ^x.x.x  # 虚拟键盘组件（已存在）
```

运行：
```bash
flutter pub get
```

### 第2步：替换虚拟键盘组件

找到使用 `OnScreenVirtualKeyboard` 的地方并替换为 `EnhancedKeyboardPanel`：

**替换前：**
```dart
import 'package:cloudplayplus/utils/widgets/on_screen_keyboard.dart';

// ... 在构建方法中
OnScreenVirtualKeyboard()
```

**替换后：**
```dart
import 'package:cloudplayplus/widgets/keyboard/enhanced_keyboard_panel.dart';

// ... 在构建方法中
EnhancedKeyboardPanel()
```

### 第3步：初始化快捷键服务（可选）

如果需要在应用启动时初始化，可以在 `main.dart` 中：

```dart
import 'package:cloudplayplus/services/shortcut_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化快捷键服务
  await ShortcutService().init();
  
  runApp(MyApp());
}
```

---

## 📱 功能说明

### 快捷键条

- **位置**：位于虚拟键盘上方
- **样式**：
  - 毛玻璃背景（`rgba(255, 255, 255, 0.98)`）
  - 阴影效果
  - 水平滚动（当按钮过多时）

### 设置按钮

- **位置**：快捷键条最左侧
- **颜色**：紫色渐变（`#667eea → #764ba2`）
- **功能**：点击打开设置弹窗

### 快捷键按钮

- **显示内容**：
  - 图标（emoji）
  - 快捷键组合（如 `Ctrl+C`）
- **交互**：
  - 点击发送快捷键到远程桌面
  - 按下时缩放动画（`scale(0.95)`）
  - 触觉反馈

### 设置弹窗

- **平台切换**：
  - Windows、macOS、Linux 三选一
  - 切换时自动加载对应平台的预设快捷键
- **快捷键管理**：
  - 查看所有快捷键
  - 启用/禁用快捷键
  - 显示快捷键组合

---

## 🔧 自定义配置

### 添加新的快捷键

编辑 `lib/models/shortcut.dart` 中的 `_getDefaultShortcuts` 函数：

```dart
ShortcutItem(
  id: 'my-shortcut',
  label: '我的快捷键',
  icon: '🎯',
  keys: [
    ShortcutKey(key: 'Ctrl', keyCode: 'ControlLeft'),
    ShortcutKey(key: 'Shift', keyCode: 'ShiftLeft'),
    ShortcutKey(key: 'N', keyCode: 'KeyN'),
  ],
  platform: platform,
  order: 9,
),
```

### 修改快捷键样式

编辑 `lib/widgets/keyboard/shortcut_bar.dart` 中的样式常量。

---

## ⚙️ 技术细节

### 键码映射

快捷键的 `keyCode` 字符串会被转换为Windows虚拟键码（VK_*），映射表位于：
- `lib/widgets/keyboard/enhanced_keyboard_panel.dart` 的 `_getKeyCodeFromString` 方法

### 按键发送逻辑

1. 用户点击快捷键按钮
2. 按顺序按下所有按键（发送 `keyDown` 事件）
3. 延迟 50ms
4. 按相反顺序释放所有按键（发送 `keyUp` 事件）

示例：`Ctrl+C`
```
1. ControlLeft DOWN
2. KeyC DOWN
3. [50ms delay]
4. KeyC UP
5. ControlLeft UP
```

### 数据持久化

- 使用 `SharedPreferences` 存储
- 键名：`shortcut_settings`
- 格式：JSON
- 存储内容：
  - 当前平台
  - 所有快捷键配置（包括启用状态、顺序等）

---

## 🐛 常见问题

### Q: 快捷键不生效？
A: 检查：
1. 是否已连接到远程桌面
2. 远程桌面是否支持该快捷键
3. 键码映射是否正确

### Q: 如何添加更多按键映射？
A: 编辑 `enhanced_keyboard_panel.dart` 中的 `_getKeyCodeFromString` 方法，参考 `lib/controller/platform_key_map.dart`

### Q: 如何修改默认快捷键？
A: 编辑 `lib/models/shortcut.dart` 中的 `_getDefaultShortcuts` 函数

---

## 📚 相关文件

```
cloudplayplus_stone/
├── lib/
│   ├── models/
│   │   └── shortcut.dart                    # 数据模型
│   ├── services/
│   │   └── shortcut_service.dart           # 数据服务
│   └── widgets/
│       └── keyboard/
│           ├── shortcut_bar.dart           # 快捷键条UI
│           └── enhanced_keyboard_panel.dart # 集成组件
├── docs/
│   ├── shortcut_bar_design.html            # 设计规范
│   └── shortcut_implementation_guide.md     # 本文档
└── src/
    └── types/
        └── shortcut.ts                      # TypeScript类型定义
```

---

## 🎯 下一步

1. **测试**：在真实设备上测试各个平台的快捷键
2. **优化**：根据用户反馈调整UI和交互
3. **扩展**：
   - 添加自定义快捷键功能
   - 支持拖拽排序
   - 导入/导出配置
   - 快捷键录制功能

---

## 📝 更新日志

**v1.0.0** - 2025-01-24
- ✅ 初始实现
- ✅ 支持 Windows/macOS/Linux 三平台
- ✅ 8个预设快捷键
- ✅ 快捷键启用/禁用
- ✅ 数据持久化
