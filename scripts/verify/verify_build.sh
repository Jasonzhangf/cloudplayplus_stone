#!/bin/bash
# 验证 Flutter 项目构建是否正常

set -e

echo "🔍 验证 Flutter 环境..."

# 检查 Flutter 版本
flutter --version

# 检查依赖
echo "📦 检查依赖..."
flutter pub get

# 分析代码
echo "🔬 分析代码..."
flutter analyze --no-fatal-infos 2>&1 | head -50

# 运行测试
echo "🧪 运行测试..."
flutter test test/smooth_mouse_controller_test.dart

echo "✅ 构建验证完成"
