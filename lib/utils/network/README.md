# Network Strategy Lab / Adaptive Encoding

本目录包含 CloudPlayPlus 的网络自适应策略与纯函数策略模块。

## 1. 目标：窗口分辨率 576×768 的带宽分级策略（待长期维护）

适用范围：

- `captureTargetType` 为 `window` / `iterm2`（窗口/Panel 串流）
- 编码目标以“**延迟优先 + 可恢复**”为原则：
  - 带宽不足是常态，必须能自愈（不能因为 buffer 达到上限就进入“永久降档”）
  - 默认 buffer 仅做轻微抖动平滑（约 5 帧），不把卡顿变成大延迟

基准（以 576×768 为例）：

- `B=250 kbps`：`15 fps`、`250 kbps`（可接受的基准体验）
- `B<250 kbps`：允许降到 `5 fps`（保交互连续性）
- `B=500 kbps`：升到 `30 fps`
- `B=1000 kbps`：升到 `60 fps`
- `B>1000 kbps`：保持 `60 fps`，只提高码率以提升质量

> 对其他窗口分辨率：按面积比例缩放基准码率（见下文 `R15_scaled`）。

---

## 2. 如何测“实际带宽”（BWE）

目标是估计“链路可持续可用吞吐能力（capacity）”，不是当前编码实际发了多少：

优先级（线上推荐）：

1. `candidate-pair.availableOutgoingBitrate`（WebRTC GCC/BWE 的可用上行带宽估计，单位 bps）
2. 若不可用：用 `outbound-rtp.bytesSent` 的 delta 估算 `tx_kbps` 作为保底（注意：会被 target cap 限死，不代表链路上限）

采样与平滑：

- 采样周期：500ms~1000ms（与 controller -> host 反馈周期一致即可）
- 平滑：5s 窗口 `median` 或 EWMA（避免抖动导致升/降档来回跳）

健康降权：

当出现明显拥塞/抖动（任一）：

- `loss > 2%` 或 `rtt > 450ms` 或 `freezeDelta > 0`

则有效带宽：

- `B = BWE_smooth * 0.8`（降权系数可调）

---

## 3. FPS 分级（Tier）与防抖（Hysteresis）

定义阈值：

- `T1=250 kbps`, `T2=500 kbps`, `T3=1000 kbps`

对应 tier：

- `B < T1` → `5 fps`
- `T1 ≤ B < T2` → `15 fps`
- `T2 ≤ B < T3` → `30 fps`
- `B ≥ T3` → `60 fps`

升档（更保守）：

- 连续 `5s` 满足：`B >= nextTierThreshold` 且 `loss < 1%` 且 `rtt < 300ms` 且 `freezeDelta == 0`

降档（更快）：

- 连续 `1.5s` 满足任一：
  - `B < currentTierThreshold * 0.85`
  - 或 `loss > 3%` 或 `freezeDelta > 0`

规则：

- 每次只跨 1 个 tier（避免抖动）
- tier 变化需要明确日志输出（便于回放/复现）

---

## 4. 码率策略（Bitrate）

### 4.1 基准码率（按 fps 线性缩放）

定义 15fps 的基准码率：

- `R15 = 250 kbps`（576×768）

对其他分辨率按面积缩放：

- `R15_scaled = R15 * (width*height) / (576*768)`（再 clamp 到合理范围）

对应 fpsTier 的基准：

- `R_base(fpsTier) = R15_scaled * fpsTier / 15`

### 4.2 按带宽封顶（headroom）

- `R_cap = B * 0.85`

最终码率：

- 若 `fpsTier < 60`：`R_video = min(R_base(fpsTier), R_cap)`
- 若 `fpsTier == 60`：
  - `R_video = min(R_cap, 1000 + qualityBoost(B))`
  - `qualityBoost(B) = clamp((B - 1000) * 0.5, 0, 1500)`（可调）

下限：

- `R_video >= 25 kbps`（极端网络保活）

---

## 5. Buffer 满了怎么办（“丢整 GOP”）

当前实现基于 WebRTC 内置 jitter buffer：

- 我们无法直接访问/控制内部队列来“按 GOP 主动丢弃”
- 现实等价行为：当参考帧链断裂或延迟过大时，P 帧即使到达也无法解码，直到下一个关键帧恢复（等价于“丢弃剩余 GOP”）

因此工程上更可控的手段是：

- 控制 GOP / 关键帧间隔（例如 2s 一个关键帧）
- 在切档/恢复后触发关键帧（PLI/FIR）以缩短恢复时间

---

## 6. 文件索引

- `video_buffer_policy.dart`：接收端 buffer（frames/seconds）目标的纯函数策略
- `strategy_lab_policy.dart`：策略实验台的纯函数与触发器（用于 loopback verifier）

