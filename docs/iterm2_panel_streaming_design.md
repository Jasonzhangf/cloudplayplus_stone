# iTerm2 Panel 串流功能设计文档

## 功能概述

实现从 macOS 端捕获 iTerm2 某个特定 panel（而非整个窗口），并支持在串流过程中动态切换 panel。

## 核心需求

1. **Panel 识别**：能够检测 iTerm2 窗口中的所有 panel
2. **Panel 捕获**：选择性捕获某个 panel 的内容
3. **动态切换**：串流过程中可以切换到其他 panel
4. **性能优化**：保证流畅的串流体验

## 技术方案

### 方案选择：窗口捕获 + 帧裁剪（推荐）

```
流程：
1. 捕获整个 iTerm2 窗口（使用 SourceType.Window）
2. 通过 macOS Accessibility API 获取当前选中 panel 的边界坐标
3. 在视频流中裁剪到目标 panel 区域
4. 串流裁剪后的视频帧

优点：
- 利用现有 WebRTC 窗口捕获能力
- 不需要额外的系统权限
- 切换 panel 只需更新裁剪坐标，无需重建串流

缺点：
- 需要实现帧裁剪逻辑
- 轻微的性能开销
```

## 架构设计

### 组件划分

```
┌──────────────────────────────────────────────────────────┐
│  1. ITerm2PanelDetector（macOS Native）                  │
│     - 使用 Accessibility API 获取 panel 列表              │
│     - 返回每个 panel 的 ID、标题、边界坐标                 │
│     - 监听 panel 布局变化                                 │
└────────────────┬─────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────┐
│  2. PanelStreamService（Dart）                           │
│     - 管理当前选中的 panel                                │
│     - 计算裁剪坐标                                        │
│     - 提供 panel 列表给 UI                                │
└────────────────┬─────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────┐
│  3. VideoFrameCropper（Dart/Native）                     │
│     - 接收原始视频帧                                      │
│     - 应用裁剪坐标                                        │
│     - 输出裁剪后的帧到串流                                │
└────────────────┬─────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────┐
│  4. PanelSwitcherUI（Flutter Widget）                    │
│     - 显示 panel 列表（编号 + 标题）                      │
│     - 提供快捷切换按钮                                    │
│     - 显示当前 panel 状态                                 │
└──────────────────────────────────────────────────────────┘
```

### 数据结构

```dart
/// Panel 信息
class PanelInfo {
  final String id;              // 唯一标识
  final String title;           // Panel 标题（如"Session 1"）
  final Rectangle<int> bounds;  // 相对于窗口的边界
  final bool isActive;          // 是否为当前激活的 panel
}

/// 裁剪配置
class CropConfig {
  final int x;        // 裁剪区域左上角 x 坐标
  final int y;        // 裁剪区域左上角 y 坐标
  final int width;    // 裁剪区域宽度
  final int height;   // 裁剪区域高度
}
```

## 实现计划

### 阶段 1：macOS Native Panel 检测（预计 1-2 天）

**文件结构：**
```
plugins/hardware_simulator/macos/Classes/
├── ITerm2PanelDetector.swift       （新增）
├── HardwareSimulatorPlugin.swift   （修改：添加 panel 检测方法）
```

**关键代码（Swift）：**
```swift
class ITerm2PanelDetector {
    /// 获取 iTerm2 所有 panel 信息
    static func getPanels() -> [[String: Any]] {
        guard let iterm2 = getITerm2App() else { return [] }
        
        var panels: [[String: Any]] = []
        let windows = getWindowList(for: iterm2)
        
        for window in windows {
            // 遍历窗口的子元素，找到 AXSplitGroup
            let splitGroups = findSplitGroups(in: window)
            
            for (index, group) in splitGroups.enumerated() {
                if let bounds = getBounds(for: group) {
                    panels.append([
                        "id": "panel_\(index)",
                        "title": getTitle(for: group) ?? "Panel \(index + 1)",
                        "x": Int(bounds.origin.x),
                        "y": Int(bounds.origin.y),
                        "width": Int(bounds.size.width),
                        "height": Int(bounds.size.height),
                        "isActive": isActive(group)
                    ])
                }
            }
        }
        
        return panels
    }
    
    /// 获取 iTerm2 应用的 AXUIElement
    private static func getITerm2App() -> AXUIElement? {
        let apps = NSWorkspace.shared.runningApplications
        guard let iterm2 = apps.first(where: { 
            $0.bundleIdentifier == "com.googlecode.iterm2" 
        }) else {
            return nil
        }
        return AXUIElementCreateApplication(iterm2.processIdentifier)
    }
}
```

**Dart 接口：**
```dart
// lib/services/iterm2_panel_service.dart
class ITerm2PanelService {
  static const MethodChannel _channel = 
      MethodChannel('hardware_simulator');
  
  /// 获取所有 iTerm2 panel
  Future<List<PanelInfo>> getPanels() async {
    final result = await _channel.invokeMethod('getITerm2Panels');
    return (result as List).map((e) => PanelInfo.fromMap(e)).toList();
  }
  
  /// 监听 panel 变化（可选）
  Stream<List<PanelInfo>> get panelStream {
    // 定时轮询或使用事件监听
  }
}
```

### 阶段 2：视频帧裁剪实现（预计 1 天）

**方案 A：使用 WebRTC VideoTrackSource（性能最优）**
```dart
// 在获取 MediaStream 后添加 Transform
void applyCropToTrack(MediaStreamTrack track, CropConfig crop) {
  // 使用 WebRTC 原生能力裁剪
  // 需要在 native 层实现
}
```

**方案 B：使用 Canvas 裁剪（通用但性能稍差）**
```dart
class VideoFrameCropper {
  RTCVideoRenderer? _renderer;
  
  Future<void> cropAndStream(
    MediaStream source, 
    CropConfig crop
  ) async {
    // 1. 渲染原始帧到隐藏 Canvas
    // 2. 裁剪目标区域
    // 3. 创建新的 MediaStream
  }
}
```

### 阶段 3：UI 设计与实现（预计 1 天）

参考现有的 `keyboard_layout_mock_v2.html` 风格，创建 Panel 切换器。

**UI 组件：**
```dart
// lib/widgets/iterm2_panel_switcher.dart
class ITerm2PanelSwitcher extends StatefulWidget {
  final Function(PanelInfo) onPanelSelected;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      // 悬浮面板，类似快捷键按钮
      child: Column(
        children: [
          // Panel 列表
          Expanded(
            child: ListView(
              children: panels.map((panel) => 
                PanelListItem(
                  panel: panel,
                  onTap: () => onPanelSelected(panel),
                )
              ).toList(),
            ),
          ),
          // 快捷键提示
          Text('快捷键：1-9 切换 Panel'),
        ],
      ),
    );
  }
}
```

**集成到主界面：**
在 `global_remote_screen_renderer.dart` 的 Stack 中添加 Panel 切换器悬浮按钮。

### 阶段 4：优化与测试（预计 1 天）

1. **性能优化**
   - 使用硬件加速裁剪（Metal/VideoToolbox）
   - 缓存 panel 列表，减少 Accessibility API 调用
   - 异步更新裁剪坐标

2. **边界情况处理**
   - iTerm2 未运行时的降级
   - Panel 关闭时自动切换到其他 panel
   - 窗口大小改变时重新计算坐标

3. **测试场景**
   - 2x2 四宫格布局
   - 不对称布局（1大2小）
   - 动态添加/删除 panel

## 技术风险与应对

### 风险 1：Accessibility API 权限

**问题**：macOS 需要用户授予辅助功能权限。

**应对**：
- 在首次使用时引导用户开启权限
- 提供详细的权限设置步骤
- 权限未授予时降级到全窗口捕获

### 风险 2：帧裁剪性能

**问题**：实时裁剪可能增加 CPU 负载。

**应对**：
- 优先使用 WebRTC 原生裁剪能力
- 降低裁剪帧率（如每秒只裁剪 30 帧）
- 使用 GPU 加速（Metal）

### 风险 3：iTerm2 版本兼容性

**问题**：不同版本的 iTerm2 窗口结构可能不同。

**应对**：
- 测试主流 iTerm2 版本（3.4+）
- 提供多种检测策略（AX hierarchy 遍历）
- 检测失败时回退到手动框选模式

## 备选方案

### 方案 B：屏幕捕获 + 区域裁剪

如果窗口捕获遇到问题，可以：
1. 捕获整个屏幕
2. 获取 iTerm2 窗口的绝对位置
3. 计算 panel 的屏幕坐标并裁剪

缺点：性能较差，隐私问题。

### 方案 C：iTerm2 Python API

iTerm2 提供 Python API，可以：
1. 获取 session 内容（纯文本）
2. 本地渲染成图像
3. 串流渲染后的图像

缺点：只适用于纯文本终端，无法捕获图形界面。

## 参考资料

- [iTerm2 Python API](https://iterm2.com/python-api/)
- [macOS Accessibility Programming Guide](https://developer.apple.com/library/archive/documentation/Accessibility/Conceptual/AccessibilityMacOSX/)
- [WebRTC VideoTrackSource](https://webrtc.github.io/webrtc-org/native-code/native-apis/)

## 变更日志

- 2026-01-25: 初始版本，定义核心架构和实现计划
