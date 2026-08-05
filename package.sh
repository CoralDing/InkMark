#!/bin/bash
# 文件说明：墨记本地发布脚本，构建通用架构应用并生成经过校验的 DMG 安装包。
# 作者：Codex
# 创建时间：2026-07-29

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFO_PLIST="$ROOT_DIR/InkMark/InkMark-Info.plist"
DERIVED_DATA="$ROOT_DIR/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Release/墨记.app"
OUTPUT_DIR="$ROOT_DIR/outputs"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
DATE_TAG="$(date +%Y%m%d)"
DMG_PATH="$OUTPUT_DIR/墨记-$VERSION-$DATE_TAG.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/moji-release.XXXXXX")"

# 无论构建在哪一步结束，都清理仅用于组装 DMG 的临时目录。
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

echo "[墨记] 正在构建 Release 版本 ${VERSION}（${BUILD_NUMBER}）..."
xcodebuild \
  -project "$ROOT_DIR/InkMark.xcodeproj" \
  -scheme InkMark \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "[墨记] 正在执行本地临时签名与校验..."
codesign --force --deep --sign - --identifier io.github.dingyi60.moji "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "[墨记] 正在组装 DMG..."
mkdir -p "$OUTPUT_DIR"
rm -f "$DMG_PATH"
ditto "$APP_PATH" "$STAGING_DIR/墨记.app"
ln -s /Applications "$STAGING_DIR/应用程序"
hdiutil create \
  -volname "墨记 $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "[墨记] 正在验证磁盘映像..."
hdiutil verify "$DMG_PATH"

echo "[墨记] 发布产物：${DMG_PATH}"
echo "[墨记] 应用架构：$(lipo -archs "$APP_PATH/Contents/MacOS/墨记")"
echo "[墨记] SHA-256：$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
