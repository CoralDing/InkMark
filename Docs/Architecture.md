<!--
文件说明：墨记当前架构说明，描述应用分层、数据流和关键安全边界。
作者：Codex
创建时间：2026-07-29
-->

# 架构说明

墨记是单 Target（构建目标）的原生 macOS 文档应用，不依赖服务端或第三方包管理器。

## 分层

- `Sources/App/Modern`：应用生命周期、系统菜单、`NSDocument` 文档模型和窗口组合。
- `Sources/Features/Editor/Modern`：基于 `NSTextView` 的纯文本编辑器。
- `Sources/Features/Preview/Modern`：基于 `WKWebView` 的 HTML 预览和链接导航策略。
- `Sources/Core/Markdown`：Markdown 到 HTML 的轻量渲染器及主题 CSS。
- `Sources/Core/Preferences`：`UserDefaults` 偏好模型和原生设置窗口。
- `Sources/Core/Plugins`：内置插件、用户脚本扫描、安装和启停状态。

## 文档数据流

```text
NSTextView 输入
    ↓ 80ms 防抖
ModernMarkdownRenderer
    ↓ HTML + CSP
WKWebView
    ↓ WKUserScript
内置插件与已启用用户插件
```

`ModernMarkdownDocument` 是数据流中心，负责文件读写、编辑状态、预览刷新、工具栏和导出 HTML。

## 安全边界

- Markdown 原始 HTML 会被转义，不作为可执行页面内容直接拼接。
- 用户插件只从应用支持目录读取普通、非隐藏、最大 1MB 的 `.js` 文件。
- 插件通过 `WKUserScript` 注入，不写入导出的 HTML。
- 预览 CSP 禁止网络连接和页面脚本标签，仅允许本地/远程图片与媒体资源。
- 外部链接交由系统默认应用打开，预览区只保留页内锚点导航。

## 兼容范围

当前渲染器面向常用 GitHub Flavored Markdown（GitHub 风格 Markdown）子集，不以完整 CommonMark（通用 Markdown 规范）兼容为目标。新增语法时应优先补充可复现样例和边界测试。

