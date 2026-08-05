<!--
文件说明：墨记开源项目主页，介绍产品定位、核心能力、使用方式与隐私原则。
作者：Codex
创建时间：2026-07-29
-->

<p align="center">
  <img src="Docs/Images/moji-app-icon.png" width="128" height="128" alt="墨记应用图标">
</p>

<h1 align="center">墨记 InkMark</h1>

<p align="center">
  清晰、快速、本地优先的 macOS Markdown 编辑与阅读工具
</p>

<p align="center">
  macOS 11.0+ · Apple Silicon 与 Intel · 当前版本 1.0.0 · MIT License
</p>

墨记是一款面向 macOS 的原生 Markdown 编辑器与阅读器。它专注于安静、直接的写作体验，将源码编辑、实时预览和沉浸阅读放在同一个窗口中，并为 Mermaid、PlantUML、KaTeX 数学公式和本地插件提供完整支持。

文档默认保存在本地，无需注册账号，也不依赖云服务。无论是日常笔记、技术文档、方案设计还是离线阅读，墨记都希望让 Markdown 保持简单、高效且可靠。

![墨记分栏模式与夜间主题](Docs/Images/app-preview.png)

## 核心能力

| 分类 | 能力 |
| --- | --- |
| 写作与阅读 | 写作、分栏、阅读三种模式；Markdown 语法着色；原生查找、拼写检查、撤销与重做 |
| 实时预览 | 默认 GitHub 风格排版，支持清爽、纸张、夜间、暖色和手稿主题，可调整阅读宽度 |
| 双向滚动 | 编辑器与预览按 Markdown 源行同步滚动，图表和公式异步渲染后仍能保持当前章节 |
| 标准语法 | 标题、列表、引用、链接、图片、代码块、表格、任务列表和删除线 |
| 扩展语法 | GitHub 提示块、内容分栏、折叠块、附件、视频、技术资产和 ZERO 链接卡片 |
| 本地图表 | Mermaid、PlantUML 和 KaTeX 数学公式均在本机渲染，断网状态下仍可使用 |
| 原生体验 | macOS 菜单、工具栏、快捷键、自动保存、文件关联和符合系统习惯的设置窗口 |
| 插件扩展 | 内置文档目录与代码复制，可安装本地 `.js` 预览插件并单独启停 |

## 编辑体验

墨记提供三种视图模式，可根据当前任务快速切换：

- **写作模式**：专注 Markdown 源码，适合长时间输入和整理内容。
- **分栏模式**：左侧编辑、右侧预览，适合边写边检查最终排版。
- **阅读模式**：隐藏编辑器，获得更完整、沉浸的文档阅读空间。

编辑器与预览区使用源行映射进行双向滚动。即使页面中包含较高的表格、代码块、图片或异步生成的图表，两侧也会尽量保持在同一段内容。

## Markdown 预览

墨记支持常用 GitHub Flavored Markdown（GitHub 风格 Markdown），包括表格、任务列表、删除线和围栏代码块。预览默认使用熟悉的 GitHub 风格，也可以在设置中切换多种阅读主题。

除标准 Markdown 外，墨记还支持：

- Mermaid 流程图、时序图、状态图、类图和甘特图。
- PlantUML 时序图、类图、用例图和其他 UML（统一建模语言）图表。
- KaTeX 行内公式、块级公式和 `math` 代码围栏。
- GitHub 提示块、分栏、折叠内容、视频和技术资源卡片。

完整效果可以查看 [墨记完整功能演示](Examples/墨记完整功能演示.md) 和 [扩展 Markdown 语法](Docs/ExtendedMarkdown.md)。

## 本地优先

墨记不要求登录账号，Markdown 文档、图表源码和数学公式均保留在本机。Mermaid、PlantUML 与 KaTeX 随应用提供，不会为了生成预览而上传文档内容。

用户插件以本地 JavaScript 文件形式安装，可以增强预览页面，但无法直接调用墨记的原生应用接口。预览页也会限制主动网络访问，降低文档内容意外外传的风险。

## 下载与安装

前往 [Releases](https://github.com/CoralDing/InkMark/releases/latest) 下载适合当前 Mac 的 DMG（macOS 磁盘映像安装包）：

| 安装包 | 适用设备 |
| --- | --- |
| `macOS-arm64` | Apple Silicon Mac，例如 M1、M2、M3、M4 |
| `macOS-x86_64` | Intel 处理器 Mac |
| `macOS-universal` | 同时兼容 Apple Silicon 与 Intel，无法判断架构时选择此版本 |

打开 DMG 后，将“墨记”拖入“应用程序”文件夹即可。当前开源安装包使用本地临时签名，尚未进行 Apple Developer ID（苹果开发者分发签名）公证；如果 macOS 首次阻止打开，请在访达中右键应用并选择“打开”。

## 系统要求

- macOS 11.0 或更高版本
- Apple Silicon 或 Intel 处理器
- 无需额外安装 Java 或其他运行环境

## 相关文档

- [完整功能演示](Examples/墨记完整功能演示.md)
- [扩展 Markdown 语法](Docs/ExtendedMarkdown.md)
- [插件开发指南](Docs/PluginDevelopment.md)
- [变更日志](CHANGELOG.md)

## 开源许可

墨记以 [MIT License](LICENSE) 开源。随应用分发的第三方运行库及许可证详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和 [LICENSES](LICENSES)。
