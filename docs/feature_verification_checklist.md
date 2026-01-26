# iTerm2 Panel 串流功能 - 基础功能验证清单

## 概述

在实现完整功能前，需要先验证以下基础功能是否可用。

## 验证清单

### 1. macOS 系统集成

- [ ] 确认 macOS 版本支持（需要 macOS 10.15+）
- [ ] 验证 Accessibility API 权限获取
- [ ] 测试 NSWorkspace API 获取运行应用
- [ ] 测试 AXUIElement 访问窗口元素

### 2. WebRTC 视频捕获

- [ ] 验证 `desktopCapturer.getSources(types: [SourceType.Window])` 可用
- [ ] 测试捕获 iTerm2 窗口
- [ ] 验证 MediaStream 获取成功
- [ ] 测试视频流播放

### 3. 视频帧处理

- [ ] 验证 MediaStreamTrack 访问
- [ ] 测试视频帧读取
- [ ] 验证帧尺寸获取
- [ ] 测试帧数据访问（Uint8List）

### 4. 坐标计算

- [ ] 验证窗口相对坐标计算
- [ ] 测试屏幕绝对坐标转换
- [ ] 验证裁剪区域计算
- [ ] 测试边界检查

### 5. 状态管理

- [ ] 验证 Provider 状态更新
- [ ] 测试跨组件状态共享
- [ ] 验证状态持久化
- [ ] 测试状态重置

### 6. 交互逻辑

- [ ] 验证键盘事件监听（数字键 1-9）
- [ ] 测试快捷键绑定
- [ ] 验证点击事件处理
- [ ] 测试手势事件监听

## 验证方法

### 方法 1：创建独立测试脚本

为每个基础功能创建独立的测试脚本：

```
scripts/verify/
├── verify_accessibility.sh        # 验证 Accessibility API
├── verify_webrtc_capture.sh       # 验证 WebRTC 捕获
├── verify_video_processing.sh     # 验证视频处理
└── verify_state_management.sh     # 验证状态管理
```

### 方法 2：使用 Flutter DevTools

- 打开 Flutter DevTools
- 检查 Widget 树
- 验证状态变化
- 监控性能

### 方法 3：手动验证清单

在真机上逐项测试并记录结果。

## 下一步

1. **优先验证**：Accessibility API + WebRTC 捕获（核心功能）
2. **创建验证脚本**：自动化基础功能测试
3. **记录验证结果**：更新此清单

## 参考文档

- [macOS Accessibility Programming Guide](https://developer.apple.com/library/archive/documentation/Accessibility/Conceptual/AccessibilityMacOSX/)
- [WebRTC Desktop Capturer](https://webrtc.github.io/webrtc-org/native-code/native-apis/)
- [Flutter Platform Channels](https://docs.flutter.dev/development/platform-integration/platform-channels)
