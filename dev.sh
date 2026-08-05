#!/bin/bash
# 文件说明：墨记本地开发调试脚本，构建 Debug 版本并打开最新 App。
# 作者：Codex
# 创建时间：2026-06-18

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$ROOT_DIR/DerivedData/Build/Products/Debug/墨记Debug.app"

echo "[墨记] 正在构建 Debug 版本..."
xcodebuild \
  -project "$ROOT_DIR/InkMark.xcodeproj" \
  -scheme InkMark \
  -configuration Debug \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$ROOT_DIR/DerivedData" \
  CODE_SIGN_IDENTITY= \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "[墨记] 正在结束旧的 Debug 实例..."
pkill -x "墨记Debug" 2>/dev/null || true

echo "[墨记] 正在打开最新 Debug App: $APP_PATH"
open -n "$APP_PATH"
echo "[墨记] 已启动。"
