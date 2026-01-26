#!/bin/bash
# 运行 WebRTC 窗口捕获验证（Flutter macOS app）

set -e

echo "🚀 Running WebRTC window capture verify app (macOS)..."

echo "Tip: the app may trigger macOS Screen Recording permission prompt."

echo "Starting flutter run..."
flutter run -d macos -t scripts/verify/verify_webrtc_window_capture_app.dart
