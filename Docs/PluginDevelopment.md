<!--
文件说明：墨记预览插件开发指南，定义脚本格式、运行时机、安全限制和示例。
作者：Codex
创建时间：2026-07-29
-->

# 插件开发

墨记插件是注入 Markdown 预览页的 JavaScript（浏览器脚本语言）文件，适合增加目录、复制按钮、标注或自定义 DOM 处理。

## 安装规则

- 文件扩展名必须是 `.js`。
- 单个文件不能超过 1MB。
- 隐藏文件和非普通文件不会加载。
- 文件名会作为设置页展示名称，同名安装会自动追加序号。
- 插件目录：`~/Library/Application Support/墨记/Plugins`。

## 运行时机

插件通过 `WKUserScript` 在主文档加载结束时执行。每次编辑导致预览重载后，插件会重新执行，因此实现必须可以重复运行。

推荐使用独立标记避免重复创建元素：

```javascript
(() => {
  if (document.documentElement.dataset.examplePlugin === "ready") return;
  document.documentElement.dataset.examplePlugin = "ready";

  document.querySelectorAll("blockquote").forEach((quote) => {
    quote.classList.add("example-highlight");
  });

  const style = document.createElement("style");
  style.textContent = ".example-highlight { border-left-width: 3px; }";
  document.head.appendChild(style);
})();
```

## 可用内容

- 标准 DOM API（网页文档接口）。
- 当前预览页中由墨记生成的标题、段落、列表、表格、代码块和链接。
- 页面 CSS 变量：`--text`、`--heading`、`--muted`、`--accent`、`--border`、`--soft-bg`、`--code-bg`。

## 安全限制

- 没有文件系统、菜单、窗口或其他墨记原生 API。
- CSP 禁止 `fetch`、`XMLHttpRequest`、WebSocket（网页长连接）等网络连接。
- 不要把文档内容写入日志、剪贴板或外部页面，除非这是用户明确触发的功能。
- 不要依赖私有 class 名称；优先使用标准 HTML 标签和 `moji-` 前缀自有 class。

## 核心预览能力

- Mermaid 随应用分发并在本地运行，支持 `mermaid` 代码围栏。
- 数学公式使用本地 KaTeX 渲染 `$...$`、`$$...$$` 和 `math` 代码围栏。
- PlantUML 在用户首次安装当前架构组件后使用本地 PlantUML 与 Temurin JRE 生成 SVG，支持 `plantuml` 和 `puml` 代码围栏，图表源码不会上传。
- 上述能力属于 Markdown 格式支持，始终启用；插件总开关只控制目录、代码复制和用户脚本。

## 完整示例

仓库提供了一个不访问网络的阅读时间插件：[Examples/Plugins/reading-time.js](../Examples/Plugins/reading-time.js)。它演示了重复执行保护、中文与英文内容统计、CSS 变量复用和辅助功能文案，可直接从墨记设置页安装。
