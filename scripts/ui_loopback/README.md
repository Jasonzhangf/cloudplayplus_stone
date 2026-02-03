# UI Loopback Regression (macOS)

Goal: reproduce and fix "switch iTerm2 panel -> disconnect back to device list" locally, without Android.

## Run (2-process)

Terminal A (Host):

```bash
pkill -9 CloudPlayPlus || true
nohup env LOOPBACK_MODE=host LOOPBACK_HIDE_WINDOW=1 \
  build/macos/Build/Products/Debug/CloudPlayPlus.app/Contents/MacOS/CloudPlayPlus \
  > /tmp/cloudplayplus_host_bg.out 2>&1 &
```

Terminal B (Controller):

```bash
nohup env LOCAL_TEST_MODE=controller LOOPBACK_MODE=controller LOOPBACK_HIDE_WINDOW=1 \
  build/macos/Build/Products/Debug/CloudPlayPlus.app/Contents/MacOS/CloudPlayPlus \
  > /tmp/cloudplayplus_controller_bg.out 2>&1 &
```

## Drive UI state via CLI (controller)

```bash
python3 scripts/ui_loopback/cli_connect_and_select_panel.py
python3 scripts/ui_loopback/cli_burst_switch_panels.py
```

## Collect logs

- Host: `/tmp/cloudplayplus_host_bg.out`
- Controller: `/tmp/cloudplayplus_controller_bg.out`
- Daily logs: `~/Library/Application Support/CloudPlayPlus/logs/`

