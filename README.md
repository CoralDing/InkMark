<!--
文件说明：墨记开源项目说明，介绍产品能力、构建方式、架构和贡献入口。
作者：Codex
创建时间：2026-07-29
-->

# 墨记

墨记是一款原生 macOS Markdown（轻量标记语言）编辑与预览工具。它使用 Swift（苹果现代开发语言）、AppKit（macOS 原生界面框架）和 WKWebView（网页预览控件）构建，强调清晰、快速、本地优先。

![墨记主界面](Docs/Images/app-preview.png)

## 功能

- 三种模式：在写作、分栏和阅读模式之间一键切换，并记住分栏比例；分栏模式下编辑与预览按 Markdown 源行双向同步滚动。
- 源码体验：轻量 Markdown 语法着色、动态正文宽度、原生查找、拼写检查和撤销重做。
- 常用语法：支持标题、列表、引用、链接、图片、代码块、表格、任务列表和删除线。
- 扩展内容：支持 GitHub 提示块、响应式内容分栏、折叠块、附件卡片、视频、数学公式、技术资产和 ZERO 链接卡片。
- 图表支持：Mermaid 与 PlantUML 均在本地渲染，断网状态下也能生成图表。
- Git 风格：默认采用接近 GitHub 文档的排版，并提供清爽、纸张、夜间、暖色和手稿主题；编辑与预览配色保持一致。
- 本地资源：支持文档目录内的相对图片，并在实时刷新时保留预览滚动位置。
- 原生体验：系统菜单、工具栏、快捷键、自动保存、查找、拼写检查和文件关联。
- 插件管理：内置文档目录与代码复制，也可安装本地 `.js` 预览插件并单独启停。
- 本地优先：不依赖账号、云服务或远程更新源；图表和公式源码不会上传，插件没有墨记原生接口权限，主动网络接口会被预览安全策略阻止。

Mermaid 使用标准代码围栏即可在本地渲染：

````text
```mermaid
flowchart LR
  Markdown --> 墨记 --> SVG
```
````

PlantUML 支持 `plantuml` 与 `puml` 代码围栏。墨记使用随应用分发的 PlantUML 和 Temurin JRE（Java 运行环境）在本机生成 SVG（矢量图），无需安装 Java，也不会发送图表源码。离线运行时会增加安装包体积。

## 系统要求

- macOS 11.0 或更高版本
- Xcode 15 或更高版本；推荐使用当前稳定版 Xcode

## 本地开发

克隆仓库后直接运行：

```bash
./dev.sh
```

脚本会构建 Debug（调试版）并启动最新应用。也可以使用 Xcode 打开工程：

```bash
open InkMark.xcodeproj
```

命令行构建：

```bash
xcodebuild \
  -project InkMark.xcodeproj \
  -scheme InkMark \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

项目没有 CocoaPods（旧依赖管理工具）或 Ruby 依赖。仓库已包含图表预览所需的 PlantUML 和双架构 Temurin JRE，首次克隆无需额外安装 Java。

Markdown 渲染器提供独立冒烟测试（覆盖主要流程的轻量自动测试），可直接运行：

```bash
xcrun swiftc \
  InkMark/Sources/Core/Markdown/ModernMarkdownRenderer.swift \
  Tests/RendererSmokeTests/main.swift \
  -o /tmp/moji-renderer-tests
/tmp/moji-renderer-tests
```

## 打包安装包

运行发布脚本即可构建通用架构应用，并生成可直接安装的 DMG（磁盘映像安装包）：

```bash
./package.sh
```

脚本会执行 Release（发布版）构建、本地临时签名、签名校验和 DMG 校验。产物保存到 `outputs/`，同时输出 SHA-256（文件完整性摘要），便于发布后核对下载文件。

## 项目结构

```text
InkMark/
├── InkMark/                 # 应用源码、Info.plist 和资源
│   ├── Sources/App/         # 应用生命周期与文档窗口
│   ├── Sources/Core/        # Markdown、设置和插件核心能力
│   ├── Sources/Features/    # 编辑器与预览功能
│   └── Images.xcassets/     # 应用图标
├── InkMark.xcodeproj/       # Xcode 工程与共享 Scheme
├── Docs/                    # 架构和插件开发文档
├── Examples/Plugins/        # 可直接安装的预览插件示例
├── Tests/RendererSmokeTests/# Markdown 渲染冒烟测试
├── LICENSES/                # 上游项目许可证
├── dev.sh                   # 本地开发入口
└── package.sh               # 本地发布打包入口
```

架构说明见 [Docs/Architecture.md](Docs/Architecture.md)，插件开发见 [Docs/PluginDevelopment.md](Docs/PluginDevelopment.md)。

墨记扩展语法及完整示例见 [Docs/ExtendedMarkdown.md](Docs/ExtendedMarkdown.md)。

插件示例见 [Examples/Plugins/reading-time.js](Examples/Plugins/reading-time.js)，可以在“设置 → 插件 → 添加”中直接安装。

## 贡献

提交改动前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。问题报告需要包含 macOS 版本、应用版本、复现步骤和预期结果；界面问题建议附截图。

安全问题请按照 [SECURITY.md](SECURITY.md) 处理，不要在公开议题中披露尚未修复的漏洞。

## 许可证

墨记以 [MIT License](LICENSE) 开源。

随应用分发的第三方运行库及许可证详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和 [LICENSES](LICENSES)。
