# 快捷键功能 - 设计实施计划（待审核）

> 本文为“设计报告 + 任务跟踪”入口文件。请先审核“设计方案”部分，确认后再进入“执行任务清单”。

## 一、背景与目标

### 1.1 背景
- 已完成快捷键功能的核心代码与设计文档，详见：
  - `docs/shortcut_bar_design.html`
  - `docs/shortcut_implementation_guide.md`
  - `docs/shortcut_summary.md`
  - `docs/shortcut_final_summary.md`

### 1.2 本阶段目标（MVP）
- 在现有虚拟键盘之上集成快捷键条（Shortcut Bar）。
- 支持 Windows/macOS/Linux 三平台预设快捷键。
- 提供设置弹窗：平台切换、启用/禁用快捷键。
- 完成按键发送逻辑与持久化保存。

### 1.3 本阶段不做的内容（Out of Scope）
- 自定义快捷键编辑器
- 拖拽排序
- 导入/导出配置
- 快捷键录制

## 二、设计方案（请重点审核）

### 2.1 用户体验与界面设计
- 快捷键条位于虚拟键盘上方，独立横向滚动。
- 左侧固定“设置”按钮，打开底部抽屉式设置面板。
- 快捷键按钮包含：图标（emoji）+ 组合键文本。
- 按压反馈：缩放动画 + 轻触觉反馈。

### 2.2 交互与状态
- 平台切换后：快捷键列表立即切换为对应平台预设。
- 启用/禁用快捷键：仅影响显示与发送行为，不影响数据结构。
- 数据持久化：保存当前平台 + 快捷键启用状态 + 顺序。

### 2.3 数据结构与服务层
- 数据模型位于 `lib/models/shortcut.dart`，核心结构：
  - `ShortcutItem`：id/label/icon/keys/platform/enabled/order
  - `ShortcutKey`：key/keyCode
  - `ShortcutSettings`：platform/items
- 数据服务位于 `lib/services/shortcut_service.dart`：
  - SharedPreferences 存储 `shortcut_settings` JSON
  - 提供 init/get/update/reset

### 2.4 按键发送逻辑
- 组合键发送顺序：依次 keyDown → 50ms → 逆序 keyUp。
- keyCode 字符串映射为 Windows VK（在 `enhanced_keyboard_panel.dart`）。
- 保留 `OnScreenVirtualKeyboard` 兼容入口，但内部委托 `EnhancedKeyboardPanel`。

### 2.5 集成方案
- 将 `OnScreenVirtualKeyboard` 调用点替换为 `EnhancedKeyboardPanel`。
- 若需要全局初始化：`main.dart` 中 `ShortcutService().init()`。

### 2.6 风险与验证点
- 键码映射覆盖不全 → 需验证常用组合键。
- 远端系统差异（Win/macOS/Linux） → 需真机验证。
- 设置状态同步（UI↔持久化） → 需反复开关测试。

## 三、验收标准

### 功能验收
- 打开虚拟键盘时快捷键条可见。
- 点击任意快捷键可在远程桌面触发对应动作。
- 设置弹窗可切换平台，列表即时更新。
- 启用/禁用后，快捷键显示与行为一致。
- 重启应用后，设置保持。

### 体验验收
- UI 与设计规范一致（颜色/尺寸/布局/动效）。
- 无明显卡顿或异常闪烁。

## 四、执行任务清单（审核通过后启用）

> 状态说明：
> - [ ] 未开始
> - [~] 进行中
> - [x] 已完成

### 4.1 设计复核
- [x] 确认最小功能模块（MVP）范围
- [x] 打开 `docs/shortcut_bar_design.html` 进行 UI 对照确认
- [ ] 确认快捷键清单满足当前版本需求
- [ ] 确认 Out of Scope 内容不进入当前版本

### 4.2 集成落地
- [x] 替换 `OnScreenVirtualKeyboard` → `EnhancedKeyboardPanel`
- [ ] 确认 `ShortcutService` 初始化策略（是否放入 `main.dart`）
- [ ] 本地运行与基本交互验证

### 4.3 功能验证
- [ ] Windows 预设 8 个快捷键逐项测试
- [ ] macOS 预设 8 个快捷键逐项测试
- [ ] Linux 预设 8 个快捷键逐项测试
- [ ] 设置弹窗平台切换 + 启用/禁用逻辑验证
- [ ] 重启后持久化验证

### 4.4 构建与交付
- [ ] 构建 APK（debug 或 release）并交付测试

### 4.5 文档补充（如需）
- [ ] 补充“已知问题 / 兼容性说明”
- [ ] 补充“下一阶段扩展建议”的优先级

## 五、已确认事项（来自最新指示）

1. **范围确认**：按最小功能模块（MVP）先做。
2. **流程确认**：先完成后构建 APK，交由你测试后再完善。

## 六、待确认事项（请你补充）

1. **构建类型**：优先 debug 还是 release APK？
2. **初始化方式**：是否需要在 `main.dart` 强制初始化 `ShortcutService`？
3. **测试平台优先级**：先验 Windows，再验 macOS/Linux 是否可接受？

---

# iTerm2 Panel 串流（研究 & UI 编排）任务

> 目标：聚焦 iTerm2 多 panel（session）检测与切换能力，作为“只串流某个 panel”的基础。
> 注意：本阶段先完成 **基础能力的 CLI 验证** 与 **静态 UI 模拟**，不直接进入最终功能实现。

## 一、已落盘文档/原型

- `docs/iterm2_panel_streaming_design.md`：设计方案（窗口捕获+裁剪、风险与计划）
- `docs/iterm2_panel_ui_mockup.html`：UI 静态交互原型
- `docs/ui_refactoring_plan.md`：在现有界面基础上重构 UI 的编排计划
- `docs/feature_verification_checklist.md`：基础功能验证清单（先验证后编排）

## 二、基础能力 CLI 验证（必须先完成）

> 状态说明：
> - [ ] 未开始
> - [~] 进行中
> - [x] 已完成

### 2.1 iTerm2 Python API 可用性

- [x] Python 包 `iterm2` 可导入（模块存在）
- [x] iTerm2 API 连接成功（`connected`）
- [x] 可枚举 window/tab/session（示例：检测到 sessions=12）
- [x] 可读取当前 session（`current_session.session_id`）
- [x] 可切换激活 session（使用 `await session.async_activate()`）

#### 验证命令记录

```bash
python3 - <<'PY'
import importlib.util
print('iterm2 module found:', bool(importlib.util.find_spec('iterm2')))
PY

python3 - <<'PY'
import iterm2
async def main(connection):
    print('connected')
    app = await iterm2.async_get_app(connection)
    print('windows:', len(app.windows))
iterm2.run_until_complete(main)
PY

python3 - <<'PY'
import iterm2
async def main(connection):
    app = await iterm2.async_get_app(connection)
    items=[]
    for w_i,w in enumerate(app.windows):
        for t_i,tab in enumerate(w.tabs):
            for s_i,session in enumerate(tab.sessions):
                items.append((w_i,t_i,s_i,session.session_id,session.name))
    print('sessions:', len(items))
    for w_i,t_i,s_i,sid,name in items:
        print(f'w{w_i} t{t_i} s{s_i} id={sid} name={name}')
iterm2.run_until_complete(main)
PY

python3 - <<'PY'
import iterm2
async def main(connection):
    app = await iterm2.async_get_app(connection)
    tab = app.current_terminal_window.current_tab
    before = tab.current_session.session_id
    target = tab.sessions[1]
    print('before:', before)
    print('target:', target.session_id)
    await target.async_activate()
    after = tab.current_session.session_id
    print('after:', after)
iterm2.run_until_complete(main)
PY
```

### 2.2 WebRTC 窗口捕获基础能力（后续验证项）

- [ ] `desktopCapturer.getSources(types: [SourceType.Window])` 能列出 iTerm2 窗口源
- [ ] `navigator.mediaDevices.getDisplayMedia` 能捕获 iTerm2 窗口并生成 MediaStream
- [ ] 串流侧能正常播放

#### 验证脚本（已创建）

- `scripts/verify/verify_webrtc_window_capture_app.dart`：Flutter macOS 验证小程序（列出窗口源、下拉选择、Start 捕获并预览）
- `scripts/verify/verify_webrtc_window_capture.sh`：一键运行脚本

运行方式：

```bash
scripts/verify/verify_webrtc_window_capture.sh
```

预期结果：
- 点击右上角刷新按钮能加载 `Window + Screen` 源
- 下拉列表中能看到 iTerm2（若 iTerm2 正在运行）
- 点击 Start 触发系统权限弹窗（若未授权），授权后能看到窗口画面预览

#### 当前阻塞（已复现）

- `flutter run -d macos` 在当前环境失败：`xcrun: error: unable to find utility "xcodebuild"`
- 这表示本机未安装/未配置 Xcode Command Line Tools（或 PATH 未包含开发者工具）

---

# 网络缓冲（延迟优先）任务

> 目标：默认极低延迟（5 frames jitter buffer），仅在 **已降质仍卡顿** 时才增加缓冲。

## 现状问题（已确认）
- 旧策略是 1~10 秒级的 `jitterBufferMinimumDelay`，在网络波动时会把端到端延迟直接拉高。
- 用户期望：**低延迟优先**，默认仅 5 帧缓冲，只有在降帧/降码率后仍卡才考虑增加缓冲。

## 本次实现（已完成）
- 缓冲策略从 “秒” 改为 “帧”，默认 `base=5f`，最大 `max=60f`（Android best-effort）。
- 仅当 **degraded + unstable** 时才允许增大 buffer：
  - degraded：出现 freeze / rxFps<=15 / rxKbps 很低
  - unstable：loss/jitter/rtt 触发阈值
- Debug overlay 增加 `Buffer: {frames}f {seconds}s`，方便你现场判断策略是否在工作。

## 验证（已完成）
- `flutter test` 全量通过（包含 `test/video_buffer_policy_test.dart`）。

---

# 串流恢复 / 输入法 / 坐标（功能修复任务）

> 目标：把“恢复上次连接 + 手动控制系统输入法 + 缩放/键盘下坐标稳定 + 防溢出”这条链路做扎实，优先保证 **可重复验证** 与 **回环测试**，再做 UI/体验打磨。

## 一、问题清单（来自最新反馈）

1. **启动后未恢复上次连接页面**
   - 期望：App 启动进入“上次连接的设备 + 上次选择的串流目标（桌面/窗口/iTerm2 panel）”
   - 现状：默认进入全屏桌面，需手动进入设备页并切换。

2. **iTerm2 快捷目标点击不切换**
   - 期望：点击底部 panel 快捷立刻切换，并且在 DataChannel 未就绪时给出明确反馈/延迟执行。

3. **放大后弹出键盘导致点击坐标偏移**
   - 期望：弹出键盘仅“把视频区域向上抬起”，不应改变已缩放/平移画面的相对定位与触控映射。

4. **页面模式（scroll/布局）弹出键盘后 overflow / 卡死**
   - 期望：键盘出现时画面上移且有溢出保护；不会把渲染区域挤成 0 导致黑屏或布局异常。

## 二、执行策略（必须逐步验证）

### 2.1 本地回环验证优先

- [ ] 增加/完善回环测试：连接、切换模式、切换窗口/面板、输入输出、坐标映射
- [ ] 统一记录“切换请求 → host ack → controller 状态”三段证据（日志 + 单测断言）

### 2.2 状态持久化与恢复

- [ ] 连接成功后持久化“上次连接设备”的匹配信息（不仅是 uid；需可在设备列表中定位）
- [ ] App 启动后：设备列表刷新完成时自动定位并进入该设备详情页
- [ ] 进入详情页后：自动触发连接（使用本地保存的密码），并在 DataChannel 打开时恢复上次串流目标
- [ ] 前后台切换：在串流页恢复时优先尝试 reconnect（失败再提示）

### 2.3 输入法与缩放/坐标稳定

- [ ] 系统输入法（Android/iOS）只允许“用户点击键盘按钮”显隐；禁止点击画面时自动隐藏
- [ ] 缩放/平移状态下，键盘弹出/消失不应造成触控映射漂移
- [ ] 保护：keyboardInset + overlayInset 不能把视频区域挤到不可用（做 clamp / minHeight）

## 三、验收证据（完成后需提供）

- [ ] `flutter test` 全绿
- [ ] 新增/更新单测覆盖上述 4 类问题（至少 1 个“恢复”+ 1 个“坐标/键盘”）
- [ ] 关键日志片段：显示 restore 的目标（模式/窗口/面板 id）+ DataChannel open + captureTargetChanged ack


解决方式：

```bash
xcode-select --install
# 或切换到已安装的 Xcode：
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

#### 最新进展（已验证可运行）

- [x] 在本机切换到 Xcode Developer 路径后，`scripts/verify/verify_webrtc_window_capture.sh` 可以成功构建并启动 macOS 验证 App。
- [~] App 内已完成：sources 加载成功（captureSources: 21），并触发窗口捕获开始（start desktop capture: sourceId: 65, type: window, fps: 30）。
- [ ] 仍需确认：捕获开始后 UI 是否能持续显示预览（目前反馈“点击后 app 消失/退后台”）。

#### 观察与结论（阶段性）

- ✅ `desktopCapturer.getSources` 能返回窗口源（已看到 sources 数量日志）。
- ✅ 捕获流程已进入 native “start desktop capture” 阶段。
- ⚠️ 捕获开始后应用可能短暂退后台（系统 UI/前台切换），但可通过手动激活回到前台继续验证。

#### 最新验证结果（已截图确认）

- [x] `getDisplayMedia` 返回成功：`videoTracks=1`。
- [x] 捕获可输出画面（预览区出现画面，但当前示例选择了 `dartaotruntime` 窗口，画面呈现绿色噪点）。
- [ ] 需要进一步验证：捕获 iTerm2 窗口时画面是否正常（窗口名可能动态变化，需用更稳定的匹配策略）。

## 三、使用 iTerm2 Python API 获取 panel（session）尺寸能力（补充验证）

- [x] iTerm2 Python API 可返回当前 session 的 `frame`（像素级 origin/size）与 `grid_size`。

## 四、建议：用 iTerm2 Python API 提供稳定“命名/定位”信息

> 目的：iTerm2 窗口标题（WebRTC sources.name）可能频繁变化，直接用窗口名匹配不可靠。
> 改用 iTerm2 API 输出的 tab/session 变量做“稳定标签”，再在 UI 中展示给用户选择。

已验证：

- [x] `tab.title` 可通过 `session.async_get_variable('tab.title')` 获取（示例返回 `node`）。
- [x] `session.name`、`session.path`、`session.hostname`、`session.username` 可通过 `async_get_variable` 获取。
- [x] 可直接枚举 `window_id`（如 `pty-...`）以及每个 session 的 `frame`（用于后续裁剪坐标）。

示例命令：

```bash
python3 - <<'PY'
import iterm2
async def main(connection):
    app = await iterm2.async_get_app(connection)
    w = app.current_terminal_window
    tab = w.current_tab
    s = tab.current_session
    print('window_id:', w.window_id)
    print('tab.title:', await s.async_get_variable('tab.title'))
    print('session.name:', await s.async_get_variable('session.name'))
    print('session.path:', await s.async_get_variable('session.path'))
    print('frame:', s.frame)
iterm2.run_until_complete(main)
PY
```

落地建议：

1. UI 列表用 iTerm2 的 `tab.title + session.name + session.path` 组合显示（对用户友好、且比窗口名稳定）。
2. 在“捕获窗口源”层，避免强依赖窗口名，改为：
   - 先让用户选择 WebRTC Window source（一次），或
   - 使用更稳定的特征（bundle/app + 最近选中）来锁定 iTerm2 主窗口。
3. Panel 切换：通过 iTerm2 API `session.async_activate()` 切换激活 pane，并同步裁剪区域到对应 `session.frame`。

示例：

```bash
python3 - <<'PY'
import iterm2
async def main(connection):
    app = await iterm2.async_get_app(connection)
    s = app.current_terminal_window.current_tab.current_session
    print('frame:', s.frame)
    print('grid_size:', s.grid_size)
iterm2.run_until_complete(main)
PY
```

### 2.3 视频裁剪基础能力（后续验证项）

- [x] 能拿到“目标 panel”的像素边界（来源：iTerm2 Python API 或辅助方式）
- [x] 能对视频帧进行裁剪（或通过 native 支持）

验证记录（2026-01-26）：

1) 通过系统命令对 iTerm2 窗口截图（写入剪贴板）：

```bash
screencapture -c -x iTerm2
```

2) 通过 AppKit 从剪贴板落盘 PNG：

```bash
python3 - <<'PY'
from AppKit import NSPasteboard
import os
pb = NSPasteboard.generalPasteboard()
data = pb.dataForType_("public.png")
if data:
    path = "build/verify/iterm2-window.png"
    data.writeToFile_atomically_(path, False)
    print(f"Saved: {path}")
    os.system(f"ls -lh {path}")
else:
    print("No PNG in clipboard")
PY
```

3) 通过 iTerm2 Python API 获取 panel frame（已验证可用）：

```bash
python3 - <<'PY'
import iterm2, json
async def main(connection):
    app = await iterm2.async_get_app(connection)
    w = app.current_terminal_window
    s = w.current_tab.current_session
    f = s.frame
    data = {
        "window_id": w.window_id,
        "session_id": s.session_id,
        "session_name": s.name,
        "frame": {"x": f.origin.x, "y": f.origin.y, "w": f.size.width, "h": f.size.height},
        "grid": {"w": s.grid_size.width, "h": s.grid_size.height}
    }
    print(json.dumps(data))
iterm2.run_until_complete(main)
PY
```

4) 用 frame 裁剪（本次确认使用“bottom-left → top-left”的坐标换算）：

```bash
python3 - <<'PY'
import json, os
from PIL import Image
meta_path = 'build/verify/iterm2-panel-meta.json'
img_path = 'build/verify/iterm2-window.png'
out_path = 'build/verify/iterm2-panel.png'
with open(meta_path, 'r') as f:
    meta = json.load(f)
x = int(round(meta['frame']['x']))
y = int(round(meta['frame']['y']))
w = int(round(meta['frame']['w']))
h = int(round(meta['frame']['h']))
img = Image.open(img_path)
img_w, img_h = img.size
# bottom-left -> top-left
box = (x, img_h - (y+h), x+w, img_h - y)
box = (max(0, min(img_w, box[0])), max(0, min(img_h, box[1])),
       max(0, min(img_w, box[2])), max(0, min(img_h, box[3])))
img.crop(box).save(out_path)
print('Saved:', out_path)
os.system(f"ls -lh {out_path}")
PY
```

产物：

- `build/verify/iterm2-window.png`
- `build/verify/iterm2-panel.png`

备注：`pngpaste` 不存在，使用 AppKit 读取剪贴板成功。

对齐修正（2026-01-26）：

- 发现问题：直接用 `top = img_h - (y + h)` 裁剪时，产物与 pane 内容有垂直偏移（窗口没有对齐）。
- 原因：iTerm2 `session.frame.y` 的坐标系更接近 `visibleFrame`（不含菜单栏），而 `screencapture` 得到的是整屏像素（含菜单栏），导致需要额外扣掉菜单栏高度。
- 修正：从 iTerm2 Python API 读 `window.frame.y`（当前机器为 74），在换算时额外减去该值：

  - `top = img_h - (y + h) - window_frame.y`

- 已固化为一键脚本（无需 AppleScript window id）：`scripts/verify/verify_iterm2_panel_screenshot.sh`

一键验证命令：

```bash
scripts/verify/verify_iterm2_panel_screenshot.sh
```

该脚本会在 `build/verify/` 下生成带时间戳的：

- `iterm2-window-*.png`
- `iterm2-panel-*.png`
- `iterm2-panel-meta-*.json`

## 三、UI 静态模拟（在基础能力验证之后）

- [x] `docs/iterm2_panel_ui_mockup.html` 可交互：点击/数字键切换“panel”
- [ ] 将 UI 方案映射到 Flutter 现有 Stack 结构（不接后端，仅 mock 数据）
- [ ] 与 `FloatingShortcutButton` / 小地图 / 虚拟鼠标的层级与手势不冲突

## 四、UI 编排与重构（后续执行）

- [ ] 确认最终 UI 形态：左上角触发按钮 + 左侧抽屉面板（推荐）
- [ ] 实现 Flutter 静态组件（mock 数据）：Panel 列表、选中态、刷新按钮、快捷键提示
- [ ] 接入 iTerm2 Python API 的“panel 列表 + 激活切换”能力
- [ ] 评估“只串流某个 panel”的实现路线：窗口捕获 + 裁剪

## 五、macOS 15 窗口捕获（WebRTC）绿屏问题定位与修复

背景（2026-01-26）：

- macOS 15.2（内核 26.2）上：
  - `SourceType.Screen`（整屏捕获）正常
  - `SourceType.Window`（窗口捕获）出现绿屏/内容错位（微信/iTerm2 等多个窗口均复现）
  - 同时 `source.thumbnail` 正常（说明窗口列表/静态缩略图链路可用）

结论：legacy window capture 的实时帧链路在 macOS 15 上不可靠，需要改用 ScreenCaptureKit。

修复（最小可行，2026-01-26 已验证通过）：

- 在 macOS `getDisplayMedia` 的 window 分支，改为使用 ScreenCaptureKit 捕获并把 `CVPixelBuffer` 注入 WebRTC：
  - `SCShareableContent` → 匹配 `SCWindow`
  - `SCStreamConfiguration.pixelFormat` 使用 **NV12**：`kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`
  - `CVPixelBuffer` → `RTCCVPixelBuffer` → `RTCVideoFrame`
  - 使用真实 `RTCVideoCapturer` 通过 `RTCVideoCapturerDelegate` 投递帧

验证日志（节选）：

- `[SCK] startCapture ok` 且 `[SCK] first frame ...` 后画面恢复正常

代码位置：

- `plugins/flutter-webrtc/common/darwin/Classes/FlutterRTCDesktopCapturer.m`

后续待办：

- [ ] 用更稳定的标识做窗口映射（避免仅用窗口标题匹配）
- [ ] 清理/降级调试日志（保留必要的 error 日志）
- [ ] 处理多窗口切换与资源释放（多 stream 并发/重复 start/stop）

### 5.1 Monkey 测试（窗口切换 + 截图留档）

目的：快速做“切换窗口源 / Start/Stop / 截图留档”的回归测试，确保不再出现绿屏。

操作：

1) 启动 verify app：

```bash
scripts/verify/verify_webrtc_window_capture.sh
```

2) 在 app 内对多个窗口重复：

- 选 window source
- 点 `Start`（确认画面正常）
- 点 `Shot`（保存到 `build/verify/`）
- 点 `Stop`

输出：

- `build/verify/webrtc_window_capture_*.png`

辅助脚本（提示步骤）：

```bash
scripts/verify/monkey_webrtc_window_capture_macos.sh
```

## 六、下一阶段规划：窗口列表缩略图 + 切换 + 比例匹配

目标：形成“窗口列表 + 缩略图 + 一键切换 + 比例/裁剪”的稳定能力，为 iTerm2 pane 级串流打基础。

### 6.1 API 设计（P0）

WindowSource 结构（由 `getDesktopSources` 返回）：

- `id`: 现有 sourceId（与 WebRTC 内部对应）
- `windowId`: 原生窗口 ID（SCWindow.windowID / CGWindowID）
- `title`: 窗口标题
- `appId`: bundleId
- `appName`: 应用名
- `thumbnail`: bytes（PNG/JPEG）
- `thumbnailMime`: `image/png` / `image/jpeg`
- `w` / `h`: 缩略图尺寸

新增 MethodChannel：

- `getDesktopSourcesV2`：返回带缩略图的窗口列表（含缓存/节流策略）
- `setCaptureTarget`：`windowId` + 可选 `cropRect` + `targetAspect` / `targetSize`

### 6.2 缩略图生成（P0）

策略：macOS 端生成，Dart 只做展示。

- 来源：优先 `ScreenCaptureKit` / 备用 `CGWindowListCreateImage`
- 缓存：按 `windowId` 缓存最后缩略图（TTL 1–2s）
- 节流：同一窗口 500–1000ms 内不重复生成
- 格式：PNG（清晰）或 JPEG（小体积）

### 6.3 UI 列表与切换（P0）

---

# 代码重构（模块化 + 单一实现 + CLI）任务（待审核）

> 目标：把当前“可运行但耦合严重”的实现，重构为 **模块化/可测试/可通过 CLI 独立验证** 的架构；UI 仅做编排与渲染；核心逻辑只保留唯一实现。
>
> 执行原则：**先写清计划与验收（本章节）→ 再动代码 → 每一步必须有验证证据 → 不盲测。**

## 一、强制架构原则（必须遵守）

1. **唯一实现（Single Source of Truth）**
   - 同一能力（例如：裁切计算、手势判定、输入注入路由、码率/帧率自适应策略、消息 schema 解析）在项目中只能有一处实现。
   - UI、API、脚本、测试均不得复制逻辑；只能调用 core blocks。

2. **层次职责**
   - `lib/widgets/**`、`lib/pages/**`：只做 UI 渲染 + 轻量状态（ValueNotifier/Provider 等）+ 调用 blocks；**禁止**写业务算法/协议解析/输入注入策略。
   - `lib/services/**`：Facade / API 调度层；只负责生命周期、依赖注入、与 blocks 交互；**禁止**写算法与判定策略。
   - `lib/core/**`：blocks/use-cases（业务逻辑唯一实现）+ ports（平台依赖抽象）+ CLI 命令编排。
   - `bin/**`：唯一 CLI 入口（参数解析 + 调用 `lib/core/cli`），不写业务逻辑。

3. **验证优先**
   - 每一步提交前必须通过：`flutter analyze` + `flutter test`
   - 涉及串流/裁切/切换的改动必须跑 verify（见“验证栈”）。
   - 不允许把临时构建物、测试产物、截图、设备日志等提交进 git。

## 二、本轮重构范围（按优先级）

### P0（必须完成）
1. `lib/entities/session.dart`（连接/消息路由/切换/裁切/输入注入/自适应等耦合点）
2. `lib/utils/widgets/global_remote_screen_renderer.dart`（渲染 + 手势 + 坐标 + 发送策略混杂）
3. `lib/widgets/keyboard/floating_shortcut_button.dart`（UI/IME/快捷键发送/设置面板耦合）
4. 建立 `lib/core/**` + `bin/**` CLI 骨架，并用单测固定行为

### P1（后续）
1. `lib/settings_screen.dart`

### P2（后续）
1. `lib/utils/widgets/virtual_gamepad/control_management_screen.dart`

## 三、目标目录结构（重构后）

> 说明：本轮优先落地骨架与 P0 拆分；P1/P2 在后续迭代完成。

```
bin/
  cloudplayplus_cli.dart                    # 唯一 CLI 入口

lib/
  core/
    cli/
      cloudplayplus_cli.dart                # CLI 命令注册/分发（不含业务逻辑）
    blocks/                                 # 业务逻辑唯一实现（可被 CLI/API/UI 调用）
      ...                                   # 逐步迁移：gesture/encoding/input/capture/iterm2
    ports/                                  # IO/平台抽象（ProcessRunner/Clock/Logger/SettingsStore 等）

  app/                                      # 应用编排（调用 blocks；不写算法）
    ...

  entities/
    session.dart                            # 作为 library，拆成多个 part 文件
    session/
      ...                                   # signaling/router/capture/iterm2/input/adaptive/debug 等

  widgets/                                  # 纯 UI（渲染与交互）；逻辑下沉 blocks
    ...
```

## 四、验证栈（强制）

### 4.1 必跑（每个步骤）
```bash
flutter analyze
flutter test
```

> 备注：当前仓库存在大量历史 analyzer issue（warning/info）。本轮重构的门槛是：
> - `flutter analyze` **不得出现 error**；
> - 不新增与本次改动相关的 analyzer 问题（尤其是新文件/改动文件）。

### 4.2 串流/裁切/切换相关改动必跑（macOS 可用时）
```bash
dart run scripts/verify/verify_webrtc_loopback_content_app.dart
dart run scripts/verify/verify_iterm2_panels_loopback.dart
```

> 证据要求：verify 会生成 `build/verify/*` 截图/日志（本地留档即可，不入 git）。

## 五、执行任务清单（先 P0，再 P1/P2）

> 状态说明：
> - [ ] 未开始
> - [~] 进行中
> - [x] 已完成

### 5.0 基础骨架（core + CLI）（P0）
- [x] 创建目录：`lib/core/cli/` `lib/core/blocks/` `lib/core/ports/` `lib/app/`
  - 验收：目录存在；不影响 app 构建
- [x] 新增 CLI 入口：`bin/cloudplayplus_cli.dart`
  - 验收：`dart run bin/cloudplayplus_cli.dart --help` 退出码为 0
- [x] CLI 核心：`lib/core/cli/cloudplayplus_cli.dart`
  - 目标签名：`int runCloudPlayPlusCli(List<String> args, {required IOSink out, required IOSink err});`
  - 验收：可在单测中调用；输出稳定
- [x] 新增单测：`test/cli_smoke_test.dart`
  - 验收：`--help` 输出包含命令说明；测试全绿

### 5.1 拆分 `lib/entities/session.dart`（P0）
> 第一步用 `part` 拆文件，确保行为不变（不引入跨库 import 问题）。

- [x] 将 `lib/entities/session.dart` 声明为 library：`library streaming_session;`
- [~] 新建 `lib/entities/session/**` 并按职责拆成 part 文件（先拆文件，再逐步下沉 blocks）
  - `signaling.dart`：offer/answer/candidate + 连接状态推进
  - `datachannel_router.dart`：datachannel message 分发（含 setCaptureTarget / desktopSourcesRequest / iterm2SourcesRequest / adaptiveEncoding 等）
  - `capture/capture_switcher.dart`：`_switchCaptureToSource` 与 capture start/stop
  - `capture/desktop_sources.dart`：desktop sources 枚举与 payload 组装（含 thumbnail）
  - `capture/iterm2/iterm2_sources.dart`：iTerm2 panels 查询/解析/返回（保留现有脚本调用）
  - `capture/iterm2/iterm2_activate_and_crop.dart`：iTerm2 激活 + cropRectNorm 选择与应用
  - `input/input_routing.dart`：键盘/文本输入路由（含 TTY 偏好写入）
  - `adaptive/adaptive_encoding_feedback.dart`：自适应反馈处理与 FPS 重应用
  - `debug/input_trace_hooks.dart`：录制/回放 hook（调用 `lib/utils/input/input_trace.dart`）
- [ ] 验收：`flutter test` 与 `flutter analyze` 全绿；verify 脚本仍可跑通（本地）
- [ ] 验收：`flutter test` 全绿；`flutter analyze` 无 error 且不新增本轮相关问题；verify 脚本仍可跑通（本地）

### 5.2 拆分 `global_remote_screen_renderer`（P0）
- [ ] 将 `lib/utils/widgets/global_remote_screen_renderer.dart` 拆为 `lib/widgets/remote_screen/**`
  - `global_remote_screen_renderer.dart`：Widget 壳（仅渲染/编排）
  - `remote_screen_gestures.dart`：手势采集与事件分发（不写算法）
  - `remote_screen_transform.dart`：变换状态存储（不写算法）
- [ ] 将手势判定/去抖/策略迁移到 `lib/core/blocks/gestures/**`（唯一实现）
- [ ] 验收：现有 gesture/scroll 相关测试全绿（`two_finger_*`、`scroll_anchor_packet_test.dart`）

### 5.3 拆分 `floating_shortcut_button.dart`（P0）
- [ ] 拆为 `lib/widgets/keyboard/floating_shortcut_button/**` 小组件文件
- [ ] 将 IME 手动唤起/保持策略迁移到 `lib/core/blocks/ime/**`
- [ ] 将组合键发送策略迁移到 `lib/core/blocks/input/**`（唯一实现）
- [ ] 验收：`system_ime_manual_toggle_test.dart`、`shortcut_panel_top_right_actions_position_test.dart` 全绿

### 5.4 Settings 与 VirtualGamepad（P1/P2）
- [ ] P1：拆分 `lib/settings_screen.dart` 至 `lib/pages/settings/**`
- [ ] P2：拆分 `lib/utils/widgets/virtual_gamepad/control_management_screen.dart` 至 `lib/widgets/virtual_gamepad/editor/**` + `lib/core/blocks/virtual_gamepad/**`

- Grid/List 展示：thumbnail + title + app icon
- 切换策略：Stop → Start（稳定优先）
- 选中态：高亮 + 右侧预览

### 6.4 比例匹配与裁剪（P1）

参数来源：远端分辨率/比例由 app 传入宿主端（`setCaptureTarget`）。

捕获输出流程：

- window capture 仍为全窗口
- native 侧在推送 `RTCVideoFrame` 前做 `crop + scale + letterbox`
- iTerm2：用 Python API 得到 pane frame → 转为 window 像素坐标 → crop

裁剪/信箱：

- `cropRect`（x,y,w,h）以窗口像素为基准
- `targetAspect` / `targetSize` 决定 letterbox 逻辑

### 6.5 里程碑

P0（先行落地）：

- [ ] `getDesktopSourcesV2` 返回缩略图
- [ ] UI 列表展示缩略图
- [ ] 窗口切换（Stop → Start）

P1（比例与 pane）：

- [ ] `setCaptureTarget` 支持 `cropRect` / `targetAspect`
- [ ] iTerm2 pane 级裁剪 + letterbox

风险与验证：

- macOS 权限/前台：确认不再弹系统选择 UI
- 缩略图性能：窗口多时保持流畅（节流）
- 切换稳定性：多次切换无绿屏/崩溃
