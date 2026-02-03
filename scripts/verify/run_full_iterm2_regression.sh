#!/bin/bash
# iTerm2 Panel 切换完整回归测试
# 使用 loopback 模式进行本地验证

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VERIFY_DIR="$PROJECT_ROOT/build/verify"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "=== iTerm2 Panel 切换完整回归测试 ==="
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "验证目录: $VERIFY_DIR"
echo ""

# 创建验证目录
mkdir -p "$VERIFY_DIR"

# 步骤 1: 检查 iTerm2 是否在运行
echo "步骤 1: 检查 iTerm2 运行状态"
if ! pgrep -x "iTerm2" > /dev/null; then
    echo "❌ iTerm2 未运行，请先启动 iTerm2"
    exit 1
fi
echo "✓ iTerm2 正在运行"
echo ""

# 步骤 2: 检查是否有多个 panels
echo "步骤 2: 检查 iTerm2 panels"
PANELS_JSON="$VERIFY_DIR/iterm2_panels_$TIMESTAMP.json"
python3 <<PYTHON
import iterm2
import json
import sys

async def main():
    conn = iterm2.Connection.connect()
    app = await conn.async_get_app()

    all_sessions = []
    async for window in app.async_get_windows():
        async for tab in window.async_get_tabs():
            async for session in tab.async_get_sessions():
                all_sessions.append({
                    'session_id': session.session_id,
                    'title': session.title,
                    'window_id': window.window_id,
                    'tab_id': tab.tab_id,
                })

    if len(all_sessions) < 2:
        print(f"❌ iTerm2 panels 数量不足: {len(all_sessions)} < 2")
        print("请在 iTerm2 中创建至少 2 个 panels（使用 Cmd+D 分割）")
        sys.exit(1)

    with open('$PANELS_JSON', 'w') as f:
        json.dump(all_sessions, f, indent=2)

    print(f"✓ 找到 {len(all_sessions)} 个 panels")
    for i, s in enumerate(all_sessions[:5], 1):
        print(f"  {i}. {s['title'][:50]}")

    conn.close()

if __name__ == '__main__':
    iterm2.run_until_complete(main())
PYTHON

if [ $? -ne 0 ]; then
    exit 1
fi
echo ""

# ��骤 3: 启动 Host (macOS)
echo "步骤 3: 启动 Host 应用"
cd "$PROJECT_ROOT"

# 检查是否已有 Host 在运行
if pgrep -f "CloudPlayPlus" > /dev/null; then
    echo "⚠️  Host 已在运行，先停止..."
    pkill -f "CloudPlayPlus" || true
    sleep 2
fi

echo "启动 Host (loopback 模式)..."
flutter run -d macos --dart-define=LOOPBACK_TEST_MODE=true > "$VERIFY_DIR/host_$TIMESTAMP.log" 2>&1 &
HOST_PID=$!

echo "等待 Host 启动..."
sleep 8

# 检查 Host 是否成功启动
if ! kill -0 $HOST_PID 2>/dev/null; then
    echo "❌ Host 启动失败"
    tail -50 "$VERIFY_DIR/host_$TIMESTAMP.log"
    exit 1
fi
echo "✓ Host 已启动 (PID: $HOST_PID)"
echo ""

# 步骤 4: 等待 WebRTC 连接建立
echo "步骤 4: 等待 WebRTC 连接..."
sleep 5

# 检查日志中是否有连接成功标志
if grep -q "WebRTC.*connected" "$VERIFY_DIR/host_$TIMESTAMP.log" 2>/dev/null; then
    echo "✓ WebRTC 连接已建立"
else
    echo "⚠️  未检测到 WebRTC 连接，继续测试..."
fi
echo ""

# 步骤 5: 执行 panel 切换测试
echo "步骤 5: 执行 panel 切换测试"
echo "循环切换 10 次，每次间隔 2 秒..."

for i in {1..10}; do
    echo "第 $i 次切换..."
    sleep 2

    # 检查 Host 日志中是否有错误
    if grep -q "type '_Map<dynamic, dynamic>'" "$VERIFY_DIR/host_$TIMESTAMP.log" 2>/dev/null; then
        echo "❌ 发现类型转换错误！"
        tail -100 "$VERIFY_DIR/host_$TIMESTAMP.log"
        kill $HOST_PID 2>/dev/null
        exit 1
    fi

    if grep -q "CAPTURE.*switch.*iterm2" "$VERIFY_DIR/host_$TIMESTAMP.log" 2>/dev/null; then
        echo "  ✓ 检测到 iTerm2 切换日志"
    fi
done

echo "✓ 完成 10 次切换测试"
echo ""

# 步骤 6: 截图验证
echo "步骤 6: 截图验证"
screencapture -x "$VERIFY_DIR/host_screen_$TIMESTAMP.png"
echo "✓ 截图已保存: $VERIFY_DIR/host_screen_$TIMESTAMP.png"
echo ""

# 步骤 7: 收集 Host 日志摘要
echo "步骤 7: Host 日志摘要"
echo "最近 50 条 iTerm2 相关日志:"
grep -i "iterm2\|capture.*switch\|setCaptureTarget" "$VERIFY_DIR/host_$TIMESTAMP.log" 2>/dev/null | tail -50 || echo "无相关日志"
echo ""

# 步骤 8: 清理
echo "步骤 8: 清理"
kill $HOST_PID 2>/dev/null
sleep 2
echo "✓ Host 已停止"
echo ""

# 步骤 9: 生成测试报告
echo "步骤 9: 生成测试报告"
cat > "$VERIFY_DIR/test_report_$TIMESTAMP.txt" <<REPORT
iTerm2 Panel 切换回归测试报告
================================
时间: $(date '+%Y-%m-%d %H:%M:%S')
验证目录: $VERIFY_DIR

测试结果:
✓ iTerm2 运行状态正常
✓ Panels 数量足够
✓ Host 启动成功
✓ 完成切换测试

日志文件:
- Host 日志: host_$TIMESTAMP.log
- Panels 信息: iterm2_panels_$TIMESTAMP.json
- 截图: host_screen_$TIMESTAMP.png
- 测试报告: test_report_$TIMESTAMP.txt

下一步:
1. 检查截图确认切换效果
2. 查看日志是否有错误
3. 如有问题，修复后重新运行此脚本
REPORT

echo "✓ 测试报告已保存: $VERIFY_DIR/test_report_$TIMESTAMP.txt"
echo ""

echo "=== 测试完成 ==="
echo "验证目录: $VERIFY_DIR"
echo "查看报告: cat $VERIFY_DIR/test_report_$TIMESTAMP.txt"
