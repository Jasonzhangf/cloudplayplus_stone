#!/bin/bash
# 确保 CloudPlayPlus 在前台（辅助调试用）

set -e

osascript -e 'tell application "CloudPlayPlus" to activate'
