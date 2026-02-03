# CloudPlayPlus CLI WebSocket 协议

## 概述

CloudPlayPlus 提供两套 CLI WebSocket 服务，用于自动化测试和远程控制：

- Host CLI Server：监听 `127.0.0.1:19001`
- Controller CLI Server：监听 `127.0.0.1:19002`

端口固定，供脚本/daemon 调用。

## 连接地址

```text
ws://127.0.0.1:19001  (host)
ws://127.0.0.1:19002  (controller)
```

## 消息格式

### 请求

```json
{
  "cmd": "command_name",
  "id": "optional_request_id",
  "...": "params"
}
```

### 响应

```json
{
  "cmd": "command_name",
  "id": "optional_request_id",
  "success": true,
  "data": {}
}
```

失败：

```json
{
  "cmd": "command_name",
  "id": "optional_request_id",
  "success": false,
  "error": "error_message"
}
```

## Controller CLI 命令

### connect
连接到指定 Host（LAN）。

请求：
```json
{ "cmd": "connect", "host": "127.0.0.1", "port": 17999 }
```

### disconnect
断开当前连接。

请求：
```json
{ "cmd": "disconnect" }
```

### get_state
获取当前 controller 状态（连接状态、当前 target、上次 target、模式等）。

请求：
```json
{ "cmd": "get_state" }
```

### set_mode
设置控制端模式（影响自动恢复策略/默认页面）。

请求：
```json
{ "cmd": "set_mode", "mode": "iterm2" }
```

`mode` 取值：`desktop` | `window` | `iterm2`

### list_screens
列出可选屏幕。

请求：
```json
{ "cmd": "list_screens" }
```

### list_windows
列出可选窗口。

请求：
```json
{ "cmd": "list_windows" }
```

### list_iterm2_panels
获取 iTerm2 面板列表（来自 Host 下发的 `iterm2Sources`）。

请求：
```json
{ "cmd": "list_iterm2_panels" }
```

### set_capture_target
统一的“切换捕获目标”命令，支持 screen/window/iterm2/region。

#### 1) screen

请求：
```json
{ "cmd": "set_capture_target", "type": "screen", "screenId": "0" }
```

#### 2) window

请求：
```json
{ "cmd": "set_capture_target", "type": "window", "windowId": 1351 }
```

#### 3) iterm2 panel

请求：
```json
{ "cmd": "set_capture_target", "type": "iterm2", "iterm2SessionId": "sess-3", "cgWindowId": 1008 }
```

#### 4) region

region 基于一个 base（screen/window）并附带归一化坐标。

请求：
```json
{
  "cmd": "set_capture_target",
  "type": "region",
  "base": {"type": "screen", "screenId": "0"},
  "rect": {"x": 0.1, "y": 0.1, "w": 0.8, "h": 0.8}
}
```

### restore_last_target
恢复到上次连接目标：
- 如果 last target 仍存在：恢复 last
- 如果 last target 不存在：fallback 到“同模式”的第一个可用目标（panel/window）或默认屏幕

请求：
```json
{ "cmd": "restore_last_target" }
```

请求：
```json
{ "cmd": "switch_panel", "sessionId": "sess-3", "cgWindowId": 1008 }
```

## Host CLI 命令

### get_state
获取 host 当前会话信息。

请求：
```json
{ "cmd": "get_state" }
```

## 日志

CLI 的命令收发和执行结果必须写入本地日志：

- Host: `~/Library/Application Support/CloudPlayPlus/logs/host_YYYYMMDD.log`
- Controller: `~/Library/Application Support/CloudPlayPlus/logs/app_YYYYMMDD.log`

## 备注（当前实现状态）

目前仓库里已有一个 CLI Server stub 在 `lib/main.dart`，只会回显 cmd。
接下来会把上述命令全部落地，并用本地自连接（Host+Controller）作为回归测试基线。
