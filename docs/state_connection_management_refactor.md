# 状态管理 + 连接管理重构整合方案（落盘）

> 日期：2026-02-01
>
> 目的：把当前工程里分散的“状态管理 + 连接编排”收敛到 **单一真相源** 与 **单一编排入口**，并让核心逻辑可被唯一 CLI 驱动与测试覆盖。

---

## 1. 背景：当前不健康的状态/连接结构

### 1.1 多真相源（State Duplication）

同一类事实在多个位置各自维护（会漂移）：

- 会话集合（controller）：`lib/services/streaming_manager.dart` 的 `StreamingManager.sessions`
- 会话集合（host）：`lib/services/streamed_manager.dart` 的 `StreamedManager.sessions`
- 当前活跃会话指针：`lib/services/webrtc_service.dart` 的 `currentRenderingSession/currentDeviceId`
- 设备连接状态：`lib/entities/device.dart` 的 `Device.connectionState (ValueNotifier)`
- 会话内部状态：`lib/entities/session.dart` 的 `StreamingSession.connectionState`

后果：UI 看到的状态与真实连接状态不一致（例如“已经连上但界面还是原来的设置界面”）。

### 1.2 编排入口分散（Competing Orchestrations）

连接/重连/恢复逻辑散落在：

- `lib/services/websocket_service.dart`（cloud WS 重连）
- `lib/services/lan/lan_signaling_client.dart`（LAN WS 连接与 auto-restore）
- `lib/services/app_lifecycle_reconnect_service.dart`（前后台恢复）
- `lib/utils/widgets/device_tile_page.dart`（页面里也有恢复/重连逻辑）
- `lib/entities/session.dart`（会话内部还有 restore/auto-pick 等逻辑）

后果：冷启动/后台恢复/断线时可能多路重连、重复请求、竞态导致“偶现连不上/切换失败/状态错乱”。

### 1.3 配置与会话耦合（Settings Contamination）

`lib/global_settings/streaming_settings.dart` 被同时用于：

- 用户配置（长期）
- 会话输入（短期，且会在 `StreamingManager.startStreaming` 中写入密码明文/哈希）

后果：跨会话污染、测试难复现、CLI 很难精确驱动。

---

## 2. 目标架构（必须遵守）

### 2.1 分层（编排 vs 基础块 vs UI）

- **Core（唯一实现）**：`lib/core/**`
  - 所有算法/策略/协议解析/判定只能在 core
  - 需可被 **CLI** 与 **测试** 调用
- **App 编排层**：`lib/app/**`
  - 维护 `AppState`（单一真相源）
  - 维护 `AppStore.dispatch(AppIntent)`（唯一编排入口）
  - 执行副作用（EffectRunner）并把结果回灌成内部 intent
- **UI**：`lib/pages/**` `lib/widgets/**`
  - 只订阅 `AppState`，只发送 intent
  - 不直接调用 WebSocket/WebRTC/LAN/Settings 单例

### 2.2 单一真相源（Single Source of Truth）

引入：

- `AppState`：全局状态树（sessions/devices/quick/ui/diagnostics）
- `AppStore`：唯一可写入口（dispatch intent）

UI 不再把 `Device.connectionState` / `WebrtcService.currentRenderingSession` 作为真相，只能作为兼容镜像（过渡期）。

---

## 3. 状态模型（Session / CaptureTarget / Metrics）

> 这些类型必须在 `lib/app/state/**` 中实现，便于 UI 与编排层共享、便于测试。

### 3.1 SessionState

- `TransportKind`：`cloud` / `lan`
- `SessionPhase`：`idle -> signalingConnecting -> signalingReady -> webrtcNegotiating -> dataChannelReady -> streaming -> disconnecting -> disconnected/failed`

### 3.2 CaptureTarget（统一 screen/window/iterm2）

统一字段：

- `captureTargetType`：`screen|window|iterm2`
- `desktopSourceId` / `windowId` / `iterm2SessionId`
- `cropRectNorm`（只允许来自 host/calc，不允许被本地 zoom/pan 污染）

### 3.3 Metrics（解码/渲染/网络）

必须区分：

- 解码帧率（WebRTC stats）
- 渲染帧率（Flutter FrameTiming）

---

## 4. Intent + Effect（唯一编排入口）

### 4.1 AppIntent（UI -> Store）

所有动作都必须经由 intent：

- 连接（cloud / LAN）
- 断开
- 切换 capture target（screen/window/iterm2）
- 生命周期事件（resumed/paused）
- 上传诊断日志（LAN）
- 刷新 LAN hints
- 上报 render perf / host encoding status

### 4.2 AppEffect（Store -> 副作用）

所有副作用集中在 EffectRunner：

- 调用现有 `StreamingManager` / `LanSignalingClient` / `WebSocketService`
- 持久化 quick target / LAN hints
- probe `/artifact/info` 后上传日志
- 统一重试 backoff（5s -> 9s -> 26s）

---

## 5. 迁移计划（严格分阶段）

### Phase 0：文档 + 任务清单（本文件 + task.md）

### Phase A：不重写底层会话，仅“统一编排 + 单一真相源”

- 引入 `AppState/AppStore`
- UI 改为 dispatch intent（不直接调用底层单例）
- 汇聚现有事件源（WebSocket/LAN/hostEncodingStatus/captureTargetChanged）更新 AppState

### Phase B：收敛配置与状态源

- QuickTarget 从 service 单例迁到 `AppState.quick`，持久化通过 repo/effect
- `StreamingSettings` 会话污染收敛到 SessionConfig（或封装写入/清理）

### Phase C：抽象 transport/webrtc，并删除重复恢复逻辑

- `AppLifecycleReconnectService` 降级为仅 dispatch lifecycle intent
- 删除 UI 内部的 restore/重连逻辑

---

## 6. 验证与证据要求

每一步必须提供：

- `flutter test` 全绿（至少覆盖改动相关测试）
- `flutter analyze` 无 error（允许历史 warning/info，但不得引入新 error）
- 连接/切换/裁切相关改动必须跑 verify（本地生成 `build/verify/**` 证据，不入 git）

### 6.1 验收标准（Phase A / Phase B）

**Phase A（统一编排 + 单一真相源，底层不重写）**

- UI 行为不依赖单例状态（允许兼容镜像，但 UI 展示以 `AppState` 为准）
- 连接/断开/切换目标均由 intent 触发并可单测覆盖
- 前后台恢复的重连节流统一由 runner/backoff 负责（避免 UI 层多路重连）
- `flutter test` 全绿；`flutter analyze` 无 error

**Phase B（收敛配置与状态源）**

- QuickTarget 的“上次连接/收藏/快捷切换”仅有一处持久化与一处读取（repo），UI 只读 `AppState.quick`
- SessionConfig（或等价封装）保证“会话输入/用户配置”不再混写到全局 `StreamingSettings`

### 6.2 回滚策略（可操作）

本重构按阶段交付，回滚以“最小风险恢复可用性”为目标：

- **Phase A 回滚**：删除/回退 `lib/app/**` 的 store/reducer/effects 相关改动，UI 重新直接调用旧 service；底层单例未被删除，回滚不会破坏 WebRTC/WebSocket/LAN 运行。
- **Phase B/C 回滚**：保持旧持久化格式兼容（读老写新），并保证新 repo 可被替换为旧 service；若出现线上问题，可回退到 Phase A 的稳定版本。

### 6.3 测试清单（强制）

**每次改动必跑**

- `flutter test`
- `flutter analyze --no-fatal-warnings --no-fatal-infos`（要求 0 error）

**涉及连接/切换/裁切/输入时必跑（macOS 可用时）**

- `dart run scripts/verify/verify_iterm2_panels_loopback.dart`
- `dart run scripts/verify/verify_iterm2_panel_encoding_matrix_manual_app.dart`

