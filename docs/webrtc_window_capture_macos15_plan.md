# macOS 15 窗口级捕获（WebRTC）研究与最小落地方案

## 背景

- 当前项目在 macOS 15.2（内核 26.2）上：
  - `SourceType.Screen`（整屏捕获）正常。
  - `SourceType.Window`（窗口捕获）在多窗口（iTerm2、微信等）出现绿屏/内容错位。
  - `desktopCapturer.getSources(... thumbnailSize ...)` 返回的 `source.thumbnail` 正常。

结论：窗口列表与静态缩略图链路可用，但 **实时窗口捕获链路**（`getDisplayMedia(window)`）在 macOS 15 上存在兼容性问题。

## 为什么不直接用 Swift 脚本验证 ScreenCaptureKit

我们尝试用 `swift scripts/verify/sck_window_capture.swift` 做最小抓帧，但在 Swift 脚本环境触发 SkyLight 初始化断言（`CGS_REQUIRE_INIT`）。

结论：ScreenCaptureKit 的 `SCStream` 需要运行在完整的 macOS App 进程/RunLoop 环境中，Swift REPL/脚本不适合作为验证载体。

## 最小落地（MVP）建议

目标：以最小改动让 macOS 15 上 **window capture 可用**，用于后续“只串流某个窗口/切换窗口”。

### 路线 A：在 flutter-webrtc 插件内实现 ScreenCaptureKit window capture（推荐）

1. **不改 Dart API**：仍然从 Dart 侧通过 `desktopCapturer.getSources(types:[Window])` 获取窗口列表。
2. **替换 native window capture**：在 macOS 端 `getDisplayMedia` 的 window source 分支，改为 ScreenCaptureKit 输出 `CVPixelBuffer`。
3. **注入 WebRTC**：将 `CVPixelBuffer` 转成 `RTCCVPixelBuffer` → `RTCVideoFrame`，通过 `RTCVideoCapturerDelegate` 投递给 `RTCVideoSource`。

关键难点：

- 需要把 Dart 侧 sourceId 与 SCK 的 `SCWindow.windowID` 做映射（稳定）。
  - 目前 `desktopCapturer` 只提供 `id`/`name`，`name` 可能变化。
  - 需要在 native 的 sources 列表里把 `CGWindowNumber` 或 `SCWindow.windowID` 回传给 Dart。

### 路线 B：升级/替换 WebRTC.xcframework（备选）

如果上游 WebRTC 在 macOS 15 已修复 legacy window capture，也可以通过升级 xcframework 的方式规避。

风险：升级可能影响其他平台/编解码稳定性。

## 验证清单（MVP）

- [ ] 在 macOS 15 上选择任意窗口（微信/iTerm2）进行 window capture，RTCVideoView 正常显示
- [ ] fps 15/30 均可工作
- [ ] 切换窗口 source 后仍可正常显示
- [ ] 与现有 Screen capture 不互相影响

