/**
 * 文件说明：墨记 Markdown 渲染器冒烟测试，覆盖引用、代码围栏和属性转义等关键边界。
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-04
 */

import Foundation

/// 验证条件是否成立；失败时直接终止测试进程，让本地脚本和 CI 都能识别失败。
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError("渲染测试失败：\(message)")
    }
}

let renderer = ModernMarkdownRenderer()

// 块级节点必须携带原始 Markdown 行号，双栏滚动同步依赖这些锚点做内容位置插值。
let sourceMapHTML = renderer.renderHTML(from: "# 标题\n\n第一段\n\n- 项目一\n- 项目二\n\n```swift\nlet value = 1\n```")
expect(sourceMapHTML.contains("<h1 data-source-line=\"1\">"), "标题源行号缺失")
expect(sourceMapHTML.contains("<p data-source-line=\"3\">"), "段落源行号缺失")
expect(sourceMapHTML.contains("<li data-source-line=\"5\">"), "列表项源行号缺失")
expect(sourceMapHTML.contains("<pre data-source-line=\"8\">"), "代码块源行号缺失")
expect(sourceMapHTML.contains("data-source-line-count=\"10\""), "文档总行数锚点缺失")

// GitHub 提示块应从普通引用升级为语义化高亮容器，同时保留正文 Markdown。
let alertHTML = renderer.renderHTML(from: "> [!WARNING]\n> **发布前**请完成检查。")
expect(alertHTML.contains("class=\"moji-alert moji-alert-warning\""), "警告提示块样式缺失")
expect(alertHTML.contains("<strong>发布前</strong>"), "提示块正文格式缺失")
expect(!alertHTML.contains("[!WARNING]"), "提示块标记不应显示在预览中")

// 内容分栏与折叠块使用可读的容器扩展语法，并保留内部块级渲染能力。
let layoutHTML = renderer.renderHTML(from: """
::: columns
::: column
## 左栏
左侧内容
::: column
## 右栏
右侧内容
:::

::: details 查看详情
- 项目一
- 项目二
:::
""")
expect(layoutHTML.contains("class=\"moji-columns\""), "内容分栏容器缺失")
expect(layoutHTML.components(separatedBy: "class=\"moji-column\"").count - 1 == 2, "内容分栏数量错误")
expect(layoutHTML.contains("<details class=\"moji-details\""), "折叠块容器缺失")
expect(layoutHTML.contains("<summary>查看详情</summary>"), "折叠块标题缺失")

// 媒体和业务资源使用围栏元数据生成可点击卡片，危险脚本协议必须被拒绝。
let richContentHTML = renderer.renderHTML(from: """
```attachment
title: 需求说明.pdf
url: ./需求说明.pdf
description: 评审附件
```

```video
title: 演示视频
url: https://example.com/demo.mp4
```

```asset
title: 接口评审
url: javascript:alert(1)
```

```math
E = mc^2
```
""")
expect(richContentHTML.contains("moji-resource-attachment"), "附件卡片缺失")
expect(richContentHTML.contains("<video controls"), "视频控件缺失")
expect(!richContentHTML.contains("href=\"javascript:"), "资源卡片不能接受脚本协议")
expect(richContentHTML.contains("class=\"moji-math\""), "块级数学公式容器缺失")

// 公式中的星号和网址字符不能提前被 Markdown 强调或自动链接规则改写。
let protectedMathHTML = renderer.renderHTML(from: "公式 $a*b*$ 与 $https://example.com$")
expect(protectedMathHTML.contains("$a*b*$"), "公式中的星号被错误解析")
expect(!protectedMathHTML.contains("<em>b</em>"), "公式不能生成 Markdown 斜体标签")
expect(!protectedMathHTML.contains("<a href=\"https://example.com\">"), "公式中的网址不能自动转成链接")

// 连续引用行应合并为一个容器，`>` 空行只负责分隔引用内部段落。
let blockquoteHTML = renderer.renderHTML(from: "> 第一段\n>\n> 第二段")
expect(blockquoteHTML.components(separatedBy: "<blockquote").count - 1 == 1, "多行引用应只生成一个 blockquote")
expect(blockquoteHTML.contains("<p data-source-line=\"1\">第一段</p>"), "引用第一段缺失")
expect(blockquoteHTML.contains("<p data-source-line=\"3\">第二段</p>"), "引用第二段缺失")
expect(!blockquoteHTML.contains("<p>&gt;</p>"), "引用空行不应显示为符号")
let emptyBlockquoteHTML = renderer.renderHTML(from: ">\n>")
expect(emptyBlockquoteHTML.contains("<blockquote data-source-line=\"1\"></blockquote>"), "全空引用应保留空容器")
expect(!emptyBlockquoteHTML.contains("<div class=\"empty-shell\">"), "全空引用不能嵌入文档空状态")

// 使用真实文档头信息验证多段引用，防止分隔行中的引用标记泄漏到预览正文。
let documentDescriptionMarkdown = """
> 文档说明：参照《南京和成都京东 MALL 阶段性报告（截止到 7.24）》，说明七类数据接口及自动导出的整体思路。
>
> 作者：dingyi60(Codex)
>
> 创建时间：2026-08-02
>
> 文档性质：方案思路，不包含代码改动。
"""
let documentDescriptionHTML = renderer.renderHTML(from: documentDescriptionMarkdown)
expect(documentDescriptionHTML.components(separatedBy: "<blockquote").count - 1 == 1, "文档头信息应合并为一个引用块")
expect(!documentDescriptionHTML.contains("<p>&gt;</p>"), "文档头信息的引用分隔行不应显示大于号")
expect(documentDescriptionHTML.contains("<p data-source-line=\"3\">作者：dingyi60(Codex)</p>"), "文档作者信息缺失")

// 不同编辑器可能在 `>` 后写入特殊空白，渲染器应保持兼容。
let whitespaceBlockquoteHTML = renderer.renderHTML(from: ">\t制表符\n>　全角空格\n>\u{00A0}不间断空格")
expect(whitespaceBlockquoteHTML.components(separatedBy: "<blockquote").count - 1 == 1, "特殊空白引用应合并为一个引用块")
expect(!whitespaceBlockquoteHTML.contains("&gt;"), "特殊空白不能导致引用标记泄漏")

// 波浪线围栏需要和反引号围栏一致，保留语言标记并转义代码内容。
let tildeFenceHTML = renderer.renderHTML(from: "~~~swift\nlet value = \"<安全>\"\n~~~")
expect(tildeFenceHTML.contains("<code class=\"language-swift\">"), "波浪线围栏语言标记缺失")
expect(tildeFenceHTML.contains("&lt;安全&gt;"), "代码内容必须进行 HTML 转义")

// 链接目标中的引号必须编码，不能逃逸 href 属性并形成额外 HTML 属性。
let safeLinkHTML = renderer.renderHTML(from: "[链接](https://example.com/\"quoted)")
expect(safeLinkHTML.contains("&quot;quoted"), "链接目标中的引号必须编码")
expect(!safeLinkHTML.contains("href=\"https://example.com/\"quoted"), "链接目标不能打断 href 属性")

print("墨记 Markdown 渲染冒烟测试通过")
