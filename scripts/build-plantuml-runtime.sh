#!/bin/bash
# 文件说明：使用当前 Temurin JDK 裁剪 PlantUML 所需的最小 Java 运行时，供发布流程按 CPU 架构生成离线图表依赖。
# 作者：dingyi60(Codex)
# 创建时间：2026-08-06

set -euo pipefail

# PlantUML 的静态依赖由 jdeps 分析得出；java.desktop 会连带引入字体、图像和 XML 能力，
# 以保证时序图、类图、活动图等 SVG 输出与完整运行时一致。
REQUIRED_MODULES="java.base,java.compiler,java.desktop,java.logging,java.prefs,java.scripting,jdk.unsupported"

if [[ "$#" -ne 1 ]]; then
  echo "用法：$0 <输出运行时目录>" >&2
  exit 1
fi

OUTPUT_DIRECTORY="$1"
JAVA_HOME_DIRECTORY="$OUTPUT_DIRECTORY/Contents/Home"
JLINK_PATH="${JAVA_HOME:-}/bin/jlink"

# 本地开发环境可能只把 jlink 放进 PATH；发布环境优先使用 setup-java 提供的 JAVA_HOME。
if [[ ! -x "$JLINK_PATH" ]]; then
  JLINK_PATH="$(command -v jlink || true)"
fi

# 输出目录必须由调用方提供一个不存在的新路径，避免脚本意外覆盖已验证的发布运行时。
if [[ -e "$OUTPUT_DIRECTORY" ]]; then
  echo "输出目录已存在，为避免覆盖，已停止：$OUTPUT_DIRECTORY" >&2
  exit 1
fi

if [[ ! -x "$JLINK_PATH" ]]; then
  echo "未找到 jlink。请先设置指向完整 JDK 的 JAVA_HOME。" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIRECTORY/Contents"

# 移除调试符号、头文件和手册页，只保留 PlantUML 本地离线渲染实际使用的 Java 模块。
"$JLINK_PATH" \
  --add-modules "$REQUIRED_MODULES" \
  --strip-debug \
  --no-header-files \
  --no-man-pages \
  --compress=2 \
  --output "$JAVA_HOME_DIRECTORY"

# 生成后立即确认 Java 可启动且必要模块齐全，避免把不完整运行时传给后续打包步骤。
"$JAVA_HOME_DIRECTORY/bin/java" --version
for required_module in ${REQUIRED_MODULES//,/ }; do
  "$JAVA_HOME_DIRECTORY/bin/java" --list-modules | grep -q "^${required_module}@"
done

echo "[墨记] PlantUML 精简运行时已生成：$OUTPUT_DIRECTORY"
du -sh "$OUTPUT_DIRECTORY"
